extends SceneTree
## L exterior: existing recipe/Source/Canvas pipeline, user:// writes only.
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const Layout=preload("res://addons/ember_import/ember_building_layout.gd")
const Creation=preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
var errors:Array[String]=[]
func _initialize():run.call_deferred()
func world_front_corner(instance: Node3D, source: EmberVoxelModelResource, parameters: Dictionary, path: String) -> Vector3:
	var corner := Layout.front_corner(parameters)
	var grid := Vector2(source.size_blocks.x, source.size_blocks.z)
	var point := corner + grid * 0.5
	return instance.get_node(path).to_global(Vector3(point.x, 0.0, point.y))


func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("WING_FAIL ",label)
func build(recipe:Resource,id:String)->EmberVoxelModelResource:
	var report=Generator.build(recipe,Color.WHITE,{},id,id)
	check(not report.has("error"),str(report.get("error",id)))
	return report.get("geometry")
func sample(source:EmberVoxelModelResource,point:Vector3)->int:
	var cell=Vector3i(point.floor());var grid=source.grid_size()
	return source.voxels[cell.x+grid.x*(cell.z+grid.z*cell.y)]
func roof_preserved(base:EmberVoxelModelResource,wing:EmberVoxelModelResource,settings:Dictionary)->bool:
	var a=base.grid_size();var b=wing.grid_size()
	var shift_z=(b.z-a.z-roundi(settings.wing_length_m*16))/2
	for y in a.y:
		for z in a.z:
			for x in a.x:
				var index=x+a.x*(z+a.z*y)
				if base.voxel_part_ids[index] not in [3,4]:continue
				var target=x+b.x*(z+shift_z+b.z*y)
				if wing.voxel_part_ids[target]!=base.voxel_part_ids[index]:return false
	return true


func gable_outer_slope_joins(source: EmberVoxelModelResource, settings: Dictionary) -> bool:
	var grid := source.grid_size()
	var wing := Layout.wing_rect(settings)
	var origin := Layout.model_offset(settings) * 16 + Vector2(grid.x, grid.z) * 0.5
	var join_z := roundi(wing.position.y * 16 + origin.y)
	var outer_x := wing.end.x if settings.wing_side == 1 else wing.position.x
	var direction := -1 if settings.wing_side == 1 else 1
	var samples := 0
	for distance in range(1, roundi(wing.size.x * 8) - 1):
		var x := floori(outer_x * 16 + origin.x + direction * distance)
		for y in grid.y:
			var before := sample(source, Vector3(x, y, join_z - 1)) == 2
			var after := sample(source, Vector3(x, y, join_z)) == 2
			if before != after:
				return false
			if before:
				samples += 1
	return samples > 0


func cross_roof_has_continuous_valley(source: EmberVoxelModelResource, p: Dictionary, opposite: bool) -> bool:
	var packed := EmberVoxelPrefab.prepare_resource(source)
	if packed == null:
		return false
	var prop := packed.instantiate()
	var faces: PackedVector3Array = prop.get_node("Collision/Shape").shape.get_faces()
	prop.free()
	var wing := Layout.wing_rect(p, opposite)
	var right := (int(p.wing_side) == 1) != opposite
	var outer := wing.end.x if right else wing.position.x
	var origin := Layout.model_offset(p) + Vector2(source.size_blocks.x, source.size_blocks.z) * 0.5
	var main_pitch := float(p.roof_height_m) / (float(p.width_m) * 0.5)
	var rise := minf(float(p.roof_height_m) * 0.75, main_pitch * wing.size.x * 0.8)
	var cross_pitch := rise / (wing.size.y * 0.75)
	var eave := 0.25 + float(p.floor_height_m) * int(p.floors) + 3.0 / 16.0
	# A profile across the diagonal must climb away from it in both directions.
	# Sample the published collision so a hole hidden by a preview shader fails.
	for fraction: float in [0.15, 0.25, 0.35]:
		var z := wing.position.y - wing.size.y * fraction
		var cross_height := eave + cross_pitch * (z - wing.position.y + wing.size.y * 0.5)
		var valley_distance := (cross_height - eave) / main_pitch
		for shift: float in [-0.1, 0.0, 0.1]:
			var distance := valley_distance + shift
			var x := outer + (-distance if right else distance)
			var point := Vector2(x, z) + origin
			var hit_y := -INF
			for index in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(
					Vector3(point.x, 12.0, point.y), Vector3(point.x, 0.0, point.y),
					faces[index], faces[index + 1], faces[index + 2]
				)
				if hit is Vector3:
					hit_y = maxf(hit_y, hit.y)
			if absf(hit_y - maxf(cross_height, eave + distance * main_pitch)) > 0.13:
				return false
	return true


