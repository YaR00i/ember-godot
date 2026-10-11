"""Native shop authoring and persistence gates, isolated from cities and JOI."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_party_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes

TESTS = ('test_shop_resource.gd', 'test_shop_persistence.gd')


def prepare_project(destination):
    prepare_code(destination)
    for test in TESTS:
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    (destination / '.shop-test-sandbox').write_text('neutral native shop fixtures only\n', encoding='utf-8')


def run_gate(engine, test):
    with tempfile.TemporaryDirectory(prefix='ember-shop-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'content/combat', 'materials')}
        environment = os.environ.copy()
        environment['EMBER_SHOP_TEST_ROOT'] = destination.as_posix()
        result = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/' + test],
                                env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = result.stdout + result.stderr
        print(output, end='')
        for folder, before in frozen.items():
            after = hashes(destination / folder)
            if folder == 'content/items':
                after.pop('shop_fixture_key.tres', None)
            if before != after:
                raise RuntimeError('shop gate changed copied shared inputs: ' + folder)
        if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
            raise RuntimeError(test + ' failed')


def run_pack_gate(engine):
    with tempfile.TemporaryDirectory(prefix='ember-shop-pack-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        shutil.copyfile(ROOT / 'tools/test_shop_catalog_pack.gd', destination / 'tools/test_shop_catalog_pack.gd')
        environment = os.environ.copy()
        environment['EMBER_SHOP_TEST_ROOT'] = destination.as_posix()
        build = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/test_shop_catalog_pack.gd'],
                               env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = build.stdout + build.stderr
        print(output, end='')
        if build.returncode or 'ERROR:' in output or 'PASS build binary shop pack' not in output:
            raise RuntimeError('shop pack build failed')
        source = Path(next(line.removeprefix('SHOP_PACK: ') for line in build.stdout.splitlines() if line.startswith('SHOP_PACK: ')))
        empty = destination / 'source-free'
        empty.mkdir()
        pack = empty / 'shops.pck'
        shutil.copyfile(source, pack)
        read = subprocess.run([str(engine), '--headless', '--path', str(empty), '--main-pack', str(pack), '--script',
                               'res://tools/test_shop_catalog_pack.gd', '--', '--read-pack'],
                              capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = read.stdout + read.stderr
        print(output, end='')
        if read.returncode or 'ERROR:' in output or 'PASS shop catalog PCK;' not in output:
            raise RuntimeError('binary shop catalog gate failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=TESTS)
    args = parser.parse_args()
    engine = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
    for test in (args.test,) if args.test else TESTS:
        run_gate(engine, test)
    if not args.test:
        run_pack_gate(engine)
    print('PASS independent native shop gates; historical shops/JSON absent, copied inputs unchanged')


if __name__ == '__main__':
    main()
