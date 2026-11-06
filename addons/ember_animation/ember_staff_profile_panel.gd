extends VBoxContainer
## Isolated review host uses the same runtime Visual, library and UndoRedo owner.
const Profile=preload("res://scripts/ember_staff_profile.gd")
const Visual=preload("res://scripts/ember_hoshi_visual.gd")
var library: AnimationLibrary
var history: UndoRedo
var visual: Visual
var actor: CharacterBody3D
var camera: Camera3D
var walking := false
var yaw := 0.0
var _world: Node3D
var _status: Label
var _feedback: Label
var _events: Label
var _values: Dictionary = {}
var _slots: Dictionary = {}
var _buttons: Dictionary = {}
var event_log: Array = []
var _pickup: SpinBox
var _contact: ContactReadout
class ContactReadout extends SkeletonModifier3D:
	var visual:Visual
	var error_mm:=0.0
	func _process_modification()->void:
		var sk:=get_skeleton()
		var hand:=sk.to_global(sk.get_bone_global_pose(sk.find_bone("J_Bip_R_Hand")).origin)
		error_mm=hand.distance_to(visual._back_weapon.get_node("RightGrip/Wrist").global_position)*1000.0

func setup(source: AnimationLibrary, undo: UndoRedo) -> void:
	library=source;history=undo
	name="Посох · профиль"
	var header:=Label.new();header.text="Посох Миры · явный хват и отпускание · стойка/ходьба";add_child(header)
	var columns:=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;add_child(columns)
	var viewport_box:=SubViewportContainer.new();viewport_box.stretch=true;viewport_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(viewport_box)
	var viewport:=SubViewport.new();viewport.size=Vector2i(1000,700);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport_box.add_child(viewport)
	_world=Node3D.new();viewport.add_child(_world)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("333c49");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;_world.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-25,0);light.light_energy=1.8;_world.add_child(light)
	var ground:=StaticBody3D.new();_world.add_child(ground)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(1000,.2,1000);collision.shape=shape;collision.position.y=-.1;ground.add_child(collision)
	var mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(1000,1000);mesh.mesh=plane;var mat:=StandardMaterial3D.new();mat.albedo_color=Color("505967");mesh.material_override=mat;ground.add_child(mesh)
	camera=Camera3D.new();camera.current=true;camera.fov=34;_world.add_child(camera)
	var form:=VBoxContainer.new();form.custom_minimum_size.x=410;columns.add_child(form)
	var notes:=Label.new();notes.text="Редактируется отдельная библиотека пробы.\nКаст — текущая поза посоха с маркером impact.\nУдар/защита пусты до назначения; новых движений нет.";form.add_child(notes)
	for key in ["ready_hand","ready_direction","cast_hand","cast_direction"]:
		var row:=HBoxContainer.new();form.add_child(row)
		var label:=Label.new();label.text={"ready_hand":"Рука · удержание","ready_direction":"Направление · удержание","cast_hand":"Рука · каст","cast_direction":"Направление · каст"}[key];label.custom_minimum_size.x=180;row.add_child(label)
		_values[key]=[]
		for i in 3:
			var spin:=SpinBox.new();spin.min_value=-2;spin.max_value=2;spin.step=.01;spin.custom_minimum_size.x=70;row.add_child(spin);_values[key].append(spin)
	for slot in Profile.SLOTS:
		var row:=HBoxContainer.new();form.add_child(row);var label:=Label.new();label.text={&"cast":"Каст",&"strike":"Удар",&"guard":"Защита"}[slot];label.custom_minimum_size.x=80;row.add_child(label)
		var choice:=OptionButton.new();choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choice.add_item("Не назначено");choice.set_item_metadata(0,&"")
		for clip in library.get_animation_list():
			if library.get_animation(clip).get_meta(Profile.POSE,false):choice.add_item(clip);choice.set_item_metadata(choice.item_count-1,clip)
		row.add_child(choice);_slots[slot]=choice
	var pickup_row:=HBoxContainer.new();form.add_child(pickup_row);var pickup_label:=Label.new();pickup_label.text="Подхват вдоль древка, м";pickup_row.add_child(pickup_label)
	_pickup=SpinBox.new();_pickup.min_value=0;_pickup.max_value=.8;_pickup.step=.01;pickup_row.add_child(_pickup)
	button(form,"Применить позы и назначения",commit_profile)
	var warning:=Label.new();warning.text="Применение перезапускает пробу.\nUndo/Redo и сохранение — в верхней строке.\nНазначение одного клипа нескольким слотам\nне создаёт новую анимацию удара/защиты.";form.add_child(warning)
	var row:=HBoxContainer.new();add_child(row)
	var walk:=CheckButton.new();walk.text="На ходу";walk.toggled.connect(func(value):walking=value);row.add_child(walk)
	button(row,"Спереди",func():yaw=0.0);button(row,"Сбоку",func():yaw=-PI/2);button(row,"Сзади",func():yaw=PI)
	for spec in [["draw","Достать",func():show_error(visual.set_staff_equipped(true))],["stow","Убрать / развернуть",func():show_error(visual.set_staff_equipped(false))],["cast","Каст",func():show_error(visual.play_staff_profile_action(&"cast"))],["strike","Удар",func():show_error(visual.play_staff_profile_action(&"strike"))],["guard","Защита",func():show_error(visual.play_staff_profile_action(&"guard"))],["cancel","Отмена действия",func():visual.cancel_staff_profile_action()],["wave","Помахать",func():show_error(visual.play_animation_action(&"wave_left"))]]:
		_buttons[spec[0]]=button(row,spec[1],spec[2])
	_status=Label.new();add_child(_status);_events=Label.new();add_child(_events);_feedback=Label.new();add_child(_feedback)
	reload_profile()

