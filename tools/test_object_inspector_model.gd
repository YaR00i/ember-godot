extends SceneTree
const MixedFixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
## I0 contract: one read-only snapshot explains prop/light/Interact/references
## without changing authored .tscn or JOI content.

const SANDBOX_SCENE := "res://scenes/editor_fixture_b.tscn"
const TOWN_SCENE := "res://scenes/editor_fixture_a.tscn"


func _init() -> void:
	if not MixedFixture.prepare(self):
		quit(2)
		return
	var errors: Array[String] = []
	var sandbox_hash := FileAccess.get_sha256(SANDBOX_SCENE)
	var town_hash := FileAccess.get_sha256(TOWN_SCENE)
	var sandbox := _instantiate(SANDBOX_SCENE)
	var town := _instantiate(TOWN_SCENE)
	if sandbox == null or town == null:
		errors.append("editor_fixture_b/editor_fixture_a could not be instantiated")
	else:
		_test_talk_shop(errors, sandbox)
		_test_quest(errors, sandbox)
		_test_door(errors, town)
		_test_light_and_generated_child(errors, town)
		_test_native_source(errors)
		_test_native_references(errors)
		sandbox.free()
		town.free()
	if sandbox_hash != FileAccess.get_sha256(SANDBOX_SCENE):
		errors.append("Inspector snapshot changed editor_fixture_b.tscn")
	if town_hash != FileAccess.get_sha256(TOWN_SCENE):
		errors.append("Inspector snapshot changed editor_fixture_a.tscn")
	MixedFixture.verify_sources(errors)
	if not errors.is_empty():
		printerr("FAIL object inspector model")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS object inspector model")
	print("  prop identity + Asset/Scene/Derived components")
	print("  lantern authored/effective light + generated child owner")
	print("  native destinations and unsaved local triggers resolve without JOI")
	print("  talk/shop/quest references retain their existing catalog owners")
	print("  scene files unchanged")
	quit(0)


func _instantiate(path: String) -> Node:
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	return packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed else null


func _test_native_source(errors: Array[String]) -> void:
	# Native source identity must not depend on any available sibling JOI path.
	var previous_pack: Variant = ProjectSettings.get_setting("ember/pack_path", "")
	ProjectSettings.set_setting("ember/pack_path", "user://missing-inspector-legacy-pack")
	EmberVoxelPrefab.begin_import()
	var prop := EmberVoxelPrefab.make_preview_instance("editor_fixture_block", 1.0)
	if prop == null:
		errors.append("native source fixture could not load without JOI")
	else:
		var snapshot := EmberObjectInspectorModel.snapshot(prop)
		var sources: Dictionary = snapshot.get("sources", {})
		if str(sources.get("owner", "")) != "godot" or str(sources.get("source", "")) != EmberVoxelCatalog.native_path("editor_fixture_block"):
			errors.append("Inspector lost the native Resource source owner/path")
		if _row_value(_component(snapshot, "renderer"), "Source") != "Godot Resource (.tres)":
			errors.append("Inspector labels the native Resource as legacy JSON")
		var panel := EmberObjectInspectorPanel.new()
		panel.setup(prop, snapshot)
		var hint: String = panel.call("_source_hint", "Asset")
		if not hint.contains("Godot Resource") or hint.contains("JOI"):
			errors.append("native Asset tooltip points to JOI")
		panel.free()
		prop.free()
	ProjectSettings.set_setting("ember/pack_path", previous_pack)
	EmberVoxelPrefab.begin_import()


func _test_native_references(errors: Array[String]) -> void:
	var previous_pack: Variant = ProjectSettings.get_setting("ember/pack_path", "")
	ProjectSettings.set_setting("ember/pack_path", "user://missing-inspector-reference-pack")
	var map := EmberMapLoader.new()
	map.map_id = "unsaved_native_fixture"
	var regions := Node3D.new()
	regions.name = "Regions"
	map.add_child(regions)
	var group := Node3D.new()
	regions.add_child(group)
	var region := EmberRegion.new()
	region.region_id = "unsaved_trigger"
	group.add_child(region)
	var door := EmberInteract.new()
	map.add_child(door)
	door.trigger_id = "unsaved_trigger"
	door.target_map_id = "landscape_compact"
	door.target_region_id = "landscape_compact_start"
	var component := _component(EmberObjectInspectorModel.snapshot(door), "interact")
	for label in ["Trigger", "Target map", "Target region"]:
		if not _row_value(component, label).contains("resolved"):
			errors.append("native reference missing without JOI: %s" % label)
	door.target_region_id = "missing_entry"
	component = _component(EmberObjectInspectorModel.snapshot(door), "interact")
	if not _row_value(component, "Target region").contains("MISSING"):
		errors.append("missing native entrance was reported as resolved")
	door.target_map_id = "combat_lab"
	component = _component(EmberObjectInspectorModel.snapshot(door), "interact")
	if not _row_value(component, "Target map").contains("MISSING"):
		errors.append("non-map scene was reported as a native map destination")
	map.free()
	ProjectSettings.set_setting("ember/pack_path", previous_pack)


