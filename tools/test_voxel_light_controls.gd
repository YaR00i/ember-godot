extends SceneTree
## Focused scene-owned lighting controls/history/storage. No authored writes.
const PanelScript = preload("res://addons/ember_import/ember_world_look_panel.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
 if not ok: failures.append(label)
func run() -> void:
 var source := Terrain.new();source.width=4;source.depth=4;source.palette=PackedColorArray([Color.TRANSPARENT,Color(0.5,0.4,0.3)]);source.palette_surface_roles=PackedStringArray(["","soil"]);source.palette_material_ids=PackedStringArray(["","soil_grain"])
 for key in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:
  var channel=source.get(key);channel.resize(16);channel.fill(0 if key.begins_with("water") else 1);source.set(key,channel)
 check(source.validation_errors().is_empty(),"valid minimal Source")
 var scene := Node3D.new();scene.name="VoxelLightControls"
 var map := EmberMapLoader.new();map.name="Map";map.compact_terrain=source;map.world_look=2;map.imported_tile_size=16;scene.add_child(map);map.owner=scene
 var look:=Node3D.new();look.name="Look";map.add_child(look);look.owner=scene
 var sun:=DirectionalLight3D.new();sun.name="Sun";sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS;sun.directional_shadow_max_distance=1600;sun.shadow_enabled=true;look.add_child(sun);sun.owner=scene
 root.add_child(scene);current_scene=scene
 for i in 8: await process_frame
 var projection=map._visual_surface_projection
 var revision: int=projection.column_revision();var pending: int=projection.pending_tile_count();var tile_count: int=projection._tiles.size()
 var panel := PanelScript.new();root.add_child(panel);var history:=UndoRedo.new();panel.set_target(scene,map,history)
 check(is_equal_approx(panel._sliders.voxel_light_cell_m.value,0.0625),"native panel shows metre default")
 check(is_equal_approx(panel._sliders.voxel_light_levels.value,8),"native panel shows gradation default")
 var count:=history.get_history_count()
 panel._drag_started("voxel_light_cell_m");panel._sliders.voxel_light_cell_m.value=0.125;panel._sliders.voxel_light_cell_m.value=0.25;panel._drag_ended(true,"voxel_light_cell_m")
 check(history.get_history_count()==count+1 and is_equal_approx(map.voxel_light_cell_m,0.25),"one drag is one action")
 history.undo();check(is_equal_approx(map.voxel_light_cell_m,0.0625),"cell Undo")
 history.redo();check(is_equal_approx(map.voxel_light_cell_m,0.25),"cell Redo")
 panel._sliders.voxel_light_levels.value=12;check(map.voxel_light_levels==12,"levels routes to scene owner")
 history.undo();check(map.voxel_light_levels==8,"levels Undo")
 history.redo();check(map.voxel_light_levels==12,"levels Redo")
 check(projection.column_revision()==revision and projection.pending_tile_count()==pending and projection._tiles.size()==tile_count and projection._look_pending.is_empty(),"controls do not queue geometry or change Source revision")
 var material: ShaderMaterial=projection._ground_material
 check(material.get_shader_parameter("voxel_light_enabled")==true and is_equal_approx(material.get_shader_parameter("voxel_light_cell"),4.0) and is_equal_approx(material.get_shader_parameter("voxel_light_levels"),12.0),"ground uses physical metres and current levels")
 var object:=ShaderMaterial.new();object.shader=load("res://shaders/ember_tree_bark.gdshader");map.bind_voxel_light(object,2,1.0)
 check(is_equal_approx(object.get_shader_parameter("voxel_light_cell"),0.25),"object-local metres do not inherit world scale twice")
 for look_id in [0,1,2,0,2]:
  map.bind_voxel_light(object,look_id,1.0)
  check(bool(object.get_shader_parameter("voxel_light_enabled"))==(look_id==2),"voxel-only binding "+str(look_id))
 map.voxel_light_cell_m=NAN;check(is_equal_approx(map.voxel_light_cell_m,0.0625),"nonfinite cell falls back safely")
 map.voxel_light_cell_m=-1;check(is_equal_approx(map.voxel_light_cell_m,0.015625),"cell range validation")
 map.voxel_light_levels=999;check(map.voxel_light_levels==32,"gradation range validation")
 map.voxel_light_cell_m=0.25;map.voxel_light_levels=12
 check(sun.directional_shadow_mode==DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and is_equal_approx(sun.directional_shadow_max_distance,1600),"author Sun preserved")
 var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack existing Map owner")
 var path: String="user://ember-tests/voxel-light-controls-"+str(OS.get_process_id())+".tscn";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
 check(ResourceSaver.save(packed,path)==OK,"save disposable scene")
 var reopened: Node=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate();root.add_child(reopened)
 var saved: EmberMapLoader=reopened.get_node("Map")
 check(is_equal_approx(saved.voxel_light_cell_m,0.25) and saved.voxel_light_levels==12,"fresh reopen retains both settings")
 check(saved.compact_terrain.validation_errors().is_empty(),"reopened Source validation")
 panel._sliders.voxel_light_cell_m.value=0.5;panel.set_target(reopened,saved,history)
 check(is_equal_approx(panel._sliders.voxel_light_cell_m.value,0.25),"discard restores saved scene via existing retarget path")
 history.undo();check(is_equal_approx(saved.voxel_light_cell_m,0.25),"old history does not edit reopened owner")
 panel.set_target(null,null,null);check(not panel._sliders.voxel_light_cell_m.editable,"closed scene disables stale control")
 history.clear_history();history.free();panel.free();reopened.free();scene.free()
 authored_copy_check()
 print("VOXEL_LIGHT_CONTROLS ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"manual_gate":"mouse and author visual acceptance"}))
 quit(0 if failures.is_empty() else 1)

func authored_copy_check() -> void:
 var authored: Node=load("res://scenes/landscape_compact.tscn").instantiate()
 var map: EmberMapLoader=authored.get_node("Map")
 var sun: DirectionalLight3D=authored.get_node("Map/Look/Sun")
 var distance:=sun.directional_shadow_max_distance;var cascades:=sun.directional_shadow_mode;var angle:=sun.light_angular_distance;var source_path:=map.compact_terrain.resource_path
 map.voxel_light_cell_m=0.125;map.voxel_light_levels=16
 var tree: EmberVoxelProp=map.get_node("Props/PaintedOak")
 var visual: MeshInstance3D=tree.get_node("Mesh");var published: Mesh=visual.mesh
 var original: ShaderMaterial=published.surface_get_material(0)
 tree.set_world_look(2)
 check(visual.mesh!=published and visual.get_active_material(0)!=original,"tree owns derived light materials")
 check(original.get_shader_parameter("voxel_light_enabled")==false,"shared prefab material remains unchanged")
 var derived: Mesh=visual.mesh;tree.set_world_look(0);tree.set_world_look(2)
 check(visual.mesh==derived,"returning to tree look reuses prepared light material mesh")
 tree.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
 check(visual.mesh==published,"pre-save restores published tree mesh rather than derived lighting state")
 var packed:=PackedScene.new();check(packed.pack(authored)==OK,"pack detached actual map copy")
 var path: String="user://ember-tests/voxel-light-main-copy-"+str(OS.get_process_id())+".tscn"
 check(ResourceSaver.save(packed,path)==OK,"save lighting on temporary main-map copy")
 authored.free()
 var reopened: Node=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
 var saved: EmberMapLoader=reopened.get_node("Map");var saved_sun: DirectionalLight3D=reopened.get_node("Map/Look/Sun")
 check(is_equal_approx(saved.voxel_light_cell_m,0.125) and saved.voxel_light_levels==16,"main-map fresh reopen retains lighting")
 check(saved_sun.directional_shadow_max_distance==distance and saved_sun.directional_shadow_mode==cascades and saved_sun.light_angular_distance==angle,"main-map saved author Sun remains exact")
 check(saved.compact_terrain.resource_path==source_path,"main-map Source owner retained")
 reopened.free()

