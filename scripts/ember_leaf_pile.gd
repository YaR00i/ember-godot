extends Area3D
## Authored cover for an existing flag-gated world pickup. ExploreState owns progress.
@export var revealed_flag_id := ""
@export var scatter_effect: PackedScene
var progress_state: EmberExploreState

func _ready() -> void:
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	if progress_state == null: progress_state = get_node_or_null("/root/EmberExploreProgress")
	if progress_state != null:
		progress_state.progress_changed.connect(_refresh)
	_refresh()

func _on_body_entered(body: Node3D) -> void:
	if body is EmberPlayer:
		# Revealing thaws the pickup; do it outside the physics query flush.
		_trample.call_deferred(weakref(body))

func _trample(reference: WeakRef) -> void:
	var actor := reference.get_ref() as EmberPlayer
	if actor == null or not actor.is_inside_tree(): return
	var direction := Vector3(actor.velocity.x, 0, actor.velocity.z)
	if direction.length_squared() < 0.01:
		direction = global_position - actor.global_position
		direction.y = 0
	receive_world_hit(actor, direction.normalized())

func _refresh() -> void:
	var revealed: bool = progress_state != null and progress_state.flags.get(revealed_flag_id, false) == true
	var visual := get_node_or_null("PileVisual") as Node3D
	if visual != null: visual.visible = not revealed
	collision_layer = 0 if revealed or revealed_flag_id.strip_edges().is_empty() else 4

func receive_world_hit(_actor: Node3D, direction: Vector3) -> bool:
	if progress_state == null or progress_state.combat_party_locked or revealed_flag_id.strip_edges().is_empty(): return false
	if progress_state.flags.get(revealed_flag_id, false) == true: return false
	var result := progress_state.reveal_world_cover(revealed_flag_id, world_cover_action())
	if not bool(result.get("changed", false)): return false
	if scatter_effect != null:
		var effect := scatter_effect.instantiate()
		if effect is Node3D and effect.has_method("play"):
			get_tree().current_scene.add_child(effect)
			effect.play(global_transform, 16.0, direction)
		else: effect.free()
	return true

func world_hit_feedback() -> String:
	return "Листья разлетелись — под ними что-то лежит"

func world_cover_action() -> String:
	return "reveal_leaves"
