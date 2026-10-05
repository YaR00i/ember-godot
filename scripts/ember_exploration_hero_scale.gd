class_name EmberExplorationHeroScale
extends RefCounted
## One authored block is one metre; exploration placeholders share this scale.

const HEIGHT_BLOCKS := {
	"protagonist": 1.8,
	"mira": 1.5,
	"orik": 1.7,
	"sena": 1.7,
}
const RADIUS_BLOCKS := {
	"protagonist": 0.25,
	"mira": 0.26,
	"orik": 0.25,
	"sena": 0.25,
}
const COLLISION_RADIUS_BLOCKS := 2.5 / 16.0


static func height(hero_id: String, block_size: float) -> float:
	return float(HEIGHT_BLOCKS.get(hero_id, 1.7)) * block_size


static func radius(hero_id: String, block_size: float) -> float:
	return float(RADIUS_BLOCKS.get(hero_id, 0.25)) * block_size


static func collision_radius(block_size: float) -> float:
	# Preserve the accepted stepping footprint while taller placeholders are
	# evaluated. Visual width is allowed to be fuller than this test capsule.
	return COLLISION_RADIUS_BLOCKS * block_size
