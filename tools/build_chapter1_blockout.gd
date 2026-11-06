extends SceneTree
## Explicit offline build of the first playable chapter layout. Never runs in gameplay.
const G = preload("res://tools/chapter1_blockout_geometry.gd")
var errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var selected := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): selected = argument.trim_prefix("--only=")
	for build in [residential, centre, harbor, estate, woodland, coast, tide_cave]:
		if not selected.is_empty() and str(build.get_method()) != selected: continue
		var scene: Node3D = build.call()
		var error := G.save(scene)
		if error != OK: errors.append("%s: %s" % [scene.name, error_string(error)])
		else: print("SAVED ", scene.name)
		scene.free()
	if not errors.is_empty(): printerr("CHAPTER1 BUILD FAIL ", errors); quit(1); return
	print("CHAPTER1 EXTERIORS BUILD PASS — seven saved native maps")
	quit(0)

func residential() -> Node3D:
	var scene := G.base_map("chapter1_residential", "Жилая улица · канал и дворы", Vector2i(32, 36))
	G.water_strip(scene, 16, 1.3, 1.1)
	G.paint_path(scene, [Vector2(12.8, 1), Vector2(14, 8), Vector2(13, 18), Vector2(12.3, 27), Vector2(13, 35)], 2.0, 3)
	G.paint_path(scene, [Vector2(19.3, 1), Vector2(20.2, 8), Vector2(18.8, 18), Vector2(18, 27), Vector2(19, 35)], 2.0, 3)
	G.paint_path(scene, [Vector2(11, 10), Vector2(30, 10)], 2.6, 3)
	G.paint_path(scene, [Vector2(4, 27), Vector2(24, 27)], 2.2, 3)
	for z in [10.0, 27.0]:
		G.box(G.props(scene), "Bridge%d" % int(z), Vector3(110, 4, 28), Vector3(16 * 16, 8, z * 16), Color("9f9279"))
	G.building(scene, "KaiHome", "Дом Кая", Vector2(7, 7), Vector3(72, 48, 60), "chapter1_home", "return_home")
	for definition in [[Vector2(7, 18), -0.08], [Vector2(7, 29), 0.10], [Vector2(25, 6), -0.08], [Vector2(26, 18), 0.07], [Vector2(25, 30), -0.10]]:
		G.building(scene, "Neighbour%d" % G.props(scene).get_child_count(), "Дом", definition[0], Vector3(64, 42, 48), "", "", definition[1])
	for xz in [Vector2(8, 11), Vector2(8, 22), Vector2(25, 10), Vector2(26, 22)]:
		var yard := G.group(G.props(scene), "Yard%d" % G.props(scene).get_child_count(), xz)
		G.box(yard, "VegetableBed", Vector3(40, 2, 22), Vector3(0, 1, 0), Color("77654a"), false)
		for i in 5: G.box(yard, "Crop%d" % i, Vector3(5, 4, 11), Vector3(-16 + i * 8, 4, 0), Color("7b8c54"), false)
		G.fence(yard, Vector2(0, 1.1), 58)
	for xz in [Vector2(3, 13), Vector2(28, 12), Vector2(4, 33), Vector2(29, 33)]: G.tree(scene, "Maple%d" % G.props(scene).get_child_count(), xz, 0.5)
	G.gate(scene, "ToCentre", "Центр →", Vector2(30.5, 10), "chapter1_centre", "from_residential", Vector2(27.5, 10), "from_centre")
	G.gate(scene, "ToEstate", "К усадьбе Миры →", Vector2(5, 34), "chapter1_estate", "from_residential", Vector2(5, 31), "from_estate")
	G.region(scene.get_node("Map/Regions"), "chapter1_residential", "entry", Vector3(11 * 16, 8, 10 * 16))
	return scene

