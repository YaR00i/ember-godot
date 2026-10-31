@tool
extends Node3D
## Scene-owned editable scatter of the accepted painted tuft. Only parameters
## are saved; meshes/instances follow the existing map surface and material bank.
const Styles = preload("res://scripts/ember_material_look_bake.gd")
const Fixture = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Detail = preload("res://scripts/ember_detail_scatter.gd")
const PatternBake = preload("res://scripts/ember_detail_pattern_bake.gd")
const FlowerCover = preload("res://scripts/ember_flowered_grass.gd")
const GRASS_CARD_ATLAS = preload("res://content/terrain_materials/textures/grass-cards-runtime.png")
const Preparation = preload("res://scripts/ember_detail_preparation.gd")
@export_storage var detail_kind := 0:
	set(value):
		detail_kind = clampi(value,0,3); _coloured_meshes.clear(); _dirty = true
@export_storage var cover_pattern: EmberCompactTerrainPattern:
	set(value):
		if cover_pattern != null and cover_pattern.changed.is_connected(_cover_changed): cover_pattern.changed.disconnect(_cover_changed)
		cover_pattern = value
		if cover_pattern != null: cover_pattern.changed.connect(_cover_changed)
		_cover_changed()
var _cover_preview: EmberCompactTerrainPattern
@export_storage var detail_preset: Resource:
	set(value):
		if detail_preset is PatternBake.Preset and detail_preset.geometry != null:
			if detail_preset.changed.is_connected(_pattern_changed): detail_preset.changed.disconnect(_pattern_changed)
			if detail_preset.geometry.geometry_changed.is_connected(_pattern_changed): detail_preset.geometry.geometry_changed.disconnect(_pattern_changed)
			if detail_preset.generator_recipe != null and detail_preset.generator_recipe.changed.is_connected(_pattern_changed): detail_preset.generator_recipe.changed.disconnect(_pattern_changed)
		detail_preset = value
		if detail_preset != null and PatternBake.validation_errors(detail_preset).is_empty():
			detail_preset.changed.connect(_pattern_changed)
			detail_preset.geometry.geometry_changed.connect(_pattern_changed)
			if detail_preset.generator_recipe != null: detail_preset.generator_recipe.changed.connect(_pattern_changed)
		_pattern_changed()
@export_storage var detail_variant := 0
@export_storage var detail_mixed := true
var _pattern_data: Dictionary = {}
@export_storage var painted_only := false:
	set(value):
		painted_only=value
		if is_inside_tree():Preparation.moved_sleeping_patch(self)
var _density_decode_error:=""
var _density_bad_blob:=PackedByteArray()
var _density_storage_valid:=true
var density_cells: Dictionary = {}:
	set(value):
		# Brush/history already replace complete snapshots. Keep the stored one
		# immutable so property-list refreshes can reuse validation safely, with
		# no hash collisions, stale aliases or another full mask copy in RAM.
		density_cells = value.duplicate()
		density_cells.make_read_only()
		_density_storage_valid=Detail.validation_errors(density_cells).is_empty()
		_dirty = true
		_wake_preparation()
		_density_decode_error="";_density_bad_blob=PackedByteArray()
var density_mask:PackedByteArray=PackedByteArray():
	get:return _density_bad_blob if not _density_decode_error.is_empty() else Detail.encode_mask(density_cells)
	set(value):
		var decoded:=Detail.decode_mask(value)
		if not decoded.error.is_empty():
			_density_decode_error=decoded.error;_density_bad_blob=value;_dirty=true
		else:density_cells=decoded.cells
@export_range(0.0, 1.0, 0.05) var detail_jitter := 0.8:
	set(value): detail_jitter = value; _dirty = true
@export_range(0.0, 0.75, 0.05) var detail_variation := 0.25:
	set(value): detail_variation = value; _dirty = true
@export_range(0.0, 180.0, 5.0) var detail_yaw := 180.0:
	set(value): detail_yaw = value; _dirty = true
var _detail_preview: Dictionary = {}:
	set(value):
		_detail_preview = value
		_wake_preparation() # Existing brush drafts respond immediately, even on a sleeping patch.
var _detail_transform_cache: Dictionary = {}
var _detail_cache_key := 0
var detail_generations := 0
var detail_disk_hits := 0
static var _pebble_meshes: Dictionary = {}
@export var size_blocks := Vector2(5, 4):
	set(value):
		size_blocks = value.max(Vector2(0.1, 0.1))
		_dirty = true
		if is_inside_tree():Preparation.moved_sleeping_patch(self)
@export_range(0.0, 200.0, 1.0) var tufts_per_block := 100.0:
	set(value):
		tufts_per_block = value
		_dirty = true
@export_range(0.2, 4.0, 0.05) var tuft_size := 1.0:
	set(value):
		tuft_size = value
		_dirty = true
		if is_inside_tree():Preparation.moved_sleeping_patch(self)
@export var scatter_seed := 7:
	set(value):
		scatter_seed = value
		_dirty = true
var _dirty := true
var _rebuilding := false:
	set(value):
		_rebuilding=value
		if not value:
			_pending_material=null;_material_role_binding=false;_material_role_refreshes.clear()
var _pending_material:ShaderMaterial
var _material_role_binding:=false
var _material_role_refreshes:Dictionary={} # Latest profile commands only while role IO awaits.
var _detail_resident := false
var _detail_poll_projection_id := 0
var _detail_priority_pending := false
var _detail_fade_state:Array=[]
var _detail_poll_epoch:=-1
var _detail_poll_area:=Rect2()
var _detail_context:WeakRef
var _detail_context_projection_id:=0
var _map_ref:WeakRef

func _wake_preparation() -> void:
	set_process(true)
	if not is_inside_tree():return
	_detail_priority_pending=true
	var map:=_map()
	if map==null:return
	var projection:=map.get_node_or_null("DerivedCompactWorldTerrain")
	if projection!=null:Preparation.for_projection(projection).prioritize(self)

func detail_preparation_pending() -> bool:
	return _detail_resident and (_dirty or _rebuilding)
var _look := 0
var _visual: MultiMeshInstance3D
static var _meshes: Dictionary = {}
static var _coloured_meshes: Dictionary = {}
var _transform := Transform3D.IDENTITY
var _revision := -1
var _surface_stamp:Array=[]
var _material_layout: Array = []
var _area_valid:=false
var _area_bounds:=Rect2()
var _area_map_id:=0
var _area_unit:=0.0
var _area_transform:=Transform3D.IDENTITY
var _area_painted:=false
var _area_size:=Vector2.ZERO
var _area_tuft_size:=0.0

