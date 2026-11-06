extends SceneTree
var INPUT:=""
var OUTPUT:="res://assets/local_characters/hoshi/motion.res"
const CLIP_SOURCES:={"idle":"Idle_Loop","walk":"Walk_Loop","run":"Jog_Fwd_Loop","talk":"Idle_Talking_Loop","sit":"Sitting_Idle_Loop","dance":"Dance_Loop",
	"fall":"Jump_Loop","land":"Jump_Land","roll":"Roll","swim":"Swim_Fwd_Loop","swim_idle":"Swim_Idle_Loop"}
var requested_clips:=PackedStringArray(["idle","walk","run"])
var target:Skeleton3D
var source:Skeleton3D
var modifier:RetargetModifier3D
var player:AnimationPlayer
var ids:Dictionary={}
var saved:Dictionary={}
var capture_pose:=false
func _initialize()->void:run.call_deferred()
func capture()->void:
	if not capture_pose:return
	for id:int in ids:saved[id]=[target.get_bone_pose_rotation(id),target.get_bone_pose_position(id)]
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("source="):INPUT=arg.trim_prefix("source=")
		if arg.begins_with("output="):OUTPUT=arg.trim_prefix("output=")
		if arg.begins_with("clips="):requested_clips=arg.trim_prefix("clips=").split(",",false)
	if INPUT.is_empty():printerr("Provide source=<Quaternius Standard GLB>");quit(2);return
	if requested_clips.is_empty():printerr("Provide at least one clip");quit(2);return
	var unique:Dictionary={}
	for clip:String in requested_clips:
		if not CLIP_SOURCES.has(clip) or unique.has(clip):printerr("Unknown or repeated clip: ",clip);quit(2);return
		unique[clip]=true
	var avatar=(load("res://assets/local_characters/hoshi/avatar.scn") as PackedScene).instantiate()
	var original:Skeleton3D=avatar.find_children("*","Skeleton3D",true,false)[0]
	var human:Dictionary=avatar.get_meta("hoshi_bones")
	var profile:=SkeletonProfileHumanoid.new()
	var dst_alias:Dictionary={0:"Root"}
	for semantic:String in human:dst_alias[int(human[semantic])]=semantic.substr(0,1).to_upper()+semantic.substr(1)
	var map:Dictionary={"root":"Root","pelvis":"Hips","spine_01":"Spine","spine_02":"Chest","spine_03":"UpperChest","neck_01":"Neck","Head":"Head"}
	for side in ["l","r"]:
		var prefix:String="Left" if side=="l" else "Right"
		for pair in [["clavicle","Shoulder"],["upperarm","UpperArm"],["lowerarm","LowerArm"],["hand","Hand"],["thigh","UpperLeg"],["calf","LowerLeg"],["foot","Foot"],["ball","Toes"]]:map[pair[0]+"_"+side]=prefix+pair[1]
		for finger in ["index","middle","ring","pinky","thumb"]:
			var label:String={"index":"Index","middle":"Middle","ring":"Ring","pinky":"Little","thumb":"Thumb"}[finger]
			var parts=["Metacarpal","Proximal","Distal"] if finger=="thumb" else ["Proximal","Intermediate","Distal"]
			for i in 3:map[finger+"_0"+str(i+1)+"_"+side]=prefix+label+parts[i]
	var doc:=GLTFDocument.new();var state:=GLTFState.new();assert(doc.append_from_file(INPUT,state)==OK)
	var root_model:Node3D=doc.generate_scene(state);source=root_model.find_children("*","Skeleton3D",true,false)[0]
	player=root_model.find_children("*","AnimationPlayer",true,false)[0]
	for i in source.get_bone_count():
		var name:=source.get_bone_name(i)
		if map.has(name):source.set_bone_name(i,map[name])
	for key in player.get_animation_list():
		var anim:=player.get_animation(key)
		for t in anim.get_track_count():
			var path:=anim.track_get_path(t)
			if path.get_subname_count()>0 and map.has(str(path.get_subname(0))):anim.track_set_path(t,NodePath(str(path).get_slice(":",0)+":"+map[str(path.get_subname(0))]))
	target=Skeleton3D.new()
	for i in original.get_bone_count():
		target.add_bone(dst_alias.get(i,original.get_bone_name(i)))
		target.set_bone_parent(i,original.get_bone_parent(i));target.set_bone_rest(i,original.get_bone_rest(i))
		if dst_alias.has(i):ids[i]=original.get_bone_name(i)
	modifier=RetargetModifier3D.new();modifier.profile=profile;modifier.use_global_pose=false;modifier.set_scale_enabled(false)
	source.add_child(modifier);modifier.add_child(target)
	source.motion_scale=absf(source.get_bone_global_rest(source.find_bone("Hips")).origin.y)
	target.motion_scale=absf(target.get_bone_global_rest(target.find_bone("Hips")).origin.y)
	root.add_child(root_model)
	modifier.modification_processed.connect(capture)
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library:=AnimationLibrary.new()
	var report:Dictionary={"source":INPUT,"source_sha256":FileAccess.get_sha256(INPUT),"source_motion_scale":source.motion_scale,"target_motion_scale":target.motion_scale,"mapped_bones":ids.size(),"clips":{}}
	for clip_name:String in requested_clips:
		var pair:Array=[clip_name,CLIP_SOURCES[clip_name]]
		assert(player.has_animation(pair[1]),"Missing source clip: "+pair[1])
		var src:=player.get_animation(pair[1]);var anim:=Animation.new();anim.length=src.length;anim.loop_mode=Animation.LOOP_NONE if clip_name in ["land", "roll"] else Animation.LOOP_LINEAR
		var tracks:Dictionary={}
		for id:int in ids:
			var t:=anim.add_track(Animation.TYPE_ROTATION_3D);anim.track_set_path(t,NodePath("Skeleton3D:"+str(ids[id])));tracks[id]=t
		var hip:int=human.hips;var position:=anim.add_track(Animation.TYPE_POSITION_3D);anim.track_set_path(position,NodePath("Skeleton3D:"+str(ids[hip])))
		player.play(pair[1]);capture_pose=true
		var changed:=0.0;var base:Dictionary={}
		for frame in 61:
			player.seek(float(frame)*src.length/60.0,true)
			await process_frame;await process_frame
			assert(saved.size()==ids.size())
			for id:int in ids:
				var q:Quaternion=saved[id][0]
				if frame==0:base[id]=q
				changed=maxf(changed,base[id].angle_to(q))
				anim.rotation_track_insert_key(tracks[id],float(frame)*src.length/60.0,base[id] if frame==60 else q)
			anim.position_track_insert_key(position,float(frame)*src.length/60.0,saved[hip][1])
		capture_pose=false
		library.add_animation(pair[0],anim);report.clips[pair[0]]={"source":pair[1],"length":src.length,"max_rotation_change":changed}
		print("QUATERNIUS_CLIP ",pair[0]," length=",src.length," change=",changed)
		assert(changed>0.01)
	assert(ResourceSaver.save(library,OUTPUT,ResourceSaver.FLAG_COMPRESS)==OK)
	var f:=FileAccess.open(OUTPUT.get_base_dir().path_join("motion-source.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("QUATERNIUS_RETARGET_PASS");avatar.free();quit()
