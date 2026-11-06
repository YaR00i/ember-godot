extends RefCounted
## One short-lived GPU burst per stride on the existing authored leaf mask.
const LeafCover := preload("res://scripts/ember_ground_leaf_cover.gd")
const STRIDE_M := 0.78
const MIN_SPEED_M := 1.65
const MIN_INTERVAL := 0.15

var _distance := 0.0
var _cooldown := 0.0
var _left := false
var _particles: GPUParticles3D
var _idle_timer: Timer


func tick(actor: CharacterBody3D, dt: float, unit: float, running: bool) -> void:
	_cooldown = maxf(0.0, _cooldown - dt)
	var motion := actor.get_real_velocity()
	motion.y = 0.0
	var speed := motion.length()
	if not running or not actor.is_on_floor() or speed < MIN_SPEED_M * unit:
		_distance = 0.0
		return
	_distance += speed * dt
	if _distance < STRIDE_M * unit or _cooldown > 0.0: return
	_distance = 0.0
	_cooldown = MIN_INTERVAL
	var scene := actor.get_tree().current_scene
	var map := scene.get_node_or_null("Map") as EmberMapLoader if scene != null else null
	if map == null or not is_instance_valid(map._visual_surface_projection): return
	var forward := motion / speed
	var side := Vector3.UP.cross(forward)
	_left = not _left
	var foot := actor.global_position + side * (0.11 if _left else -0.11) * unit
	var density := LeafCover.painted_density_at(map, map.imported_tile_size, foot)
	if density <= 0.0: return
	var projection := map._visual_surface_projection
	var ground: Dictionary = projection.floor_surface_sample(foot)
	if not ground.get("solid", false) or absf(ground.position.y - foot.y) > unit * 0.25: return
	var water: Dictionary = projection.water_surface_sample(foot)
	if water.get("wet", false) and water.position.y > ground.position.y: return
	_emit(actor, ground.position, forward, side, density, unit)


func _emit(actor: Node3D, point: Vector3, forward: Vector3, side: Vector3, density: float, unit: float) -> void:
	if not is_instance_valid(_particles):
		_particles = _make_emitter(unit)
		actor.add_child(_particles, false, Node.INTERNAL_MODE_BACK)
		_idle_timer = Timer.new()
		_idle_timer.one_shot = true
		_idle_timer.wait_time = _particles.lifetime + 0.12
		_idle_timer.timeout.connect(_particles.hide)
		_particles.add_child(_idle_timer, false, Node.INTERNAL_MODE_BACK)
	_particles.show()
	_idle_timer.start()
	for i in clampi(roundi(2.0 + 5.0 * density), 2, 7):
		var kick := -forward * randf_range(0.55, 1.30) + side * randf_range(-1.0, 1.0)
		kick.y = randf_range(1.35, 2.3)
		var offset := side * randf_range(-0.12, 0.12) + forward * randf_range(-0.14, 0.10) + Vector3.UP * 0.04
		_particles.emit_particle(Transform3D(Basis.IDENTITY, point + offset * unit), kick * unit,
			Color.WHITE, Color(0, 0, 0, 0), GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY)


func _make_emitter(unit: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "GroundLeafSteps"
	emitter.emitting = false
	emitter.amount = 48
	emitter.lifetime = 0.65
	emitter.local_coords = false
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0) * unit, Vector3(8.0, 3.0, 8.0) * unit)
	var motion := ParticleProcessMaterial.new()
	motion.gravity = Vector3.DOWN * unit * 7.0
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -320.0
	motion.angular_velocity_max = 320.0
	motion.scale_min = 0.65
	motion.scale_max = 1.15
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	motion.color_ramp = ramp
	emitter.process_material = motion
	var material := StandardMaterial3D.new()
	material.albedo_texture = LeafCover.preset.albedo_texture
	material.albedo_color = Color(0.83, 0.73, 0.63)
	material.uv1_scale = Vector3(0.5, 0.5, 1.0)
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var leaf := QuadMesh.new()
	leaf.size = Vector2.ONE * unit * 0.21
	leaf.material = material
	emitter.draw_pass_1 = leaf
	return emitter
