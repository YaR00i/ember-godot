"""Axis contract: MagicaVoxel Z-up → Ember/Godot Y-up, ember(x,y,z) = vox(x,z,y).

Mirrors joi-conductor src/game/voxel/vox/voxFile.ts + emberVoxCodec.ts.
Run from anywhere: python tools/test_vox_axes.py
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JOI_PACK = ROOT.parent / "joi-conductor" / "content" / "ember"
LANTERN_VOX = JOI_PACK / "voxels" / "models" / "vox_fan_lantern_paper.vox"
LANTERN_JSON = JOI_PACK / "voxels" / "models" / "vox_fan_lantern_paper.json"
MAP_JSON = JOI_PACK / "maps" / "fan_town.json"


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


def main() -> int:
    errors: list[str] = []
    if not LANTERN_VOX.is_file():
        print(f"SKIP vox file missing: {LANTERN_VOX}")
        return 0
    model = parse_vox(LANTERN_VOX)
    sx, sy, sz = model["size"]
    es = ember_size(sx, sy, sz)
    if es[0] != sx or es[1] != sz or es[2] != sy:
        errors.append(f"ember_size mismatch {es} from vox {(sx, sy, sz)}")
    sample = model["voxels"][0]
    ex, ey, ez = vox_to_ember(*sample[:3])
    if (ex, ey, ez) != (sample[0], sample[2], sample[1]):
        errors.append(f"axis map wrong for {sample} -> {(ex, ey, ez)}")
    if ey > es[1] or ez > es[2]:
        errors.append(f"ember voxel out of ember size {es}")
    print(
        f"ok vox {LANTERN_VOX.name}: vox_size={(sx, sy, sz)} "
        f"ember_size={es} voxels={len(model['voxels'])}"
    )

    prefab = json.loads(LANTERN_JSON.read_text(encoding="utf-8"))
    inner = prefab.get("model") or {}
    if inner.get("emissiveCastsLight") is not True:
        errors.append("lantern json missing emissiveCastsLight")
    if inner.get("emissiveLightShadows") is not True:
        errors.append("lantern json missing emissiveLightShadows")
    em = inner.get("emissive") or []
    hv = int(inner.get("heightVoxels") or 26)
    n = 16 * hv * 16
    if len(em) != n:
        errors.append(f"paper lantern emissive len {len(em)} != grid {n}")
    glow = sum(1 for v in em if int(v or 0) > 0)
    if glow < 8:
        errors.append(f"paper lantern expected window glow voxels, got {glow}")
    print(f"ok lantern json range={inner.get('emissiveLightRange')} glow={glow}")

    stone_json = JOI_PACK / "voxels" / "models" / "vox_fan_lantern_stone.json"
    stone = json.loads(stone_json.read_text(encoding="utf-8"))
    sm = stone.get("model") or {}
    sem = sm.get("emissive") or []
    shy = int(sm.get("heightVoxels") or 24)
    sn = 16 * shy * 16
    sx = sz = 16
    w = cx = cy = cz = 0.0
    skip = 0
    for y in range(shy):
        for z in range(sz):
            for x in range(sx):
                i = x + z * sx + y * sx * sz
                amt = int(sem[i] or 0) if i < len(sem) else 0
                if amt <= 0:
                    continue
                skip += 1
                ww = amt / 255.0
                w += ww
                cx += (x + 0.5) * ww
                cy += (y + 0.5) * ww
                cz += (z + 0.5) * ww
    if skip != 16:
        errors.append(f"stone lantern window voxels {skip}, expected 16")
    if w <= 0:
        errors.append("stone lantern missing emissive centroid")
    else:
        cy /= w
        if abs(cy - 14.0) > 0.6:
            errors.append(f"stone lantern light should sit in the chamber y~14, got {cy}")
        if sm.get("emissiveSuppressHostShadow") is True:
            errors.append("stone lantern must cast host umbra (no emissiveSuppressHostShadow)")
        print(f"ok stone lantern chamber y={cy:.2f} window_skip={skip}")

    town = json.loads(MAP_JSON.read_text(encoding="utf-8"))
    if town.get("id") != "fan_town":
        errors.append("fan_town id mismatch")
    props = town.get("voxelProps") or []
    lanterns = [p for p in props if str(p.get("modelId", "")).startswith("vox_fan_lantern")]
    if len(lanterns) < 3:
        errors.append(f"expected several lanterns, got {len(lanterns)}")
    print(f"ok fan_town voxelProps={len(props)} lanterns={len(lanterns)}")

    doors = [
        p
        for p in props
        if isinstance(p.get("interactivity"), dict)
        and p["interactivity"].get("kind") == "door"
    ]
    if len(doors) < 4:
        errors.append(f"fan_town expected 4 doors, got {len(doors)}")
    else:
        print(f"ok fan_town doors={len(doors)}")
    starts = [r for r in (town.get("regions") or []) if r.get("kind") == "player_start"]
    if not starts:
        errors.append("fan_town missing player_start")
    else:
        print(f"ok fan_town player_start={starts[0].get('id')}")

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
    shader = (ROOT / "shaders" / "ember_voxel_toon.gdshader").read_text(encoding="utf-8")
    shader_code = shader.split("void light()", 1)[0]
    if "LIGHT_VERTEX =" in shader_code:
        errors.append("toon shader must keep Godot's default view-space LIGHT_VERTEX (world round-trip causes moire)")
    else:
        print("ok toon shader keeps default view-space LIGHT_VERTEX")
    if "LIGHT_IS_DIRECTIONAL" not in shader or "smoothstep" not in shader:
        errors.append("toon light() must soften directional ATTENUATION (shadow acne on voxel roofs)")
    if "local_light_softness" not in shader or "soft_ramp" not in shader:
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
        "EmberVoxelPrefab.ensure_saved",
        "Legacy .vox · диагностика",
        "Legacy .json · диагностика",
        "Показать в папке",
        "Дублировать безопасно",
        "Открыть модель в Godot",
        "_placement_snapshot",
        "_scene_file_hash",
        "validate_packed",
    ):
        if contract not in dock_text:
            errors.append(f"Ember migration dock missing {contract}")
    plugin_text = (ROOT / "addons" / "ember_import" / "plugin.gd").read_text(encoding="utf-8")
    if "ConfirmationDialog" not in plugin_text or "Reimport map from pack…" not in plugin_text:
        errors.append("destructive full-map reimport must require confirmation")
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
    if 'name = "EmberMigrationWorkflow"' not in plugin_text or '"Ember Migration"' not in plugin_text:
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
    for contract in ("move + rotate + Interact", "source .tscn and JOI map JSON preserved"):
        if contract not in roundtrip_text:
            errors.append(f"scene authoring roundtrip smoke missing {contract}")
    inspector_actions_test = ROOT / "tools" / "test_object_inspector_actions.gd"
    inspector_actions_test_text = inspector_actions_test.read_text(encoding="utf-8") if inspector_actions_test.is_file() else ""
    for contract in ("Undo/Redo", "save/reopen", "source .tscn and JOI map JSON unchanged"):
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
    interior_scene = ROOT / "scenes" / "agent_sandbox_interior.tscn"
    if not interior_scene.is_file() or 'map_id = "agent_sandbox_interior"' not in interior_scene.read_text(encoding="utf-8"):
        errors.append("agent_sandbox_interior play scene is missing")
    for fan_interior in ("fan_town_inn", "fan_town_mage", "fan_town_smith", "fan_town_house"):
        fan_interior_scene = ROOT / "scenes" / f"{fan_interior}.tscn"
        if not fan_interior_scene.is_file() or f'map_id = "{fan_interior}"' not in fan_interior_scene.read_text(encoding="utf-8"):
            errors.append(f"{fan_interior} play scene is missing")
    transition_smoke = ROOT / "tools" / "test_map_transition.gd"
    transition_smoke_text = transition_smoke.read_text(encoding="utf-8") if transition_smoke.is_file() else ""
    for contract in ("door -> interior:start", "exit -> sandbox:cabin_enter"):
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
    for contract in ("weapon_arena", "arena_weapon", "EmberEconomy.grant_items", "combat_stats", "use_item", "hpRestore", "canUse"):
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
    for contract in ("armor damage -> hpRestore clamp", "save v2 stores current HP only", "agent_sandbox H probe"):
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

    def moon_energy(sun, fill, night, scale=1.25):
        n = max(0.0, min(1.0, night))
        return max(0.5, (1.05 + n * 0.35) * max(0.4, sun) * (0.45 + fill) * scale)

    fan_moon = moon_energy(1.41, 0.23, 0.92, 1.25)
    if abs(fan_moon - 1.644) > 0.02:
        errors.append(f"fan_town moon energy expected ~1.64 got {fan_moon}")
    else:
        print(f"ok fan_town moon energy={fan_moon:.3f}")
    town_scene = ROOT / "scenes" / "fan_town.tscn"
    town_text = town_scene.read_text(encoding="utf-8")
    if "moon_energy_scale = 0.37" in town_text:
        errors.append("fan_town.tscn moon_energy_scale still 0.37 (kills moonlight)")
    if "directional_shadow_max_distance = 520" not in town_text:
        errors.append("fan_town.tscn missing directional_shadow_max_distance")
    else:
        print("ok fan_town.tscn moon scale and shadow distance")

    inst_count = town_text.count("instance=ExtResource")
    if inst_count < 100:
        errors.append(f"fan_town.tscn expected prefab instances, got {inst_count}")
    else:
        print(f"ok fan_town.tscn prefab instances={inst_count}")
    if town_text.count('name="Interact"') < 4:
        errors.append("fan_town.tscn missing door Interact nodes")
    else:
        print("ok fan_town.tscn door Interact")
    lantern_prefab = ROOT / "prefabs" / "voxels" / "vox_fan_lantern_stone.tscn"
    if not lantern_prefab.is_file():
        errors.append("missing packed lantern prefab")
    else:
        lp = lantern_prefab.read_text(encoding="utf-8")
        if 'name="Omni"' not in lp:
            errors.append("lantern prefab missing Omni child")
        else:
            print("ok lantern prefab Omni child")
    sandbox_scene = ROOT / "scenes" / "agent_sandbox.tscn"
    sandbox_text = sandbox_scene.read_text(encoding="utf-8")
    if sandbox_text.count("instance=ExtResource") < 8:
        errors.append("agent_sandbox.tscn expected prefab instances")
    else:
        print("ok agent_sandbox.tscn prefab instances")
    interact_gd = (ROOT / "scripts" / "ember_interact.gd").read_text(encoding="utf-8")
    for kind in ("door", "talk", "shop", "trigger"):
        if f'"{kind}"' not in interact_gd:
            errors.append(f"EmberInteract missing kind {kind}")
    sandbox = JOI_PACK / "maps" / "agent_sandbox.json"
    if not sandbox.is_file():
        errors.append("agent_sandbox map missing for Godot play scene")
    else:
        print("ok agent_sandbox map for scenes/agent_sandbox.tscn")

    layers = {str(layer.get("name")): layer.get("data") or [] for layer in town.get("layers") or []}
    height = layers.get("height") or []
    walls = sum(1 for v in height if int(v or 0) > 0)
    ground = layers.get("ground_z0") or layers.get("ground") or []
    floors = sum(1 for v in ground if int(v or 0) > 0)
    if walls < 8 or floors < 32:
        errors.append(f"expected terrain columns, height>0={walls} ground={floors}")
    print(f"ok fan_town terrain height_cells={walls} ground_cells={floors}")

    pine_json = JOI_PACK / "voxels" / "models" / "vox_fan_pine.json"
    pine_vox = JOI_PACK / "voxels" / "models" / "vox_fan_pine.vox"
    pine = json.loads(pine_json.read_text(encoding="utf-8"))
    pine_voxels = (pine.get("model") or {}).get("voxels") or []
    pine_occ = sum(1 for v in pine_voxels if int(v or 0) > 0)
    if pine_vox.is_file():
        print(f"ok pine has .vox and json voxels={pine_occ}")
    elif pine_occ < 32:
        errors.append(f"pine json should mesh without .vox, occupied={pine_occ}")
    else:
        print(f"ok pine json-only occupied={pine_occ} (no .vox)")

    # Tangent-plane voxel snap lives in JOI Three (`voxelLightSnap.ts`).
    # Godot Forward+ must not grid-snap LIGHT_VERTEX — cell centers acne on floors.
    def snap(world, normal, vs=1.0):
        nlen = math.sqrt(sum(c * c for c in normal)) or 1.0
        en = [c / nlen for c in normal]
        n_abs = [abs(c) for c in en]
        n_max = max(n_abs)
        keep = [1.0 if a >= n_max - 1e-4 else 0.0 for a in n_abs]
        p = [w - n * (vs * 0.02) for w, n in zip(world, en)]
        grid = [(math.floor(c / vs) + 0.5) * vs for c in p]
        return [g if k < 0.5 else w for g, k, w in zip(grid, keep, world)]

    s = snap((10.3, 4.0, 20.7), (0.0, 1.0, 0.0), 1.0)
    if abs(s[0] - 10.5) > 1e-6 or abs(s[1] - 4.0) > 1e-6 or abs(s[2] - 20.5) > 1e-6:
        errors.append(f"voxel snap floor expected (10.5, 4, 20.5) got {s}")
    else:
        print("ok voxel light snap floor keeps Y, quantizes XZ")

    if errors:
        print("FAIL")
        for err in errors:
            print(" -", err)
        return 1
    print("PASS ember-godot pack contract")
    return 0


if __name__ == "__main__":
    sys.exit(main())