func centre() -> Node3D:
	var scene := G.base_map("chapter1_centre", "Центр · площадь и лавки", Vector2i(32, 32), "stone")
	G.building(scene, "Guild", "Гильдия", Vector2(16, 5), Vector3(112, 64, 72), "chapter1_guild", "return_guild")
	G.building(scene, "Smith", "Кузнец", Vector2(6, 11), Vector3(64, 42, 48), "chapter1_smith", "return_smith")
	G.building(scene, "GeneralStore", "Товары", Vector2(25, 12), Vector3(64, 42, 48), "chapter1_general_store", "return_general_store")
	G.building(scene, "Alchemy", "Алхимическая лавка", Vector2(26, 22), Vector3(64, 42, 48), "chapter1_alchemy", "return_alchemy")
	G.building(scene, "TailorReserve", "Ремесленник · место", Vector2(6, 22), Vector3(64, 42, 48))
	var fountain := G.group(G.props(scene), "Fountain", Vector2(16, 19))
	G.box(fountain, "Basin", Vector3(34, 5, 34), Vector3(0, 2.5, 0), Color("96978b"))
	G.box(fountain, "Water", Vector3(27, 1, 27), Vector3(0, 5.5, 0), Color("719ca9"), false)
	G.box(fountain, "Column", Vector3(6, 20, 6), Vector3(0, 15, 0), Color("a9a48f"))
	G.label(fountain, "Площадь / ярмарка", Vector3(0, 39, 0))
	for x in [9.0, 22.0]:
		var stand := G.group(G.props(scene), "FairStall%d" % int(x), Vector2(x, 28))
		G.box(stand, "Table", Vector3(40, 13, 15), Vector3(0, 6.5, 0), Color("9f8766"))
		G.label(stand, "Место прилавка", Vector3(0, 24, 0))
	G.crates(scene, Vector2(28, 28), 3)
	G.gate(scene, "ToResidential", "← Жилая улица", Vector2(1.5, 17), "chapter1_residential", "from_centre", Vector2(4.5, 17), "from_residential")
	G.gate(scene, "ToHarbor", "Порт →", Vector2(30.5, 17), "chapter1_harbor", "from_centre", Vector2(27.5, 17), "from_harbor")
	G.gate(scene, "ToWoodland", "За город →", Vector2(16, 30), "chapter1_woodland", "from_centre", Vector2(16, 27), "from_woodland")
	G.region(scene.get_node("Map/Regions"), "chapter1_centre", "entry", Vector3(16 * 16, 8, 14 * 16))
	return scene

func harbor() -> Node3D:
	var scene := G.base_map("chapter1_harbor", "Порт · склады и причалы", Vector2i(32, 32), "stone")
	var ground = G.map_of(scene).compact_terrain
	for z in range(22 * 16, ground.depth):
		for x in ground.width:
			var i: int = z * ground.width + x
			ground.heights[i] = 1; ground.water_levels[i] = 6; ground.water_materials[i] = 5
	G.building(scene, "Warehouse", "Склад · место", Vector2(8, 6), Vector3(96, 56, 64))
	G.building(scene, "PortStores", "Портовые лавки · место", Vector2(24, 6), Vector3(96, 48, 64))
	for x in [10.0, 24.0]: G.box(G.props(scene), "Pier%d" % int(x), Vector3(30, 5, 110), Vector3(x * 16, 8, 25 * 16), Color("927e61"))
	for p in [Vector2(9, 14), Vector2(23, 13), Vector2(26, 19)]: G.crates(scene, p, 5)
	G.gate(scene, "ToCentre", "← Центр", Vector2(1.5, 17), "chapter1_centre", "from_harbor", Vector2(4.5, 17), "from_centre")
	G.region(scene.get_node("Map/Regions"), "chapter1_harbor", "entry", Vector3(16 * 16, 8, 17 * 16))
	G.label(G.props(scene), "Тропа к маяку · позднее", Vector3(28 * 16, 34, 10 * 16))
	return scene

