"""Check current retained catalogs and saved historical progress in isolation."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_interaction_tests import ROOT, prepare_project
from run_voxel_migration_tests import hashes


def main():
    with tempfile.TemporaryDirectory(prefix='ember-retired-content-') as temporary:
        project = Path(temporary).resolve()
        prepare_project(project)
        folders = ('content/action_scripts', 'content/dialogues', 'content/quests',
                   'content/shops', 'content/voxel_models', 'content/world_surfaces')
        for folder in folders:
            shutil.copytree(ROOT / folder, project / folder)
        frozen = {folder: hashes(project / folder) for folder in (*folders, 'content/items', 'content/item_icons', 'materials')}
        shutil.copyfile(ROOT / 'tools/test_retired_content_catalogs.gd', project / 'tools/test_retired_content_catalogs.gd')
        result = subprocess.run([str(ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'), '--headless', '--path', str(project),
                                 '--script', 'res://tools/test_retired_content_catalogs.gd'],
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=40)
        output = result.stdout + result.stderr
        print(output, end='')
        if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
            raise RuntimeError('retired content gate failed')
        if any(hashes(project / folder) != before for folder, before in frozen.items()):
            raise RuntimeError('catalog gate changed native inputs')
        print('PASS actual catalog retirement; source hashes unchanged, real saves/author scenes/JOI not used')


if __name__ == '__main__':
    main()