func button(parent:Node,title:String,callback:Callable)->Button:
	var result:=Button.new();result.text=title;result.pressed.connect(callback);parent.add_child(result);return result

func show_error(message:String)->void:_feedback.text=message

func commit_profile()->void:
	var previous:=Profile.read(library)
	var next:=previous.duplicate(true)
	next.poses=previous.poses.duplicate()
	next.pickup_grip=_pickup.value
	for key in _values:next.poses.set(key,Vector3(_values[key][0].value,_values[key][1].value,_values[key][2].value))
	for slot in _slots:next.actions[slot]=_slots[slot].get_selected_metadata()
	var error:=Profile.validate(library,next)
	if not error.is_empty():show_error(error);return
	history.create_action("Профиль посоха")
	history.add_do_method(apply_profile.bind(next));history.add_undo_method(apply_profile.bind(previous));history.commit_action()

func apply_profile(profile:Dictionary)->void:
	library.set_meta(Profile.META,profile);reload_profile()

func reload_profile()->void:
	var profile:=Profile.read(library)
	_pickup.value=profile.pickup_grip
	for key in _values:
		var value:Vector3=profile.poses.get(key)
		for i in 3:_values[key][i].value=value[i]
	for slot in _slots:
		var choice:OptionButton=_slots[slot]
		for i in choice.item_count:
			if choice.get_item_metadata(i)==profile.actions[slot]:choice.select(i)
	if is_instance_valid(actor):actor.free()
	actor=CharacterBody3D.new();_world.add_child(actor)
	var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.22;capsule.height=1.3;collision.shape=capsule;collision.position.y=.66;actor.add_child(collision)
	visual=Visual.new();visual.important_character=true;actor.add_child(visual);assert(visual.setup(actor,1.0,library,true));visual.set_process(false)
	var error:=visual.configure_staff_profile(library);assert(error.is_empty(),error)
	_contact=ContactReadout.new();_contact.visual=visual;visual.skeleton.add_child(_contact)
	visual.staff_profile_event.connect(func(event,slot,seconds):
		event_log.append({"event":event,"slot":slot,"seconds":seconds})
		_events.text="Событие: %s · %s · %.3f с"%[event,slot,seconds])
	_feedback.text="Профиль загружен. Игровые ресурсы не изменены."

func _physics_process(dt:float)->void:
	if not is_instance_valid(actor):return
	actor.velocity=Vector3(0,-.1,1.2 if walking else 0.0);actor.move_and_slide();visual._process(dt)
	var target:=actor.global_position+Vector3(0,.85,0)
	camera.position=target+Vector3(sin(yaw)*3.5,.2,cos(yaw)*3.5);camera.look_at(target)
	_status.text="%s · крепление: %s · основа: %s · %.3f с"%[visual.staff_profile_state(),"правая рука" if visual._profile_attached else "за спиной",visual.current_motion,visual.motion.current_animation_position]
	if visual._profile_attached:_status.text+=" · до цели запястья: %.2f мм"%_contact.error_mm
	_status.modulate=Color.SALMON if visual._profile_attached and _contact.error_mm>5.0 else Color.WHITE
	for slot in Profile.SLOTS:_buttons[String(slot)].disabled=Profile.read(library).actions[slot].is_empty()
