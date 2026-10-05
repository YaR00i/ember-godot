@tool
extends RefCounted
## Deterministic map-coordinate terrain sampling. No scene, storage or UI access.
## Slope-aware ridges are an approximation inspired by de Carpentier's Swiss
## turbulence, not the proprietary NMS generator or hydraulic erosion.

const PROFILES := ["hills", "ridges", "eroded"]
const DEFAULTS := {"profile": "hills", "seed": 7, "sea_m": 2.0, "land_m": 2.0,
	"relief_m": 6.0, "feature_m": 18.0, "shore_m": 5.0, "land_fraction": 0.72}

var parameters: Dictionary
var area_m: Rect2
var _coast: FastNoiseLite
var _terrain: FastNoiseLite
var _detail: FastNoiseLite


static func parameter_error(values: Dictionary) -> String:
	if values.get("profile", "") not in PROFILES: return "Выберите рисунок рельефа."
	if typeof(values.get("seed")) != TYPE_INT: return "Номер рисунка должен быть целым."
	var limits := {"sea_m": Vector2(0.5, 16), "land_m": Vector2(0.25, 8),
		"relief_m": Vector2(0, 24), "feature_m": Vector2(2, 96),
		"shore_m": Vector2(0.5, 24), "land_fraction": Vector2(0.3, 0.9)}
	for key in limits:
		var value = values.get(key)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
			return "Параметр %s должен быть конечным числом." % key
		var range_value: Vector2 = limits[key]
		if value < range_value.x or value > range_value.y: return "Параметр %s вне допустимого диапазона." % key
	return ""


func configure(bounds_m: Rect2, values: Dictionary) -> void:
	area_m = bounds_m
	parameters = values.duplicate(true)
	_coast = _noise(int(values.seed) + 101, 2)
	_terrain = _noise(int(values.seed) + 1009, 3 if values.profile == "hills" else 1)
	_detail = _noise(int(values.seed) + 2003, 2)


func _noise(seed_value: int, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	return noise


func configure_legacy_coast(depth_cells: int, land_height: int, water_height: int, relief_cells: int, seed_value: int) -> void:
	# Compatibility recipe for the existing +Map coast preset. Keep its field,
	# rounding and initial materials intact while sharing the sampling owner.
	parameters = {"depth": depth_cells, "land": land_height, "water": water_height,
		"relief": relief_cells, "coast_range": minf(160.0, float(depth_cells) * 0.12)}
	_coast = _noise(seed_value, 2)
	_coast.frequency = 1.0 / 360.0
	_terrain = _noise(seed_value + 1009, 2)
	_terrain.frequency = 1.0 / 192.0


func legacy_coast_height(point_cells: Vector2, height_limit: int) -> int:
	var shoreline := float(parameters.depth) * 0.42 + _coast.get_noise_2d(point_cells.x, 0.0) * float(parameters.coast_range)
	var blend := clampf((point_cells.y - shoreline + 64.0) / 128.0, 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	var rolling := _terrain.get_noise_2dv(point_cells) * float(parameters.relief) * blend
	var raw := lerpf(float(parameters.water - 8), float(parameters.land), blend) + rolling
	return clampi(roundi(raw / 4.0) * 4, 4, height_limit)


func height_m(point_m: Vector2) -> float:
	var feature := float(parameters.feature_m)
	var radius := area_m.size * (0.5 * float(parameters.land_fraction))
	var relative := (point_m - area_m.get_center()) / radius
	var coast_variation := _coast.get_noise_2dv(point_m / (feature * 1.8)) * 0.12
	var coast_distance := (1.0 - relative.length() - coast_variation) * minf(radius.x, radius.y)
	var shore := float(parameters.shore_m)
	var land_weight := smoothstep(0.0, shore, coast_distance)
	var bottom_weight := smoothstep(-shore, 0.0, coast_distance)
	var bottom_m := minf(2.0, float(parameters.sea_m) - 0.25)
	var form := _landform(point_m / feature)
	return float(parameters.sea_m) - bottom_m * (1.0 - bottom_weight) + land_weight * (
		float(parameters.land_m) + float(parameters.relief_m) * form)


func _landform(point: Vector2) -> float:
	if parameters.profile == "hills":
		return clampf(0.5 + 0.5 * _terrain.get_noise_2dv(point), 0.0, 1.0)
	var sum := 0.0
	var amplitude := 1.0
	var frequency := 1.0
	var normalizer := 0.0
	var warp := Vector2.ZERO
	for octave in 3:
		var at := (point + warp * 0.18) * frequency + Vector2.ONE * float(octave * 17)
		var value := _terrain.get_noise_2dv(at)
		var ridge := 1.0 - absf(value)
		sum += amplitude * ridge * ridge
		normalizer += amplitude
		if parameters.profile == "eroded":
			# Finite differences in noise coordinates keep the sampler independent
			# of terrain resolution and section boundaries.
			var h := 0.15
			var gradient := Vector2(
				_terrain.get_noise_2dv(at + Vector2(h, 0)) - _terrain.get_noise_2dv(at - Vector2(h, 0)),
				_terrain.get_noise_2dv(at + Vector2(0, h)) - _terrain.get_noise_2dv(at - Vector2(0, h))) / (2.0 * h)
			warp += amplitude * gradient * -value
			amplitude *= 0.5 * clampf(sum, 0.15, 1.0)
		else:
			amplitude *= 0.5
		frequency *= 1.92
	var detail := _detail.get_noise_2dv(point * 3.0) * 0.04
	return clampf(sum / normalizer + detail, 0.0, 1.0)
