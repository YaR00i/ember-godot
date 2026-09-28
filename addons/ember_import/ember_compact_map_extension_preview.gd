@tool
extends Node3D
## Editor-only projection of the exact candidate strip, using the terrain tile mesher.

signal preview_built

const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")

var _candidate: TerrainResource
var _projection: EmberTerrainPilotProjection
var _saved_projection_position := Vector3.ZERO
var _saved_groups: Array[Dictionary] = []
var _pending: Array[Vector2i] = []
var _ground_material: Material
var _liquid_material: Material


func show_candidate(target: EmberMapLoader, previous: TerrainResource, candidate: TerrainResource, direction: String) -> bool:
	if target == null or previous == null or candidate == null or direction not in Extension.DIRECTIONS:
		return false
	_projection = target._visual_surface_projection as EmberTerrainPilotProjection
	if not is_instance_valid(_projection) or not _projection.is_inside_tree():
		return false
	_candidate = candidate
	_ground_material = Materials.opaque_material()
	_liquid_material = Materials.water_material().duplicate() as Material
	(_liquid_material as ShaderMaterial).set_shader_parameter("coordinate_scale", float(TerrainResource.CELLS_PER_BLOCK))
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
	_projection.set_editor_extension_edge_hidden(direction, true)
	var old_x_tiles := ceili(float(previous.width) / TerrainProjection.TILE_SIZE)
	var old_z_tiles := ceili(float(previous.depth) / TerrainProjection.TILE_SIZE)
	var new_x_tiles := ceili(float(candidate.width) / TerrainProjection.TILE_SIZE)
	var new_z_tiles := ceili(float(candidate.depth) / TerrainProjection.TILE_SIZE)
	for z in new_z_tiles:
		for x in new_x_tiles:
			var on_strip := (direction == "west" and x <= new_x_tiles - old_x_tiles) or (direction == "east" and x >= old_x_tiles - 1) or (direction == "north" and z <= new_z_tiles - old_z_tiles) or (direction == "south" and z >= old_z_tiles - 1)
			if on_strip:
				_pending.append(Vector2i(x, z))
	_add_border(previous, candidate, direction, cells)
	set_process(true)
	return true


func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	while not _pending.is_empty() and Time.get_ticks_usec() - started < 4000:
		var key: Vector2i = _pending.pop_front()
		var generated := MeshBuilder.build_tile(_candidate, key.x * TerrainProjection.TILE_SIZE, key.y * TerrainProjection.TILE_SIZE, TerrainProjection.TILE_SIZE)
		var tile := Node3D.new()
		tile.name = "PreviewTile_%d_%d" % [key.x, key.y]
		add_child(tile, false, Node.INTERNAL_MODE_BACK)
		var ground := MeshInstance3D.new()
		var ground_mesh := generated.terrain as ArrayMesh
		if ground_mesh.get_surface_count() > 0:
			ground_mesh.surface_set_material(0, _ground_material)
		ground.mesh = ground_mesh
		tile.add_child(ground, false, Node.INTERNAL_MODE_BACK)
		var liquid := MeshInstance3D.new()
		var liquid_mesh := generated.water as ArrayMesh
		if liquid_mesh.get_surface_count() > 0:
			liquid_mesh.surface_set_material(0, _liquid_material)
		liquid.mesh = liquid_mesh
		tile.add_child(liquid, false, Node.INTERNAL_MODE_BACK)
	if _pending.is_empty():
		set_process(false)
		preview_built.emit()


func _add_border(previous: TerrainResource, candidate: TerrainResource, direction: String, cells: int) -> void:
	var x0 := 0 if direction == "west" else previous.width if direction == "east" else 0
	var x1 := cells if direction == "west" else candidate.width if direction == "east" else candidate.width
	var z0 := 0 if direction == "north" else previous.depth if direction == "south" else 0
	var z1 := cells if direction == "north" else candidate.depth if direction == "south" else candidate.depth
	var height := float(candidate.origin_y + candidate.heights[candidate.column_index(clampi(x0, 0, candidate.width - 1), clampi(z0, 0, candidate.depth - 1))]) + 0.4
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
	_pending.clear()
	if is_instance_valid(_projection):
		_projection.position = _saved_projection_position
		_projection.set_editor_extension_edge_hidden("", false)
	for saved in _saved_groups:
		var group: Node3D = saved.node.get_ref()
		if is_instance_valid(group):
			group.position = saved.position
	_saved_groups.clear()
	_projection = null
	_candidate = null


func _exit_tree() -> void:
	clear_preview()
