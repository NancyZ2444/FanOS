"""Package complete backend/admin source dependencies without secrets or runtime data."""
import hashlib
import json
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
paths = []
for folder in ("apps/api/app", "apps/api/migrations", "apps/admin/src", "apps/admin/public"):
    paths.extend(p for p in (root / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc")
for folder in ("apps/admin",):
    paths.extend(p for p in (root / folder).iterdir() if p.is_file() and p.suffix in {".json", ".ts", ".js", ".html"} and not p.name.startswith(".env"))
for name in ("apps/api/pyproject.toml", "apps/api/alembic.ini", "deploy/docker/api.Dockerfile", "deploy/docker/admin.Dockerfile", "deploy/nginx/cloud-admin.conf", "deploy/nginx/admin.conf", "docker-compose.cloud.yml", ".dockerignore"):
    paths.append(root / name)
destination = root / "output/releases/FanOS-Cloud-Feedback-20261014.zip"
destination.parent.mkdir(parents=True, exist_ok=True)
manifest = {}
with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(set(paths)):
        name = path.relative_to(root).as_posix()
        if path.name.startswith(".env") or path.name.endswith(".tsbuildinfo"):
            continue
        content = path.read_bytes()
        manifest[name] = hashlib.sha256(content).hexdigest()
        archive.writestr("source/" + name, content)
    archive.writestr("manifest.json", json.dumps(manifest, indent=2))
    for name in ("deploy.sh", "README.txt"):
        archive.write(root / "deploy/releases/catalog-feedback-20261014" / name, name)
    for name in ("preflight.py", "install_source.py"):
        archive.write(root / "deploy/releases/catalog-media-20261014" / name, name)
print(f"{destination}\n{len(manifest)} source files, {destination.stat().st_size} bytes")
