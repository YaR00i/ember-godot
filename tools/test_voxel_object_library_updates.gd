extends SceneTree
const Shelf = preload("res://addons/ember_import/ember_voxel_object_library_panel.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
var errors := 0

class FixtureShelf extends Shelf:
	var refresh_count := 0
	var fixture_entries: Array[Dictionary] = []
	func refresh(preferred_id := "") -> void:
		refresh_count += 1
		if _picker == null: return
		var selected := preferred_id if not preferred_id.is_empty() else selected_model_id()
		_all_entries = fixture_entries.duplicate(true)
		_apply_filter(selected)

func entry(id: String) -> Dictionary:
	return {"id":id,"title":"Board","label":"Board · " + id,"tooltip":id,"owner":"godot","ready":true,"variations":[]}

func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var directory := "user://library_updates_%d" % Time.get_ticks_usec()
	var panel := FixtureShelf.new()
	panel.fixture_entries = [entry("stable")]
	root.add_child(panel)
	for frame in 3: await process_frame
	panel._picker._search.text = "board"
	panel._picker._refresh()
	panel._owner_filter = "godot"
	panel._apply_filter("stable")
	var preview := ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_RGBA8))
	panel._textures["stable"] = preview
	var refreshed := panel.refresh_count
	var notifications: Array = []
	var observer := func(paths: PackedStringArray) -> void: notifications.append(paths)
	Store.asset_events.assets_published.connect(observer)
	panel.fixture_entries.append(entry("created_board"))
	var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(16,8,16),16,Color.CORAL,"created_board","Created board").source
	var before := source.to_definition().duplicate(true)
	var packed := EmberVoxelPrefab.prepare_resource(source)
	var source_path := directory.path_join("models/created_board.tres")
	var prefab_path := directory.path_join("prefabs/created_board.tscn")
	var result := Store.install_prepared_asset(source,packed,source_path,prefab_path)
	check(result.ok and notifications.size() == 1,"successful asset installation notifies shelf")
	check(notifications[0] == PackedStringArray([source_path,prefab_path]),"notification contains final published paths")
	check(source.to_definition() == before,"publication notification never mutates draft")
	var reopened := ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(reopened != null and reopened.model_id == source.model_id and reopened.validation_errors().is_empty(),"notified source is already readable and valid")
	# Adjacent saves coalesce, but each successful transaction is observable.
	result = Store.install_prepared_asset(source,packed,source_path,prefab_path)
	check(result.ok and notifications.size() == 2,"save existing asset notifies")
	for frame in 3: await process_frame
	check(panel.refresh_count == refreshed + 1,"adjacent publication refreshes coalesce")
	check(panel._picker._search.text == "board" and panel._owner_filter == "godot","refresh retains query and owner filter")
	check(panel.selected_model_id() == "stable" and panel._picker._items.item_count == 2,"refresh discovers object without losing selection")
	check(panel._picker.selected_entry().get("texture") == preview,"unrelated in-memory preview retained")
	refreshed = panel.refresh_count
	var blocked := directory.path_join("blocked")
	var file := FileAccess.open(blocked,FileAccess.WRITE)
	file.store_string("Fixture blocks publication directory")
	file.close()
	result = Store.install_prepared_asset(source,packed,blocked.path_join("bad.tres"),prefab_path)
	for frame in 3: await process_frame
	check(not result.ok and notifications.size() == 2 and panel.refresh_count == refreshed,"failed publication never refreshes or advertises asset")
	panel.hide()
	panel.fixture_entries.append(entry("hidden_board"))
	Store.asset_events.assets_published.emit(PackedStringArray([source_path]))
	for frame in 3: await process_frame
	check(panel.refresh_count == refreshed,"hidden shelf postpones catalog work")
	panel.show()
	for frame in 3: await process_frame
	check(panel.refresh_count == refreshed + 1 and panel._picker._items.item_count == 3,"normal bottom-tab reopening refreshes existing shelf")
	check(panel._picker._search.text == "board" and panel.selected_model_id() == "stable","reopening preserves search and selection")
	var connection_count := Store.asset_events.assets_published.get_connections().size()
	panel.free()
	check(Store.asset_events.assets_published.get_connections().size() == connection_count - 1,"shelf detaches publication observer on destruction")
	Store.asset_events.assets_published.disconnect(observer)
	print("test_voxel_object_library_updates: ","PASS" if errors == 0 else "FAIL"," · ",errors)
	quit(errors)
