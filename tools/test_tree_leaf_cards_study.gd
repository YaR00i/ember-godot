extends SceneTree
const Restored=preload("res://scripts/prototypes/ember_smooth_tree_material_fixture.gd")
const Cards=preload("res://scripts/prototypes/ember_tree_leaf_cards_fixture.gd")
const Materials=preload("res://scripts/prototypes/ember_painted_bark_projection.gd")
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func _initialize() -> void:
	var inputs:=Restored.new().build()
	var source_before: String=inputs.source.voxels.hex_encode().sha256_text()
	var old_clouds: Array=inputs.meshes.clouds.surface_get_arrays(0).duplicate(true)
	var old_wood: Array=inputs.meshes.wood.surface_get_arrays(0).duplicate(true)
	var first:=Cards.build(inputs);var second:=Cards.build(inputs)
	check(first.cards>200 and first.cards<1500 and first.groups==14,"bounded fixed cards from existing crown groups")
	check(first.triangles==first.cards*2,"two triangles per card")
	check(first.mesh.surface_get_arrays(0)==second.mesh.surface_get_arrays(0),"same Source gives deterministic card placement, UV, colour and light normals")
	check(source_before==inputs.source.voxels.hex_encode().sha256_text(),"Source immutable")
	check(inputs.meshes.clouds.surface_get_arrays(0)==old_clouds and inputs.meshes.wood.surface_get_arrays(0)==old_wood,"previous crown/wood/paint unchanged")
	var arrays: Array=first.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var coords: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var macro: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM1]
	for i in range(0,vertices.size(),4):
		var centre: Vector3=(vertices[i]+vertices[i+1]+vertices[i+2]+vertices[i+3])*0.25
		for j in 4:
			var normal: Vector3=normals[i+j]
			check(absf(normal.dot(vertices[i+j]-centre))<0.001,"card is planar")
			check(coords[i+j].x>=0 and coords[i+j].x<=1 and coords[i+j].y>=0 and coords[i+j].y<=1,"one full artwork per card")
			var at: int=(i+j)*4
			var lighting:=Vector3(macro[at],macro[at+1],macro[at+2])
			check(lighting.is_finite() and absf(lighting.length()-1.0)<0.003,"valid group lighting direction")
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	var plain:=Materials.leaf_cards_material(inputs.meshes.clouds,profile,false)
	var painted:=Materials.leaf_cards_material(inputs.meshes.clouds,profile,true)
	for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
		check(painted.get_shader_parameter("painterly_grass_"+key)==profile.get("grass_light_"+key),"common accepted light profile "+key)
	check(plain.get_shader_parameter("painted_leaf_card_coloured")==false and painted.get_shader_parameter("painted_leaf_card_coloured")==true,"plain/painted share shape and alpha artwork")
	var texture: Texture2D=painted.get_shader_parameter("painted_leaf_card_albedo")
	var image:=texture.get_image()
	check(image.has_mipmaps(),"alpha card distance filtering")
	check(image.get_pixel(0,0).a<0.01 and image.get_pixel(image.get_width()-1,image.get_height()-1).a<0.01,"true transparent margins")
	var covered:=0;var samples:=0
	for y in range(0,image.get_height(),8):
		for x in range(0,image.get_width(),8):
			samples+=1
			if image.get_pixel(x,y).a>=0.4:covered+=1
	check(float(covered)/samples>0.12 and float(covered)/samples<0.75,"alpha silhouette has leaves and air, not solid rectangles")
	print("TREE_LEAF_CARDS_TEST ","PASS" if errors.is_empty() else errors," cards=",first.cards," alpha coverage=",float(covered)/samples)
	quit(0 if errors.is_empty() else 1)
