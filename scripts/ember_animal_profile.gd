extends Resource
## An entry in content/animals. Animation names address the model's library.

enum Reaction { ENCOUNTER, RETREAT, STARTLE, FREEZE }

@export var display_name: String
@export var model: PackedScene
@export var model_scale := 1.0
@export var model_yaw := PI
@export var ground_offset := 0.0
@export var idle_clip := &"idle"
@export var move_clip := &"walk"
@export var reaction: Reaction = Reaction.FREEZE
@export var walk_speed := 7.0
@export var retreat_speed := 12.0
@export var notice_distance := 18.0
@export var roam_radius := 9.0
@export var retreat_radius := 18.0
@export var body_size := Vector3(4, 8, 6)