func _init()->void:
	# The default dictionary also needs the snapshot contract before any caller
	# can access it; member initializers do not invoke their own setters.
	density_cells={}

func _get_property_list()->Array[Dictionary]:
	# Only these two properties have dynamic storage. _validate_property would
	# enter GDScript for every inherited Node3D property on every scene-tree
	# refresh, even for distant patches. Keep the saved names/types unchanged.
	return [{"name":"density_cells","type":TYPE_DICTIONARY,"usage":PROPERTY_USAGE_NONE if _density_storage_valid else PROPERTY_USAGE_STORAGE},
		{"name":"density_mask","type":TYPE_PACKED_BYTE_ARRAY,"usage":PROPERTY_USAGE_STORAGE if _density_storage_valid else PROPERTY_USAGE_NONE}]

func _ready() -> void:
	# Establish the empty derived host during scene entry. Streaming later only
	# swaps disposable buffers/materials; adding a child for each newly prepared
	# patch repeatedly invalidates the editor's entire large scene tree.
	_ensure_visual()
	add_to_group(&"ember_grass_patches")
	if painted_only and _map() != null: _look = maxi(0, _map().world_look)
	_register_detail_poll.call_deferred()

func _ensure_visual()->void:
	if is_instance_valid(_visual):return
	_visual=MultiMeshInstance3D.new()
	_visual.name="DerivedGrass"
	_visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.hide()
	add_child(_visual,false,Node.INTERNAL_MODE_BACK)

func _register_detail_poll() -> void:
	if not is_inside_tree() or (Engine.is_editor_hint() and owner == null) or not _detail_preview.is_empty(): return
	var map := _map()
	if map == null: return
	var projection := map.get_node_or_null("DerivedCompactWorldTerrain")
	if projection != null and projection.document != null and projection.ground_style == 1:
		Preparation.for_projection(projection).sleep_patch(self)

func _notification(what:int)->void:
	if what==NOTIFICATION_TRANSFORM_CHANGED and _detail_poll_projection_id!=0 and is_inside_tree():
		Preparation.moved_sleeping_patch(self)

func _exit_tree() -> void:
	# Undo/Redo can reattach this exact node without another _ready().
	_watch_object_surface(_map(),false)
	Preparation.cancel_patch(self)
	_detail_poll_projection_id = 0
	_detail_context=null;_detail_context_projection_id=0;_detail_poll_epoch=-1
	_map_ref=null
	_area_valid=false
	_dirty=true
	set_process(true)

func _world_area()->Rect2:
	var map:=_map()
	var unit:float=map.imported_tile_size
	var map_id:=map.get_instance_id()
	var current_transform:=global_transform
	if _area_valid and _area_map_id==map_id and _area_unit==unit and _area_transform==current_transform and _area_painted==painted_only and _area_size==size_blocks and _area_tuft_size==tuft_size:
		return _area_bounds
	var area:=Rect2(Vector2.ZERO,Vector2.ONE*Detail.PATCH_M) if painted_only else Rect2(-size_blocks*0.5,size_blocks)
	var low:=Vector2.INF;var high:=-low
	for p in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:
		var world:=to_global(Vector3(p.x*unit,0,p.y*unit));var q:=Vector2(world.x,world.z)
		low=low.min(q);high=high.max(q)
	_area_bounds=Rect2(low,high-low).grow(0.35*unit*tuft_size)
	_area_map_id=map_id;_area_unit=unit;_area_transform=current_transform
	_area_painted=painted_only;_area_size=size_blocks;_area_tuft_size=tuft_size;_area_valid=true
	return _area_bounds

func _watch_object_surface(map:EmberMapLoader,active:bool)->void:
	if map==null:return
	var connected:=map.surface_object_changed.is_connected(_object_surface_changed)
	if active:
		if not connected:map.surface_object_changed.connect(_object_surface_changed)
	elif connected:map.surface_object_changed.disconnect(_object_surface_changed)

func _object_surface_changed(bounds:AABB)->void:
	# Unloaded patches hold no placement buffers. Placement inputs are rebuilt
	# on return; do not scan the entire distant meadow per object. Unpainted
	# scatter also snapshots object obstruction bounds before awaiting cache IO.
	if not _detail_resident:_dirty=true;return
	if not is_inside_tree() or _map()==null:return
	if _world_area().intersects(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)),true):_dirty=true


func apply_voxel_light_settings(map: EmberMapLoader) -> void:
	for material in _material_targets():map.bind_voxel_light(material, _look, map.imported_tile_size)

func _material_targets()->Array[ShaderMaterial]:
	# A cache await can hold a candidate while the old buffer remains visible.
	# Preview/light edits must reach both, without regenerating placement.
	var targets:Array[ShaderMaterial]=[]
	if is_instance_valid(_visual) and _visual.material_override is ShaderMaterial:targets.append(_visual.material_override)
	if _pending_material!=null and not _material_role_binding and _pending_material not in targets:targets.append(_pending_material)
	return targets


func set_material_light(mode: int, gray: bool) -> void:
	for material in _material_targets():
		material.set_shader_parameter("material_light_mode", mode)
		material.set_shader_parameter("material_gray_preview", gray)
		Materials.refresh_existing_terrain_features(material)


func refresh_shared_material(pattern: EmberCompactTerrainPattern = null, id := "") -> void:
	if detail_kind == 2: return # This source keeps its own palette, independent of terrain artwork.
	var map := _map()
	if map == null: return
	var projection = map._visual_surface_projection
	if not is_instance_valid(projection) or projection.document == null: return
	var source = projection.document
	if _material_role_binding:
		if pattern==null:
			_material_role_refreshes.clear();_material_role_refreshes[""]=[pattern,id]
		else:
			for slot in source.palette_surface_roles.size():
				if source.material_id_for_palette(slot)==id:
					_material_role_refreshes[id]=[pattern,id];break
	for material in _material_targets():
		if detail_kind == 1:
			Materials.set_compact_terrain_roles(material, PackedStringArray(["stone"]), PackedStringArray(["cartoon_stone"]), PackedColorArray(), {id: pattern} if pattern != null else {})
			continue
		if pattern == null:
			Materials.set_compact_terrain_roles(material, source.palette_surface_roles, source.palette_material_ids, source.palette)
			if detail_kind == 0 and _look == 0:
				_bind_grass_cards(material, source.palette_surface_roles.find("grass"))
			if detail_kind == 3:
				FlowerCover.bind(material,_cover_preview if _cover_preview != null else cover_pattern,source.palette_surface_roles.find("grass"))
		else:
			for slot in source.palette_surface_roles.size():
				if source.material_id_for_palette(slot) != id: continue
				Materials.update_grass_light_profile(material, slot, pattern)
				Materials.update_style_rim_profile(material, slot, pattern)


