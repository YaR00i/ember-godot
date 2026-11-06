extends "res://scripts/ember_interact.gd"
## The point owns fish profiles. The bag and completion flag stay in ExploreState.

@export var caught_flag_id := ""
@export var intro_dialogue_id := ""
@export var catches: Array[Dictionary] = []
@onready var _bobber := get_node_or_null("Bobber") as Node3D
@onready var _ripple := get_node_or_null("Bobber/Ripple") as Node3D
@onready var _bobber_y := _bobber.position.y if _bobber != null else 0.0
@onready var _ripple_y := _ripple.position.y if _ripple != null else 0.0
var _bobber_phase := ""
var _phase_started := 0.0
var _tug_sound: AudioStreamPlayer


func refresh_runtime_binding() -> void:
	if not catches.is_empty():
		add_to_group("ember_interact")


func prompt() -> String:
	return "Рыбачить"


func activate_from(actor: Node3D) -> String:
	var player := actor as EmberPlayer
	if player == null or not is_instance_valid(player.interaction_ui):
		return "Рыбалка недоступна"
	return player.interaction_ui.open_fishing(self)


func show_bobber(phase: String, elapsed: float) -> void:
	if phase != _bobber_phase:
		_bobber_phase = phase
		_phase_started = elapsed
		if phase == "tug":
			_play_tug_sound()
		elif phase.is_empty() and is_instance_valid(_tug_sound):
			_tug_sound.stop()
	if _bobber == null:
		return
	_bobber.visible = not phase.is_empty()
	if not _bobber.visible:
		return
	var age := elapsed - _phase_started
	var shaking := phase in ["warning", "tug"]
	var offset := sin(elapsed * 5.0) * 0.2
	if phase == "warning":
		offset = sin(age * 30.0) * 0.8
	if phase == "tug":
		offset = -3.0 * exp(-age * 8.0) - 1.7 * pow(maxf(0.0, sin(age * 26.0)), 3.0)
	_bobber.position.y = _bobber_y + offset
	if _ripple != null:
		_ripple.visible = shaking
		_ripple.position.y = _ripple_y - offset
		_ripple.scale = Vector3.ONE * (1.0 + clampf(age * 2.2, 0.0, 1.2))


func _play_tug_sound() -> void:
	if not is_instance_valid(_tug_sound):
		_tug_sound = AudioStreamPlayer.new()
		_tug_sound.name = "TugSound"
		_tug_sound.stream = _make_tug_sound()
		_tug_sound.volume_db = -9.0
		add_child(_tug_sound)
	_tug_sound.play()


func _make_tug_sound() -> AudioStreamWAV:
	# A short splash with a bright attack. Separate RNG keeps loot rolls independent.
	const RATE := 16000
	const SAMPLES := 2400
	var rng := RandomNumberGenerator.new()
	rng.seed = 94823
	var data := PackedByteArray()
	data.resize(SAMPLES * 2)
	var smooth_noise := 0.0
	for index in SAMPLES:
		var time := float(index) / RATE
		smooth_noise = lerpf(smooth_noise, rng.randf_range(-1.0, 1.0), 0.35)
		var attack := minf(time * 320.0, 1.0)
		var envelope := attack * pow(1.0 - float(index) / SAMPLES, 2.5)
		var pitch := sin(TAU * (760.0 * time - 950.0 * time * time))
		data.encode_s16(index * 2, int((smooth_noise * 0.70 + pitch * 0.22) * envelope * 24000.0))
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = RATE
	clip.data = data
	return clip


func roll_catch() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var weights := PackedFloat32Array()
	for entry in catches:
		var id := str(entry.get("itemId", ""))
		var weight := float(entry.get("weight", 0))
		var calm := float(entry.get("calm", 0))
		var tug := float(entry.get("tug", 0))
		var chance := float(entry.get("bonusChance", 0))
		var bonus := str(entry.get("bonusItemId", ""))
		if EmberItemCatalog.definition(id).is_empty() or not is_finite(weight) or weight <= 0:
			continue
		if not is_finite(calm) or calm < 0.6 or not is_finite(tug) or tug < 0.2:
			continue
		if not is_finite(chance) or chance < 0 or chance > 1 or (chance > 0 and EmberItemCatalog.definition(bonus).is_empty()):
			continue
		candidates.append(entry)
		weights.append(weight)
	if candidates.is_empty():
		return {}
	return candidates[RandomNumberGenerator.new().rand_weighted(weights)]
