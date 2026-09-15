"""Package native W03 water evidence and verify its W02 checkpoint, no author writes."""
import argparse
import difflib
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image


parser = argparse.ArgumentParser()
parser.add_argument("worktree", type=Path)
parser.add_argument("fixture", type=Path)
args = parser.parse_args()
worktree, fixture = args.worktree, args.fixture
qa = worktree / "art/water/flow/qa"
native = fixture / "art/water/flow/qa"


def hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


w02 = json.loads((worktree / "art/water/pixel/qa/final-code-hashes.json").read_text(encoding="utf-8"))
checkpoint_names = [
    "shaders/ember_voxel_surface_water.gdshader",
    "materials/ember_voxel_surface_water.tres",
    "tools/test_water_material.gd",
]
for name in checkpoint_names:
    assert hash_file(worktree / "art/water/checkpoint-w02" / name) == w02[name], name
for name, digest in w02.items():
    if name not in checkpoint_names:
        assert hash_file(worktree / name) == digest, name

w01 = json.loads((worktree / "art/water/qa/final-code-hashes.json").read_text(encoding="utf-8"))
assert hash_file(worktree / "art/water/checkpoint-w02/tools/test_water_pattern_seams.gd") == w01["tools/test_water_pattern_seams.gd"]

owned = [
    "shaders/ember_voxel_toon.gdshader",
    "shaders/ember_voxel_transparent.gdshader",
    "shaders/ember_diorama_light.gdshaderinc",
    "shaders/ember_material_opaque.gdshader",
    "shaders/ember_material_transparent.gdshader",
    "shaders/ember_material_surface.gdshaderinc",
    "materials/ember_voxel_toon.tres",
    "materials/ember_voxel_transparent.tres",
    "scripts/ember_material_library.gd",
]
non_water = [worktree / name for name in owned] + list((worktree / "materials/library").glob("*.tres"))
for path in non_water:
    assert hash_file(path) == hash_file(fixture / path.relative_to(worktree)), path

sequence_names = ["close-before", "close-no-network", "close-flow", "game-flow", "wide-flow"]
for case in sequence_names:
    source = native / case
    target = qa / case
    target.mkdir(parents=True, exist_ok=True)
    for path in source.iterdir():
        if path.is_file() and path.suffix in (".png", ".gif"):
            shutil.copy2(path, target / path.name)

for path in native.glob("probe-*.png"):
    shutil.copy2(path, qa / path.name)

for case in sequence_names:
    directory = qa / case
    frames = sorted(directory.glob("motion-*.png"))
    assert len(frames) == 48, directory
    assert len({hash_file(path) for path in frames}) > 1, directory
    gif = Image.open(directory / "water-motion.gif")
    assert gif.n_frames == 48, directory

for path in qa.glob("*.log"):
    log = path.read_text(encoding="utf-8-sig")
    assert not any(token in log for token in ("ERROR:", "SCRIPT ERROR", "FAIL")), path

changed = checkpoint_names + ["tools/test_water_pattern_seams.gd", "tools/test_diorama_materials.gd"]
new_names = [
    "tools/render_water_flow.gd",
    "tools/render_water_flow.gd.uid",
    "tools/test_water_flow.gd",
    "tools/test_water_flow.gd.uid",
    "tools/package_water_flow.py",
]
patch = ""
for name in changed:
    previous = (worktree / "art/water/checkpoint-w02" / name).read_text(encoding="utf-8")
    current = (worktree / name).read_text(encoding="utf-8")
    patch += "".join(difflib.unified_diff(
        previous.splitlines(True), current.splitlines(True), fromfile="a/" + name, tofile="b/" + name
    ))
for name in new_names:
    current = (worktree / name).read_text(encoding="utf-8")
    patch += "".join(difflib.unified_diff(
        [], current.splitlines(True), fromfile="/dev/null", tofile="b/" + name
    ))
patch_path = worktree / "art/water/flow/refinement.patch"
patch_path.write_text(patch, encoding="utf-8", newline="\n")

sections = []
for name in ("docs/EMBER_NOW.md", "docs/EMBER_PRODUCT_PLAN.md", "docs/EMBER_TECHNICAL_HANDOFF.md", "MIGRATION_TEST_PLAN.md"):
    document = (worktree / name).read_text(encoding="utf-8")
    start = document.index("<!-- BEGIN water-w03-d97c-20260915")
    end_marker = "<!-- END water-w03-d97c-20260915 -->"
    end = document.index(end_marker, start) + len(end_marker)
    sections.append("## " + name + "\n\n" + document[start:end] + "\n")
(worktree / "art/water/flow/documentation-sections.md").write_text("\n".join(sections), encoding="utf-8")

names = changed + new_names
(qa / "final-code-hashes.json").write_text(
    json.dumps({name: hash_file(worktree / name) for name in names}, indent=2) + "\n", encoding="utf-8"
)

reverse = subprocess.run(
    ["git", "apply", "--check", "--reverse", str(patch_path)],
    cwd=worktree,
    capture_output=True,
    text=True,
)
assert reverse.returncode == 0, reverse.stderr

report = (
    "PASS W03 package: W02 checkpoint verified, "
    f"{len(non_water)} owned non-water files identical, 5 native 48-frame sequences, "
    "active logs clean of errors, reverse-applicable incremental patch and docs ready"
)
(qa / "package-guard.log").write_text(report + "\n", encoding="utf-8")
print(report)