func _test_talk_shop(errors: Array[String], sandbox: Node) -> void:
	var talk := sandbox.get_node_or_null("Map/Props/talk_npc") as EmberVoxelProp
	var shop := sandbox.get_node_or_null("Map/Props/shop_kiosk") as EmberVoxelProp
	if talk == null or shop == null:
		errors.append("sandbox talk/shop props missing")
		return
	var talk_snapshot := EmberObjectInspectorModel.snapshot(talk)
	var talk_component := _component(talk_snapshot, "interact")
	if str(talk_snapshot.get("placementId", "")) != "talk_npc":
		errors.append("talk snapshot lost placement identity")
	var script_value := _row_value(talk_component, "Script")
	if script_value.find("Тестовый собеседник") < 0 or script_value.find("resolved") < 0:
		errors.append("talk script reference did not resolve: %s" % script_value)
	var shop_snapshot := EmberObjectInspectorModel.snapshot(shop)
	var shop_component := _component(shop_snapshot, "interact")
	if str(shop_component).find("Тестовая лавка") < 0 or str(shop_component).find("позиций") < 0:
		errors.append("shop reference did not join the catalog")


func _test_door(errors: Array[String], town: Node) -> void:
	var door := town.get_node_or_null("Map/Props/destination_door") as EmberVoxelProp
	if door == null:
		errors.append("editor_fixture_a mage door missing")
		return
	var snapshot := EmberObjectInspectorModel.snapshot(door)
	var interact := _component(snapshot, "interact")
	if str(interact).find("editor_fixture_destination") < 0 or str(interact).find("missing_entry") < 0:
		errors.append("door destination is absent from Inspector snapshot")
	if not _row_value(interact, "Target region").contains("MISSING"):
		errors.append("legacy-only mage entrance was incorrectly reported as a saved native region")


func _test_quest(errors: Array[String], sandbox: Node) -> void:
	var quest := sandbox.get_node_or_null("Map/Props/quest_sign") as EmberVoxelProp
	if quest == null:
		errors.append("sandbox quest marker is missing")
		return
	var component := _component(EmberObjectInspectorModel.snapshot(quest), "interact")
	if _row_value(component, "Fallback status") != "available":
		errors.append("Inspector lost authored quest status")
	if _row_value(component, "Current quest icon") != "quest_available":
		errors.append("Inspector did not derive quest alias icon")
	if _row_value(component, "Quest flag") != "interaction_quest_status":
		errors.append("Inspector lost quest progress flag key")
	var marker_role := _row_value(component, "Роль маркера")
	if marker_role != "Выдать задание":
		errors.append("Inspector did not infer the quest giver role from its action chain: %s" % marker_role)
	if _row_value(component, "На свежем прохождении").find("янтарный") < 0:
		errors.append("Inspector did not explain the fresh-save marker state")
	if str(component).find("MISSING") >= 0:
		errors.append("quest flag was incorrectly validated as an executable script")


func _test_light_and_generated_child(errors: Array[String], town: Node) -> void:
	var prop := _first_lantern(town)
	if prop == null:
		errors.append("editor_fixture_a has no generated Omni owner")
		return
	var snapshot := EmberObjectInspectorModel.snapshot(prop)
	var light := _component(snapshot, "light")
	if light.is_empty():
		errors.append("lantern snapshot has no Emissive Light component")
	elif str(light).find("Effective Omni range") < 0 or str(light).find("Derived") < 0:
		errors.append("lantern snapshot does not separate authored/effective light")
	var omni := prop.get_node_or_null("Omni")
	var child_snapshot := EmberObjectInspectorModel.snapshot(omni)
	if bool(child_snapshot.get("selectedIsOwner", true)):
		errors.append("generated Omni selection did not resolve its prop owner")
	if str(child_snapshot.get("diagnostics", [])).find("Authoring owner") < 0:
		errors.append("generated child snapshot lacks owner guidance")
	var previous: Variant = prop.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, "")
	prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, "deliberately-stale-test")
	var stale := EmberObjectInspectorModel.snapshot(prop)
	if str(stale.get("prefabState", "")) != "нужна пересборка":
		errors.append("stale source signature was not diagnosed")
	prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, previous)


func _component(snapshot: Dictionary, component_id: String) -> Dictionary:
	var components: Array = snapshot.get("components", [])
	for component in components:
		if typeof(component) == TYPE_DICTIONARY and str(component.get("id", "")) == component_id:
			return component
	return {}


func _row_value(component: Dictionary, label: String) -> String:
	var rows: Array = component.get("rows", [])
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("label", "")) == label:
			return str(row.get("value", ""))
	return ""


func _first_lantern(root: Node) -> EmberVoxelProp:
	if root is EmberVoxelProp and root.get_node_or_null("Omni") != null:
		return root as EmberVoxelProp
	for child in root.get_children():
		var found := _first_lantern(child)
		if found != null:
			return found
	return null
