"""Fetch only image URLs from a catalog export, using an explicitly supplied proxy.

No credentials, redirects or private-network destinations. The resulting manifest
binds every original URL to a SHA-256 verified file for the server-side importer.
"""

import argparse
import hashlib
import io
import json
import time
from pathlib import Path
from urllib.parse import urlsplit

import httpx
from PIL import Image

ALLOWED_HOSTS = {
    "upload.wikimedia.org",
    "image-cdn-fa.spotifycdn.com",
    "image-cdn-ak.spotifycdn.com",
    "i.scdn.co",
}


def download_url(source, thumbnails):
    """Keep the same Wikimedia file; use its official standard-size rendition."""
    url = urlsplit(source)
    parts = url.path.split("/")
    if (
        thumbnails
        and url.hostname == "upload.wikimedia.org"
        and len(parts) == 6
        and parts[1:3] == ["wikipedia", "commons"]
        and parts[-1].lower().endswith((".jpg", ".jpeg", ".png"))
        and not url.query
    ):
        return url._replace(
            path="/wikipedia/commons/thumb/" + "/".join(parts[3:]) + "/960px-" + parts[-1]
        ).geturl()
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--proxy", required=True)
    parser.add_argument("--wikimedia-thumbnails", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    args.destination.mkdir(parents=True, exist_ok=True)
    cache = {}
    with httpx.Client(
        proxy=args.proxy, trust_env=False, follow_redirects=False, timeout=30
    ) as client:
        for item in manifest["items"]:
            source = item["source_url"]
            url = urlsplit(source)
            if (
                url.scheme != "https"
                or url.hostname not in ALLOWED_HOSTS
                or url.port not in {None, 443}
                or url.username
                or url.password
            ):
                item["error"] = "Source is not in the transfer allowlist"
                continue
            existing = args.destination / item.get("file", "missing")
            if (
                existing.is_file()
                and existing.resolve().is_relative_to(args.destination.resolve())
                and hashlib.sha256(existing.read_bytes()).hexdigest() == item.get("sha256")
            ):
                item.pop("error", None)
                continue
            if source in cache:
                item.update(cache[source])
                continue
            try:
                time.sleep(1)
                content = bytearray()
                fetched_url = download_url(source, args.wikimedia_thumbnails)
                with client.stream(
                    "GET", fetched_url, headers={"User-Agent": "FanOS-CatalogThumbnail/1.0"}
                ) as response:
                    response.raise_for_status()
                    if not response.headers.get("content-type", "").startswith("image/"):
                        raise ValueError("Not an image")
                    for chunk in response.iter_bytes():
                        content.extend(chunk)
                        if len(content) > 20 * 1024 * 1024:
                            raise ValueError("Image exceeds 20 MB")
                with Image.open(io.BytesIO(content)) as image:
                    if image.width * image.height > 40_000_000:
                        raise ValueError("Image exceeds pixel limit")
                    image.verify()
                filename = hashlib.sha256(source.encode()).hexdigest() + ".image"
                (args.destination / filename).write_bytes(content)
                cache[source] = {
                    "file": filename,
                    "sha256": hashlib.sha256(content).hexdigest(),
                    "download_url": fetched_url,
                }
                item.update(cache[source])
                item.pop("error", None)
                print(f"Ready: {item['kind']} / {item['name']}", flush=True)
            except Exception as exc:
                item["error"] = str(exc)[:300]
                print(f"Failed: {item['name']} ({type(exc).__name__})", flush=True)
    (args.destination / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2)
    )
    ready = sum(bool(i.get("file")) for i in manifest["items"])
    print(f"Transferred {ready}/{len(manifest['items'])} image references")


if __name__ == "__main__":
    main()
