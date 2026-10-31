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
