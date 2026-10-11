"""Save relocation and pause/transition regressions in disposable native projects."""

from pathlib import Path
import shutil
import subprocess
import tempfile

from run_party_tests import ROOT, prepare_project as prepare_code

TESTS = ('test_retired_save_destination.gd', 'test_explore_pause_menu.gd',
         'test_map_transition.gd', 'test_combat_encounter_transition.gd', 'test_combat_defeat_retry.gd')


def prepare_project(destination):
    prepare_code(destination)
    for test in TESTS:
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    shutil.copyfile(ROOT / 'scenes/combat_lab.tscn', destination / 'scenes/combat_lab.tscn')
    folder = destination / 'content/action_scripts'
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'content/action_scripts/colored_crossing_victory.tres', folder / 'colored_crossing_victory.tres')


def main():
    engine = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
    for test in TESTS:
        with tempfile.TemporaryDirectory(prefix='ember-save-destination-') as temporary:
            destination = Path(temporary).resolve()
            prepare_project(destination)
            try:
                result = subprocess.run([str(engine), '--headless', '--path', str(destination), '--script', 'res://tools/' + test],
                                        capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=40)
            except subprocess.TimeoutExpired as error:
                for partial in (error.stdout, error.stderr):
                    if partial:
                        print(partial.decode('utf-8', 'replace') if isinstance(partial, bytes) else partial)
                raise
            output = result.stdout + result.stderr
            print(output, end='', flush=True)
            if result.returncode or 'ERROR:' in output or 'FAIL' in output or 'PASS' not in result.stdout:
                raise RuntimeError(test + ' failed')
    print('PASS native save destination gates; real saves/author scenes/JOI not used')


if __name__ == '__main__':
    main()