func set_world_look(value: int) -> void:
	_look = maxi(0, value)
	_dirty = true


func is_detail_stone() -> bool:
	return painted_only and (detail_kind == 1 or (detail_kind == 2 and detail_preset is PatternBake.Preset and detail_preset.kind == PatternBake.Preset.KIND_GENERATED_VOLUME and detail_preset.generator_recipe != null and detail_preset.generator_recipe.generator_id == "rock"))


func prepared_look_mesh(look: int) -> ArrayMesh:
	if detail_kind == 3: return FlowerCover.mesh(_cover_preview if _cover_preview != null else cover_pattern) # Painted foliage stays thin in every world.
	# Small ground stones keep their faceted shape; the voxel world omits this decoration.
	if is_detail_stone(): look = 1
	if detail_kind == 2: return _pattern_data.variants[detail_variant].meshes[look] if not _pattern_data.is_empty() else ArrayMesh.new()
	if detail_kind == 1: return _pebble_look_mesh(look)
	if not _meshes.has(look):
		if look == 0:
			_meshes[look] = Fixture.grass_card_mesh()
		else:
			# Preserve the accepted voxel silhouette independently of the new detailed blades.
			var original: ArrayMesh = load("res://prefabs/voxels/meshes/environment_review_grass.res").mesh
			_meshes[look] = Styles.grass_mesh(original, look, Fixture.grass_tuft_outline(), {"pixel_m": 0.0625, "coverage": true})
	return _meshes[look]


func prepared_coloured_look_mesh(look: int, slot: int) -> ArrayMesh:
	if detail_kind == 3 or (detail_kind == 0 and look == 0): return prepared_look_mesh(look) # Cards keep local atlas UVs; the material owns their palette slot.
	if detail_kind == 2: return prepared_look_mesh(look)
	if detail_kind == 1: slot = 0
	var key := Vector3i(detail_kind,look,slot)
	if _coloured_meshes.has(key): return _coloured_meshes[key]
	var mesh := prepared_look_mesh(look)
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	for i in colors.size():
		colors[i] = Color(1,0,0,float(slot)/255.0)
		uv[i] = Vector2(slot,slot)/255.0
		uv2[i] = Vector2(float(slot)/255.0,0)
	arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_TEX_UV] = uv; arrays[Mesh.ARRAY_TEX_UV2] = uv2
	if detail_kind == 1:
		for channel in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1): arrays[channel] = null
	var colored := ArrayMesh.new(); colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_coloured_meshes[key] = colored
	return colored


func _process(_delta: float) -> void:
	var began:=Time.get_ticks_usec()
	var map := _map()
	if map == null: return
	var projection := map.get_node_or_null("DerivedCompactWorldTerrain")
	if projection == null or projection.document == null: return
	var context:RefCounted=_detail_context.get_ref() if _detail_context!=null else null
	if context==null or context._released or _detail_context_projection_id!=projection.get_instance_id():
		context=Preparation.for_projection(projection)
		_detail_context=weakref(context);_detail_context_projection_id=projection.get_instance_id();_detail_poll_epoch=-1
	var epoch:int=context.detail_poll_epoch() if not Engine.is_editor_hint() else -1
	var area:=_world_area()
	if epoch>=0 and epoch==_detail_poll_epoch and area==_detail_poll_area and _detail_resident and not _dirty and _revision==projection.column_revision() and global_transform==_transform and is_instance_valid(_visual) and _visual.material_override is ShaderMaterial and _detail_fade_state.size()==6:
		var material:=_visual.material_override as ShaderMaterial
		if material.get_instance_id()==_detail_fade_state[0] and material.shader.get_instance_id()==_detail_fade_state[1] and (material.get_shader_parameter("ember_anomaly_prepared")==true)==_detail_fade_state[5]:
			context.finish_detail(began)
			return
	_update_detail_patch(map,projection)
	_detail_poll_epoch=epoch;_detail_poll_area=area
	context.finish_detail(began)

func _update_detail_patch(map:EmberMapLoader,projection:Node3D)->void:
	var resident:bool=projection.detail_area_resident(_world_area(),_detail_resident)
	if not resident:
		_watch_object_surface(map,false)
		if _detail_resident:
			_detail_resident=false
			Preparation.cancel_patch(self)
			_dirty=true
			_detail_transform_cache.clear()
			_surface_stamp.clear()
			if is_instance_valid(_visual):
				_visual.multimesh=null
				_visual.material_override=null
				_visual.hide()
			_detail_fade_state.clear()
		if (not Engine.is_editor_hint() or owner != null) and _detail_preview.is_empty():
			Preparation.for_projection(projection).sleep_patch(self)
		return
	_detail_resident=true
	_watch_object_surface(map,true)
	_update_detail_fade(projection,map)
	if _rebuilding:return
	if projection._live_brush_active: return
	if _surface_stamp.is_empty() and not _dirty and is_instance_valid(_visual):_surface_stamp=_surface_signature(projection)
	if global_transform != _transform:_dirty=true
	if projection.column_revision()!=_revision:
		if not _dirty and _surface_signature(projection)!=_surface_stamp:_dirty=true
		_revision=projection.column_revision()
	if not _dirty: return
	# Residency/fade and all invalidators still run for a clean resident. Only a
	# rebuild needs ready terrain: do not rescan its tiles every rendered frame.
	if projection.editor_detail_active():
		if not projection.detail_area_ready(_world_area()):return
	elif projection.pending_tile_count()>0:return
	if Engine.is_editor_hint() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	if not Engine.is_editor_hint() and not Preparation.for_projection(projection).available(): return
	_dirty = false
	_transform = global_transform
	_revision = projection.column_revision()
	_rebuilding = true
	_rebuild.call_deferred(map, projection)


func _scatter_current(map: EmberMapLoader, projection: Node3D) -> bool:
	if not _detail_resident:return false
	if not is_inside_tree() or not is_instance_valid(map) or not is_instance_valid(projection) or projection.document==null or map.get_node_or_null("DerivedCompactWorldTerrain")!=projection or projection._live_brush_active or global_transform!=_transform or _dirty:return false
	if projection.column_revision()!=_revision:
		if _surface_signature(projection)!=_surface_stamp:return false
		_revision=projection.column_revision()
	return true


