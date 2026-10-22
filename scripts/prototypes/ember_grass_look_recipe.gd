extends RefCounted
## Derived grass only. Source pigment, scatter, light and physics stay owned
## by the existing material/grass workflow. Flat clumps retain their own rules.
const Bake=preload("res://scripts/ember_material_look_bake.gd")
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const VOXEL_STEP_M:=0.03125

static func colours(master: Image) -> Array[Image]:
	return [master,Bake.calm_variant(master,16,0.85),TerrainLook.pixel_image(master,32)]

static func meshes(master: ArrayMesh,outline: PackedVector2Array) -> Array[ArrayMesh]:
	return [master,Bake.grass_mesh(master,1,outline,{"corners":7}),Bake.grass_mesh(master,2,outline,{"pixel_m":VOXEL_STEP_M,"coverage":true,"preserve_height":true})]
