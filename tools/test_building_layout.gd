extends SceneTree
## Building plan gestures/recipe/save checks. Writes fixtures only under user://.
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const Layout=preload("res://addons/ember_import/ember_building_layout.gd")
const Creation=preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const RecipePanel=preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
var errors:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("LAYOUT_FAIL ",label)

func check_canopy(source: EmberVoxelModelResource, recipe: Resource) -> void:
	var p: Dictionary = recipe.parameters
	var door: Dictionary = recipe.structure.door
	var grid := source.grid_size()
	var center := (Layout.point(door, p.width_m, p.depth_m, p) + Layout.model_offset(p)) * 16.0
	center += Vector2(grid.x, grid.z) * 0.5
	var normal: Vector3 = Layout.edge(door.side, p).normal
	var outside := Vector3(center.x, 36.0, center.y) + normal * 5.0
	var cell := Vector3i(outside.floor())
	var roof_index := cell.x + grid.x * (cell.z + grid.z * cell.y)
	var roof_owner := source.voxel_part_ids[roof_index]
	check(roof_owner > 0 and source.merge_parts[roof_owner - 1] == "Вход · кровля козырька", "canopy follows the current doorway normal")
	var clearance_index := cell.x + grid.x * (cell.z + grid.z * 31)
	check(source.voxels[clearance_index] == 0, "entry is open below the canopy")
	check(source.merge_parts.count("Вход · деревянный раскос") == 2, "canopy uses two timber brackets")


func window_sample(source: EmberVoxelModelResource, recipe: Resource, across: float, up: float, outward := 1.5) -> int:
	var p: Dictionary = recipe.parameters
	var grid := source.grid_size()
	var opening: Dictionary = recipe.structure.windows[0]
	var center := (Layout.point(opening, p.width_m, p.depth_m, p) + Layout.model_offset(p)) * 16.0
	center += Vector2(grid.x, grid.z) * 0.5
	var y := 4.0 + float(p.floor_height_m) * 16.0 * 0.38
	var cell := Vector3i(Vector3(center.x + across, y + up, center.y - outward).floor())
	return source.voxels[cell.x + grid.x * (cell.z + grid.z * cell.y)]


func entry_sample(source: EmberVoxelModelResource, recipe: Resource, across: float, y: float, outward: float) -> int:
	var p: Dictionary = recipe.parameters
	var door: Dictionary = recipe.structure.door
	var grid := source.grid_size()
	var center := (Layout.point(door, p.width_m, p.depth_m, p) + Layout.model_offset(p)) * 16.0
	center += Vector2(grid.x, grid.z) * 0.5
	var normal: Vector3 = Layout.edge(door.side, p).normal
	var point := Vector3(center.x, y, center.y) + normal * outward + normal.cross(Vector3.UP) * across
	var cell := Vector3i(point.floor())
	return source.voxels[cell.x + grid.x * (cell.z + grid.z * cell.y)]


func facade_part_at(source: EmberVoxelModelResource, recipe: Resource, detail: Dictionary, y: float, outward := 1.5, along := 0.0) -> String:
	var profile := Layout.facade_detail_profile(detail, recipe.parameters)
	var grid := source.grid_size()
	var center: Vector2 = ((profile.from + profile.to) * 0.5 + Layout.model_offset(recipe.parameters)) * 16.0
	center += Vector2(grid.x, grid.z) * 0.5
	var normal: Vector3 = profile.normal
	var position := Vector3(center.x, y * 16.0, center.y) + normal * outward + normal.cross(Vector3.UP) * along
	var cell := Vector3i(position.floor())
	var id := source.voxel_part_ids[cell.x + grid.x * (cell.z + grid.z * cell.y)]
	return source.merge_parts[id - 1] if id > 0 else ""


func fence_and_gate(source: EmberVoxelModelResource, recipe: Resource) -> Dictionary:
	var grid := source.grid_size()
	var gate_id := source.merge_parts.find("Калитка · открыта") + 1
	var owners := source.voxel_part_ids
	var colors := source.voxels
	var p: Dictionary = recipe.parameters
	var door: Dictionary = recipe.structure.door
	var point := (Layout.point(door, p.width_m, p.depth_m, p) + Layout.model_offset(p)) * 16.0
	point += Vector2(grid.x, grid.z) * 0.5
	var normal: Vector3 = Layout.edge(door.side, p).normal
	var along_x := normal.z != 0.0
	var center := clampf(point.x, 12.0, grid.x - 12.0) if along_x else clampf(point.y, 12.0, grid.z - 12.0)
	var fence_floor := PackedInt32Array()
	var gate_floor := PackedInt32Array()
	var gate := PackedInt32Array()
	var fence_top := 0
	var fence_color := 0
	var gate_clear := true
	var capsule_radius := EmberExplorationHeroScale.collision_radius(1.0) * 16.0
	for y in 16:
		for z in grid.z:
			for x in grid.x:
				var index := x + grid.x * (z + grid.z * y)
				var id := owners[index]
				if id == 0:
					continue
				if id == gate_id:
					gate.append(index)
					if y == 1:
						gate_floor.append(index)
					var along := float(x if along_x else z)
					gate_clear = gate_clear and (along + 1.0 <= center - capsule_radius or along >= center + capsule_radius)
				elif source.merge_parts[id - 1].begins_with("Ограда ·"):
					fence_top = y + 1
					fence_color = colors[index]
					if y == 0:
						fence_floor.append(index)
	return {"fence_floor": fence_floor, "gate_floor": gate_floor, "gate": gate,
		"fence_top": fence_top, "fence_color": fence_color, "gate_clear": gate_clear}


