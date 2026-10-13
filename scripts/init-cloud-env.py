"""Create fresh credentials for restricted cloud testing; never overwrite them."""
from pathlib import Path
import os
import secrets

target = Path(__file__).resolve().parents[1] / ".env.cloud"
if target.exists():
    raise SystemExit(".env.cloud already exists; preserved existing credentials")
values = {
    "POSTGRES_PASSWORD": secrets.token_hex(24),
    "JWT_SECRET": secrets.token_hex(32),
    "WORKER_TOKEN": secrets.token_hex(32),
    "DEV_PHONE_CODE": "666666",
    "PUBLIC_MEDIA_BASE_URL": "http://localhost:5173/media",
}
with open(target, "x", opener=lambda path, flags: os.open(path, flags, 0o600)) as handle:
    handle.write("\n".join(f"{key}={value}" for key, value in values.items()) + "\n")
print("Created .env.cloud. Keep it private. Login code:", values["DEV_PHONE_CODE"])
