"""Boar/in-place battle and durable result in one disposable project."""
import os
import argparse
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
    parser.add_argument('--test', choices=('test_shore_combat.gd','test_explore_feedback.gd','test_combat_world_items.gd'), default='test_shore_combat.gd')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ember-shore-combat-') as directory:
        project = Path(directory)
        prepare_project(project)
        for folder in ('prefabs/items', 'scenes/combat'):
            shutil.copytree(ROOT / folder, project / folder, dirs_exist_ok=True)
        shutil.copyfile(ROOT / 'scenes/combat_lab.tscn', project / 'scenes/combat_lab.tscn')
        if args.test == 'test_combat_world_items.gd':
            for relative in ('prefabs/voxels/meshes/quest_carry_crate_block.res','content/voxel_models/quest_carry_crate.tres'):
                target=project/relative
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(ROOT/relative,target)
        for folder in ('content/action_scripts', 'content/dialogues', 'content/quests'):
            (project / folder).mkdir(parents=True, exist_ok=True)
            for source in (ROOT / folder).glob('shore_*.tres'):
                shutil.copyfile(source, project / folder / source.name)
        shutil.copyfile(ROOT / 'tools' / args.test, project / 'tools' / args.test)
        environment = os.environ.copy()
        environment['EMBER_INTERACTION_TEST_ROOT'] = project.as_posix()
        command = [str(ROOT / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'), '--path', str(project), '--script', 'res://tools/' + args.test]
        command += ['--rendering-method', 'forward_plus', '--windowed', '--resolution', '1280x800', '--max-fps', '30'] if args.native else ['--headless']
        result = subprocess.run(command, env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=110)
        print(result.stdout, end=''); print(result.stderr, end='')
        expected = 'CRATE_COMBAT PASS' if args.test == 'test_combat_world_items.gd' else ('FEEDBACK PASS' if args.test == 'test_explore_feedback.gd' else 'SHORE_COMBAT PASS')
        if result.returncode or 'ERROR:' in result.stderr or expected not in result.stdout:
            raise SystemExit(1)

if __name__ == '__main__':
    main()
