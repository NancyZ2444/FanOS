# card-matcher integration

`vendor/card_matcher` remains an isolated, unmodified copy of the supplied
`functional tool/card-matcher` project. Optional model weights under `vendor/models`
are kept outside Git until their redistribution licenses are verified.
Those person/pose/expression embeddings (especially their Mock mode) do not prove
which printed card edition was photographed. They are **not** the scan matching
engine as of 2026-10-08.

`adapter.py` detects up to 10 non-overlapping card-shaped regions, corrects their
perspective and independently matches each crop. `visual.py` uses real OpenCV SIFT
artwork features with RANSAC homography verification (`sift-homography-v1`). A
reference photo is cropped before indexing, so tabletop background is not used
as the card identity. Featureless or multi-card reference images are rejected.

Public scans additionally require visible human facial evidence in each region
(`yunet-portrait-presence-v1`). The bundled MIT-licensed YuNet weights run locally
in OpenCV CPU; missing/corrupt weights fail closed with an explicit service
error. Keyboard keys, empty sleeves and screen edges are rejected before both
enclosure suppression and non-maximum suppression. No-person photos return zero
regions, not a fabricated whole-image card. A tight, card-shaped portrait may
still be accepted when no outline is visible. Admin cropping/indexing is kept
separate and continues to accept non-person/back-side artwork. Detection is not
identity recognition; no facial embeddings are produced or stored. Heavily
occluded, back-facing or very small faces can be missed and should be retaken.

Only published cards with the current image URL and matching index version can
be returned. Missing/legacy indices return `SCAN_INDEX_UNAVAILABLE`, not synthetic
candidates. No visual evidence returns an unrecognized region; one region's error
does not fail the others. Similarities are heuristic geometric scores, **not**
calibrated correctness probabilities. Similar top candidates require confirmation.

Index writes use the catalog Outbox worker's file lock and atomic replacement.
After updating existing installations run `alembic upgrade head` and
`python scripts/import_card_assets.py --rebuild-existing` from `apps/api`.
New backend artwork uploads are queued automatically; keep the catalog worker
running. Old embedding records cannot be reused as artwork feature indices.

OpenCV is now a base dependency. The optional `ai`/`ai-face` extras and vendor
weights remain available for future evaluation, but are not prerequisites for this
artwork-matching path. `production_ready=false` remains intentional until field
accuracy, large-index performance and operational deployment are validated.
See [verification and activation](../../../../../docs/AI_SCAN_VERIFICATION.md).
