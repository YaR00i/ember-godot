extends EmberInteract
## The player drives the run through the existing CharacterBody3D controller.

@onready var sled_visual: Node3D = $SledVisual
@onready var launch: Marker3D = $Launch
@onready var _parked_transform := sled_visual.transform


func refresh_runtime_binding() -> void:
	if not Engine.is_editor_hint():
		add_to_group("ember_interact")


func prompt() -> String:
	return "Сесть в сани"


func activate_from(actor: Node3D) -> String:
	if actor.begin_ice_sled(self):
		return "Сани · A / D — рулить"
	return "Подойди к саням и освободи руки."


func update_rider(at: Vector3, heading: Vector3, normal: Vector3) -> void:
	var forward := heading.slide(normal).normalized()
	sled_visual.global_transform = Transform3D(
		Basis(normal.cross(forward).normalized(), normal, forward), at
	)


func park() -> void:
	sled_visual.transform = _parked_transform