func _update_detail_fade(projection:Node3D,map:EmberMapLoader)->void:
	if not is_instance_valid(_visual) or not _visual.material_override is ShaderMaterial:return
	var material:=_visual.material_override as ShaderMaterial
	var active:bool=projection.editor_detail_active()
	var anchor:Vector3=projection.detail_world_anchor()
	var fade:=Vector2(projection.detail_policy.detail_fade_begin_m,projection.detail_policy.detail_fade_end_m)*map.imported_tile_size
	var anomaly_active:bool=material.get_shader_parameter("ember_anomaly_prepared")==true
	var state:Array=[material.get_instance_id(),material.shader.get_instance_id(),active,anchor,fade,anomaly_active]
	if state==_detail_fade_state:return
	var fully_faded:=false
	if active and not anomaly_active:
		var area:=_world_area();var focus:=Vector2(anchor.x,anchor.z)
		# Every instance root lies inside this conservative patch area. Once
		# even its nearest edge is past fade-end, the vertex shader collapses
		# every instance to zero. Keep its resident buffer, skip the empty draw.
		fully_faded=focus.distance_to(focus.clamp(area.position,area.end))>=fade.y
	_visual.visible=not fully_faded and not (is_detail_stone() and _look==2)
	material.set_shader_parameter("world_detail_fade_enabled",active)
	material.set_shader_parameter("world_detail_anchor",anchor)
	material.set_shader_parameter("world_detail_fade_range",fade)
	_detail_fade_state=state

func _surface_signature(projection:Node3D)->Array:
	var source=projection.document
	var unit:float=_map().imported_tile_size
	var area:=Rect2(Vector2.ZERO,Vector2.ONE*Detail.PATCH_M) if painted_only else Rect2(-size_blocks*0.5,size_blocks)
	var radius:=0.25 if painted_only else 0.128*1.18*tuft_size+0.035
	if painted_only and detail_kind==2:
		if not _pattern_data.is_empty() and _pattern_data.has("variants") and detail_variant<_pattern_data.variants.size():
			radius=0.0
			for mesh:ArrayMesh in _pattern_data.variants[detail_variant].meshes:
				var box:=mesh.get_aabb();radius=maxf(radius,maxf(box.size.x,box.size.z)*0.45*tuft_size*(1.0+detail_variation))
		else:radius=2.0
	var low:=Vector2.INF;var high:=-Vector2.INF
	for point in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:
		var world:=to_global(Vector3(point.x*unit,0,point.y*unit))
		for offset in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:
			var local:=projection.to_local(world+Vector3(offset.x,0,offset.y)*radius*unit)
			var cell:=Vector2(local.x,local.z);low=low.min(cell);high=high.max(cell)
	# Four raw columns beyond the sampled footprint cover material blending too.
	low=(low-Vector2.ONE*4).max(Vector2.ZERO);high=(high+Vector2.ONE*4).min(Vector2(source.width-1,source.depth-1))
	var result:Array=[projection.get_instance_id(),projection.global_transform,projection.ground_style,source.width,source.depth,source.origin_y,source.palette_surface_roles.duplicate(),source.palette_material_ids.duplicate(),source.palette.duplicate()]
	if painted_only:
		var objects:Array=[];var world_area:=_world_area()
		for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
			if not _map().is_ancestor_of(prop):continue
			var visual:=prop.get_node_or_null("Mesh") as MeshInstance3D
			if visual==null or visual.mesh==null:continue
			var box:AABB=visual.global_transform*visual.mesh.get_aabb()
			if world_area.intersects(Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)),true):objects.append(prop.detail_surface_signature())
		result[1]=[projection.global_transform,objects,"object-roots-v1"]
	for y in range(floori(low.y/64),floori(high.y/64)+1):
		for x in range(floori(low.x/64),floori(high.x/64)+1):result.append([Vector2i(x,y),projection.surface_tile_revision(Vector2i(x,y))])
	return result


func _map() -> EmberMapLoader:
	# Clean resident callbacks and their bounds queries use the same owner.
	# Cache only while attached: reparent/Undo exits the tree and clears this
	# weak reference, while detached authoring queries still resolve ancestry.
	if _map_ref!=null:
		var cached:=_map_ref.get_ref() as EmberMapLoader
		if cached!=null:return cached
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is EmberMapLoader:
			if is_inside_tree():_map_ref=weakref(ancestor)
			return ancestor
		ancestor = ancestor.get_parent()
	return null


func _bind_grass_cards(material: ShaderMaterial, slot: int) -> void:
	material.set_shader_parameter("flower_atlas", GRASS_CARD_ATLAS)
	material.set_shader_parameter("flower_palette_slot", float(slot))
	material.set_shader_parameter("flower_tint", Color.WHITE)


