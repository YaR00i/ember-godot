extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Gate=preload("res://tools/test_leaf_pile.gd")
var errors: Array[String]=[]
func _init() -> void:
	if not Fixture.prepare(self):quit(2);return
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)
func frames(n: int) -> void:
	for i in n:await physics_frame
func shot(label: String) -> void:
	var folder:=OS.get_environment("EMBER_BERRY_CAPTURE_DIR")
	if folder.is_empty():return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run() -> void:
	var generator:=preload("res://addons/ember_import/ember_voxel_generator.gd")
	var layout:=preload("res://addons/ember_import/ember_voxel_fruit_placement.gd")
	var source:=load("res://content/voxel_models/vox_forest_berry_bush.tres") as EmberVoxelModelResource
	var recipe: Resource=load("res://content/editor/voxel_generators/vox_forest_berry_bush.tres")
	var rebuilt: Dictionary=generator.build(recipe,Color.WHITE,{},source.display_name,source.model_id)
	check(rebuilt.geometry.voxels==source.voxels,"saved recipe does not rebuild bush")
	var initial_voxels:=source.voxels.duplicate()
	var points:=layout.clusters(source,recipe.seed,15,16.0,0.55)
	check(points.size()==15 and points==layout.clusters(source,recipe.seed,15,16.0,0.55),"branch placement missing/unstable")
	check(points!=layout.clusters(source,recipe.seed+1,15,16.0,0.55),"placement seed is inert")
	check(points.filter(func(point):return point.wood.y>float(recipe.parameters.height)*0.8).size()>=8,"upper crown lacks berries for top camera")
	check(source.tree_surface.settings.get("plant_kind","")=="shrub","missing shared branch surface")
	check(source.validation_errors().is_empty(),"invalid shared shrub Source")
	var invalid:=source.duplicate_model();invalid.tree_surface.settings.shrub_leaf_scale=NAN
	check(not invalid.validation_errors().is_empty(),"invalid shrub leaf scale accepted")
	var branch_geometry:=preload("res://scripts/ember_tree_surface_geometry.gd")
	var branches:=branch_geometry.branches(source.tree_surface.structure)
	check(branches.filter(func(branch):return branch.order==1).size()==5,"shrub lacks basal shoots")
	var leaf_layout:=preload("res://scripts/ember_tree_surface.gd").leaf_layout(EmberVoxelPrefab.model_of(source.to_definition()))
	check(leaf_layout.cards>100 and leaf_layout.cards<1000,"shrub leaf-card budget invalid")
	for point in points:
		var branch: Dictionary=branches[point.branch_id]
		check(branch.order==3 and point.wood.distance_to(branch_geometry.point_at(branch,point.branch_t))<0.0001,"fruit lacks real twig support")
		check(point.wood.distance_to(point.attachment)<0.3,"berry stem too long")
		check(point.attachment.is_finite() and point.wood.is_finite(),"nonfinite support")
	check(source.voxels==initial_voxels,"fruit placement mutated source")
	for preset in generator.creation_presets(generator.BUSH):
		var generated: Dictionary=generator.build(preset.recipe,Color.WHITE,{},"fixture shrub")
		check(not layout.clusters(generated.geometry,7).is_empty(),"bush preset has no fruit supports")
	var empty:=source.duplicate_model();empty.tree_surface={};empty.voxels.fill(0)
	check(layout.clusters(empty,7).is_empty(),"woodless source created unsupported berries")
	check(layout.clusters(source,7,0).is_empty(),"zero cluster count created fruit")
	var foreign:=source.duplicate_model();foreign.tags=PackedStringArray(["tree"])
	check(layout.clusters(foreign,7).is_empty(),"bush placement silently accepted an unsupported tree frame")
	check(ResourceSaver.save(source,"user://berry-source.tres")==OK,"source save failed")
	var reopened_source:=load("user://berry-source.tres") as EmberVoxelModelResource
	check(layout.clusters(reopened_source,recipe.seed,15,16.0,0.55)==points,"source reopen changed fruit placement")
	var state:=root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled=false;state.flags.clear();state.inventory.erase("forest_berry")
	var host:=Gate.Host.new();var map:=Gate.StubMap.new();map.name="Map";host.add_child(map)
	var canvas:=CanvasLayer.new();canvas.name="CanvasLayer";host.add_child(canvas);var hud:=Label.new();hud.name="Gate";canvas.add_child(hud)
	root.add_child(host);current_scene=host
	var bush: EmberInteract=load("res://prefabs/items/berry_bush.scn").instantiate();host.add_child(bush)
	check(bush.get_node("Plant") is EmberVoxelProp and bush.get_node("Plant").model_id==source.model_id,"harvest bush bypasses existing generator")
	check(bush.get_node("Berries").get_children().filter(func(node):return str(node.name).begins_with("Berry")).size()==30,"bush must show thirty berries")
	for cluster in points.size():
		for j in 2:
			var fruit: Node3D=bush.get_node("Berries/Berry%d_%d"%[cluster,j])
			check(fruit.position.distance_to(points[cluster].attachment)<1.6 and fruit.scale.x==5.5,"baked fruit is unrelated to twig/berry scale")
	var player:=EmberPlayer.new();player.progress_state=state;player.position=Vector3(0,0,18);host.add_child(player);player.set_physics_process(false)
	var camera:=Camera3D.new();host.add_child(camera);camera.position=Vector3(44,34,62);camera.look_at(Vector3(0,15,0));camera.fov=38;camera.current=true
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.shadow_enabled=true;host.add_child(sun)
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("a9c2ce");world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=0.4;host.add_child(world)
	var ground:=MeshInstance3D.new();ground.mesh=BoxMesh.new();ground.mesh.size=Vector3(160,1,160);ground.position.y=-0.5;var paint:=StandardMaterial3D.new();paint.albedo_color=Color("71825b");ground.material_override=paint;host.add_child(ground)
	await frames(4)
	check(bush.get_node("Berries").visible and bush.is_in_group("ember_interact"),"unharvested bush unavailable")
	state.persistence_enabled=true;state.set_world_context("landscape_compact",player,16);check(state.save_slot(0),"fresh save failed")
	player.visible=false
	await shot("berry-bush-before")
	var side_pose:=camera.transform
	camera.position=Vector3(20,68,35);camera.look_at(Vector3(0,17,0));camera.fov=40
	await shot("berry-bush-top")
	camera.transform=side_pose;camera.fov=38
	state.inventory["forest_berry"]=98
	player._try_interact()
	check(state.inventory.forest_berry==98 and not state.flags.get(bush.completion_flag_id,false) and bush.get_node("Berries").visible,"full stack consumed bush")
	state.inventory.erase("forest_berry");state.combat_party_locked=true;bush.activate_from(player)
	check(not state.inventory.has("forest_berry") and not state.flags.get(bush.completion_flag_id,false),"combat handoff harvested")
	state.combat_party_locked=false
	var writes: Array[int]=[0];var saved:=func(_path):writes[0]+=1
	state.saved.connect(saved)
	player._try_interact();await frames(2)
	check(state.inventory.get("forest_berry",0)==3 and state.flags.get(bush.completion_flag_id,false) and not bush.get_node("Berries").visible,"F did not harvest")
	check(writes[0]==1 and not bush.is_in_group("ember_interact"),"harvest not one save/prompt still active")
	bush.activate_from(player);player._try_interact()
	check(state.inventory.forest_berry==3 and writes[0]==1,"repeat gave berries")
	check(state.save_slot(1),"harvest save failed");state.saved.disconnect(saved)
	await frames(100);await shot("berry-bush-after")
	for slot in [0,1]:
		var loaded:=EmberExploreState.new();loaded.storage_root=state.storage_root;check(loaded.load_slot(slot),"cold load failed");state.adopt_loaded_save(loaded);loaded.free();await frames(2)
		check(bush.get_node("Berries").visible==(slot==0) and bush.is_in_group("ember_interact")== (slot==0),"cold load visual/prompt mismatch")
		check(int(state.inventory.get("forest_berry",0))==(0 if slot==0 else 3),"cold load inventory mismatch")
	var replacement: EmberInteract=load("res://prefabs/items/berry_bush.scn").instantiate();replacement.position.x=80;host.add_child(replacement)
	check(not replacement.get_node("Berries").visible and not replacement.is_in_group("ember_interact"),"recreated generated bush regrew consumed harvest")
	replacement.queue_free()
	var authored: Node3D=load("res://prefabs/items/berry_bush.scn").instantiate();var packed:=PackedScene.new();check(packed.pack(authored)==OK,"pack failed");authored.free()
	check(ResourceSaver.save(packed,"user://berry-bush.scn")==OK,"scene save failed")
	var reopened: Node3D=load("user://berry-bush.scn").instantiate();check(reopened.completion_flag_id==bush.completion_flag_id and reopened.harvest_count==3,"scene data lost");reopened.free()
	var berry: Node3D=load("res://prefabs/items/forest_berry.scn").instantiate();check(berry.validation_errors().is_empty(),"invalid berry physics")
	berry.scale=Vector3.ONE*80;berry.position=Vector3(65,0,0);host.add_child(berry);camera.position=Vector3(88,18,30);camera.look_at(Vector3(65,10,0));await frames(3);await shot("forest-berry-model")
	var icon:=EmberItemCatalog.icon_definition("forest_berry");check(icon.get("rows",[]).size()==16 and icon.rows.all(func(row):return row.length()==16),"bad icon")
	state.persistence_enabled=false;host.queue_free();await process_frame;await process_frame
	print("PASS berry bush: generated source/recipe, automatic wood supports/all presets/determinism/roundtrip, F, stack/combat guards, atomic single save, no repeat, cold states, scene/icon/physics data and native render" if errors.is_empty() else "FAIL berry bush")
	quit(0 if errors.is_empty() else 1)
