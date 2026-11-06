extends MeshInstance3D

const RANGE_M := 8.0

var direction := Vector3.FORWARD
var speed := 0.0
var remaining := 0.0
var radius := 0.0
var shooter: RID
var target: WeakRef
var on_hit: Callable


func launch(unit: float, source: RID, forward: Vector3, enemy: Node3D, hit: Callable) -> void:
	direction = forward.normalized()
	speed = 13.0 * unit
	remaining = RANGE_M * unit
	radius = 0.30 * unit
	shooter = source
	target = weakref(enemy) if is_instance_valid(enemy) else null
	on_hit = hit
	var bolt := CapsuleMesh.new()
	bolt.radius = unit * 0.075
	bolt.height = unit * 0.55
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.68, 0.36, 1.0)
	bolt.material = glow
	mesh = bolt
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := MeshInstance3D.new()
	var spark := SphereMesh.new()
	spark.radius = unit * 0.063
	spark.height = unit * 0.126
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.99, 0.87, 1.0)
	spark.material = white
	core.mesh = spark
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.position.y = unit * 0.19
	add_child(core)
	quaternion = Quaternion(Vector3.UP, direction)


func _physics_process(dt: float) -> void:
	if not on_hit.is_valid():
		queue_free()
		return
	var distance := minf(remaining, speed * dt)
	var from := global_position
	var to := from + direction * distance
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [shooter])
	ray.collide_with_areas = true
	ray.hit_from_inside = true
	var collision := get_world_3d().direct_space_state.intersect_ray(ray)
	var enemy := target.get_ref() as Node3D if target != null else null
	if is_instance_valid(enemy) and enemy.is_visible_in_tree():
		var aim: Vector3 = enemy.field_spell_aim_point()
		var nearest := Geometry3D.get_closest_point_to_segment(aim, from, to)
		if nearest.distance_squared_to(aim) <= radius * radius and (collision.is_empty() or from.distance_squared_to(nearest) < from.distance_squared_to(collision.position)):
			on_hit.call(enemy, direction)
			queue_free()
			return
	if not collision.is_empty():
		on_hit.call(collision.collider, direction)
		queue_free()
		return
	global_position = to
	remaining -= distance
	if remaining <= 0.0:
		queue_free()
