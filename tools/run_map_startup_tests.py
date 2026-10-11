"""Native startup and saved cutaway gates with poisoned/absent legacy maps."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_interaction_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes

TESTS = ('test_native_map_startup.gd', 'test_native_cutaway.gd')


def prepare_project(destination):
    prepare_code(destination)
    for test in TESTS:
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    (destination / '.map-startup-test-sandbox').write_text('user fixtures only\n', encoding='utf-8')


def main():
    engine = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
    for test in TESTS:
        with tempfile.TemporaryDirectory(prefix='ember-map-startup-') as temporary:
            destination = Path(temporary).resolve()
            prepare_project(destination)
            frozen = {folder: hashes(destination / folder) for folder in ('content', 'materials')}
            env = os.environ.copy()
            env['EMBER_MAP_STARTUP_TEST_ROOT'] = destination.as_posix()
            result = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/' + test],
                                    env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=40)
            output = result.stdout + result.stderr
            print(output, end='', flush=True)
            if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
                raise RuntimeError(test + ' failed')
            if any(hashes(destination / folder) != original for folder, original in frozen.items()):
                raise RuntimeError('startup changed copied shared sources')
    print('PASS native map startup gates; no historical maps/voxel libraries/JOI copied')


if __name__ == '__main__':
    main()
