"""Check immutable pre-library sources and previous diorama viewport evidence."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("fixture", type=Path)
parser.add_argument("worktree", type=Path)
args = parser.parse_args()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
before = json.loads((args.worktree / "art/lighting/qa/source-hashes.json").read_text(encoding="utf-8"))
errors = [name for name, digest in before.items() if not (args.fixture / name).is_file() or sha(args.fixture / name) != digest]
current = {p.relative_to(args.fixture).as_posix() for directory in ("content", "scenes", "prefabs")
           for p in (args.fixture / directory).rglob("*") if p.is_file() and p.suffix in (".tres", ".tscn")}
extra = current - before.keys()
if extra != {"scenes/material_library_stand.tscn"}:
    errors.append("unexpected source additions/removals: " + str(extra))
print(f"{'FAIL' if errors else 'PASS'} existing source byte guard: {len(before)} unchanged; one owned stand scene added")
for case in ("corner", "corner-night", "pier"):
    for view in ("near", "overview"):
        old = args.worktree / f"art/lighting/qa/candidate-{case}-{view}.png"
        new = args.fixture / f"art/lighting/qa/candidate-library-guard-{case}-{view}.png"
        equal = old.is_file() and new.is_file() and sha(old) == sha(new)
        print(f"{'PASS' if equal else 'FAIL'} previous lighting/water pixel guard: {case}-{view}")
        if not equal:
            errors.append(f"changed viewport: {case}-{view}")
for error in errors:
    print(error)
raise SystemExit(bool(errors))
