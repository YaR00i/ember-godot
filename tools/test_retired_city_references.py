"""Check incoming active references before retiring the seven historical scenes.

Retired scenes may retain historical references until the next cleanup slice.
This is a static gate, not proof against every dynamically constructed path.
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RETIRED = ('fan_town', 'fan_town_house', 'fan_town_inn', 'fan_town_mage',
           'fan_town_smith', 'agent_sandbox', 'agent_sandbox_interior')
RETIRED_ACTIONS = ('sbx_bush_se_actions', 'sbx_bush_se_actions_2', 'sbx_bush_se_actions_3',
                   'sbx_bush_sw_actions', 'sbx_bush_sw_actions_2', 'sbx_planter_nw_actions',
                   'sbx_quest_active_actions', 'sbx_quest_active_actions_2',
                   'sbx_quest_done_actions', 'sbx_quest_done_actions_3', 'sandbox_chain')
RETIRED_CONTENT = ('action_scripts/sandbox_chain.tres', 'quests/sandbox_notice_quest.tres',
                   'shops/village_kiosk.tres', 'world_surfaces/fan_town_surface.tres',
                   'world_surfaces/agent_sandbox_surface.tres', 'dialogues/sandbox_notice_talk.tres')
OFFLINE_BATCH = 'addons/ember_import/ember_voxel_migration_batches.gd'
NATIVE_MIXED_TESTS = ('test_object_inspector_model.gd', 'test_object_inspector_panel.gd',
                      'test_object_inspector_actions.gd', 'test_scene_edit_roundtrip.gd',
                      'test_standalone_trigger_authoring.gd', 'test_quest_journal_authoring.gd',
                      'test_graph_workspace.gd', 'test_map_visual_library.gd',
                      'test_voxel_surface_sculpt.gd', 'test_world_surface_projection.gd',
                      'fixtures/ember_mixed_editor_test_fixture.gd', 'test_voxel_prefab_rebuild.gd',
                      'test_diorama_materials.gd', 'test_surface_large_profile.gd',
                      'qa_voxel_editor_edit_cost.gd', 'qa_voxel_editor_performance_ab.gd',
                      'editor_test_voxel_shapes.gd', 'test_vox_axes.py', 'test_graph_lifecycle.gd')


def violations(root):
    errors = []
    for name in RETIRED:
        if (root / 'scenes' / (name + '.tscn')).exists():
            errors.append('scenes/' + name + '.tscn: archived scene restored to active project')
    if (root / OFFLINE_BATCH).exists():
        errors.append(OFFLINE_BATCH + ': retired batch module restored to active addons')
    names = '|'.join(re.escape(name) for name in RETIRED)
    # Quoted exact map IDs include exported destinations and action documents;
    # binary Resources retain full text paths as well.
    reference = re.compile(r'res://scenes/(?:' + names + r')\.tscn|["\'](?:' + names + r')["\']')
    retired_catalog_ref = re.compile(r'["\'](?:' + '|'.join(re.escape(name) for name in (*RETIRED_ACTIONS, 'sandbox_notice_quest', 'village_kiosk', 'sandbox_notice_talk')) + r')["\']|res://content/dialogues/sandbox_notice_talk\.tres')
    for folder in ('scripts', 'addons', 'scenes', 'content', 'prefabs'):
        for path in (root / folder).rglob('*'):
            if not path.is_file() or path.suffix not in ('.gd', '.tscn', '.tres', '.res'):
                continue
            relative = path.relative_to(root).as_posix()
            if relative in ('scenes/' + name + '.tscn' for name in RETIRED):
                continue
            text = path.read_bytes().decode('utf-8', errors='replace')
            if OFFLINE_BATCH in text:
                errors.append(relative + ': active dependency on retired offline batches')
            for line_number, line in enumerate(text.splitlines(), 1):
                if relative == 'scripts/ember_map_transition.gd' and line.startswith('const RETIRED_MAP_IDS :='):
                    continue  # Required save compatibility registry, not a destination.
                if relative.startswith('content/world_surfaces/') and line.startswith('"semanticOwner":'):
                    continue  # Historical authoring metadata, retired with the scene.
                if reference.search(line):
                    errors.append(f'{relative}:{line_number}: retired map reference')
                if retired_catalog_ref.search(line):
                    errors.append(f'{relative}:{line_number}: retired city catalog reference')
    for name in RETIRED_ACTIONS:
        if (root / 'content/action_scripts' / (name + '.tres')).exists():
            errors.append(name + ': retired action still in active catalog')
    for path in RETIRED_CONTENT:
        if (root / 'content' / path).exists():
            errors.append('content/' + path + ': archived city content restored to active catalog')
    for name in NATIVE_MIXED_TESTS:
        path = root / 'tools' / name
        if path.exists() and reference.search(path.read_text(encoding='utf-8')):
            errors.append('tools/' + name + ': native mixed gate revived a retired map dependency')
    return errors


def main():
    errors = violations(ROOT)
    if errors:
        raise SystemExit('FAIL retired city references:\n' + '\n'.join(errors))
    print('PASS active city references; retired batch module absent, save compatibility registry preserved')


if __name__ == '__main__':
    main()
