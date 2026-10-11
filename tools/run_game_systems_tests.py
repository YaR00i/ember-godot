"""Native game-systems prototype gates in a disposable, author-data-frozen project."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from run_interaction_tests import ROOT, prepare_project
from run_voxel_migration_tests import hashes

ENGINE = ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'
REGRESSIONS = ('test_save_publication.gd', 'test_party_progression.gd',
               'test_combat_items.gd', 'test_combat_result_bridge.gd', 'test_combat_prototype.gd',
               'test_combat_status_resource.gd', 'test_combat_effect_library.gd',
               'test_combat_action_resource.gd', 'test_combat_grid.gd',
               'test_combat_action_plan.gd', 'test_combat_personal_actions.gd',
               'test_combat_unit_resource.gd', 'test_combat_ai_profile_resource.gd',
               'test_combat_loot_table_resource.gd', 'test_encounter_resource.gd')


def prepare(destination):
    prepare_project(destination)
    for folder in ('content/action_scripts', 'content/dialogues', 'scenes/combat/arenas'):
        shutil.copytree(ROOT / folder, destination / folder)
    shutil.copyfile(ROOT / 'scenes/combat_lab.tscn', destination / 'scenes/combat_lab.tscn')
    for name in ('test_game_systems_workspace.gd', 'test_game_systems_operations.gd', 'test_status_authoring.gd', 'test_combat_action_authoring.gd', 'test_combat_encounter_authoring.gd', 'test_game_systems_lab.gd', 'test_game_systems_library_check.gd', 'editor_test_game_systems.gd', *REGRESSIONS):
        source = ROOT / 'tools' / name
        if source.exists(): shutil.copyfile(source, destination / 'tools' / name)


def execute(project, args, env, timeout=180, expected_save_failures=False):
    result = subprocess.run([str(ENGINE), '--path', str(project), *args], env=env,
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout)
    output = result.stdout + result.stderr
    print(output, end='', flush=True)
    lines = output.splitlines()
    failed = any(line.startswith('FAIL') for line in lines)
    errors = [line for line in lines if line.startswith('ERROR:')]
    error_gate = 'ERROR:' in output
    if expected_save_failures:
        expected = {'EXPECTED SAVE FAILURE: ' + kind + '/' + fault
                    for kind in ('manual', 'autosave') for fault in ('open', 'short', 'preserve', 'publish', 'rollback')}
        observed = {line for line in lines if line.startswith('EXPECTED SAVE FAILURE:')}
        error_gate = (observed != expected or len(errors) != 10 or
                      any(not line.startswith('ERROR: ember save: cannot publish') for line in errors) or
                      'SCRIPT ERROR' in output)
    if result.returncode or error_gate or failed:
        raise RuntimeError('game systems gate failed')
    return output


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--editor', action='store_true')
    mode.add_argument('--operations', action='store_true')
    mode.add_argument('--regressions', action='store_true')
    mode.add_argument('--statuses', action='store_true')
    mode.add_argument('--actions', action='store_true')
    mode.add_argument('--encounters', action='store_true')
    mode.add_argument('--lab', action='store_true')
    mode.add_argument('--check', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ember-game-systems-') as temporary:
        project = Path(temporary).resolve()
        prepare(project)
        frozen = {folder: hashes(project / folder) for folder in ('content', 'scenes', 'materials')}
        env = os.environ.copy()
        env['EMBER_GAME_SYSTEMS_TEST_ROOT'] = project.as_posix()
        if args.regressions:
            for test in REGRESSIONS:
                output = execute(project, ['--headless', '--script', 'res://tools/' + test], env,
                                 expected_save_failures=test == 'test_save_publication.gd')
                if 'PASS' not in output: raise RuntimeError('regression did not complete: ' + test)
            output = 'PASS game systems related save/combat/progression regressions\n'
            print(output, end='')
        elif args.lab:
            config = project / 'project.godot'
            text = config.read_text(encoding='utf-8').replace('gl_compatibility', 'forward_plus')
            text += '\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=900\n'
            text = text.replace('config/name="EmberInteractionTests"', 'config/name="EmberLibraryLabTest"')
            config.write_text(text, encoding='utf-8')
            source = project / 'content/combat/encounters/colored_crossing_demo.tres'
            fixture = source.read_text(encoding='utf-8').replace('encounter_id = "colored_crossing_demo"', 'encounter_id = "library_lab_fixture"')
            import re
            fixture = re.sub(r'party_unit_ids = .*', 'party_unit_ids = PackedStringArray("mira")', fixture)
            fixture = re.sub(r'enemy_unit_ids = .*', 'enemy_unit_ids = PackedStringArray("wisp")', fixture)
            fixture = re.sub(r'victory_xp = .*', 'victory_xp = 9', fixture)
            (project / 'content/combat/encounters/library_lab_fixture.tres').write_text(fixture, encoding='utf-8')
            frozen = {folder: hashes(project / folder) for folder in ('content', 'scenes', 'materials')}
            execute(project, ['--headless', '--editor', '--import'], env)
            output = execute(project, ['--windowed', '--resolution', '1600x900', '--max-fps', '30', '--script', 'res://tools/test_game_systems_lab.gd', '--', '--ember-library-encounter=res://content/combat/encounters/library_lab_fixture.tres'], env)
        elif args.editor:
            for name in ('ember_import', 'ember_surface_canvas'):
                shutil.copyfile(ROOT / 'addons' / name / 'plugin.cfg', project / 'addons' / name / 'plugin.cfg')
            execute(project, ['--headless', '--editor', '--import'], env)
            gate = project / 'addons/game_systems_gate'
            gate.mkdir()
            shutil.copyfile(ROOT / 'tools/editor_test_game_systems.gd', gate / 'plugin.gd')
            (gate / 'plugin.cfg').write_text('[plugin]\nname="Game systems gate"\ndescription="Disposable UI gate"\nauthor="Ember"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
            config = project / 'project.godot'
            text = config.read_text(encoding='utf-8').replace('gl_compatibility', 'forward_plus')
            text += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/ember_import/plugin.cfg", "res://addons/game_systems_gate/plugin.cfg")\n'
            config.write_text(text, encoding='utf-8')
            output = execute(project, ['--editor', '--windowed', '--resolution', '1600x900', '--max-fps', '30'], env, timeout=240)
        else:
            test = 'test_game_systems_library_check.gd' if args.check else 'test_combat_encounter_authoring.gd' if args.encounters else 'test_combat_action_authoring.gd' if args.actions else 'test_status_authoring.gd' if args.statuses else 'test_game_systems_operations.gd' if args.operations else 'test_game_systems_workspace.gd'
            output = execute(project, ['--headless', '--script', 'res://tools/' + test], env)
        if 'PASS game systems' not in output: raise RuntimeError('gate did not complete')
        if any(hashes(project / folder) != before for folder, before in frozen.items()):
            raise RuntimeError('prototype changed copied author data')
        print('PASS game systems sandbox; gameplay data unchanged, live editor/cache/saves not used')


if __name__ == '__main__':
    main()
