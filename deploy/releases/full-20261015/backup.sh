#!/usr/bin/env bash
# Run as ubuntu on the known cloud host. No service is stopped or data deleted.
set -euo pipefail
umask 077
cd /home/ubuntu/FanOS-code
test -f .env.cloud
test -z "$(git status --porcelain)" || { echo 'STOP: server checkout is dirty'; exit 1; }
sudo -n python3 - <<'PY'
import json, subprocess
config = json.loads(subprocess.check_output(['docker', 'compose', '-p', 'fanos', '--env-file', '.env.cloud', '-f', 'docker-compose.cloud.yml', 'config', '--format', 'json']))
assert config['services']['api']['environment']['PUBLIC_MEDIA_BASE_URL'] == 'http://106.53.120.249:5173/media'
for service, target, expected in [('postgres', '/var/lib/postgresql/data', 'fanos_fan_os_postgres'), ('api', '/srv/api/data/uploads', 'fanos_fan_os_uploads')]:
    info = json.loads(subprocess.check_output(['docker', 'inspect', 'fanos-' + service + '-1']))[0]
    assert info['Config']['Labels']['com.docker.compose.project'] == 'fanos'
    assert next(m['Name'] for m in info['Mounts'] if m['Destination'] == target) == expected
print('Existing fanos project, database and upload volumes verified')
PY
fanos_backup=$(mktemp -d /home/ubuntu/FanOS-backups/full-20261015.XXXXXX)
git rev-parse HEAD > "$fanos_backup/previous-commit.txt"
cp .env.cloud "$fanos_backup/env.cloud"
cp deploy/nginx/cloud-admin.conf "$fanos_backup/nginx.conf"
sha256sum .env.cloud > "$fanos_backup/env.sha256"
sudo -n docker inspect fanos-api-1 fanos-admin-1 fanos-catalog-index-worker-1 > "$fanos_backup/containers.json"
sudo -n docker exec fanos-postgres-1 pg_dump -U fan_os -d fan_os --format=c > "$fanos_backup/database.dump"
test -s "$fanos_backup/database.dump"
sudo -n docker exec -i fanos-postgres-1 pg_restore --list < "$fanos_backup/database.dump" > "$fanos_backup/database-archive-list.txt"
for volume in fanos_fan_os_uploads fanos_fan_os_matcher_index; do
  mount=$(sudo -n docker volume inspect --format '{{.Mountpoint}}' "$volume")
  test "$mount" = "/var/lib/docker/volumes/$volume/_data"
  sudo -n tar -C "$mount" -czf - . > "$fanos_backup/$volume.tar.gz"
  gzip -t "$fanos_backup/$volume.tar.gz"
  sudo -n find "$mount" -type f -exec sha256sum '{}' + > "$fanos_backup/$volume.sha256"
done
sudo -n docker exec -i fanos-api-1 python - > "$fanos_backup/table-counts.json" <<'PY'
import json
from sqlalchemy import inspect, text
from app.core.database import engine
with engine.connect() as db:
    print(json.dumps({t: db.scalar(text('SELECT count(*) FROM "' + t + '"')) for t in inspect(engine).get_table_names()}, sort_keys=True))
PY
python3 - "$fanos_backup" <<'PY'
import json, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
services = {}
for container in json.loads((root / 'containers.json').read_text()):
    service = container['Config']['Labels']['com.docker.compose.service']
    tag = 'fanos-' + service + ':before-' + root.name.lower()
    subprocess.run(['sudo', '-n', 'docker', 'tag', container['Image'], tag], check=True)
    services[service] = {'image': tag}
services['admin']['volumes'] = [str(root / 'nginx.conf') + ':/etc/nginx/conf.d/default.conf:ro']
(root / 'rollback.compose.json').write_text(json.dumps({'services': services}, indent=2))
PY
(cd "$fanos_backup" && sha256sum database.dump *.tar.gz > backup.sha256)
echo "BACKUP=$fanos_backup"
