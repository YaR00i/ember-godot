"""Validate unchanged canonical sources; water pixels intentionally differ in W01."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("fixture", type=Path)
parser.add_argument("worktree", type=Path)
args = parser.parse_args()
before = json.loads((args.worktree / "art/lighting/qa/source-hashes.json").read_text(encoding="utf-8"))
errors = []
for name, digest in before.items():
    path = args.fixture / name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        errors.append(name)
current = {p.relative_to(args.fixture).as_posix() for directory in ("content", "scenes", "prefabs")
           for p in (args.fixture / directory).rglob("*") if p.is_file() and p.suffix in (".tres", ".tscn")}
if current - before.keys() != {"scenes/material_library_stand.tscn"}:
    errors.append("unexpected canonical source addition")
print(f"{'FAIL' if errors else 'PASS'} W01 canonical source guard: {len(before)} unchanged; existing material stand is the sole source addition")
for error in errors: print(error)
raise SystemExit(bool(errors))
