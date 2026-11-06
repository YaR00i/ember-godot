extends SceneTree
## Offline blockout authoring. Saved rooms use the shared exploration/interact owners.
const G = preload("res://tools/chapter1_blockout_geometry.gd")
const Shop = preload("res://scripts/ember_shop_resource.gd")
const Dialogue = preload("res://scripts/ember_dialogue_resource.gd")
var errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_write_content()
	for build in [home, guild, smith, general_store, alchemy, mansion]:
		var scene: Node3D = build.call()
		var error := G.save(scene)
		if error != OK: errors.append("%s: %s" % [scene.name, error_string(error)])
		else: print("SAVED ", scene.name)
		scene.free()
	if not errors.is_empty():
		printerr("CHAPTER1 INTERIORS BUILD FAIL ", errors)
		quit(1)
		return
	print("CHAPTER1 INTERIORS BUILD PASS — six saved rooms, three shops, three placeholder dialogues")
	quit(0)

func _write_content() -> void:
	_write_shop("chapter1_smith", "Кузнец · макет ассортимента", [
		{"itemId": "traveler_tunic", "buyPrice": 12, "sellPrice": 5, "stock": 2},
	])
	_write_shop("chapter1_general_store", "Обычные товары · макет ассортимента", [
		{"itemId": "apple", "buyPrice": 2, "sellPrice": 1, "stock": 8},
		{"itemId": "meat_bun", "buyPrice": 5, "sellPrice": 2, "stock": 4},
	])
	_write_shop("chapter1_alchemy", "Алхимическая лавка · макет ассортимента", [
		{"itemId": "herb", "buyPrice": 3, "sellPrice": 1, "stock": 8},
		{"itemId": "revival_spark", "buyPrice": 15, "sellPrice": 0, "stock": 2},
	])
	_write_dialogue("chapter1_blockout_home", "Мать · макет", "Это макет кухни и разговора. Утренняя сцена и вручение подарка будут добавлены позднее.")
	_write_dialogue("chapter1_blockout_guild", "Служащий · макет", "Здесь будет выдача городских поручений. Сейчас проверяем вход, разговор и возвращение на площадь.")
	_write_dialogue("chapter1_blockout_mansion", "Управляющий · макет", "Это макет входного зала. Место встречи с Мирой находится в саду снаружи.")

func _write_shop(id: String, title: String, listings: Array) -> void:
	var resource := Shop.new()
	resource.shop_id = id
	resource.definition = {"id": id, "nameRu": title, "listings": listings}
	var error := ResourceSaver.save(resource, "res://content/shops/" + id + ".tres")
	if error != OK: errors.append("shop %s: %s" % [id, error_string(error)])

func _write_dialogue(id: String, speaker: String, text: String) -> void:
	var resource := Dialogue.new()
	resource.dialogue_id = id
	resource.document = {"id": id, "nameRu": speaker, "use": "talk", "startStepId": "line", "steps": [
		{"id": "line", "type": "dialogue", "nameRu": speaker, "textRu": text, "next": "end"},
		{"id": "end", "type": "end"},
	]}
	var error := ResourceSaver.save(resource, "res://content/dialogues/" + id + ".tres")
	if error != OK: errors.append("dialogue %s: %s" % [id, error_string(error)])

func _room(id: String, title: String, size: Vector2i, parent_map: String, return_id: String) -> Node3D:
	var scene := G.base_map(id, title, size, "stone")
	var map := G.map_of(scene)
	map.camera_distance = 150.0
	map.camera_polar = 0.73
	map.camera_yaw = 0.0
	var shell := G.group(G.props(scene), "RoomShell", Vector2.ZERO)
	var width := size.x * G.UNIT
	var depth := size.y * G.UNIT
	G.box(shell, "NorthWall", Vector3(width, 28, 4), Vector3(width * 0.5, 14, 2), Color("a79d85"))
	G.box(shell, "WestWall", Vector3(4, 15, depth), Vector3(2, 7.5, depth * 0.5), Color("a79d85"))
	G.box(shell, "EastWall", Vector3(4, 15, depth), Vector3(width - 2, 7.5, depth * 0.5), Color("a79d85"))
	var front_piece := (width - 40.0) * 0.5
	for side in [-1.0, 1.0]:
		G.box(shell, "FrontWall%d" % int(side), Vector3(front_piece, 12, 4), Vector3(width * 0.5 + side * (20 + front_piece * 0.5), 6, depth - 2), Color("a79d85"))
	var door := G.group(G.props(scene), "ExitDoor", Vector2(size.x * 0.5, size.y - 1.0))
	var interact := G.door(door, parent_map, Vector3(0, 8, 0), "Наружу")
	interact.target_region_id = return_id
	G.region(door, id, "entry", Vector3(0, 0, -27))
	G.label(door, "Выход · F", Vector3(0, 34, 0), Color("d7e9b9"))
	return scene

func _npc(scene: Node3D, id: String, caption: String, xz: Vector2, kind: String, reference: String) -> Node3D:
	var value := G.group(G.props(scene), id, xz)
	value.set_meta("presentation_id", G.map_of(scene).map_id + "_" + id)
	G.box(value, "Body", Vector3(10, 22, 8), Vector3(0, 11, 0), Color("8e9a9c"))
	G.box(value, "Head", Vector3(9, 9, 9), Vector3(0, 27, 0), Color("c5b291"))
	G.label(value, caption + " · F", Vector3(0, 43, 0))
	var values := {"kind": kind, "note": caption + " · макет"}
	values["shop_id" if kind == "shop" else "script_id"] = reference
	var interact := EmberSceneAuthoring.make_interact(values, G.UNIT)
	interact.name = "Interaction"
	interact.position = Vector3(0, 12, 9)
	value.add_child(interact)
	return value

