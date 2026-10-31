@tool
extends Resource
## Authoring intentions stored in the map's scene metadata. Applied terrain
## remains owned by EmberTerrainPilotResource; gameplay never runs this plan.
const Math = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Influence = preload("res://scripts/prototypes/ember_terrain_plan_math.gd")
const META := &"_ember_terrain_plan"
const VERSION := 12
const GROVE_MEMBER_META := &"_ember_grove_member"
const GROVE_GROUP_META := &"_ember_grove_group"
const MAX_GROVE_MEMBERS := 256
const MEMBERS_PER_SECTION:=64
const SECTION_M:=Influence.Sections.CELLS/16
const MAX_WORLD_M:=Influence.MAX_WORLD_M

static func region_member_limit(bounds:Rect2i)->int:
	return maxi(1,ceili(float(bounds.size.x*bounds.size.y)/(SECTION_M*SECTION_M)))*MEMBERS_PER_SECTION

func member_limit(extent:=Vector2i.ZERO)->int:
	# With no map attached (read/save), derive the envelope from existing regions.
	if extent==Vector2i.ZERO:
		for region:Dictionary in regions:
			if region.get("bounds") is Rect2i:extent=extent.max(region.bounds.end)
	extent=extent.clamp(Vector2i.ZERO,Vector2i.ONE*MAX_WORLD_M)
	return maxi(MAX_GROVE_MEMBERS,ceili(float(extent.x)/SECTION_M)*ceili(float(extent.y)/SECTION_M)*MEMBERS_PER_SECTION)
const MAX_REGIONS := 256
@export var schema_version := 1 # Older scenes omitted the default v1 value.
@export var regions: Array[Dictionary] = []
@export_storage var patches: Array[Dictionary] = [] # Local editor provenance, stripped at export.
@export_storage var object_layers: Dictionary = {} # IDs/protection only; scene instances own geometry.
@export_storage var paint_locks: Dictionary = {} # Sparse 64x64-cell bitmaps; editor-only manual paint protection.
const PAINT_TILE := 64
const PAINT_BYTES := 512
const MAX_PATCHES := 256
const PATCH_CHANNELS := {"before": TYPE_PACKED_INT32_ARRAY, "after": TYPE_PACKED_INT32_ARRAY,
	"before_caps": TYPE_PACKED_BYTE_ARRAY, "after_caps": TYPE_PACKED_BYTE_ARRAY,
	"tops": TYPE_PACKED_BYTE_ARRAY, "bases": TYPE_PACKED_BYTE_ARRAY,
	"waters": TYPE_PACKED_INT32_ARRAY, "colors": TYPE_PACKED_BYTE_ARRAY,
	"affected": TYPE_PACKED_BYTE_ARRAY, "protected": TYPE_PACKED_BYTE_ARRAY,
	"before_tops": TYPE_PACKED_BYTE_ARRAY, "before_bases": TYPE_PACKED_BYTE_ARRAY,
	"before_waters": TYPE_PACKED_INT32_ARRAY, "before_colors": TYPE_PACKED_BYTE_ARRAY}
const V3_CHANNELS := ["before_tops","before_bases","before_waters","before_colors"]

static func read(node: Node) -> Variant:
	return node.get_meta(META) if is_instance_valid(node) and node.has_meta(META) else null

static func storage_path(scene_path:String,map_path:String)->String:
	# One existing Plan Resource per scene/Map. A Save As gets its own file,
	# so editing a temporary map copy cannot overwrite the author's plan.
	return scene_path.get_basename()+"_"+map_path.replace("/","_").validate_filename()+"_plan.res"

func working_copy() -> Resource:
	var result := get_script().new() as Resource
	result.schema_version = schema_version
	result.regions.assign(regions.duplicate(true))
	result.patches.assign(patches.duplicate(true))
	result.object_layers = object_layers.duplicate(true)
	result.paint_locks = paint_locks.duplicate(true)
	return result

func data() -> Dictionary: return {"version": schema_version, "regions": regions.duplicate(true), "patches": patches.duplicate(true), "object_layers":object_layers.duplicate(true),"paint_locks":paint_locks.duplicate(true)}

static func from_data(value: Variant) -> Resource:
	if not value is Dictionary or value.get("version") not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, VERSION] or not value.get("regions") is Array or not value.get("patches", []) is Array or not value.get("object_layers",{}) is Dictionary or not value.get("paint_locks",{}) is Dictionary: return null
	for region in value.regions:
		if not region is Dictionary: return null
	var result := load("res://scripts/ember_terrain_plan_resource.gd").new() as Resource
	result.schema_version = value.version
	result.regions.assign(value.regions.duplicate(true))
	for patch in value.get("patches", []):
		if not patch is Dictionary: return null
	result.patches.assign(value.get("patches", []).duplicate(true))
	result.object_layers = value.get("object_layers",{}).duplicate(true)
	result.paint_locks = value.get("paint_locks",{}).duplicate(true)
	return result if result.validation_errors().is_empty() else null

