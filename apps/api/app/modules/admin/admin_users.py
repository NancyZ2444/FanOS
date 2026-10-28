from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.auth_models import AdminPrincipal
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin, secret_hash
from app.modules.auth import service as s
from app.modules.auth.admin_api import permit, reason_check, sql_page, version_check

router = APIRouter(prefix="/admin/console/admins", tags=["Admin Users"])


def public_admin(row):
    return {
        "id": row.id,
        "account": row.account,
        "name": row.display_name,
        "role": row.role,
        "is_active": row.is_active,
        "version": row.version,
        "created_at": row.created_at,
        "last_login_at": row.last_login_at,
    }


def password_valid(value):
    if (
        len(value) < 12
        or not any(c.isalpha() for c in value)
        or not any(c.isdigit() for c in value)
    ):
        raise DomainError("WEAK_PASSWORD", "后台密码至少 12 位，并包含字母及数字")
    return value


class AdminUserDraft(BaseModel):
    account: str = Field(min_length=3, max_length=100, pattern=r"^[a-zA-Z0-9_.@-]+$")
    password: str = Field(max_length=256)
    name: str = Field(min_length=1, max_length=100)
    role: Literal["admin", "content_operator", "operation_admin"]
    is_active: bool = True
    reason: str = Field(min_length=1, max_length=1000)


@router.get("")
def list_admins(
    q: str = "",
    role: str = "",
    status: str = "",
    page: int = 1,
    page_size: int = 20,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.admins.manage")
    query = select(AdminPrincipal).order_by(AdminPrincipal.created_at.desc())
    if q:
        query = query.where(
            or_(AdminPrincipal.account.contains(q), AdminPrincipal.display_name.contains(q))
        )
    if role:
        query = query.where(AdminPrincipal.role == role)
    if status:
        query = query.where(AdminPrincipal.is_active == (status in {"active", "enabled"}))
    return success(sql_page(db, query, page, page_size, public_admin))


@router.post("")
def add_admin(payload: AdminUserDraft, actor=Depends(current_admin), db: Session = Depends(get_db)):
    permit(actor, "auth.admins.manage")
    reason_check(payload.reason)
    s.lock(db)
    if db.scalar(select(AdminPrincipal).where(AdminPrincipal.account == payload.account)):
        raise DomainError("ACCOUNT_EXISTS", "后台登录账号已存在", 409)
    row = AdminPrincipal(
        account=payload.account,
        password_hash=secret_hash(password_valid(payload.password)),
        display_name=payload.name,
        role=payload.role,
        is_active=payload.is_active,
    )
    db.add(row)
    db.flush()
    s.audit(db, "admin.create", actor, reason=payload.reason, admin_id=row.id, role=row.role)
    db.commit()
    return success(public_admin(row))


class AdminAccessPatch(BaseModel):
    role: Literal["admin", "content_operator", "operation_admin"]
    is_active: bool
    name: str | None = Field(default=None, min_length=1, max_length=100)
    expected_version: int
    reason: str


@router.patch("/{user_id}")
def update_admin(
    user_id: str,
    payload: AdminAccessPatch,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.admins.manage")
    reason_check(payload.reason)
    s.lock(db)
    row = db.get(AdminPrincipal, user_id)
    if not row:
        raise DomainError("NOT_FOUND", "后台账号不存在", 404)
    version_check(row, payload.expected_version)
    demoting = not payload.is_active or payload.role != "admin"
    if row.id == actor.id and demoting:
        raise DomainError("PROTECTED_ACCOUNT", "不能停用自己或移除自己的超级管理员权限", 422)
    if (
        row.is_active
        and row.role == "admin"
        and demoting
        and db.scalar(
            select(func.count())
            .select_from(AdminPrincipal)
            .where(AdminPrincipal.is_active.is_(True), AdminPrincipal.role == "admin")
        )
        <= 1
    ):
        raise DomainError("LAST_ADMIN", "不能停用最后一个有效超级管理员", 422)
    row.role, row.is_active = payload.role, payload.is_active
    if payload.name:
        row.display_name = payload.name
    row.version += 1
    s.revoke(db, row.id, "admin")
    s.audit(
        db,
        "admin.access.update",
        actor,
        reason=payload.reason,
        admin_id=row.id,
        role=row.role,
        is_active=row.is_active,
    )
    db.commit()
    return success(public_admin(row))


class ResetPassword(BaseModel):
    password: str = Field(max_length=256)
    reason: str
    expected_version: int


@router.post("/{user_id}/reset-password")
def reset_password(
    user_id: str,
    payload: ResetPassword,
    actor=Depends(current_admin),
    db: Session = Depends(get_db),
):
    permit(actor, "auth.admins.manage")
    reason_check(payload.reason)
    s.lock(db)
    row = db.get(AdminPrincipal, user_id)
    if not row:
        raise DomainError("NOT_FOUND", "后台账号不存在", 404)
    version_check(row, payload.expected_version)
    row.password_hash = secret_hash(password_valid(payload.password))
    row.version += 1
    s.revoke(db, row.id, "admin")
    s.audit(db, "admin.password.reset", actor, admin_id=row.id, reason=payload.reason)
    db.commit()
    return success(public_admin(row))
