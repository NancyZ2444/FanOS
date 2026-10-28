"""Versioned operator capabilities. Super administrators retain recovery access."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session, object_session

from app.auth_models import AuthState
from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_admin

KEY = "admin-role-permissions"
ROLES = {"admin": "超级管理员", "content_operator": "内容运营", "operation_admin": "运营管理员"}
CAPABILITIES = {
    "catalog.view": "图鉴查看",
    "catalog.edit": "图鉴新增、编辑与导入",
    "catalog.publish": "图鉴审核、发布与状态管理",
    "catalog.delete": "图鉴删除与合并",
    "social.manage": "社交动态管理",
    "sources.manage": "社交数据源管理",
    "daily.manage": "每日翻卡管理",
    "notifications.manage": "消息通知管理",
    "announcements.manage": "公告与首页运营",
    "users.manage": "用户业务管理",
    "comments.manage": "评论管理",
    "reports.manage": "举报与作品审核",
    "albums.manage": "数字相册权益与素材",
    "logs.view": "操作日志查看",
    "auth.users.view": "App 账号查看",
    "auth.users.manage": "App 账号状态管理",
    "auth.users.password": "App 用户密码重置",
    "auth.users.sensitive": "App 账号敏感信息查看",
    "auth.identities.unbind": "第三方身份解绑",
    "auth.whitelist.manage": "登录白名单管理",
    "auth.test_code.manage": "测试验证码配置",
    "auth.support.manage": "登录客服入口管理",
    "auth.admins.manage": "后台管理员管理",
    "roles.manage": "角色权限管理",
}
LOCKED = {"roles.manage", "auth.admins.manage"}
DEPENDENCIES = {
    "auth.users.manage": "auth.users.view",
    "auth.users.password": "auth.users.view",
    "auth.users.sensitive": "auth.users.view",
    "auth.identities.unbind": "auth.users.view",
    "auth.test_code.manage": "auth.whitelist.manage",
}

DEFAULTS = {
    "content_operator": ["catalog.view", "catalog.edit", "social.manage", "sources.manage"],
    "operation_admin": [
        "catalog.view",
        "daily.manage",
        "notifications.manage",
        "announcements.manage",
        "users.manage",
        "comments.manage",
        "reports.manage",
        "auth.users.view",
    ],
}


def effective(actor):
    if actor.role == "admin":
        return list(CAPABILITIES)
    if actor.role not in DEFAULTS:
        return []
    db = object_session(actor)
    state = (
        db.scalar(
            select(AuthState).where(AuthState.id == KEY).execution_options(populate_existing=True)
        )
        if db
        else None
    )
    configured = state.data.get(actor.role) if state else None
    return [
        key
        for key in (configured if isinstance(configured, list) else DEFAULTS[actor.role])
        if key in CAPABILITIES and key not in LOCKED
    ]


def require(actor, capability):
    if capability not in effective(actor):
        raise DomainError("PERMISSION_DENIED", "当前角色没有此操作权限", 403)


def capability(domain, action="view"):
    if domain == "catalog":
        if action == "view":
            return "catalog.view"
        if action in {"delete", "merge"}:
            return "catalog.delete"
        if action in {"publish", "reject", "offline", "archive", "restore"}:
            return "catalog.publish"
        return "catalog.edit"
    if domain in {"logs", "roles"}:
        return f"{domain}.{'view' if domain == 'logs' else 'manage'}"
    return domain if domain.startswith("auth.") else f"{domain}.manage"


def payload(db):
    state = db.get(AuthState, KEY)
    roles = {
        role: list(CAPABILITIES)
        if role == "admin"
        else (state.data.get(role, DEFAULTS[role]) if state else DEFAULTS[role])
        for role in ROLES
    }
    return {
        "version": state.version if state else 0,
        "roles": roles,
        "capabilities": [
            {"key": key, "label": label, "admin_only": key in LOCKED}
            for key, label in CAPABILITIES.items()
        ],
    }


class Matrix(BaseModel):
    version: int = Field(ge=0)
    roles: dict[str, list[str]]


router = APIRouter(prefix="/admin/console/roles", tags=["Role Permissions"])


@router.get("")
def read_roles(actor=Depends(current_admin), db: Session = Depends(get_db)):
    require(actor, "roles.manage")
    return success(payload(db))


@router.put("")
def save_roles(body: Matrix, actor=Depends(current_admin), db: Session = Depends(get_db)):
    require(actor, "roles.manage")
    from app.modules.auth.service import lock

    from .catalog_service import audit

    lock(db)
    before = payload(db)
    if body.version != before["version"]:
        raise DomainError("CONFIG_VERSION_CONFLICT", "权限已被其他管理员更新，请刷新后重试", 409)
    if set(body.roles) != set(ROLES) or set(body.roles["admin"]) != set(CAPABILITIES):
        raise DomainError("INVALID_PERMISSIONS", "请保留所有角色及超级管理员完整权限", 422)
    for role, keys in body.roles.items():
        if (
            len(keys) != len(set(keys))
            or set(keys) - set(CAPABILITIES)
            or (role != "admin" and set(keys) & LOCKED)
        ):
            raise DomainError("INVALID_PERMISSIONS", "存在未知、重复或不可授权的权限", 422)
        if (
            role != "admin"
            and any(key.startswith("catalog.") and key != "catalog.view" for key in keys)
            and "catalog.view" not in keys
        ):
            raise DomainError("INVALID_PERMISSIONS", "图鉴操作权限需要同时开启图鉴查看", 422)
        for key, dependency in DEPENDENCIES.items():
            if key in keys and dependency not in keys:
                raise DomainError(
                    "INVALID_PERMISSIONS",
                    f"{CAPABILITIES[key]}需要同时开启{CAPABILITIES[dependency]}",
                    422,
                )
    state = db.get(AuthState, KEY)
    if not state:
        state = AuthState(id=KEY, kind="admin-role-permissions", version=0)
        db.add(state)
    state.data = {role: sorted(keys) for role, keys in body.roles.items() if role != "admin"}
    state.version += 1
    db.flush()
    audit(db, actor, "system.roles.update", "role_permissions", KEY, before, payload(db))
    db.commit()
    return success(payload(db))
