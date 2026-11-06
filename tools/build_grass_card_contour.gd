extends SceneTree
## Derived geometry only. Bake in the disposable QA project, then copy the .res.
const Fixture = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const ATLAS := "res://content/terrain_materials/textures/grass-cards-runtime.png"
const OUTPUT := "res://prefabs/voxels/meshes/grass_card_contour.res"

func _init() -> void:
	var mesh := Fixture.grass_card_contour_mesh(Image.load_from_file(ATLAS))
	# Native LOD switches index buffers, not plants or artwork. Keep the cheap
	# original cards at distance; their alpha silhouette is the same grass.
	var arrays:=mesh.surface_get_arrays(0)
	var original:=Fixture.grass_card_mesh().surface_get_arrays(0)
	var offset:int=arrays[Mesh.ARRAY_VERTEX].size()
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		if original[channel]!=null and not original[channel].is_empty():
			assert(arrays[channel]!=null)
			arrays[channel].append_array(original[channel])
	var far_indices:PackedInt32Array=original[Mesh.ARRAY_INDEX].duplicate()
	for index in far_indices.size():far_indices[index]+=offset
	var render_mesh:=ArrayMesh.new()
	# MultiMesh plants carry their scale in instance transforms. Calibrated in
	# native 1440p near/wide views; the index choice remains engine-owned.
	render_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{0.05:far_indices})
	for name in mesh.get_meta_list():render_mesh.set_meta(name,mesh.get_meta(name))
	mesh=render_mesh
	mesh.set_meta("source_atlas_sha256",FileAccess.get_sha256(ATLAS))
	mesh.set_meta("recipe","supporting-trapezoid-padding8-native-card-lod-v2")
	assert(ResourceSaver.save(mesh,OUTPUT,ResourceSaver.FLAG_COMPRESS)==OK)
	print("GRASS_CARD_BAKED triangles=",mesh.surface_get_array_index_len(0)/3," area=",mesh.get_meta("card_area_fraction"))
	quit()
