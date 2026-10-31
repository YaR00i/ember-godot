extends SceneTree
## Native Forward+: reproduce the released rock carrier returning, not startup.
const Layers=preload("res://scripts/ember_solid_material_layers.gd")
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
	var holder:=Node3D.new();root.add_child(holder)
	var rows:Array[Dictionary]=[]
	for model in ["vox_painted_rock_group","vox_external_coastal_rock"]:
		var prop:EmberVoxelProp=load("res://prefabs/voxels/"+model+".tscn").instantiate();holder.add_child(prop)
		prop.apply_object_detail(true)
		var signature:=Grove.fingerprint(prop,holder)
		var visual:=prop.get_node("Mesh") as MeshInstance3D
		var expected_faces:PackedVector3Array=visual.mesh.get_faces()
		var expected_pixels:PackedByteArray=visual.mesh.get_meta("solid_layer_faces").get_image().get_data() if visual.mesh.has_meta("solid_layer_faces") else PackedByteArray()
		var physical:=prop.authoring_collision_shape()
		var last:WeakRef=weakref(prop._living_mesh) if prop._living_mesh!=null else null
		prop.apply_object_detail(false)
		if last!=null:check(last.get_ref()==null,"CPU cache does not pin released GPU carrier")
		var prepared_before:int=Layers.preparations
		for j in 3:
			await process_frame
			var started:=Time.get_ticks_usec();prop.apply_object_detail(true);var cost:=Time.get_ticks_usec()-started
			rows.append({"model":model,"return_us":cost})
			check(cost<100000,"released carrier returns without the 0.8s stall")
			if "--budget-120" in OS.get_cmdline_user_args():check(cost<8333,"warm carrier return fits the target PC's 120 FPS frame budget")
			check(visual.mesh.get_faces()==expected_faces,"returned geometry matches previous carrier")
			if not expected_pixels.is_empty():check(visual.mesh.get_meta("solid_layer_faces").get_image().get_data()==expected_pixels,"cached face pixels stay exactly equal")
			check(prop.authoring_collision_shape()==physical and Grove.fingerprint(prop,holder)==signature,"return preserves physical/authored bindings")
			check(prop.get_node("Collision/Shape").shape==physical,"visual return reuses the actual published physical boundary")
			prop.apply_object_detail(false)
		check(Layers.preparations==prepared_before,"warm returns reuse CPU face preparation")
		if model=="vox_painted_rock_group":
			var key:int=prop._hull_mesh.get_instance_id()
			check(Layers._prepared.has(key),"flat carrier has bounded CPU cache entry")
			prop._hull_mesh.emit_changed()
			check(not Layers._prepared.has(key),"mesh change invalidates CPU descriptors")
			var source:=prop._solid_source();source.notify_geometry_changed(PackedInt32Array())
			check(not EmberVoxelProp._solid_sources.has(source.resource_path),"Source change invalidates warm model read")
		prop.free()
	holder.free();await process_frame
	print("OBJECT_DETAIL_RETURN ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"rows":rows,"cpu_entries":Layers._prepared.size()}));quit(0 if errors.is_empty() else 1)
