"""One bottle/pickup/inventory/save/editor slice in a disposable project."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from run_interaction_tests import ROOT, prepare_project


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ember-world-items-') as directory:
        project = Path(directory)
        prepare_project(project)
        for folder in ('prefabs/items', 'scenes/combat'):
            shutil.copytree(ROOT / folder, project / folder, dirs_exist_ok=True)
        crate_mesh = project / 'prefabs/voxels/meshes/quest_carry_crate_block.res'
        crate_mesh.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'prefabs/voxels/meshes/quest_carry_crate_block.res', crate_mesh)
        for folder in ('content/action_scripts', 'content/dialogues', 'content/quests'):
            (project / folder).mkdir(parents=True, exist_ok=True)
            for source in (ROOT / folder).glob('shore_*.tres'):
                shutil.copyfile(source, project / folder / source.name)
        shutil.copyfile(ROOT / 'tools/test_world_item_cycle.gd', project / 'tools/test_world_item_cycle.gd')
        environment = os.environ.copy()
        environment['EMBER_INTERACTION_TEST_ROOT'] = project.as_posix()
        command = [str(ROOT / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'), '--path', str(project), '--script', 'res://tools/test_world_item_cycle.gd']
        command += ['--rendering-method', 'forward_plus', '--windowed', '--resolution', '1280x800', '--max-fps', '30'] if args.native else ['--headless']
        result = subprocess.run(command, env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        print(result.stdout, end='')
        print(result.stderr, end='')
        if result.returncode or 'ERROR:' in result.stderr or 'WORLD_ITEM PASS' not in result.stdout:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
