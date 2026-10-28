from io import BytesIO

from PIL import Image
from test_feedback_workflow import ROOT, missing, result, upload

from app.integrations.storage import get_storage


def test_uploaded_front_and_back_crop_authorization_and_original_retained(
    client, auth_headers, second_app_headers
):
    for _side in ("front", "back"):
        original = upload(client, auth_headers)
        cropped = result(
            client.post(
                ROOT + "/images/crop",
                headers=auth_headers,
                json={"image_id": original["id"], "crop": [0.1, 0.2, 0.6, 0.5]},
            )
        )
        assert cropped["id"] != original["id"]
        with Image.open(BytesIO(get_storage().read_bytes(cropped["image_url"]))) as image:
            assert image.size == (90, 105)
        with Image.open(BytesIO(get_storage().read_bytes(original["image_url"]))) as image:
            assert image.size == (150, 210)
        result(
            client.post(
                ROOT + "/images/crop",
                headers=second_app_headers,
                json={"image_id": original["id"], "crop": [0, 0, 1, 1]},
            ),
            422,
        )
        result(
            client.post(
                ROOT + "/images/crop",
                headers=auth_headers,
                json={"image_id": original["id"], "crop": [0.9, 0, 0.5, 1]},
            ),
            422,
        )
        result(
            client.post(
                ROOT + "/images/crop",
                headers=auth_headers,
                json={"image_id": original["id"], "detected_card_id": "both", "crop": [0, 0, 1, 1]},
            ),
            422,
        )


def test_detected_crop_remains_supported(client, auth_headers, second_app_headers):
    body = missing(client, auth_headers)
    request = {"detected_card_id": body["missing"]["detected_card_id"], "crop": [0, 0, 0.5, 1]}
    result(client.post(ROOT + "/images/crop", headers=auth_headers, json=request))
    result(client.post(ROOT + "/images/crop", headers=second_app_headers, json=request), 404)
    result(
        client.post(ROOT + "/images/crop", headers=auth_headers, json={"crop": [0, 0, 1, 1]}), 422
    )