func _rebuild(map: EmberMapLoader, projection: Node3D) -> void:
	if not await _wait_preparation(map,projection): return
	if not painted_only and detail_kind in [0,3]:
		if not await Preparation.prepare_shader(detail_kind == 3 or _look == 0,self,func():return not _scatter_current(map,projection)):
			_rebuilding=false;_dirty=true;return
		if not await _wait_preparation(map,projection):return
	_ensure_visual() # Also supports a live script refresh of an older patch.
	if painted_only:
		await _rebuild_painted(map, projection)
		return
	# Admission only queues work. Surface scans belong to the shared budget;
	# painted patches establish their own stamp in _rebuild_painted below.
	_surface_stamp=_surface_signature(projection)
	var document = projection.document
	var slot: int = document.palette_surface_roles.find("grass")
	if slot < 0:
		_visual.hide()
		_rebuilding = false
		return
	_visual.show()
	# Both ordinary and local looks use the same palette/blend layout.
	var colored := prepared_coloured_look_mesh(_look,slot)
	var material := _visual.material_override as ShaderMaterial
	var layout := [document.palette_surface_roles.duplicate(),document.palette_material_ids.duplicate(),document.palette.duplicate(),_look == 0]
	if material == null or layout != _material_layout:
		material = Materials.compact_flower_material() if _look == 0 else Materials.compact_grass_material()
		Materials.set_compact_terrain_roles(material, document.palette_surface_roles, document.palette_material_ids, document.palette)
		_material_layout = layout
	if _look == 0: _bind_grass_cards(material, slot)
	material.set_shader_parameter("smooth_surface_enabled", true)
	material.set_shader_parameter("painterly_blades", true)
	material.set_shader_parameter("ember_texture_world_unit", map.imported_tile_size)
	material.set_shader_parameter("material_light_mode", map.compact_material_light_mode)
	material.set_shader_parameter("material_gray_preview", map.compact_material_gray_preview)
	# Port of the accepted grass-field scatter: 10 cm jittered grid, joined
	# noise patches, short broad silhouettes, no random pigment or tiny shadows.
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	var patches := FastNoiseLite.new()
	patches.seed = 7153 + scatter_seed - 7
	patches.frequency = 0.72
	patches.fractal_octaves = 2
	var transforms: Array[Transform3D] = []
	var unit := map.imported_tile_size
	var spacing := 1.0/sqrt(maxf(tufts_per_block, 0.01))
	var weights_cache := {}
	var blocked: Array[Rect2] = []
	for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
		if not map.is_ancestor_of(prop): continue
		var visual := prop.get_node_or_null("Mesh") as MeshInstance3D
		if visual == null or visual.mesh == null: continue
		var bounds: AABB = visual.global_transform*visual.mesh.get_aabb()
		blocked.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)))
	var preparation = Preparation.for_projection(projection)
	_pending_material=material
	var disk_key: String = await preparation.content_key(projection,_surface_stamp,[false,_look,size_blocks,tufts_per_block,tuft_size,scatter_seed,global_transform,unit,blocked],self,func():return not _scatter_current(map,projection))
	if not _scatter_current(map,projection): _rebuilding=false; _dirty=true; return
	var stored: Dictionary = await preparation.read_async(disk_key,self,func():return not _scatter_current(map,projection))
	if not await _wait_preparation(map,projection):return
	if stored.has(_look):
		transforms.assign(stored[_look]); detail_disk_hits+=1
		_publish_scatter(transforms,colored,material,map,projection); return
	var smooth = preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
	for z in floori(size_blocks.y/spacing):
		for x in floori(size_blocks.x/spacing):
			if x%16 == 0 and not preparation.available() and not await _wait_preparation(map,projection): return
			if tufts_per_block <= 0 or transforms.size() >= 20000: continue
			var p := -size_blocks*0.5+Vector2(x+0.5,z+0.5)*spacing+Vector2(rng.randf_range(-0.4,0.4),rng.randf_range(-0.4,0.4))*spacing
			var point := to_global(Vector3(p.x*unit, 0, p.y*unit))
			var obstruction := false
			for bounds in blocked:
				if bounds.has_point(Vector2(point.x,point.z)): obstruction = true; break
			if obstruction: continue
			var floor_hit: Dictionary = projection.floor_surface_sample(point)
			if not floor_hit.get("solid", false) or floor_hit.get("material_role") != "grass": continue
			var cell: Vector2i = floor_hit.cell
			var index: int = document.column_index(cell.x, cell.y)
			if document.column_value("water_levels", index) > document.column_value("heights", index): continue
			var weights: Dictionary = smooth.material_weights(document, cell, weights_cache)
			var grass: float = weights.get(slot, 0.0)
			if grass < 0.60: continue
			var patch := smoothstep(-0.35,0.32,patches.get_noise_2dv(p))
			var density := lerpf(0.78,1.0,patch)*lerpf(0.60,1.0,smoothstep(0.60,0.95,grass))
			if rng.randf() > density: continue
			var width := rng.randf_range(0.92,1.18)*tuft_size
			var height := lerpf(1.40,2.10,patch)*rng.randf_range(0.94,1.06)*tuft_size
			point = floor_hit.position
			if not _footprint_clear(point, (0.128*width+0.035)*unit, projection, unit): continue
			if _look > 0:
				var local := projection.to_local(point)
				var q := Vector2(local.x, local.z)
				local.y = float(document.origin_y + document.column_value("heights", index)) if _look == 2 else float(projection.LookBake.plane(projection._smooth_field(Vector2i(cell.x/64, cell.y/64)), q).height)
				point = projection.to_global(local)
			var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(width,height,width)*unit)
			transforms.append(global_transform.affine_inverse()*Transform3D(basis, point))
	if not await _wait_preparation(map,projection): return
	preparation.write(disk_key,{_look:transforms},func():return not _scatter_current(map,projection))
	_publish_scatter(transforms, colored, material, map, projection)


func _publish_scatter(transforms: Array[Transform3D], colored: ArrayMesh, material: ShaderMaterial, map: EmberMapLoader, projection: Node3D) -> void:
	var scatter := MultiMesh.new()
	scatter.transform_format = MultiMesh.TRANSFORM_3D
	scatter.mesh = colored
	scatter.instance_count = transforms.size()
	for i in transforms.size(): scatter.set_instance_transform(i, transforms[i])
	if not _scatter_current(map,projection):
		_rebuilding = false; _dirty = true; return
	map.bind_voxel_light(material, _look, map.imported_tile_size)
	Materials.refresh_terrain_features(material)
	_visual.material_override = material
	_visual.multimesh = scatter
	_visual.visible = not (is_detail_stone() and _look == 2)
	_update_detail_fade(projection,map)
	# _scatter_current already validated the stamp; no await or source edit
	# occurs during this publication, so another complete scan is redundant.
	_rebuilding = false
	_detail_priority_pending=false


func validation_errors() -> Array[String]:
	var errors := Detail.validation_errors(density_cells)
	if not _density_decode_error.is_empty():errors.append(_density_decode_error)
	if detail_kind not in [0, 1, 2, 3]: errors.append("Неизвестный набор деталей.")
	if detail_kind == 3: errors.append_array(FlowerCover.validation_errors(cover_pattern))
	if detail_kind == 2:
		errors.append_array(PatternBake.validation_errors(detail_preset))
		if detail_variant < 0 or detail_variant >= 8: errors.append("Некорректный вариант набора.")
		elif errors.is_empty():
			var count: int = PatternBake.variant_count(detail_preset)
			if detail_variant >= int(count): errors.append("В источнике нет этого варианта.")
	if not is_finite(tuft_size) or tuft_size < 0.2 or tuft_size > 4.0: errors.append("Некорректный размер деталей.")
	if not is_finite(detail_jitter) or detail_jitter < 0 or detail_jitter > 1: errors.append("Некорректный разброс.")
	if not is_finite(detail_variation) or detail_variation < 0 or detail_variation > 0.75: errors.append("Некорректная вариация размера.")
	if not is_finite(detail_yaw) or detail_yaw < 0 or detail_yaw > 180: errors.append("Некорректный разброс поворота.")
	return errors


func _pattern_changed(_indices := PackedInt32Array()) -> void:
	_pattern_data = {}; _detail_transform_cache.clear(); _dirty = true


func preview_cover(pattern: EmberCompactTerrainPattern) -> void:
	_cover_preview = pattern; _cover_changed()


