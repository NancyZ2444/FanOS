from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.common.response import success
from app.core.database import get_db
from app.modules.auth import service
from app.modules.auth.schemas import LoginRequest, RefreshRequest

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/request-code")
def request_code() -> dict:
    return success({"retry_after": 60}, "验证码已发送；开发环境请使用 123456")


@router.post("/login")
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> dict:
    return success(service.login(db, payload.method, payload.phone, payload.code))


@router.post("/refresh")
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)) -> dict:
    return success(service.refresh(db, payload.refresh_token))


@router.post("/logout")
def logout() -> dict:
    return success(message="已退出登录")
