@tool
extends Node3D
## Editor-only projection of the exact candidate strip, using the terrain tile mesher.

signal preview_built

const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const WaterRegions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const GeometryCache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
const MeshLOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")

var _candidate: TerrainResource
var _projection: EmberTerrainPilotProjection
var _saved_projection_position := Vector3.ZERO
var _saved_groups: Array[Dictionary] = []
var _pending: Array[Vector2i] = []
var _ground_material: Material
var _liquid_material: Material
var _area := Rect2i()
var _saved_hidden := {}
var _water_fields: RefCounted
var _water_fields_ready := false
var _look:=Vector2i(-99,-99)
var _preview_keys:Array[Vector2i]=[]
var _built_tiles:Dictionary={}
var _announced:=false
var _reuse_dry_tiles := false
var _preview_revision := -1
var _tile_jobs := {}
var _prepared_tiles := {}


func show_candidate(target: EmberMapLoader, previous: TerrainResource, candidate: TerrainResource, direction: String, along := -1, address := Vector2i(-1, -1)) -> bool:
	if target == null or previous == null or candidate == null or (direction not in Extension.DIRECTIONS and direction != "address"):
		return false
	_projection = target._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(_projection) or not _projection.is_inside_tree():
		return false
	_candidate = candidate
	_ground_material = _projection._ground_material
	_liquid_material = _projection._water_material
	scale = _projection.scale
	position = _projection.position
	var cells := Extension.Creation.SECTION_BLOCKS * TerrainResource.CELLS_PER_BLOCK
	var shift := Extension.scene_shift(direction, target.imported_tile_size)
	_saved_projection_position = _projection.position
	_projection.position += shift
	for group_name in ["Terrain", "Props", "Regions"]:
		var group := target.get_node_or_null(group_name) as Node3D
		if group != null:
			_saved_groups.append({"node": weakref(group), "position": group.position})
			group.position += shift
	_saved_hidden = _projection._editor_hidden_edge_keys.duplicate()
	if address.x >= 0:
		_area = Rect2i(address * cells, Vector2i(cells, cells))
	elif along >= 0:
		_area = Rect2i(Vector2i(previous.width if direction == "east" else 0, along * cells) if direction in ["west", "east"] else Vector2i(along * cells, previous.depth if direction == "south" else 0), Vector2i(cells, cells))
	else:
		_area = Rect2i(Vector2i(previous.width if direction == "east" else 0, previous.depth if direction == "south" else 0), Vector2i(cells, candidate.depth) if direction in ["west", "east"] else Vector2i(candidate.width, cells))
	var moved := Vector2i(cells / TerrainProjection.TILE_SIZE if direction == "west" else 0, cells / TerrainProjection.TILE_SIZE if direction == "north" else 0)
	for key in candidate.tile_keys(TerrainProjection.TILE_SIZE):
		if not Rect2i(key * TerrainProjection.TILE_SIZE, Vector2i.ONE * TerrainProjection.TILE_SIZE).intersects(_area.grow(TerrainProjection.TILE_SIZE)): continue
		_pending.append(key)
		var old_key := key - moved
		if _projection._tiles.has(old_key):
			_projection._editor_hidden_edge_keys[old_key] = true
			(_projection._tiles[old_key] as Node3D).hide()
	_add_border(previous, candidate, direction, cells)
	set_process(true)
	return true


