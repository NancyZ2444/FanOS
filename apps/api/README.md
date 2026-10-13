# Fan OS API

FastAPI + SQLAlchemy 2 modular monolith for the current Flutter Phase 1 scope.

## Local run without Docker

```bash
cd apps/api
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev,ai]'
# Without .env the API uses local SQLite for an infrastructure-free smoke run.
# Copy .env.example only when PostgreSQL is available.
alembic upgrade head
python -m app.seed_cli
uvicorn app.main:app --reload
```

OpenAPI UI: `http://localhost:8000/docs`. Health: `http://localhost:8000/health`.
Development phone login uses `13800000000` / `123456`. Admin login uses
`13900000000` / `123456`.

## Full stack

From the repository root:

```bash
docker compose up --build
```

This starts PostgreSQL 16, Redis 7, MinIO, API, and the crawler Worker. Third-party
platform providers stay in authorized Mock mode until credentials are configured.

## AI Scan

The current engine verifies printed card artwork using OpenCV SIFT + RANSAC
(`sift-homography-v1`), included in base dependencies. It detects up to 10 separate
card regions and matches each independently. API mode never fabricates matches:
an empty or legacy index returns `503 SCAN_INDEX_UNAVAILABLE`; unmatched crops
return an unrecognized result. Upload limits are 15 MB / 24 megapixels.

The supplied ONNX/person-feature engine remains untouched under
`app/integrations/card_matcher/vendor` for future evaluation. Its optional model
configuration is not required for current artwork matching.

To activate scanning:

1. Run `alembic upgrade head`, start a reachable API and log in from the App.
2. Upload authorized, clear card-front images in Admin or place them under
   `../../assets/import/cards/<card-id>/front.jpg` and run
   `python scripts/import_card_assets.py`.
3. For photos already in the database, run
   `python scripts/import_card_assets.py --rebuild-existing` once after upgrading.
4. Run `python -m app.modules.admin.catalog_jobs` for subsequent upload indexing.
   The root `scripts/dev-admin.sh` already starts this worker.
5. Publish the card and check `GET /api/v1/scan/status`: `available=true` and
   `indexed_card_count>0` indicate that at least one current published image is indexed.

`production_ready=false` distinguishes a functioning local feature from a
production-validated recognizer. Similarity is not a measured accuracy percentage.
Only indexed artwork is recognizable; no downloaded model can replace the card
reference library. Glare, overlap, similar editions and large libraries still need
field evaluation. See [details and tests](../../docs/AI_SCAN_VERIFICATION.md).

Confirmations are transactional and idempotent per detected region. Replaying the
same confirmation does not increment Owned again; two physical copies detected
in one photo increment twice. History includes remote crops and `owned_added`.
Feedback uses server-persisted image/candidate/user context, not client claims.

Album artwork independently supports optional front and back images. See
`../../assets/import/albums/README.md` and run `python scripts/import_album_assets.py`.

## Phase 2/3 reserved boundaries

Migration `a8e42c19f5d0` adds inactive Community, Outbox, notification-inbox, device-token,
moderation, and user-block tables. No Community or Chat router is registered in Phase 1.
Realtime Chat intentionally remains a shared contract under `app/modules/chat_contract` and
will be implemented as a separate service. See
`../../docs/architecture/PHASE2_PHASE3_EVOLUTION.md` before enabling either domain.

## Verification

```bash
ruff format --check app tests scripts migrations \
  --exclude app/integrations/card_matcher/vendor
ruff check app tests scripts migrations \
  --exclude app/integrations/card_matcher/vendor
pytest
alembic check
```

The copied vendor source is intentionally excluded from project formatting so future
upstream comparisons remain reliable. See `app/integrations/card_matcher/PROVENANCE.md`.
