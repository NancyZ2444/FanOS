"""Fetch only image URLs from a catalog export, using an explicitly supplied proxy.

No credentials, redirects or private-network destinations. The resulting manifest
binds every original URL to a SHA-256 verified file for the server-side importer.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
from urllib.parse import urlsplit

import httpx
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--proxy", required=True)
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
                or url.hostname != "upload.wikimedia.org"
                or url.port not in {None, 443}
                or url.username
                or url.password
            ):
                item["error"] = "Source is not in the transfer allowlist"
                continue
            if source in cache:
                item.update(cache[source])
                continue
            try:
                content = bytearray()
                with client.stream(
                    "GET", source, headers={"User-Agent": "FanOS-CatalogThumbnail/1.0"}
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
                cache[source] = {"file": filename, "sha256": hashlib.sha256(content).hexdigest()}
                item.update(cache[source])
                print(f"Ready: {item['kind']} / {item['name']}", flush=True)
            except Exception as exc:
                item["error"] = str(exc)[:300]
                print(f"Failed: {item['name']} ({type(exc).__name__})", flush=True)
    (args.destination / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2)
    )
    print(
        f"Transferred {sum(bool(i.get('file')) for i in manifest['items'])}/{len(manifest['items'])} image references"
    )


if __name__ == "__main__":
    main()
