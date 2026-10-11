"""Run the mutation/Undo gates on synthetic input in a disposable Godot project.

No author content, prefabs, materials, JOI files, or live editor cache are copied.
Only the disposable project has write targets. A killed child can leave at most
temporary fixture data; cleanup is not the boundary protecting author assets.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
TESTS = ("test_voxel_migration_queue.gd", "test_voxel_migration_batch.gd")
IDS = ("migration_fixture_json", "migration_fixture_vox")


def copy_code(destination):
    for folder in ("scripts", "addons/ember_import", "addons/ember_surface_canvas", "shaders", "tools/prototypes"):
        for source in (ROOT / folder).rglob("*"):
            if source.is_file() and source.suffix in (".gd", ".uid", ".gdshader", ".gdshaderinc", ".glsl"):
                target = destination / source.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
    for name in (*TESTS, "voxel_migration_test_guard.gd"):
        shutil.copyfile(ROOT / "tools" / name, destination / "tools" / name)
    # Rebuild the name registry from the copied sources, without starting an
    # editor/import process or depending on the working checkout's cache.
    entries = []
    for source in destination.rglob("*.gd"):
        text = source.read_text(encoding="utf-8-sig")
        match = re.search(r"^class_name\s+(\w+)", text, re.MULTILINE)
        if not match:
            continue
        base = re.search(r"^extends\s+(\w+)", text, re.MULTILINE)
        entries.append(json.dumps({
            "base": base.group(1) if base else "RefCounted", "class": match.group(1),
            "icon": "", "is_abstract": False, "is_tool": bool(re.search(r"^@tool", text, re.MULTILINE)),
            "language": "GDScript", "path": "res://" + source.relative_to(destination).as_posix(),
        }))
    cache = destination / ".godot" / "global_script_class_cache.cfg"
    cache.parent.mkdir()
    cache.write_text("list=[" + ",\n".join(entries) + "]\n", encoding="utf-8")
    # The action owner's type dependencies include combat scripts with fixed
    # preloads. Copy their small non-voxel fixtures, never the author libraries.
    shutil.copytree(ROOT / "content" / "combat", destination / "content" / "combat")
    shutil.copytree(ROOT / "scenes" / "prototypes", destination / "scenes" / "prototypes")


def chunk(name, content):
    return name + struct.pack("<II", len(content), 0) + content


def make_fixtures(destination):
    models = destination / "migration-fixtures" / "voxels" / "models"
    models.mkdir(parents=True)
    items = destination / "migration-fixtures" / "items"
    items.mkdir()
    (items / "catalog.json").write_text('{"items": []}', encoding="utf-8")
    for index, model_id in enumerate(IDS):
        voxels = [0] * (16 * 16)
        voxels[0] = 1
        definition = {"id": model_id, "nameRu": model_id, "tags": ["test"], "model": {
            "voxelsPerBlock": 16, "sizeBlocks": {"x": 1, "y": 1, "z": 1},
            "heightVoxels": 1, "physical": True, "material": "wood" if index == 0 else {}, "palette": ["#00000000", "#ff8040"], "voxels": voxels,
        }}
        if index == 1:
            definition["mesh"] = {"file": "voxels/models/" + model_id + ".vox"}
            rgba = bytes((255, 128, 64, 255)) * 256
            children = (chunk(b"SIZE", struct.pack("<III", 16, 16, 1))
                        + chunk(b"XYZI", struct.pack("<I", 1) + bytes((0, 0, 0, 1)))
                        + chunk(b"RGBA", rgba))
            (models / (model_id + ".vox")).write_bytes(
                b"VOX " + struct.pack("<I", 150) + b"MAIN" + struct.pack("<II", 0, len(children)) + children
            )
        (models / (model_id + ".json")).write_text(json.dumps(definition), encoding="utf-8")


def hashes(directory):
    return {str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in directory.rglob("*") if path.is_file()}


def run_gate(godot, name, interrupt=False):
    with tempfile.TemporaryDirectory(prefix="ember-migration-") as temporary:
        destination = Path(temporary).resolve()
        copy_code(destination)
        make_fixtures(destination)
        (destination / ".migration-test-sandbox").write_text("synthetic fixtures only\n", encoding="utf-8")
        (destination / "project.godot").write_text('''config_version=5
[application]
config/name="EmberMigrationTests"
config/use_custom_user_dir=true
config/custom_user_dir="ember-tests/migration"
[autoload]
EmberExploreProgress="*res://scripts/ember_explore_state.gd"
[ember]
pack_path="res://migration-fixtures"
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding="utf-8")
        source_before = hashes(destination / "migration-fixtures")
        environment = os.environ.copy()
        environment["EMBER_MIGRATION_TEST_ROOT"] = destination.as_posix()
        print("Running", name, "in", destination, flush=True)
        command = [str(godot), "--headless", "--path", str(destination), "--script", "res://tools/" + name]
        if interrupt:
            log = tempfile.TemporaryFile()
            child = subprocess.Popen(command + ["--", "--pause-after-migration"], env=environment,
                                     stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 25
                while not (destination / ".migration-written").exists():
                    if child.poll() is not None or time.monotonic() >= deadline:
                        log.seek(0)
                        print(log.read().decode("utf-8", errors="replace"))
                        raise RuntimeError("child did not reach migration interruption checkpoint")
                    time.sleep(0.02)
                child.kill()
                child.communicate(timeout=10)
                if not (destination / "content/voxel_models" / (IDS[0] + ".tres")).is_file():
                    raise RuntimeError("interruption occurred before native migration write")
                if hashes(destination / "migration-fixtures") != source_before:
                    raise RuntimeError("interrupted child changed frozen source bytes")
                print("PASS forced termination after native write; no Undo/cleanup was executed")
                return
            finally:
                if child.poll() is None:
                    child.kill()
                child.communicate(timeout=10)
                log.close()
        result = subprocess.run(command, env=environment,
                                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        print(result.stdout, end="")
        print(result.stderr, end="")
        if hashes(destination / "migration-fixtures") != source_before:
            raise RuntimeError("mutation changed synthetic frozen source bytes")
        output = result.stdout + result.stderr
        if result.returncode or "ERROR:" in output or "FAIL" in output or "PASS voxel migration" not in result.stdout:
            raise RuntimeError(name + " failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / "tools/godot/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--test", choices=TESTS, help="Run just one isolated gate")
    parser.add_argument("--verify-interruption", action="store_true", help="Also kill a child after native migration, before Undo")
    args = parser.parse_args()
    godot = args.godot.resolve()
    # On Windows the console executable is only a launcher and may exit while
    # the engine is alive. Use the engine process so return codes/kill are real.
    if godot.name.endswith("_console.exe"):
        engine = godot.with_name(godot.name.replace("_console.exe", ".exe"))
        if engine.is_file():
            godot = engine
    for name in (args.test,) if args.test else TESTS:
        run_gate(godot, name)
    if args.verify_interruption:
        run_gate(godot, TESTS[0], interrupt=True)
    print("PASS isolated voxel migration gates; synthetic source bytes preserved")


if __name__ == "__main__":
    main()
