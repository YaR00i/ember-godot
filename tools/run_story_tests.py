"""Native action/dialogue authoring gates in a guarded disposable project."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_interaction_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes

TESTS = ('test_action_resource.gd', 'test_vn_dialogue_resource.gd',
         'test_dialogue_authoring.gd', 'test_action_chain_authoring.gd')


def prepare_project(destination):
    prepare_code(destination)
    for test in TESTS:
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    (destination / '.story-test-sandbox').write_text('neutral native story fixtures only\n', encoding='utf-8')


def environment(destination):
    result = os.environ.copy()
    result['EMBER_STORY_TEST_ROOT'] = destination.as_posix()
    result['EMBER_INTERACTION_TEST_ROOT'] = destination.as_posix()
    return result


def run_gate(engine, test):
    with tempfile.TemporaryDirectory(prefix='ember-story-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'content/combat', 'materials', 'assets/world_markers')}
        result = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/' + test],
                                env=environment(destination), capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = result.stdout + result.stderr
        print(output, end='')
        for folder, before in frozen.items():
            if before != hashes(destination / folder):
                raise RuntimeError('story gate changed copied inputs: ' + folder)
        if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
            raise RuntimeError(test + ' failed')


def run_pack_gate(engine):
    with tempfile.TemporaryDirectory(prefix='ember-story-pack-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        shutil.copyfile(ROOT / 'tools/test_story_catalog_pack.gd', destination / 'tools/test_story_catalog_pack.gd')
        build = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/test_story_catalog_pack.gd'],
                               env=environment(destination), capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = build.stdout + build.stderr
        print(output, end='')
        if build.returncode or 'ERROR:' in output or 'PASS build binary story pack' not in output:
            raise RuntimeError('story pack build failed')
        source = Path(next(line.removeprefix('STORY_PACK: ') for line in build.stdout.splitlines() if line.startswith('STORY_PACK: ')))
        empty = destination / 'source-free'
        empty.mkdir()
        pack = empty / 'stories.pck'
        shutil.copyfile(source, pack)
        read = subprocess.run([str(engine), '--headless', '--path', str(empty), '--main-pack', str(pack), '--script',
                               'res://tools/test_story_catalog_pack.gd', '--', '--read-pack'],
                              capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
        output = read.stdout + read.stderr
        print(output, end='')
        if read.returncode or 'ERROR:' in output or 'PASS story catalog PCK;' not in output:
            raise RuntimeError('binary story catalog gate failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=TESTS)
    args = parser.parse_args()
    engine = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
    for test in (args.test,) if args.test else TESTS:
        run_gate(engine, test)
    if not args.test:
        run_pack_gate(engine)
    print('PASS native story authoring gates; historical stories/cities/JOI absent')


if __name__ == '__main__':
    main()