func _process(_delta: float) -> void:
	if not is_instance_valid(_projection) or _candidate==null:return
	var look:=Vector2i(_projection.world_look,_projection.ground_style)
	if look!=_look:
		_cancel_tile_jobs()
		if _preview_keys.is_empty():_preview_keys.assign(_pending)
		else:_pending.assign(_preview_keys)
		_look=look;_announced=false
		_sync_look_materials()
	if _water_fields != null and not _water_fields_ready:
		if not _water_fields.prepare(3000,_liquid_material as ShaderMaterial,_ground_material as ShaderMaterial,Vector2(_projection.global_position.x,_projection.global_position.z)): return
		if not _water_fields.gpu_ready(): return
		_water_fields.commit(); _water_fields_ready = true
		_sync_look_materials()
		for entry: Dictionary in _water_fields.regions.values():
			entry.water.set_shader_parameter("water_flow_map",_water_fields.flow_texture)
			entry.water.set_shader_parameter("river_phase_map",_water_fields.phase_texture)
			entry.water.set_shader_parameter("ripple_cell_field",preload("res://scripts/prototypes/ember_compact_ripple_field.gd").texture())
			entry.water.set_shader_parameter("ripple_field_available",1.0)
	var started := Time.get_ticks_usec()
	if _reuse_dry_tiles and _look == Vector2i(0, 1):
		_process_dry_tiles(started)
	else:
		while not _pending.is_empty() and Time.get_ticks_usec() - started < 4000:
			var key: Vector2i = _pending.pop_front()
			var generated := MeshBuilder.build_tile(_candidate, key.x * TerrainProjection.TILE_SIZE, key.y * TerrainProjection.TILE_SIZE, TerrainProjection.TILE_SIZE, _projection.water_mesh_step, _projection.water_volume_sides,PackedVector4Array(),{},false,false,_look.y==1 and _look.x!=2,_projection.smooth_material_blend_enabled)
			_publish_tile(key, generated)
	if _pending.is_empty() and _tile_jobs.is_empty() and not _announced:
		_announced=true
		preview_built.emit()


func _process_dry_tiles(started: int) -> void:
	for key: Vector2i in _tile_jobs.keys():
		if Time.get_ticks_usec() - started >= 4000:
			break
		var record: Dictionary = _tile_jobs[key]
		if record.task >= 0:
			if not WorkerThreadPool.is_task_completed(record.task):
				continue
			WorkerThreadPool.wait_for_task_completion(record.task)
			record.task = -1
			if record.job.tile_data.is_empty():
				_cancel_tile_jobs()
				_pending.assign(_preview_keys)
				_reuse_dry_tiles = false
				return
			record.publication = MeshBuilder.EditorTilePublication.new(record.job.tile_data)
		var publication: RefCounted = record.publication
		while not publication.ready and Time.get_ticks_usec() - started < 4000:
			publication.advance()
		if publication.ready and Time.get_ticks_usec() - started < 4000:
			_prepared_tiles[key] = publication.result
			_publish_tile(key, publication.result)
			_tile_jobs.erase(key)
	var limit := clampi(OS.get_processor_count() - 4, 1, 4)
	while not _pending.is_empty() and _tile_jobs.size() < limit and Time.get_ticks_usec() - started < 4000:
		var key: Vector2i = _pending.pop_front()
		var cache := GeometryCache.new()
		cache.directory = ""
		var job := cache.editor_job(_candidate, key, _projection.smooth_material_blend_enabled, {"far_stride": 1})
		var cancellation := MeshLOD.Cancellation.new()
		var task := WorkerThreadPool.add_task(job.run.bind(cancellation.is_cancelled), false, "Ember road preview tile")
		if task < 0:
			_cancel_tile_jobs()
			_pending.assign(_preview_keys)
			_reuse_dry_tiles = false
			return
		_tile_jobs[key] = {"job":job, "task":task, "cancellation":cancellation}


func _cancel_tile_jobs() -> void:
	for record: Dictionary in _tile_jobs.values():
		record.cancellation.set_cancelled(true)
	for record: Dictionary in _tile_jobs.values():
		if record.task >= 0:
			WorkerThreadPool.wait_for_task_completion(record.task)
	_tile_jobs.clear()
	_prepared_tiles = {}


func take_prepared_tiles() -> Dictionary:
	if not _announced or _prepared_tiles.is_empty() or not is_instance_valid(_projection) or _preview_revision != _projection.column_revision():
		return {}
	if not _projection.can_reuse_dry_preview(_candidate, _preview_keys):
		return {}
	var prepared := _prepared_tiles
	_prepared_tiles = {}
	return prepared


