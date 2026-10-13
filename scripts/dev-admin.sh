#!/usr/bin/env bash
set -euo pipefail
FANOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FANOS_PYTHON="${FANOS_ROOT}/apps/api/.venv/bin/python"
if [[ ! -x "$FANOS_PYTHON" ]]; then
  echo "请先按 apps/admin/README.md 安装 API 的 .venv 依赖。"
  exit 1
fi
FANOS_PIDS=()
cleanup() { for pid in "${FANOS_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM
cd "$FANOS_ROOT/apps/api"
export AUTO_SEED="${AUTO_SEED:-false}"
"$FANOS_PYTHON" -m alembic upgrade head
"$FANOS_PYTHON" -m uvicorn app.main:app --host 127.0.0.1 --port 8000 &
FANOS_PIDS+=("$!")
"$FANOS_PYTHON" -m app.modules.admin.catalog_jobs &
FANOS_PIDS+=("$!")
cd "$FANOS_ROOT/apps/admin"
if [[ ! -d node_modules ]]; then npm ci; fi
node node_modules/vite/bin/vite.js --host 127.0.0.1 &
FANOS_PIDS+=("$!")
echo "Fan OS Admin: http://127.0.0.1:5173"
wait
