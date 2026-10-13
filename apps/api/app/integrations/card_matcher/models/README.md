# Scan portrait-presence model

- Source: https://github.com/opencv/opencv_zoo/tree/47534e27c9851bb1128ccc0102f1145e27f23f98/models/face_detection_yunet
- File: `face_detection_yunet_2023mar.onnx` (OpenCV 4.x; 232589 bytes).
- SHA-256: `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4`.
- License: MIT, retained in `LICENSE-YuNet.txt`.

Bundled with the API; no runtime download, external inference service, identity
recognition or face-vector storage. This gate checks for a visible person using
facial evidence, not whether they are a particular idol. Back-facing/occluded,
very small or heavily stylized faces may be rejected. Existing SIFT artwork
matching still determines the card edition, and the user confirms the result.
