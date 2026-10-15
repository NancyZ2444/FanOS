"""Read-only safeguards before applying the release to the known cloud stack."""
import json
import subprocess
from pathlib import Path

root = Path("/home/ubuntu/FanOS-code")
config = json.loads(subprocess.check_output([
    "docker", "compose", "-p", "fanos", "--env-file", ".env.cloud", "-f",
    "docker-compose.cloud.yml", "config", "--format", "json",
], cwd=root))
public = config["services"]["api"]["environment"].get("PUBLIC_MEDIA_BASE_URL", "")
if public != "http://106.53.120.249:5173/media":
    raise SystemExit("STOP: PUBLIC_MEDIA_BASE_URL must be http://106.53.120.249:5173/media; check .env.cloud")
targets = {"postgres": "/var/lib/postgresql/data", "api": "/srv/api/data/uploads"}
for service, target in targets.items():
    info = json.loads(subprocess.check_output(["docker", "inspect", f"fanos-{service}-1"]))[0]
    if info["Config"]["Labels"].get("com.docker.compose.project") != "fanos":
        raise SystemExit("STOP: unexpected Compose project")
    actual = next(m.get("Name") for m in info["Mounts"] if m["Destination"] == target)
    source = next(v["source"] for v in config["services"][service]["volumes"] if v["target"] == target)
    expected = config["volumes"][source]["name"]
    if actual != expected:
        raise SystemExit(f"STOP: {service} volume differs; refusing to create an empty stack")
print("OK: fanos project, media URL and existing database/upload volumes verified")
