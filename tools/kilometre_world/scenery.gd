extends Node3D
## Batch repeated visuals per spatial cell; each placement retains the prefab's
## measured mesh offset and physical shape in the metre-based QA world.
const PREFABS := {
	"tree":"vox_painted_oak", "birch":"vox_painted_birch", "rock":"vox_painted_rock_group",
	"house":"vox_coastal_house", "lamp":"vox_fan_lantern_paper", "crate":"vox_crate_1"
}
const CELL := 48.0
var collision_tiles := {}
var live_bodies := {}
var last_cell := Vector2i(-9999,-9999)
var groups := 0
var lamp_sites := PackedVector3Array()
var lamps: Array[OmniLight3D] = []

static func bake_tree_lods(directory: String) -> Error:
	var lod = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
	for kind in ["tree","birch"]:
		var node = load("res://prefabs/voxels/%s.tscn" % PREFABS[kind]).instantiate()
		var source: ArrayMesh = node.get_node("Mesh").mesh
		var job = lod.object_job(source)
		job.run()
		var importer: ImporterMesh = job.importer
		var compact := ArrayMesh.new()
		var before := 0
		var after := 0
		for surface in importer.get_surface_count():
			var arrays := importer.get_surface_arrays(surface)
			before += arrays[Mesh.ARRAY_INDEX].size()/3
			var levels := importer.get_surface_lod_count(surface)
			if levels > 0:arrays[Mesh.ARRAY_INDEX] = importer.get_surface_lod_indices(surface,0)
			after += arrays[Mesh.ARRAY_INDEX].size()/3
			# Compact the vertices referenced by the new near mesh; regenerate
			# the distant index levels against that same vertex layout.
			var builder := SurfaceTool.new()
			builder.create_from_arrays(arrays)
			builder.deindex()
			builder.index()
			compact.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,builder.commit_to_arrays(),[],{},source.surface_get_format(surface))
			if compact.get_surface_count() != surface+1:
				node.free()
				return ERR_INVALID_DATA
			compact.surface_set_name(surface,source.surface_get_name(surface))
		compact.custom_aabb = source.get_aabb()
		var result: Dictionary = lod.object_mesh(compact)
		result.mesh.set_meta("source_triangles",before)
		result.mesh.set_meta("near_triangles",after)
		var error := ResourceSaver.save(result.mesh,directory+"/"+kind+".res",ResourceSaver.FLAG_COMPRESS)
		node.free()
		if error != OK:return error
		print("KILOMETRE_TREE_LODS ",kind," ",result.levels," original ",before," near ",after)
	return OK

func setup(props: Array, terrain, directory: String) -> void:
	var templates := {}
	var batches := {}
	for kind: String in PREFABS:
		var native = load("res://prefabs/voxels/%s.tscn" % PREFABS[kind]).instantiate()
		var visual := native.get_node("Mesh") as MeshInstance3D
		var mesh: Mesh
		if kind in ["tree","birch"] and ResourceLoader.exists(directory+"/"+kind+".res"):
			mesh = load(directory+"/"+kind+".res")
		else:
			mesh = visual.mesh.duplicate()
		for i in mesh.get_surface_count():
			mesh.surface_set_material(i,visual.get_active_material(i))
		var unit := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE/16.0),Vector3.ZERO)
		var local := unit * visual.transform
		var bounds := local * mesh.get_aabb()
		var shift := Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)
		var shape := native.get_node_or_null("Collision/Shape") as CollisionShape3D
		var material := visual.material_override
		if kind == "rock":
			var stone := preload("res://content/terrain_materials/cartoon_stone.tres")
			var rock_material := StandardMaterial3D.new()
			rock_material.albedo_texture = stone.albedo_texture
			rock_material.uv1_triplanar = true
			rock_material.uv1_scale = Vector3.ONE/stone.pattern_size_m
			rock_material.roughness = 0.92
			material = rock_material
		templates[kind] = {"mesh":mesh,"material":material,
			"local":Transform3D(Basis.IDENTITY,shift)*local,
			"shape":shape.shape if shape != null else null,
			"shape_xf":Transform3D(Basis.IDENTITY,shift)*unit*shape.transform if shape != null else Transform3D.IDENTITY,
			"height":bounds.size.y}
		native.free()
	for row: Dictionary in props:
		var pos := Vector3(row.x,0,row.z)
		pos.y = terrain.data.get_surface_height(pos)
		if not is_finite(pos.y):push_error("Invalid terrain support for "+str(row));continue
		var cell := Vector2i(floori(pos.x/CELL),floori(pos.z/CELL))
		var kind: String = row.type
		var xf := Transform3D(Basis(Vector3.UP,row.yaw).scaled(Vector3.ONE*float(row.scale)),pos)
		if not batches.has(cell):batches[cell] = {}
		if not batches[cell].has(kind):batches[cell][kind] = []
		batches[cell][kind].append(xf*templates[kind].local)
		if templates[kind].shape != null:
			if not collision_tiles.has(cell):collision_tiles[cell]=[]
			collision_tiles[cell].append([templates[kind].shape,xf*templates[kind].shape_xf])
		if kind=="lamp":lamp_sites.append(pos+Vector3.UP*float(templates[kind].height)*float(row.scale)*0.88)
	for cell: Vector2i in batches:
		for kind: String in batches[cell]:
			var transforms: Array = batches[cell][kind]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = templates[kind].mesh
			mm.instance_count = transforms.size()
			var origin := Vector3(cell.x*CELL,0,cell.y*CELL)
			for i in transforms.size():
				var transform: Transform3D = transforms[i]
				transform.origin -= origin
				mm.set_instance_transform(i,transform)
			var visual := MultiMeshInstance3D.new()
			visual.multimesh = mm
			visual.position = origin
			visual.material_override = templates[kind].material
			add_child(visual)
			groups += 1
	for i in mini(6,lamp_sites.size()):
		var light := OmniLight3D.new()
		light.light_color = Color("#ffc37a")
		light.light_energy = 2.0
		light.omni_range = 8.0
		light.shadow_enabled = false
		add_child(light)
		lamps.append(light)

func follow(pos: Vector3) -> void:
	var cell := Vector2i(floori(pos.x/CELL),floori(pos.z/CELL))
	if cell == last_cell:return
	last_cell = cell
	for key: Vector2i in live_bodies.keys():
		if absi(cell.x-key.x)>2 or absi(cell.y-key.y)>2:
			var body: StaticBody3D = live_bodies[key]
			remove_child(body)
			body.queue_free()
			live_bodies.erase(key)
	for z in range(cell.y-1,cell.y+2):
		for x in range(cell.x-1,cell.x+2):
			var key := Vector2i(x,z)
			if not collision_tiles.has(key) or live_bodies.has(key):continue
			var body := StaticBody3D.new()
			body.collision_layer = 4
			for entry: Array in collision_tiles[key]:
				var shape := CollisionShape3D.new()
				shape.shape = entry[0]
				shape.transform = entry[1]
				body.add_child(shape)
			add_child(body)
			live_bodies[key]=body
	var near := Array(lamp_sites)
	near.sort_custom(func(a:Vector3,b:Vector3):return a.distance_squared_to(pos)<b.distance_squared_to(pos))
	for i in lamps.size():
		lamps[i].position=near[i]
		lamps[i].visible=pos.distance_to(near[i])<100.0
