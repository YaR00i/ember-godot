extends "res://tools/capture_rock_solid.gd"
## One disposable voxel Resource, six existing masses, three derived looks.
## No conversion from a finished smooth/faceted mesh back into voxels.
const Model=preload("res://scripts/ember_voxel_model_resource.gd")
const Mesher=preload("res://scripts/vox_mesher.gd")
var captured_look_meshes: Array=[]

func look_material(_look: int) -> Material:
	return scene.plain_materials[0]

func source_volume(clouds: Array[PackedVector3Array]):
	var model=Model.new();model.model_id="rock_three_looks_lab"
	model.display_name="Six rock masses · common voxel source"
	model.size_blocks=Vector3i(6,3,4);model.height_voxels=48
	model.palette=PackedColorArray([Color.TRANSPARENT,Color("94958f")])
	var size: Vector3i=model.grid_size();var count:=size.x*size.y*size.z
	model.voxels.resize(count);model.voxel_part_ids.resize(count)
	for id in clouds.size():
		model.merge_parts.append("Rock %d"%id)
		# Each fixture column contributed four top/bottom corner pairs.
		for i in range(0,clouds[id].size(),8):
			var top:=clouds[id][i];var bottom:=clouds[id][i+1]
			for y in range(floori(bottom.y),roundi(top.y)):
				var index:=Mesher.cell_index(roundi(top.x),y,roundi(top.z),size.x,size.z)
				model.voxels[index]=1;model.voxel_part_ids[index]=id+1
	check(model.validation_errors().is_empty(),"common voxel Resource validates")
	return model

func mass_data(model,id: int) -> Dictionary:
	var size: Vector3i=model.grid_size();var cells:=PackedByteArray();cells.resize(model.voxels.size())
	var points:=PackedVector3Array();var count:=0
	for z in size.z:
		for x in size.x:
			var bottom:=size.y;var top:=-1
			for y in size.y:
				var index:=Mesher.cell_index(x,y,z,size.x,size.z)
				if model.voxel_part_ids[index]!=id+1:continue
				cells[index]=model.voxels[index];count+=1
				bottom=mini(bottom,y);top=maxi(top,y+1)
			if top<0:continue
			for offset: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.ONE]:
				points.append(Vector3(x+offset.x,top,z+offset.y))
				points.append(Vector3(x+offset.x,bottom,z+offset.y))
	return {"cells":cells,"points":points,"count":count}

func voxel_mesh(model,cells: PackedByteArray) -> ArrayMesh:
	var size: Vector3i=model.grid_size()
	var mesh:=Mesher.build_from_packed_voxel_region(cells,size,model.palette,PackedByteArray(),Vector3i.ZERO,size,1.0)
	# Bind the same stone slot to the existing terrain material; geometry and
	# face normals remain the native VoxMesher output.
	var result:=ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays:=mesh.surface_get_arrays(surface)
		var count: int=arrays[Mesh.ARRAY_VERTEX].size()
		var colours:=PackedColorArray();colours.resize(count);colours.fill(Color(1,0,0,1.0/255.0))
		var uv:=PackedVector2Array();uv.resize(count);uv.fill(Vector2.ONE/255.0)
		var uv2:=PackedVector2Array();uv2.resize(count);uv2.fill(Vector2(1.0/255.0,0))
		arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
		# Unused material-profile custom channels aren't needed by this shader.
		for channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:arrays[channel]=null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func ordinary_look(_model, mass: Dictionary, id: int) -> Dictionary:
	return solid(mass.points,SPECS[id][3],true,true)

func faceted_look(_model, mass: Dictionary, id: int) -> Dictionary:
	return solid(mass.points,SPECS[id][3],true,false)

func capture_looks(_source, clouds: Array[PackedVector3Array], nodes: Array[MeshInstance3D]) -> Dictionary:
	var model=source_volume(clouds)
	var fingerprint: String=model.voxels.hex_encode().sha256_text()
	var path:=output.path_join("common-rock-source.res")
	check(ResourceSaver.save(model,path)==OK,"save common voxel Source")
	var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.voxels==model.voxels and reopened.voxel_part_ids==model.voxel_part_ids,"reopen voxel source and part ownership")
	var variants: Array=[];var stats: Array=[]
	for id in nodes.size():
		var mass:=mass_data(model,id)
		var detailed:=ordinary_look(model,mass,id)
		var faceted:=faceted_look(model,mass,id)
		var voxels:=voxel_mesh(model,mass.cells)
		check(detailed.side_angles_degrees==faceted.side_angles_degrees,"same principal side slopes")
		var old_fit:=solid(clouds[id],SPECS[id][3])
		if id<2:
			for side in old_fit.side_angles_degrees.size():
				check(absf(old_fit.side_angles_degrees[side]-faceted.side_angles_degrees[side])<2.0,"accepted large-rock lean preserved within 2 degrees")
		variants.append([detailed.mesh,faceted.mesh,voxels])
		var voxel_bounds:=voxels.get_aabb();var coarse_bounds: AABB=faceted.mesh.get_aabb()
		stats.append({"rock":id,"occupied_voxels":mass.count,"detailed_faces":detailed.faces,"faceted_faces":faceted.faces,
			"triangles":[detailed.triangles,faceted.triangles,voxels.get_faces().size()/3],"side_angles_degrees":faceted.side_angles_degrees,
			"bounds_delta_m":maxf(voxel_bounds.position.distance_to(coarse_bounds.position),voxel_bounds.end.distance_to(coarse_bounds.end))/16.0})
		await process_frame
	var initial: Image
	captured_look_meshes=variants
	for look in 3:
		for id in nodes.size():
			nodes[id].mesh=variants[id][look];nodes[id].material_override=look_material(look)
		var frame:=await capture("look-%d"%look)
		if look==0:initial=frame
		check(model.voxels.hex_encode().sha256_text()==fingerprint,"look derives from unchanged voxel source")
	for id in nodes.size():
		nodes[id].mesh=variants[id][0];nodes[id].material_override=look_material(0)
	check(initial.get_data()==(await capture("look-return")).get_data(),"return to detailed look exact")
	return {"source_hash":fingerprint,"voxel_m":0.0625,"rocks":stats,"source_file":"common-rock-source.res",
		"order":["detailed","faceted","voxel"],"scope":"same occupied Source; fitted convex presentation only, no physics integration"}
