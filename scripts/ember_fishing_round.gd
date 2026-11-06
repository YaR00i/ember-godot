extends RefCounted
## One transient catch attempt. The interaction UI owns input and reward commit.

const BITE_DELAY := 0.7
const WARNING_TIME := 0.38
const ESCAPE_TIME := 17.0

var species: Dictionary
var elapsed := 0.0
var progress := 0.0


func _init(profile: Dictionary) -> void:
	species = profile.duplicate()


func phase() -> String:
	if elapsed < BITE_DELAY:
		return "wait"
	var calm := float(species.calm)
	var cycle_time := fposmod(elapsed - BITE_DELAY, calm + float(species.tug))
	if cycle_time >= calm:
		return "tug"
	return "warning" if cycle_time >= calm - WARNING_TIME else "reel"


func advance(delta: float, holding: bool) -> String:
	var step := clampf(delta, 0.0, 0.05)
	var current_phase := phase()
	if holding and current_phase != "wait":
		var rate := -0.38 if current_phase == "tug" else 0.20
		progress = clampf(progress + step * rate, 0.0, 1.0)
	elapsed += step
	if progress >= 1.0:
		return "caught"
	return "escaped" if elapsed >= ESCAPE_TIME else ""
