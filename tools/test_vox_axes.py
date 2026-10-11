"""Axis contract: MagicaVoxel Z-up → Ember/Godot Y-up, ember(x,y,z) = vox(x,z,y).

Synthetic VOX input plus current native Godot/static contracts; no historical pack.
Run from anywhere: python tools/test_vox_axes.py
"""
from __future__ import annotations

import struct
import tempfile
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def parse_vox(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"VOX " or data[8:12] != b"MAIN":
        raise SystemExit(f"not a vox file: {path}")
    models: list[dict] = []
    pending = None

    def walk(start: int, end: int) -> None:
        nonlocal pending
        offset = start
        while offset + 12 <= end:
            cid = data[offset : offset + 4].decode("ascii")
            content, children = struct.unpack_from("<ii", data, offset + 4)
            content_start = offset + 12
            content_end = content_start + content
            children_end = content_end + children
            if content_end > end or children_end > end:
                break
            if cid == "SIZE" and content >= 12:
                pending = struct.unpack_from("<iii", data, content_start)
            elif cid == "XYZI" and content >= 4 and pending:
                n = struct.unpack_from("<i", data, content_start)[0]
                voxels = []
                p = content_start + 4
                for _ in range(n):
                    if p + 4 > content_end:
                        break
                    x, y, z, i = data[p : p + 4]
                    voxels.append((x, y, z, i))
                    p += 4
                models.append({"size": pending, "voxels": voxels})
                pending = None
            if children:
                walk(content_end, children_end)
            offset = children_end

    main_content, main_children = struct.unpack_from("<ii", data, 12)
    walk(20 + main_content, 20 + main_content + main_children)
    if not models:
        raise SystemExit("vox: no model")
    return models[0]


def vox_to_ember(x: int, y: int, z: int) -> tuple[int, int, int]:
    return (x, z, y)


def ember_size(sx: int, sy: int, sz: int) -> tuple[int, int, int]:
    return (sx, sz, sy)


def fixture_axis_checks(errors: list[str]) -> None:
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return tag + struct.pack("<ii", len(payload), 0) + payload
    cells = [(1, 2, 9, 5), (2, 6, 10, 1)]
    children = chunk(b"SIZE", struct.pack("<iii", 3, 7, 11)) + chunk(b"XYZI", struct.pack("<i", len(cells)) + b"".join(bytes(cell) for cell in cells))
    data = b"VOX " + struct.pack("<i", 150) + b"MAIN" + struct.pack("<ii", 0, len(children)) + children
    with tempfile.TemporaryDirectory(prefix="ember-axis-fixture-") as temporary:
        path = Path(temporary) / "asymmetric.vox"
        path.write_bytes(data)
        model = parse_vox(path)
    if model["size"] != (3, 7, 11) or model["voxels"] != cells:
        errors.append("synthetic VOX parser lost size, axes, cells or palette indices")
    if ember_size(*model["size"]) != (3, 11, 7): errors.append("asymmetric VOX size axis conversion failed")
    expected = [(1, 9, 2), (2, 10, 6)]
    if [vox_to_ember(*cell[:3]) for cell in model["voxels"]] != expected: errors.append("asymmetric VOX occupied cell conversion failed")
    print("ok generated asymmetric VOX dimensions/cells/palette and Z-up -> Y-up")


def shader_source(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'#include "res://([^"]+)"', lambda m: shader_source(ROOT / m[1]), text)
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def main() -> int:
    errors: list[str] = []
    fixture_axis_checks(errors)
    prefab_gd = ROOT / "scripts" / "ember_voxel_prefab.gd"
    text = prefab_gd.read_text(encoding="utf-8")
    if "res://prefabs/voxels" not in text:
        errors.append("prefab dir contract missing")
    else:
        print("ok godot prefab dir res://prefabs/voxels")
    for contract in (
        "source_signature",
        "validate_packed",
        "Collision/Shape",
        "ShadowBody",
        "resource_uid_from_header",
        "_copy_mesh_surfaces",
    ):
        if contract not in text:
            errors.append(f"targeted prefab validation missing {contract}")
    loader_gd = ROOT / "scripts" / "ember_map_loader.gd"
    loader_text = loader_gd.read_text(encoding="utf-8")
    if "GEN_EDIT_STATE_INSTANCE" not in loader_text:
        errors.append("map loader must instance prefabs with GEN_EDIT_STATE_INSTANCE")
    shader = shader_source(ROOT / "shaders" / "ember_voxel_toon.gdshader")
    shader_code = shader.split("void light()", 1)[0]
    if "LIGHT_VERTEX =" in shader_code:
        errors.append("toon shader must keep Godot's default view-space LIGHT_VERTEX (world round-trip causes moire)")
    else:
        print("ok toon shader keeps default view-space LIGHT_VERTEX")
    if "LIGHT_IS_DIRECTIONAL" not in shader or "smoothstep" not in shader:
        errors.append("toon light() must soften directional ATTENUATION (shadow acne on voxel roofs)")
    if "local_light_softness" not in shader or "smoothstep(0.0, 0.72, ndotl)" not in shader or "mix(hard, soft, local_softness)" not in shader:
        errors.append("local point lights need a smooth N.L ramp (toon quantization creates concentric rings)")
    if "voxel_snap" in shader or "voxel_size" in shader:
        errors.append("Godot toon shader must not carry the Three-only light probe snap")
    transparent_shader = ROOT / "shaders" / "ember_voxel_transparent.gdshader"
    transparent_text = transparent_shader.read_text(encoding="utf-8") if transparent_shader.is_file() else ""
    if "depth_prepass_alpha" not in transparent_text or "ALPHA = clamp(COLOR.a" not in transparent_text:
        errors.append("transparent voxel surface needs its own alpha toon shader")
    mesher_text = (ROOT / "scripts" / "vox_mesher.gd").read_text(encoding="utf-8")
    for contract in ("model_channel", "opacity_from_transparency", '"transparent"'):
        if contract not in mesher_text:
            errors.append(f"voxel mesher missing transparency contract {contract}")
    lights_gd = (ROOT / "scripts" / "ember_lights.gd").read_text(encoding="utf-8")
    if "SHADOW_LAYER_LAMP_HOST" not in lights_gd or "shadow_caster_mask" not in lights_gd:
        errors.append("Omni must exclude lamp ShadowBody from cube shadows (host cage ate fill)")
    if "MAX_OMNI_SHADOWS" not in lights_gd or "tune_moon_shadows" not in lights_gd:
        errors.append("moon/omni shadow polish helpers missing")
    if "apply_shadow_atlas" not in lights_gd:
        errors.append("shadow atlas/filter must be tunable (apply_shadow_atlas)")
    if "SHADOW_PARALLEL_4_SPLITS" not in lights_gd:
        errors.append("moon PSSM default is 4 splits")
    if "shadow_caster_mask" not in loader_text or "_isolate_lamp_host_shadows" not in loader_text:
        errors.append("map loader must isolate lamp host ShadowBody from Omni casters")
    if "refresh_omni_shadow_focus" not in loader_text:
        errors.append("map loader must rank nearby lantern cube shadows")
    if "_omni_shadow_ids" not in loader_text:
        errors.append("omni cube ranker must avoid reallocating the same K lights")
    if "camera_far" not in loader_text or "directional_shadow_size" not in loader_text:
        errors.append("Map Inspector must expose camera_far and shadow resolution")
    if "Применить все настройки света" not in loader_text:
        errors.append("Map Inspector needs an explicit apply-lighting action")
    if "lighting_test_shadows" not in loader_text or "set_lighting_test_profile" not in loader_text:
        errors.append("Map Inspector needs comparable production/stress light profiles")
    if "[0, 2, 4, 8, 12, 16]" not in loader_text:
        errors.append("Map Inspector needs 0/2/4/8 plus 12/16 stress profiles")
    if "preview_local_shadows_in_editor" not in loader_text:
        errors.append("Map Inspector needs an explicit editor shadow-preview switch")
    if "lamp_softness" not in loader_text:
        errors.append("Map Inspector needs a local-light softness control")
    for contract in ("lamp_shadow_bias", "lamp_shadow_normal_bias", "lamp_shadow_blur"):
        if contract not in loader_text:
            errors.append(f"Map Inspector missing local shadow anti-acne control {contract}")
    if "vp.use_debanding = use_debanding" not in loader_text:
        errors.append("Map quality must apply viewport debanding for smooth local-light gradients")
    if "glow_bicubic_upscale" in loader_text:
        errors.append("Godot 4.7 removed Environment.glow_bicubic_upscale")

    benchmark_gd = ROOT / "scripts" / "ember_benchmark_overlay.gd"
    benchmark_text = benchmark_gd.read_text(encoding="utf-8") if benchmark_gd.is_file() else ""
    for contract in ("KEY_F3", "KEY_F4", "SHADOW_PROFILES", "viewport_get_measured_render_time_gpu"):
        if contract not in benchmark_text:
            errors.append(f"lighting benchmark missing {contract}")
    if "omni_shadow_active_count" not in benchmark_text or "omni_shadow_candidate_count" not in benchmark_text:
        errors.append("lighting benchmark must distinguish budget from actual shadow-capable lanterns")

    dock_gd = ROOT / "addons" / "ember_import" / "ember_tools_dock.gd"
    dock_text = dock_gd.read_text(encoding="utf-8") if dock_gd.is_file() else ""
    for contract in (
        "get_selected_nodes",
        "ember_voxel_scene_refresh.gd",
                "Показать в папке",
        "Дублировать безопасно",
        "Открыть модель в Godot",
        "validate_packed",
    ):
        if contract not in dock_text:
            errors.append(f"Ember migration dock missing {contract}")
    plugin_text = (ROOT / "addons" / "ember_import" / "plugin.gd").read_text(encoding="utf-8")
    if "Reimport map from pack…" in plugin_text:
        errors.append("native editor revived destructive legacy map reimport")
    inspector_model_path = ROOT / "addons" / "ember_import" / "ember_object_inspector_model.gd"
    inspector_model_text = inspector_model_path.read_text(encoding="utf-8") if inspector_model_path.is_file() else ""
    for contract in ("func snapshot", "Asset", "Scene", "Derived", "EmberInteractionContent.resolve"):
        if contract not in inspector_model_text:
            errors.append(f"object Inspector read model missing {contract}")
    inspector_plugin_path = ROOT / "addons" / "ember_import" / "ember_object_inspector_plugin.gd"
    inspector_plugin_text = inspector_plugin_path.read_text(encoding="utf-8") if inspector_plugin_path.is_file() else ""
    for contract in ("extends EditorInspectorPlugin", "_can_handle", "_parse_begin"):
        if contract not in inspector_plugin_text:
            errors.append(f"object Inspector plugin missing {contract}")
    if "add_inspector_plugin" not in plugin_text or "remove_inspector_plugin" not in plugin_text:
        errors.append("object Inspector must have symmetric editor lifecycle")
    if "add_control_to_bottom_panel" not in plugin_text or "remove_control_from_bottom_panel" not in plugin_text:
        errors.append("migration workflow dock must use the bottom panel and leave native Inspector visible")
    if 'name = "EmberMigrationWorkflow"' not in plugin_text or '"Ember · Сервис"' not in plugin_text:
        errors.append("migration workflow needs a new stable layout key distinct from legacy right dock Ember")
    if "DOCK_SLOT_RIGHT_BL" in plugin_text:
        errors.append("migration workflow dock must not squeeze the native Inspector right slot")
    if "func rebuild_prop" not in dock_text or "_rebuild_from_inspector" not in plugin_text:
        errors.append("object Inspector rebuild must delegate to the existing dock contract")
    gizmo_path = ROOT / "addons" / "ember_import" / "ember_voxel_prop_gizmo.gd"
    gizmo_text = gizmo_path.read_text(encoding="utf-8") if gizmo_path.is_file() else ""
    if "visual.mesh.get_aabb()" not in gizmo_text or 'get_node_or_null("Omni")' in gizmo_text:
        errors.append("voxel prop editor bounds must use Mesh AABB and ignore Omni range")
    if "add_node_3d_gizmo_plugin" not in plugin_text or "remove_node_3d_gizmo_plugin" not in plugin_text:
        errors.append("voxel prop compact-bounds gizmo must have symmetric editor lifecycle")
    authoring_path = ROOT / "scripts" / "ember_scene_authoring.gd"
    authoring_text = authoring_path.read_text(encoding="utf-8") if authoring_path.is_file() else ""
    for contract in (
        "next_duplicate_id",
        "attach_duplicate",
        "source_child.owner == root",
        "make_interact",
        "attach_interact",
        "normalized_interact_values",
        "interact_validation_errors",
    ):
        if contract not in authoring_text:
            errors.append(f"safe scene authoring missing {contract}")
    if "get_undo_redo" not in plugin_text or "_add_authored_duplicate" not in plugin_text:
        errors.append("safe duplicate must integrate with editor Undo/Redo")
    actions_path = ROOT / "addons" / "ember_import" / "ember_object_inspector_actions.gd"
    actions_text = actions_path.read_text(encoding="utf-8") if actions_path.is_file() else ""
    for contract in ("EditorUndoRedoManager", "add_undo_reference", "func save", "func remove"):
        if contract not in actions_text:
            errors.append(f"object Inspector Interact actions missing {contract}")
    panel_path = ROOT / "addons" / "ember_import" / "ember_object_inspector_panel.gd"
    panel_text = panel_path.read_text(encoding="utf-8") if panel_path.is_file() else ""
    for contract in ("interact_save_requested", "interact_remove_requested", "InteractEditor"):
        if contract not in panel_text:
            errors.append(f"object Inspector Interact form missing {contract}")
    interact_editor_path = ROOT / "addons" / "ember_import" / "ember_interact_editor.gd"
    interact_editor_text = interact_editor_path.read_text(encoding="utf-8") if interact_editor_path.is_file() else ""
    for contract in ("script_ref_ids", "shop_ids", "map_ids", "region_ids", "interact_validation_errors"):
        if contract not in interact_editor_text:
            errors.append(f"kind-dependent Interact editor missing {contract}")
    if "EmberSceneAuthoring.make_interact" not in loader_text:
        errors.append("map import and Inspector must share the same Interact construction helper")

    migration_plan = ROOT / "MIGRATION_TEST_PLAN.md"
    if not migration_plan.is_file() or "0/2/4/8" not in migration_plan.read_text(encoding="utf-8"):
        errors.append("migration test plan missing lighting profile protocol")
    rebuild_smoke = ROOT / "tools" / "test_voxel_prefab_rebuild.gd"
    rebuild_text = rebuild_smoke.read_text(encoding="utf-8") if rebuild_smoke.is_file() else ""
    for contract in ("validate_packed", "get_sha256", "placements preserved", "transparent surface"):
        if contract not in rebuild_text:
            errors.append(f"headless targeted-rebuild smoke missing {contract}")
    scene_roundtrip = ROOT / "tools" / "test_scene_edit_roundtrip.gd"
    roundtrip_text = scene_roundtrip.read_text(encoding="utf-8") if scene_roundtrip.is_file() else ""
    for contract in ("move + rotate + Interact", "source .tscn and native source preserved"):
        if contract not in roundtrip_text:
            errors.append(f"scene authoring roundtrip smoke missing {contract}")
    inspector_actions_test = ROOT / "tools" / "test_object_inspector_actions.gd"
    inspector_actions_test_text = inspector_actions_test.read_text(encoding="utf-8") if inspector_actions_test.is_file() else ""
    for contract in ("Undo/Redo", "save/reopen", "source .tscn and native source unchanged"):
        if contract not in inspector_actions_test_text:
            errors.append(f"object Inspector actions smoke missing {contract}")

    transition_path = ROOT / "scripts" / "ember_map_transition.gd"
    transition_text = transition_path.read_text(encoding="utf-8") if transition_path.is_file() else ""
    for contract in ("consume_spawn_region", "trigger_allowed", "RETURN_TRIGGER_GUARD_MS"):
        if contract not in transition_text:
            errors.append(f"map transition handoff missing {contract}")
    region_text = (ROOT / "scripts" / "ember_region.gd").read_text(encoding="utf-8")
    if "body_entered.connect" not in region_text or "target_map_id" not in region_text:
        errors.append("EmberRegion transition trigger runtime is not wired")
    if "region_world" not in loader_text:
        errors.append("map loader cannot resolve targetRegionId for player spawn")
    transition_smoke = ROOT / "tools" / "test_map_transition.gd"
    transition_smoke_text = transition_smoke.read_text(encoding="utf-8") if transition_smoke.is_file() else ""
    for contract in ("door -> nested entry", "exit -> matching return routes"):
        if contract not in transition_smoke_text:
            errors.append(f"map transition smoke missing {contract}")
    camera_movement_path = ROOT / "scripts" / "ember_camera_movement.gd"
    camera_movement_text = camera_movement_path.read_text(encoding="utf-8") if camera_movement_path.is_file() else ""
    if "world_direction" not in camera_movement_text or "camera_yaw" not in camera_movement_text:
        errors.append("camera-relative movement leaf contract is missing")
    player_text = (ROOT / "scripts" / "ember_player.gd").read_text(encoding="utf-8")
    for contract in ("Input.get_vector", "camera_rig.yaw", "EmberCameraMovement.world_direction"):
        if contract not in player_text:
            errors.append(f"EmberPlayer camera-relative movement missing {contract}")

    interaction_content_path = ROOT / "scripts" / "ember_interaction_content.gd"
    interaction_content_text = interaction_content_path.read_text(encoding="utf-8") if interaction_content_path.is_file() else ""
    for contract in (
        "resolve_script_ref",
        "ActionCatalog.document",
        "DialogueCatalog.document",
        "ShopCatalog.definition",
        "ItemCatalog.definitions",
        "shop_view",
    ):
        if contract not in interaction_content_text:
            errors.append(f"talk/shop content adapter missing {contract}")
    interaction_ui_path = ROOT / "scripts" / "ember_interaction_ui.gd"
    interaction_ui_text = interaction_ui_path.read_text(encoding="utf-8") if interaction_ui_path.is_file() else ""
    for contract in ("EmberDialogueSession", "_pending_shop_id", "blocks_movement"):
        if contract not in interaction_ui_text:
            errors.append(f"talk/shop runtime UI missing {contract}")
    if "interaction_ui.activate(interact)" not in player_text or "interaction_ui.blocks_movement()" not in player_text:
        errors.append("EmberPlayer does not route talk/shop through the single UI owner")
    if "area is EmberRegion" not in player_text:
        errors.append("EmberPlayer does not reuse EmberRegion for chest interaction")

    action_script_path = ROOT / "scripts" / "ember_action_script.gd"
    action_script_text = action_script_path.read_text(encoding="utf-8") if action_script_path.is_file() else ""
    for contract in ("resolve_script_ref", "run_script", "give_item", "set_flag", "MAX_DEPTH"):
        if contract not in action_script_text:
            errors.append(f"action-list queue builder missing {contract}")
    for contract in ("economy_state.grant_item", "economy_state.apply_authored_flag", "_advance_script_queue"):
        if contract not in interaction_ui_text:
            errors.append(f"action-list UI executor missing {contract}")
    if "interaction_ui.activate_script(region.script_id)" not in player_text:
        errors.append("EmberPlayer does not route script-only regions through the action-list executor")
    if 'kind == "trigger" and not script_id.is_empty()' not in region_text:
        errors.append("script-only EmberRegion does not join the existing F interaction group")
    action_script_smoke = ROOT / "tools" / "test_action_script.gd"
    action_script_smoke_text = action_script_smoke.read_text(encoding="utf-8") if action_script_smoke.is_file() else ""
    for contract in ("talk -> visible coin reward -> typed flag", "script-only region joins", "save once per completed chain"):
        if contract not in action_script_smoke_text:
            errors.append(f"action-list headless smoke missing {contract}")

    equipment_path = ROOT / "scripts" / "ember_equipment.gd"
    equipment_text = equipment_path.read_text(encoding="utf-8") if equipment_path.is_file() else ""
    for contract in ("accessory1", "accessory2", "shoes", "import_saved", "combat_stats", "use_item", "hpRestore", "canUse"):
        if contract not in equipment_text:
            errors.append(f"inventory/equipment leaf contract missing {contract}")
    inventory_ui_path = ROOT / "scripts" / "ember_inventory_ui.gd"
    inventory_ui_text = inventory_ui_path.read_text(encoding="utf-8") if inventory_ui_path.is_file() else ""
    if "progress_state.equip_item" not in inventory_ui_text or "progress_state.unequip_slot" not in inventory_ui_text:
        errors.append("inventory UI bypasses the shared EmberExploreState owner")
    if "progress_state.use_item_on_member" not in inventory_ui_text or "HP %d/%d" not in inventory_ui_text:
        errors.append("inventory UI does not route consumables/show HP through EmberExploreState")
    if "inventory_ui.toggle()" not in player_text or "inventory_ui.blocks_movement()" not in player_text:
        errors.append("EmberPlayer does not route inventory input/movement blocking")
    explore_state_text = (ROOT / "scripts" / "ember_explore_state.gd").read_text(encoding="utf-8")
    for contract in ("var party", '"party": EmberPartyState.serialize', "func save_autosave", "func use_item_on_member", "func apply_damage", "legacy_save_path"):
        if contract not in explore_state_text:
            errors.append(f"health/save owner missing {contract}")
    health_smoke = ROOT / "tools" / "test_health_consumables.gd"
    health_smoke_text = health_smoke.read_text(encoding="utf-8") if health_smoke.is_file() else ""
    for contract in ("armor damage -> hpRestore clamp", "save v2 stores current HP only", "native H probe"):
        if contract not in health_smoke_text:
            errors.append(f"health/consumables headless smoke missing {contract}")
    talk_shop_smoke = ROOT / "tools" / "test_talk_shop.gd"
    talk_shop_smoke_text = talk_shop_smoke.read_text(encoding="utf-8") if talk_shop_smoke.is_file() else ""
    for contract in ("guard dialogue: 3 authored lines", "branch dialogue: 2 authored choices", "canonical catalog listings"):
        if contract not in talk_shop_smoke_text:
            errors.append(f"talk/shop headless smoke missing {contract}")
    camera_movement_smoke = ROOT / "tools" / "test_camera_relative_movement.gd"
    camera_movement_smoke_text = camera_movement_smoke.read_text(encoding="utf-8") if camera_movement_smoke.is_file() else ""
    if "W follows camera forward" not in camera_movement_smoke_text:
        errors.append("camera-relative movement headless smoke is missing")
    prefab_runtime_text = (ROOT / "scripts" / "ember_voxel_prefab.gd").read_text(encoding="utf-8")
    if "built.take_over_path(path)" not in prefab_runtime_text or "FileAccess.file_exists(ProjectSettings.globalize_path(path))" not in prefab_runtime_text:
        errors.append("first-time interior prefab import must keep freshly saved mesh live without an early ResourceLoader reopen")
    if "ACTION_MESSAGE_MS" not in player_text or "_action_message_until_ms" not in player_text:
        errors.append("interaction result HUD must survive longer than one physics frame")

    project_text = (ROOT / "project.godot").read_text(encoding="utf-8")
    debanding_off = (
        "anti_aliasing/quality/use_debanding=false" in project_text
        or "@export var use_debanding := false" in loader_text
    )
    if not debanding_off:
        errors.append("voxel look must leave ordered debanding off (its dither pattern is visible)")

    if errors:
        for error in errors: print("FAIL", error)
        return 1
    print("PASS native Ember axis/static contracts; historical content absent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
