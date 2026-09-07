@tool
class_name EmberVnBackground
extends Resource
## Godot-owned metadata for one VN background/CG.
## The image lives under res://assets/vn_backgrounds; dialogue documents keep a
## stable string ID so graph edges and runtime state do not depend on file paths.

@export var id := ""
@export var display_name := ""
@export_file var image_path := ""
@export_enum("cg", "splash") var kind := "cg"
@export var tags: PackedStringArray = []


func normalized_id() -> String:
	return id.strip_edges()


func caption() -> String:
	var clean := display_name.strip_edges()
	return clean if not clean.is_empty() else normalized_id()
