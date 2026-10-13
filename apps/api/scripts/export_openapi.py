#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

API_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = API_ROOT.parents[1]
sys.path.insert(0, str(API_ROOT))

from app.main import app  # noqa: E402


def main() -> None:
    target = REPO_ROOT / "contracts" / "openapi"
    target.mkdir(parents=True, exist_ok=True)
    schema = app.openapi()
    (target / "fan-os-v1.json").write_text(
        json.dumps(schema, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (target / "fan-os-v1.yaml").write_text(
        yaml.safe_dump(schema, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )
    print(f"OpenAPI exported to {target}")


if __name__ == "__main__":
    main()