func _cover_changed() -> void:
	if detail_kind != 3 or _visual == null or _visual.material_override == null: _dirty = true; return
	var pattern := _cover_preview if _cover_preview != null else cover_pattern
	if not FlowerCover.validation_errors(pattern).is_empty(): _dirty=true; _visual.hide(); return
	if _visual.multimesh.mesh != FlowerCover.mesh(pattern):
		_dirty = true; return # Existing rebuild invalidates sphere geometry when the authored shape changes.
	var map := _map()
	if map == null or map._visual_surface_projection == null: return
	var slot: int = map._visual_surface_projection.document.palette_surface_roles.find("grass")
	for material in _material_targets():FlowerCover.bind(material,pattern,slot)
	_visual.show()
	map.anomaly_materials_changed.emit()


func _pebble_look_mesh(look: int) -> ArrayMesh:
	if not _pebble_meshes.has(look):
		# Reuse the existing authored stone and its three converters once per process.
		var prop: EmberVoxelProp = load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate()
		prop.set_world_look(1)
		var bounds: AABB = prop.get_node("Mesh").mesh.get_aabb()
		var scale_value := 0.12 / maxf(bounds.size.x, bounds.size.z)
		var bottom := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		var transform_value := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_value), -bottom * scale_value)
		for variant in [0, 1, 2]:
			var mesh: ArrayMesh
			if variant == 0: mesh = prop._living_for(null, "")
			else:
				prop.set_world_look(variant)
				mesh = prop.get_node("Mesh").mesh
			if mesh == null: mesh = prop._hull_mesh
			var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for part in mesh.get_surface_count(): surface.append_from(mesh, part, transform_value)
			_pebble_meshes[variant] = surface.commit()
		prop.free()
	return _pebble_meshes[look]


