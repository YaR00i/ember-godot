@tool
extends RefCounted
## Editor placement/provenance. Geometry remains ordinary native voxel prefabs.
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const Math = preload("res://scripts/prototypes/ember_terrain_plan_math.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const PlacementMath = preload("res://addons/ember_import/ember_voxel_placement_math.gd")
const SmoothSurface = preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const GroundMesh=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const GROUND_TILE_SIZE := 64
const MAX_TREES := 64
const MAX_GROUND_FIELDS:=16
const SNAP_PARENT := &"_ember_grove_snapshot_parent"
const SNAP_NAME := &"_ember_grove_snapshot_name"
const SNAP_SCENE := &"_ember_grove_snapshot_scene"
var error := ""
var finished := false
var cancelled := false
var output_plan: Resource
var placements: Array[Dictionary] = []
var removals: Array[Node] = []
var protected_members: Array[Dictionary] = []
var protected_nodes: Array[Node] = []
var templates := {}
var model_hashes := {}
var scene_version := {}
var elapsed_us := 0
var worst_step_us := 0
var _source: EmberTerrainPilotResource
var _surface_rule_version: Dictionary={}
var _map: EmberMapLoader
var _root: Node
var _frame := Transform3D.IDENTITY
var _ground_style := 0
var _smooth_fields := {}
var _smooth_keys: Array[Vector2i] = []
var _smooth_cursor := 0
var _smooth_job: SmoothSurface.FieldJob
var _smooth_offset:=Vector2i.ZERO
var _candidate:Dictionary={}
var _member_limit:=Plan.MAX_GROVE_MEMBERS
var _protected_counts:Dictionary={}
var fields_prepared:=0
var peak_fields:=0
var _regions: Array[Dictionary] = []
var _group_noises := {} # One derived sampler per placement region/job, never saved.
var _roads: Array[Dictionary] = []
var _objects: Array[Dictionary] = []
var _walk: Array[Node] = []
var _old_members := {}
var _props := {}
var _skip_slots := {}
var _taken: Array[Dictionary] = []
var _used_ids := {}
var _region_index := 0
var _cell_index := 0
var _region_count := 0
var _prepared_members := false
var _base_bounds := {}
var _base_versions := {}
var _template_bounds := {}
var _spatial := {}
var _spatial_entries: Array[Dictionary] = []
var _large_entries: Array[int] = []
var _publication := {}

static func choices(all_objects := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in EmberVoxelVisuals.entries():
		if entry.owner != "godot" or not entry.ready: continue
		var id: String = entry.id
		var recipe: Resource = Creation.load_recipe(id)
		var role := "other"
		var generator := str(recipe.get("generator_id")) if recipe != null else ""
		if generator in ["large_tree","tree"] or "tree" in entry.tags: role = "tree"
		elif generator == "bush" or "bush" in entry.tags or "_bush" in id: role = "bush"
		elif generator == "rock" or "rock" in entry.tags: role = "rock"
		if not all_objects and role != "tree": continue
		var title: String = entry.title
		if recipe != null and not str(recipe.get("family_title")).is_empty(): title = str(recipe.get("family_title"))+" · "+str(recipe.get("variation_name"))
		result.append({"id":id,"title":title,"role":role,"tooltip":entry.tooltip})
	result.sort_custom(func(a,b): return a.id < b.id)
	return result

func _bounds(prop: EmberVoxelProp) -> AABB:
	if not _base_bounds.has(prop.model_id):
		var path := EmberVoxelCatalog.native_path(prop.model_id)
		var model := load(path) as EmberVoxelModelResource if FileAccess.file_exists(path) else null
		var box := AABB()
		if model != null:
			box = PlacementMath.base_voxel_bounds(model.grid_size(),model.normalized_density(),model.voxels)
			_base_versions[prop.model_id] = FileAccess.get_sha256(path)
		_base_bounds[prop.model_id] = box
	var native_box: AABB = _base_bounds[prop.model_id]
	var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null: return AABB()
	var mesh_path := mesh.mesh.resource_path
	var native_mesh := mesh_path == EmberVoxelPrefab.mesh_path(prop.model_id) or mesh_path.begins_with(EmberVoxelPrefab.prefab_path(prop.model_id)+"::")
	if native_box.size != Vector3.ZERO and native_mesh:
		var original: Vector3 = mesh.get_meta("ember_block_position",mesh.position/prop.block_world_size)
		return Transform3D(Basis.from_scale(mesh.scale/16.0),mesh.position-original*prop.block_world_size)*native_box
	return mesh.transform*mesh.mesh.get_aabb()

func _add_neighbor(entry: Dictionary) -> void:
	var index := _spatial_entries.size(); _spatial_entries.append(entry)
	var radius: float = entry.radius+entry.get("spacing",0.0)+entry.get("clearance",0.5)
	var low := Vector2i(floori((entry.point.x-radius)/4),floori((entry.point.y-radius)/4))
	var high := Vector2i(floori((entry.point.x+radius)/4),floori((entry.point.y+radius)/4))
	if (high.x-low.x+1)*(high.y-low.y+1) > 256: _large_entries.append(index); return
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var cell := Vector2i(x,z)
			if not _spatial.has(cell): _spatial[cell] = []
			_spatial[cell].append(index)

func _neighbors(point: Vector2, radius: float) -> Array[Dictionary]:
	var found := {}; var result: Array[Dictionary] = []
	for index in _large_entries: found[index] = true
	for z in range(floori((point.y-radius)/4),floori((point.y+radius)/4)+1):
		for x in range(floori((point.x-radius)/4),floori((point.x+radius)/4)+1):
			for index in _spatial.get(Vector2i(x,z),[]): found[index] = true
	for index in found: result.append(_spatial_entries[index])
	return result

static func roots(map: Node) -> Array[Node]:
	var result: Array[Node] = []; var pending: Array[Node] = [map]
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		if node.has_meta(Plan.GROVE_GROUP_META) or node.has_meta(Plan.GROVE_MEMBER_META): result.append(node); continue
		for child in node.get_children():
			if child.owner != null: pending.append(child)
	return result

static func _owned(node: Node, owner_node: Node) -> void:
	for child in node.get_children(): child.owner = owner_node; _owned(child,owner_node)

static func _flatten_snapshot(node: Node) -> void:
	# Preserve native instance boundaries. Flattening includes the current look's
	# derived meshes/materials and turns small recovery records into huge files.
	node.set_meta(SNAP_SCENE,node.scene_file_path)
	for child in node.get_children(): _flatten_snapshot(child)

static func _unflatten_snapshot(node: Node) -> void:
	node.scene_file_path = str(node.get_meta(SNAP_SCENE,node.scene_file_path)); node.remove_meta(SNAP_SCENE)
	for child in node.get_children(): _unflatten_snapshot(child)

static func _snapshot_owners(original:Node,copy:Node,owner_node:Node,inherited:Node=null)->void:
	if original is EmberVoxelProp and copy.has_node("Mesh"):
		var authored:Dictionary=original.authoring_visual_state()
		for key:String in authored:copy.get_node("Mesh").set(key,authored[key])
	if not original.scene_file_path.is_empty():inherited=original
	for child in original.get_children():
		var next:=copy.get_node_or_null(NodePath(str(child.name)))
		if next==null:continue
		if child.owner==null:
			copy.remove_child(next);next.free();continue
		if inherited==null or child.owner!=inherited:next.owner=owner_node
		_snapshot_owners(child,next,owner_node,inherited)

static func snapshot(map: Node) -> PackedScene:
	var container := Node3D.new(); container.name = "GroveSnapshot"
	for node in roots(map):
		var copy := node.duplicate(Node.DUPLICATE_SIGNALS|Node.DUPLICATE_GROUPS|Node.DUPLICATE_SCRIPTS|Node.DUPLICATE_USE_INSTANTIATION)
		_flatten_snapshot(copy)
		copy.set_meta(SNAP_PARENT,str(map.get_path_to(node.get_parent())))
		copy.set_meta(SNAP_NAME,str(node.name))
		container.add_child(copy); copy.owner = container; _snapshot_owners(node,copy,container)
	var packed := PackedScene.new(); var result := packed.pack(container); container.free()
	return packed if result == OK else null

static func pose_version(map: Node) -> Dictionary:
	var result := {}
	if not is_instance_valid(map): return result
	for node in roots(map):
		if node is Node3D:
			result[str(map.get_path_to(node))] = [node.global_transform,node.visible,str(node.get("model_id")) if node is EmberVoxelProp else "",node.get_child_count()]
	return result

static func _copy_values(target: Node, template: Node, scene_root: Node) -> void:
	for property in template.get_property_list():
		var key: String = property.name
		if not int(property.usage)&PROPERTY_USAGE_STORAGE or key.begins_with("metadata/") or key in ["script","owner","name"]: continue
		var value: Variant = template.get(key)
		if value is Object and not value is Resource: continue
		target.set(key,value)
	if target is Node3D: target.transform = template.transform
	target.scene_file_path = str(template.get_meta(SNAP_SCENE,template.scene_file_path))
	for key in target.get_meta_list():
		if key not in [SNAP_PARENT,SNAP_NAME,SNAP_SCENE] and not template.has_meta(key): target.remove_meta(key)
	for key in template.get_meta_list():
		if key not in [SNAP_PARENT,SNAP_NAME,SNAP_SCENE]: target.set_meta(key,template.get_meta(key))
	for child in target.get_children():
		if template.get_node_or_null(NodePath(str(child.name))) == null: target.remove_child(child); child.queue_free()
	for child in template.get_children():
		var existing := target.get_node_or_null(NodePath(str(child.name)))
		if existing != null and existing.get_class() == child.get_class() and existing.get_script() == child.get_script(): _copy_values(existing,child,scene_root)
		else:
			if existing != null: target.remove_child(existing); existing.queue_free()
			var copy := child.duplicate(); _unflatten_snapshot(copy); target.add_child(copy); copy.owner = scene_root; _snapshot_owners(child,copy,scene_root)

static func restore_snapshot(map: Node, scene_root: Node, packed: PackedScene) -> String:
	if packed == null: return "Нет снимка деревьев рощи."
	var snapshot_root := packed.instantiate(); var desired := {}
	for child in snapshot_root.get_children():
		var path := str(child.get_meta(SNAP_PARENT,"")); var name_value := str(child.get_meta(SNAP_NAME,""))
		if path.is_empty() or path.begins_with("/") or ".." in path.split("/") or name_value.is_empty() or map.get_node_or_null(NodePath(path)) == null:
			snapshot_root.free(); return "Снимок рощи не соответствует структуре карты."
		desired[path.path_join(name_value)] = child
	for node in roots(map):
		if not desired.has(str(map.get_path_to(node))): node.get_parent().remove_child(node); node.queue_free()
	for path in desired:
		var template: Node = desired[path]; var existing := map.get_node_or_null(NodePath(path))
		if existing != null and existing.get_class() == template.get_class() and existing.get_script() == template.get_script(): _copy_values(existing,template,scene_root)
		else:
			if existing != null: existing.get_parent().remove_child(existing); existing.queue_free()
			var copy := template.duplicate(); _unflatten_snapshot(copy); copy.name = str(template.get_meta(SNAP_NAME)); copy.remove_meta(SNAP_NAME); copy.remove_meta(SNAP_PARENT)
			map.get_node(NodePath(str(template.get_meta(SNAP_PARENT)))).add_child(copy); copy.owner = scene_root; _snapshot_owners(template,copy,scene_root)
	snapshot_root.free(); return ""

static func _canonical(value: Variant, resource_cache := {},omit_render_units:=true) -> Variant:
	if typeof(value) == TYPE_FLOAT: return 0.0 if absf(value) < 0.000001 else snappedf(value,0.000001)
	if value is Vector3: return [_canonical(value.x),_canonical(value.y),_canonical(value.z)]
	if value is Vector2: return [_canonical(value.x),_canonical(value.y)]
	if value is Color: return [_canonical(value.r),_canonical(value.g),_canonical(value.b),_canonical(value.a)]
	if value is Basis: return [_canonical(value.x),_canonical(value.y),_canonical(value.z)]
	if value is Transform3D: return [_canonical(value.basis),_canonical(value.origin)]
	if typeof(value) == TYPE_STRING_NAME: return str(value)
	if value is Resource:
		if value is Script or value is Shader or value is Texture2D: return [value.get_class(),value.resource_path]
		var id:=str(value.get_instance_id())+":"+str(omit_render_units)
		if resource_cache.has(id): return resource_cache[id]
		var data := {"class":value.get_class(),"values":{}}
		resource_cache[id] = [value.get_class()] # Guard recursive Resource links.
		for property in value.get_property_list():
			var key: String = property.name
			if omit_render_units and value is ShaderMaterial and key in ["shader_parameter/ember_texture_world_unit","metadata/ember_units_per_metre"]:continue
			if int(property.usage)&PROPERTY_USAGE_STORAGE and key not in ["resource_path","resource_name","resource_local_to_scene","script"]:
				data.values[key] = _canonical(value.get(key),resource_cache,omit_render_units)
		resource_cache[id] = data
		return data
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256); digest.update(var_to_bytes(value))
		return [typeof(value),digest.finish().hex_encode()]
	if value is Object: return null
	if value is Dictionary:
		var result := {}; var keys: Array = value.keys(); keys.sort()
		for key in keys: result[key] = _canonical(value[key],resource_cache,omit_render_units)
		return result
	if value is Array:
		var result := []; for item in value: result.append(_canonical(item,resource_cache,omit_render_units))
		return result
	return value

static func _node_data(node: Node, resource_cache := {},legacy:=false) -> Dictionary:
	var values := {"class":node.get_class(),"children":[]}
	var authored:Dictionary={}
	if not legacy and node.name=="Mesh" and node.get_parent() is EmberVoxelProp:authored=node.get_parent().authoring_visual_state()
	for property in node.get_property_list():
		var key: String = property.name
		if not legacy and key=="instance_shader_parameters/ember_style_rim_master":continue
		if not int(property.usage)&PROPERTY_USAGE_STORAGE or key.begins_with("metadata/") or key in ["owner","name","transform","position","rotation","rotation_degrees","scale","unique_name_in_owner"]: continue
		values[key] = _canonical(authored.get(key,node.get(key)),resource_cache,not legacy)
	for key in node.get_meta_list():
		if key not in [Plan.GROVE_MEMBER_META,Plan.GROVE_GROUP_META,SNAP_PARENT,SNAP_NAME,SNAP_SCENE]: values["meta:"+str(key)] = _canonical(node.get_meta(key),resource_cache,not legacy)
	for child in node.get_children():
		var data := _node_data(child,resource_cache,legacy); data.name = str(child.name)
		if child is Node3D: data.transform = child.transform
		values.children.append(data)
	return values

static func fingerprint(prop: Node3D, map: Node3D, frame := Transform3D.IDENTITY, parent_path := "", resource_cache := {},legacy:=false) -> Dictionary:
	var result:Dictionary={"transform":frame.affine_inverse()*prop.global_transform if prop.is_inside_tree() else prop.transform,
		"name":str(prop.name),"parent":parent_path if not parent_path.is_empty() else str(map.get_path_to(prop.get_parent())),
		"signature":JSON.stringify(_canonical(_node_data(prop,resource_cache,legacy),resource_cache,not legacy)).sha256_text()}
	if not legacy:result.signature_version=2
	return result

static func scene_fingerprint(map: Node3D, frame: Transform3D, excluded := {}) -> Dictionary:
	var result := {}; var pending: Array[Node] = [map.get_node_or_null("Props")]; var cache := {}
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		if node == null: continue
		if excluded.has(node.get_instance_id()): continue
		if node is EmberVoxelProp:
			result[str(map.get_path_to(node))] = fingerprint(node,map,frame,"",cache); continue
		if node is MeshInstance3D:
			result[str(map.get_path_to(node))] = fingerprint(node,map,frame,"",cache); continue
		if node is Node3D: result[str(map.get_path_to(node))] = [node.transform,node.visible]
		for child in node.get_children(): pending.append(child)
	return result

static func native_hash(id: String) -> String:
	var recipe_hash := FileAccess.get_sha256(Creation.recipe_path(id)) if FileAccess.file_exists(Creation.recipe_path(id)) else "no-recipe"
	return (FileAccess.get_sha256(EmberVoxelCatalog.native_path(id))+FileAccess.get_sha256(EmberVoxelPrefab.prefab_path(id))+recipe_hash).sha256_text()

func begin(source: EmberTerrainPilotResource, map: EmberMapLoader, scene_root: Node, plan: Resource, catalog := {}) -> bool:
	_source = source; _map = map; _root = scene_root
	if source == null or map == null or scene_root == null or plan == null: error = "Нет земли или плана рощи."; return false
	_surface_rule_version=source.surface_rules.duplicate(true)
	var problems: Array[String] = plan.validation_errors(Vector2i(source.width/16,source.depth/16))
	if not problems.is_empty(): error = problems[0]; return false
	var projection := map._visual_surface_projection as Node3D
	_frame = projection.global_transform if is_instance_valid(projection) and projection.is_inside_tree() else map.global_transform
	_ground_style = map.compact_ground_style
	if _ground_style == 1 and not source.is_sectioned() and source.width*source.depth > map.smooth_column_limit():
		error = "Детальная опора объектов: превышен бюджет земли этой карты.";return false
	output_plan = plan.working_copy(); output_plan.upgrade_local_layers(); output_plan.object_layers.clear()
	_member_limit=plan.member_limit(Vector2i(source.width/16,source.depth/16))
	if source.is_sectioned():_member_limit=maxi(Plan.MAX_GROVE_MEMBERS,source.sections.size()*Plan.MEMBERS_PER_SECTION)
	for region: Dictionary in plan.regions:
		if region.get("kind") == "road" and region.get("enabled",true): _roads.append({"curve":Math.path_curve(region.points_m),"values":region.parameters})
		if region.get("kind") not in ["grove","placement"] or not region.get("enabled",true): continue
		if region.parameters.model_ids.is_empty() and region.parameters.density > 0: error = "Выберите готовые объекты из библиотеки."; return false
		_regions.append(region.duplicate(true))
		if region.kind == "placement": _group_noises[region.id] = Math.placement_group_noise(region.parameters)
		for id in region.parameters.model_ids:
			if templates.has(id): continue
			if catalog.is_empty() and (not FileAccess.file_exists(EmberVoxelCatalog.native_path(id)) or not FileAccess.file_exists(EmberVoxelPrefab.prefab_path(id))):
				error = "Объект недоступен: "+str(id); return false
			var packed: PackedScene = catalog.get(id) if not catalog.is_empty() else load(EmberVoxelPrefab.prefab_path(id)) as PackedScene
			if packed == null or (catalog.is_empty() and not FileAccess.file_exists(EmberVoxelCatalog.native_path(id))):
				error = "Объект недоступен: "+str(id); return false
			var test := packed.instantiate()
			if not test is EmberVoxelProp or test.model_id != id or test.get_node_or_null("Mesh") == null or test.get_node("Mesh").mesh == null: test.free(); error = "Некорректный prefab объекта: "+str(id); return false
			_template_bounds[id] = _bounds(test)
			var visual:MeshInstance3D=test.get_node("Mesh")
			if visual.mesh is ArrayMesh and visual.mesh.get_surface_count()>0 and visual.mesh.surface_get_name(0)=="tree_bark":
				test.set_world_look(0)
			test.free(); templates[id] = packed
			if catalog.is_empty(): model_hashes[id] = native_hash(id)
	for region_id in plan.object_layers:
		for member: Dictionary in plan.object_layers[region_id]:
			var record := member.duplicate(true); record.region = region_id; _old_members[member.id] = record
	var parent := map.get_node_or_null("Props")
	if parent == null: error = "В карте нет обычной группы Props для объектов."; return false
	_walk.append(parent); scene_version = scene_fingerprint(map,_frame)
	_used_ids = EmberSceneAuthoring.placement_ids(scene_root)
	return true

func cancel() -> void:
	cancel_publication()
	cancelled = true; finished = true
	_smooth_job=null;_smooth_fields.clear();_smooth_keys.clear();_candidate.clear()

func _walk_one() -> void:
	var node := _walk.pop_back() as Node
	if node is EmberVoxelProp:
		_props[node.placement_id] = node
		return
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = (_frame.affine_inverse()*node.global_transform)*node.mesh.get_aabb()
		var footprint := PlacementMath.footprint(box,Transform3D.IDENTITY)
		_objects.append(footprint); _add_neighbor(footprint)
	for child in node.get_children(): _walk.append(child)

func _prepare_members() -> void:
	var cache := {}
	for id in _old_members:
		var record: Dictionary = _old_members[id]; var prop := _props.get(id) as EmberVoxelProp
		var unchanged: bool = prop != null and prop.get_meta(Plan.GROVE_MEMBER_META,{}) == {"region":record.region,"slot":record.slot} and fingerprint(prop,_map,_frame,"",cache,int(record.expected.get("signature_version",1))==1) == record.expected
		if record.get("protected",false) or not unchanged:
			record.protected = true; protected_members.append(record)
			_skip_slots[str(record.region)+":"+str(record.slot)] = true
			if prop != null: protected_nodes.append(prop)
		else: removals.append(prop)
	for prop: EmberVoxelProp in _props.values():
		if prop in removals: continue
		var footprint := PlacementMath.footprint(_bounds(prop),_frame.affine_inverse()*prop.global_transform)
		_objects.append(footprint); _add_neighbor(footprint)
	_prepared_members = true
	for member:Dictionary in protected_members:_protected_counts[member.region]=int(_protected_counts.get(member.region,0))+1

func _candidate_ground_fields(point:Vector2,radius:float)->bool:
	if _ground_style!=1:return true
	var required:Dictionary={}
	for offset in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var cell:=Vector2i(((point+offset)*16).floor())
		if not _source.has_column(cell.x,cell.y):continue
		var key:=Vector2i(cell.x/GROUND_TILE_SIZE,cell.y/GROUND_TILE_SIZE)
		required[key]=true
	_smooth_keys.clear();_smooth_cursor=0
	for key:Vector2i in required:
		if _smooth_fields.has(key):
			var field:Dictionary=_smooth_fields[key];_smooth_fields.erase(key);_smooth_fields[key]=field
		else:_smooth_keys.append(key)
	return _smooth_keys.is_empty()

func _ground(point: Vector2, slope: float, radius := 0.5) -> float:
	var levels: Array[float] = []
	for offset in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var cell := Vector2i(floori((point.x+offset.x)*16),floori((point.y+offset.y)*16))
		if cell.x < 0 or cell.y < 0 or cell.x >= _source.width or cell.y >= _source.depth: return -INF
		var index: int = _source.column_index(cell.x,cell.y); var height: int = _source.column_value("heights",index)
		if height <= 0 or _source.column_value("top_materials",index) == 0 or _source.column_value("water_levels",index) > height: return -INF
		var level:=float(height+_source.origin_y)
		if _ground_style == 1:
			var key:=Vector2i(cell.x/GROUND_TILE_SIZE,cell.y/GROUND_TILE_SIZE)
			level=SmoothSurface.sample(_smooth_fields[key],(point+offset)*16.0)
			if _source.column_value("water_levels",index)>0 and _source.column_value("water_levels",index)+_source.origin_y>level:return -INF
		levels.append(level/16.0)
	if (levels.max()-levels.min())*100.0/maxf(0.1,radius*2) > slope+0.001: return -INF
	return levels.max()

func _placement_allowed(foot: Dictionary, spacing: float, clearance: float) -> bool:
	for road: Dictionary in _roads:
		if not Math.path_sample(road.curve,foot.point,road.values.width_m,road.values.edge_m+foot.radius+clearance).is_empty(): return false
	for entry in _neighbors(foot.point,foot.radius+clearance+spacing):
		if foot.point.distance_to(entry.point) < maxf(maxf(spacing,entry.get("spacing",0.0)),foot.radius+entry.radius+maxf(clearance,entry.get("clearance",0.5))): return false
	return true

func _point_allowed(point: Vector2, spacing: float) -> bool:
	for road: Dictionary in _roads:
		var values: Dictionary = road.values
		if not Math.path_sample(road.curve,point,values.width_m,values.edge_m+0.5).is_empty(): return false
	for entry: Dictionary in _objects:
		if point.distance_to(entry.point) < spacing*0.5+entry.radius: return false
	for previous in _taken:
		if point.distance_to(previous.point) < maxf(spacing,previous.spacing): return false
		if previous.get("generic",false) and point.distance_to(previous.foot_point) < 0.5+previous.radius+previous.clearance: return false
	return true

func _point_one() -> void:
	var region: Dictionary = _regions[_region_index]; var values: Dictionary = region.parameters
	var columns := ceili(float(region.bounds.size.x)/values.spacing_m); var rows := ceili(float(region.bounds.size.y)/values.spacing_m)
	if _candidate.is_empty() and _cell_index >= columns*rows:
		_region_index += 1; _cell_index = 0; _region_count = 0; return
	if _candidate.is_empty():
		var cell := Vector2i(_cell_index%columns,_cell_index/columns); _cell_index += 1
		if values.model_ids.is_empty(): return
		_candidate=Math.grove_candidate(region.bounds,values,cell,_group_noises.get(region.id) as FastNoiseLite)
		if _candidate.is_empty():return
	var next:Dictionary=_candidate
	if _skip_slots.has(str(region.id)+":"+str(next.key)):_candidate={};return
	next.model_id = values.model_ids[next.variant]
	var height := -INF
	var footprint := {}
	var base: AABB = _template_bounds[next.model_id]
	if region.kind == "placement":
		footprint = PlacementMath.footprint(base,Transform3D(Basis(Vector3.UP,next.turn),Vector3(next.point.x,0,next.point.y)*16))
		var bounds := Rect2(region.bounds)
		if not bounds.encloses(Rect2(footprint.point-Vector2.ONE*footprint.radius,Vector2.ONE*footprint.radius*2)):_candidate={};return
		if not _candidate_ground_fields(footprint.point,footprint.radius):return
		_candidate={}
		height = _ground(footprint.point,values.slope_percent,footprint.radius)
		if not is_finite(height) or not _placement_allowed(footprint,values.spacing_m,values.clearance_m): return
	else:
		if not _candidate_ground_fields(next.point,0.5):return
		_candidate={}
		height = _ground(next.point,values.slope_percent)
		if not is_finite(height) or not _point_allowed(next.point,values.spacing_m): return
	_region_count += 1
	var protected_count:int=_protected_counts.get(region.id,0)
	var region_limit:int=Plan.region_member_limit(region.bounds)
	if _region_count+protected_count > region_limit: error = "Превышен бюджет области: %d объектов. Уменьшите плотность или увеличьте интервал."%region_limit; return
	if placements.size()+protected_members.size() >= _member_limit: error = "Превышен бюджет созданных участков: %d объектов."%_member_limit; return
	next.region = region.id
	next.transform = Transform3D(Basis(Vector3.UP,next.turn),Vector3(next.point.x,height-(base.position.y/16.0 if region.kind == "placement" else 0.0),next.point.y)*16.0)
	if footprint.is_empty(): footprint = PlacementMath.footprint(base,next.transform)
	placements.append(next); _taken.append({"point":next.point,"spacing":values.spacing_m,"generic":region.kind == "placement","foot_point":footprint.point,"radius":footprint.radius,"clearance":values.get("clearance_m",0.5)})
	footprint.spacing = values.spacing_m; footprint.clearance = values.get("clearance_m",0.5); _add_neighbor(footprint)

func step(budget_us := 4000) -> void:
	if finished or cancelled: return
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec()-started < budget_us:
		if not _walk.is_empty(): _walk_one()
		elif _smooth_cursor < _smooth_keys.size():
			var key:=_smooth_keys[_smooth_cursor]
			if _smooth_job==null:
				var begin:=key*GROUND_TILE_SIZE
				if _source.is_sectioned():
					var input:=GroundMesh.editor_surface_input(_source,begin.x,begin.y,GROUND_TILE_SIZE)
					_smooth_offset=input.start;_smooth_job=SmoothSurface.FieldJob.new(input.source,input.bounds)
				else:
					_smooth_offset=Vector2i.ZERO
					_smooth_job=SmoothSurface.FieldJob.new(_source,Rect2i(begin,Vector2i(mini(GROUND_TILE_SIZE,_source.width-begin.x),mini(GROUND_TILE_SIZE,_source.depth-begin.y))))
			_smooth_job.step(maxi(1,budget_us-int(Time.get_ticks_usec()-started)))
			if _smooth_job.finished:
				_smooth_job.result.start+=_smooth_offset
				while _smooth_fields.size()>=MAX_GROUND_FIELDS:_smooth_fields.erase(_smooth_fields.keys()[0])
				_smooth_fields[key]=_smooth_job.result;_smooth_job=null;_smooth_cursor+=1
				fields_prepared+=1;peak_fields=maxi(peak_fields,_smooth_fields.size())
		elif not _prepared_members: _prepare_members()
		elif _region_index < _regions.size(): _point_one()
		else: finished = true; break
		if not error.is_empty(): finished = true; break
	var elapsed := Time.get_ticks_usec()-started; elapsed_us += elapsed; worst_step_us = maxi(worst_step_us,elapsed)

func stale() -> bool:
	if _source!=null and _source.surface_rules!=_surface_rule_version:return true
	if not is_instance_valid(_map) or scene_fingerprint(_map,_frame,_publication.get("excluded",{})) != scene_version: return true
	if _map.compact_ground_style != _ground_style:return true
	var projection:=_map._visual_surface_projection as Node3D
	var frame: Transform3D=projection.global_transform if is_instance_valid(projection) and projection.is_inside_tree() else _map.global_transform
	if frame!=_frame:return true
	for id in _base_versions:
		if FileAccess.get_sha256(EmberVoxelCatalog.native_path(id)) != _base_versions[id]: return true
	for id in model_hashes:
		if native_hash(id) != model_hashes[id]: return true
	return false

func make_prop(spec: Dictionary, parent: Node3D, reserved := {}) -> EmberVoxelProp:
	var id := "grove_"+str(spec.region).sha256_text().substr(0,12)+"_"+str(spec.key)
	var suffix := 1
	while _used_ids.has(id) or reserved.has(id):
		var previous: Dictionary = _old_members.get(id,{})
		if not reserved.has(id) and previous.get("region") == spec.region and previous.get("slot") == spec.key and _props.get(id) in removals: break
		id = "grove_"+str(spec.region).sha256_text().substr(0,12)+"_"+str(spec.key)+"_"+str(suffix); suffix += 1
	var prop := EmberSceneAuthoring.make_model_instance(_root,templates[spec.model_id],spec.model_id,Vector3.ZERO,reserved,id)
	if prop == null: return null
	prop.transform = parent.global_transform.affine_inverse()*_frame*spec.transform
	prop.scene_file_path = (templates[spec.model_id] as PackedScene).resource_path
	if prop.scene_file_path.is_empty(): prop.scene_file_path = EmberVoxelPrefab.prefab_path(spec.model_id)
	prop.set_meta(Plan.GROVE_MEMBER_META,{"region":spec.region,"slot":spec.key})
	return prop

func finalize(parent: Node3D) -> Dictionary:
	var added: Array[EmberVoxelProp] = []; var reserved := {}; var cache := {}
	for record in protected_members:
		var copy := record.duplicate(true); copy.erase("region")
		if output_plan.index_of(record.region) >= 0:
			if not output_plan.object_layers.has(record.region): output_plan.object_layers[record.region] = []
			output_plan.object_layers[record.region].append(copy)
	for spec in placements:
		var prop := make_prop(spec,parent,reserved)
		if prop == null: error = "Не удалось создать обычный экземпляр объекта."; break
		reserved[prop.placement_id] = true; added.append(prop)
		var expected := fingerprint(prop,_map,_frame,str(_map.get_path_to(parent)),cache)
		expected.transform = spec.transform
		if not output_plan.object_layers.has(spec.region): output_plan.object_layers[spec.region] = []
		output_plan.object_layers[spec.region].append({"id":prop.placement_id,"slot":spec.key,"expected":expected,"protected":false})
	if not error.is_empty():
		for prop in added: prop.free()
		return {}
	return {"added":added,"removed":removals.duplicate(),"parent":parent,"root":_root,"plan":output_plan,"unmark":protected_nodes.filter(func(node): return output_plan.index_of(str(node.get_meta(Plan.GROVE_MEMBER_META,{}).get("region",""))) < 0)}

## The existing editor generation queue calls this once per frame. Unowned
## instances are a cancellable preview: native packing and Grove snapshots omit
## them. Commit only assigns owners, so _ready and deferred look setup do not
## run again for the entire batch in one frame.
func begin_publication(parent: Node3D) -> void:
	_publication={"parent":parent,"added":[],"reserved":{},"cache":{},"excluded":{},"cursor":0,"protected":0,"finished":false,"worst_step_us":0}

func step_publication(budget_us := 4000) -> void:
	if _publication.is_empty() or _publication.finished: return
	if not is_instance_valid(_publication.parent) or not is_instance_valid(_root):
		error="Карта была закрыта."; return
	var started:=Time.get_ticks_usec()
	var count:=0
	while Time.get_ticks_usec()-started<budget_us and count<4:
		if _publication.protected<protected_members.size():
			var record:Dictionary=protected_members[_publication.protected]
			var copy:=record.duplicate(true);copy.erase("region")
			if output_plan.index_of(record.region)>=0:
				if not output_plan.object_layers.has(record.region):output_plan.object_layers[record.region]=[]
				output_plan.object_layers[record.region].append(copy)
			_publication.protected+=1
		elif _publication.cursor<placements.size():
			var spec:Dictionary=placements[_publication.cursor]
			var prop:=make_prop(spec,_publication.parent,_publication.reserved)
			if prop==null:error="Не удалось создать обычный экземпляр объекта.";return
			_publication.reserved[prop.placement_id]=true
			var expected:=fingerprint(prop,_map,_frame,str(_map.get_path_to(_publication.parent)),_publication.cache)
			expected.transform=spec.transform
			if not output_plan.object_layers.has(spec.region):output_plan.object_layers[spec.region]=[]
			output_plan.object_layers[spec.region].append({"id":prop.placement_id,"slot":spec.key,"expected":expected,"protected":false})
			_publication.added.append(prop);_publication.excluded[prop.get_instance_id()]=true
			_publication.parent.add_child(prop) # owner stays null until the one history action
			_publication.cursor+=1
			if _publication.cursor==placements.size():break
		else:
			# A separate tick after the last instance lets its deferred map look
			# bindings finish before the publication becomes an authored action.
			_publication.finished=true;break
		count+=1
	_publication.worst_step_us=maxi(_publication.worst_step_us,Time.get_ticks_usec()-started)

func publication_progress() -> Vector2i:
	return Vector2i(_publication.get("cursor",0),placements.size())

func publication_finished() -> bool:
	return not _publication.is_empty() and _publication.finished

func take_publication() -> Dictionary:
	if not publication_finished() or not error.is_empty():return {}
	var delta:Dictionary={"added":_publication.added,"removed":removals.duplicate(),"parent":_publication.parent,"root":_root,"plan":output_plan,"unmark":protected_nodes.filter(func(node): return output_plan.index_of(str(node.get_meta(Plan.GROVE_MEMBER_META,{}).get("region",""))) < 0)}
	_publication={}
	return delta

func cancel_publication() -> void:
	for prop in _publication.get("added",[]):
		if is_instance_valid(prop):prop.free()
	_publication={}

static func apply_delta(delta: Dictionary, forward: bool) -> void:
	var parent: Node = delta.parent
	for prop in delta.removed if forward else delta.added:
		if is_instance_valid(prop) and prop.get_parent() != null: prop.get_parent().remove_child(prop)
	for prop in delta.added if forward else delta.removed:
		if is_instance_valid(prop): EmberSceneAuthoring.attach_model_instance(delta.root,parent,prop)
	for node in delta.get("unmark",[]):
		if not is_instance_valid(node): continue
		if forward:
			if not delta.has("old_markers"): delta.old_markers = {}
			delta.old_markers[node.get_instance_id()] = node.get_meta(Plan.GROVE_MEMBER_META,{})
			node.remove_meta(Plan.GROVE_MEMBER_META)
		else: node.set_meta(Plan.GROVE_MEMBER_META,delta.old_markers.get(node.get_instance_id(),{}))
