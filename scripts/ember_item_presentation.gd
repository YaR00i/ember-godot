extends Node3D
## Native world-scene data: collision shape/material live beside the item model.
@export_group("Физика предмета")
@export var body_shape: Shape3D
@export var body_center := Vector3.ZERO
@export var surface: PhysicsMaterial
@export_range(0.0,8.0,0.05,"or_greater") var linear_damping := 1.0
@export_range(0.0,8.0,0.05,"or_greater") var angular_damping := 2.0
static var _scaled_shapes: Dictionary={}

static func _clear_scaled_shapes() -> void:
	_scaled_shapes.clear()

func scaled_body_shape(world_size: float) -> Shape3D:
	if body_shape==null or not is_finite(world_size) or world_size<=0.0:return null
	var key:=str(body_shape.get_instance_id())+":"+str(world_size)
	if _scaled_shapes.has(key):return _scaled_shapes[key]
	if not body_shape.changed.is_connected(_clear_scaled_shapes):body_shape.changed.connect(_clear_scaled_shapes)
	# Dynamic bodies need native-size shapes, not scaled collision nodes.
	var result:=body_shape.duplicate() as Shape3D
	if result is SphereShape3D:result.radius*=world_size
	elif result is BoxShape3D:result.size*=world_size
	elif result is CapsuleShape3D or result is CylinderShape3D:
		result.height*=world_size;result.radius*=world_size
	elif result is ConvexPolygonShape3D:
		var points: PackedVector3Array=result.points
		for i in points.size():points[i]*=world_size
		result.points=points
	result.margin*=world_size
	if _scaled_shapes.size()>=16:_scaled_shapes.erase(_scaled_shapes.keys()[0])
	_scaled_shapes[key]=result
	return result

func validation_errors() -> Array[String]:
	var errors: Array[String]=[]
	if body_shape!=null and not (body_shape is SphereShape3D or body_shape is BoxShape3D or body_shape is CapsuleShape3D or body_shape is CylinderShape3D or body_shape is ConvexPolygonShape3D):
		errors.append("Item needs a convex dynamic-body shape")
	if body_shape is ConvexPolygonShape3D:
		var points: PackedVector3Array=body_shape.points
		if points.size()<4:errors.append("Item collision hull is empty")
		for point in points:
			if not point.is_finite():errors.append("Invalid item collision point");break
	if not body_center.is_finite():errors.append("Invalid item collision centre")
	for value in [linear_damping,angular_damping]:
		if not is_finite(value) or value<0.0:errors.append("Invalid item damping")
	if surface!=null:
		for value in [surface.friction,surface.bounce]:
			if not is_finite(value) or value<0.0 or value>1.0:errors.append("Invalid item surface material")
	return errors
