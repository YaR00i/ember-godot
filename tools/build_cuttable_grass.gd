extends SceneTree
## Baked gameplay tuft from the accepted grass cards/material. No terrain edits.
const Fixture = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const MATERIAL := "res://prefabs/items/materials/cuttable_grass.res"
const FLAG := "cuttable_grass_revealed"
func _init() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("Grass material baking requires Forward+ to serialize texture-array layers"); quit(2); return
	var artwork := preload("res://scripts/ember_tree_bark_surface.gd")
	var coverage := artwork.artwork("res://content/terrain_materials/textures/grass-edge-coverage.png")
	# Existing material binder loads this PNG; seed its cache without editor import.
	coverage.take_over_path("res://content/terrain_materials/textures/grass-edge-coverage.png")
	var material := Materials.compact_flower_material()
	# Match the main meadow's authored pigment/profile instead of a second tint.
	var terrain := load("res://content/world_terrains/landscape_compact.res") as EmberTerrainPilotResource
	assert(terrain != null)
	var slot := terrain.palette_surface_roles.find("grass")
	assert(slot >= 0)
	# This asset only needs grass. Do not embed the entire map's soil/stone banks.
	var material_id := terrain.palette_material_ids[slot] if slot < terrain.palette_material_ids.size() else ""
	Materials.set_compact_terrain_roles(material,PackedStringArray(["","grass"]),PackedStringArray(["",material_id]),PackedColorArray([Color.TRANSPARENT,terrain.palette[slot]]))
	material.set_shader_parameter("flower_atlas",artwork.artwork("res://content/terrain_materials/textures/grass-cards-runtime.png",true))
	material.set_shader_parameter("material_grass_coverage",ImageTexture.create_from_image(coverage.get_image()))
	material.set_shader_parameter("flower_palette_slot",1.0)
	material.set_shader_parameter("flower_tint",Color.WHITE)
	material.set_shader_parameter("smooth_surface_enabled",true)
	material.set_shader_parameter("ember_texture_world_unit",16.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATERIAL.get_base_dir()))
	assert(ResourceSaver.save(material,MATERIAL,ResourceSaver.FLAG_COMPRESS)==OK)
	material=load(MATERIAL)
	var full := load("res://prefabs/voxels/meshes/grass_card_contour.res") as ArrayMesh
	var lower := clip(full,false)
	var standing := SurfaceTool.new(); standing.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stubble := SurfaceTool.new(); stubble.begin(Mesh.PRIMITIVE_TRIANGLES)
	var effect := preload("res://scripts/ember_grass_cut_effect.gd").new()
	effect.name="CutGrassScatter"; effect.lifetime=0.65; effect.gravity=6
	var blade_material := material.duplicate() as ShaderMaterial
	var pigment := Image.create(1,1,false,Image.FORMAT_RGBA8); pigment.fill(Color("6d8345"))
	blade_material.set_shader_parameter("flower_atlas",ImageTexture.create_from_image(pigment))
	for variant in 4:
		var batch := MultiMeshInstance3D.new(); batch.name="Blades%d"%variant
		batch.multimesh=MultiMesh.new(); batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh=single_blade(variant); batch.multimesh.instance_count=16
		batch.material_override=blade_material; effect.add_child(batch); batch.owner=effect
	var rng := RandomNumberGenerator.new(); rng.seed=30102026
	for index in 64:
		var angle := rng.randf()*TAU; var radius := sqrt(rng.randf())
		var point := Vector3(cos(angle)*radius*12.0,rng.randf_range(4.5,16.0),sin(angle)*radius*9.0)
		var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(1.3,2.4))
		var pose := Transform3D(basis,point/16.0)
		effect.leaf_transforms.append(pose)
		effect.get_child(index%4).multimesh.set_instance_transform(index/4,pose)
	var positions := [Vector3(-6,0,0),Vector3(6,0,1),Vector3(0,0,-5)]
	for index in 3:
		var pose := Transform3D(Basis(Vector3.UP,index*1.7).scaled(Vector3(60,120,60)),positions[index])
		standing.append_from(full,0,pose); stubble.append_from(lower,0,pose)
	save_scene(effect,"res://prefabs/items/cut_grass_scatter.scn")
	var grass := preload("res://scripts/ember_cuttable_grass.gd").new()
	grass.name="CuttableGrass"; grass.revealed_flag_id=FLAG
	grass.scatter_effect=load("res://prefabs/items/cut_grass_scatter.scn")
	grass.collision_layer=4; grass.collision_mask=0; grass.monitoring=false
	add_mesh(grass,"PileVisual",standing.commit(),material)
	var base := add_mesh(grass,"CutStubble",stubble.commit(),material); base.visible=false
	var shape := CollisionShape3D.new(); shape.name="BodyShape"; shape.shape=BoxShape3D.new(); shape.shape.size=Vector3(32,21,26); shape.position.y=10.5
	grass.add_child(shape); shape.owner=grass
	var item := preload("res://scripts/ember_world_item_3d.gd").new()
	item.name="HiddenPickup"; item.pickup_id="cut_grass_herb"; item.item_id="herb"; item.available_flag_id=FLAG; item.position=Vector3(0,3,0)
	grass.add_child(item); item.owner=grass
	save_scene(grass,"res://prefabs/items/cuttable_grass.scn")
	var herb := Node3D.new(); herb.name="HerbSprig"
	var mesh := add_mesh(herb,"Sprig",full,material)
	mesh.transform=Transform3D(Basis(Vector3.FORWARD,0.35).scaled(Vector3(1.8,3.2,1.8)),Vector3.ZERO)
	var tie := MeshInstance3D.new(); tie.name="BundleTie"; tie.mesh=CylinderMesh.new()
	tie.mesh.top_radius=0.07; tie.mesh.bottom_radius=0.07; tie.mesh.height=0.022; tie.mesh.radial_segments=8
	tie.position=Vector3(0,0.032,0); var twine:=StandardMaterial3D.new(); twine.albedo_color=Color("bc9d6c"); twine.roughness=0.95; tie.material_override=twine
	mesh.add_child(tie); tie.owner=herb
	save_scene(herb,"res://prefabs/items/herb_sprig.scn")
	print("PASS baked cuttable grass: accepted cards/stubble, 64 individual blade wisps in four batches, existing herb pickup")
	quit()