func estate() -> Node3D:
	var scene := G.base_map("chapter1_estate", "Усадьба Миры · подход, двор и сад", Vector2i(32, 36))
	G.paint_path(scene, [Vector2(5, 33), Vector2(8, 26), Vector2(15, 21), Vector2(16, 13)], 3, 3)
	G.building(scene, "Mansion", "Особняк Миры", Vector2(16, 7), Vector3(144, 80, 96), "chapter1_mansion", "return_mansion")
	for x in [7.0, 25.0]: G.building(scene, "RichHouse%d" % int(x), "Ухоженный дом", Vector2(x, 27), Vector3(64, 48, 48))
	var garden := G.group(G.props(scene), "Garden", Vector2(24, 18))
	G.box(garden, "Pool", Vector3(60, 3, 38), Vector3(0, 1.5, 0), Color("a8a48c"))
	G.box(garden, "Water", Vector3(53, 1, 31), Vector3(0, 3.5, 0), Color("7498a0"), false)
	G.label(garden, "Сад / место Миры", Vector3(0, 24, 0))
	for p in [Vector2(5, 16), Vector2(8, 21), Vector2(27, 11), Vector2(26, 29)]: G.tree(scene, "Maple%d" % G.props(scene).get_child_count(), p, 0.55)
	G.grass(scene, "GardenGrass", Vector2(22, 24), Vector2(4, 3))
	var workbench := (load("res://prefabs/items/crafting_workbench.tscn") as PackedScene).instantiate() as Node3D
	G.props(scene).add_child(workbench)
	workbench.position = Vector3(352, 8, 256)
	G.gate(scene, "ToResidential", "← Жилая улица", Vector2(5, 34), "chapter1_residential", "from_estate", Vector2(5, 31), "from_residential")
	G.region(scene.get_node("Map/Regions"), "chapter1_estate", "entry", Vector3(15 * 16, 8, 22 * 16))
	return scene

func woodland() -> Node3D:
	var scene := G.base_map("chapter1_woodland", "Опушка и склоны · прогулка", Vector2i(40, 36))
	var delivery := (load("res://prefabs/items/chapter1_delivery_crate.tscn") as PackedScene).instantiate() as Node3D
	G.props(scene).add_child(delivery)
	delivery.position = Vector3(112, 8.3, 288)
	G.paint_path(scene, [Vector2(3, 18), Vector2(11, 20), Vector2(19, 13), Vector2(28, 17), Vector2(38, 18)], 3)
	G.paint_path(scene, [Vector2(11, 20), Vector2(9, 8), Vector2(20, 6), Vector2(28, 17)], 1.8)
	G.paint_path(scene, [Vector2(19, 13), Vector2(24, 27), Vector2(34, 27), Vector2(28, 17)], 1.8)
	for p in [Vector2(6, 5), Vector2(5, 28), Vector2(14, 31), Vector2(16, 5), Vector2(25, 7), Vector2(33, 7), Vector2(35, 30), Vector2(29, 31)]:
		G.tree(scene, "Maple%d" % G.props(scene).get_child_count(), p, 0.7)
	for p in [Vector2(6, 11), Vector2(15, 27), Vector2(31, 11), Vector2(35, 24)]: G.grass(scene, "Grass%d" % G.props(scene).get_child_count(), p, Vector2(4, 4))
	G.crates(scene, Vector2(10, 23), 3)
	G.label(G.props(scene), "Телега / груз · место", Vector3(10 * 16, 30, 24 * 16))
	G.label(G.props(scene), "Задача / короткий путь · место", Vector3(28 * 16, 28, 27 * 16))
	G.gate(scene, "ToCentre", "← Город", Vector2(1.5, 18), "chapter1_centre", "from_woodland", Vector2(4.5, 18), "from_centre")
	G.gate(scene, "ToCoast", "Побережье →", Vector2(38.5, 18), "chapter1_coast", "from_woodland", Vector2(35.5, 18), "from_coast")
	G.region(scene.get_node("Map/Regions"), "chapter1_woodland", "entry", Vector3(6 * 16, 8, 18 * 16))
	return scene