func _furniture(scene: Node3D, id: String, xz: Vector2, size: Vector3, color: Color) -> Node3D:
	var value := G.group(G.props(scene), id, xz)
	G.box(value, "Furniture", size, Vector3(0, size.y * 0.5, 0), color)
	return value

func home() -> Node3D:
	var scene := _room("chapter1_home", "Дом Кая · кухня", Vector2i(12, 12), "chapter1_residential", "return_home")
	_furniture(scene, "KitchenTable", Vector2(4.0, 5.0), Vector3(38, 14, 25), Color("9d8667"))
	_furniture(scene, "KitchenShelf", Vector2(1.3, 2.0), Vector3(20, 24, 22), Color("8d795f"))
	_furniture(scene, "Hearth", Vector2(8.5, 1.5), Vector3(32, 27, 25), Color("8d8b80"))
	_furniture(scene, "BedReserve", Vector2(9.2, 5.7), Vector3(22, 8, 40), Color("8b9393"))
	_npc(scene, "Mother", "Мать", Vector2(6.8, 3.8), "talk", "chapter1_blockout_home")
	var kitchen := (load("res://prefabs/items/cooking_station.tscn") as PackedScene).instantiate() as Node3D
	G.props(scene).add_child(kitchen)
	kitchen.position = Vector3(40, 8, 120)
	return scene

func guild() -> Node3D:
	var scene := _room("chapter1_guild", "Гильдия · зал поручений", Vector2i(15, 14), "chapter1_centre", "return_guild")
	_furniture(scene, "ReceptionCounter", Vector2(7.5, 5.7), Vector3(72, 16, 18), Color("978165"))
	_furniture(scene, "NoticeBoard", Vector2(2.5, 1.0), Vector3(48, 29, 4), Color("aa9b78"))
	G.label(G.props(scene), "Доска поручений · место", Vector3(2.5 * 16, 47, 16))
	_furniture(scene, "BenchLeft", Vector2(2.2, 9.2), Vector3(35, 10, 14), Color("927d62"))
	_furniture(scene, "BenchRight", Vector2(12.5, 9.2), Vector3(35, 10, 14), Color("927d62"))
	_npc(scene, "GuildClerk", "Служащий гильдии", Vector2(7.5, 4.2), "talk", "chapter1_blockout_guild")
	return scene

func _shop_room(id: String, title: String, return_id: String, shop_id: String) -> Node3D:
	var scene := _room(id, title, Vector2i(12, 12), "chapter1_centre", return_id)
	_furniture(scene, "Counter", Vector2(6.0, 5.8), Vector3(58, 15, 16), Color("9c8467"))
	_npc(scene, "Shopkeeper", "Продавец", Vector2(6.0, 4.3), "shop", shop_id)
	_furniture(scene, "ShelfLeft", Vector2(1.2, 4.3), Vector3(20, 26, 45), Color("8f7d63"))
	_furniture(scene, "ShelfRight", Vector2(10.8, 4.3), Vector3(20, 26, 45), Color("8f7d63"))
	return scene

func smith() -> Node3D:
	var scene := _shop_room("chapter1_smith", "Кузнец · интерьер-макет", "return_smith", "chapter1_smith")
	_furniture(scene, "AnvilReserve", Vector2(2.8, 8.0), Vector3(20, 13, 18), Color("777f80"))
	_furniture(scene, "Workbench", Vector2(9.4, 8.6), Vector3(28, 13, 20), Color("947f62"))
	return scene

func general_store() -> Node3D:
	var scene := _shop_room("chapter1_general_store", "Обычные товары · интерьер-макет", "return_general_store", "chapter1_general_store")
	G.crates(scene, Vector2(2.2, 8.2), 2)
	_furniture(scene, "GoodsTable", Vector2(9.5, 8.4), Vector3(30, 12, 24), Color("a58d6b"))
	return scene

func alchemy() -> Node3D:
	var scene := _shop_room("chapter1_alchemy", "Алхимическая лавка · интерьер-макет", "return_alchemy", "chapter1_alchemy")
	var table := _furniture(scene, "ReagentTable", Vector2(9.3, 8.4), Vector3(30, 12, 20), Color("969079"))
	for index in 3:
		G.box(table, "Reagent%d" % index, Vector3(4, 7, 4), Vector3(-9 + index * 9, 15.5, 0), Color("7f9b8e"), false)
	return scene

func mansion() -> Node3D:
	var scene := _room("chapter1_mansion", "Особняк Миры · входной зал", Vector2i(18, 16), "chapter1_estate", "return_mansion")
	_furniture(scene, "HallTable", Vector2(9.0, 6.5), Vector3(52, 16, 30), Color("a08e70"))
	_furniture(scene, "Bookcase", Vector2(2.0, 2.0), Vector3(48, 35, 18), Color("8b7961"))
	_furniture(scene, "SofaReserve", Vector2(15.2, 5.0), Vector3(30, 13, 50), Color("879b91"))
	_npc(scene, "Steward", "Управляющий", Vector2(6.0, 8.3), "talk", "chapter1_blockout_mansion")
	G.label(G.props(scene), "Другие комнаты · позднее", Vector3(9 * 16, 45, 16))
	return scene
