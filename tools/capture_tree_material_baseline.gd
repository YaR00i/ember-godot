extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_spruce_bough_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.species_ready:await process_frame
	check(ResourceSaver.save(scene.tree_leaf_shared_material,output.path_join("painted-tree-foliage.res"),ResourceSaver.FLAG_COMPRESS)==OK,"save accepted shared leaf base")
	print("TREE_MATERIAL_BASELINE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
