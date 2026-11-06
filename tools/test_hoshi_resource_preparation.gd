extends SceneTree
## Real native resources: preparation must retain the scene across actor lifetimes.
const Hoshi = preload("res://scripts/ember_hoshi_visual.gd")
var errors: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		errors.append(label)
		push_error(label)

func run() -> void:
	var host := Node3D.new()
	check(not await Hoshi.prepare_resources(host), "detached host cannot start preparation")
	root.add_child(host)
	check(await Hoshi.prepare_resources(host), "background resources complete")
	var scene_id := ResourceLoader.get_cached_ref(Hoshi.AVATAR_PATH).get_instance_id()
	var motion_id := ResourceLoader.get_cached_ref(Hoshi.MOTION_PATH).get_instance_id()
	var first_mesh_id := 0
	for cycle in 2:
		var actor := CharacterBody3D.new()
		host.add_child(actor)
		var visual := Hoshi.new()
		visual.important_character = cycle == 1
		actor.add_child(visual)
		check(visual.setup(actor, 16.0), "prepared avatar instantiates")
		check(visual.skeleton.get_bone_count() == 136, "original skeleton remains")
		check(visual.motion.get_animation_library("").get_instance_id() == motion_id, "shared source clips")
		var mesh: MeshInstance3D = visual.avatar.find_children("*", "MeshInstance3D", true, false)[0]
		if cycle == 0:
			first_mesh_id = mesh.mesh.get_instance_id()
		else:
			check(mesh.mesh.get_instance_id() == first_mesh_id, "reveal reuses source geometry")
		actor.free()
		await process_frame
		check(ResourceLoader.has_cached(Hoshi.AVATAR_PATH), "scene retained after last actor leaves")
		check(ResourceLoader.get_cached_ref(Hoshi.AVATAR_PATH).get_instance_id() == scene_id, "same prepared scene after removal")
		check(await Hoshi.prepare_resources(host), "repeated preparation reuses completed assets")
	host.free()
	await process_frame
	print("HOSHI_RESOURCE_PREPARATION ", JSON.stringify({"pass": errors.is_empty(), "errors": errors}))
	quit(0 if errors.is_empty() else 1)
