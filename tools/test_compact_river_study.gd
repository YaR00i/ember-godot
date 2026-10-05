extends SceneTree

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const RiverBuilder = preload("res://tools/build_compact_river_study.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const SOURCE := "res://content/world_terrains/compact_irregular_water_study.res"
const DRAFT := "user://ember-tests/compact-river-study.res"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := load(SOURCE) as TerrainResource
	assert(source != null and source.validation_errors().is_empty())
	var source_heights := source.heights.duplicate()
	var source_waters := source.water_levels.duplicate()
	var river := RiverBuilder.build(source)
	assert(river != null and river.validation_errors().is_empty())
	assert(source.heights == source_heights and source.water_levels == source_waters)
	assert(source.water_flow.is_empty())
	assert(not river.water_flow.is_empty())
	assert(river.water_flow.size() == 48 * 48)
	var min_center := river.width
	var max_center := 0
	for z in range(420, 681, 20):
		var x := roundi(RiverBuilder._center_x(float(z), river.width))
		min_center = mini(min_center, x)
		max_center = maxi(max_center, x)
		var index := river.column_index(x, z)
		assert(source.water_levels[index] <= source.heights[index])
		assert(river.water_levels[index] > river.heights[index])
		assert(river.top_materials[index] == river.palette_surface_roles.find("sand"))
		var flow := river.flow_at_cell(x, z)
		assert(flow.length() > 0.35 and flow.y < -0.3)
	assert(max_center - min_center > 35)
	var mouth_x := roundi(RiverBuilder._center_x(320.0, river.width))
	assert(river.water_levels[river.column_index(mouth_x, 320)] > river.heights[river.column_index(mouth_x, 320)])
	var invalid := river.working_copy()
	invalid.water_flow[0] = Vector2(2.0, 0.0)
	assert(not invalid.validation_errors().is_empty())
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ember-tests")) == OK)
	assert(ResourceSaver.save(river, DRAFT) == OK)
	var reopened := ResourceLoader.load(DRAFT, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	assert(reopened != null and reopened.validation_errors().is_empty())
	assert(reopened.water_flow == river.water_flow)
	assert(reopened.heights == river.heights and reopened.water_levels == river.water_levels)
	# The shader now scales wave height by the per-corner depth. Equal world
	# positions must carry equal depth even across rectangles and tile borders.
	var depths_at_vertex := {}
	for tile_z in range(6, 11):
		for tile_x in range(4, 9):
			var tile := MeshBuilder.build_tile(river, tile_x * 64, tile_z * 64, 64, 8, true)
			var mesh := tile.water as ArrayMesh
			if mesh.get_surface_count() == 0:
				continue
			var arrays := mesh.surface_get_arrays(0)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
			var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
			for vertex_index in vertices.size():
				if uvs[vertex_index].y > 1.5:
					continue
				var position := vertices[vertex_index]
				if depths_at_vertex.has(position):
					assert(is_equal_approx(float(depths_at_vertex[position]), colors[vertex_index].a))
				else:
					depths_at_vertex[position] = colors[vertex_index].a
	assert(depths_at_vertex.size() > 100)
	print("PASS compact river: curved wet channel, directed flow, shared moving vertices, save/reopen")
	quit()
