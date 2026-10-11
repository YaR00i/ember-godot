"""Mixed editor gates using generated native fixtures, without author maps or JOI."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import shutil

from run_interaction_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes

TESTS = ('test_object_inspector_model.gd', 'test_object_inspector_panel.gd',
         'test_object_inspector_actions.gd', 'test_scene_edit_roundtrip.gd',
         'test_standalone_trigger_authoring.gd', 'test_quest_journal_authoring.gd',
         'test_graph_workspace.gd', 'test_map_visual_library.gd', 'test_voxel_surface_sculpt.gd', 'test_world_surface_projection.gd', 'test_voxel_prefab_rebuild.gd', 'test_diorama_materials.gd', 'test_surface_large_profile.gd', 'test_vox_axes_native.gd', 'test_native_perf_fixture.gd', 'test_graph_lifecycle.gd')


def prepare_project(destination):
    prepare_code(destination)
    arenas = destination / 'scenes/combat/arenas'
    arenas.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'scenes/combat/arenas/colored_crossing.tscn', arenas / 'colored_crossing.tscn')
    for name in ('qa_voxel_editor_edit_cost.gd', 'qa_voxel_editor_performance_ab.gd'):
        shutil.copyfile(ROOT / 'tools' / name, destination / 'tools' / name)
    for test in TESTS:
        shutil.copyfile(ROOT / 'tools' / test, destination / 'tools' / test)
    project = destination / 'project.godot'
    project.write_text(project.read_text(encoding='utf-8') + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/ember_surface_canvas/plugin.cfg")\n', encoding='utf-8')
    (destination / '.mixed-editor-test-sandbox').write_text('generated editor fixtures only\n', encoding='utf-8')


def run_gate(test):
    with tempfile.TemporaryDirectory(prefix='ember-mixed-editor-') as temporary:
        destination = Path(temporary).resolve()
        prepare_project(destination)
        frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'materials')}
        env = os.environ.copy()
        env['EMBER_INTERACTION_TEST_ROOT'] = destination.as_posix()
        command = [str(ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'), '--headless',
                   '--path', str(destination), '--script', 'res://tools/' + test]
        try:
            result = subprocess.run(command, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
        except subprocess.TimeoutExpired as error:
            for partial in (error.stdout, error.stderr):
                if partial: print(partial.decode('utf-8', 'replace') if isinstance(partial, bytes) else partial, flush=True)
            raise
        output = result.stdout + result.stderr
        print(output, end='', flush=True)
        accepted = 'PASS' in result.stdout or (test == 'test_surface_large_profile.gd' and '"errors": []' in result.stdout)
        if result.returncode or 'ERROR:' in output or 'FAIL' in output or not accepted:
            raise RuntimeError(test + ' failed')
        if any(hashes(destination / folder) != original for folder, original in frozen.items()):
            raise RuntimeError('mixed gate changed shared author inputs')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=TESTS)
    args = parser.parse_args()
    for test in (args.test,) if args.test else TESTS:
        run_gate(test)
    print('PASS mixed editor gates; author scenes/voxel sources/JOI absent')


if __name__ == '__main__':
    main()
