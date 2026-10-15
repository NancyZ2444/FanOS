"""Create the manual cloud source bundle, with no secrets, database or uploaded images."""
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
files = subprocess.check_output([
    "git", "ls-files", "apps/api/app", "apps/api/migrations", "apps/admin",
], cwd=root, text=True).splitlines()
files += [
    "apps/api/app/modules/admin/media_router.py", "apps/api/app/modules/catalog/media_import.py",
    "apps/api/app/modules/catalog/media_worker.py", "apps/admin/src/components/MediaIngestionStatus.tsx",
    "apps/api/pyproject.toml", "apps/api/alembic.ini", "apps/admin/package.json",
    "apps/admin/package-lock.json", "apps/admin/index.html", "apps/admin/tsconfig.json",
    "apps/admin/vite.config.ts",
    "deploy/docker/api.Dockerfile", "deploy/docker/admin.Dockerfile", ".dockerignore",
    "deploy/nginx/cloud-admin.conf", "deploy/nginx/admin.conf", "docker-compose.cloud.yml",
]
output = root / "output/releases/FanOS-Cloud-Media-20261014.zip"
manifest = {}
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as bundle:
    for name in sorted(set(files)):
        if ".env" in Path(name).name:
            continue
        content = (root / name).read_bytes()
        manifest[name] = hashlib.sha256(content).hexdigest()
        bundle.writestr("source/" + name, content)
    bundle.writestr("manifest.json", json.dumps(manifest, indent=2))
    for path in (root / "deploy/releases/catalog-media-20261014").iterdir():
        if path.is_file():
            bundle.write(path, path.name)
print(output)
print(f"{len(manifest)} files, {output.stat().st_size} bytes. No environment secrets included.")
