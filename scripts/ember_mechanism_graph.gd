extends RefCounted
## Pure boolean topology. Scene components own sensing and physical effects.
const LABELS := {"plate": "Нажимная плита", "lever": "Рычаг", "all": "ВСЕ", "any": "ЛЮБОЙ", "not": "НЕ", "door": "Дверь", "lamp": "Лампа", "hold": "Задержка выключения", "latch": "Фиксация сигнала"}
static func inputs(kind: String) -> int:
	return 2 if kind in ["all", "any", "latch"] else 1 if kind in ["not", "door", "lamp", "hold"] else 0
static func output(kind: String) -> bool:
	return kind in ["plate", "lever", "all", "any", "not", "hold", "latch"]
static func input_label(kind: String, port: int) -> String:
	return ("Включить" if port == 0 else "Сброс") if kind == "latch" else "Вход %d" % [port + 1]
static func errors(document: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var nodes: Array = document.get("nodes", [])
	if nodes.size() > 128: result.append("В первой версии допускается до128 компонентов в схеме.")
	var by_id := {}
	for node in nodes:
		var id := str(node.get("id", ""))
		if not id.is_valid_identifier() or by_id.has(id): result.append("У компонентов должны быть разные устойчивые имена.")
		by_id[id] = node
		if not LABELS.has(str(node.get("kind", ""))): result.append("Неизвестный тип компонента.")
		if str(node.get("label", "")).strip_edges().is_empty(): result.append("Дай компоненту понятное название.")
		for field in ["required_weight", "character_weight"]:
			var weight := float(node.get(field, 0.0 if field == "required_weight" else 1.0))
			if not is_finite(weight) or weight < 0.0 or weight > 1000.0: result.append("Вес плиты: число от0 до1000.")
		if str(node.get("kind", "")) == "hold":
			var duration := float(node.get("hold_seconds", 3.0))
			if not is_finite(duration) or duration < 0.05 or duration > 120.0: result.append("Задержка выключения: от0,05 до120 секунд.")
		var at: Vector2 = node.get("position", Vector2.ZERO)
		if not at.is_finite(): result.append("Некорректное положение карточки.")
		if node.has("world_position"):
			var world: Variant = node.world_position
			if not world is Vector3 or not world.is_finite(): result.append("Некорректное положение блока в3D.")
		var offset: Vector3 = node.get("offset", Vector3(0, 40, 0))
		if not offset.is_finite() or not is_finite(float(node.get("seconds", 0.6))) or float(node.get("seconds", 0.6)) < 0.1 or not is_finite(float(node.get("settle", 0.35))) or float(node.get("settle", 0.35)) < 0.0:
			result.append("Проверь время движения, покой и смещение двери.")
	var occupied := {}
	for link in document.get("links", []):
		var source := str(link.get("from", ""))
		var target := str(link.get("to", ""))
		if not by_id.has(source) or not by_id.has(target):
			result.append("У провода отсутствует один из компонентов.")
			continue
		var port := int(link.get("port", -1))
		if not output(str(by_id[source].kind)) or port < 0 or port >= inputs(str(by_id[target].kind)):
			result.append("Этот выход нельзя подключить к выбранному входу.")
		var key := "%s:%d" % [target, port]
		if occupied.has(key): result.append("У входа уже есть провод. Сначала отключи его.")
		occupied[key] = true
	if result.is_empty() and order(document).size() != nodes.size():
		result.append("Получился замкнутый круг сигналов. В первой версии такие связи запрещены.")
	return result
static func order(document: Dictionary) -> Array[String]:
	var pending := {}
	var outgoing := {}
	for node in document.get("nodes", []): pending[str(node.id)] = 0
	for link in document.get("links", []):
		var a := str(link.get("from", "")); var b := str(link.get("to", ""))
		if not pending.has(a) or not pending.has(b): continue
		pending[b] += 1
		if not outgoing.has(a): outgoing[a] = []
		outgoing[a].append(b)
	var queue: Array[String] = []
	for id in pending:
		if pending[id] == 0: queue.append(str(id))
	var result: Array[String] = []
	while not queue.is_empty():
		var id := queue.pop_front() as String
		result.append(id)
		for child in outgoing.get(id, []):
			pending[child] -= 1
			if pending[child] == 0: queue.append(str(child))
	return result
static func evaluate(document: Dictionary, sources: Dictionary) -> Dictionary:
	return advance(document, sources, {}, 0.0).values

static func advance(document: Dictionary, sources: Dictionary, previous_timers: Dictionary, delta: float, previous_latches: Dictionary = {}) -> Dictionary:
	var values := {}
	var timers := {}
	var latches := {}
	if not errors(document).is_empty() or not is_finite(delta) or delta < 0: return {"values": values, "timers": timers, "latches": latches}
	var nodes := {}; var incoming := {}
	for node in document.get("nodes", []): nodes[str(node.id)] = node
	for link in document.get("links", []): incoming["%s:%d" % [link.to, int(link.port)]] = str(link.from)
	for id in order(document):
		var kind := str(nodes[id].kind)
		var key := "%s:0" % id
		var a := bool(values.get(str(incoming.get(key, "")), false))
		var b := bool(values.get(str(incoming.get("%s:1" % id, "")), false))
		match kind:
			"plate", "lever": values[id] = bool(sources.get(id, false))
			"all": values[id] = a and b
			"any": values[id] = a or b
			"not": values[id] = incoming.has(key) and not a
			"hold":
				var left := float(nodes[id].get("hold_seconds", 3.0)) if a else maxf(0.0, float(previous_timers.get(id, 0.0)) - delta)
				if not incoming.has(key) or left < 0.000001: left = 0.0
				timers[id] = left
				values[id] = a or left > 0.0
			"latch":
				values[id] = false if b else a or bool(previous_latches.get(id, false))
				latches[id] = values[id]
			_: values[id] = a
	return {"values": values, "timers": timers, "latches": latches}
