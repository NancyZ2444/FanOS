"""Isolated auth acceptance server: never uses the developer's business database."""
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "api"))
if "/.test-data/auth-" not in os.environ.get("DATABASE_URL", ""):
    raise SystemExit("Auth acceptance requires a new isolated test database")
from app.auth_models import AdminPrincipal, AuthState
from app.core.database import SessionLocal, create_schema
from app.core.security import secret_hash

create_schema()
with SessionLocal() as db:
    db.add(AuthState(id="auth-lock", kind="lock", data={}))
    db.add(AdminPrincipal(account="auth-e2e-admin", display_name="认证验收管理员", role="admin", password_hash=secret_hash(os.environ["AUTH_E2E_PASSWORD"])))
    db.commit()
import uvicorn
uvicorn.run("app.main:app", host="127.0.0.1", port=8016, access_log=False)
