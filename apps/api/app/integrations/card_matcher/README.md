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

Reference indexing validates the four corners before accepting a crop. Small,
tapered artwork contours cannot replace the reference; a card-shaped input with
only those fragments retains its full image. An otherwise valid card can ignore
small fragments only when they are fully inside its polygon. Separate cards and
large uncertain shapes still require explicit cropping. This check runs only in
indexing, so public detection and the editable admin preview are unaffected.

RANSAC's reprojection tolerance follows the query crop's resolution (1.2% of its
shorter side, bounded to 1–4 pixels). Small thumbnails therefore need tighter
feature alignment; full-sized images retain the previous four-pixel tolerance.
This changes geometric verification, not SIFT descriptors or the index format.

If strict artwork verification fails, a separate approximate path can return
related printed details for manual review. It requires reciprocal SIFT matches,
independent locations, coherent scale/rotation/translation, coverage in both
images and a plausible projected card. It does not identify a person. Approximate
scores are capped at 0.85 and carry `scores.approximate=1`; they sort after strict
matches and always receive `needs_confirmation`. Unsupported images still have
no candidates. Existing indices work without a rebuild. Persisted scan crops use
PNG so selected-card and direct recognition see the same pixels; original-photo
archival remains JPEG.

Public scans additionally require visible human facial evidence in each region
(`yunet-portrait-presence-v2`). The bundled MIT-licensed YuNet weights run locally
in OpenCV CPU; missing/corrupt weights fail closed with an explicit service
error. Keyboard keys, empty sleeves and screen edges are rejected before both
enclosure suppression and non-maximum suppression. No-person photos return zero
regions, not a fabricated whole-image card. A tight, card-shaped portrait may
still be accepted when no outline is visible. Admin cropping/indexing is kept
separate and continues to accept non-person/back-side artwork. Detection is not
identity recognition; no facial embeddings are produced or stored. Heavily
occluded, back-facing or very small faces can be missed and should be retaken.

Public detection supplements the original geometry with bounded multi-scale
closed outlines and large foreground silhouettes. Near-identical proposals are
merged before portrait inference; complete inner outlines take precedence over
photo perimeters. Sleeve layouts may recover a missing cell only from measured
neighbours plus its own edge and texture evidence. Portrait normalization uses
at most twelve inferences per candidate, and still requires 0.88 confidence;
weak responses only select the retry orientation. Four inferences suffice when
there is no plausible face. See the [2026-10-22 detection evaluation](../../../../../docs/SCAN_DETECTION_OPTIMIZATION_20261022.md).

Alternative outlines are compared using continuous contrast across all four
edges, so a textured background or partial artwork line does not win by size.
After selection, a large isolated public-scan card may be tightened within a
transparent sleeve only when multiple separated edges and a background-like
intervening strip support it. Each shifted side needs its own evidence; evidence
on another side cannot authorize trimming a printed border. No fixed inset is
applied; printed white borders are retained. This refinement does not run in
admin cropping or indexing.

Public `crop_region` includes optional ordered `corners` in the same normalized
full-image axes as its bounding box. The mobile overlay and hit testing use this
polygon; legacy regions without valid corners retain their rectangular overlay.
Internal admin corners still use pixel endpoints (`width - 1`, `height - 1`).
The evaluation script accepts optional manual four-corner labels to test extra
background and missing card area separately from count and bounding-box IoU.

Only published cards with the current image URL and matching index version can
be returned. Missing/legacy indices return `SCAN_INDEX_UNAVAILABLE`, not synthetic
candidates. No visual evidence returns an unrecognized region; one region's error
does not fail the others. Similarities are heuristic geometric scores, **not**
calibrated correctness probabilities. Similar top candidates require confirmation.

Index writes use the catalog Outbox worker's file lock and atomic replacement.
When migrating legacy embedding installations run `alembic upgrade head` and
`python scripts/import_card_assets.py --rebuild-existing` from `apps/api`.
New backend artwork uploads are queued automatically; keep the catalog worker
running. Old embedding records cannot be reused as artwork feature indices.
The 2026-10-23 geometry and matching changes reuse existing SIFT indices. Restart
the API and catalog worker, then retry affected failed references through the
admin scan-index endpoint. An exhausted five-attempt job does not retry itself;
the retry endpoint queues a new audited event without erasing the old failure.
For local storage configured on a loopback address, `localhost`, `127.0.0.1` and
`[::1]` are equivalent only with the same scheme, effective port and media path.
The worker uses the same storage reader as scans. External origins and traversal
remain rejected; S3 does not accept loopback aliases. This also lets existing
feedback-upload references be retried without editing their catalog image URL.

OpenCV is now a base dependency. The optional `ai`/`ai-face` extras and vendor
weights remain available for future evaluation, but are not prerequisites for this
artwork-matching path. `production_ready=false` remains intentional until field
accuracy, large-index performance and operational deployment are validated.
See [verification and activation](../../../../../docs/AI_SCAN_VERIFICATION.md).
