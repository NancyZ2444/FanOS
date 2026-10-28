"""Server-authoritative material access and per-instance rendering history."""

from copy import deepcopy

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.album_models import AlbumPage, AlbumPreferences, AlbumResource, AlbumReviewRequest
from app.common.response import DomainError
from app.models import CardAlbum, User


def snapshot(resource: dict) -> dict:
    return {key: deepcopy(resource[key]) for key in ("id", "name", "kind", "config")}


def catalog(db: Session) -> dict:
    from .service import resources

    return {r["id"]: r for r in resources(db, include_offline=True)}


def allowed(resource: dict | None, plan: str) -> bool:
    return bool(
        resource
        and resource["status"] == "PUBLISHED"
        and resource.get("membership", "ALL") in {"ALL", plan}
    )


def mark_used(db: Session, resource_id: str) -> None:
    row = db.get(AlbumResource, resource_id)
    if row:
        row.used_once = True


def background_snapshot(background: dict, resources: dict) -> None:
    resource = resources.get(background.get("resource_id"))
    if resource and not background.get("resource_snapshot"):
        background["resource_snapshot"] = snapshot(resource)
        # Canonical saved configuration is immutable after first placement.
        background.update(deepcopy(resource["config"]))


def hydrate_document(doc: dict, resources: dict) -> dict:
    for _, canvas in canvases(doc):
        background_snapshot(canvas.get("background", {}), resources)
        for element in canvas.get("elements", []):
            if element.get("type") == "STICKER" and not element.get("resource_snapshot"):
                resource = resources.get(element.get("content"))
                if resource:
                    element["resource_snapshot"] = snapshot(resource)
    background_snapshot(doc.get("card_view", {}).get("background", {}), resources)
    return doc


def canvases(doc):
    if doc.get("work_mode") != "CARDS":
        yield "cover", doc.get("cover", {})
    for page in doc.get("pages", []):
        yield f"page:{page['id']}", page.get("config", {})


def references(doc: dict):
    for _, canvas in canvases(doc):
        for element in canvas.get("elements", []):
            if element.get("type") == "STICKER":
                yield element.get("content")
        if canvas.get("background", {}).get("resource_id"):
            yield canvas["background"]["resource_id"]
    if doc.get("card_view", {}).get("background", {}).get("resource_id"):
        yield doc["card_view"]["background"]["resource_id"]


def require_resource(resources, resource_id, plan, kinds, scene=None):
    resource = resources.get(resource_id)
    if not allowed(resource, plan) or resource["kind"] not in kinds:
        name = resource["name"] if resource else resource_id
        raise DomainError(
            "ALBUM_RESOURCE_UNAVAILABLE", f"素材“{name}”已下架或需要 PRO 权限，无法新增使用", 422
        )
    if scene and resource.get("scene") != scene:
        raise DomainError("ALBUM_RESOURCE_SCENE", "该素材不适用于当前页面", 422)
    return resource


def validate_materials(db: Session, user: User, previous: dict, doc: dict) -> None:
    from .service import quota

    resources = catalog(db)
    plan = quota(db, user)["plan"]
    hydrate_document(previous, resources)
    old_canvases = dict(canvases(previous))

    def background(value, old, scene):
        resource_id = value.get("resource_id")
        if resource_id:
            if old.get("resource_id") == resource_id and old.get("resource_snapshot"):
                # Position/layout may change, but a client cannot replace historical pixels.
                resource_snapshot = deepcopy(old["resource_snapshot"])
            else:
                resource_snapshot = snapshot(
                    require_resource(resources, resource_id, plan, {"BACKGROUND", "COLOR"}, scene)
                )
            value.clear()
            value.update(deepcopy(resource_snapshot["config"]))
            value.update(resource_id=resource_id, resource_snapshot=resource_snapshot)
            mark_used(db, resource_id)
        else:
            value.pop("resource_snapshot", None)
            if value.get("type") == "IMAGE" or value.get("image_url"):
                raise DomainError(
                    "ALBUM_IMAGE_RESOURCE_REQUIRED", "图片背景须选择已上架的官方素材", 422
                )

    for key, canvas in canvases(doc):
        old = old_canvases.get(key, {})
        scene = "ALBUM_COVER" if key == "cover" else "ALBUM_PAGE"
        background(canvas.get("background", {}), old.get("background", {}), scene)
        old_elements = {e["id"]: e for e in old.get("elements", [])}
        for element in canvas.get("elements", []):
            if element["type"] != "STICKER":
                element.pop("resource_snapshot", None)
                continue
            original = old_elements.get(element["id"], {})
            if original.get("type") == "STICKER" and original.get("content") == element["content"]:
                historical = original.get("resource_snapshot")
                # Missing historical assets stay missing rather than being invented.
                element["resource_snapshot"] = deepcopy(historical)
            else:
                element["resource_snapshot"] = snapshot(
                    require_resource(resources, element["content"], plan, {"STICKER"}, scene)
                )
            mark_used(db, element["content"])
    if doc.get("work_mode") == "CARDS":
        background(
            doc.get("card_view", {}).get("background", {}),
            previous.get("card_view", {}).get("background", {}),
            "CARD_BACKGROUND",
        )


