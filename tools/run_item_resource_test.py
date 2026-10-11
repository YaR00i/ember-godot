"""Native item authoring/catalog gate in a disposable project, without JOI."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_party_tests import ROOT, FIXTURE_ITEMS, prepare_project
from run_voxel_migration_tests import hashes


def main():
    with tempfile.TemporaryDirectory(prefix='ember-item-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        shutil.copyfile(ROOT / 'tools/test_item_resource.gd', destination / 'tools/test_item_resource.gd')
        shutil.copyfile(ROOT / 'tools/test_item_catalog_pack.gd', destination / 'tools/test_item_catalog_pack.gd')
        frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'content/combat', 'materials')}
        environment = os.environ.copy()
        environment['EMBER_PARTY_TEST_ROOT'] = destination.as_posix()
        result = subprocess.run([str(ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'), '--headless', '--path', str(destination),
                                 '--script', 'res://tools/test_item_resource.gd'], env=environment,
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = result.stdout + result.stderr
        print(output, end='')
        for folder, before in frozen.items():
            after = hashes(destination / folder)
            if folder == 'content/items':
                for name in (*FIXTURE_ITEMS, 'catalog_fixture_tonic.tres'):
                    if name not in before:
                        after.pop(name, None)
            if before != after:
                raise RuntimeError('gate changed copied author inputs: ' + folder)
        if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS native item Resource' not in result.stdout:
            raise RuntimeError('native item gate failed')
        print('PASS native item authoring isolation; copied author inputs unchanged')
        # Use a fresh project: authoring intentionally left extra fixture items.
    with tempfile.TemporaryDirectory(prefix='ember-item-pack-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        shutil.copyfile(ROOT / 'tools/test_item_catalog_pack.gd', destination / 'tools/test_item_catalog_pack.gd')
        environment['EMBER_PARTY_TEST_ROOT'] = destination.as_posix()
        engine = str(ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe')
        build = subprocess.run([engine, '--headless', '--path', str(destination), '--script', 'res://tools/test_item_catalog_pack.gd'],
                               env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = build.stdout + build.stderr
        print(output, end='')
        if build.returncode or 'ERROR:' in output or 'PASS build binary item/icon pack' not in output:
            raise RuntimeError('item pack build failed')
        pack = Path(next(line.removeprefix('ITEM_PACK: ') for line in build.stdout.splitlines() if line.startswith('ITEM_PACK: ')))
        # Fresh source-free directory and process: only the PCK provides res://.
        empty = destination / 'source-free'
        empty.mkdir()
        packed = empty / 'items.pck'
        shutil.copyfile(pack, packed)
        read = subprocess.run([engine, '--headless', '--path', str(empty), '--main-pack', str(packed), '--script',
                               'res://tools/test_item_catalog_pack.gd', '--', '--read-pack'],
                              capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = read.stdout + read.stderr
        print(output, end='')
        if read.returncode or 'ERROR:' in output or 'PASS item catalog PCK;' not in output:
            raise RuntimeError('binary item catalog gate failed')


if __name__ == '__main__':
    main()
