class_name EmberVnSceneState
extends RefCounted
## Pure presentation projection for the canonical Ember scene JSON.
## Editor preview and runtime session share this owner so stage math cannot drift.

const ACTOR_FLOOR_Y := 96.0


static func visual_state(scene: Dictionary, step: Dictionary) -> Dictionary:
	if step.is_empty():
		return {}
	var kind := str(step.get("type", ""))
	var state := {
		"bgArtId": _background_art_id(scene, step),
		"actors": [],
	}
	for field in ["artId", "speaker", "portraitKey", "portraitSide"]:
		if step.has(field):
			state[field] = step[field]
	# JOI ScenePlayer deliberately keeps talk/shop_intro as text overlays.
	if str(scene.get("use", "cutscene")) != "cutscene":
		state["bgArtId"] = ""
		return state
	match kind:
		"dialogue":
			state["actors"] = dialogue_actors(step)
		"choice":
			state["actors"] = choice_actors(scene, step)
	return state


static func dialogue_actors(step: Dictionary) -> Array:
	var actors := _actor_copy(step.get("actors", []))
	if not actors.is_empty():
		return actors
	var side := str(step.get("portraitSide", "left"))
	return [{
		"id": "main",
		"speaker": str(step.get("speaker", "")),
		"portraitKey": str(step.get("portraitKey", "neutral")),
		"x": 72.0 if side == "right" else 28.0,
		"y": ACTOR_FLOOR_Y,
		"floorY": ACTOR_FLOOR_Y,
		"scale": 1.65,
		"z": 1.0,
		"lockY": true,
	}]


static func choice_actors(scene: Dictionary, step: Dictionary) -> Array:
	var incoming := _incoming_actors(scene, str(step.get("id", "")))
	if not incoming.is_empty():
		return incoming
	return _actor_copy(step.get("actors", []))


static func _background_art_id(scene: Dictionary, step: Dictionary) -> String:
	match str(step.get("type", "")):
		"dialogue", "choice":
			var override_id := str(step.get("bgArtId", "")).strip_edges()
			return override_id if not override_id.is_empty() else str(
				scene.get("defaultBgArtId", "")
			)
		"splash":
			return str(step.get("artId", ""))
	return str(scene.get("defaultBgArtId", ""))


static func _incoming_actors(scene: Dictionary, step_id: String) -> Array:
	var steps: Array = scene.get("steps", []) if typeof(scene.get("steps", [])) == TYPE_ARRAY else []
	for raw_step in steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = raw_step
		if str(candidate.get("type", "")) == "dialogue" and str(candidate.get("next", "")) == step_id:
			return dialogue_actors(candidate)
		if str(candidate.get("type", "")) == "choice":
			for raw_option in candidate.get("options", []):
				if typeof(raw_option) == TYPE_DICTIONARY and str(raw_option.get("next", "")) == step_id:
					var actors := _actor_copy(candidate.get("actors", []))
					if not actors.is_empty():
						return actors
	var target_index := -1
	for index in steps.size():
		if typeof(steps[index]) == TYPE_DICTIONARY and str((steps[index] as Dictionary).get("id", "")) == step_id:
			target_index = index
			break
	for index in range(target_index - 1, -1, -1):
		if typeof(steps[index]) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = steps[index]
		if str(candidate.get("type", "")) == "dialogue":
			return dialogue_actors(candidate)
		if str(candidate.get("type", "")) == "choice":
			var actors := _actor_copy(candidate.get("actors", []))
			if not actors.is_empty():
				return actors
	return []


static func _actor_copy(raw: Variant) -> Array:
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for value in raw:
		if typeof(value) == TYPE_DICTIONARY:
			result.append((value as Dictionary).duplicate(true))
	return result