func roof_top(source: EmberVoxelModelResource, point: Vector2) -> int:
	var grid := source.grid_size()
	var voxels := source.voxels
	var x := floori(point.x)
	var z := floori(point.y)
	for y in range(grid.y - 1, -1, -1):
		if voxels[x + grid.x * (z + grid.z * y)] != 0:
			return y + 1
	return 0


func local_building_entry(source: EmberVoxelModelResource) -> Vector3:
	var grid := source.grid_size()
	var point: Vector3 = source.solid_surface.building_entry.point
	var offset: Vector3 = source.solid_surface.get("building_offset", Vector3.ZERO)
	return (point - Vector3(grid.x, 0, grid.z) * 0.5) / 16.0 + offset


func run():
	if DisplayServer.get_name()=="headless":quit(2);return
	var scene=Node3D.new();root.add_child(scene);current_scene=scene
	var recipe=Generator.default_recipe(Generator.BUILDING);recipe.structure=Layout.defaults(1)
	check(Generator.validation_errors(recipe).is_empty(),"default structural plan")
	var invalid=recipe.duplicate(true);invalid.structure.windows[0].t=NAN
	check(not Generator.validation_errors(invalid).is_empty(),"non-finite window rejected")
	invalid=recipe.duplicate(true);invalid.structure.door.t=invalid.structure.windows[0].t
	check(not Generator.validation_errors(invalid).is_empty(),"overlapping opening rejected")
	invalid=recipe.duplicate(true);invalid.parameters.width_m=3.0;invalid.structure={"version":1,"windows":[],"door":{"side":0,"t":0.12}}
	check(not Generator.validation_errors(invalid).is_empty(),"frame crossing wall edge rejected")
	var cramped = recipe.duplicate(true)
	cramped.parameters.width_m = 4.25
	cramped.parameters.wing_side = 1
	cramped.parameters.opposite_wing = true
	cramped.structure.door = {"side": 6, "t": 0.5}
	check(Generator.validation_errors(cramped).is_empty(), "door fits the courtyard before adding a canopy")
	cramped.parameters.entry_style = 2
	var courtyard: EmberVoxelModelResource = Generator.build(cramped, Color.WHITE, {}, "Courtyard", "courtyard").geometry
	check(entry_sample(courtyard, cramped, 0.5, 34.5, 1.5) == 4, "stone arch follows the door on an annex wall")
	cramped.parameters.entry_canopy = true
	check(not Generator.validation_errors(cramped).is_empty(), "canopy cannot hit the other wing's roof")
	var full = Creation.load_recipe("vox_coastal_house_wing")
	full.parameters.entry_canopy = true
	check(not Generator.validation_errors(full).is_empty(), "canopy must fit the existing part budget")
	full.parameters.entry_canopy = false
	full.parameters.entry_style = 2
	var full_source: EmberVoxelModelResource = Generator.build(full, Color.WHITE, {}, "Wing entry", "wing_entry").geometry
	check(full_source.merge_parts.size() == 32, "entry arch fits the full wing recipe part budget")
	check(entry_sample(full_source, full, 7.5, 15.5, 1.5) == 4, "portal fits the side door on the published house")
	var roof_recipe: Resource = full.duplicate(true)
	roof_recipe.parameters.roof_shape = Layout.ROOF_FLAT
	var flat: EmberVoxelModelResource = Generator.build(roof_recipe, Color.WHITE, {}, "Flat roof", "flat_roof").geometry
	var grid := flat.grid_size()
	var center := Layout.model_offset(roof_recipe.parameters) * 16.0 + Vector2(grid.x, grid.z) * 0.5
	var deck := roof_top(flat, center)
	check(deck == grid.y and roof_top(flat, center + Vector2(20, 15)) == deck, "flat roof has one level deck on the main house")
	check(roof_top(flat, center + Vector2(25, 36)) < deck, "low wing keeps its own lower roof")
	roof_recipe.parameters.roof_shape = Layout.ROOF_PARAPET
	check(not Generator.validation_errors(roof_recipe).is_empty(), "parapet respects the 32 part limit")
	roof_recipe.parameters.fence = false
	var parapet: EmberVoxelModelResource = Generator.build(roof_recipe, Color.WHITE, {}, "Parapet", "parapet_roof").geometry
	grid = parapet.grid_size()
	center = Layout.model_offset(roof_recipe.parameters) * 16.0 + Vector2(grid.x, grid.z) * 0.5
	check(roof_top(parapet, center) == deck, "parapet leaves the center open above the deck")
	for side in [Vector2(37, 0), Vector2(-38, 0), Vector2(0, 29), Vector2(0, -30)]:
		check(roof_top(parapet, center + side) == deck + 8, "parapet rises on each edge")
	roof_recipe.parameters.wing_roof = 1
	check(not Generator.validation_errors(roof_recipe).is_empty(), "flat main roof rejects a gabled wing with an unsupported join")
	full.structure.facade_details = [{"kind": "column", "side": 5, "level": 0, "t": 0.2}]
	check(not Generator.validation_errors(full).is_empty(), "facade details use the existing part budget")
	full.parameters.fence = false
	check(Generator.validation_errors(full).is_empty(), "a column fits on the annex once the fence budget is freed")
	var wing_facade: EmberVoxelModelResource = Generator.build(full, Color.WHITE, {}, "Wing facade", "wing_facade").geometry
	check(facade_part_at(wing_facade, full, full.structure.facade_details[0], 1.5) == "Фасад · колонна", "annex column is baked on its own wall")
	var bad_details: Resource = full.duplicate(true)
	bad_details.structure.facade_details[0].t = NAN
	check(not Generator.validation_errors(bad_details).is_empty(), "non-finite facade anchor rejected")
	for side in 4:
		var fenced = recipe.duplicate(true)
		fenced.structure = {"version": 1, "windows": [], "door": {"side": side, "t": 0.5}}
		fenced.parameters.fence = true
		var wood: EmberVoxelModelResource = Generator.build(fenced, Color.WHITE, {}, "Wood fence", "wood_fence").geometry
		var wood_parts := fence_and_gate(wood, fenced)
		check(wood_parts.fence_top == 16 and wood_parts.fence_color == 3, "default fence is wood at the original height")
		check(not wood_parts.gate_floor.is_empty() and wood_parts.gate_clear, "rotated gate leaves walking clearance on wall %d" % side)
		fenced.parameters.fence_style = 1
		fenced.parameters.gate_style = 1
		var stone: EmberVoxelModelResource = Generator.build(fenced, Color.WHITE, {}, "Stone fence", "stone_fence").geometry
		var stone_parts := fence_and_gate(stone, fenced)
		check(stone_parts.fence_top == 10 and stone_parts.fence_color == 4, "stone fence is lower and uses masonry")
		check(stone_parts.fence_floor == wood_parts.fence_floor and stone_parts.gate_floor == wood_parts.gate_floor, "styles keep the fence line, gap and hinge on wall %d" % side)
		check(stone_parts.gate.size() < wood_parts.gate.size() and stone_parts.gate_clear, "chamfer removes only the upper gate corners")
		check(stone.merge_parts.size() == wood.merge_parts.size() and stone.solid_surface.building_entry == wood.solid_surface.building_entry, "styles keep budget and entry")
	var from_mesh=ArrayMesh.new();var to_mesh=ArrayMesh.new()
	from_mesh.set_meta("solid_surface_contract",1);to_mesh.set_meta("ember_building_entry",{})
	EmberVoxelPrefab._copy_mesh_surfaces(to_mesh,from_mesh)
	check(not to_mesh.has_meta("ember_building_entry"),"old entry metadata removed on mesh replacement")
	var history=UndoRedo.new();var creation=Creation.new();var directory="user://ember-tests/building-layout-%d"%OS.get_process_id()
	creation.source_directory=directory+"/sources";creation.prefab_directory=directory+"/prefabs";creation.recipe_directory=directory+"/recipes"
	check(creation.prepare_recipe(recipe,"Дом с планом","","plan_house"),creation.error)
	check(creation.save_to_library(scene,history),creation.error)
	var instance=creation.packed.instantiate();scene.add_child(instance);instance.configure_voxel_scale(16,1.0)
	var anchor=load("res://scripts/ember_building_entrance.gd").new();anchor.name="BuildingEntrance";instance.add_child(anchor)
	anchor._sync_frame();var first_anchor=anchor.transform
	var path=creation.source_directory+"/plan_house.tres";var baseline=FileAccess.get_file_as_bytes(path)
	var panel=RecipePanel.new();root.add_child(panel);panel.recipe_directory=creation.recipe_directory
	var context={"root":scene,"parent":scene,"position":Vector3.ZERO,"world_size":1.0,"undo":history,"source_directory":creation.source_directory,"prefab_directory":creation.prefab_directory}
	check(panel.open_source(creation.source,context),"open structural recipe")
	var field=panel._building_plan;check(field!=null,"shared plan field")
	var before=panel.recipe.duplicate(true);var params=before.parameters.duplicate(true);params.width_m=5.0
	panel.set_building_layout(params,before.structure)
	check(panel.recipe.parameters.width_m==5.0 and panel.creation==null,"light preview changes recipe without mesh build")
	panel.undo_parameters();check(panel.recipe.parameters.width_m==4.5,"one gesture Undo")
	panel.redo_parameters();check(panel.recipe.parameters.width_m==5.0,"gesture Redo")
	var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	field.mode=0;field._handle(event,Vector2(2.5,1.75))
	var motion=InputEventMouseMotion.new();field._handle(motion,Vector2(3,2))
	check(field._drag and panel.recipe.parameters.width_m==5.0,"drag holds uncommitted draft")
	check(panel.cancel_building_gesture() and panel.recipe.parameters.width_m==5.0,"Escape cancels draft")
	field.mode=2;field._handle(event,Vector2(2.5,-1.25))
	check(panel.recipe.structure.door.side==1,"door on side wall")
	panel.undo_parameters();check(panel.recipe.structure.door.side==0,"door change Undo")
	field.mode=1;field._handle(event,Vector2(0,1.75))
	check(panel.recipe.structure.windows.size()==5,"window placement on back wall")
	field.mode=3;field._handle(event,Vector2(0,1.75));check(panel.recipe.structure.windows.size()==4,"window eraser")
	field.mode = field.COLUMN
	field._handle(event, Vector2(0, -1.75))
	check(not panel.recipe.structure.has("facade_details"), "column cannot cover the front entrance")
	field._handle(event, Vector2(-2.0, -1.75))
	check(panel.recipe.structure.get("facade_details", []).size() == 1, "place a column on the front wall")
	field.mode = field.BEAM
	field._handle(event, Vector2(-2.0, -1.75))
	field._handle(motion, Vector2(2.0, -1.75))
	check(panel.recipe.structure.facade_details.size() == 1, "beam drag leaves recipe untouched")
	check(panel.cancel_building_gesture(), "Escape cancels a drafted beam")
	field._handle(event, Vector2(-2.0, -1.75))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	field._handle(release, Vector2(2.0, -1.75))
	check(panel.recipe.structure.facade_details.size() == 2, "one release commits the beam")
	panel.undo_parameters()
	check(panel.recipe.structure.facade_details.size() == 1, "one Undo removes the beam")
	panel.redo_parameters()
	field.mode = field.ERASE_DETAIL
	field._handle(event, Vector2(-2.0, -1.75))
	check(panel.recipe.structure.facade_details.size() == 1 and panel.recipe.structure.facade_details[0].kind == "beam", "erase picks the column where it meets the beam")
	panel.undo_parameters()
	var detail: Dictionary = panel.recipe.structure.facade_details[0]
	var resized: Dictionary = panel.recipe.parameters.duplicate(true)
	resized.width_m = 5.25
	var before_resize := Layout.facade_detail_profile(detail, panel.recipe.parameters)
	panel.set_building_layout(resized, panel.recipe.structure)
	var after_resize := Layout.facade_detail_profile(panel.recipe.structure.facade_details[0], panel.recipe.parameters)
	check(panel.recipe.parameters.width_m == 5.25 and after_resize.from.x < before_resize.from.x, "column follows the resized wall")
	panel.undo_parameters()
	var moved=panel.recipe.structure.duplicate(true);moved.door={"side":1,"t":0.15};panel.set_building_layout(panel.recipe.parameters,moved)
	var canopy := panel.controls.entry_canopy as CheckButton
	canopy.button_pressed = true
	check(panel.recipe.parameters.entry_canopy and panel.recipe.structure == moved, "canopy toggle keeps the facade layout")
	panel.undo_parameters()
	check(not panel.recipe.parameters.entry_canopy, "canopy Undo")
	panel.redo_parameters()
	panel.controls.fence.button_pressed=true;panel.controls.facade_style.select(1);panel.set_parameter("facade_style",1)
	var roof_style := panel.controls.roof_shape as OptionButton
	roof_style.select(Layout.ROOF_HIP)
	roof_style.item_selected.emit(Layout.ROOF_HIP)
	panel.undo_parameters()
	check(panel.recipe.parameters.get("roof_shape", Layout.ROOF_GABLE) == Layout.ROOF_GABLE, "roof type Undo")
	panel.redo_parameters()
	check(panel.recipe.parameters.roof_shape == Layout.ROOF_HIP and panel.recipe.structure == moved, "roof type Redo keeps the plan")
	var original_source: EmberVoxelModelResource = Generator.build(panel.recipe, Color.WHITE, {}, "Original", "window_styles").geometry
	grid = original_source.grid_size()
	center = Vector2(grid.x, grid.z) * 0.5
	var apex := roof_top(original_source, center)
	for side in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 14), Vector2(0, -14)]:
		check(roof_top(original_source, center + side) < apex, "hip roof slopes towards every side from one central apex")
	var default_fence := fence_and_gate(original_source, panel.recipe)
	var fence_style := panel.controls.fence_style as OptionButton
	var gate_style := panel.controls.gate_style as OptionButton
	fence_style.select(1)
	fence_style.item_selected.emit(1)
	gate_style.select(2)
	gate_style.item_selected.emit(2)
	panel.undo_parameters()
	check(panel.recipe.parameters.gate_style == 0 and panel.recipe.parameters.fence_style == 1, "gate style has its own Undo")
	panel.redo_parameters()
	check(panel.recipe.parameters.gate_style == 2 and panel.recipe.structure == moved, "style switches leave the plan alone")
	var style := panel.controls.window_style as OptionButton
	style.select(1)
	style.item_selected.emit(1)
	var stone_source: EmberVoxelModelResource = Generator.build(panel.recipe, Color.WHITE, {}, "Stone", "window_styles").geometry
	check(window_sample(stone_source, panel.recipe, 5.0, 8.0) == 4, "stone window uses the masonry slot")
	check(window_sample(stone_source, panel.recipe, 5.0, 8.0, 2.5) == 0, "stone frame chamfer trims the front corner")
	style.select(2)
	style.item_selected.emit(2)
	panel.undo_parameters()
	check(panel.recipe.parameters.window_style == 1, "window style Undo")
	panel.redo_parameters()
	check(panel.recipe.parameters.window_style == 2 and panel.recipe.structure == moved, "window style Redo keeps the layout")
	var entry_style := panel.controls.entry_style as OptionButton
	entry_style.select(1)
	entry_style.item_selected.emit(1)
	var portal_recipe: Resource = panel.recipe.duplicate(true)
	portal_recipe.parameters.entry_canopy = false
	var portal: EmberVoxelModelResource = Generator.build(portal_recipe, Color.WHITE, {}, "Portal", "entry_styles").geometry
	check(entry_sample(portal, portal_recipe, 7.5, 33.5, 1.5) == 4, "straight portal keeps the upper stone corner")
	check(entry_sample(portal, portal_recipe, 7.5, 33.5, 2.5) == 0, "straight portal bevels the front stone edge")
	entry_style.select(2)
	entry_style.item_selected.emit(2)
	panel.undo_parameters()
	check(panel.recipe.parameters.entry_style == 1, "entry style Undo")
	panel.redo_parameters()
	check(panel.recipe.parameters.entry_style == 2 and panel.recipe.structure == moved, "entry style Redo keeps the layout")
	panel._save_mode.select(1);panel.prepare();check(panel.creation!=null,"exact prepared plan")
	check(FileAccess.get_file_as_bytes(path)==baseline,"preview keeps Source read-only")
	if panel.creation!=null:
		check(panel.creation.source.validation_errors().is_empty(),"layout and fence Source valid")
		check_canopy(panel.creation.source, panel.recipe)
		var arch: EmberVoxelModelResource = panel.creation.source
		var arched_gate := fence_and_gate(arch, panel.recipe)
		check(arched_gate.fence_floor == default_fence.fence_floor and arched_gate.gate_floor == default_fence.gate_floor, "arched gate keeps the same footing and fence gap")
		check(arched_gate.gate.size() < default_fence.gate.size() and arched_gate.gate_clear, "arched crown changes the gate without blocking the center")
		var preview := panel.creation.packed.instantiate() as EmberVoxelProp
		preview.position.x = 30.0
		scene.add_child(preview)
		preview.configure_voxel_scale(16, 1.0)
		await physics_frame
		await physics_frame
		var collider := preview.get_node("Collision/Shape") as CollisionShape3D
		var collision_grid := arch.grid_size()
		var door_center := float(collision_grid.z) * 0.5 + 16.0 * (Layout.point(moved.door, panel.recipe.parameters.width_m,
			panel.recipe.parameters.depth_m, panel.recipe.parameters) + Layout.model_offset(panel.recipe.parameters)).y
		var start := collider.to_global(Vector3(collision_grid.x + 4.0, 7.0, door_center) / 16.0)
		var player_shape := CapsuleShape3D.new()
		player_shape.radius = EmberExplorationHeroScale.collision_radius(1.0)
		player_shape.height = 0.75
		var sweep := PhysicsShapeQueryParameters3D.new()
		sweep.shape = player_shape
		sweep.transform = Transform3D(Basis.IDENTITY, start)
		sweep.motion = Vector3.LEFT * 0.75
		var space := preview.get_world_3d().direct_space_state
		var clear := space.cast_motion(sweep)
		check(clear.size() == 2 and clear[0] == 1.0, "player capsule fits the actual preview collider at the gate")
		sweep.transform = Transform3D(Basis.IDENTITY, start + Vector3.BACK * 0.875)
		var blocked := space.cast_motion(sweep)
		check(blocked.size() == 2 and blocked[0] < 1.0, "stone fence blocks the capsule beside the gate")
		preview.queue_free()
		check(facade_part_at(arch, panel.recipe, moved.facade_details[0], 1.5) == "Фасад · колонна", "preview contains a column on the chosen wall")
		check(facade_part_at(arch, panel.recipe, moved.facade_details[1], 2.75) == "Фасад · балка", "preview contains the beam span")
		check(entry_sample(arch, panel.recipe, 5.5, 33.5, 1.5) == 0, "arch cuts the upper stone corner")
		check(entry_sample(arch, panel.recipe, 0.5, 34.5, 1.5) == 4, "arch keeps the stone crown")
		check(entry_sample(arch, panel.recipe, 0.5, 28.5, 3.5) == 3, "wooden door fills the arch on the same side as the canopy")
		check(window_sample(original_source, panel.recipe, 5.0, 15.0) == 3 and window_sample(arch, panel.recipe, 5.0, 15.0) == 0, "arch removes the square upper corner")
		check(window_sample(arch, panel.recipe, 0.0, 15.0) == 3, "arch keeps the high center")
		check(arch.merge_parts.size() == original_source.merge_parts.size() and arch.solid_surface.building_entry == original_source.solid_surface.building_entry, "window styles keep part count and entrance frame")
		var broken=panel.creation.source.duplicate_model();broken.solid_surface.building_entry.point=Vector3(NAN,0,0)
		check(not broken.validation_errors().is_empty(),"invalid baked entrance rejected")
		check(panel.creation.source.merge_parts.has("Калитка · открыта"),"open gate published")
		check(panel.save_variant(),"save structural variant")
		anchor._sync_frame();check(anchor.position.x>2.5 and anchor.transform!=first_anchor,"published entrance follows moved facade door")
		for look in [0,1,2]:
			instance.set_world_look(look);anchor._sync_frame();check(anchor.position.x>2.5,"entry frame stable look%d"%look)
		var disk=Creation.load_recipe("plan_house",creation.recipe_directory)
		check(disk.structure==panel.recipe.structure and disk.parameters.fence and disk.parameters.entry_canopy,"fresh structural recipe reopen")
		check(disk.parameters.window_style == 2, "arch window style survives reopening")
		check(disk.parameters.entry_style == 2, "entry arch survives reopening")
		check(disk.parameters.roof_shape == Layout.ROOF_HIP, "main roof survives reopening")
		check(disk.parameters.fence_style == 1 and disk.parameters.gate_style == 2, "both independent fence styles survive reopening")
		check(disk.structure.facade_details == moved.facade_details, "facade anchors survive reopening")
		var saved=FileAccess.get_file_as_bytes(path)
		history.undo()
		var undone=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(undone.voxels==creation.source.voxels and Creation.load_recipe("plan_house",creation.recipe_directory).parameters.width_m==4.5,"Source and recipe Undo")
		anchor._sync_frame();check(anchor.transform.is_equal_approx(first_anchor),"entry frame Undo")
		history.redo()
		check(Creation.load_recipe("plan_house",creation.recipe_directory).parameters.width_m==5.0 and Creation.load_recipe("plan_house",creation.recipe_directory).parameters.fence,"Source and recipe Redo")
		anchor._sync_frame();check(anchor.position.x>2.5,"entry frame Redo")
		saved=FileAccess.get_file_as_bytes(path)
		var source=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(source.solid_surface.has("building_entry"),"baked entrance serialized")
		check(source.voxels == arch.voxels and source.voxel_part_ids == arch.voxel_part_ids, "published entry geometry matches preview")
		check(panel.open_source(source,context),"fresh panel reopen")
		var original=panel.recipe.structure.duplicate(true);var next=original.duplicate(true);next.windows.remove_at(0)
		next.erase("facade_details")
		panel.set_building_layout(panel.recipe.parameters,next)
		panel.set_parameter("entry_style", 0)
		panel.set_parameter("fence_style", 0)
		panel.set_parameter("gate_style", 0)
		panel.set_parameter("roof_shape", Layout.ROOF_FLAT)
		panel.discard()
		check(panel.recipe.structure==original and panel.recipe.parameters.entry_style == 2 and FileAccess.get_file_as_bytes(path)==saved,"discard plan and entry edits")
		check(panel.recipe.parameters.fence_style == 1 and panel.recipe.parameters.gate_style == 2, "discard restores both fence styles")
		check(panel.recipe.parameters.roof_shape == Layout.ROOF_HIP, "discard restores the main roof")
	var workspace=load("res://addons/ember_import/ember_voxel_generation_panel.gd").new();root.add_child(workspace)
	workspace._select_provider(workspace.PROVIDERS.find(Generator.BUILDING))
	check(is_instance_valid(workspace._building_plan),"same plan in creation workspace")
	workspace.set_building_layout(recipe.parameters,recipe.structure)
	check(workspace.recipe.structure==recipe.structure,"creation keeps structure")
	check(workspace.controls.entry_style is OptionButton,"creation exposes the same entry styles")
	check(workspace.controls.fence_style is OptionButton and workspace.controls.gate_style is OptionButton,"creation exposes the same fence styles")
	workspace._preset.select(2)
	workspace._preset.item_selected.emit(2)
	check(workspace.recipe.parameters.opposite_wing and workspace.recipe.structure.get("facade_details", []).size() == 2, "estate preset keeps the courtyard and balcony plan")
	workspace.history.undo()
	check(not workspace.recipe.parameters.opposite_wing, "estate preset Undo")
	workspace.history.redo()
	var estate_plan: Dictionary = workspace.recipe.structure.duplicate(true)
	var estate_field: Control = workspace._building_plan
	estate_field.level = 1
	estate_field.mode = estate_field.ERASE_DETAIL
	estate_field._handle(event, Vector2(0, -2.95))
	check(workspace.recipe.structure.facade_details.size() == 1, "remove a balcony on the second floor")
	estate_field.mode = estate_field.BALCONY
	estate_field._handle(event, Vector2(0, -2.5))
	check(workspace.recipe.structure.facade_details.size() == 2, "place balcony back over the entrance")
	workspace.history.undo()
	check(workspace.recipe.structure.facade_details.size() == 1, "balcony placement has one Undo")
	workspace.history.redo()
	var overcrowded: Resource = workspace.recipe.duplicate(true)
	overcrowded.parameters.corner_posts = true
	check(not Generator.validation_errors(overcrowded).is_empty(), "estate validates the balcony part budget before baking")
	var invalid_balcony: Resource = workspace.recipe.duplicate(true)
	invalid_balcony.structure.facade_details[0].level = 0
	check(not Generator.validation_errors(invalid_balcony).is_empty(), "balcony needs an upper wall")
	workspace.presets.directory = directory + "/presets"
	var estate_preset_path: String = workspace.presets.save_preset(workspace.recipe, "Усадьба")
	check(not estate_preset_path.is_empty() and workspace.presets.list_presets(Generator.BUILDING)[0].recipe.structure == workspace.recipe.structure, "saved building preset preserves the edited layout")
	workspace.session.source_directory = creation.source_directory
	workspace.session.prefab_directory = creation.prefab_directory
	workspace.session.recipe_directory = creation.recipe_directory
	check(workspace.session.begin(workspace.recipe, "Усадьба", 1, 0), "start estate generation")
	var estate_candidate: Dictionary = workspace.session.step()
	check(not estate_candidate.is_empty(), workspace.session.error)
	if not estate_candidate.is_empty():
		var estate: EmberVoxelModelResource = estate_candidate.creation.source
		var estate_recipe: Resource = estate_candidate.creation.recipe
		check(estate.merge_parts.size() == 31 and estate.merge_parts.count("Балкон · плита") == 2, "two guarded balconies fit with the wings and windows")
		var estate_grid := estate.grid_size()
		var estate_center := Layout.model_offset(estate_recipe.parameters) * 16.0 + Vector2(estate_grid.x, estate_grid.z) * 0.5
		check(roof_top(estate, estate_center + Vector2(0, 64)) == 0, "courtyard is open to the rear")
		check(roof_top(estate, estate_center + Vector2(-44, 64)) > 0 and roof_top(estate, estate_center + Vector2(44, 64)) > 0, "courtyard has a wing on both sides")
		for balcony: Dictionary in estate_plan.facade_details:
			check(facade_part_at(estate, estate_recipe, balcony, 2.6875) == "Балкон · плита", "balcony deck is attached to the correct wall")
		estate_recipe.parameters.erase("balcony_width_m")
		estate_recipe.parameters.erase("balcony_depth_m")
		check(estate_candidate.creation.save_to_library(scene, history), estate_candidate.creation.error)
		var reopened_estate := Creation.load_recipe(estate.model_id, creation.recipe_directory)
		check(reopened_estate != null and reopened_estate.structure == estate_recipe.structure, "estate plan survives publishing and reopening")
		check(panel.open_source(estate, context), "published estate opens for editing")
		var changed_estate: Dictionary = panel.recipe.structure.duplicate(true)
		changed_estate.facade_details.pop_back()
		panel.set_building_layout(panel.recipe.parameters, changed_estate)
		panel.discard()
		check(panel.recipe.structure == reopened_estate.structure, "discard restores published estate balconies")
		panel.set_parameter("balcony_width_m", 2.5)
		check(panel.recipe.parameters.balcony_width_m == 1.5, "a balcony may not cover a courtyard wing")
		panel.set_parameter("balcony_width_m", 2.25)
		panel.set_parameter("balcony_depth_m", 1.0)
		panel.undo_parameters()
		check(panel.recipe.parameters.balcony_depth_m == 0.875, "balcony depth Undo")
		panel.redo_parameters()
		panel._save_mode.select(1)
		panel.prepare()
		check(panel.creation != null, "resize fits the estate source budget")
		if panel.creation != null:
			var resized_estate: EmberVoxelModelResource = panel.creation.source
			var front_balcony: Dictionary = estate_plan.facade_details[0]
			check(facade_part_at(estate, estate_recipe, front_balcony, 2.6875, 15.5, 16.5) != "Балкон · плита", "old deck keeps its old dimensions")
			check(facade_part_at(resized_estate, panel.recipe, front_balcony, 2.6875, 15.5, 16.5) == "Балкон · плита", "resized deck extends both outward and along the wall")
			check(panel.save_variant(), "resize a balcony on a legacy estate in place")
			var resized_disk := Creation.load_recipe(estate.model_id, creation.recipe_directory)
			check(resized_disk.parameters.balcony_width_m == 2.25 and resized_disk.parameters.balcony_depth_m == 1.0 and resized_disk.structure == reopened_estate.structure, "sizes reopen with the same balcony anchors")
	var yard_recipe: Resource = load("res://content/editor/voxel_generator_presets/canal_courtyard_house.tres").duplicate(true)
	yard_recipe.parameters = Generator.normalized_parameters(Generator.BUILDING, yard_recipe.parameters)
	var yard_plan := Layout.fence_plan(yard_recipe.parameters, yard_recipe.structure.door)
	check(yard_plan.segments.size() == 5, "canal house starts with room around the yard and a gap for the gate")
	var yard_field: Control = workspace._building_plan
	workspace.set_building_layout(yard_recipe.parameters, yard_recipe.structure)
	yard_field.mode = yard_field.FENCE
	var yard_rect: Rect2 = yard_plan.rectangle
	var left := Vector2(yard_rect.position.x, yard_rect.get_center().y)
	yard_field._handle(event, left)
	yard_field._handle(motion, left + Vector2.LEFT * 0.5)
	check(workspace.recipe.parameters.fence_left_m == 1.0 and yard_field._draft.fence_left_m == 1.5, "fence side drag remains a draft")
	yard_field._handle(release, left + Vector2.LEFT * 0.5)
	check(workspace.recipe.parameters.fence_left_m == 1.5 and workspace.recipe.parameters.fence_right_m == 0.75, "move only the selected fence side")
	workspace.history.undo()
	check(workspace.recipe.parameters.fence_left_m == 1.0, "fence side move is one Undo")
	workspace.history.redo()
	check(workspace.recipe.parameters.fence_left_m == 1.5, "fence side move Redo")
	workspace.history.undo()
	var standard_yard: EmberVoxelModelResource = Generator.build(yard_recipe, Color.WHITE, {}, "Двор", "yard_regular").geometry
	yard_recipe.parameters.fence_bay_side = 1
	check(not Generator.validation_errors(yard_recipe).is_empty(), "fence bay counts four extra sections")
	yard_recipe.parameters.corner_posts = false
	var bay := Layout.fence_plan(yard_recipe.parameters, yard_recipe.structure.door)
	check(bay.segments.size() == 9 and is_equal_approx(bay.bounds.position.x, yard_plan.bounds.position.x - 1.5) and bay.hinge == yard_plan.hinge, "square side pocket expands left while the gate stays put")
	var yard_creation := Creation.new()
	yard_creation.source_directory = creation.source_directory
	yard_creation.prefab_directory = creation.prefab_directory
	yard_creation.recipe_directory = creation.recipe_directory
	check(yard_creation.prepare_recipe(yard_recipe, "Двор с карманом", "", "yard_bay"), yard_creation.error)
	if yard_creation.source != null:
		var yard_source := yard_creation.source
		check(local_building_entry(yard_source).is_equal_approx(local_building_entry(standard_yard)), "asymmetric yard storage preserves the local entrance anchor")
		var yard_grid := yard_source.grid_size()
		var placement: Vector3 = yard_source.solid_surface.building_offset
		var grid_shift := (placement - Layout.placement_offset(yard_recipe.parameters)) * 16.0
		var yard_origin := Layout.model_offset(yard_recipe.parameters) * 16.0 + Vector2(yard_grid.x, yard_grid.z) * 0.5 - Vector2(grid_shift.x, grid_shift.z)
		var far_wall: Vector2 = Vector2(bay.bounds.position.x, yard_rect.get_center().y)
		check(roof_top(yard_source, yard_origin + far_wall * 16.0) == 16, "square pocket appears in the exact Source")
		check(roof_top(yard_source, yard_origin + (far_wall + Vector2.RIGHT * 0.75) * 16.0) == 0, "inside of the new pocket is open")
		check(yard_creation.save_to_library(scene, history), yard_creation.error)
		var yard_disk := Creation.load_recipe("yard_bay", creation.recipe_directory)
		check(yard_disk != null and yard_disk.parameters.fence_bay_side == 1 and yard_disk.parameters.fence_rear_m == 1.5, "fence setbacks and bay survive reopening")
	print("BUILDING_LAYOUT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	panel.queue_free();workspace.queue_free();scene.queue_free();history.clear_history();history.free()
	for i in 5:await process_frame
	quit(0 if errors.is_empty() else 1)
