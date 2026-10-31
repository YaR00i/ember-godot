"""Mixed editor gates using generated native fixtures, without author maps or JOI."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import shutil

from run_interaction_tests import ROOT, prepare_project as prepare_code
from run_voxel_migration_tests import hashes

TESTS = ('test_cuttable_grass.gd', 'test_tree_leaf_palette.gd', 'test_leaf_pile.gd', 'test_world_strike.gd', 'test_physical_crates.gd', 'test_mechanism_circuits.gd', 'test_pressure_gate.gd', 'test_quest_conversation_draft.gd', 'test_quest_authoring_journey.gd', 'test_quest_npc_options.gd', 'test_quest_harbor_errand.gd', 'test_quest_reach_zone.gd', 'test_object_inspector_model.gd', 'test_object_inspector_panel.gd',
         'test_object_inspector_actions.gd', 'test_scene_edit_roundtrip.gd',
         'test_standalone_trigger_authoring.gd', 'test_quest_journal_authoring.gd',
         'test_graph_workspace.gd', 'test_quest_graph_workflow.gd', 'test_quest_object_zone.gd', 'test_quest_crate_placement.gd', 'test_map_visual_library.gd', 'test_voxel_surface_sculpt.gd', 'test_world_surface_projection.gd', 'test_voxel_prefab_rebuild.gd', 'test_diorama_materials.gd', 'test_surface_large_profile.gd', 'test_vox_axes_native.gd', 'test_native_perf_fixture.gd', 'test_graph_lifecycle.gd')


TESTS += ('test_fruit_tree.gd', 'test_world_item_physics.gd', 'test_berry_bush.gd')
TESTS += ('test_combat_action_plan.gd','test_combat_vertical_profile.gd')


def prepare_project(destination):
    prepare_code(destination)
    npc_assets = destination / 'prefabs/items'
    npc_assets.mkdir(parents=True, exist_ok=True)
    for name in ('shore_keeper.tscn', 'shore_keeper_visual.tscn', 'quest_crate.tscn', 'physical_crates.tscn', 'quest_crate_break.scn', 'autumn_leaf_pile.scn', 'autumn_leaf_scatter.scn', 'empty_bottle.tscn', 'cuttable_grass.scn', 'cut_grass_scatter.scn', 'herb_sprig.scn'):
        shutil.copyfile(ROOT / 'prefabs/items' / name, npc_assets / name)
    grass_material = npc_assets / 'materials/cuttable_grass.res'
    grass_material.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'prefabs/items/materials/cuttable_grass.res', grass_material)
    shutil.copyfile(ROOT / 'prefabs/items/apple.scn', npc_assets / 'apple.scn')
    for name in ('forest_berry.scn', 'berry_bush.scn'):
        shutil.copyfile(ROOT / 'prefabs/items' / name, npc_assets / name)
    source = destination / 'content/voxel_models/quest_carry_crate.tres'
    source.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'content/voxel_models/quest_carry_crate.tres', source)
    texture = destination / 'content/material_studies/foliage/autumn_leaf_atlas_v2.res'
    texture.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'content/material_studies/foliage/autumn_leaf_atlas_v2.res', texture)
    mesh = destination / 'prefabs/voxels/meshes/quest_carry_crate_block.res'
    mesh.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'prefabs/voxels/meshes/quest_carry_crate_block.res', mesh)
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
        if test == 'test_berry_bush.gd':
            for relative in ('content/voxel_models/vox_forest_berry_bush.tres',
                             'content/editor/voxel_generators/vox_forest_berry_bush.tres',
                             'prefabs/voxels/vox_forest_berry_bush.tscn',
                             'content/material_studies/trees/leaf_cluster_atlas_v8_separate_leaves.png',
                             'content/material_studies/trees/bark_species_v1/oak-v3-painted.png'):
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
        if test == 'test_fruit_tree.gd':
            for relative in ('prefabs/items/fruit_tree.scn', 'prefabs/voxels/vox_painted_oak.tscn',
                             'prefabs/voxels/meshes/vox_painted_oak_block.res'):
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
        if test == 'test_tree_leaf_palette.gd':
            for relative in ('content/editor/voxel_generators/vox_painted_maple.tres',
                             'content/voxel_models/vox_painted_maple.tres',
                             'content/material_studies/trees/maple_v1/leaf-atlas-v2-rooted.png',
                             'content/material_studies/trees/bark_species_v1/maple-v1.png'):
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
        frozen = {folder: hashes(destination / folder) for folder in ('content/items', 'content/item_icons', 'materials')}
        env = os.environ.copy()
        env['EMBER_INTERACTION_TEST_ROOT'] = destination.as_posix()
        command = [str(ROOT / 'tools/godot/Godot_v4.7.2-stable_win64.exe'), '--headless',
                   '--path', str(destination), '--script', 'res://tools/' + test]
        if test in ('test_tree_leaf_palette.gd', 'test_cuttable_grass.gd', 'test_fruit_tree.gd', 'test_world_item_physics.gd', 'test_berry_bush.gd'):
            # Shader defaults and palette colour need the real Forward+ renderer.
            command.remove('--headless')
            command.extend(['--rendering-method', 'forward_plus', '--windowed',
                            '--resolution', '1280x800', '--max-fps', '60', '--quit-after', '2400'])
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
