extends SceneTree
## Native Forward+ proof: measure actual shadow primitives, not policy metadata.
const Shadow = preload("res://scripts/ember_runtime_shadow_lod.gd")
const Lod = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
class ObservedShadow extends "res://scripts/ember_runtime_shadow_lod.gd":
	var full_updates := 0
	func update(object: Node3D, state: Dictionary) -> bool:
		full_updates += 1
		return super.update(object, state)
class QuietMap extends EmberMapLoader:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
class Anchors extends Node:
	var points: Array[Vector3] = [Vector3.ZERO]
	func physics_activity_anchors(_world: World3D) -> Array[Vector3]: return points
var errors: Array[String] = []
var stage: Node3D
var map: EmberMapLoader
var camera: Camera3D
var sun: DirectionalLight3D
var prop: EmberVoxelProp
var visual: MeshInstance3D
var mesh: ArrayMesh
var observations: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("SHADOW_LOD_FAIL ", label)
func frames(count := 6) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func stats() -> Dictionary:
	await frames()
	return {"visible": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow": root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"draws": root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
func update() -> void:
	map._runtime_shadow_lights_dirty = true
	map._update_runtime_shadow_context()
	map._update_prop_shadow(prop)
func active() -> bool:
	return prop._runtime_shadow != null and is_instance_valid(prop._runtime_shadow.proxy)
func stored_uniform(node: GeometryInstance3D, name: String) -> bool:
	for property in node.get_property_list():
		if property.name == "instance_shader_parameters/" + name:
			return (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0
	return false
func run() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		printerr("SHADOW_LOD_FAIL requires native Forward+ GPU"); quit(2); return
	root.size = Vector2i(1024, 640)
	root.mesh_lod_threshold = 1.0
	root.use_taa = false
	stage = Node3D.new(); root.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new(); settings.background_mode = Environment.BG_COLOR; settings.background_color = Color("7e91a6")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color = Color.WHITE; settings.ambient_light_energy = 0.25
	environment.environment = settings; stage.add_child(environment)
	camera = Camera3D.new(); camera.position = Vector3(0, 70, 140); camera.fov = 70; camera.far = 600
	stage.add_child(camera); camera.look_at(Vector3.ZERO); camera.make_current()
	sun = DirectionalLight3D.new(); sun.name = "Sun"; sun.rotation_degrees = Vector3(-55, -20, 0)
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 500; sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	stage.add_child(sun)
	var receiver := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(600, 600); receiver.mesh = plane
	var floor_material := StandardMaterial3D.new(); floor_material.albedo_color = Color("bcba99"); receiver.material_override = floor_material
	stage.add_child(receiver)
	map = QuietMap.new(); map.imported_tile_size = 1.0; map.world_look = 0; map.compact_ground_style = 1
	var terrain := EmberTerrainPilotResource.new(); terrain.width = 128; terrain.depth = 128; terrain.origin_y = 0
	map.compact_terrain = terrain; stage.add_child(map)
	var anchors := Anchors.new(); stage.add_child(anchors); map.set_physics_activity_source(anchors)
	var sphere := SphereMesh.new(); sphere.radius = 8; sphere.height = 20; sphere.radial_segments = 64; sphere.rings = 32
	var source := ArrayMesh.new(); source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays()); source.surface_set_name(0, "shadow_fixture")
	var baked := Lod.object_mesh(source); mesh = baked.mesh
	check(baked.levels > 0 and Shadow.has_lods(mesh), "actual source ArrayMesh has native index LODs")
	prop = EmberVoxelProp.new(); prop.position = Vector3(80, 10, 0)
	visual = MeshInstance3D.new(); visual.name = "Mesh"; visual.mesh = mesh; visual.lod_bias = 1000.0
	var shader := Shader.new(); shader.code = "shader_type spatial; instance uniform vec4 dye : source_color = vec4(0.4,0.65,0.2,1.0); uniform float sway = 0.15; void vertex(){VERTEX.x += sin(VERTEX.y)*sway;} void fragment(){ALBEDO=dye.rgb;ALPHA=step(0.25,fract(UV.x*8.0));ALPHA_SCISSOR_THRESHOLD=0.5;}"
	var material := ShaderMaterial.new(); material.shader = shader
	visual.material_override = material; visual.set_surface_override_material(0, material)
	visual.custom_aabb = mesh.get_aabb().grow(0.25); visual.extra_cull_margin = 0.5
	prop.add_child(visual)
	var body := StaticBody3D.new(); body.name = "Collision"; prop.add_child(body)
	var shape := CollisionShape3D.new(); shape.name = "Shape"; shape.shape = source.create_trimesh_shape(); body.add_child(shape)
	var physical_shape := shape.shape
	map.add_child(prop); prop.owner = stage; prop._world_look = 0
	prop._distance_mesh = mesh; prop._distance_source = source
	prop._runtime_shadow = ObservedShadow.new()
	Shadow.forward_instance_parameter(visual,"dye", Color("81a85c"))
	var original_transform := visual.transform; var original_bias := visual.lod_bias
	var original_surfaces: Array = mesh.get("_surfaces").duplicate(true)
	observations.baseline = await stats()
	update()
	observations.context = {"enabled": map.editor_object_detail_enabled(), "empty": map._runtime_shadow_context.is_empty(), "world_look": map.world_look, "ground_style": map.compact_ground_style, "lods": Shadow.has_lods(mesh)}
	check(active(), "far native shadow proxy admitted")
	if active():
		var proxy: MeshInstance3D = prop._runtime_shadow.proxy
		check(proxy.owner == null and proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "derived proxy is unsaved SHADOWS_ONLY")
		check(proxy.mesh == visual.mesh and proxy.material_override == material and proxy.get_surface_override_material(0) == material, "identical mesh, shader, alpha and surface override pointers")
		check(proxy.transform == visual.transform and proxy.layers == visual.layers and proxy.custom_aabb == visual.custom_aabb and proxy.extra_cull_margin == visual.extra_cull_margin, "transform, bounds and caster layers match")
		check(proxy.get_instance_shader_parameter("dye") == visual.get_instance_shader_parameter("dye"), "instance shader parameters match")
	check(visual.visible and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and visual.lod_bias == original_bias, "visible source remains drawn with its original LOD bias")
	observations.proxy = await stats()
	check(observations.baseline.shadow > 0 and observations.proxy.shadow > 0 and observations.proxy.shadow < observations.baseline.shadow, "native lod_bias actually reduces directional shadow primitives")
	check(observations.proxy.visible == observations.baseline.visible, "visible geometry primitive count is unchanged")
	check(shape.shape == physical_shape and not shape.disabled and body.collision_layer == 1 and prop.runtime_physics_safe(), "proxy preserves canonical collision and existing physics activity eligibility")
	if active():
		var ready_proxy: MeshInstance3D = prop._runtime_shadow.proxy
		var full_updates: int = prop._runtime_shadow.full_updates
		var changed_receivers := 0
		var receiver_state: Array = map._runtime_shadow_context.receivers.duplicate()
		for turn in 64:
			camera.position.x = 8.0 if turn % 2 == 0 else -8.0
			camera.look_at(Vector3.ZERO)
			map._update_runtime_shadow_context()
			if map._runtime_shadow_context.receivers != receiver_state: changed_receivers += 1
			receiver_state = map._runtime_shadow_context.receivers.duplicate()
		check(changed_receivers == 64 and prop._runtime_shadow.proxy == ready_proxy, "camera receiver sweeps keep already-published distant shadow")
		check(prop._runtime_shadow.full_updates == full_updates, "camera receiver sweeps do not repeat full object binding")
		camera.position.x = 0; camera.look_at(Vector3.ZERO); map._update_runtime_shadow_context()
	if active():
		var stable_proxy: MeshInstance3D = prop._runtime_shadow.proxy
		var rebuilds: int = prop._runtime_shadow._parameter_rebuilds
		var scans: int = prop._runtime_shadow._explicitness_scans
		var getters: int = prop._runtime_shadow._parameter_getters
		var defaults: int = prop._runtime_shadow._default_getters
		for repeat in 256: update()
		check(prop._runtime_shadow.proxy == stable_proxy and stable_proxy.get_instance_shader_parameter("dye") == visual.get_instance_shader_parameter("dye"), "stable repeated updates retain proxy and explicit instance value")
		Shadow.forward_instance_parameter(visual,"dye", Color("b28f62"))
		check(stable_proxy.get_instance_shader_parameter("dye") == visual.get_instance_shader_parameter("dye"), "changed explicit instance value reaches proxy")
		Shadow.forward_instance_parameter(visual,"dye", null)
		check(not stored_uniform(stable_proxy,"dye"), "cleared source override returns proxy to shared shader default")
		for repeat in 256: update()
		check(not stored_uniform(stable_proxy,"dye"), "stable unset defaults stay unset")
		check(prop._runtime_shadow._parameter_rebuilds == rebuilds and prop._runtime_shadow._explicitness_scans == scans, "512 stable updates avoid repeated binding rebuilds and explicitness scans")
		observations.stable_reads = {"source": prop._runtime_shadow._parameter_getters-getters, "defaults": prop._runtime_shadow._default_getters-defaults}
		check(observations.stable_reads.source == 0 and observations.stable_reads.defaults == 0, "512 stable updates and forwarded changes perform zero RS value getters")
		# Explicitly setting the same shader default and clearing it must also
		# leave the proxy unset, even though the native getter's value is equal.
		Shadow.forward_instance_parameter(visual,"dye", Color(0.4,0.65,0.2,1.0))
		check(not stored_uniform(stable_proxy,"dye"), "explicit shader default needs no proxy override")
		Shadow.forward_instance_parameter(visual,"dye", null)
		check(not stored_uniform(stable_proxy,"dye"), "equal-value clear remains at shared shader default")
		check(stable_proxy.get_meta(Shadow.DERIVED_PROXY_META,false), "proxy is marked for source-owned instance styling")
	# A same-bias proxy must reproduce the original rendered frame exactly.
	if active(): prop._runtime_shadow.proxy.lod_bias = visual.lod_bias
	await frames()
	var proxy_image := root.get_texture().get_image()
	prop.restore_runtime_shadow_lod(); await frames()
	var source_image := root.get_texture().get_image()
	check(proxy_image.get_data() == source_image.get_data(), "same-bias proxy preserves native alpha/shadow image exactly")
	update(); map.set_runtime_shadow_lod_enabled(false)
	check(not active() and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "runtime A/B switch immediately restores source caster")
	update(); check(not active(), "disabled shadow LOD cannot readmit proxies")
	Shadow.forward_instance_parameter(visual,"dye", Color("8a7c63"))
	check(not visual.has_meta(Shadow.SOURCE_BINDING_META), "inactive source has no retained helper binding")
	map.set_runtime_shadow_lod_enabled(true)
	update()
	check(active() and prop._runtime_shadow.proxy.get_instance_shader_parameter("dye") == visual.get_instance_shader_parameter("dye"), "inactive forwarded value is captured on return")
	Shadow.forward_instance_parameter(visual,"dye", null)
	visual.set_instance_shader_parameter("dye", Color("ad9267"))
	Shadow.invalidate_instance_parameters(visual)
	check(not active() and not visual.has_meta(Shadow.SOURCE_BINDING_META), "external raw setter explicitly invalidates source binding and restores caster")
	update()
	check(active() and prop._runtime_shadow.proxy.get_instance_shader_parameter("dye") == visual.get_instance_shader_parameter("dye"), "explicit invalidation takes one fresh snapshot")
	Shadow.forward_instance_parameter(visual,"dye", null)
	# Active local shadows, alternate directional owners and low sun pin full geometry.
	update(); var local := OmniLight3D.new(); local.shadow_enabled = true; local.omni_range = 30; local.position = prop.position
	stage.add_child(local); update(); check(not active(), "affecting local shadow light retains full caster"); local.free()
	update(); sun.rotation_degrees.x = -5; update(); check(not active(), "low sun retains full caster")
	sun.rotation_degrees = Vector3(-55, -20, 0); update(); check(active(), "sun return readmits valid native proxy")
	var moon := DirectionalLight3D.new(); moon.shadow_enabled = true; stage.add_child(moon); update()
	check(not active(), "multiple directional shadow lights retain full caster"); moon.free()
	# A remote, offscreen high caster can still cast into the near receiver area.
	sun.rotation_degrees = Vector3(-30, -90, 0); prop.position = Vector3(-200, 120, 0)
	update(); check(not camera.is_position_in_frustum(prop.global_position), "long-shadow fixture caster is genuinely offscreen")
	check(not active() and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "offscreen long shadow crossing near receivers pins original caster")
	sun.rotation_degrees = Vector3(-55, -20, 0); prop.position = Vector3(80, 10, 0); update()
	check(active(), "far caster restored after long-shadow control")
	var near_receiver := map._runtime_shadow_context.duplicate()
	near_receiver.receivers = near_receiver.receivers.duplicate()
	near_receiver.receivers.append(Shadow.receiver_area(prop.object_detail_bounds()).grow(24.0))
	check(prop.has_method("recheck_runtime_shadow_receivers"), "receiver-only entry point is available")
	if prop.has_method("recheck_runtime_shadow_receivers"):
		check(not prop.call("recheck_runtime_shadow_receivers", near_receiver) and not active(), "receiver-only near entry immediately restores full shadow caster")
		update()
		visual.position.x += 1.0
		check(not prop.call("recheck_runtime_shadow_receivers", map._runtime_shadow_context) and not active(), "receiver-only transform change restores full caster")
		visual.position.x -= 1.0; update()
		visual.custom_aabb = visual.custom_aabb.grow(0.25)
		check(not prop.call("recheck_runtime_shadow_receivers", map._runtime_shadow_context) and not active(), "receiver-only bounds change restores full caster")
		visual.custom_aabb = mesh.get_aabb().grow(0.25); update()
		visual.layers = 3
		check(not prop.call("recheck_runtime_shadow_receivers", map._runtime_shadow_context) and not active(), "receiver-only layer change restores full caster")
		visual.layers = 1; update()
		var replacement := material.duplicate() as Material
		visual.set_surface_override_material(0, replacement)
		check(not prop.call("recheck_runtime_shadow_receivers", map._runtime_shadow_context) and not active(), "receiver-only surface replacement restores full caster")
		visual.set_surface_override_material(0, material)
	update(); check(active(), "near receiver departure permits readmission")
	# Source Resource invalidation is synchronous, before the next bounded scan.
	material.shader = shader.duplicate(); check(not active() and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "material replacement invalidates proxy synchronously")
	update(); check(active(), "replacement material readmits using current pointers")
	material.shader.code += "\n"; check(not active(), "Shader Resource change invalidates cached parameter bindings")
	update(); check(active() and not stored_uniform(prop._runtime_shadow.proxy,"dye"), "shader rebind preserves unset defaults")
	mesh.emit_changed(); check(not active(), "mesh Resource change immediately restores source caster")
	update(); check(active(), "mesh LOD cache revalidates without duplicate signal connections")
	prop.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE); check(not active(), "editor save restores authored caster")
	update(); var other := Node3D.new(); stage.add_child(other); prop.reparent(other)
	check(not active() and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "reparent restores source caster")
	prop.reparent(map); prop._world_look = 0; update()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED; prop.restore_runtime_shadow_lod(); update()
	check(not active() and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "double-sided authored caster is preserved")
	check(mesh.get("_surfaces") == original_surfaces and visual.transform == original_transform, "source geometry and transform remain unchanged")
	map.set_physics_activity_source(null)
	var helper_lifetime: WeakRef = weakref(prop._runtime_shadow)
	stage.free(); await process_frame
	check(helper_lifetime.get_ref() == null, "freeing source releases helper resources and weak metadata binding")
	var result := {"pass": errors.is_empty(), "errors": errors, "native": observations, "native_lod_levels": baked.levels,
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": root.size}
	var file := FileAccess.open("user://runtime-shadow-lod.json", FileAccess.WRITE); file.store_string(JSON.stringify(result, "  ")); file.close()
	print("RUNTIME_SHADOW_LOD ", JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
