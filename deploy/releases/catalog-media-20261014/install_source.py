"""Verify bundle, save a recoverable source snapshot, then install only listed files."""
import hashlib
import json
import shutil
import sys
import tarfile
from pathlib import Path

bundle, project, backup = map(Path, sys.argv[1:])
manifest = json.loads((bundle / "manifest.json").read_text())
for name, digest in manifest.items():
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or ".env" in relative.name:
        raise SystemExit(f"STOP: unsafe bundle path {name}")
    source = bundle / "source" / relative
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise SystemExit(f"STOP: checksum mismatch {name}")
with tarfile.open(backup / "source-before.tar.gz", "w:gz") as archive:
    for name in manifest:
        target = project / name
        if target.exists():
            archive.add(target, arcname=name)
(backup / "new-files.json").write_text(json.dumps([n for n in manifest if not (project / n).exists()]))
for name in manifest:
    target = project / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(bundle / "source" / name, target)
print(f"Installed {len(manifest)} source files; .env.cloud and runtime data were not touched")