def validate_copy(db: Session, user: User, album: CardAlbum, doc: dict):
    from .service import quota

    if album.is_moderated:
        raise DomainError("ALBUM_MODERATED", "作品限制解除前不能复制，请先申请复核", 403)
    resources, plan = catalog(db), quota(db, user)["plan"]
    blocked = [
        resources[r]["name"] if r in resources else r
        for r in set(references(doc))
        if not allowed(resources.get(r), plan)
    ]
    if blocked:
        error = DomainError(
            "ALBUM_COPY_RESOURCE_UNAVAILABLE",
            "以下素材当前不可用于新作品：" + "、".join(blocked),
            409,
        )
        error.details = blocked
        raise error
    # A copied historical instance is a new use, not a way around scene checks.
    for key, canvas in canvases(doc):
        scene = "ALBUM_COVER" if key == "cover" else "ALBUM_PAGE"
        background = canvas.get("background", {})
        if background.get("resource_id"):
            require_resource(
                resources, background["resource_id"], plan, {"BACKGROUND", "COLOR"}, scene
            )
        for element in canvas.get("elements", []):
            if element.get("type") == "STICKER":
                require_resource(resources, element["content"], plan, {"STICKER"}, scene)
    if doc.get("work_mode") == "CARDS":
        rid = doc.get("card_view", {}).get("background", {}).get("resource_id")
        if rid:
            require_resource(resources, rid, plan, {"BACKGROUND", "COLOR"}, "CARD_BACKGROUND")


def backfill_snapshots(db: Session) -> dict:
    """Run before catalog edits, preserving all old editions and shelf selections."""
    from .service import document

    resources = catalog(db)
    changed, missing = 0, set()
    for album in db.scalars(select(CardAlbum)).all():
        doc = document(db, album)
        missing.update(r for r in references(doc) if r not in resources)
        hydrate_document(doc, resources)
        if album.cover_config != doc["cover"]:
            album.cover_config = doc["cover"]
            changed += 1
        if album.card_view_config != doc["card_view"]:
            album.card_view_config = doc["card_view"]
        for page in doc["pages"]:
            row = db.get(AlbumPage, page["id"])
            if row and row.page_config != page["config"]:
                row.page_config = page["config"]
        if album.published_snapshot:
            published = hydrate_document(deepcopy(album.published_snapshot), resources)
            missing.update(r for r in references(published) if r not in resources)
            album.published_snapshot = published
            for resource_id in references(published):
                mark_used(db, resource_id)
        for resource_id in references(doc):
            mark_used(db, resource_id)
    for review in db.scalars(select(AlbumReviewRequest)).all():
        review.snapshot = hydrate_document(deepcopy(review.snapshot), resources)
    # Existing books on the implicit default shelf need the same historical guarantee.
    for user_id in db.scalars(select(CardAlbum.user_id).distinct()).all():
        if not db.get(AlbumPreferences, user_id) and "cream-white" in resources:
            db.add(
                AlbumPreferences(
                    user_id=user_id,
                    shelf_theme="cream-white",
                    view_mode="SHELF",
                    shelf_snapshot=snapshot(resources["cream-white"]),
                )
            )
    db.flush()
    for preference in db.scalars(select(AlbumPreferences)).all():
        if not preference.shelf_snapshot and preference.shelf_theme in resources:
            preference.shelf_snapshot = snapshot(resources[preference.shelf_theme])
        mark_used(db, preference.shelf_theme)
    return {"updated_albums": changed, "missing_resources": sorted(missing)}
