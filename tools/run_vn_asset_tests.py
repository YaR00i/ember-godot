"""Guarded native VN import, visual picker and binary descriptor PCK gates."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_interaction_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes

TESTS = ('test_vn_background_library.gd', 'test_vn_portrait_library.gd', 'test_visual_library.gd')
FOLDERS = ('content/vn_backgrounds', 'content/vn_portraits', 'assets/vn_backgrounds', 'assets/vn_portraits')


def prepare_project(destination):
    prepare_code(destination)
    for folder in FOLDERS:
        if (ROOT / folder).exists():
            shutil.copytree(ROOT / folder, destination / folder)
        else:
            (destination / folder).mkdir(parents=True)
    for test in (*TESTS, 'test_vn_asset_pack.gd'):
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    (destination / '.vn-test-sandbox').write_text('native VN writes in disposable project only\n', encoding='utf-8')


def execute(engine, destination, test, environment=None, extra=()):
    result = subprocess.run([str(engine), '--headless', '--path', str(destination), *extra,
                             '--script', 'res://tools/' + test], env=environment,
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=45)
    output = result.stdout + result.stderr
    print(output, end='')
    if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
        raise RuntimeError(test + ' failed')
    return result.stdout


def main():
    engine = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
    frozen = {folder: hashes(ROOT / folder) for folder in FOLDERS}
    for test in (*TESTS, 'test_vn_asset_pack.gd'):
        with tempfile.TemporaryDirectory(prefix='ember-vn-') as temporary:
            destination = Path(temporary).resolve()
            prepare_project(destination)
            env = os.environ.copy()
            env['EMBER_VN_TEST_ROOT'] = destination.as_posix()
            before = {folder: hashes(destination / folder) for folder in FOLDERS}
            output = execute(engine, destination, test, env)
            for folder, original in before.items():
                after = hashes(destination / folder)
                if any(after.get(name) != digest for name, digest in original.items()):
                    raise RuntimeError('VN test changed existing copied asset: ' + folder)
            if test == 'test_vn_asset_pack.gd':
                source = Path(next(line.removeprefix('VN_PACK: ') for line in output.splitlines() if line.startswith('VN_PACK: ')))
                empty = destination / 'source-free'
                empty.mkdir()
                pack = empty / 'vn.pck'
                shutil.copyfile(source, pack)
                # Reader detects source-free mode through the PCK-only marker.
                execute(engine, empty, test, extra=('--main-pack', str(pack)))
                # Import only in this disposable checkout; remove raw source
                # images from a second PCK to exercise exported .ctex paths.
                imported = subprocess.run([str(engine), '--headless', '--path', str(destination), '--editor', '--import'],
                                          env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
                import_output = imported.stdout + imported.stderr
                if imported.returncode or 'ERROR:' in import_output:
                    print(import_output)
                    raise RuntimeError('disposable VN image import failed')
                build = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/' + test,
                                        '--', '--build-imported'], env=env, capture_output=True, text=True,
                                       encoding='utf-8', errors='replace', timeout=45)
                print(build.stdout + build.stderr, end='')
                if build.returncode or 'ERROR:' in build.stderr or 'PASS' not in build.stdout:
                    raise RuntimeError('imported VN pack build failed')
                imported_source = Path(next(line.removeprefix('VN_PACK: ') for line in build.stdout.splitlines() if line.startswith('VN_PACK: ')))
                shutil.copyfile(imported_source, pack)
                execute(engine, empty, test, extra=('--main-pack', str(pack)))
    if any(hashes(ROOT / folder) != original for folder, original in frozen.items()):
        raise RuntimeError('working VN author assets changed')
    print('PASS native VN gates; original author assets unchanged; JOI absent')


if __name__ == '__main__':
    main()
