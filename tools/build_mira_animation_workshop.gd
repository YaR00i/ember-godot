extends SceneTree

const Visual = preload("res://scripts/ember_hoshi_visual.gd")
const Workshop = preload("res://tools/ember_mira_animation_workshop.gd")
const BAKED_LIBRARY := "res://assets/local_characters/hoshi/mira_motion_trial.res"
const EDITABLE_LIBRARY := "res://assets/local_characters/hoshi/mira_motion_editable.tres"
const WORKSHOP_SCENE := "res://assets/local_characters/hoshi/mira_animation_workshop.scn"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if not ResourceLoader.exists(EDITABLE_LIBRARY):
		var source := load(BAKED_LIBRARY) as AnimationLibrary
		if source == null or ResourceSaver.save(source, EDITABLE_LIBRARY) != OK:
			push_error("Сначала нужна локальная библиотека пробы Миры.")
			quit(1)
			return
	if FileAccess.file_exists(WORKSHOP_SCENE):
		print("Мастерская Миры уже подготовлена.")
		quit()
		return
	var library := load(EDITABLE_LIBRARY) as AnimationLibrary
	var workshop := CharacterBody3D.new()
	workshop.name = "MiraAnimationWorkshop"
	workshop.set_script(Workshop)
	root.add_child(workshop)
	var visual := Visual.new()
	visual.name = "Mira"
	workshop.add_child(visual)
	if not visual.setup(workshop, 1.0, library) or not is_instance_valid(visual._back_weapon_socket):
		push_error("Не удалось собрать риг Миры с посохом.")
		quit(1)
		return

	var motion := visual.motion
	# Expose the actual editable library on the native timeline.
	motion.stop()
	motion.remove_animation_library("")
	motion.add_animation_library("", library)
	motion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	workshop.set("player_path", workshop.get_path_to(motion))
	workshop.set("skeleton_path", workshop.get_path_to(visual.skeleton))
	workshop.set("socket_path", workshop.get_path_to(visual._back_weapon_socket))
	workshop.set("staff_path", workshop.get_path_to(visual._back_weapon))
	workshop.set("chest_bone", visual._back_weapon_bone)
	workshop.editor_description = "Motion → шкала анимации. BackWeaponSocket → стрелки и Transform. Кнопки сохранения находятся в инспекторе корня."
	visual.set_script(null)
	add_lighting(workshop)
	own_children(workshop, workshop)
	var scene := PackedScene.new()
	if scene.pack(workshop) != OK or ResourceSaver.save(scene, WORKSHOP_SCENE, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Не удалось сохранить сцену мастерской Миры.")
		quit(1)
		return
	print("Мастерская Миры готова: ", WORKSHOP_SCENE)
	quit()

func own_children(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		# The preview needs native editor access to the rig and its controls.
		child.scene_file_path = ""
		child.owner = owner_node
		own_children(child, owner_node)

func add_lighting(workshop: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.19, 0.22, 0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	workshop.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	workshop.add_child(sun)
	var camera := Camera3D.new()
	workshop.add_child(camera)
	camera.position = Vector3(1.65, 1.15, 2.60)
	camera.look_at(Vector3(0.0, 0.76, 0.0))
	camera.fov = 38.0
	camera.current = true
