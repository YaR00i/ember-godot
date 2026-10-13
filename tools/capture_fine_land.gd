extends SceneTree
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
var errors: Array[String]=[]
var output:="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func capture(name: String) -> void:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name))==OK,"image "+name)
	print("CAPTURE ",name)
func run() -> void:
	for suffix in ["legacy","fine"]:
		var scene=load("res://scenes/compact_landform_"+suffix+"_study.tscn").instantiate();root.add_child(scene)
		var deadline:=Time.get_ticks_msec()+120000
		while not scene.ready_for_morph and Time.get_ticks_msec()<deadline:await process_frame
		check(scene.ready_for_morph,"ready");if not scene.ready_for_morph:quit(1);return
		var map=scene.get_node("Map");var projection=map._visual_surface_projection
		var original: Resource=map.compact_terrain.working_copy()
		scene.get_node("Instructions").hide()
		var clay:=StandardMaterial3D.new();clay.albedo_color=Color("b8b9a5");clay.roughness=1
		for tile in projection._tiles.values():tile.get_node("Ground").material_override=clay
		await capture("landform-"+suffix+"-clay.png")
		if suffix=="fine":
			for phase in [0.0,0.5,1.0,0.0]:
				scene.set_phase(phase);await physics_frame;await physics_frame
				for key: Vector2i in scene.preparations:
					var entry: Dictionary=scene.preparations[key]
					var faces: PackedVector3Array=projection._tiles[key].get_node("GroundPhysics/Shape").shape.get_faces()
					for i in range(0,faces.size(),maxi(1,faces.size()/79)):
						check(absf(faces[i].y-Smooth.corner(entry.current,roundi(faces[i].x),roundi(faces[i].z)))<0.002,"fine mesh/collision/field parity")
				await capture("landform-fine-phase-%d.png"%roundi(phase*2))
			check(map.compact_terrain.same_terrain_data(original),"same source through all appearances")
			for entry: Dictionary in scene.preparations.values():check(entry.current.heights==entry.base.heights,"return exact fine form")
		for tile in projection._tiles.values():tile.get_node("Ground").material_override=null
		await capture("landform-"+suffix+"-materials.png")
		scene.queue_free();await process_frame;await process_frame
	print("FINE_LAND_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
