import importlib.util
from pathlib import Path

import pytest


def test_retired_code_script_does_not_mutate_environment(tmp_path):
    script = Path(__file__).resolve().parents[3] / "scripts" / "set-dev-login-code.py"
    spec = importlib.util.spec_from_file_location("dev_code", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    path = tmp_path / ".env.cloud"
    before = "JWT_SECRET=fixture\nDEV_PHONE_CODE=000000\n"
    path.write_text(before)
    with pytest.raises(ValueError, match="forbidden"):
        module.update_code(path)
    assert path.read_text() == before
    assert len(list(tmp_path.iterdir())) == 1
