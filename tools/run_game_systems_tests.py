"""Native game-systems prototype gates in a disposable, author-data-frozen project."""
import argparse
import json
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
    for name in ('test_game_systems_workspace.gd', 'test_game_systems_operations.gd', 'test_status_authoring.gd', 'test_combat_action_authoring.gd', 'test_combat_encounter_authoring.gd', 'test_game_systems_lab.gd', 'test_game_systems_lab_setup.gd', 'test_game_systems_lab_presets.gd', 'test_game_systems_library_check.gd', 'test_game_systems_usage.gd', 'editor_test_game_systems.gd', 'editor_test_game_systems_cycle.gd', 'test_game_systems_cycle.gd', 'test_combat_lab.gd', 'test_combat_arena_scenes.gd', 'test_combat_prebattle_deployment.gd', 'test_combat_vertical_view.gd', 'test_combat_vertical_animation.gd', *REGRESSIONS):
        source = ROOT / 'tools' / name
        if source.exists(): shutil.copyfile(source, destination / 'tools' / name)
    for name in ('test_combat_encounter_transition.gd', 'test_combat_defeat_retry.gd', 'editor_test_game_systems_stability.gd', 'test_editor_filesystem.gd', 'test_combat_action_conditions.gd', 'test_combat_equipment_conditions.gd', 'test_game_start_authoring.gd'):
        shutil.copyfile(ROOT / 'tools' / name, destination / 'tools' / name)


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
        raise RuntimeError('game systems gate failed (Godot exit code %s)' % result.returncode)
    return output


