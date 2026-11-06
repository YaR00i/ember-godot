extends RefCounted
## Pure persistent pickup records. ExploreState owns these records and inventory.

const MAX_RECORDS := 4096

static func normalize(raw: Variant) -> Dictionary:
	var result := {}
	if not raw is Dictionary: return result
	for key in raw:
		if result.size() >= MAX_RECORDS: break
		if not key is String or key.is_empty() or not raw[key] is Dictionary: continue
		var row: Dictionary = raw[key]
		if not row.get("itemId") is String or str(row.itemId).is_empty(): continue
		if not row.get("mapId") is String or str(row.mapId).is_empty(): continue
		var count: Variant = row.get("count")
		if typeof(count) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(count)) or count < 0 or count > 999 or float(count) != floor(float(count)): continue
		if not valid_vector(row.get("position")) or not valid_vector(row.get("rotation")): continue
		result[key] = {"itemId": row.itemId, "mapId": row.mapId, "count": int(count),
			"position": Array(row.position).duplicate(), "rotation": Array(row.rotation).duplicate()}
		var physical := normalized_physical(row.get("physical", {}))
		if not physical.is_empty(): result[key]["physical"] = physical
		var carrier: Variant = row.get("carrierHeroId", "")
		if not physical.is_empty() and physical.carryable and carrier is String and not carrier.is_empty() and carrier.length() <= 64:
			result[key]["carrierHeroId"] = carrier
	return result

static func normalized_physical(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.is_empty(): return {}
	var result := {}
	for key in ["carryable", "pushable", "breakable"]:
		if typeof(raw.get(key)) != TYPE_BOOL: return {}
		result[key] = raw[key]
	var bounds := {"itemMass": [0.05, 1000.0], "visualSize": [1.0, 128.0], "returnRadius": [0.0, 4096.0], "breakImpactSpeed": [1.0, 200.0], "throwDamage": [1.0, 100.0]}
	for key in bounds:
		var value: Variant = raw.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < bounds[key][0] or float(value) > bounds[key][1]: return {}
		if key == "throwDamage" and float(value) != floor(float(value)): return {}
		result[key] = int(value) if key == "throwDamage" else float(value)
	for key in ["availableFlagId", "startQuestId", "breakEffect"]:
		if not raw.get(key, "") is String or str(raw.get(key, "")).length() > 256: return {}
		result[key] = str(raw.get(key, ""))
	var effect: String = result.breakEffect
	if not effect.is_empty() and (not effect.begins_with("res://prefabs/") or effect.get_extension() not in ["scn", "tscn"] or ".." in effect): return {}
	if not valid_vector(raw.get("returnOrigin")): return {}
	result["returnOrigin"] = Array(raw.returnOrigin).duplicate()
	return result

static func valid_vector(raw: Variant) -> bool:
	if not raw is Array or raw.size() != 3: return false
	for value in raw:
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 10000000.0: return false
	return true

static func vector(raw: Array) -> Vector3:
	return Vector3(float(raw[0]),float(raw[1]),float(raw[2]))

static func packed(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
