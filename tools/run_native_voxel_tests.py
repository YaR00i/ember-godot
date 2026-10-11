"""Native voxel catalog/shelf/preview gates, without cities or a JOI pack."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from run_interaction_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes

TESTS = ('test_native_voxel_catalog.gd', 'test_voxel_visual_library.gd')


def prepare_project(destination):
    prepare_code(destination)
    shutil.copytree(ROOT / 'content/voxel_models', destination / 'content/voxel_models')
    for test in TESTS:
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    (destination / '.voxel-native-test-sandbox').write_text('native author inputs frozen\n', encoding='utf-8')
    count = len(tuple((ROOT / 'content/voxel_models').glob('*.tres')))
    (destination / '.voxel-native-count').write_text(str(count), encoding='utf-8')
    # Keep three current prop derivatives, and their declared dependencies only.
    pending = [Path('prefabs/voxels/' + id + '.tscn') for id in
               ('vox_fan_crate_stack', 'vox_fan_barrel', 'vox_fan_anvil')]
    copied = set()
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        copied.add(relative)
        target = destination / relative
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        if relative.suffix in ('.tscn', '.tres'):
            text = (ROOT / relative).read_text(encoding='utf-8-sig')
            pending.extend(Path(path) for path in re.findall(r'path="res://([^"]+)"', text))


def execute(engine, destination, test, env=None, extra=()):
    result = subprocess.run([str(engine), '--headless', '--path', str(destination), *extra,
                             '--script', 'res://tools/' + test], env=env,
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=45)
    output = result.stdout + result.stderr
    print(output, end='', flush=True)
    if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
        raise RuntimeError(test + ' failed')
    return result.stdout


def main():
    engine = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
    frozen = hashes(ROOT / 'content/voxel_models')
    for test in TESTS:
        with tempfile.TemporaryDirectory(prefix='ember-native-voxel-') as temporary:
            destination = Path(temporary).resolve()
            prepare_project(destination)
            before = {folder: hashes(destination / folder) for folder in ('content/voxel_models', 'prefabs/voxels', 'materials')}
            env = os.environ.copy()
            env['EMBER_VOXEL_TEST_ROOT'] = destination.as_posix()
            output = execute(engine, destination, test, env)
            if any(hashes(destination / folder) != original for folder, original in before.items()):
                raise RuntimeError('native voxel gate modified copied author/derivative files')
            if test == 'test_native_voxel_catalog.gd':
                source = Path(next(line.removeprefix('VOXEL_PACK: ') for line in output.splitlines() if line.startswith('VOXEL_PACK: ')))
                empty = destination / 'source-free'
                empty.mkdir()
                pack = empty / 'voxels.pck'
                shutil.copyfile(source, pack)
                execute(engine, empty, test, extra=('--main-pack', str(pack)))
    if hashes(ROOT / 'content/voxel_models') != frozen:
        raise RuntimeError('working native voxel sources changed')
    print('PASS native voxel gates; current sources/derivatives frozen, historical cities/JOI absent')


if __name__ == '__main__':
    main()