func _rebuild_painted(map: EmberMapLoader, projection: Node3D) -> void:
	var cells: Dictionary = _detail_preview.get("cells", density_cells)
	if not Detail.validation_errors(cells).is_empty() or not validation_errors().is_empty():
		_visual.hide(); _rebuilding = false; return
	if detail_kind == 2:
		_pattern_data = await PatternBake.prepare(detail_preset,self)
		if not _scatter_current(map,projection): _rebuilding = false; _dirty = true; return
		if _pattern_data.has("error") or detail_variant >= _pattern_data.get("variants",[]).size():
			_visual.hide(); _rebuilding = false; return
	if not await _wait_preparation(map,projection): return
	var unit := map.imported_tile_size
	var slot: int = projection.document.palette_surface_roles.find("grass") if detail_kind in [0,3] else 0
	if slot < 0: _visual.hide(); _rebuilding = false; return
	if detail_kind in [0,3]:
		if not await Preparation.prepare_shader(detail_kind == 3 or _look == 0,self,func():return not _scatter_current(map,projection)):
			_rebuilding=false;_dirty=true;return
		if not await _wait_preparation(map,projection):return
	var colored := prepared_coloured_look_mesh(_look, slot)
	var material := Materials.compact_flower_material() if detail_kind == 3 or (detail_kind == 0 and _look == 0) else Materials.compact_grass_material() if detail_kind == 0 else Materials.compact_terrain_material()
	var source = projection.document
	if detail_kind in [0,3]:
		var layout:Array=[source.palette_surface_roles.duplicate(),source.palette_material_ids.duplicate(),source.palette.duplicate()]
		_pending_material=material;_material_role_binding=true
		if not await Preparation.for_projection(projection).bind_saved_material_roles_async(material,layout[0],layout[1],layout[2],self,func():return not _scatter_current(map,projection)):
			_rebuilding=false;_dirty=true;return
		_material_role_binding=false
		if not _scatter_current(map,projection) or projection.document!=source or layout!=[source.palette_surface_roles,source.palette_material_ids,source.palette]:
			_rebuilding=false;_dirty=true;return
		var refreshes:Array=_material_role_refreshes.values();_material_role_refreshes.clear()
		for refresh:Array in refreshes:refresh_shared_material(refresh[0],refresh[1])
		if not await _wait_preparation(map,projection):return
	elif detail_kind == 1: Materials.set_compact_terrain_roles(material, PackedStringArray(["stone"]), PackedStringArray(["cartoon_stone"]))
	else:
		var palette: PackedColorArray = _pattern_data.variants[detail_variant].palette
		var roles := PackedStringArray(); roles.resize(palette.size())
		Materials.set_compact_terrain_roles(material,roles,PackedStringArray(),palette)
	material.set_shader_parameter("smooth_surface_enabled", true)
	material.set_shader_parameter("painterly_blades", detail_kind in [0,3])
	if detail_kind == 3: FlowerCover.bind(material,_cover_preview if _cover_preview != null else cover_pattern,slot)
	if detail_kind == 0 and _look == 0: _bind_grass_cards(material,slot)
	material.set_shader_parameter("ember_texture_world_unit", unit)
	material.set_shader_parameter("material_light_mode", map.compact_material_light_mode)
	material.set_shader_parameter("material_gray_preview", map.compact_material_gray_preview)
	var transforms: Array[Transform3D] = []
	var seed_value: int = _detail_preview.get("seed", scatter_seed)
	var size_value: float = _detail_preview.get("size", tuft_size)
	var jitter: float = _detail_preview.get("jitter", detail_jitter)
	var variation: float = _detail_preview.get("variation", detail_variation)
	var yaw_range: float = _detail_preview.get("yaw", detail_yaw)
	_surface_stamp=_surface_signature(projection)
	var cache_key := hash([cells,seed_value,size_value,jitter,variation,yaw_range,detail_kind,_pattern_data.get("key",""),detail_variant,detail_mixed,_surface_stamp,global_transform,unit])
	if cache_key == _detail_cache_key and _detail_transform_cache.has(_look):
		_visual.show(); _publish_scatter(_detail_transform_cache[_look], colored, material, map, projection); return
	var detailed: Array[Transform3D] = []; var low_poly: Array[Transform3D] = []; var voxel: Array[Transform3D] = []
	var variants := {0:detailed,1:low_poly,2:voxel}
	var patch_origin := map.to_local(global_position) / unit
	var absolute_cell := Detail.cell_address(Vector2(patch_origin.x, patch_origin.z))
	var preparation = Preparation.for_projection(projection)
	_pending_material=material
	var disk_key: String = await preparation.content_key(projection,_surface_stamp,[true,Detail.encode_mask(cells),seed_value,size_value,jitter,variation,yaw_range,detail_kind,_pattern_data.get("key",""),detail_variant,detail_mixed,colored.get_aabb(),global_transform,unit,"object-roots-v1"],self,func():return not _scatter_current(map,projection))
	if not _scatter_current(map,projection): _rebuilding=false; _dirty=true; return
	var stored: Dictionary = await preparation.read_async(disk_key,self,func():return not _scatter_current(map,projection))
	if not await _wait_preparation(map,projection):return
	if stored.has(0) and stored.has(1) and stored.has(2) and stored[0].size()==stored[1].size() and stored[0].size()==stored[2].size():
		_detail_transform_cache=stored; _detail_cache_key=cache_key; detail_disk_hits+=1
		transforms.assign(stored[_look]); _visual.show()
		_publish_scatter(transforms,colored,material,map,projection); return
	# Footprint roots are only consumed by a new scatter. A valid disk hit
	# must not read back and scan every look mesh for every painted patch.
	var roots:=PackedVector3Array()
	if detail_kind in [0,3]:
		for variant in 3:
			var mesh:=prepared_coloured_look_mesh(variant,slot)
			var low_y:=mesh.get_aabb().position.y
			for vertex:Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if vertex.y<=low_y+0.0001 and not vertex in roots:roots.append(vertex)
	# One broad phase per cold patch, using the existing physical-surface owner.
	# Include every root and edge probe even for enlarged/rotated tufts. This
	# list is local to this cancellable rebuild, never a persistent spatial cache.
	var probe_radius := 0.28 * unit * tuft_size
	for root_point in roots:
		probe_radius = maxf(probe_radius,root_point.length() * 1.6 * size_value * (1.0 + variation) * unit)
	var world_area := _world_area().grow(probe_radius)
	var candidates := map._solid_floor_candidates(AABB(Vector3(world_area.position.x,0,world_area.position.y),Vector3(world_area.size.x,0,world_area.size.y)))
	var terrain_job:RefCounted=null
	var foreground_cells:Dictionary=cells
	var worker_variants:Dictionary={};var foreground_ranges:Dictionary={}
	var terrain_cells:Dictionary=_terrain_only_cells(cells,candidates,unit,jitter) if detail_kind in [0,3] else {}
	if not terrain_cells.is_empty():
		while not preparation.terrain_job_available():
			if not await preparation.wait_for_turn(self) or not _scatter_current(map,projection):
				_rebuilding=false;_dirty=true;return
		terrain_job=_terrain_scatter_job(projection,terrain_cells,absolute_cell,unit,seed_value,size_value,jitter,variation,yaw_range)
		if terrain_job!=null:
			terrain_job.collect_ranges=terrain_cells.size()!=cells.size()
			preparation.start_terrain_job(self,terrain_job)
			await terrain_job.ready
			if terrain_job.cancelled() or not _scatter_current(map,projection) or terrain_job.result.is_empty():
				_rebuilding=false;_dirty=true;return
			# Job completion is polled before node processing. Reacquire a budget
			# turn before foreground roots/merge, rather than doing that work on
			# top of the next full ground/scatter allowance in the same frame.
			if not await _wait_preparation(map,projection):return
			foreground_cells=cells.duplicate()
			for cell:Vector2i in terrain_cells:foreground_cells.erase(cell)
			if foreground_cells.is_empty():variants=terrain_job.result
			else:worker_variants=terrain_job.result
	if not foreground_cells.is_empty():
		var ordered := foreground_cells.keys(); ordered.sort()
		for cell: Vector2i in ordered:
			var begin:int=variants[0].size()
			var density := float(cells[cell])
			for candidate in Detail.CANDIDATES:
				if not preparation.available() and not await _wait_preparation(map,projection): return
				if detail_kind == 2 and detail_mixed and Detail.sample_variant(cell + absolute_cell,candidate,seed_value,_pattern_data.variants.size()) != detail_variant: continue
				var rng := RandomNumberGenerator.new(); rng.seed = Detail.sample_seed(cell + absolute_cell, candidate, seed_value)
				if rng.randf() >= density * Detail.CELL_M * Detail.CELL_M / Detail.CANDIDATES: continue
				var offset := Vector2(candidate % 4 + 0.5, floori(candidate / 4.0) + 0.5)
				offset += Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45)) * jitter
				var p := Vector2(cell) * Detail.CELL_M + offset * Detail.CELL_M / 4.0
				var point := to_global(Vector3(p.x * unit, 0, p.y * unit))
				var hit: Dictionary = map.surface_floor_sample_with_candidates(point,candidates)
				if not hit.get("solid", false): continue
				if hit.has("object") and detail_kind not in [0,3]:continue
				if detail_kind in [0,3] and hit.get("material_role") not in ["grass", "soil"]: continue
				if detail_kind == 1 and hit.get("material_role") != "sand": continue
				if hit.get("submerged",false):continue
				var on_object:bool=hit.has("object")
				var index:int=source.column_index(hit.cell.x,hit.cell.y) if not on_object else -1
				point = hit.position
				var size_random := rng.randf_range(1.0 - variation, 1.0 + variation) * size_value
				var yaw := rng.randf_range(-deg_to_rad(yaw_range),deg_to_rad(yaw_range))
				var footprint := maxf(colored.get_aabb().size.x,colored.get_aabb().size.z)*0.45 if detail_kind == 2 else 0.035
				if not on_object and not _footprint_clear(point, footprint * unit * size_random, projection, unit): continue
				var shape_scale := Vector3(1, 1.6, 1) if detail_kind == 0 else Vector3(1,0.35,1) if detail_kind == 1 else Vector3.ONE
				var basis := Basis(Vector3.UP, yaw).scaled(shape_scale * size_random * unit)
				if on_object and (hit.normal.y<0.55 or not _object_roots_clear(point,basis,roots,map,unit,candidates)):continue
				var outward:=_edge_direction(point,map,unit,candidates) if on_object and detail_kind==0 else Vector3.ZERO
				for variant in [0,1,2]:
					var placed := point
					if variant > 0 and not on_object:
						var local := projection.to_local(point)
						local.y = float(source.origin_y + source.column_value("heights", index)) if variant == 2 else float(projection.LookBake.plane(projection._smooth_field(Vector2i(hit.cell.x/64, hit.cell.y/64)), Vector2(local.x,local.z)).height)
						placed = projection.to_global(local)
					var placed_basis:=basis
					# Shear along blade height: all y=0 roots stay fixed. No new
					# shader/custom-data channel, geometry variant or detached fringe.
					if variant==0:placed_basis.y+=outward*basis.y.length()*0.45
					variants[variant].append(global_transform.affine_inverse() * Transform3D(placed_basis, placed))
			if not worker_variants.is_empty():foreground_ranges[cell]=Vector2i(begin,variants[0].size()-begin)
	if not worker_variants.is_empty():variants=Detail.merge_cells(cells,worker_variants,terrain_job.cell_ranges,variants,foreground_ranges)
	if not _scatter_current(map,projection): _rebuilding = false; _dirty = true; return
	_detail_transform_cache = variants; _detail_cache_key = cache_key; detail_generations += 1
	transforms.assign(variants[_look])
	_visual.show()
	if not await _wait_preparation(map,projection): return
	preparation.write(disk_key,variants,func():return not _scatter_current(map,projection))
	_publish_scatter(transforms, colored, material, map, projection)


