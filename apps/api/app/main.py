from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.common.response import DomainError, success
from app.core.config import get_settings
from app.core.database import SessionLocal, create_schema
from app.modules.admin.admin_users import router as admin_users_router
from app.modules.admin.catalog_extensions import contribution_router
from app.modules.admin.catalog_extensions import router as catalog_extensions_router
from app.modules.admin.console_router import router as console_router
from app.modules.admin.media_router import router as media_router
from app.modules.admin.operations import router as operations_router
from app.modules.admin.permissions import router as role_permissions_router
from app.modules.admin.public_operations import router as public_operations_router
from app.modules.admin.router import router as admin_router
from app.modules.albums.color_extraction import router as album_colors_router
from app.modules.albums.favorites import router as album_favorites_router
from app.modules.albums.operations import router as album_operations_router
from app.modules.albums.router import router as albums_router
from app.modules.auth.admin_api import router as auth_admin_router
from app.modules.auth.router import router as auth_router
from app.modules.catalog.profiles import router as profiles_router
from app.modules.catalog.router import router as catalog_router
from app.modules.catalog.tag_router import router as tag_router
from app.modules.collections.router import router as collections_router
from app.modules.daily_cards.router import router as daily_cards_router
from app.modules.feedback.router import (
    admin_router as feedback_admin_router,
)
from app.modules.feedback.router import (
    router as feedback_router,
)
from app.modules.home.router import router as home_router
from app.modules.notifications.router import router as notifications_router
from app.modules.scan.router import router as scan_router
from app.modules.social_feed.router import router as social_feed_router
from app.modules.users.router import router as users_router
from app.seed import seed_database


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()

    class SafeAccessLog(logging.Filter):
        def filter(self, record):
            if isinstance(record.args, tuple) and len(record.args) == 5:
                args = list(record.args)
                args[2] = str(args[2]).split("?", 1)[0]
                record.args = tuple(args)
            return True

    logging.getLogger("uvicorn.access").addFilter(SafeAccessLog())
    create_schema()
    from app.auth_models import AuthState

    with SessionLocal() as db:
        for key, kind in (
            ("auth-lock", "lock"),
            ("test-code:" + settings.environment, "test-config"),
            ("support", "support"),
        ):
            if db.get(AuthState, key) is None:
                db.add(AuthState(id=key, kind=kind, data={}))
        db.commit()
    if settings.auto_seed:
        with SessionLocal() as db:
            seed_database(db)
    yield


settings = get_settings()
app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description=(
        "Fan OS Phase 1 user, catalog, AI Scan, collection, social feed, and operations API."
    ),
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/media", StaticFiles(directory=settings.local_media_root), name="media")


@app.middleware("http")
async def request_identity(request: Request, call_next):
    from app.modules.auth.service import audit_context

    request.state.request_id = uuid4().hex
    ip = request.client.host if request.client else ""
    ip_masked = ".".join(ip.split(".")[:2]) + ".*.*" if "." in ip else ip.split(":")[0] + ":…"
    marker = audit_context.set(
        {
            "request_id": request.state.request_id,
            "ip_masked": ip_masked,
            "device_summary": request.headers.get("User-Agent", "")[:160],
        }
    )
    try:
        response = await call_next(request)
    finally:
        audit_context.reset(marker)
    response.headers["X-Request-ID"] = request.state.request_id
    return response


for router in (
    role_permissions_router,
    auth_router,
    auth_admin_router,
    profiles_router,
    catalog_router,
    tag_router,
    home_router,
    users_router,
    album_operations_router,
    album_colors_router,
    albums_router,
    album_favorites_router,
    collections_router,
    daily_cards_router,
    scan_router,
    social_feed_router,
    notifications_router,
    admin_router,
    media_router,
    console_router,
    catalog_extensions_router,
    contribution_router,
    feedback_router,
    feedback_admin_router,
    admin_users_router,
    operations_router,
    public_operations_router,
):
    app.include_router(router, prefix=settings.api_v1_prefix)


@app.get("/health")
def health() -> dict:
    return success({"status": "ok", "environment": settings.environment})


@app.exception_handler(DomainError)
async def domain_error_handler(request: Request, exc: DomainError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "code": 1,
            "error_code": exc.error_code,
            "message": exc.message,
            "data": {
                "details": getattr(exc, "details", []),
                **getattr(exc, "public_data", {}),
                "request_id": getattr(request.state, "request_id", ""),
            },
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "code": 1,
            "error_code": "VALIDATION_ERROR",
            "message": "请求参数不正确",
            "data": {
                "details": [
                    {"loc": item["loc"], "type": item["type"], "msg": item["msg"]}
                    for item in exc.errors()
                ],
                "request_id": getattr(request.state, "request_id", ""),
            },
        },
    )
