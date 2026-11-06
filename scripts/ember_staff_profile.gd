@tool
extends RefCounted
## The existing AnimationLibrary owns this opt-in profile and its clip references.
const META := &"ember_staff_profile"
const POSE := &"ember_staff_pose"
const Controls = preload("res://scripts/ember_mira_motion_controls.gd")
const Poses = preload("res://scripts/ember_mira_staff_poses.gd")
const SLOTS := [&"cast", &"strike", &"guard"]

static func create(library: AnimationLibrary) -> Dictionary:
	# Only fresh names are created. Existing gameplay clips remain intact.
	var draw_name := free_name(library, "profile_staff_draw")
	var draw := library.get_animation(Controls.DRAW).duplicate() as Animation
	# The legacy lowering arc puts the wrist beyond Mira's arm reach. This
	# profile owns a separate reachable lateral pickup, never edits that clip.
	for channel in [&"lowering",&"side_exit",&"hip_position"]:
		var old := draw.find_track(NodePath("MotionControls:"+String(channel)),Animation.TYPE_VALUE)
		if old>=0:draw.remove_track(old)
	Controls._curve(draw,&"lowering",[[0.0,0.0],[1.0,0.0]])
	Controls._curve(draw,&"side_exit",[[0.0,0.0],[0.27,0.0],[0.75,1.0],[1.0,1.0]])
	Controls._curve(draw,&"hip_position",[[0.0,Vector3(-0.22,0.65,0.03)]])
	draw.add_marker(&"grip", draw.length * 0.27)
	library.add_animation(draw_name, draw)
	var cast_name := free_name(library, "profile_staff_cast")
	var cast := Animation.new()
	cast.length = library.get_animation(&"staff_strike").length
	var impact := minf(0.38, cast.length * 0.5)
	cast.add_marker(&"impact", impact)
	cast.set_meta(POSE, true)
	var track := cast.add_track(Animation.TYPE_VALUE)
	cast.track_set_path(track, ^"MotionControls:ready_blend")
	cast.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for key in [[0.0,0.0],[impact,1.0],[cast.length,0.0]]:
		cast.track_insert_key(track,key[0],key[1])
	library.add_animation(cast_name, cast)
	return {"version":1,"draw":draw_name,"attach_marker":&"grip","pickup_grip":0.30,
		"poses":(load(Poses.PATH) as Resource).duplicate(),
		"actions":{&"cast":cast_name,&"strike":&"",&"guard":&""}}

static func free_name(library: AnimationLibrary, base: String) -> StringName:
	var name := base
	var index := 2
	while library.has_animation(name):
		name = base + "_" + str(index);index += 1
	return StringName(name)

static func read(library: AnimationLibrary) -> Dictionary:
	var value: Variant = library.get_meta(META, {})
	return value if value is Dictionary else {}

static func validate(library: AnimationLibrary, profile: Dictionary) -> String:
	if profile.get("version") != 1 or not profile.get("poses") is Poses or not profile.poses.is_valid():
		return "Нужен корректный профиль поз посоха."
	var pickup: Variant=profile.get("pickup_grip")
	if not (pickup is float or pickup is int) or not is_finite(pickup) or pickup<0.0 or pickup>0.8:
		return "Нужна точка подхвата на древке, от 0 до 0,8 м."
	if not library.has_animation(profile.get("draw", &"")):
		return "Не найден клип доставания."
	var draw := library.get_animation(profile.draw)
	var marker: StringName = profile.get("attach_marker", &"")
	if draw.loop_mode != Animation.LOOP_NONE or not draw.has_marker(marker):
		return "В клипе доставания нужен маркер grip."
	var time := draw.get_marker_time(marker)
	if time <= 0.0 or time >= draw.length:
		return "Маркер хвата должен быть внутри перехода."
	var phase := time / draw.length
	if Controls.weight(draw,&"grip_weight",phase,0.0)<0.999:
		return "На маркере кисть должна завершить хват."
	for channel in [&"lowering",&"side_exit",&"ready_blend"]:
		if Controls.weight(draw,channel,phase,1.0)>0.001:
			return "Посох должен оставаться в креплении до маркера хвата."
	var actions: Variant = profile.get("actions")
	if not actions is Dictionary:
		return "Нужны назначения действий."
	for slot in SLOTS:
		var name: StringName = actions.get(slot,&"")
		if name.is_empty():continue
		if not library.has_animation(name):return "Нет клипа действия: " + name
		var clip := library.get_animation(name)
		var track := clip.find_track(^"MotionControls:ready_blend",Animation.TYPE_VALUE)
		if not clip.get_meta(POSE,false) or clip.loop_mode != Animation.LOOP_NONE or track<0 or clip.track_get_key_count(track)<2:
			return "Нужен конечный клип позы посоха: " + name
		for key in clip.track_get_key_count(track):
			var value: Variant = clip.track_get_key_value(track,key)
			if not (value is float or value is int) or not is_finite(value) or value<0.0 or value>1.0:
				return "Вес позы должен быть от 0 до 1."
		if absf(float(clip.value_track_interpolate(track,0.0)))>.001 or absf(float(clip.value_track_interpolate(track,clip.length)))>.001:
			return "Клип должен начинаться и завершаться в удержании."
		if slot != &"guard" and (not clip.has_marker(&"impact") or clip.get_marker_time(&"impact")<=0.0 or clip.get_marker_time(&"impact")>=clip.length):
			return "Для каста/удара нужен внутренний маркер impact."
	return ""

static func pose_weight(clip: Animation, seconds: float) -> float:
	# Ease the artist's envelope without moving its event marker.
	return smoothstep(0.0,1.0,Controls.weight(clip,&"ready_blend",seconds/clip.length,0.0))

static func interpolate_at_contact(a:Transform3D,b:Transform3D,contact:Vector3,weight:float)->Transform3D:
	# Interpolating a long prop's base makes its grip bulge beyond arm reach.
	# Interpolate the contact trajectory and rotate the prop around that point.
	var result:=a.interpolate_with(b,weight)
	result.origin=(a*contact).lerp(b*contact,weight)-result.basis*contact
	return result