func run():
	if DisplayServer.get_name()=="headless":quit(2);return
	# Existing generated assets must still pass the transaction's manual-edit guard.
	for id in ["vox_coastal_house","vox_coastal_house_layout","vox_coastal_house_wing"]:
		var source:EmberVoxelModelResource=load("res://content/voxel_models/"+id+".tres")
		var recipe=Creation.load_recipe(id);var result=Generator.build(recipe,Color.WHITE,{},source.display_name,id)
		check(not result.has("error") and Creation._same_generated_source(result.get("geometry"),source),"unchanged saved house "+id)
	var recipe=Generator.default_recipe(Generator.BUILDING);recipe.structure=Layout.defaults(1);recipe.parameters.fence=true
	var rectangle=build(recipe,"rectangle")
	for side in [1,2]:
		recipe.parameters.wing_side=side
		var source=build(recipe,"wing_%d"%side)
		if source==null:continue
		check(source.validation_errors().is_empty() and source.merge_parts.size()==30,"bounded wing Source")
		check(roof_preserved(rectangle,source,recipe.parameters),"main roof not overwritten by annex roof")
		var grid=source.grid_size();var offset=Layout.model_offset(recipe.parameters)
		var wing=Layout.wing_rect(recipe.parameters);var centre=(wing.get_center()+offset)*16+Vector2(grid.x,grid.z)*.5
		check(sample(source,Vector3(centre.x,10,centre.y))!=0,"wing filled")
		var empty=Vector2(-recipe.parameters.width_m/2+.5 if side==1 else recipe.parameters.width_m/2-.5,recipe.parameters.depth_m/2+recipe.parameters.wing_length_m/2)
		empty=(empty+offset)*16+Vector2(grid.x,grid.z)*.5
		check(sample(source,Vector3(empty.x,10,empty.y))==0,"L courtyard remains empty")
	# Eave height and overhang bound the roof junction, not just its default pose.
	for floors in [1,2]:
		for overhang in [.125,.5]:
			var edge_recipe=recipe.duplicate(true);edge_recipe.parameters.floors=floors;edge_recipe.parameters.overhang_m=overhang
			edge_recipe.parameters.floor_height_m=2.25 if floors==1 else 3.0
			edge_recipe.parameters.wing_side=0;var base=build(edge_recipe,"edge_base")
			edge_recipe.parameters.wing_side=1 if floors==1 else 2
			edge_recipe.parameters.wing_width_m=1.5 if overhang<.5 else 3.0
			edge_recipe.parameters.wing_length_m=1.0 if overhang<.5 else 3.0
			var wing=build(edge_recipe,"edge_wing")
			check(base!=null and wing!=null and roof_preserved(base,wing,edge_recipe.parameters),"roof junction at floor/overhang bounds")
	recipe.parameters.wing_side=1
	var too_many=recipe.duplicate(true)
	too_many.structure.windows.append({"side":5,"t":0.5,"level":0})
	check(Generator.validation_errors(too_many).is_empty(),"annex window fits 32 parts")
	too_many.structure.windows.append({"side":4,"t":0.5,"level":0})
	check(not Generator.validation_errors(too_many).is_empty(),"34 parts rejected before preparation")
	var covered=recipe.duplicate(true);covered.structure.windows.append({"side":2,"t":0.75,"level":0})
	check(not Generator.validation_errors(covered).is_empty(),"covered rear wall cannot receive a window")
	var upper=recipe.duplicate(true);upper.parameters.floors=2;upper.parameters.fence=false;upper.structure.windows.append({"side":5,"t":0.5,"level":1})
	check(not Generator.validation_errors(upper).is_empty(),"annex upper-storey opening rejected")
	upper.parameters.wing_roof = 1
	for side in [1, 2]:
		upper.parameters.wing_side = side
		upper.parameters.overhang_m = 0.125 if side == 1 else 0.5
		upper.parameters.wing_width_m = 1.5 if side == 1 else 3.0
		var gabled := build(upper, "gable_wing_%d" % side)
		if gabled != null:
			check(gabled.merge_parts.size() <= 32 and gabled.validation_errors().is_empty(), "gable wing fits the existing Source budget")
			check(gable_outer_slope_joins(gabled, upper.parameters), "outer slope meets at the section seam, side %d" % side)
		upper.parameters.wing_roof = 2
		var crossed := build(upper, "cross_wing_%d" % side)
		if crossed != null:
			check(cross_roof_has_continuous_valley(crossed, upper.parameters, false), "cross-gable collision at valley, side %d" % side)
		upper.parameters.wing_roof = 1
	var scene=Node3D.new();root.add_child(scene);current_scene=scene
	var directory="user://ember-tests/building-wing-%d"%OS.get_process_id();var history=UndoRedo.new();var creation=Creation.new()
	creation.source_directory=directory+"/sources";creation.prefab_directory=directory+"/prefabs";creation.recipe_directory=directory+"/recipes"
	var rectangle_recipe=Generator.default_recipe(Generator.BUILDING);rectangle_recipe.structure=Layout.defaults(1);rectangle_recipe.parameters.fence=true
	check(creation.prepare_recipe(rectangle_recipe,"Дом QA","","wing_fixture"),creation.error)
	check(creation.save_to_library(scene,history),creation.error)
	var instance=creation.packed.instantiate();scene.add_child(instance);instance.owner=scene;instance.authoring_source=creation.source;instance.configure_voxel_scale(16,16)
	instance.position = Vector3(50, 10, -20)
	instance.rotation.y = 0.7
	var initial_corner := world_front_corner(instance, creation.source, rectangle_recipe.parameters, "Mesh")
	var anchor=load("res://scripts/ember_building_entrance.gd").new();instance.add_child(anchor);anchor._sync_frame();var initial_anchor=anchor.transform
	var panel=load("res://addons/ember_import/ember_voxel_generator_panel.gd").new();root.add_child(panel);panel.recipe_directory=creation.recipe_directory
	var context={"root":scene,"parent":scene,"position":Vector3.ZERO,"world_size":1.0,"undo":history,"source_directory":creation.source_directory,"prefab_directory":creation.prefab_directory}
	check(panel.open_source(creation.source,context),"open real recipe panel")
	var field=panel._building_plan;field.mode=4
	var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	field._handle(press,Vector2(2.25,1.75));var motion=InputEventMouseMotion.new();field._handle(motion,Vector2(2.25,3))
	check(panel.recipe.parameters.wing_side==0 and field._draft.wing_length_m==2.5,"annex gesture draft")
	var release=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;field._handle(release,Vector2(2.25,3))
	check(panel.recipe.parameters.wing_side==1 and panel.recipe.parameters.wing_length_m==2.5,"annex gesture commit")
	panel.undo_parameters();check(panel.recipe.parameters.wing_side==0,"annex gesture one Undo")
	panel.redo_parameters();check(panel.recipe.parameters.wing_length_m==2.5,"annex gesture Redo")
	# The top plan recentres its draft; its visible inner corner must still resize
	# both dimensions correctly through the real Control coordinate conversion.
	field.mode=0;press.position=field._point_to_screen(Vector2(.25,4.25));field._gui_input(press)
	motion.position=field._point_to_screen(Vector2(.5,4.5));field._gui_input(motion)
	check(field._draft.wing_length_m==3 and field._draft.wing_width_m==1.75 and panel.recipe.parameters.wing_length_m==2.5,"2D corner light draft")
	release.position=motion.position;field._gui_input(release)
	check(panel.recipe.parameters.wing_length_m==3 and panel.recipe.parameters.wing_width_m==1.75,"2D inner corner commits length and width")
	panel.undo_parameters();check(panel.recipe.parameters.wing_length_m==2.5 and panel.recipe.parameters.wing_width_m==2,"2D corner one Undo")
	field.mode = 5
	var wing_before := Layout.wing_rect(panel.recipe.parameters)
	var handle := wing_before.get_center()
	press.position = field._point_to_screen(handle)
	field._gui_input(press)
	motion.position = field._point_to_screen(handle - Vector2(1.0, 0.0))
	field._gui_input(motion)
	check(field._draft.wing_inset_m == 1.0 and panel.recipe.parameters.wing_inset_m == 0.0, "wing move remains a draft")
	release.position = motion.position
	field._gui_input(release)
	var shifted := Layout.wing_rect(panel.recipe.parameters)
	check(shifted.position == wing_before.position - Vector2(1.0, 0.0) and shifted.size == wing_before.size, "plan moves wing without resizing")
	check(11 in Layout.wall_ids(panel.recipe.parameters), "uncovered rear wall is selectable")
	panel.undo_parameters()
	check(panel.recipe.parameters.wing_inset_m == 0.0, "wing move is one Undo")
	var protected_layout: Dictionary = panel.recipe.structure.duplicate(true)
	protected_layout.windows.append({"side": 2, "t": 0.4, "level": 0})
	var proposed: Dictionary = panel.recipe.parameters.duplicate(true)
	proposed.wing_inset_m = 1.0
	check(Layout.errors(protected_layout, panel.recipe.parameters).is_empty(), "existing rear window fits before moving")
	check(not Layout.errors(protected_layout, proposed).is_empty(), "move cannot cover an existing rear window")
	panel.redo_parameters()
	var data=panel.recipe.structure.duplicate(true);data.door={"side":5,"t":0.5};data.windows.append({"side":4,"t":0.5,"level":0})
	panel.set_building_layout(panel.recipe.parameters,data);panel._save_mode.select(1);panel.prepare()
	check(panel.creation!=null and panel.creation.source.merge_parts.size()==32,"exact 32-part annex preview")
	var prepared_source: EmberVoxelModelResource = panel.creation.source
	var prepared_parameters: Dictionary = panel.recipe.parameters.duplicate(true)
	var shifted_grid := prepared_source.grid_size()
	var shifted_origin := Layout.model_offset(prepared_parameters) * 16 + Vector2(shifted_grid.x, shifted_grid.z) * 0.5
	var vacant := Vector2(wing_before.end.x - 0.25, shifted.get_center().y) * 16 + shifted_origin
	check(sample(prepared_source, Vector3(vacant.x, 10.0, vacant.y)) == 0, "old wing footprint is open")
	var window := Layout.point(data.windows.back(), prepared_parameters.width_m, prepared_parameters.depth_m, prepared_parameters) * 16 + shifted_origin
	check(sample(prepared_source, Vector3(window.x + 1.0, 27.0, window.y)) == 5, "wing window is painted at its shifted position")
	check(panel.save_variant(),"update annex variant")
	for path in ["Mesh", "Collision/Shape"]:
		check(world_front_corner(instance, prepared_source, prepared_parameters, path).is_equal_approx(initial_corner), "save keeps world corner on " + path)
	anchor._sync_frame();check(anchor.transform!=initial_anchor,"door anchor follows annex")
	var saved_anchor=anchor.transform
	for look in [0,1,2]:instance.set_world_look(look);anchor._sync_frame();check(anchor.transform.is_equal_approx(saved_anchor),"annex anchor stable look%d"%look)
	history.undo();anchor._sync_frame();check(anchor.transform.is_equal_approx(initial_anchor),"annex asset/door Undo")
	history.redo();anchor._sync_frame();check(anchor.transform.is_equal_approx(saved_anchor),"annex asset/door Redo")
	var disk=Creation.load_recipe("wing_fixture",creation.recipe_directory);check(disk.parameters.wing_side==1 and disk.parameters.wing_inset_m==1.0 and disk.structure.door.side==5,"shifted annex recipe fresh reopen")
	var disk_prefab := ResourceLoader.load(creation.prefab_directory.path_join("wing_fixture.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var reopened := disk_prefab.instantiate() as EmberVoxelProp
	scene.add_child(reopened)
	reopened.transform = instance.transform
	reopened.configure_voxel_scale(16, 16)
	check(world_front_corner(reopened, prepared_source, disk.parameters, "Mesh").is_equal_approx(initial_corner), "fresh prefab preserves rotated corner")
	check(panel.open_source(ResourceLoader.load(creation.source_directory+"/wing_fixture.tres","",ResourceLoader.CACHE_MODE_IGNORE_DEEP),context),"annex source fresh reopen")
	field = panel._building_plan
	panel.set_parameter("wing_length_m",2);panel.discard();check(panel.recipe.parameters.wing_length_m==2.5,"discard annex edit")
	panel.set_parameter("wing_length_m", 2)
	panel.set_parameter("width_m", 5)
	panel.set_parameter("fence", false)
	panel.set_parameter("floors", 2)
	var roof_choice := panel.controls["wing_roof"] as OptionButton
	panel.set_parameter("wing_roof", 1)
	check(panel.recipe.parameters.wing_roof == 0, "gabled roof requires the corner position")
	panel.set_parameter("wing_inset_m", 0.0)
	roof_choice.select(1)
	roof_choice.item_selected.emit(1)
	check(panel.recipe.parameters.wing_roof == 1, "roof selector enables the gabled wing")
	panel.undo_parameters()
	check(panel.recipe.parameters.wing_roof == 0, "roof choice Undo restores lean-to")
	panel.redo_parameters()
	var gabled_layout: Dictionary = panel.recipe.structure.duplicate(true)
	gabled_layout.windows.append({"side": 5, "t": 0.5, "level": 1})
	panel.set_building_layout(panel.recipe.parameters, gabled_layout)
	panel.set_parameter("wing_roof", 0)
	check(panel.recipe.parameters.wing_roof == 1, "switch back protects the upper window")
	panel.set_parameter("opposite_wing", true)
	check(not panel.recipe.parameters.opposite_wing, "second wing cannot exceed the part budget")
	var two_wing_layout: Dictionary = panel.recipe.structure.duplicate(true)
	two_wing_layout.windows.remove_at(1)
	two_wing_layout.windows.remove_at(0)
	two_wing_layout.windows.append({"side": 8, "t": 0.5, "level": 0})
	var two_wing_parameters: Dictionary = panel.recipe.parameters.duplicate(true)
	two_wing_parameters.opposite_wing = true
	panel.set_building_layout(two_wing_parameters, two_wing_layout)
	check(panel.recipe.parameters.opposite_wing and Layout.outline(panel.recipe.parameters).size() == 8, "two wings and courtyard in plan")
	panel.set_parameter("opposite_width_m", 3.0)
	check(panel.recipe.parameters.opposite_width_m == 1.5, "reject touching roof overhangs")
	panel.set_parameter("opposite_wing", false)
	check(panel.recipe.parameters.opposite_wing, "cannot remove a wing with a window")
	field.mode = 0
	var second := Layout.wing_rect(panel.recipe.parameters, true)
	field._handle(press, Vector2(second.position.x, second.end.y), true)
	field._handle(motion, Vector2(second.position.x, second.end.y + 0.5), true)
	check(field._draft.opposite_length_m == 2.5 and field._draft.wing_length_m == 2.0, "resize only the selected wing")
	field._handle(release, Vector2(second.position.x, second.end.y + 0.5), true)
	panel.undo_parameters()
	check(panel.recipe.parameters.opposite_length_m == 2.0, "second wing resize is one Undo")
	panel.redo_parameters()
	panel.set_parameter("opposite_roof", 2)
	check(panel.recipe.parameters.opposite_roof == 1, "cross roof cannot exceed the part budget")
	var cross_layout: Dictionary = panel.recipe.structure.duplicate(true)
	cross_layout.windows.remove_at(0)
	panel.set_building_layout(panel.recipe.parameters, cross_layout)
	var second_roof := panel.controls["opposite_roof"] as OptionButton
	second_roof.select(2)
	second_roof.item_selected.emit(2)
	check(panel.recipe.parameters.opposite_roof == 2, "cross roof selectable on the second wing")
	panel.undo_parameters()
	check(panel.recipe.parameters.opposite_roof == 1, "cross roof Undo restores parallel ridge")
	panel.redo_parameters()
	panel._save_mode.select(1)
	panel.prepare()
	if panel.creation == null:
		check(false, "second preview after reopening: " + panel._info.text)
	else:
		var next_source: EmberVoxelModelResource = panel.creation.source
		var next_parameters: Dictionary = panel.recipe.parameters.duplicate(true)
		var grid := next_source.grid_size()
		var origin := Layout.model_offset(next_parameters) * 16 + Vector2(grid.x, grid.z) * 0.5
		for opposite in [false, true]:
			var center := Layout.wing_rect(next_parameters, opposite).get_center() * 16 + origin
			check(sample(next_source, Vector3(center.x, 10, center.y)) == 1, "both wings are built")
		var rear := Layout.edge(2, next_parameters)
		var courtyard: Vector2 = (rear.a + rear.b) * 8 + origin + Vector2(0, 8)
		check(sample(next_source, Vector3(courtyard.x, 10, courtyard.y)) == 0, "courtyard stays open")
		check(panel.save_variant(), "second save after reopening")
		check(world_front_corner(instance, next_source, next_parameters, "Mesh").is_equal_approx(initial_corner), "second edit does not accumulate corner drift")
		disk = Creation.load_recipe("wing_fixture", creation.recipe_directory)
		check(disk.parameters.wing_roof == 1 and disk.parameters.opposite_roof == 2 and disk.parameters.opposite_wing and disk.parameters.opposite_length_m == 2.5, "both wing profiles survive reopening")
		check(disk.structure.windows.back().side == 8 and disk.structure.windows[-2].level == 1, "independent facade openings survive reopening")
		disk.parameters.wing_roof = 2
		var both_crossed := build(disk, "crossed_wings")
		if both_crossed != null:
			check(both_crossed.merge_parts.size() == 32, "two cross roofs fit at the supported budget")
			for opposite in [false, true]:
				check(cross_roof_has_continuous_valley(both_crossed, disk.parameters, opposite), "both valleys survive in the same house")
	var stored_source := ResourceLoader.load(creation.source_directory + "/wing_fixture.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	check(panel.open_source(stored_source, context), "open saved house for side attachment")
	var side_parameters := prepared_parameters.duplicate(true)
	side_parameters.wing_on_side = true
	check(not Layout.errors(data, side_parameters).is_empty(), "attachment protects the covered side window")
	var side_layout: Dictionary = data.duplicate(true)
	side_layout.windows = data.windows.filter(func(opening: Dictionary) -> bool: return opening.side != 1)
	panel.set_building_layout(side_parameters, side_layout)
	check(Layout.wing_turn(panel.recipe.parameters) == 1, "right side attachment selected")
	var side_field = panel._building_plan
	side_field.mode = 5
	var side_center := Layout.wing_rect(panel.recipe.parameters).get_center()
	side_field._handle(press, side_center, true)
	side_field._handle(motion, side_center + Vector2(0.0, 0.5), true)
	side_field._handle(release, side_center + Vector2(0.0, 0.5), true)
	check(panel.recipe.parameters.wing_inset_m == 0.5, "side wing drag follows the side wall")
	panel._save_mode.select(1)
	panel.prepare()
	if panel.creation == null:
		check(false, "side wing preview: " + panel._info.text)
	else:
		var side_source: EmberVoxelModelResource = panel.creation.source
		var parameters: Dictionary = panel.recipe.parameters.duplicate(true)
		var center := Layout.wing_rect(parameters).get_center()
		var grid := side_source.grid_size()
		center = (center + Layout.model_offset(parameters)) * 16 + Vector2(grid.x, grid.z) * 0.5
		check(sample(side_source, Vector3(center.x, 10.0, center.y)) == 1, "side wing volume appears on the selected side")
		check(panel.save_variant(), "side wing save")
		check(world_front_corner(instance, side_source, parameters, "Mesh").is_equal_approx(initial_corner), "side attachment holds the world corner")
		anchor._sync_frame()
		check(anchor.transform.basis.z.is_equal_approx(Vector3.RIGHT), "door faces outward on the right")
		var saved_side := Creation.load_recipe("wing_fixture", creation.recipe_directory)
		check(saved_side.parameters.wing_on_side and saved_side.parameters.wing_inset_m == 0.5 and saved_side.structure.door.side == 5, "side wing and door survive reopen")
		saved_side.parameters.wing_side = 2
		saved_side.structure.windows = side_layout.windows.filter(func(opening: Dictionary) -> bool: return opening.side != 3)
		var left_source := build(saved_side, "left_side_wing")
		if left_source != null:
			check(left_source.solid_surface.building_entry.normal == Vector3.LEFT, "mirrored door faces outward")
	print("BUILDING_WING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"main_roof_voxel_coverage":"preserved","max_parts":32}))
	panel.queue_free();scene.queue_free();history.clear_history();history.free()
	for i in 5:await process_frame
	quit(0 if errors.is_empty() else 1)
