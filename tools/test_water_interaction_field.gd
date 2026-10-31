extends SceneTree
## One persistent surface equation receives stationary and moving contacts.
const Field = preload("res://scripts/prototypes/ember_compact_wave_obstacles.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); printerr("INTERACTION FAIL ", label)
func energy(field: RefCounted) -> float:
	var total := 0.0
	for p in field.patches:
		for value in p.h: total += absf(value)
	return total
func fixture() -> EmberTerrainPilotResource:
	var document := EmberTerrainPilotResource.new(); document.width = 160; document.depth = 160
	document.palette = PackedColorArray([Color.TRANSPARENT, Color.GRAY, Color.BLUE])
	for key in ["heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials"]:
		var values: Variant = document.get(key); values.resize(160 * 160)
		values.fill(4 if key == "heights" else 12 if key == "water_levels" else 2 if key == "water_materials" else 1)
		document.set(key, values)
	return document
func run() -> void:
	var document := fixture(); var before := document.water_levels.duplicate()
	var shore := Image.create_empty(160, 160, false, Image.FORMAT_R8); shore.fill(Color.WHITE)
	var settings := {"wave_speed": 0.42, "river_speed": 0.0, "wave_height": 0.0, "river_mix": 0.8,
		"spacing": 4.0, "opening": 0.3, "sea_period": 9.0, "sea_height": 0.0, "sea_reach": 10.0}
	var shapes: Array[Dictionary] = [{"kind": "circle", "center": Vector2(80, 80), "radius": 6.0, "velocity": Vector2.ZERO}]
	var field := Field.new(); field.build(document, shapes, null, shore, null, settings, true)
	check(field.ready and not field.cache_hit, "live contact starts without a settling bake")
	field.update_contacts(shapes)
	for i in 80: field.advance(i * 0.05, 2, 1.0)
	check(energy(field) == 0.0, "stationary object in calm water creates no perpetual waves")
	var measured := PackedFloat32Array()
	for i in 60:
		shapes[0].center += Vector2(0.2, 0); shapes[0].velocity = Vector2(4, 0)
		field.update_contacts(shapes); field.advance((80 + i) * 0.05, 2, 1.0)
		measured.append(field.contact_update_us + field.update_us)
	var moving_energy := energy(field)
	check(moving_energy > 0.1, "movement disturbs calm water through the same field")
	var retained := energy(field)
	shapes[0].velocity = Vector2.ZERO; field.update_contacts(shapes)
	check(energy(field) > retained * 0.95, "stopping preserves the propagated wave history")
	for i in 600: field.advance((140 + i) * 0.05, 2, 1.0)
	check(energy(field) < moving_energy * 0.5, "stopped disturbance dissipates")
	settings.wave_height = 2.0
	var incoming := Field.new(); incoming.build(document, shapes, null, shore, null, settings, true); incoming.update_contacts(shapes)
	for i in 200: incoming.advance(i * 0.05, 2, 1.0)
	check(energy(incoming) > 0.1, "incoming waves interact with the same stationary body")
	var prior_energy := energy(incoming)
	shapes[0].center.x += 1.0; incoming.update_contacts(shapes)
	check(energy(incoming) > prior_energy * 0.8, "moving the contour does not reset the whole field")
	var next := Field.new(); next.build(document, shapes, null, shore, null, settings, true); next.inherit_live(incoming)
	check(energy(next) > energy(incoming) * 0.8, "replacement local patch inherits world-space history")
	for p in incoming.patches:
		for value in p.h: check(is_finite(value) and absf(value) < 8.0, "bounded finite surface")
	check(document.water_levels == before, "terrain source is untouched")
	var group: Array[Dictionary] = [{"kind": "circle", "center": Vector2(280, 80), "radius": 17.6},
		{"kind": "circle", "center": Vector2(230, 80), "radius": 4.0}, {"kind": "circle", "center": Vector2(250, 80), "radius": 4.0}]
	for shape in group: shape.center.x -= 140.0
	var grouped := Field.new(); grouped.build(document, group, null, shore, null, settings, true)
	for shape in group: check(grouped.covers_contact(shape), "group placement fits each contact with an absorbing margin")
	var many: Array[Dictionary] = []
	for i in 5: many.append({"kind": "circle", "id": i + 1, "center": Vector2(40 + i * 110, 80), "radius": 4.0})
	var limited := Field.new(); limited.build(document, many, null, shore, null, settings, true)
	check(limited.patches.size() == Field.MAX_PATCHES and limited.accepted_contact_ids.size() == 4 and not limited.accepted_contact_ids.has(5), "explicit contact budget does not pretend to cover an unallocated patch")
	measured.sort()
	print("INTERACTION_FIELD ", JSON.stringify({"pass": failures.is_empty(), "errors": failures, "moving_energy": moving_energy,
		"calm_after_stop": energy(field), "incoming_energy": energy(incoming), "update_p50_ms": measured[measured.size()/2]/1000.0,
		"update_p95_ms": measured[floori(measured.size()*0.95)]/1000.0}))
	quit(0 if failures.is_empty() else 1)
