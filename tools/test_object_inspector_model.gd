extends SceneTree
## I0 contract: one read-only snapshot explains prop/light/Interact/references
## without changing authored .tscn or JOI content.

const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const TOWN_SCENE := "res://scenes/fan_town.tscn"


func _init() -> void:
	var errors: Array[String] = []
	var sandbox_hash := FileAccess.get_sha256(SANDBOX_SCENE)
	var town_hash := FileAccess.get_sha256(TOWN_SCENE)
	var sandbox := _instantiate(SANDBOX_SCENE)
	var town := _instantiate(TOWN_SCENE)
	if sandbox == null or town == null:
		errors.append("agent_sandbox/fan_town could not be instantiated")
	else:
		_test_talk_shop(errors, sandbox)
		_test_quest(errors, sandbox)
		_test_door(errors, town)
		_test_light_and_generated_child(errors, town)
		sandbox.free()
		town.free()
	if sandbox_hash != FileAccess.get_sha256(SANDBOX_SCENE):
		errors.append("Inspector snapshot changed agent_sandbox.tscn")
	if town_hash != FileAccess.get_sha256(TOWN_SCENE):
		errors.append("Inspector snapshot changed fan_town.tscn")
	if not errors.is_empty():
		printerr("FAIL object inspector model")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS object inspector model")
	print("  prop identity + Asset/Scene/Derived components")
	print("  lantern authored/effective light + generated child owner")
	print("  door/talk/shop/quest references resolve from existing pack")
	print("  scene files unchanged")
	quit(0)


func _instantiate(path: String) -> Node:
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	return packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed else null


func _test_talk_shop(errors: Array[String], sandbox: Node) -> void:
	var talk := sandbox.get_node_or_null("Map/Props/sbx_talk_npc") as EmberVoxelProp
	var shop := sandbox.get_node_or_null("Map/Props/sbx_shop_kiosk") as EmberVoxelProp
	if talk == null or shop == null:
		errors.append("sandbox talk/shop props missing")
		return
	var talk_snapshot := EmberObjectInspectorModel.snapshot(talk)
	var talk_component := _component(talk_snapshot, "interact")
	if str(talk_snapshot.get("placementId", "")) != "sbx_talk_npc":
		errors.append("talk snapshot lost placement identity")
	var script_value := _row_value(talk_component, "Script")
	if script_value.find("Страж у входа") < 0 or script_value.find("resolved") < 0:
		errors.append("talk script reference did not resolve: %s" % script_value)
	var shop_snapshot := EmberObjectInspectorModel.snapshot(shop)
	var shop_component := _component(shop_snapshot, "interact")
	if str(shop_component).find("Киоск деревни") < 0 or str(shop_component).find("позиций") < 0:
		errors.append("shop reference did not join the catalog")


func _test_door(errors: Array[String], town: Node) -> void:
	var door := town.get_node_or_null("Map/Props/ft_mage_door") as EmberVoxelProp
	if door == null:
		errors.append("fan_town mage door missing")
		return
	var snapshot := EmberObjectInspectorModel.snapshot(door)
	var interact := _component(snapshot, "interact")
	if str(interact).find("fan_town_mage") < 0 or str(interact).find("start") < 0:
		errors.append("door destination is absent from Inspector snapshot")
	if str(interact).find("MISSING") >= 0:
		errors.append("authored fan_town mage door reports a missing reference")


func _test_quest(errors: Array[String], sandbox: Node) -> void:
	var quest := sandbox.get_node_or_null("Map/Props/sbx_quest_sign") as EmberVoxelProp
	if quest == null:
		errors.append("sandbox quest marker is missing")
		return
	var component := _component(EmberObjectInspectorModel.snapshot(quest), "interact")
	if _row_value(component, "Fallback status") != "available":
		errors.append("Inspector lost authored quest status")
	if _row_value(component, "Current quest icon") != "quest_available":
		errors.append("Inspector did not derive quest alias icon")
	if _row_value(component, "Quest flag") != "sandbox_notice_status":
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
		errors.append("fan_town has no generated Omni owner")
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
