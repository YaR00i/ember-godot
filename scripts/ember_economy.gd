class_name EmberEconomy
extends RefCounted
## Pure buy/sell math for the existing JOI items + shops contract.
## Runtime state, UI and disk persistence stay with their dedicated owners.

const WALLET_ITEM_ID := "coin"


static func compact_counts(raw: Variant) -> Dictionary:
	var result := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for raw_id in raw:
		var item_id := str(raw_id).strip_edges()
		var value: Variant = raw[raw_id]
		if item_id.is_empty() or (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT):
			continue
		var count := roundi(float(value))
		if count > 0:
			result[item_id] = count
	return result


static func normalize_stock_counts(raw: Variant) -> Dictionary:
	var result := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for raw_id in raw:
		var item_id := str(raw_id).strip_edges()
		var value: Variant = raw[raw_id]
		if item_id.is_empty() or (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT):
			continue
		result[item_id] = maxi(0, roundi(float(value)))
	return result


static func seed_shop_remaining(shop: Dictionary) -> Dictionary:
	var result := {}
	var listings: Variant = shop.get("listings", [])
	if typeof(listings) != TYPE_ARRAY:
		return result
	for raw_listing in listings:
		if typeof(raw_listing) != TYPE_DICTIONARY:
			continue
		var listing: Dictionary = raw_listing
		var item_id := str(listing.get("itemId", "")).strip_edges()
		if not item_id.is_empty() and listing.has("stock"):
			result[item_id] = maxi(0, roundi(float(listing.get("stock", 0))))
	return result


static func wallet_count(inventory: Dictionary) -> int:
	return maxi(0, int(inventory.get(WALLET_ITEM_ID, 0)))


static func grant_items(
	inventory: Dictionary,
	item_ids: Array,
	items: Dictionary,
) -> Dictionary:
	var result := compact_counts(inventory)
	for raw_id in item_ids:
		var item_id := str(raw_id).strip_edges()
		if item_id.is_empty():
			continue
		var item: Dictionary = items.get(item_id, {})
		var stack_max := maxi(1, int(item.get("stackMax", 99)))
		result[item_id] = mini(stack_max, int(result.get(item_id, 0)) + 1)
	return compact_counts(result)


static func remaining_stock(shop: Dictionary, remaining: Dictionary, item_id: String) -> Variant:
	var listing := _listing(shop, item_id)
	if listing.is_empty():
		return 0
	if not listing.has("stock"):
		return null
	if remaining.has(item_id):
		return maxi(0, int(remaining[item_id]))
	return maxi(0, int(listing.get("stock", 0)))


static func listing_sell_price(listing: Dictionary) -> int:
	if listing.has("sellPrice"):
		return maxi(0, roundi(float(listing.get("sellPrice", 0))))
	return maxi(0, floori(float(listing.get("buyPrice", 0)) / 2.0))


static func resolve_sell_price(
	item_id: String,
	shop: Dictionary,
	items: Dictionary,
) -> Variant:
	if item_id == WALLET_ITEM_ID:
		return null
	var item: Dictionary = items.get(item_id, {})
	if bool(item.get("unsellable", false)):
		return null
	var listing := _listing(shop, item_id)
	if not listing.is_empty():
		return listing_sell_price(listing)
	if item.has("sellPrice"):
		return maxi(0, roundi(float(item.get("sellPrice", 0))))
	return null


static func buy(
	shop: Dictionary,
	item_id: String,
	inventory: Dictionary,
	remaining: Dictionary,
	items: Dictionary,
) -> Dictionary:
	var next_inventory := compact_counts(inventory)
	var next_remaining := normalize_stock_counts(remaining)
	if shop.is_empty():
		return _failure("unknown_shop", next_inventory, next_remaining)
	var listing := _listing(shop, item_id)
	if listing.is_empty():
		return _failure("unknown_item", next_inventory, next_remaining)
	var left: Variant = remaining_stock(shop, next_remaining, item_id)
	if left != null and int(left) <= 0:
		return _failure("out_of_stock", next_inventory, next_remaining)
	var price := maxi(0, roundi(float(listing.get("buyPrice", 0))))
	if wallet_count(next_inventory) < price:
		return _failure("broke", next_inventory, next_remaining)
	var item: Dictionary = items.get(item_id, {})
	var stack_max := maxi(1, int(item.get("stackMax", 99)))
	_set_count(next_inventory, WALLET_ITEM_ID, wallet_count(next_inventory) - price)
	next_inventory[item_id] = mini(stack_max, int(next_inventory.get(item_id, 0)) + 1)
	if left != null:
		next_remaining[item_id] = int(left) - 1
	return {
		"ok": true,
		"shopId": str(shop.get("id", "")),
		"itemId": item_id,
		"inventory": compact_counts(next_inventory),
		"remaining": normalize_stock_counts(next_remaining),
	}


