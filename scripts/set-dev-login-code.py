"""Explicit opt-in for the test server; changes no JWT, database or worker secrets."""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path


def update_code(path: Path) -> Path | None:
    if path.is_symlink() or not path.is_file():
        raise ValueError("Expected an existing regular .env.cloud file")
    content = path.read_text(encoding="utf-8")
    if re.search(r"(?m)^\s*ENVIRONMENT\s*=\s*['\"]?production", content, re.IGNORECASE):
        raise ValueError("Fixed test codes are forbidden in production")
    pattern = r"(?m)^DEV_PHONE_CODE=.*$"
    matches = re.findall(pattern, content)
    if len(matches) > 1:
        raise ValueError("Duplicate DEV_PHONE_CODE; resolve manually")
    if matches == ["DEV_PHONE_CODE=666666"]:
        return None
    updated = (
        re.sub(pattern, "DEV_PHONE_CODE=666666", content)
        if matches
        else content.rstrip() + "\nDEV_PHONE_CODE=666666\n"
    )
    backup_fd, backup_name = tempfile.mkstemp(
        prefix=".env.cloud.before-test-code-", dir=path.parent
    )
    with os.fdopen(backup_fd, "w", encoding="utf-8") as handle:
        handle.write(content)
    staging_fd, staging_name = tempfile.mkstemp(
        prefix=".env.cloud.code-update-", dir=path.parent
    )
    try:
        with os.fdopen(staging_fd, "w", encoding="utf-8") as handle:
            handle.write(updated)
        os.replace(staging_name, path)
    finally:
        Path(staging_name).unlink(missing_ok=True)
    return Path(backup_name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm-development", action="store_true", required=True)
    args = parser.parse_args()
    target = Path(__file__).resolve().parents[1] / ".env.cloud"
    backup = update_code(target)
    print("Development test code set to 666666. Other credentials are unchanged.")
    if backup:
        print(f"Private backup: {backup}")
    print("Recreate the API container for the environment change to take effect.")