def full_cycle(project, env):
    """Three processes share saved Resources and private fixture saves only."""
    (project / '.game-systems-cycle-sandbox').write_text('disposable author/play/fresh-load fixtures only\n', encoding='utf-8')
    (project / 'scenes/combat/arenas/cycle_arena.tscn').write_text('''[gd_scene load_steps=4 format=3]
[ext_resource type="PackedScene" path="res://scenes/combat/arenas/thaw_keeper.tscn" id="1_arena"]
[sub_resource type="StandardMaterial3D" id="material"]
albedo_color = Color(0.8, 0.18, 0.65, 1)
[sub_resource type="BoxMesh" id="mesh"]
material = SubResource("material")
size = Vector3(0.75, 1.4, 0.75)
[node name="CycleArena" instance=ExtResource("1_arena")]
metadata/cycle_arena = true
[node name="CameraRig" parent="." index="5"]
pitch_degrees = 35.0
fov = 44.0
[node name="CombatCamera3D" parent="CameraRig" index="0"]
fov = 44.0
[node name="CombatKeyLight" parent="." index="1"]
light_color = Color(0.9, 0.8, 1, 1)
[node name="DecorPreviewCamera" type="Camera3D" parent="."]
current = true
[node name="AuthoredArenaMarker" type="MeshInstance3D" parent="."]
position = Vector3(-1.1, 0.7, 1.2)
mesh = SubResource("mesh")
''', encoding='utf-8')
    for name in ('ember_import', 'ember_surface_canvas'):
        shutil.copyfile(ROOT / 'addons' / name / 'plugin.cfg', project / 'addons' / name / 'plugin.cfg')
    config = project / 'project.godot'
    text = config.read_text(encoding='utf-8').replace('gl_compatibility', 'forward_plus')
    text = text.replace('config/name="EmberInteractionTests"', 'config/name="EmberSystemsCycle-' + project.name + '"')
    text += '\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=900\n'
    config.write_text(text, encoding='utf-8')
    execute(project, ['--headless', '--editor', '--import'], env)
    gate = project / 'addons/game_systems_cycle_gate'
    gate.mkdir()
    shutil.copyfile(ROOT / 'tools/editor_test_game_systems_cycle.gd', gate / 'plugin.gd')
    (gate / 'plugin.cfg').write_text('[plugin]\nname="Game systems full cycle gate"\ndescription="Disposable author/play/load"\nauthor="Ember"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
    config.write_text(text + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/ember_import/plugin.cfg", "res://addons/game_systems_cycle_gate/plugin.cfg")\n', encoding='utf-8')
    original_mira = (project / 'content/combat/units/mira.tres').read_bytes()
    original_start = (project / 'content/game_start/default.tres').read_bytes()
    manifest = None
    try:
        author = execute(project, ['--editor', '--windowed', '--resolution', '1600x900', '--max-fps', '30'], env, timeout=180)
        if 'PASS game systems cycle author' not in author: raise RuntimeError('cycle author did not complete')
        manifest = json.loads((project / '.game-systems-cycle.json').read_text(encoding='utf-8'))
        config.write_text(text, encoding='utf-8')  # Runtime receives no editor gate/plugin.
        command = ['--windowed', '--resolution', '1600x900', '--max-fps', '30', '--script', 'res://tools/test_game_systems_cycle.gd', '--']
        played = execute(project, command + ['--cycle-play'], env)
        loaded = execute(project, command + ['--cycle-load'], env)
        if 'PASS game systems cycle play' not in played or 'PASS game systems cycle load' not in loaded:
            raise RuntimeError('cycle runtime did not complete')
    finally:
        (project / 'content/combat/units/mira.tres').write_bytes(original_mira)
        (project / 'content/game_start/default.tres').write_bytes(original_start)
        if manifest:
            for source in manifest['hashes']:
                relative = source.removeprefix('res://')
                target = (project / relative).resolve()
                if not target.is_relative_to(project) or target not in (project / 'content/combat/units/mira.tres', project / 'content/game_start/default.tres') and not target.name.startswith('cycle_'):
                    raise RuntimeError('unexpected cycle cleanup target')
                if target.name.startswith('cycle_'): target.unlink(missing_ok=True)
    return 'PASS game systems full author/play/fresh-load cycle'


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--editor', action='store_true')
    mode.add_argument('--stability', action='store_true')
    mode.add_argument('--operations', action='store_true')
    mode.add_argument('--regressions', action='store_true')
    mode.add_argument('--statuses', action='store_true')
    mode.add_argument('--actions', action='store_true')
    mode.add_argument('--conditions', action='store_true')
    mode.add_argument('--gear-conditions', action='store_true')
    mode.add_argument('--start', action='store_true')
    mode.add_argument('--start-editor', action='store_true')
    mode.add_argument('--encounters', action='store_true')
    mode.add_argument('--lab', action='store_true')
    mode.add_argument('--arena', action='store_true')
    mode.add_argument('--lab-setup', action='store_true')
    mode.add_argument('--presets', action='store_true')
    mode.add_argument('--presets-editor', action='store_true')
    mode.add_argument('--cycle', action='store_true')
    mode.add_argument('--usage', action='store_true')
    mode.add_argument('--check', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='ember-game-systems-') as temporary:
        project = Path(temporary).resolve()
        prepare(project)
        frozen = {folder: hashes(project / folder) for folder in ('content', 'scenes', 'materials')}
        env = os.environ.copy()
        env['EMBER_GAME_SYSTEMS_TEST_ROOT'] = project.as_posix()
        if args.cycle:
            output = full_cycle(project, env)
            print(output)
        elif args.presets:
            config = project / 'project.godot'
            text = config.read_text(encoding='utf-8').replace('config/name="EmberInteractionTests"', 'config/name="EmberLabPresets-' + project.name + '"').replace('gl_compatibility', 'forward_plus')
            text += '\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=900\n'
            config.write_text(text, encoding='utf-8')
            execute(project, ['--headless', '--editor', '--import'], env)
            command = ['--headless', '--script', 'res://tools/test_game_systems_lab_presets.gd', '--']
            execute(project, command + ['--preset-write'], env)
            execute(project, command + ['--preset-reopen'], env)
            manifest = json.loads((project / '.lab-presets-gate.json').read_text(encoding='utf-8'))
            output = execute(project, ['--windowed', '--resolution', '1600x900', '--max-fps', '30', '--script', 'res://tools/test_game_systems_lab_presets.gd', '--', '--preset-play', '--ember-library-encounter=res://content/combat/encounters/colored_crossing_demo.tres', '--ember-library-setup=' + manifest['request']], env)
        elif args.regressions:
            for test in REGRESSIONS:
                output = execute(project, ['--headless', '--script', 'res://tools/' + test], env,
                                 expected_save_failures=test == 'test_save_publication.gd')
                if 'PASS' not in output: raise RuntimeError('regression did not complete: ' + test)
            output = 'PASS game systems related save/combat/progression regressions\n'
            print(output, end='')
        elif args.arena:
            config = project / 'project.godot'
            config.write_text(config.read_text(encoding='utf-8').replace('gl_compatibility', 'forward_plus') + '\n[display]\nwindow/size/viewport_width=1600\nwindow/size/viewport_height=900\n', encoding='utf-8')
            execute(project, ['--headless', '--editor', '--import'], env)
            for test in ('test_combat_encounter_transition.gd', 'test_combat_defeat_retry.gd', 'test_combat_lab.gd', 'test_combat_arena_scenes.gd', 'test_combat_prebattle_deployment.gd', 'test_combat_vertical_view.gd', 'test_combat_vertical_animation.gd'):
                output = execute(project, ['--windowed', '--resolution', '1600x900', '--max-fps', '30', '--script', 'res://tools/' + test], env)
                if 'PASS' not in output: raise RuntimeError('arena regression did not complete: ' + test)
            output = 'PASS game systems arena shell/projection/deployment/camera/animation regressions\n'
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
            fixture = fixture.replace('res://scenes/combat/arenas/colored_crossing.tscn', 'res://scenes/combat/arenas/library_arena_fixture.tscn')
            (project / 'scenes/combat/arenas/library_arena_fixture.tscn').write_text('''[gd_scene load_steps=4 format=3]
[ext_resource type="PackedScene" path="res://scenes/combat/arenas/thaw_keeper.tscn" id="1_arena"]
[sub_resource type="StandardMaterial3D" id="material"]
albedo_color = Color(0.8, 0.18, 0.65, 1)
[sub_resource type="BoxMesh" id="mesh"]
material = SubResource("material")
size = Vector3(0.75, 1.4, 0.75)
[node name="LibraryArenaFixture" instance=ExtResource("1_arena")]
metadata/library_arena_fixture = true
[node name="script" type="Node3D" parent="."]
[node name="DecorPreviewCamera" type="Camera3D" parent="."]
current = true
[node name="AuthoredArenaMarker" type="MeshInstance3D" parent="."]
position = Vector3(-1.1, 0.7, 1.2)
mesh = SubResource("mesh")
''', encoding='utf-8')
            (project / 'content/combat/encounters/library_lab_fixture.tres').write_text(fixture, encoding='utf-8')
            (project / 'scenes/combat/arenas/library_invalid_arena.tscn').write_text('[gd_scene format=3]\n[node name="InvalidArena" type="Control"]\n', encoding='utf-8')
            bad_fixture = fixture.replace('encounter_id = "library_lab_fixture"', 'encounter_id = "library_lab_bad_arena"').replace('library_arena_fixture.tscn', 'library_invalid_arena.tscn')
            (project / 'content/combat/encounters/library_lab_bad_arena.tres').write_text(bad_fixture, encoding='utf-8')
            (project / 'tools/fixtures/arena_validation_only.gd').write_text('''extends "res://scripts/prototypes/ember_combat_grid_3d_world.gd"
func _init() -> void:
    var file := FileAccess.open("user://arena-validation-instantiated-%d" % OS.get_process_id(), FileAccess.WRITE)
    file.store_string("instantiated")
''', encoding='utf-8')
            (project / 'scenes/combat/arenas/library_validation_only.tscn').write_text('''[gd_scene load_steps=3 format=3]
[ext_resource type="PackedScene" path="res://scenes/combat/arenas/thaw_keeper.tscn" id="1_arena"]
[ext_resource type="Script" path="res://tools/fixtures/arena_validation_only.gd" id="2_script"]
[node name="ValidationOnly" instance=ExtResource("1_arena")]
script = ExtResource("2_script")
''', encoding='utf-8')
            frozen = {folder: hashes(project / folder) for folder in ('content', 'scenes', 'materials')}
            execute(project, ['--headless', '--editor', '--import'], env)
            output = execute(project, ['--windowed', '--resolution', '1600x900', '--max-fps', '30', '--script', 'res://tools/test_game_systems_lab.gd', '--', '--ember-library-encounter=res://content/combat/encounters/library_lab_fixture.tres'], env)
            request_dir = Path(os.environ['APPDATA']) / 'EmberLibraryLabTest/ember-library-lab/requests'
            request_dir.mkdir(parents=True, exist_ok=True)
            request = request_dir / (project.name + '.json')
            setup = {'party': {'mira': {'level': 9, 'equipment': {'weapon': None, 'armor': 'traveler_tunic', 'shoes': None, 'accessory1': None, 'accessory2': None}}}, 'inventory': {'herb': 3}}
            request.write_text(json.dumps({'version': 1, 'encounterPath': 'res://content/combat/encounters/library_lab_fixture.tres', 'setup': setup}), encoding='utf-8')
            try:
                output = execute(project, ['--windowed', '--resolution', '1600x900', '--max-fps', '30', '--script', 'res://tools/test_game_systems_lab.gd', '--', '--ember-library-encounter=res://content/combat/encounters/library_lab_fixture.tres', '--ember-library-setup=' + request.as_posix()], env)
                if request.exists(): raise RuntimeError('runtime did not consume transient setup request')
            finally:
                request.unlink(missing_ok=True)
        elif args.editor or args.presets_editor or args.stability or args.start_editor:
            if args.presets_editor: env['EMBER_GAME_SYSTEMS_EDITOR_FOCUS'] = 'presets'
            if args.start_editor: env['EMBER_GAME_SYSTEMS_EDITOR_FOCUS'] = 'start'
            if args.stability:
                env['EMBER_STABILITY_CYCLES'] = '12'
                execute(project, ['--headless', '--script', 'res://tools/test_editor_filesystem.gd'], env)
            for name in ('ember_import', 'ember_surface_canvas'):
                shutil.copyfile(ROOT / 'addons' / name / 'plugin.cfg', project / 'addons' / name / 'plugin.cfg')
            execute(project, ['--headless', '--editor', '--import'], env)
            gate = project / 'addons/game_systems_gate'
            gate.mkdir()
            shutil.copyfile(ROOT / 'tools' / ('editor_test_game_systems_stability.gd' if args.stability else 'editor_test_game_systems.gd'), gate / 'plugin.gd')
            (gate / 'plugin.cfg').write_text('[plugin]\nname="Game systems gate"\ndescription="Disposable UI gate"\nauthor="Ember"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
            config = project / 'project.godot'
            text = config.read_text(encoding='utf-8').replace('gl_compatibility', 'forward_plus')
            text += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/ember_import/plugin.cfg", "res://addons/game_systems_gate/plugin.cfg")\n'
            config.write_text(text, encoding='utf-8')
            output = execute(project, ['--editor', '--windowed', '--resolution', '1600x900', '--max-fps', '30'], env, timeout=240)
        else:
            if args.start:
                output = execute(project, ['--headless', '--script', 'res://tools/test_game_start_authoring.gd'], env)
            elif args.gear_conditions:
                output = execute(project, ['--headless', '--script', 'res://tools/test_combat_equipment_conditions.gd'], env)
            elif args.conditions:
                output = execute(project, ['--headless', '--script', 'res://tools/test_combat_action_conditions.gd'], env)
            else:
                test = 'test_game_systems_usage.gd' if args.usage else 'test_game_systems_lab_setup.gd' if args.lab_setup else 'test_game_systems_library_check.gd' if args.check else 'test_combat_encounter_authoring.gd' if args.encounters else 'test_combat_action_authoring.gd' if args.actions else 'test_status_authoring.gd' if args.statuses else 'test_game_systems_operations.gd' if args.operations else 'test_game_systems_workspace.gd'
                output = execute(project, ['--headless', '--script', 'res://tools/' + test], env)
        if 'PASS game systems' not in output: raise RuntimeError('gate did not complete')
        if any(hashes(project / folder) != before for folder, before in frozen.items()):
            raise RuntimeError('prototype changed copied author data')
        print('PASS game systems sandbox; gameplay data unchanged, live editor/cache/saves not used')


if __name__ == '__main__':
    main()
