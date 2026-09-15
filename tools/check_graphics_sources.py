"""QA source hash guard. Reads scene/resource/prefab bytes; writes only manifest."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("project", type=Path)
parser.add_argument("manifest", type=Path)
parser.add_argument("--record", action="store_true")
args = parser.parse_args()
paths = sorted(p for directory in ("content", "scenes", "prefabs")
               for p in (args.project / directory).rglob("*")
               if p.is_file() and p.suffix in (".tres", ".tscn"))
hashes = {p.relative_to(args.project).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in paths}
if args.record:
    args.manifest.write_text(json.dumps(hashes, indent=2), encoding="utf-8")
    print(f"RECORDED {len(hashes)} scene/source/prefab hashes")
else:
    before = json.loads(args.manifest.read_text(encoding="utf-8"))
    changed = [name for name in sorted(before.keys() | hashes.keys())
               if before.get(name) != hashes.get(name)]
    print(f"{'FAIL' if changed else 'PASS'} graphics source hashes: {len(hashes)} files")
    for name in changed:
        print(name)
    raise SystemExit(bool(changed))
