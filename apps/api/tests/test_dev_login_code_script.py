import importlib.util
from pathlib import Path

import pytest


def test_code_update_preserves_other_secrets_and_is_idempotent(tmp_path):
    script = Path(__file__).resolve().parents[3] / "scripts" / "set-dev-login-code.py"
    spec = importlib.util.spec_from_file_location("dev_code", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    path = tmp_path / ".env.cloud"
    before = "JWT_SECRET=test-secret\nDEV_PHONE_CODE=000000\nWORKER_TOKEN=test-worker\n"
    path.write_text(before)
    backup = module.update_code(path)
    assert backup.read_text() == before
    assert path.read_text() == before.replace("DEV_PHONE_CODE=000000", "DEV_PHONE_CODE=666666")
    assert path.stat().st_mode & 0o777 == 0o600
    assert module.update_code(path) is None
    path.write_text("ENVIRONMENT=production\nDEV_PHONE_CODE=000000\n")
    with pytest.raises(ValueError, match="forbidden"):
        module.update_code(path)
