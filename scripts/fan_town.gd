extends Node3D
## Fan town from `content/ember` — lighting gate, not play.

@export var map_id := "fan_town"

@onready var _hud: Label = $CanvasLayer/Gate


func _ready() -> void:
	var loader := EmberMapLoader.new()
	loader.name = "Map"
	add_child(loader)
	var stats: Dictionary = loader.load_map(map_id)
	var cam := OrbitCamera.new()
	var ts := float(stats.get("tile_size", 16))
	var w := float(stats.get("width", 32))
	var h := float(stats.get("height", 32))
	cam.target = Vector3(w * ts * 0.5, 10.0, h * ts * 0.5)
	cam.distance = 90.0
	cam.pitch = 0.72
	add_child(cam)
	_hud.text = _gate_text(stats)


func _gate_text(stats: Dictionary) -> String:
	return "\n".join([
		"Ember Godot — lighting gate (%s)" % map_id,
		"Pack: %s" % EmberPack.pack_root(),
		"Props %s   Omni %s   Omni with shadow %s   Missing .vox %s" % [
			stats.get("props", 0),
			stats.get("omni", 0),
			stats.get("omni_shadow", 0),
			stats.get("missing_vox", 0),
		],
		"RMB orbit · wheel zoom",
		"",
		"Gate (look, don't code play yet):",
		"  [ ] Night fill from lanterns, not a flat ambient",
		"  [ ] Lamp umbras on the ground (several at once)",
		"  [ ] No hitch / freeze while looking around",
		"Fail any box → stay in JOI for mechanics. Pass → then walk/camera.",
	])
