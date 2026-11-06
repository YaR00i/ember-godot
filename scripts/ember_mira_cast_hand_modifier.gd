extends SkeletonModifier3D
## Evaluates the clip's leading hand after the neutral ready-pose modifiers.
var apply_hand_pose: Callable

func _process_modification_with_delta(_delta: float) -> void:
	if apply_hand_pose.is_valid():
		apply_hand_pose.call()
