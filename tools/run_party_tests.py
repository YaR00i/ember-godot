"""Run bag, health/respawn and follower gates without historical cities or JOI.

Native test items exist only in a guarded disposable project. Scene/save writes
use unique user:// fixtures; current native items and shared inputs stay frozen.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_voxel_migration_tests import ROOT, copy_code, hashes

TESTS = ('test_inventory_equipment.gd', 'test_health_consumables.gd',
         'test_party_followers.gd', 'test_defeat_respawn.gd', 'test_party_save_v2.gd', 'test_equipment_layout.gd')
FIXTURE_ITEMS = ('party_fixture_weapon.tres', 'party_fixture_arena.tres',
                 'party_fixture_armor.tres')


def prepare_project(destination):
    copy_code(destination)
    for folder in ('content/items', 'content/item_icons', 'materials', 'tools/fixtures'):
        shutil.copytree(ROOT / folder, destination / folder)
    for name in TESTS:
        shutil.copyfile(ROOT / 'tools' / name, destination / 'tools' / name)
    # Save-v2 preloads the current encounter; its arena is a small native scene.
    arenas = destination / 'scenes/combat/arenas'
    arenas.mkdir(parents=True)
    shutil.copyfile(ROOT / 'scenes/combat/arenas/colored_crossing.tscn', arenas / 'colored_crossing.tscn')
    (destination / '.party-test-sandbox').write_text('synthetic native party fixtures only\n', encoding='utf-8')
    (destination / 'project.godot').write_text('''config_version=5
[application]
config/name="EmberPartyTests"
config/use_custom_user_dir=true
config/custom_user_dir="ember-tests/party-disposable"
[autoload]
EmberExploreProgress="*res://scripts/ember_explore_state.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding='utf-8')


def run_gate(godot, test, capture_arg=None):
    with tempfile.TemporaryDirectory(prefix='ember-party-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        if capture_arg:
            project = destination / 'project.godot'
            project.write_text(project.read_text(encoding='utf-8').replace('gl_compatibility', 'forward_plus'), encoding='utf-8')
        frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'content/combat', 'materials')}
        environment = os.environ.copy()
        environment['EMBER_PARTY_TEST_ROOT'] = destination.as_posix()
        command = [str(godot)] + ([] if capture_arg else ['--headless'])
        command += ['--path', str(destination), '--script', 'res://tools/' + test]
        if capture_arg:
            command += ['--max-fps', '30']
            command += ['--', capture_arg]
        result = subprocess.run(command,
                                env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = result.stdout + result.stderr
        print(output, end='')
        for folder, before in frozen.items():
            after = hashes(destination / folder)
            if folder == 'content/items':
                for name in FIXTURE_ITEMS:
                    if name not in before:
                        after.pop(name, None)
            if before != after:
                raise RuntimeError('gate changed copied shared inputs: ' + folder)
        if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
            raise RuntimeError(test + ' failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe')
    parser.add_argument('--test', choices=TESTS)
    captures = parser.add_mutually_exclusive_group()
    captures.add_argument('--visual', action='store_true', help='Forward+ inventory capture in the disposable project')
    captures.add_argument('--capture-active', action='store_true', help='Forward+ active-party captures in the disposable project')
    args = parser.parse_args()
    godot = args.godot.resolve()
    if godot.name.endswith('_console.exe'):
        godot = godot.with_name(godot.name.replace('_console.exe', '.exe'))
    capture_arg = '--visual' if args.visual else '--capture-active' if args.capture_active else None
    capture_test = ('test_equipment_layout.gd' if args.test == 'test_equipment_layout.gd' else 'test_inventory_equipment.gd') if args.visual else 'test_party_followers.gd'
    if capture_arg and args.test and args.test != capture_test:
        parser.error('capture option requires --test ' + capture_test)
    selected = (capture_test,) if capture_arg else (args.test,) if args.test else TESTS
    for test in selected:
        run_gate(godot, test, capture_arg)
    print('PASS independent party gates; historical content absent, shared inputs unchanged')


if __name__ == '__main__':
    main()