func add_mesh(parent: Node3D,label: String,mesh: ArrayMesh,material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new(); visual.name=label; visual.mesh=mesh; visual.material_override=material
	parent.add_child(visual); visual.owner=parent
	return visual

func save_scene(node: Node3D,path: String) -> void:
	var packed := PackedScene.new(); assert(packed.pack(node)==OK)
	assert(ResourceSaver.save(packed,path)==OK); node.free()

func single_blade(variant: int) -> ArrayMesh:
	# The accepted geometric tuft has eight separate blades in authored order.
	var arrays := Fixture.grass_blade_mesh().surface_get_arrays(0)
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	assert(indices.size()%8==0)
	var count := indices.size()/8
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Root -> upper bend -> tip: one quad and one triangle. The short cosmetic
	# flight needs no middle bend or duplicate back faces (cull_disabled material).
	assert(count==30)
	for local in [0,13,2,0,24,13,24,25,26]:
		var i := indices[variant*count+local]
		surface.set_normal(arrays[Mesh.ARRAY_NORMAL][i]); surface.set_color(arrays[Mesh.ARRAY_COLOR][i])
		surface.set_uv(arrays[Mesh.ARRAY_TEX_UV][i]); surface.set_uv2(arrays[Mesh.ARRAY_TEX_UV2][i])
		surface.add_vertex(arrays[Mesh.ARRAY_VERTEX][i])
	surface.index()
	return surface.commit()

func clip(mesh: ArrayMesh,above: bool) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for start in range(0,indices.size(),3):
		var polygon: Array[Dictionary]=[]
		for j in 3:
			var i := indices[start+j]
			polygon.append({"p":arrays[Mesh.ARRAY_VERTEX][i],"uv":arrays[Mesh.ARRAY_TEX_UV][i],"n":arrays[Mesh.ARRAY_NORMAL][i],"c":arrays[Mesh.ARRAY_COLOR][i],"uv2":arrays[Mesh.ARRAY_TEX_UV2][i]})
		var output: Array[Dictionary]=[]
		for j in polygon.size():
			var a: Dictionary=polygon[j]; var b: Dictionary=polygon[(j+1)%polygon.size()]
			var a_in: bool=a.p.y>=0.035 if above else a.p.y<=0.035
			var b_in: bool=b.p.y>=0.035 if above else b.p.y<=0.035
			if a_in:output.append(a)
			if a_in!=b_in:
				var amount: float=(0.035-a.p.y)/(b.p.y-a.p.y)
				var edge: Dictionary={}
				for key in a:edge[key]=a[key].lerp(b[key],amount)
				output.append(edge)
		for j in range(1,output.size()-1):
			for vertex: Dictionary in [output[0],output[j],output[j+1]]:
				surface.set_normal(vertex.n.normalized()); surface.set_color(vertex.c)
				surface.set_uv(vertex.uv); surface.set_uv2(vertex.uv2); surface.add_vertex(vertex.p)
	return surface.commit()
