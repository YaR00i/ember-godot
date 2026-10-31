extends Node3D
## Presentation only: native Hoshi model and baked clips. EmberPlayer owns motion.
const AVATAR_PATH="res://assets/local_characters/hoshi/avatar.scn"
const MOTION_PATH="res://assets/local_characters/hoshi/motion.res"
const Outline=preload("res://shaders/ember_hoshi_outline.gdshader")
const WorldToon=preload("res://shaders/ember_hoshi_toon.gdshader")
var avatar:Node3D
var motion:AnimationPlayer
var skeleton:Skeleton3D
var actor:CharacterBody3D
var height_m:=1.48
var unit:=16.0
var speed_mps:=0.0
var current_motion:=""
var toon:Array[ShaderMaterial]=[]
var blink_targets:Array=[]
var age:=0.0
var loaded:=false

func setup(owner_actor:CharacterBody3D,units_per_metre:float)->bool:
	if not ResourceLoader.exists(AVATAR_PATH) or not ResourceLoader.exists(MOTION_PATH):return false
	actor=owner_actor;unit=units_per_metre
	avatar=(load(AVATAR_PATH) as PackedScene).instantiate();add_child(avatar)
	height_m=avatar.get_meta("hoshi_height",1.48)
	avatar.position=-avatar.get_meta("hoshi_center",Vector3.ZERO)-Vector3.UP*float(avatar.get_meta("hoshi_floor",0.0))
	scale=Vector3.ONE*unit
	motion=avatar.get_node("Motion");skeleton=avatar.find_children("*","Skeleton3D",true,false)[0]
	motion.remove_animation_library("")
	motion.add_animation_library("",load(MOTION_PATH))
	var styling:Dictionary=avatar.get_meta("hoshi_styling",{})
	for mesh:MeshInstance3D in avatar.find_children("*","MeshInstance3D",true,false):
		# Serialized '..' is the companion project's legacy default and may be
		# omitted from the packed file. Resolve explicitly in the target engine.
		if mesh.skin!=null:mesh.skeleton=mesh.get_path_to(skeleton)
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var both:=mesh.find_blend_shape_by_name("Fcl_EYE_Close")
		for name in (["Fcl_EYE_Close"] if both>=0 else ["Fcl_EYE_Close_L","Fcl_EYE_Close_R"]):
			var index:=mesh.find_blend_shape_by_name(name)
			if index>=0:blink_targets.append([mesh,index])
		for surface in mesh.mesh.get_surface_count():
			var original=mesh.get_active_material(surface)
			var source_toon:bool=original is ShaderMaterial and original.get_meta("hoshi_toon",false)
			var facial:bool=original is BaseMaterial3D and original.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED
			if not source_toon and not facial:continue
			var mat:ShaderMaterial=original.duplicate() if source_toon else ShaderMaterial.new()
			mat.shader=WorldToon
			if facial:
				mat.set_shader_parameter("base_texture",original.albedo_texture)
				mat.set_shader_parameter("base_factor",original.albedo_color)
				mat.set_shader_parameter("alpha_cutoff",original.alpha_scissor_threshold)
				mat.set_shader_parameter("shadow_strength",0.73)
			mat.set_shader_parameter("hoshi_edge_strength",styling.get("edge_strength",0.16));mat.set_shader_parameter("hoshi_edge_width",styling.get("edge_width",0.4))
			var edge:Color=styling.get("edge_color",Color.WHITE);mat.set_shader_parameter("hoshi_edge_color",Vector3(edge.r,edge.g,edge.b))
			var outline:=ShaderMaterial.new();outline.shader=Outline
			outline.set_shader_parameter("base_texture",mat.get_shader_parameter("base_texture"))
			outline.set_shader_parameter("alpha_cutoff",mat.get_shader_parameter("alpha_cutoff"))
			var color:Color=styling.get("outline_color",Color(0.2,0.16,0.27));outline.set_shader_parameter("outline_color",Vector3(color.r,color.g,color.b))
			outline.set_shader_parameter("outline_strength",styling.get("outline_strength",0.45));outline.set_shader_parameter("outline_width",styling.get("outline_width",0.35))
			if source_toon:mat.next_pass=outline
			mesh.set_surface_override_material(surface,mat);toon.append(mat)
	loaded=true;motion.play("idle");current_motion="idle"
	return true

func _process(dt:float)->void:
	if not loaded or not is_visible_in_tree():return
	age+=dt
	var velocity:=actor.get_real_velocity()/unit
	velocity.y=0
	speed_mps=lerpf(speed_mps,velocity.length(),1.0-exp(-12.0*dt))
	if velocity.length()>0.08:rotation.y=lerp_angle(rotation.y,atan2(velocity.x,velocity.z),1.0-exp(-12.0*dt))
	var next:="idle" if speed_mps<0.08 else "walk" if speed_mps<1.8 else "run"
	if next!=current_motion:motion.play(next,0.18);current_motion=next
	motion.speed_scale=1.0 if next=="idle" else clampf(speed_mps/(1.2 if next=="walk" else 3.0),0.45,1.5)
	# Native morph targets are kept; no replacement face or exported rest edits.
	var blink:=pow(maxf(0.0,cos(age*TAU/4.6)),80.0)
	for target in blink_targets:target[0].set_blend_shape_value(target[1],blink)