func _publish_tile(key: Vector2i, generated: Dictionary) -> void:
	if _reuse_dry_tiles and _projection._tiles.has(key):
		_projection._editor_hidden_edge_keys[key] = true
		(_projection._tiles[key] as Node3D).hide()
	if _built_tiles.has(key):
		remove_child(_built_tiles[key]);_built_tiles[key].queue_free()
	var tile := Node3D.new();_built_tiles[key]=tile
	tile.name = "PreviewTile_%d_%d" % [key.x, key.y]
	add_child(tile, false, Node.INTERNAL_MODE_BACK)
	var ground := MeshInstance3D.new()
	var ground_mesh := generated.terrain as ArrayMesh
	if _look.x==1 and _look.y==1 and ground_mesh.get_surface_count()>0:
		ground_mesh=preload("res://scripts/prototypes/ember_terrain_look_bake.gd").faceted(ground_mesh,generated.smooth_field).mesh
	var fields: Dictionary = _water_fields.regions.get(Vector2i(key.x/6,key.y/6),{}) if _water_fields_ready else {}
	ground.material_override = fields.get("ground", _ground_material)
	ground.mesh = ground_mesh
	tile.add_child(ground, false, Node.INTERNAL_MODE_BACK)
	var liquid := MeshInstance3D.new()
	liquid.material_override = fields.get("water", _liquid_material)
	liquid.mesh = generated.water
	tile.add_child(liquid, false, Node.INTERNAL_MODE_BACK)


func show_area(target: EmberMapLoader, candidate: TerrainResource, area_cells: Rect2i, offset_sections := Vector2i.ZERO, only_tiles: Array[Vector2i] = [], prepare_water := false, reuse_dry_tiles := false) -> bool:
	# The same exact-candidate renderer also serves bounded terrain generation.
	# It has no collision or saved nodes and never installs the candidate draft.
	if target == null or candidate == null or not area_cells.has_area(): return false
	_projection = target._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(_projection) or not _projection.is_inside_tree(): return false
	_candidate = candidate
	_preview_revision = _projection.column_revision()
	var wet := _includes_water(candidate, only_tiles) if prepare_water or reuse_dry_tiles else false
	_reuse_dry_tiles = reuse_dry_tiles and not wet and _projection.can_reuse_dry_preview(candidate, only_tiles)
	_ground_material = _projection._ground_material
	_liquid_material = _projection._water_material
	var current := _projection.document
	var private_ground := _ground_material is ShaderMaterial and current != null and (
		candidate.palette != current.palette or candidate.palette_material_ids != current.palette_material_ids
		or candidate.palette_surface_roles != current.palette_surface_roles)
	if private_ground:
		_ground_material = _ground_material.duplicate()
		Materials.set_compact_terrain_roles(_ground_material as ShaderMaterial, candidate.palette_surface_roles, candidate.palette_material_ids, candidate.palette)
	if prepare_water and wet and _liquid_material is ShaderMaterial and (_liquid_material as ShaderMaterial).shader.resource_path.ends_with("ember_compact_sky_reflection_study.gdshader"):
		# Reuse the same derived field builder for a private exact candidate.
		# Only an explicit Preview starts this work; the source remains active.
		_liquid_material = _liquid_material.duplicate()
		if not private_ground:
			_ground_material = _ground_material.duplicate()
		(_liquid_material as ShaderMaterial).set_shader_parameter("shore_field_available",1.0)
		_water_fields = WaterRegions.new(); _water_fields.request(candidate,0)
	scale = _projection.scale
	position = _projection.position
	_saved_projection_position = _projection.position
	_saved_hidden = _projection._editor_hidden_edge_keys.duplicate()
	var moved := offset_sections * TerrainResource.Sections.CELLS / TerrainProjection.TILE_SIZE
	var shift := Vector3(offset_sections.x, 0, offset_sections.y) * Extension.Creation.SECTION_BLOCKS * target.imported_tile_size
	if shift != Vector3.ZERO:
		_saved_groups.append({"node": weakref(target), "position": target.position})
		target.position -= target.basis * shift
	_projection.position += shift
	for group_name in ["Terrain", "Props", "Regions"]:
		var group := target.get_node_or_null(group_name) as Node3D
		if group != null and shift != Vector3.ZERO:
			_saved_groups.append({"node": weakref(group), "position": group.position})
			group.position += shift
	_area = area_cells
	for key in candidate.tile_keys(TerrainProjection.TILE_SIZE) if only_tiles.is_empty() else only_tiles:
		if not Rect2i(key * TerrainProjection.TILE_SIZE, Vector2i.ONE * TerrainProjection.TILE_SIZE).intersects(_area.grow(TerrainProjection.TILE_SIZE)): continue
		_pending.append(key)
		var old_key: Vector2i = key - moved
		if not _reuse_dry_tiles and _projection._tiles.has(old_key):
			_projection._editor_hidden_edge_keys[old_key] = true
			(_projection._tiles[old_key] as Node3D).hide()
	_add_border(candidate, candidate, "area", 0)
	set_process(true)
	return true