func coast() -> Node3D:
	var scene := G.base_map("chapter1_coast", "Дальний берег · рыбалка и пещера", Vector2i(40, 36), "sand")
	var ground = G.map_of(scene).compact_terrain
	for z in ground.depth:
		for x in range(31 * 16, ground.width):
			var i: int = z * ground.width + x
			ground.heights[i] = 1; ground.water_levels[i] = 6; ground.water_materials[i] = 5
	G.paint_path(scene, [Vector2(2, 18), Vector2(11, 23), Vector2(21, 20), Vector2(27, 11), Vector2(28, 3)], 2.5)
	G.paint_path(scene, [Vector2(11, 23), Vector2(10, 30), Vector2(25, 30), Vector2(27, 11)], 1.7)
	for p in [Vector2(7, 9), Vector2(17, 7), Vector2(20, 32)]: G.tree(scene, "Maple%d" % G.props(scene).get_child_count(), p, 0.65)
	var fishing_stop := preload("res://prefabs/items/chapter1_fishing_stop.tscn").instantiate() as Node3D
	fishing_stop.position = Vector3(480, 8, 432)
	G.props(scene).add_child(fishing_stop)
	fishing_stop.owner = scene
	G.label(G.props(scene), "Загадочный торговец · место", Vector3(11 * 16, 26, 30 * 16))
	var mouth := G.group(G.props(scene), "CaveMouth", Vector2(28, 4))
	G.box(mouth, "LeftRock", Vector3(22, 46, 30), Vector3(-27, 23, 0), Color("777e79"))
	G.box(mouth, "RightRock", Vector3(22, 46, 30), Vector3(27, 23, 0), Color("777e79"))
	G.box(mouth, "CapRock", Vector3(76, 16, 30), Vector3(0, 47, 0), Color("777e79"))
	G.gate(scene, "ToWoodland", "← Опушка", Vector2(1.5, 18), "chapter1_woodland", "from_coast", Vector2(4.5, 18), "from_woodland")
	G.gate(scene, "ToCave", "В пещеру →", Vector2(28, 2), "chapter1_tide_cave", "from_coast", Vector2(28, 6), "from_tide_cave")
	G.region(scene.get_node("Map/Regions"), "chapter1_coast", "entry", Vector3(6 * 16, 8, 18 * 16))
	return scene

func tide_cave() -> Node3D:
	var scene := G.base_map("chapter1_tide_cave", "Приливная пещера · черновые камеры", Vector2i(28, 32), "stone")
	for data in [[Vector3(8, 45, 390), Vector3(2 * 16, 22.5, 16 * 16)], [Vector3(8, 45, 390), Vector3(26 * 16, 22.5, 16 * 16)], [Vector3(384, 45, 8), Vector3(14 * 16, 22.5, 2 * 16)]]:
		G.box(G.props(scene), "CaveWall%d" % G.props(scene).get_child_count(), data[0], data[1], Color("727b78"))
	G.paint_path(scene, [Vector2(14, 29), Vector2(11, 22), Vector2(17, 16), Vector2(14, 8)], 3, 2)
	G.label(G.props(scene), "Камера совместной задачи · место", Vector3(14 * 16, 30, 19 * 16))
	for x in [7.0, 21.0]:
		var crystal := G.group(G.props(scene), "Crystal%d" % int(x), Vector2(x, 7))
		G.box(crystal, "CrystalBlock", Vector3(16, 40, 18), Vector3(0, 20, 0), Color("86a9ad"))
	G.label(G.props(scene), "Кристальный грот · место сцены", Vector3(14 * 16, 40, 8 * 16))
	var team_gate := preload("res://prefabs/items/chapter1_team_gate.tscn").instantiate() as Node3D
	team_gate.position = Vector3(224, 8, 240)
	G.props(scene).add_child(team_gate)
	team_gate.owner = scene
	var tide_cache := preload("res://prefabs/items/chapter1_tide_cache.tscn").instantiate() as Node3D
	tide_cache.position = Vector3(224, 8, 128)
	G.props(scene).add_child(tide_cache)
	tide_cache.owner = scene
	var battle := preload("res://prefabs/items/chapter1_tide_battle.tscn").instantiate() as Node3D
	battle.position = Vector3(72, 8, 144)
	G.props(scene).add_child(battle)
	battle.owner = scene
	G.gate(scene, "ToCoast", "← На берег", Vector2(14, 30), "chapter1_coast", "from_tide_cave", Vector2(14, 27), "from_coast")
	G.region(scene.get_node("Map/Regions"), "chapter1_tide_cave", "entry", Vector3(14 * 16, 8, 26 * 16))
	return scene
