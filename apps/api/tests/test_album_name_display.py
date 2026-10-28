from test_album_v11 import create
from test_digital_albums import BASE, data, page, patch


def test_album_name_mode_persists_in_private_and_published_work(client, auth_headers):
    for work_mode in ("BOOK", "CARDS"):
        album = create(client, auth_headers, work_mode)
        for name_mode in ("official", "combined", "remark"):
            view = {**album["card_view"], "name_display_mode": name_mode}
            album = data(patch(client, auth_headers, album, card_view=view))
            reread = data(client.get(f"{BASE}/{album['id']}", headers=auth_headers))
            assert reread["card_view"]["name_display_mode"] == name_mode
        assert (
            patch(
                client,
                auth_headers,
                album,
                card_view={**album["card_view"], "name_display_mode": "unknown"},
            ).status_code
            == 422
        )
        placements = page(["card-aria-01"])
        content = (
            {"card_instances": placements["slots"]}
            if work_mode == "CARDS"
            else {"pages": [placements]}
        )
        album = data(patch(client, auth_headers, album, visibility="PUBLIC", **content))
        data(
            client.post(
                f"{BASE}/{album['id']}/publish",
                headers=auth_headers,
                json={"revision": album["revision"]},
            )
        )
        public = data(client.get(f"{BASE}/{album['id']}"))
        assert public["card_view"]["name_display_mode"] == "remark"
        assert "aliases" not in public["card_view"]
