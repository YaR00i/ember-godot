"""World-action quest authoring and transactions, in a disposable Forward+ project."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile
from run_mixed_editor_tests import prepare_project

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=('test_quest_world_actions.gd', 'test_quest_authoring_journey.gd',
                                          'test_quest_purchase.gd', 'test_quest_handover.gd', 'test_world_strike.gd'),
                        default='test_quest_world_actions.gd')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ember-quest-world-') as folder:
        project = Path(folder)
        prepare_project(project)
        shutil.copytree(ROOT / 'content/recipes', project / 'content/recipes', dirs_exist_ok=True)
        shutil.copyfile(ROOT / 'content/dialogues/chapter1_fishing_cooked.tres',
                        project / 'content/dialogues/chapter1_fishing_cooked.tres')
        shutil.copyfile(ROOT / 'tools/test_quest_world_actions.gd', project / 'tools/test_quest_world_actions.gd')
        env = os.environ.copy()
        env['EMBER_INTERACTION_TEST_ROOT'] = project.as_posix()
        godot = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
        imported = subprocess.run([str(godot), '--headless', '--editor', '--path', str(project), '--quit'],
                                  capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        if imported.returncode or 'SCRIPT ERROR:' in imported.stdout + imported.stderr:
            print(imported.stdout + imported.stderr)
            raise SystemExit(1)
        result = subprocess.run([str(godot), '--path', str(project), '--script', 'res://tools/' + args.test,
                                 '--rendering-method', 'forward_plus', '--windowed', '--resolution', '1280x800', '--max-fps', '30'],
                                env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=150)
        print(result.stdout + result.stderr)
        if result.returncode or 'ERROR:' in result.stdout + result.stderr or 'PASS' not in result.stdout:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