func _terrain_only_cells(cells:Dictionary,candidates:Array,unit:float,jitter:float)->Dictionary:
	if candidates.is_empty():return cells
	var planar:=Transform2D(Vector2(global_basis.x.x,global_basis.x.z),Vector2(global_basis.z.x,global_basis.z.z),Vector2(global_position.x,global_position.z))
	if absf(planar.determinant())<0.00001:return {}
	var inverse:=planar.affine_inverse();var bounds:Array[Rect2]=[]
	for prop in candidates:
		# Live authoring previews may extend beyond the published physical bounds.
		if prop.authoring_preview!=null and is_instance_valid(prop.authoring_preview.get_ref()):return {}
		var box:AABB=prop.surface_floor_bounds()
		if box==AABB():return {}
		var low:=Vector2.INF;var high:=-Vector2.INF
		for point:Vector2 in [Vector2(box.position.x,box.position.z),Vector2(box.end.x,box.position.z),Vector2(box.end.x,box.end.z),Vector2(box.position.x,box.end.z)]:
			var local:Vector2=(inverse*point)/unit;low=low.min(local);high=high.max(local)
		bounds.append(Rect2(low,high-low))
	var result:Dictionary={}
	var halo:=maxf(0.0,absf(jitter)-1.0)*Detail.CELL_M*0.45/4.0+0.00001
	for cell:Vector2i in cells:
		var area:=Rect2(Vector2(cell)*Detail.CELL_M,Vector2.ONE*Detail.CELL_M).grow(halo)
		var clear:=true
		for box:Rect2 in bounds:
			if area.intersects(box,true):clear=false;break
		if clear:result[cell]=cells[cell]
	return result


func _terrain_scatter_job(projection:Node3D,cells:Dictionary,absolute_cell:Vector2i,unit:float,seed_value:int,size_value:float,jitter:float,variation:float,yaw_range:float)->RefCounted:
	if projection.ground_style!=1:return null
	var basis:=projection.global_basis
	# Tilted/sheared terrain and object-supported tufts retain the exact scene
	# query path. Ordinary upright terrain uses only immutable CPU snapshots.
	if absf(basis.x.y)+absf(basis.z.y)+absf(basis.y.x)+absf(basis.y.z)>0.00001 or basis.y.y<=0:return null
	var area:=_world_area();var low:=Vector2.INF;var high:=-Vector2.INF
	for p:Vector2 in [area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]:
		var local:=projection.to_local(Vector3(p.x,projection.global_position.y,p.y))
		low=low.min(Vector2(local.x,local.z));high=high.max(Vector2(local.x,local.z))
	var source=projection.document
	var bounds:=Rect2i(Vector2i(floori(low.x)-2,floori(low.y)-2),Vector2i(ceili(high.x)-floori(low.x)+5,ceili(high.y)-floori(low.y)+5)).intersection(Rect2i(0,0,source.width,source.depth))
	if not bounds.has_area():return null
	var snapshot=source.dense_window(bounds)
	var fields:Dictionary={}
	for z in range(bounds.position.y/64,(bounds.end.y-1)/64+1):
		for x in range(bounds.position.x/64,(bounds.end.x-1)/64+1):
			var key:=Vector2i(x,z);var field:Dictionary=projection._smooth_field(key)
			fields[key]={"start":field.start,"size":field.size,"heights":field.heights.duplicate()}
	var job:=Detail.TerrainJob.new()
	job.input={"bounds":bounds,"extent":Vector2i(source.width,source.depth),"heights":snapshot.heights.duplicate(),"tops":snapshot.top_materials.duplicate(),"water":snapshot.water_levels.duplicate(),"origin_y":source.origin_y,"roles":source.palette_surface_roles.duplicate(),"fields":fields,"cells":cells.duplicate(true),"absolute_cell":absolute_cell,"unit":unit,"seed":seed_value,"size":size_value,"jitter":jitter,"variation":variation,"yaw":yaw_range,"kind":detail_kind,"projection":projection.global_transform,"projection_inverse":projection.global_transform.affine_inverse(),"patch":global_transform,"patch_inverse":global_transform.affine_inverse()}
	return job

func _wait_preparation(map: EmberMapLoader, projection: Node3D) -> bool:
	if not _scatter_current(map,projection):
		_rebuilding=false;_dirty=true;return false
	var preparation = Preparation.for_projection(projection)
	# Editor scatter only runs inside the budget dispatcher. Deferred starts
	# and shader/worker completions otherwise sneak work before node processing
	# or consume the allowance while the editor is doing unrelated UI work.
	while not preparation.in_budget_turn() or not preparation.available():
		if not await preparation.wait_for_turn(self):
			_rebuilding=false;_dirty=true;return false
		if not _scatter_current(map,projection):
			_rebuilding=false; _dirty=true; return false
	if not _scatter_current(map,projection):
		_rebuilding=false; _dirty=true; return false
	return true

func _object_roots_clear(point:Vector3,basis:Basis,roots:PackedVector3Array,map:EmberMapLoader,unit:float,candidates:Variant=null)->bool:
	for root_point in roots:
		var root_world:=point+basis*root_point
		var sample:=map.surface_floor_sample_with_candidates(root_world,candidates)
		if not sample.get("solid",false) or sample.get("material_role") not in ["grass","soil"] or sample.get("submerged",false) or absf(sample.position.y-root_world.y)>0.04*unit:return false
	return true

func _edge_direction(point:Vector3,map:EmberMapLoader,unit:float,candidates:Variant=null)->Vector3:
	var outward:=Vector3.ZERO
	for i in 8:
		var p:=Vector2.from_angle(i*TAU/8.0);var direction:=Vector3(p.x,0,p.y)
		var sample:=map.surface_floor_sample_with_candidates(point+direction*0.28*unit*tuft_size,candidates)
		if not sample.get("solid",false) or sample.position.y<point.y-0.10*unit:outward+=direction
	return outward.normalized() if outward.length_squared()>0.1 else Vector3.ZERO


func _footprint_clear(center: Vector3, radius: float, projection: Node3D, unit: float) -> bool:
	return projection.floor_footprint_clear(center,radius,unit)
