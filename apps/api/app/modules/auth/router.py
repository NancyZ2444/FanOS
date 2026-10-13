from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.core.config import get_settings
from app.core.database import get_db
from app.modules.auth import service
from app.modules.auth.schemas import LoginRequest, RefreshRequest

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/request-code")
def request_code() -> dict:
    settings = get_settings()
    if settings.is_production:
        raise DomainError("AUTH_PROVIDER_NOT_CONFIGURED", "生产环境需配置真实身份验证服务", 503)
    return success({"retry_after": 60}, f"测试验证码：{settings.dev_phone_code}")


@router.post("/login")
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> dict:
    return success(service.login(db, payload.method, payload.phone, payload.code))


@router.post("/refresh")
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)) -> dict:
    return success(service.refresh(db, payload.refresh_token))


@router.post("/logout")
def logout() -> dict:
    return success(message="已退出登录")
