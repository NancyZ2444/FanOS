"""Create an independent admin. No App account is created, linked or modified."""

import argparse
import getpass
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select

from app.auth_models import AdminPrincipal, AuthState
from app.core.database import SessionLocal, create_schema
from app.core.security import secret_hash
from app.modules.admin.admin_users import password_valid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--account", required=True)
parser.add_argument("--name", required=True)
args = parser.parse_args()
if not re.fullmatch(r"[a-zA-Z0-9_.@-]{3,100}", args.account):
    parser.error("Account must be 3–100 ASCII letters, digits or _.@- characters")
if not args.name.strip() or len(args.name) > 100:
    parser.error("Display name must be 1–100 characters")
password = getpass.getpass("New independent admin password (12+ characters): ")
if password != getpass.getpass("Confirm password: "):
    raise SystemExit("Passwords do not match; no changes made")
password_valid(password)
if len(password) > 256:
    raise SystemExit("Password exceeds the maximum length; no changes made")
create_schema()
with SessionLocal() as db:
    if db.scalar(select(AdminPrincipal.id).where(AdminPrincipal.account == args.account)):
        raise SystemExit("Admin account already exists; use audited reset flow")
    if not db.get(AuthState, "auth-lock"):
        db.add(AuthState(id="auth-lock", kind="lock", data={}))
    row = AdminPrincipal(
        account=args.account,
        display_name=args.name,
        password_hash=secret_hash(password),
        role="admin",
    )
    db.add(row)
    db.commit()
    print("Independent admin created. App users and assets were not modified.")
