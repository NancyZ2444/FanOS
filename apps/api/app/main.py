from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
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
from app.modules.admin.public_operations import router as public_operations_router
from app.modules.admin.router import router as admin_router
from app.modules.albums.favorites import router as album_favorites_router
from app.modules.albums.router import router as albums_router
from app.modules.auth.router import router as auth_router
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
    create_schema()
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

for router in (
    auth_router,
    catalog_router,
    tag_router,
    home_router,
    users_router,
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
            "data": {"details": getattr(exc, "details", [])},
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
            "data": {"details": jsonable_encoder(exc.errors())},
        },
    )
