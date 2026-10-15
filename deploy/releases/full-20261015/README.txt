Fan OS 1.0.14 / 2026101502 deployment procedure

Target: /home/ubuntu/FanOS-code, Docker Compose project fanos.
Keep .env.cloud, PostgreSQL, Redis, uploads and matcher index volumes unchanged.
Use a reviewed, pushed immutable Git commit; never deploy a stale patch ZIP.

1. Run backup.sh on the known host. It preserves PostgreSQL, uploads, matcher
   index, configuration, previous images and an application rollback override.
2. Fast-forward the clean server checkout to the exact reviewed commit.
3. Build api, admin, catalog-index-worker and catalog-media-worker while the old
   containers continue serving. Restore the backup into an isolated database and
   rehearse alembic upgrade head + alembic check with the new API image.
4. Export existing external catalog media with:
   python scripts/catalog_media_transfer.py export
   Download those exact URLs using scripts/prefetch-catalog-media.py on an
   authorized network. No account data or user uploads are sent to the image host.
   Copy the bounded files and manifest to a private server transfer directory.
   Resume a partially completed download using its manifest.json as input.
   --wikimedia-thumbnails uses the same file's official 960px rendition and
   records download_url alongside the original source URL. It does not crop or
   substitute another photo. Standard sizes: https://www.mediawiki.org/wiki/Common_thumbnail_sizes
   Explicit source hosts also include the three Spotify CDNs used by existing
   album covers. HTTPS, public DNS, size limits and no redirects remain required.
5. Apply migrations to the live database, then import verified image files via
   python scripts/catalog_media_transfer.py import /transfer/manifest.json
   (mount the transfer directory read-only into a one-off API container).
   This uses the normal compare-and-set importer; newer operator edits win.
6. Queue historical remaining local images for thumbnail generation with:
   python -m app.modules.catalog.media_worker --backfill
   Start the new api, admin, catalog-index-worker and catalog-media-worker using
   --no-deps. Verify API health, DB revision, nginx, authenticated read-only
   feedback/favorite/search routes, image status and media cache headers.
7. Build Android with USE_MOCK_API=false, ENABLE_IDOL_FEED=false and
   API_BASE_URL=http://106.53.120.249:5173/api/v1.
   Keep the existing Android signing certificate for an in-place upgrade.

Rollback (application only; do not drop new tables or restore DB automatically):
  Stop catalog-media-worker; compose with the saved rollback.compose.json and
  --no-build to restore api/admin/catalog-index-worker images. The migrations are
  additive, and managed image URLs remain compatible with the old API.
  Use -p fanos --env-file .env.cloud -f docker-compose.cloud.yml consistently.
Never run docker compose down -v, seed/demo scripts, or copy a local DB to cloud.

Future external imports still require source-network reachability. The worker
has bounded retries; failed jobs remain visible in the admin material panel.
Upload the original image directly, or repeat the verified offline transfer
when an external host is unreachable. Do not replace a photo with an unrelated
image or expose a workstation proxy publicly.

This remains a side-load test release using the existing test authentication and
HTTP endpoint. Real SMS/OAuth, HTTPS/domain setup and store signing are separate
production-readiness tasks; this release does not weaken or replace auth config.
