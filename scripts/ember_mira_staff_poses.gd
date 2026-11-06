@tool
extends Resource

const PATH := "res://scenes/props/mira_staff_poses.tres"
const CAST := &"staff_strike"

@export_range(0.0, 0.8, 0.01) var grip := 0.53
## Center of the shaft inside the curled right fingers, in hand-bone space.
@export var right_palm_contact := Vector3(-0.061, -0.013, 0.003)
## Tilts the shaft across the palm while clearing the cuff.
@export_range(-45.0, 45.0, 0.5) var right_palm_grip_tilt_degrees := -30.0
## Leaves room for the rear end of the staff alongside the torso.
@export_range(-30.0, 30.0, 0.5) var right_palm_grip_yaw_degrees := 12.0
@export var ready_hand := Vector3(-0.30, 0.94, 0.12)
@export var ready_direction := Vector3(-0.18, 0.98, 0.10)
@export var cast_hand := Vector3(-0.19, 1.10, 0.32)
@export var cast_direction := Vector3(-0.06, 0.72, 0.69)

func is_valid() -> bool:
	return is_finite(grip) and grip >= 0.0 and grip <= 0.8 \
		and is_finite(right_palm_grip_tilt_degrees) and is_finite(right_palm_grip_yaw_degrees) and right_palm_contact.is_finite() and ready_hand.is_finite() and cast_hand.is_finite() \
		and ready_direction.is_finite() and ready_direction.length_squared() > 0.001 \
		and cast_direction.is_finite() and cast_direction.length_squared() > 0.001

## Keep the prop's authored rotation relative to the hand while aligning the two contacts.
static func align_grip(hand_world: Transform3D, hand_contact: Transform3D, object_contact: Transform3D, grip_basis: Basis) -> Transform3D:
	return hand_world * hand_contact * Transform3D(grip_basis, Vector3.ZERO) * object_contact.affine_inverse()

func chest_motion(avatar: Node3D, skeleton: Skeleton3D, chest: int) -> Transform3D:
	var skeleton_frame := avatar.global_transform.affine_inverse() * skeleton.global_transform
	var rest := skeleton_frame * skeleton.get_bone_global_rest(chest)
	var animated := skeleton_frame * skeleton.get_bone_global_pose(chest)
	return Transform3D.IDENTITY.interpolate_with(animated * rest.affine_inverse(), 0.60)

func staff_pose(chest_delta: Transform3D, casting: bool) -> Transform3D:
	var hand := cast_hand if casting else ready_hand
	var direction := (cast_direction if casting else ready_direction).normalized()
	var up := Vector3.UP if absf(direction.y) < 0.95 else Vector3.BACK
	var orientation := Basis.looking_at(direction, up, true)
	return chest_delta * Transform3D(orientation, hand - orientation.z * grip)


func apply_spell_pose(staff: Node3D, skeleton: Skeleton3D, chest: int, clip: Animation, seconds: float, aim_point := Vector3.INF) -> void:
	var avatar := staff.get_parent() as Node3D
	var release := clip.get_marker_time(&"impact") if clip.has_marker(&"impact") else minf(0.38, clip.length)
	var aim := smoothstep(0.0, maxf(0.001, release), seconds)
	aim *= 1.0 - smoothstep(release, maxf(release + 0.001, clip.length), seconds)
	var chest_delta := chest_motion(avatar, skeleton, chest)
	var cast := staff_pose(chest_delta, true)
	if aim_point.is_finite():
		var hand := chest_delta * cast_hand
		var direction := (avatar.to_local(aim_point) - hand).normalized()
		if not direction.is_zero_approx():
			var up := Vector3.UP if absf(direction.y) < 0.95 else Vector3.BACK
			var orientation := Basis.looking_at(direction, up, true)
			cast = Transform3D(orientation, hand - orientation.z * grip)
	staff.transform = staff_pose(chest_delta, false).interpolate_with(cast, aim)
	var wrist := staff.get_node("RightGrip/Wrist") as Marker3D
	wrist.position.z = grip
	(avatar.get_node("RightElbowHint") as Node3D).position = Vector3(-0.48, 0.87, -0.05)
	for name in ["RightGripIK", "RightGripRotation", "LeftGripIK", "LeftGripRotation"]:
		(skeleton.get_node(name) as SkeletonModifier3D).influence = 1.0 if name.begins_with("Right") else 0.0
