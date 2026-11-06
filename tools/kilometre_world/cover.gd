extends Node3D
## A fixed window of instanced tiles. Tile coordinates and the baked density map
## determine the same roots on return. Rotation never rebuilds the buffers.
const Blades = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const Flowers = preload("res://scripts/ember_flowered_grass.gd")
const CoverShader = preload("cover.gdshader")
const TILE := 16
const RADIUS := 3
var tiles: Array[Node3D] = []
var materials: Array[ShaderMaterial] = []
var anchor := Vector2i(-99999,-99999)
var prepared_counts: Array[int] = []
var carriers: Array[MultiMesh] = []
var bounds: Array = []

func setup(spec: Dictionary, height: Texture2D, mask: Texture2D, color: Texture2D) -> void:
	var pattern := load(Flowers.PATTERN_PATH) as EmberCompactTerrainPattern
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	bounds = spec.get("tile_height_bounds", [])
	for kind in 2:
		var material := ShaderMaterial.new()
		material.shader = CoverShader
		if kind == 1:
			var flower_shader := Shader.new()
			flower_shader.code = CoverShader.code.replace("shader_type spatial;", "shader_type spatial;\n#define FLOWERS")
			material.shader = flower_shader
		material.set_shader_parameter("height_field", height)
		material.set_shader_parameter("density_field", mask)
		material.set_shader_parameter("ground_color", color)
		var grass_pattern := preload("res://content/terrain_materials/cartoon_grass.tres")
		material.set_shader_parameter("painted_grass",grass_pattern.albedo_texture)
		material.set_shader_parameter("paint_period",grass_pattern.pattern_size_m)
		if kind == 1:material.set_shader_parameter("flower_atlas", pattern.albedo_texture)
		material.set_shader_parameter("reach", 28.0 if kind == 1 else 40.0)
		materials.append(material)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Blades.grass_blade_mesh() if kind == 0 else Flowers.mesh(pattern)
		var density := float(spec.grass_max_per_m2 if kind == 0 else spec.flowers_max_per_m2)
		var base_count:=ceili(TILE*TILE*density)
		mm.instance_count = base_count*(2 if kind==0 else 1)
		mm.visible_instance_count=base_count
		prepared_counts.append(base_count)
		var extra:=RandomNumberGenerator.new()
		extra.seed=int(spec.seed)^19531
		for i in mm.instance_count:
			var random:=rng if i<base_count else extra
			var pos := Vector3(random.randf()*TILE,0,random.randf()*TILE)
			mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,random.randf()*TAU),pos))
		mm.custom_aabb = AABB(Vector3(-1,spec.height_min_m-1,-1),Vector3(TILE+2,spec.height_max_m-spec.height_min_m+4,TILE+2))
		carriers.append(mm)
	for z in range(-RADIUS,RADIUS+1):
		for x in range(-RADIUS,RADIUS+1):
			var tile := Node3D.new()
			add_child(tile)
			tiles.append(tile)
			for kind in 2:
				var visual := MultiMeshInstance3D.new()
				visual.multimesh = carriers[kind]
				visual.material_override = materials[kind]
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				tile.add_child(visual)

func follow(point: Vector3) -> void:
	var cell := Vector2i(floori(point.x/TILE),floori(point.z/TILE))
	if cell == anchor:return
	anchor = cell
	var index := 0
	for z in range(cell.y-RADIUS,cell.y+RADIUS+1):
		for x in range(cell.x-RADIUS,cell.x+RADIUS+1):
			tiles[index].position = Vector3(x*TILE,0,z*TILE)
			tiles[index].visible = x >= 0 and z >= 0 and x*TILE < 1000 and z*TILE < 1000
			if tiles[index].visible and not bounds.is_empty():
				var span: Array = bounds[z][x]
				for visual: MultiMeshInstance3D in tiles[index].get_children():
					visual.custom_aabb = AABB(Vector3(-1,span[0]-1,-1),Vector3(TILE+2,span[1]-span[0]+3,TILE+2))
			index += 1

func set_density(kind: int, value: float) -> void:
	# Shorten the shared draw; density changes preserve all retained roots.
	carriers[kind].visible_instance_count = ceili(prepared_counts[kind]*clampf(value,0.0,2.0 if kind==0 else 1.0))
