"""Save/chest gate in a disposable project, without historical cities or JOI.

Synthetic native chest models and derived prefabs may be written only here.
Author maps, voxel libraries, prefabs and editor cache are never copied.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_voxel_migration_tests import ROOT, copy_code


def prepare_project(destination):
    copy_code(destination)
    for folder in ("content/items", "content/item_icons", "materials", "tools/fixtures"):
        shutil.copytree(ROOT / folder, destination / folder)
    shutil.copyfile(ROOT / "tools/test_progress_restore.gd", destination / "tools/test_progress_restore.gd")
    (destination / ".progress-test-sandbox").write_text("synthetic native save/chest fixtures only\n", encoding="utf-8")
    (destination / "project.godot").write_text('''config_version=5
[application]
config/name="EmberProgressTests"
run/main_scene="res://scenes/fixture_main.tscn"
config/use_custom_user_dir=true
config/custom_user_dir="ember-tests/progress-disposable"
[autoload]
EmberExploreProgress="*res://scripts/ember_explore_state.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding="utf-8")


def run_gate(godot):
    with tempfile.TemporaryDirectory(prefix="ember-progress-") as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        environment = os.environ.copy()
        environment["EMBER_PROGRESS_TEST_ROOT"] = destination.as_posix()
        result = subprocess.run(
            [str(godot), "--headless", "--path", str(destination), "--script", "res://tools/test_progress_restore.gd"],
            env=environment, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120,
        )
        print(result.stdout, end="")
        print(result.stderr, end="")
        output = result.stdout + result.stderr
        if result.returncode or "ERROR:" in output or "FAIL" in output or "PASS progress restore" not in result.stdout:
            raise RuntimeError("isolated save/chest gate failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / "tools/godot/Godot_v4.7.2-stable_win64.exe")
    args = parser.parse_args()
    godot = args.godot.resolve()
    if godot.name.endswith("_console.exe"):
        godot = godot.with_name(godot.name.replace("_console.exe", ".exe"))
    run_gate(godot)
    print("PASS disposable save/chest gate; no historical maps/models/prefabs/JOI copied")


if __name__ == "__main__":
    main()
