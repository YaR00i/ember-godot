extends RefCounted
## Value adapter only: same world identity in the existing battle units/holds.
static func unit(body: Node3D,cell: Vector2i) -> Dictionary:
	return {"id":"world_item:"+body.pickup_id,"name":"Ящик · "+("разрушаемый" if body.breakable else "прочный"),
		"team":"object","hp":1,"maxHp":1,"mp":0,"maxMp":0,"speed":1,"nextAt":0.0,
		"statuses":{},"actions":[],"resistances":{},"statusResistances":{},"cell":cell,
		"weightClass":1 if body.carryable else 99,"move":0,
		"worldItemId":body.pickup_id,"worldItemBreakable":body.breakable,"worldItemMass":body.mass,
		"worldItemSize":body.visual_size,"worldItemDamage":body.throw_damage,
		"worldItemScene":str(EmberItemCatalog.definition(body.item_id).get("worldScene","")),
		"worldItemBreakEffect":body.break_effect.resource_path if body.break_effect!=null else ""}

static func install(state: Dictionary,snapshot: Dictionary) -> Dictionary:
	var result:=state.duplicate(true)
	for id in snapshot.get("units",{}):result.units[id]=snapshot.units[id].duplicate(true)
	for carrier in snapshot.get("holds",{}):
		if result.units.has(carrier):
			var id: String=snapshot.holds[carrier]
			result.holds[carrier]=id;result.units[id].erase("cell")
	return result
