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
	if _water_fields != null and not _water_fields_ready:
		if not _water_fields.prepare(3000,_liquid_material as ShaderMaterial,_ground_material as ShaderMaterial,Vector2(_projection.global_position.x,_projection.global_position.z)): return
		if not _water_fields.gpu_ready(): return
		_water_fields.commit(); _water_fields_ready = true
		for entry: Dictionary in _water_fields.regions.values():
			entry.water.set_shader_parameter("water_flow_map",_water_fields.flow_texture)
			entry.water.set_shader_parameter("river_phase_map",_water_fields.phase_texture)
			entry.water.set_shader_parameter("ripple_cell_field",preload("res://scripts/prototypes/ember_compact_ripple_field.gd").texture())
			entry.water.set_shader_parameter("ripple_field_available",1.0)
	var started := Time.get_ticks_usec()
	while not _pending.is_empty() and Time.get_ticks_usec() - started < 4000:
		var key: Vector2i = _pending.pop_front()
		var generated := MeshBuilder.build_tile(_candidate, key.x * TerrainProjection.TILE_SIZE, key.y * TerrainProjection.TILE_SIZE, TerrainProjection.TILE_SIZE, _projection.water_mesh_step, _projection.water_volume_sides)
		var tile := Node3D.new()
		tile.name = "PreviewTile_%d_%d" % [key.x, key.y]
		add_child(tile, false, Node.INTERNAL_MODE_BACK)
		var ground := MeshInstance3D.new()
		var ground_mesh := generated.terrain as ArrayMesh
		var fields: Dictionary = _water_fields.regions.get(Vector2i(key.x/6,key.y/6),{}) if _water_fields_ready else {}
		if ground_mesh.get_surface_count() > 0:
			ground_mesh.surface_set_material(0, fields.get("ground",_ground_material))
		ground.mesh = ground_mesh
		tile.add_child(ground, false, Node.INTERNAL_MODE_BACK)
		var liquid := MeshInstance3D.new()
		var liquid_mesh := generated.water as ArrayMesh
		if liquid_mesh.get_surface_count() > 0:
			liquid_mesh.surface_set_material(0, fields.get("water",_liquid_material))
		liquid.mesh = liquid_mesh
		tile.add_child(liquid, false, Node.INTERNAL_MODE_BACK)
	if _pending.is_empty():
		set_process(false)
		preview_built.emit()


func show_area(target: EmberMapLoader, candidate: TerrainResource, area_cells: Rect2i, offset_sections := Vector2i.ZERO, only_tiles: Array[Vector2i] = [], prepare_water := false) -> bool:
	# The same exact-candidate renderer also serves bounded terrain generation.
	# It has no collision or saved nodes and never installs the candidate draft.
	if target == null or candidate == null or not area_cells.has_area(): return false
	_projection = target._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(_projection) or not _projection.is_inside_tree(): return false
	_candidate = candidate
	_ground_material = _projection._ground_material
	_liquid_material = _projection._water_material
	if prepare_water and _liquid_material is ShaderMaterial and (_liquid_material as ShaderMaterial).shader.resource_path.ends_with("ember_compact_sky_reflection_study.gdshader"):
		# Reuse the same derived field builder for a private exact candidate.
		# Only an explicit Preview starts this work; the source remains active.
		_liquid_material = _liquid_material.duplicate()
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
		if _projection._tiles.has(old_key):
			_projection._editor_hidden_edge_keys[old_key] = true
			(_projection._tiles[old_key] as Node3D).hide()
	_add_border(candidate, candidate, "area", 0)
	set_process(true)
	return true


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
	if _water_fields != null: _water_fields.close(); _water_fields = null
	_water_fields_ready = false
	_pending.clear()
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
