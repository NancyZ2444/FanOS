# card-matcher integration provenance

Source supplied by the user:

`/Users/nancy/Documents/FanOS/functional tool/card-matcher`

The `vendor/card_matcher` package is an isolated copy and was not reformatted. Fan OS
multi-card detection and persistence are implemented outside it in `adapter.py` and the
Scan module. Optional model weights are not committed to Git pending redistribution
license verification. Checksums recorded from the local source on 2026-09-15:

| Model | SHA-256 |
| --- | --- |
| `models/osnet/osnet_x1_0.onnx` | `5af439e3ad6e753d632e51e6f350f198024bcc820629d3e2bb1bf9bc2955e462` |
| `models/expression/emotion-ferplus-12.onnx` | `a2a2ba6a335a3b29c21acb6272f962bd3d47f84952aaffa03b60986e04efa61c` |
| `models/pose/yolov8n-pose.onnx` | `4abcdec00c4c9891244ffa57a384195ae0d7a56cada809ecde422847e8f669d1` |

The early experimental `hsemotion/*.pt` file is unused and must not be distributed.
InsightFace `buffalo_l` was not downloaded or bundled.
