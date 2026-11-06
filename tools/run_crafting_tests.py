"""Focused recipe/UI checks in a disposable native project; never imports the working checkout."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile
from run_chapter1_blockout_tests import prepare

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fixture', type=Path)
    parser.add_argument('--headless', action='store_true')
    args = parser.parse_args()
    if args.fixture:
        execute(args.fixture, args.headless)
    else:
        with tempfile.TemporaryDirectory(prefix='ember-crafting-') as folder:
            project = Path(folder)
            prepare(ROOT, project)
            execute(project, args.headless)

def execute(project, headless):
    if project.resolve() == ROOT.resolve() or not (project / '.interaction-test-sandbox').exists():
        raise SystemExit('REFUSED: needs disposable interaction fixture')
    for folder in ('scripts', 'content/recipes'):
        shutil.copytree(ROOT / folder, project / folder, dirs_exist_ok=True)
    for name in ('crafting_workbench.tscn', 'cooking_station.tscn'):
        shutil.copyfile(ROOT / 'prefabs/items' / name, project / 'prefabs/items' / name)
    for name in ('chapter1_home.tscn', 'chapter1_estate.tscn'):
        shutil.copyfile(ROOT / 'scenes' / name, project / 'scenes' / name)
    shutil.copyfile(ROOT / 'tools/test_crafting.gd', project / 'tools/test_crafting.gd')
    godot = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    # Existing code-copy helpers have no class cache; import only this disposable project.
    imported = subprocess.run([str(godot), '--headless', '--editor', '--path', str(project), '--quit'], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
    if imported.returncode or 'SCRIPT ERROR:' in imported.stdout + imported.stderr:
        print(imported.stdout + imported.stderr); raise SystemExit(1)
    command = [str(godot), '--path', str(project), '--script', 'res://tools/test_crafting.gd']
    command += ['--headless'] if headless else ['--rendering-method', 'forward_plus', '--windowed', '--resolution', '1280x800', '--max-fps', '30']
    result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=150)
    print(result.stdout + result.stderr)
    if result.returncode or 'ERROR:' in result.stdout + result.stderr or 'CRAFTING PASS' not in result.stdout:
        raise SystemExit(1)

if __name__ == '__main__': main()