static func same(a: Variant, b: Variant) -> bool:
	if a == null or b == null: return a == b
	if a == b: return true
	return a is Resource and b is Resource and a.get_script() == b.get_script() and a.has_method("data") and a.data() == b.data()

func validation_errors(extent := Vector2i.ZERO) -> Array[String]:
	var errors: Array[String] = []
	if schema_version not in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, VERSION]: errors.append("Неподдерживаемая версия плана областей.")
	if not paint_locks.is_empty() and schema_version<10:errors.append("Защита ручной покраски требует план версии 10.")
	var paint_axis:=MAX_WORLD_M*16/PAINT_TILE
	if paint_locks.size()>paint_axis*paint_axis:errors.append("Слишком большой слой защиты покраски.")
	for key in paint_locks:
		if not key is Vector2i or key.x<0 or key.y<0 or key.x>=paint_axis or key.y>=paint_axis or not paint_locks[key] is PackedByteArray or paint_locks[key].size()!=PAINT_BYTES:
			errors.append("Некорректная плитка защиты покраски.");continue
		if extent!=Vector2i.ZERO:
			var tile:=Rect2i(key*PAINT_TILE,Vector2i.ONE*PAINT_TILE)
			if not Rect2i(Vector2i.ZERO,extent*16).encloses(tile):
				for bit in PAINT_TILE*PAINT_TILE:
					if paint_locks[key][bit/8]&(1<<(bit%8)) and not Rect2i(Vector2i.ZERO,extent*16).has_point(tile.position+Vector2i(bit%PAINT_TILE,bit/PAINT_TILE)):
						errors.append("Защита покраски выходит за границы карты.");break
	if schema_version < 7 and not object_layers.is_empty(): errors.append("Рощи требуют план версии 7.")
	if schema_version == 1 and not patches.is_empty(): errors.append("Локальные слои требуют план версии 2.")
	if regions.size() > MAX_REGIONS: errors.append("Слишком много областей в плане.")
	var ids := {}
	for region in regions:
		if not region.get("id") is String or region.id.is_empty() or ids.has(region.id):
			errors.append("Идентификатор области отсутствует или повторяется."); continue
		ids[region.id] = true
		if not region.get("name") is String or region.name.strip_edges().is_empty() or region.name.length() > 120:
			errors.append("Назовите область: от 1 до 120 символов.")
		var bounds: Variant = region.get("bounds")
		if not bounds is Rect2i or not bounds.has_area() or bounds.position.x < 0 or bounds.position.y < 0 or bounds.end.x > MAX_WORLD_M or bounds.end.y > MAX_WORLD_M:
			errors.append("Границы области должны находиться в пределах карты.")
		elif extent != Vector2i.ZERO and not Rect2i(Vector2i.ZERO, extent).encloses(bounds): errors.append("Область выходит за границу карты.")
		if not region.get("parameters") is Dictionary: errors.append("Нет параметров рельефа области.")
		else:
			var kind: Variant = region.get("kind", "generation")
			if kind not in ["generation", "plateau", "lake", "river", "mountain", "road", "grove", "placement", "coast"]: errors.append("Неизвестный тип области.")
			if region.get("kind", "generation") == "plateau" and schema_version < 2: errors.append("Плато требует план версии 2.")
			if kind == "coast" and schema_version < 12: errors.append("Область моря требует план версии 12.")
			if kind == "lake" and schema_version < 3: errors.append("Озеро требует план версии 3.")
			if kind == "river" and schema_version < 4: errors.append("Русло требует план версии 4.")
			if kind == "mountain" and schema_version < 5: errors.append("Гора требует план версии 5.")
			if kind == "road" and schema_version < 6: errors.append("Дорога требует план версии 6.")
			if kind == "grove" and schema_version < 7: errors.append("Роща требует план версии 7.")
			if kind == "placement" and schema_version < 8: errors.append("Общая расстановка требует план версии 8.")
			if schema_version<11 and region.get("parameters",{}).get("land_shape","island")=="mainland":errors.append("Сплошная суша требует план версии 11.")
			if schema_version<11:
				for key in ["terrain_sampling","mountain_shape","shape_seed"]:
					if region.get("parameters",{}).has(key):errors.append("Точная форма рельефа требует план версии 11.")
			if kind=="generation" and region.get("parameters",{}).has("terrain_operation") and schema_version<9:errors.append("Раздельные действия рельефа, фактуры и покрытий требуют план версии 9.")
			if kind=="generation" and region.get("parameters",{}).has("coverage_profile") and schema_version<10:errors.append("Крупные зоны покрытий требуют план версии 10.")
			if kind=="generation" and schema_version<10:
				for key in Math.ZONE_DEFAULTS:
					if key!="coverage_profile" and region.parameters.has(key):errors.append("Настройки крупных зон требуют план версии 10.");break
			if typeof(region.get("enabled", true)) != TYPE_BOOL: errors.append("Некорректное включение области.")
			var error := Influence.parameter_error(region.parameters,kind) if kind in ["plateau","lake","river","mountain","road","grove","placement","coast"] else Math.parameter_error(region.parameters)
			if not error.is_empty(): errors.append(error)
			elif kind=="generation" and bounds is Rect2i:
				error=Math.surface_bounds_error(bounds,region.parameters)
				if not error.is_empty():errors.append(error)
			elif kind == "lake" and bounds is Rect2i:
				error = Influence.lake_bounds_error(bounds,region.parameters)
				if not error.is_empty(): errors.append(error)
			elif kind == "mountain" and bounds is Rect2i:
				error = Influence.mountain_bounds_error(bounds,region.parameters)
				if not error.is_empty(): errors.append(error)
			if kind in ["river","road","coast"]:
				error = Influence.path_error(region.get("points_m"),extent)
				if not error.is_empty(): errors.append(error)
				elif bounds is Rect2i:
					for point in region.points_m:
						if not Rect2(bounds).has_point(point): errors.append("Границы не охватывают линию."); break
	if patches.size() > MAX_PATCHES: errors.append("Слишком большой локальный слой; уменьшите области.")
	var count := 0; var placement_ids := {}
	for region_id in object_layers:
		var members: Variant = object_layers[region_id]
		if not region_id is String or region_id.is_empty() or not members is Array: errors.append("Повреждён список деревьев рощи."); continue
		var slots := {}
		for member in members:
			count += 1
			if not member is Dictionary or not member.get("id") is String or member.id.is_empty() or placement_ids.has(member.id) or not member.get("slot") is String or slots.has(member.slot) or not member.get("expected") is Dictionary or typeof(member.get("protected",false)) != TYPE_BOOL:
				errors.append("Повреждён экземпляр рощи."); continue
			placement_ids[member.id] = true; slots[member.slot] = true
			var expected: Dictionary = member.expected
			if typeof(expected.get("signature_version",1))!=TYPE_INT or expected.get("signature_version",1) not in [1,2]:errors.append("Неизвестная версия исходного следа объекта.")
			if not expected.get("transform") is Transform3D or not expected.transform.is_finite() or not expected.get("signature") is String or not expected.get("parent") is String or not expected.get("name") is String:
				errors.append("Повреждён исходный след дерева.")
	if count > member_limit(extent): errors.append("Превышен бюджет расстановки созданной карты: %d объектов."%member_limit(extent))
	var seen := {}
	for patch in patches:
		var rect: Variant = patch.get("rect")
		if not rect is Rect2i or not rect.has_area() or rect.size.x > 64 or rect.size.y > 64 or rect.position.x < 0 or rect.position.y < 0 or rect.end.x > MAX_WORLD_M*16 or rect.end.y > MAX_WORLD_M*16:
			errors.append("Повреждены границы локального слоя."); continue
		if seen.has(rect.position): errors.append("Локальный слой повторяется.")
		if rect.position.x % 64 != 0 or rect.position.y % 64 != 0: errors.append("Локальный слой не выровнен по сетке.")
		seen[rect.position] = true
		if extent != Vector2i.ZERO and not Rect2i(Vector2i.ZERO, extent * 16).encloses(rect): errors.append("Локальный слой выходит за карту.")
		for channel in PATCH_CHANNELS:
			if schema_version < 3 and channel in V3_CHANNELS: continue
			if typeof(patch.get(channel)) != PATCH_CHANNELS[channel] or patch[channel].size() != rect.size.x * rect.size.y:
				errors.append("Повреждены данные локального слоя."); break
		if not patch.get("sides", {}) is Dictionary: errors.append("Повреждены покрытия локального слоя.")
		for name in ["sides","before_sides"]:
			if not patch.get(name,{}) is Dictionary: continue
			for key in patch.get(name,{}):
				if typeof(key) != TYPE_INT or key < 0 or key >= rect.size.x*rect.size.y or not patch[name][key] is Dictionary:
					errors.append("Повреждены записи покрытия локального слоя."); break
		if schema_version >= 3:
			if not patch.get("before_sides", {}) is Dictionary or not patch.get("flows", {}) is Dictionary or (schema_version >= 4 and not patch.get("before_flows") is Dictionary):
				errors.append("Повреждены исходные покрытия или течение локального слоя.")
			else:
				if schema_version >= 4:
					if patch.before_flows.size() != patch.flows.size(): errors.append("Повреждён исходный след течения.")
					for key in patch.flows:
						if not patch.before_flows.has(key): errors.append("Нет исходного течения блока."); break
				for channel in ["flows","before_flows"]:
					for key in patch.get(channel, {}):
						var flow: Variant = patch[channel][key]
						if not key is Vector2i or not rect.has_point(key*16) or not flow is Vector2 or not is_finite(flow.x) or not is_finite(flow.y) or flow.length_squared() > 1.0001:
							errors.append("Повреждено течение локального слоя."); break
	return errors

