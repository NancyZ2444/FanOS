#!/usr/bin/env bash
# Manual rollout. Preserves the existing fanos database, uploads, index and .env.cloud.
set -euo pipefail
project=/home/ubuntu/FanOS-code
bundle=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$project"
test -f .env.cloud || { echo 'STOP: missing .env.cloud'; exit 1; }
docker info >/dev/null
compose=(docker compose -p fanos --env-file .env.cloud -f docker-compose.cloud.yml)
"${compose[@]}" config --quiet
python3 "$bundle/preflight.py"
# No serving container is stopped before all builds succeed.
backup=$(mktemp -d /home/ubuntu/fanos-media-backup.XXXXXX)
echo "Backup directory: $backup"
"${compose[@]}" exec -T postgres pg_dump -U fan_os -d fan_os --format=c > "$backup/database.dump"
test -s "$backup/database.dump"
docker inspect --format '{{.Image}}' fanos-api-1 > "$backup/api-image.txt"
docker inspect --format '{{.Image}}' fanos-admin-1 > "$backup/admin-image.txt"
python3 "$bundle/install_source.py" "$bundle" "$project" "$backup"
"${compose[@]}" config --quiet
"${compose[@]}" build api admin catalog-media-worker catalog-index-worker
"${compose[@]}" run --rm --no-deps --entrypoint python api -c \
  'from app.modules.catalog.media_import import public_image; assert public_image("https://example.org/image.jpg") is None; print("Media import code verified")'
"${compose[@]}" up -d --no-deps api
healthy=false
for attempt in $(seq 1 30); do
  if curl --fail --silent --max-time 3 http://127.0.0.1:8000/health >/dev/null; then
    healthy=true
    break
  fi
  sleep 2
done
$healthy || { echo "STOP: API health check failed. Backups: $backup"; exit 1; }
"${compose[@]}" up -d --no-deps --force-recreate admin
"${compose[@]}" exec -T admin nginx -t
# This only queues jobs; no synchronous remote downloads and no catalog re-publication.
"${compose[@]}" exec -T api python -m app.modules.catalog.media_worker --backfill
"${compose[@]}" up -d --no-deps catalog-media-worker catalog-index-worker
"${compose[@]}" exec -T api python -c '
import json, urllib.request
schema=json.load(urllib.request.urlopen("http://127.0.0.1:8000/openapi.json", timeout=5))
assert "/api/v1/admin/console/media/{kind}/{entity_id}" in schema["paths"]
data=json.load(urllib.request.urlopen("http://127.0.0.1:8000/api/v1/catalog/bootstrap", timeout=5))["data"]
from app.modules.catalog.media_import import owned_image
assert all(not row.get("image_url") or owned_image(row["image_url"]) for rows in data.values() for row in rows)
print("OK: public catalog only serves owned image URLs; pending images use placeholders")
'
curl --fail --silent --max-time 15 http://127.0.0.1:5173/api/v1/catalog/groups -o /dev/null
echo "Done. Historical downloads continue in background. Backup: $backup"
echo 'Inspect download status: Admin > catalog detail > materials > image transfer.'
echo 'Never run docker compose down -v or recreate the project under fanos-code.'
