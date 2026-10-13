from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin
from app.models import User, new_id
from app.modules.admin.catalog_service import audit

router = APIRouter(prefix="/admin/console/admins", tags=["Admin Users"])


class AdminUserDraft(BaseModel):
    phone: str = Field(pattern=r"^1\d{10}$")
    name: str = Field(min_length=1, max_length=40)
    role: Literal["admin", "content_operator", "operation_admin"]
    is_active: bool = True


def require_super(actor: User):
    if actor.role != "admin":
        raise DomainError("PERMISSION_DENIED", "仅超级管理员可管理后台账号", 403)


def public_admin(row: User) -> dict:
    return {
        "id": row.id,
        "name": row.display_name,
        "role": row.role,
        "phone": row.phone[:3] + "****" + row.phone[-4:] if row.phone else "",
        "is_active": row.is_active,
        "created_at": row.created_at.isoformat(),
    }


@router.get("")
def list_admins(actor: User = Depends(current_admin), db: Session = Depends(get_db)) -> dict:
    require_super(actor)
    rows = db.scalars(
        select(User).where(User.role.in_(["admin", "content_operator", "operation_admin"]))
    )
    return success({"items": [public_admin(row) for row in rows]})


@router.post("")
def add_admin(
    payload: AdminUserDraft, actor: User = Depends(current_admin), db: Session = Depends(get_db)
) -> dict:
    require_super(actor)
    existing = db.scalar(select(User).where(User.phone == payload.phone))
    if existing:
        raise DomainError("ACCOUNT_EXISTS", "该手机号已有账号，请勿重复创建或隐式升级其权限", 409)
    row = User(
        id=new_id("admin"),
        phone=payload.phone,
        display_name=payload.name,
        role=payload.role,
        is_active=payload.is_active,
    )
    db.add(row)
    db.flush()
    result = public_admin(row)
    audit(db, actor, "admin.create", "admin", row.id, None, result)
    db.commit()
    return success(result)


class AdminAccessPatch(BaseModel):
    role: Literal["admin", "content_operator", "operation_admin"]
    is_active: bool


@router.patch("/{user_id}")
def update_admin(
    user_id: str,
    payload: AdminAccessPatch,
    actor: User = Depends(current_admin),
    db: Session = Depends(get_db),
) -> dict:
    require_super(actor)
    row = db.get(User, user_id)
    if not row or row.role not in {"admin", "content_operator", "operation_admin"}:
        raise DomainError("NOT_FOUND", "后台账号不存在", 404)
    if row.id == actor.id and (not payload.is_active or payload.role != "admin"):
        raise DomainError("PROTECTED_ACCOUNT", "不能停用自己或移除自己的超级管理员权限", 422)
    before = public_admin(row)
    row.role = payload.role
    row.is_active = payload.is_active
    audit(db, actor, "admin.access.update", "admin", row.id, before, public_admin(row))
    db.commit()
    return success(public_admin(row))
