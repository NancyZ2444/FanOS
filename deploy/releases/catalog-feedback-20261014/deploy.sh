#!/usr/bin/env bash
# Manual cloud deployment. Never creates a second Compose project or clears volumes.
set -euo pipefail
project=/home/ubuntu/FanOS-code
bundle=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$project"
test -f .env.cloud || { echo 'STOP: .env.cloud is missing'; exit 1; }
docker info >/dev/null
compose=(docker compose -p fanos --env-file .env.cloud -f docker-compose.cloud.yml)
"${compose[@]}" config --quiet
python3 "$bundle/preflight.py"
backup=$(mktemp -d /home/ubuntu/fanos-feedback-backup.XXXXXX)
echo "Backup: $backup"
"${compose[@]}" exec -T postgres pg_dump -U fan_os -d fan_os --format=c > "$backup/database.dump"
test -s "$backup/database.dump"
docker inspect --format '{{.Image}}' fanos-api-1 > "$backup/api-image.txt"
docker inspect --format '{{.Image}}' fanos-admin-1 > "$backup/admin-image.txt"
python3 "$bundle/install_source.py" "$bundle" "$project" "$backup"
"${compose[@]}" config --quiet
"${compose[@]}" build api admin catalog-media-worker catalog-index-worker
# This release adds tables; migration completes before the serving API is replaced.
"${compose[@]}" run --rm --no-deps --entrypoint alembic api upgrade head
"${compose[@]}" up -d --no-deps api
healthy=false
for attempt in $(seq 1 30); do
  if curl --fail --silent --max-time 3 http://127.0.0.1:8000/health >/dev/null; then
    healthy=true
    break
  fi
  sleep 2
done
$healthy || { echo "STOP: API health check failed. Backup: $backup"; exit 1; }
"${compose[@]}" up -d --no-deps --force-recreate admin
"${compose[@]}" exec -T admin nginx -t
"${compose[@]}" up -d --no-deps catalog-media-worker catalog-index-worker
"${compose[@]}" exec -T api python -c '
import json, urllib.request
schema=json.load(urllib.request.urlopen("http://127.0.0.1:8000/openapi.json", timeout=10))
for path in ["/api/v1/feedback", "/api/v1/feedback/objects/{entity_type}/{entity_id}", "/api/v1/admin/console/feedback/{feedback_id}/actions"]:
    assert path in schema["paths"], path
from app.core.database import SessionLocal
from app.modules.feedback.models import Feedback
from sqlalchemy import select
with SessionLocal() as db:
    db.execute(select(Feedback.id).limit(1))
print("OK: feedback API, review workflow and new tables are available")
'
code=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 15 http://127.0.0.1:5173/api/v1/feedback)
test "$code" = 401 || { echo "STOP: public feedback endpoint returned $code, expected 401 (login required)"; exit 1; }
echo "Done. Backup: $backup"
echo 'Refresh the admin page. New modules: 小卡缺失收录 / 图鉴问题纠错.'
echo 'Never run docker compose down -v. The cloud project remains fanos.'