static func sell(
	shop: Dictionary,
	item_id: String,
	inventory: Dictionary,
	remaining: Dictionary,
	items: Dictionary,
) -> Dictionary:
	var next_inventory := compact_counts(inventory)
	var next_remaining := normalize_stock_counts(remaining)
	if shop.is_empty():
		return _failure("unknown_shop", next_inventory, next_remaining)
	if item_id == WALLET_ITEM_ID:
		return _failure("unknown_item", next_inventory, next_remaining)
	var item: Dictionary = items.get(item_id, {})
	if bool(item.get("unsellable", false)):
		return _failure("unsellable", next_inventory, next_remaining)
	var price: Variant = resolve_sell_price(item_id, shop, items)
	if price == null:
		return _failure("unknown_item", next_inventory, next_remaining)
	var count := int(next_inventory.get(item_id, 0))
	if count <= 0:
		return _failure("nothing_to_sell", next_inventory, next_remaining)
	_set_count(next_inventory, item_id, count - 1)
	var listing := _listing(shop, item_id)
	if not listing.is_empty() and listing.has("stock"):
		var left: Variant = remaining_stock(shop, next_remaining, item_id)
		next_remaining[item_id] = int(left) + 1
	var coin_def: Dictionary = items.get(WALLET_ITEM_ID, {})
	var coin_max := maxi(1, int(coin_def.get("stackMax", 99)))
	next_inventory[WALLET_ITEM_ID] = mini(
		coin_max,
		wallet_count(next_inventory) + int(price),
	)
	return {
		"ok": true,
		"shopId": str(shop.get("id", "")),
		"itemId": item_id,
		"inventory": compact_counts(next_inventory),
		"remaining": normalize_stock_counts(next_remaining),
	}


static func listing_views(
	shop: Dictionary,
	remaining: Dictionary,
	items: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var listings: Variant = shop.get("listings", [])
	if typeof(listings) != TYPE_ARRAY:
		return result
	for raw_listing in listings:
		if typeof(raw_listing) != TYPE_DICTIONARY:
			continue
		var listing: Dictionary = raw_listing
		var item_id := str(listing.get("itemId", ""))
		var item: Dictionary = items.get(item_id, {})
		result.append({
			"itemId": item_id,
			"nameRu": str(item.get("nameRu", item.get("name", item_id))),
			"buyPrice": maxi(0, int(listing.get("buyPrice", 0))),
			"sellPrice": listing_sell_price(listing),
			"stock": remaining_stock(shop, remaining, item_id),
		})
	return result


static func sellable_views(
	shop: Dictionary,
	inventory: Dictionary,
	items: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_id in inventory:
		var item_id := str(raw_id)
		var count := int(inventory[raw_id])
		if count <= 0:
			continue
		var price: Variant = resolve_sell_price(item_id, shop, items)
		if price == null:
			continue
		var item: Dictionary = items.get(item_id, {})
		result.append({
			"itemId": item_id,
			"nameRu": str(item.get("nameRu", item.get("name", item_id))),
			"count": count,
			"sellPrice": int(price),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("nameRu", "")) < str(b.get("nameRu", ""))
	)
	return result


static func _listing(shop: Dictionary, item_id: String) -> Dictionary:
	var listings: Variant = shop.get("listings", [])
	if typeof(listings) != TYPE_ARRAY:
		return {}
	for raw_listing in listings:
		if typeof(raw_listing) == TYPE_DICTIONARY and str(raw_listing.get("itemId", "")) == item_id:
			return raw_listing
	return {}


static func _set_count(counts: Dictionary, item_id: String, value: int) -> void:
	if value > 0:
		counts[item_id] = value
	else:
		counts.erase(item_id)


static func _failure(reason: String, inventory: Dictionary, remaining: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"inventory": inventory,
		"remaining": remaining,
	}
