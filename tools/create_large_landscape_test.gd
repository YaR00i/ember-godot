extends SceneTree
## One-time authoring command. Never overwrites an existing test map.

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")


func _initialize() -> void:
	var creation := Creation.new()
	assert(creation.prepare_sections("large_landscape_test", 4, 4, 8), creation.error)
	var path := creation.commit()
	assert(not path.is_empty(), creation.error)
	print("LARGE_LANDSCAPE_TEST scene=", path, " terrain=", creation.terrain_path(), " cells=", creation.source.width, "x", creation.source.depth)
	quit()
