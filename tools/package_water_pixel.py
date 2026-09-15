"""Package native W02 evidence and verify its checkpoints/owned code, no author writes."""
import argparse
import difflib
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("worktree", type=Path)
parser.add_argument("fixture", type=Path)
args = parser.parse_args()
worktree, fixture = args.worktree, args.fixture
qa = worktree / "art/water/pixel/qa"
native = fixture / "art/water/pixel/qa"
hash_file = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = json.loads((worktree / "art/water/qa/final-code-hashes.json").read_text(encoding="utf-8"))
production = ["shaders/ember_voxel_surface_water.gdshader", "materials/ember_voxel_surface_water.tres"]
for name in production:
    assert hash_file(worktree / "art/water/checkpoint-w01" / name) == before[name], name
for name, digest in before.items():
    if name not in production and name != "tools/test_water_material.gd":
        assert hash_file(worktree / name) == digest, name
owned = ["shaders/ember_voxel_toon.gdshader", "shaders/ember_voxel_transparent.gdshader",
         "shaders/ember_diorama_light.gdshaderinc", "shaders/ember_material_opaque.gdshader",
         "shaders/ember_material_transparent.gdshader", "shaders/ember_material_surface.gdshaderinc",
         "materials/ember_voxel_toon.tres", "materials/ember_voxel_transparent.tres",
         "scripts/ember_material_library.gd"]
non_water = [worktree / name for name in owned]+list((worktree / "materials/library").glob("*.tres"))
for path in non_water:
    assert hash_file(path) == hash_file(fixture / path.relative_to(worktree)), path
spots = json.loads((qa / "pre-final-hashes.json").read_text(encoding="utf-8-sig"))
spot_report = []
for case, digest in spots.items():
    assert hash_file(native / case / "water.png").upper() == digest, case
    spot_report.append(f"PASS final-code native capture {case}: byte-identical")
(qa / "final-code-spot-check.log").write_text("\n".join(spot_report)+"\n", encoding="utf-8")
for path in native.rglob("*"):
    if path.is_file() and path.suffix in (".png", ".gif"):
        target = qa / path.relative_to(native)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
sequences = []
for directory in sorted(qa.iterdir()):
    frames = sorted(directory.glob("motion-*.png")) if directory.is_dir() else []
    if not frames:
        continue
    assert len(frames) == 48, directory
    assert len({hash_file(path) for path in frames}) > 1, directory
    gif = Image.open(directory / "water-motion.gif")
    assert gif.n_frames == 48, directory
    sequences.append(directory.name)
assert len(sequences) == 11, sequences
for path in qa.glob("*.log"):
    text = path.read_text(encoding="utf-8-sig")
    assert not any(token in text for token in ("ERROR:", "SCRIPT ERROR", "FAIL")), path
old_test = (worktree / "tools/test_water_material.gd").read_text(encoding="utf-8").replace(
    '"preview_time":-1.0,\n\t\t"reflection_pixel_size":0.125,"reflection_pixel_strength":0.7}',
    '"preview_time":-1.0}')
assert hashlib.sha256(old_test.encode()).hexdigest() == before["tools/test_water_material.gd"], "W01 material-test reconstruction"
backup = worktree / "art/water/checkpoint-w01/tools/test_water_material.gd"
backup.parent.mkdir(exist_ok=True)
backup.write_text(old_test, newline="\n", encoding="utf-8")
changes = [(name, (worktree / "art/water/checkpoint-w01" / name).read_text(encoding="utf-8")) for name in production]
changes.append(("tools/test_water_material.gd", old_test))
new_names = ["tools/render_water_pixel.gd", "tools/test_water_pixel.gd", "tools/package_water_pixel.py",
             "tools/render_water_pixel.gd.uid", "tools/test_water_pixel.gd.uid"]
changes.extend((name, "") for name in new_names)
patch = ""
for name, previous in changes:
    current = (worktree / name).read_text(encoding="utf-8")
    patch += "".join(difflib.unified_diff(previous.splitlines(True), current.splitlines(True),
                     fromfile="a/"+name if previous else "/dev/null", tofile="b/"+name))
(worktree / "art/water/pixel/refinement.patch").write_text(patch, newline="\n", encoding="utf-8")
sections = []
for name in ("docs/EMBER_NOW.md", "docs/EMBER_PRODUCT_PLAN.md", "docs/EMBER_TECHNICAL_HANDOFF.md", "MIGRATION_TEST_PLAN.md"):
    text = (worktree / name).read_text(encoding="utf-8")
    start = text.index("<!-- BEGIN water-w02-d97c-20260915")
    end = text.index("<!-- END water-w02-d97c-20260915 -->", start)+len("<!-- END water-w02-d97c-20260915 -->")
    sections.append("## "+name+"\n\n"+text[start:end]+"\n")
(worktree / "art/water/pixel/documentation-sections.md").write_text("\n".join(sections), encoding="utf-8")
names = production+["tools/test_water_material.gd"]+new_names
(qa / "final-code-hashes.json").write_text(json.dumps({name: hash_file(worktree / name) for name in names}, indent=2)+"\n", encoding="utf-8")
report = f"PASS W02 package: W01 checkpoint verified, {len(non_water)} owned non-water files identical, {len(sequences)} native48-frame sequences, 7final native captures identical, active logs clean of errors; incremental patch/docs ready"
(qa / "package-guard.log").write_text(report+"\n", encoding="utf-8")
print(report)