func index_of(id: String) -> int:
	for i in regions.size():
		if regions[i].get("id") == id: return i
	return -1

func overlaps(id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var index := index_of(id)
	if index < 0: return result
	for region in regions:
		if region.id != id and regions[index].bounds.intersects(region.bounds): result.append(region.name)
	return result

func translated(offset_m: Vector2i) -> Resource:
	var result := working_copy()
	result.paint_locks={}
	var shifted_locks: Dictionary={}
	for key: Vector2i in paint_locks:
		var mask: PackedByteArray=paint_locks[key]
		for bit in PAINT_TILE*PAINT_TILE:
			if mask[bit/8]&(1<<(bit%8)):_write_paint_lock(shifted_locks,key*PAINT_TILE+Vector2i(bit%PAINT_TILE,bit/PAINT_TILE)+offset_m*16,true)
	result.paint_locks=shifted_locks
	for region: Dictionary in result.regions:
		region.bounds = Rect2i(region.bounds.position + offset_m, region.bounds.size)
		if region.get("kind") in ["river","road","coast"]:
			var shifted_points := PackedVector2Array()
			for point in region.points_m: shifted_points.append(point+Vector2(offset_m))
			region.points_m = shifted_points
	for patch: Dictionary in result.patches:
		patch.rect = Rect2i(patch.rect.position + offset_m * 16, patch.rect.size)
		for channel in ["flows","before_flows"]:
			var shifted := {}
			for key in patch.get(channel,{}): shifted[key+offset_m] = patch[channel][key]
			if patch.has(channel): patch[channel] = shifted
	for members in result.object_layers.values():
		for member: Dictionary in members:
			var transform: Transform3D = member.expected.transform
			transform.origin += Vector3(offset_m.x*16,0,offset_m.y*16)
			member.expected.transform = transform
	return result

static func paint_locked(locks: Dictionary,cell: Vector2i) -> bool:
	var key:=Vector2i(cell.x/PAINT_TILE,cell.y/PAINT_TILE)
	if not locks.has(key):return false
	var bit:=posmod(cell.x,PAINT_TILE)+posmod(cell.y,PAINT_TILE)*PAINT_TILE
	return bool(locks[key][bit/8]&(1<<(bit%8)))

static func _write_paint_lock(cache: Dictionary,cell: Vector2i,locked: bool) -> void:
	var key:=Vector2i(cell.x/PAINT_TILE,cell.y/PAINT_TILE)
	var mask: PackedByteArray=cache.get(key,PackedByteArray())
	if mask.is_empty():mask.resize(PAINT_BYTES)
	var bit:=posmod(cell.x,PAINT_TILE)+posmod(cell.y,PAINT_TILE)*PAINT_TILE
	mask[bit/8]=(mask[bit/8]|(1<<(bit%8))) if locked else (mask[bit/8]&~(1<<(bit%8)))
	cache[key]=mask

func protect_paint_columns(indices: PackedInt32Array,width: int) -> void:
	upgrade_local_layers()
	var cache:=paint_locks.duplicate(true)
	for index in indices:_write_paint_lock(cache,Vector2i(index%width,index/width),true)
	paint_locks=cache

func protect_paint_area(bounds: Rect2i,locked: bool) -> void:
	upgrade_local_layers()
	var cache:=paint_locks.duplicate(true)
	for z in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):_write_paint_lock(cache,Vector2i(x,z),locked)
	for key in cache.keys():
		var empty:=true
		for value in cache[key]:
			if value!=0:empty=false;break
		if empty:cache.erase(key)
	paint_locks=cache

func upgrade_local_layers() -> void:
	# Called on a private authoring copy for an explicit edit, never on open.
	if schema_version >= VERSION: return
	for patch: Dictionary in patches:
		if schema_version < 3:
			for pair in [["before_tops","tops"],["before_bases","bases"],["before_waters","waters"],["before_colors","colors"]]:
				patch[pair[0]] = patch[pair[1]].duplicate()
			patch.before_sides = patch.get("sides",{}).duplicate(true)
			patch.flows = {}
		if schema_version < 4: patch.before_flows = patch.get("flows",{}).duplicate(true)
	schema_version = VERSION
