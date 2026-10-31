@tool
extends Area3D
## Observes an existing persistent world body; ExploreState owns quest progress.
@export var quest_id := ""
@export var objective_id := ""
@export var target_pickup_id := ""
@export_range(0.0, 5.0, 0.05) var settle_seconds := 0.35
var progress_state: EmberExploreState
var _settled := 0.0
var _completion_flag := ""

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitoring = not Engine.is_editor_hint()
	set_physics_process(not Engine.is_editor_hint())
	if progress_state == null:
		progress_state = get_node_or_null("/root/EmberExploreProgress")
	_completion_flag = completion_flag()

func completion_flag() -> String:
	var quest := EmberQuestCatalog.definition(quest_id)
	for objective in quest.get("objectives", []):
		if str(objective.get("id", "")) == objective_id and str(objective.get("progressMode", "flag")) == "flag":
			return str(objective.get("flagId", ""))
	return ""

func accepts_body(body: Node3D) -> bool:
	return preload("res://scripts/ember_object_zone_rules.gd").accepts_body(self, body, target_pickup_id)

func _physics_process(delta: float) -> void:
	if progress_state == null:
		return
	var flag := _completion_flag
	if flag.is_empty() or progress_state.flags.get(flag, false) == true:
		_settled = 0.0
		return
	var inside := false
	for body in get_overlapping_bodies():
		if accepts_body(body):
			inside = true
			break
	_settled = _settled + delta if inside else 0.0
	if inside and _settled >= settle_seconds:
		_settled = 0.0
		progress_state.apply_authored_flag(flag, true)
