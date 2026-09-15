"""Package W04 native evidence and verify its W03 checkpoint, no author writes."""
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
qa = worktree / "art/water/lightplay/qa"
native = fixture / "art/water/lightplay/qa"


def hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


w03 = json.loads((worktree / "art/water/flow/qa/final-code-hashes.json").read_text(encoding="utf-8"))
changed = [
    "shaders/ember_voxel_surface_water.gdshader",
    "materials/ember_voxel_surface_water.tres",
    "tools/test_water_material.gd",
]
for name in changed:
    assert hash_file(worktree / "art/water/checkpoint-w03" / name) == w03[name], name
for name, digest in w03.items():
    if name not in changed:
        assert hash_file(worktree / name) == digest, name

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
(qa / "review3-non-water-guard.log").write_text(
    f"PASS review3 non-water guard: {len(non_water)} owned files identical to fixture\n"
    + "\n".join(path.relative_to(worktree).as_posix() for path in non_water)
    + "\n",
    encoding="utf-8",
)

cases = [
    "close-current",
    "review2-close-sharp",
    "review2-close-shadow",
    "review2-close-caustics",
    "review2-game-caustics",
    "review3-close-connected",
    "review4-close-flowing",
    "review5-close-patches",
    "review6-close-wobble",
    "review7-close-standing",
]
for case in cases:
    target = qa / case
    target.mkdir(parents=True, exist_ok=True)
    for path in (native / case).glob("*.png"):
        shutil.copy2(path, target / path.name)
    frames = sorted(target.glob("motion-*.png"))
    assert len(frames) == 48, case
    assert len({hash_file(path) for path in frames}) > 1, case
    gif = Image.open(target / "water-motion.gif")
    assert gif.n_frames == 48, case

for path in native.glob("probe-*.png"):
    shutil.copy2(path, qa / path.name)

for path in qa.glob("*.log"):
    log = path.read_text(encoding="utf-8-sig")
    assert not any(token in log for token in ("ERROR:", "SCRIPT ERROR", "FAIL")), path

new_names = [
    "tools/render_water_lightplay.gd",
    "tools/render_water_lightplay.gd.uid",
    "tools/test_water_lightplay.gd",
    "tools/test_water_lightplay.gd.uid",
    "tools/package_water_lightplay.py",
    "scenes/water_lab.tscn",
    "tools/water_lab.gd",
    "tools/test_water_lab.gd",
    "tools/run_water_lab.ps1",
    "water_lab.bat",
]
patch = ""
for name in changed:
    previous = (worktree / "art/water/checkpoint-w03" / name).read_text(encoding="utf-8")
    current = (worktree / name).read_text(encoding="utf-8")
    patch += "".join(difflib.unified_diff(
        previous.splitlines(True), current.splitlines(True), fromfile="a/" + name, tofile="b/" + name
    ))
for name in new_names:
    current = (worktree / name).read_text(encoding="utf-8")
    patch += "".join(difflib.unified_diff(
        [], current.splitlines(True), fromfile="/dev/null", tofile="b/" + name
    ))
patch_path = worktree / "art/water/lightplay/refinement.patch"
patch_path.write_text(patch, encoding="utf-8", newline="\n")

sections = []
for name in ("docs/EMBER_NOW.md", "docs/EMBER_PRODUCT_PLAN.md", "docs/EMBER_TECHNICAL_HANDOFF.md", "MIGRATION_TEST_PLAN.md"):
    document = (worktree / name).read_text(encoding="utf-8")
    start = document.index("<!-- BEGIN water-w04-d97c-20260915")
    marker = "<!-- END water-w04-d97c-20260915 -->"
    end = document.index(marker, start) + len(marker)
    sections.append("## " + name + "\n\n" + document[start:end] + "\n")
(worktree / "art/water/lightplay/documentation-sections.md").write_text("\n".join(sections), encoding="utf-8")

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
(qa / "review3-reverse-patch-guard.log").write_text(
    "PASS review3 reverse patch guard: git apply --check --reverse refinement.patch\n",
    encoding="utf-8",
)

report = (
    "PASS W04 package: W03 checkpoint verified, "
    f"{len(non_water)} owned non-water files identical, {len(cases)} native 48-frame sequences, "
    "active logs clean, reverse-applicable incremental patch/docs ready"
)
(qa / "package-guard.log").write_text(report + "\n", encoding="utf-8")
print(report)
