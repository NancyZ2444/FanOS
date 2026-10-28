"""P0 operations: fresh preview, moderation, material lifecycle and quota impact."""

import hashlib
import io
import json

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.album_models import AlbumResource, AlbumReviewRequest, AlbumSettings
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin, current_user
from app.integrations.storage import get_storage
from app.models import CardAlbum, OperationLog, Report, User
from app.modules.admin.catalog_service import audit, permit

from . import materials, service
from .schemas import AlbumLimits, ModerationPatch, ResourcePatch, ReviewReject, Revision

router = APIRouter(tags=["Digital Album Operations"])


def admin_only(actor):
    from app.modules.admin.permissions import require

    require(actor, "albums.manage")


def admin_read(actor):
    from app.modules.admin.permissions import effective, require

    if "albums.manage" not in effective(actor):
        require(actor, "reports.manage")


def review_payload(review):
    return (
        {
            "id": review.id,
            "revision": review.revision,
            "status": review.status,
            "reason": review.reason,
            "created_at": review.created_at.isoformat(),
        }
        if review
        else None
    )


@router.get("/admin/console/digital-albums/{album_id}")
def admin_detail(
    album_id: str,
    preview: str = Query("default", pattern="^(default|review)$"),
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    admin_read(actor)
    row = db.get(CardAlbum, album_id)
    if not row:
        raise DomainError("ALBUM_NOT_FOUND", "相册不存在", 404)
    review = service.latest_review(db, row.id)
    if preview == "review" and (not review or review.status != "PENDING"):
        raise DomainError("ALBUM_REVIEW_NOT_PENDING", "当前没有待处理的复核申请", 409)
    doc = review.snapshot if preview == "review" else row.published_snapshot
    result = service.payload(db, row, db.get(User, row.user_id), document_override=doc)
    result["preview_version"] = (
        "REVIEW" if preview == "review" else "PUBLISHED" if row.published_snapshot else "EDITING"
    )
    result["review_request"] = review_payload(review)
    result["shelf_snapshot"] = service.preferences(db, db.get(User, row.user_id))["shelf_snapshot"]
    reports = db.scalars(
        select(Report)
        .where(Report.target_type == "digital_album", Report.target_id == row.id)
        .order_by(Report.created_at.desc())
    ).all()
    result["reports"] = [
        {
            "id": report.id,
            "reason": report.reason,
            "status": report.status,
            "reporter_id": report.reporter_id,
            "created_at": report.created_at.isoformat(),
        }
        for report in reports
    ]
    logs = db.scalars(
        select(OperationLog)
        .where(OperationLog.target_type == "digital_albums", OperationLog.target_id == row.id)
        .order_by(OperationLog.created_at.desc())
    ).all()
    result["logs"] = [
        {
            "id": log.id,
            "action": log.action,
            "actor_id": log.actor_id,
            "actor_name": (
                db.get(User, log.actor_id).display_name
                if db.get(User, log.actor_id)
                else log.actor_id
            ),
            "before": log.before,
            "after": log.after,
            "created_at": log.created_at.isoformat(),
        }
        for log in logs
    ]
    return success(result)


@router.post("/albums/{album_id}/review-request")
def request_review(
    album_id: str, data: Revision, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    service.lock_quota(db, user)
    row = service.get_album(db, album_id, user, edit=True)
    if not row.is_moderated:
        raise DomainError("ALBUM_REVIEW_NOT_REQUIRED", "作品当前无需申请复核", 409)
    if row.revision != data.revision:
        raise DomainError("ALBUM_REVISION_CONFLICT", "作品已更新，请重新加载", 409)
    previous = service.latest_review(db, row.id)
    if previous and previous.status == "PENDING":
        if previous.revision == data.revision:
            return success(
                {**service.payload(db, row, user), "review_request": review_payload(previous)}
            )
        raise DomainError("ALBUM_REVIEW_PENDING", "已有待处理的复核申请，请等待运营处理", 409)
    snapshot = materials.hydrate_document(service.document(db, row), materials.catalog(db))
    review = AlbumReviewRequest(album_id=row.id, revision=row.revision, snapshot=snapshot)
    db.add(review)
    audit(db, user, "request_review", "digital_albums", row.id, None, {"revision": row.revision})
    db.commit()
    return success({**service.payload(db, row, user), "review_request": review_payload(review)})


def locked_album(db: Session, album_id: str):
    row = db.get(CardAlbum, album_id)
    if row:
        # Match the author edit/review/publish lock on SQLite and PostgreSQL.
        service.lock_quota(db, db.get(User, row.user_id))
        db.refresh(row)
    return row


def moderate(db: Session, actor: User, album_id: str, data: ModerationPatch):
    permit(actor, "reports", "offline")
    row = locked_album(db, album_id)
    if not row:
        raise DomainError("ALBUM_NOT_FOUND", "相册不存在", 404)
    if row.status == "DELETED":
        raise DomainError("ALBUM_DELETED", "已删除作品不能恢复或变更运营状态", 409)
    status = data.status or ("RESTRICTED" if data.offline else "NORMAL")
    was_moderated = row.is_moderated
    review = service.latest_review(db, row.id)
    if status == "NORMAL" and review and review.status == "PENDING":
        if review.id != data.review_id:
            raise DomainError(
                "ALBUM_REVIEW_CONFIRM_REQUIRED", "请先预览待复核版本并确认对应申请", 409
            )
        review.status = "RESTORED"
    elif data.review_id and (
        not review or review.id != data.review_id or review.status != "PENDING"
    ):
        raise DomainError("ALBUM_REVIEW_CONFLICT", "复核申请已变化，请刷新后重试", 409)
    reports = []
    for report_id in set(data.resolve_report_ids):
        report = db.get(Report, report_id)
        if not report or report.target_type != "digital_album" or report.target_id != album_id:
            raise DomainError("ALBUM_REPORT_MISMATCH", "选择的举报不属于当前作品", 422)
        reports.append(report)
    before = {"status": service.moderation_state(row), "is_moderated": row.is_moderated}
    if status == "NORMAL" and was_moderated:
        row.publication_blocked = True
    row.moderation_status, row.is_moderated = status, status != "NORMAL"
    row.moderation_reason, row.moderation_note = data.reason, data.note
    for report in reports:
        report.status = "resolved"
    after = {**data.model_dump(), "status": status, "is_moderated": row.is_moderated}
    audit(
        db,
        actor,
        {"NORMAL": "restore", "RESTRICTED": "restrict_public", "OFFLINE": "offline"}[status],
        "digital_albums",
        row.id,
        before,
        after,
    )
    db.commit()
    return {
        "is_moderated": row.is_moderated,
        "moderation_status": status,
        "review_status": review.status if review else "NONE",
    }


@router.post("/admin/console/digital-albums/{album_id}/review-reject")
def reject_review(
    album_id: str,
    data: ReviewReject,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "reports", "offline")
    row = locked_album(db, album_id)
    review = service.latest_review(db, album_id)
    if not row or not review or review.id != data.review_id or review.status != "PENDING":
        raise DomainError("ALBUM_REVIEW_CONFLICT", "复核申请已变化，请刷新后重试", 409)
    if not data.reason.strip():
        raise DomainError("REASON_REQUIRED", "请填写驳回原因", 422)
    review.status, review.reason = "REJECTED", data.reason.strip()
    audit(
        db,
        actor,
        "reject_review",
        "digital_albums",
        album_id,
        None,
        {"review_id": review.id, "reason": review.reason},
    )
    db.commit()
    return success(review_payload(review))


def impact(db: Session, data: AlbumLimits):
    before = service.limits(db)
    after = {**before, **data.model_dump(exclude_unset=True)}
    reductions = [
        {"field": key, "before": before[key], "after": value}
        for key, value in after.items()
        if isinstance(value, int) and value < before[key]
    ]
    users, albums = set(), set()
    for user in db.scalars(select(User)).all():
        quota = service.quota(db, user)
        prefix = "pro" if quota["plan"] == "PRO" else "normal"
        if (
            after[f"{prefix}_albums"] < quota["max_album_count"]
            and quota["album_count"] > after[f"{prefix}_albums"]
        ):
            users.add(user.id)
        for row in db.scalars(
            select(CardAlbum).where(CardAlbum.user_id == user.id, CardAlbum.status != "DELETED")
        ):
            doc = service.document(db, row)
            if (
                (
                    doc.get("work_mode") == "CARDS"
                    and after[f"{prefix}_cards"] < before[f"{prefix}_cards"]
                    and len(service.occupied(doc)) > after[f"{prefix}_cards"]
                )
                or (
                    after[f"{prefix}_pages"] < before[f"{prefix}_pages"]
                    and len(doc["pages"]) > after[f"{prefix}_pages"]
                )
                or (
                    after["max_card_per_page"] < before["max_card_per_page"]
                    and any(p["grid_count"] > after["max_card_per_page"] for p in doc["pages"])
                )
            ):
                users.add(user.id)
                albums.add(row.id)
        usage = quota["color_extraction"]
        if any(
            after[f"{prefix}_color_{period}"] < before[f"{prefix}_color_{period}"]
            and usage[f"{period}_used"] > after[f"{prefix}_color_{period}"]
            for period in ("daily", "monthly")
        ):
            users.add(user.id)
    token = hashlib.sha256(
        json.dumps(
            {"before": before, "after": after, "users": sorted(users), "albums": sorted(albums)},
            sort_keys=True,
        ).encode()
    ).hexdigest()
    return {
        "requires_confirmation": bool(reductions),
        "affected_users": len(users),
        "affected_albums": len(albums),
        "reductions": reductions,
        "confirmation_token": token,
    }


@router.post("/admin/console/album-settings/impact")
def settings_impact(
    data: AlbumLimits, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    admin_only(actor)
    return success(impact(db, data))


def save_settings(db: Session, actor: User, data: AlbumLimits, confirm_impact: str):
    admin_only(actor)
    # Missing additive fields preserve existing configuration for older clients.
    before = service.limits(db)
    merged = AlbumLimits.model_validate({**before, **data.model_dump(exclude_unset=True)})
    changes = impact(db, merged)
    if changes["requires_confirmation"] and confirm_impact != changes["confirmation_token"]:
        error = DomainError(
            "ALBUM_LIMIT_IMPACT_CONFIRM_REQUIRED",
            "降低额度需要先预览影响并确认，已有内容不会删除",
            409,
        )
        error.details = changes
        raise error
    row = db.get(AlbumSettings, "global")
    if not row:
        row = AlbumSettings(id="global")
        db.add(row)
    row.config = merged.model_dump()
    audit(db, actor, "configure", "album_settings", "global", before, row.config)
    db.commit()
    return service.limits(db)


def validate_managed_image(url: str, kind: str):
    try:
        raw = get_storage().read_bytes(url)
        with Image.open(io.BytesIO(raw)) as image:
            if image.format not in (
                {"PNG", "WEBP"} if kind == "STICKER" else {"JPEG", "PNG", "WEBP"}
            ):
                raise ValueError()
    except (ValueError, OSError, NotImplementedError) as exc:
        raise DomainError("ALBUM_IMAGE_NOT_MANAGED", "请选择后台上传的素材图片", 422) from exc


def save_resource(db: Session, actor: User, data: ResourcePatch, *, create=False):
    admin_only(actor)
    resources = materials.catalog(db)
    previous = resources.get(data.id)
    if create and previous:
        raise DomainError("ALBUM_RESOURCE_EXISTS", "素材 ID 已存在，请更换 ID", 409)
    if previous and previous["kind"] != data.kind:
        raise DomainError("ALBUM_RESOURCE_KIND_IMMUTABLE", "已有素材不能变更类型，请新建素材", 409)
    if previous and previous["scene"] != data.scene:
        raise DomainError(
            "ALBUM_RESOURCE_SCENE_IMMUTABLE", "素材场景创建后不可更换，请在目标场景新建条目", 409
        )
    if previous and previous.get("published_once") and data.status == "DRAFT":
        raise DomainError(
            "ALBUM_RESOURCE_WAS_PUBLISHED", "上架过的素材不能退回草稿，请使用下架", 409
        )
    image = data.config.get("image_url")
    if image and image != (previous or {}).get("config", {}).get("image_url"):
        validate_managed_image(image, data.kind)
    materials.backfill_snapshots(db)
    row = db.get(AlbumResource, data.id)
    if not row:
        row = AlbumResource(id=data.id, published_once=bool(previous), used_once=bool(previous))
        db.add(row)
    for key, value in data.model_dump().items():
        setattr(row, key, value)
    row.published_once = row.published_once or data.status == "PUBLISHED"
    db.flush()
    audit(
        db,
        actor,
        "create" if create else "configure",
        "album_resources",
        row.id,
        previous,
        service.resource_payload(row),
    )
    db.commit()
    return service.resource_payload(row)


@router.post("/admin/console/album-resources")
def create_resource(
    data: ResourcePatch, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    return success(save_resource(db, actor, data, create=True))


MATERIAL_SCENES = {"SHELF", "ALBUM_COVER", "ALBUM_PAGE", "CARD_BACKGROUND"}


def require_scene(scene, data=None, resource=None):
    if scene not in MATERIAL_SCENES:
        raise DomainError("ALBUM_RESOURCE_SCENE", "素材场景不存在", 404)
    if (data and data.scene != scene) or (resource and resource["scene"] != scene):
        raise DomainError("ALBUM_RESOURCE_SCENE", "不能从此入口操作其他场景素材", 422)


@router.get("/admin/console/album-materials/{scene}")
def scene_resources(
    scene: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    admin_read(actor)
    require_scene(scene)
    return success(
        {"items": [r for r in service.resources(db, include_offline=True) if r["scene"] == scene]}
    )


@router.post("/admin/console/album-materials/{scene}")
def create_scene_resource(
    scene: str,
    data: ResourcePatch,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    require_scene(scene, data)
    return success(save_resource(db, actor, data, create=True))


@router.put("/admin/console/album-materials/{scene}/{resource_id}")
def update_scene_resource(
    scene: str,
    resource_id: str,
    data: ResourcePatch,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    require_scene(scene, data, materials.catalog(db).get(resource_id))
    if resource_id != data.id:
        raise DomainError("INVALID_RESOURCE_ID", "素材 ID 不一致", 422)
    return success(save_resource(db, actor, data))


@router.delete("/admin/console/album-materials/{scene}/{resource_id}")
def delete_scene_resource(
    scene: str,
    resource_id: str,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
):
    require_scene(scene, resource=materials.catalog(db).get(resource_id))
    return delete_resource(resource_id, actor, db)


@router.delete("/admin/console/album-resources/{resource_id}")
def delete_resource(
    resource_id: str, actor: User = Depends(current_admin), db: Session = Depends(get_db)
):
    admin_only(actor)
    materials.backfill_snapshots(db)
    row = db.get(AlbumResource, resource_id)
    if not row:
        raise DomainError("ALBUM_RESOURCE_NOT_FOUND", "素材不存在或为内置素材", 404)
    if row.status != "DRAFT" or row.published_once or row.used_once:
        raise DomainError(
            "ALBUM_RESOURCE_DELETE_BLOCKED",
            "仅允许删除从未上架、从未使用的草稿；历史素材请下架",
            409,
        )
    audit(db, actor, "delete", "album_resources", row.id, service.resource_payload(row), None)
    db.delete(row)
    db.commit()
    return success({"deleted": True})


@router.post("/admin/console/album-resources/upload")
async def upload_resource(
    file: UploadFile = File(...), kind: str = Form(...), actor: User = Depends(current_admin)
):
    admin_only(actor)
    if kind not in {"SHELF", "BACKGROUND", "STICKER"}:
        raise DomainError("ALBUM_RESOURCE_KIND", "该素材类型不支持图片", 422)
    raw = await file.read(10 * 1024 * 1024 + 1)
    if len(raw) > 10 * 1024 * 1024:
        raise DomainError("FILE_TOO_LARGE", "图片不能超过 10 MB", 413)
    try:
        image = Image.open(io.BytesIO(raw))
        formats = {"PNG", "WEBP"} if kind == "STICKER" else {"JPEG", "PNG", "WEBP"}
        if image.format not in formats or image.width * image.height > 40_000_000:
            raise ValueError()
        image.load()
        image = ImageOps.exif_transpose(image).convert("RGBA")
        image.thumbnail((3000, 3000))
        output = io.BytesIO()
        image.save(output, "WEBP", quality=92)
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise DomainError(
            "INVALID_IMAGE", "贴纸支持 PNG/WebP；背景和书架支持 JPG/PNG/WebP", 422
        ) from exc
    url = get_storage().save_bytes(output.getvalue(), "material.webp", "album-materials")
    return success({"url": url, "width": image.width, "height": image.height})
