extends SceneTree
## Bakes palette artwork into separate shared variants; originals stay untouched.

const Pattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const PALETTES := {
	"grass": ["55be2e", "79cf42", "46962d"],
	"soil": ["896847", "a17c54", "705640"],
	"sand": ["dec891", "e8d7a5", "c4ad7d"],
	"stone": ["899298", "a1aaac", "65777e"],
}
const FINISH := {"grass": [0.04, 0.025, 0.22], "soil": [0.02, 0.01, 0.24],
	"sand": [0.06, 0.045, 0.16], "stone": [0.18, 0.12, 0.27]}


func _initialize() -> void:
	for role in PALETTES:
		var pattern := Pattern.new()
		pattern.role_id = role
		pattern.base_color = Color(PALETTES[role][0])
		pattern.light_color = Color(PALETTES[role][1])
		pattern.shadow_color = Color(PALETTES[role][2])
		pattern.gloss = FINISH[role][0]
		pattern.sheen = FINISH[role][1]
		pattern.pixel_relief = FINISH[role][2]
		pattern.pixels = _artwork(role, false)
		pattern.side_pixels = _artwork(role, true)
		assert(pattern.validation_errors().is_empty())
		assert(ResourceSaver.save(pattern, "res://content/terrain_materials/%s_relief.tres" % role) == OK)
	var source := load("res://content/world_terrains/compact_river_water_study.res") as Terrain
	var candidate := source.working_copy()
	if candidate.palette_material_ids.is_empty(): candidate.palette_material_ids.resize(candidate.palette.size())
	for index in candidate.palette_surface_roles.size():
		var role := candidate.palette_surface_roles[index]
		if role in PALETTES: candidate.palette_material_ids[index] = role + "_relief"
	assert(candidate.same_terrain_geometry(source))
	assert(ResourceSaver.save(candidate, "res://content/world_terrains/compact_material_relief_study.res", ResourceSaver.FLAG_COMPRESS) == OK)
	print("PASS material study: four independent variants, authored geometry/flow unchanged")
	quit()


func _artwork(role: String, side: bool) -> PackedByteArray:
	var pixels := PackedByteArray()
	pixels.resize(256)
	var rng := RandomNumberGenerator.new()
	rng.seed = ["grass", "soil", "sand", "stone"].find(role) * 71 + (113 if side else 31)
	if side and role in ["soil", "sand"]:
		# Offset short sediment layers. Base-colour borders keep mirrored joins quiet.
		for band in 5:
			var y := 2 + band * 3
			var start := rng.randi_range(1, 4)
			for x in range(start, rng.randi_range(10, 14)):
				pixels[x + y * 16] = 1 if band % 2 == 0 else 2
				if x > start + 2 and x % 4 == 0: pixels[x + (y - 1) * 16] = pixels[x + y * 16]
	else:
		var count := 14 if role == "grass" else 8 if role == "stone" else 11
		for patch in count:
			var x := rng.randi_range(2, 12)
			var y := rng.randi_range(2, 12)
			var width := rng.randi_range(1, 3)
			var height := rng.randi_range(1, 2) if role == "sand" else rng.randi_range(2, 4)
			if side and role == "grass": width = 1
			for dy in height:
				for dx in width:
					if dx == width - 1 and dy == height - 1: continue
					var px := mini(x + dx + (1 if dy == 0 and height > 2 else 0), 14)
					var py := mini(y + dy, 14)
					pixels[px + py * 16] = 1 if patch % 3 == 0 else 2
			# Small light shoulders give rock clusters a direction, not random speckles.
			if role == "stone": pixels[x + y * 16] = 1
	return pixels
