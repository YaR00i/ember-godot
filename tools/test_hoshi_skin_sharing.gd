extends SceneTree
## Native skin-binding inventory. No private avatar or animation writes.
const Hoshi=preload("res://scripts/ember_hoshi_visual.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var actor:=CharacterBody3D.new();root.add_child(actor)
	var visual:=Hoshi.new();actor.add_child(visual)
	assert(visual.setup(actor,16.0));visual.set_process(false)
	for frame in 5:await process_frame
	var rows:Array=[];var groups:Dictionary={};var skins:Dictionary={};var references:Dictionary={}
	for mesh:MeshInstance3D in visual.avatar.find_children("*","MeshInstance3D",true,false):
		if mesh.skin==null:continue
		var key:Array=[]
		for bind in mesh.skin.get_bind_count():key.append([mesh.skin.get_bind_bone(bind),mesh.skin.get_bind_name(bind),mesh.skin.get_bind_pose(bind)])
		if not groups.has(key):groups[key]=[]
		groups[key].append(str(mesh.name));skins[mesh.skin.get_instance_id()]=true
		var reference:=mesh.get_skin_reference()
		if reference!=null:references[str(reference.get_skeleton())]=true
		rows.append({"mesh":str(mesh.name),"binds":mesh.skin.get_bind_count(),"skin_id":mesh.skin.get_instance_id(),"reference":str(reference.get_skeleton()) if reference!=null else "none"})
	var summary:Array=[]
	for key in groups:summary.append({"binds":key.size(),"meshes":groups[key]})
	var report:Dictionary={"skinned_meshes":rows.size(),"unique_skins":skins.size(),"unique_references":references.size(),"exact_palette_groups":summary,"rows":rows,"bones":visual.skeleton.get_bone_count()}
	var motions:Dictionary={};var paths:Dictionary={}
	for name in visual.motion.get_animation_list():
		var animation:=visual.motion.get_animation(name)
		var constant:Array=[]
		for track in animation.get_track_count():
			var path:=str(animation.track_get_path(track))
			if animation.track_get_type(track)!=Animation.TYPE_ROTATION_3D:continue
			var first:Quaternion=animation.track_get_key_value(track,0)
			var exact:=true;var max_angle:=0.0
			for key in animation.track_get_key_count(track):
				var q:Quaternion=animation.track_get_key_value(track,key)
				exact=exact and q==first;max_angle=maxf(max_angle,first.angle_to(q))
			if not paths.has(path):paths[path]=[]
			paths[path].append({"clip":name,"exact":exact,"angle":max_angle})
			if exact:constant.append(path)
		motions[name]={"tracks":animation.get_track_count(),"constant_rotations":constant}
	report.motion=motions;report.motion_paths=paths
	var output:=OS.get_environment("EMBER_CHARACTER_CAPTURE_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join("skin-inventory.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("HOSHI_SKINS ",JSON.stringify(report))
	actor.queue_free();await process_frame;await process_frame;quit()
