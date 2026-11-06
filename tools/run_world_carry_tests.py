"""Native cross-map physical cargo gate; writes and import only in a disposable fixture."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
from run_chapter1_blockout_tests import prepare
ROOT = Path(__file__).resolve().parents[1]

def run(project):
    if project.resolve() == ROOT or not (project / '.interaction-test-sandbox').exists():
        raise SystemExit('REFUSED: disposable fixture required')
    shutil.copytree(ROOT / 'scripts', project / 'scripts', dirs_exist_ok=True)
    for name in ('chapter1_woodland.tscn',):
        shutil.copyfile(ROOT / 'scenes' / name, project / 'scenes' / name)
    for name in ('chapter1_delivery_crate.tscn', 'quest_crate.tscn', 'quest_crate_break.scn', 'physical_crates.tscn'):
        shutil.copyfile(ROOT / 'prefabs/items' / name, project / 'prefabs/items' / name)
    for relative in ('content/voxel_models/quest_carry_crate.tres', 'prefabs/voxels/meshes/quest_carry_crate_block.res'):
        target = project / relative; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    shutil.copyfile(ROOT / 'tools/test_world_carry_transition.gd', project / 'tools/test_world_carry_transition.gd')
    godot = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    imported = subprocess.run([str(godot), '--headless', '--editor', '--path', str(project), '--quit'], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
    if imported.returncode or 'SCRIPT ERROR:' in imported.stdout + imported.stderr:
        print(imported.stdout + imported.stderr); raise SystemExit(1)
    result = subprocess.run([str(godot), '--path', str(project), '--rendering-method', 'forward_plus', '--windowed', '--resolution', '1280x800', '--max-fps', '60', '--script', 'res://tools/test_world_carry_transition.gd'], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=420)
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'ERROR:' in output or 'CHECK FAIL' in output or 'CARGO TRANSITION PASS' not in output: raise SystemExit(1)

def main():
    p = argparse.ArgumentParser(); p.add_argument('--fixture', type=Path); args = p.parse_args()
    if args.fixture: run(args.fixture)
    else:
        with tempfile.TemporaryDirectory(prefix='ember-cargo-') as folder:
            project = Path(folder); prepare(ROOT, project); run(project)

if __name__ == '__main__': main()
