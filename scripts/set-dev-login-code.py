"""Deprecated: V1.5 has no universal development login code.

Configure a protected code using the independent administrator's
Login whitelist -> Test code configuration UI, then add specifically authorized
numbers with an expiry. Existing .env values are ignored, never migrated.
"""
from pathlib import Path


def update_code(path: Path) -> None:
    raise ValueError(
        "Universal fixed codes are forbidden. Use the audited V1.5 whitelist configuration; "
        "this script makes no filesystem changes."
    )


if __name__ == "__main__":
    raise SystemExit(
        "This script is retired. Use Login whitelist -> Test code configuration. "
        "No environment file has been changed."
    )
