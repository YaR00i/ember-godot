"""Native interaction gates in disposable projects, without historical cities/JOI.

Only shared code/materials/items/marker SVGs and fixed type preloads are copied.
Synthetic dialogue/action/shop/quest Resources are generated inside the temporary
project. This is the native-write boundary; cleanup is not the safety mechanism.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_voxel_migration_tests import ROOT, copy_code, hashes

TESTS = ('test_talk_shop.gd', 'test_action_script.gd', 'test_interact_launch_rules.gd', 'test_quest_state.gd')


def prepare_project(destination):
    copy_code(destination)
    for folder in ('content/items', 'content/item_icons', 'materials', 'tools/fixtures', 'assets/world_markers'):
        shutil.copytree(ROOT / folder, destination / folder)
    for name in TESTS:
        shutil.copyfile(ROOT / 'tools' / name, destination / 'tools' / name)
    (destination / '.interaction-test-sandbox').write_text('synthetic native interaction fixtures only\n', encoding='utf-8')
    (destination / 'project.godot').write_text('''config_version=5
[application]
config/name="EmberInteractionTests"
config/use_custom_user_dir=true
config/custom_user_dir="ember-tests/interactions-disposable"
[autoload]
EmberExploreProgress="*res://scripts/ember_explore_state.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding='utf-8')


def run_gate(godot, test):
    with tempfile.TemporaryDirectory(prefix='ember-interaction-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'materials', 'assets/world_markers')}
        environment = os.environ.copy()
        environment['EMBER_INTERACTION_TEST_ROOT'] = destination.as_posix()
        result = subprocess.run([str(godot), '--headless', '--path', str(destination), '--script', 'res://tools/' + test],
                                env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = result.stdout + result.stderr
        print(output, end='')
        for folder, before in frozen.items():
            after = hashes(destination / folder)
            if before != after:
                raise RuntimeError('gate changed copied shared inputs: ' + folder)
        if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
            raise RuntimeError(test + ' failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--test', choices=TESTS)
    args = parser.parse_args()
    godot = args.godot.resolve()
    if godot.name.endswith('_console.exe'):
        godot = godot.with_name(godot.name.replace('_console.exe', '.exe'))
    for test in (args.test,) if args.test else TESTS:
        run_gate(godot, test)
    print('PASS independent interaction gates; historical content absent, shared inputs unchanged')


if __name__ == '__main__':
    main()