func _includes_water(candidate: TerrainResource, tiles: Array[Vector2i]) -> bool:
	if tiles.is_empty() or not candidate.is_sectioned():
		return true
	var checked := {}
	for tile in tiles:
		var key := tile * TerrainProjection.TILE_SIZE / TerrainResource.Sections.CELLS
		if checked.has(key):
			continue
		checked[key] = true
		var section: TerrainResource = candidate.sections.get(key)
		if section != null and section.water_levels.count(0) != section.water_levels.size():
			return true
	return false


func _add_border(previous: TerrainResource, candidate: TerrainResource, direction: String, cells: int) -> void:
	var x0 := _area.position.x
	var x1 := _area.end.x
	var z0 := _area.position.y
	var z1 := _area.end.y
	var height := float(candidate.origin_y + candidate.column_value("heights", candidate.column_index(x0, z0))) + 0.4
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.58, 0.18)
	material.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for pair in [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x1, z1)], [Vector2(x1, z1), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0, z0)]]:
		for point in pair:
			lines.surface_add_vertex(Vector3(point.x, height, point.y))
	lines.surface_end()
	var border := MeshInstance3D.new()
	border.name = "PreviewBoundary"
	border.mesh = lines
	add_child(border, false, Node.INTERNAL_MODE_BACK)


func clear_preview() -> void:
	set_process(false)
	_cancel_tile_jobs()
	if _water_fields != null: _water_fields.close(); _water_fields = null
	_water_fields_ready = false
	_pending.clear();_preview_keys.clear();_built_tiles.clear();_look=Vector2i(-99,-99);_announced=false
	if is_instance_valid(_projection):
		_projection.position = _saved_projection_position
		_projection._editor_hidden_edge_keys = _saved_hidden
		for key in _projection._tiles: (_projection._tiles[key] as Node3D).visible = not _saved_hidden.has(key)
	for saved in _saved_groups:
		var group: Node3D = saved.node.get_ref()
		if is_instance_valid(group):
			group.position = saved.position
	_saved_groups.clear()
	_projection = null
	_candidate = null


func _exit_tree() -> void:
	clear_preview()


func _sync_look_materials()->void:
	if _ground_material is ShaderMaterial:_projection._bind_depth_material(_ground_material)
	if _liquid_material is ShaderMaterial:_liquid_material.set_shader_parameter("sea_smooth_shore",_look.y==1 and _look.x==0)
	if _water_fields==null:return
	for fields:Dictionary in _water_fields.regions.values():
		if fields.get("ground") is ShaderMaterial:_projection._bind_depth_material(fields.ground)
		if fields.get("water") is ShaderMaterial:fields.water.set_shader_parameter("sea_smooth_shore",_look.y==1 and _look.x==0)
