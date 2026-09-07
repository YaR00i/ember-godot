@tool
class_name EmberShopStore
extends RefCounted
## Validation/writer boundary for Godot-native shops. Legacy catalog entries are
## never edited; an explicit migration creates the native override first.

const Catalog = preload("res://scripts/ember_shop_catalog.gd")


static func document(shop_id: String) -> Dictionary:
	return Catalog.definition(shop_id)


static func owner(shop_id: String) -> String:
	return Catalog.owner(shop_id)


static func source_path(shop_id: String) -> String:
	return (
		Catalog.native_path(shop_id)
		if owner(shop_id) == "native"
		else EmberPack.shop_catalog_path()
	)


static func ids() -> Array[String]:
	return Catalog.ids()


static func exists(shop_id: String) -> bool:
	return not Catalog.owner(shop_id).is_empty()


static func suggested_id(source: String) -> String:
	var clean := source.strip_edges().to_lower()
	var expression := RegEx.new()
	expression.compile("[^a-z0-9_-]+")
	clean = expression.sub(clean, "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	return "%s_shop" % (clean if not clean.is_empty() else "new")


static func normalized_document(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	result["id"] = str(raw.get("id", "")).strip_edges()
	result["nameRu"] = str(raw.get("nameRu", "")).strip_edges()
	var listings: Array[Dictionary] = []
	var raw_listings: Variant = raw.get("listings", [])
	if typeof(raw_listings) == TYPE_ARRAY:
		for raw_listing in raw_listings:
			if typeof(raw_listing) != TYPE_DICTIONARY:
				continue
			var listing: Dictionary = (raw_listing as Dictionary).duplicate(true)
			listing["itemId"] = str(listing.get("itemId", "")).strip_edges()
			listing["buyPrice"] = maxi(0, roundi(float(listing.get("buyPrice", 0))))
			listing["sellPrice"] = maxi(0, roundi(float(listing.get("sellPrice", 0))))
			if listing.has("stock"):
				listing["stock"] = maxi(0, roundi(float(listing.get("stock", 0))))
			listings.append(listing)
	result["listings"] = listings
	return result


static func validation_errors(raw: Dictionary) -> Array[String]:
	var value := normalized_document(raw)
	var errors: Array[String] = []
	if not _valid_id(str(value.get("id", ""))):
		errors.append("ID: только a-z, 0-9, _ и -, первый символ — буква или цифра.")
	if str(value.get("nameRu", "")).is_empty():
		errors.append("Укажите название магазина.")
	var listings: Array = value.get("listings", [])
	if listings.is_empty():
		errors.append("Добавьте хотя бы один товар.")
	var used := {}
	var known_items := EmberInteractionContent.item_ids()
	for index in listings.size():
		var listing: Dictionary = listings[index]
		var item_id := str(listing.get("itemId", ""))
		if item_id.is_empty() or item_id not in known_items:
			errors.append("Товар %d: выберите существующий предмет." % (index + 1))
		elif used.has(item_id):
			errors.append("Товар %d: предмет %s уже добавлен." % [index + 1, item_id])
		used[item_id] = true
	return errors


static func write_document(raw: Dictionary) -> int:
	var value := normalized_document(raw)
	var errors := validation_errors(value)
	if not errors.is_empty():
		push_error("Ember shop: %s" % " ".join(errors))
		return ERR_INVALID_DATA
	if owner(str(value.get("id", ""))) == "legacy":
		return ERR_UNAUTHORIZED
	return Catalog.write_native(value)


static func migrate_to_native(shop_id: String) -> int:
	if owner(shop_id) != "legacy":
		return ERR_ALREADY_EXISTS
	var current := document(shop_id)
	return ERR_DOES_NOT_EXIST if current.is_empty() else Catalog.write_native(current)


static func snapshot(shop_id: String) -> Dictionary:
	return Catalog.snapshot(shop_id)


static func restore_snapshot(snapshot_value: Dictionary) -> int:
	return Catalog.restore(snapshot_value)


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(value) != null
