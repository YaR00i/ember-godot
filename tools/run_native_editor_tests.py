"""Native editor dependency gate in a guarded disposable project."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_interaction_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes


TESTS = ("test_native_editor_dependencies.gd", "test_content_migration_report.gd", "test_content_migration_dashboard.gd")


def prepare_project(destination):
    prepare_code(destination)
    for test in TESTS:
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    (destination / '.editor-deps-test-sandbox').write_text('synthetic native assets only\n', encoding='utf-8')


def main():
    engine = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
    for test in TESTS:
        with tempfile.TemporaryDirectory(prefix='ember-native-editor-') as temporary:
            destination = Path(temporary).resolve()
            prepare_project(destination)
            frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'materials')}
            env = os.environ.copy()
            env['EMBER_EDITOR_DEPS_TEST_ROOT'] = destination.as_posix()
            result = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/' + test],
                                    env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=40)
            output = result.stdout + result.stderr
            print(output, end='')
            if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
                raise RuntimeError('native editor dependency gate failed')
            if any(hashes(destination / folder) != original for folder, original in frozen.items()):
                raise RuntimeError('editor gate modified copied shared sources')
    print('PASS detached native editor gate; author maps/models/prefabs and JOI not copied')


if __name__ == '__main__':
    main()
