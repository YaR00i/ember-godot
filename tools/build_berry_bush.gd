extends SceneTree
const Paint=preload("res://materials/ember_voxel_toon.tres")
func _init() -> void:
	var fruit:=preload("res://scripts/ember_item_presentation.gd").new();fruit.name="ForestBerry"
	fruit.body_center=Vector3(0,0.12,0)
	fruit.body_shape=SphereShape3D.new();fruit.body_shape.radius=0.10
	fruit.surface=PhysicsMaterial.new();fruit.surface.friction=0.6;fruit.surface.bounce=0.16
	fruit.linear_damping=0.3;fruit.angular_damping=0.6
	var s:=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ball:=SphereMesh.new();ball.radius=0.1;ball.height=0.20;ball.radial_segments=20;ball.rings=10
	append(s,ball,Transform3D(Basis.IDENTITY,Vector3(0,0.12,0)),Color("a93953"))
	for i in 5:
		var a:=float(i)*TAU/5.0
		leaf(s,Vector3(0,0.235,0),Vector3(cos(a)*0.085,-0.025,sin(a)*0.085),0.025,Color("668349"))
	mesh(fruit,s,"Mesh");save(fruit,"res://prefabs/items/forest_berry.scn")
	var bush:=preload("res://scripts/ember_berry_bush.gd").new();bush.name="BerryBush";bush.kind="custom";bush.completion_flag_id="berry_bush_harvested"
	var generator:=preload("res://addons/ember_import/ember_voxel_generator.gd")
	var recipe: Resource=generator.creation_presets(generator.BUSH)[0].recipe
	recipe.seed=173;recipe.parameters.merge({"generation_version":7,"height":28,"spread_radius":18,"stem_count":5,"foliage_density":85,"foliage_color":Color("69824d"),"foliage_highlight_color":Color("819250"),"foliage_shadow_color":Color("485e35")},true)
	recipe.family_id="vox_forest_berry_bush";recipe.family_title="Ягодный куст";recipe.variation_name="Основной"
	var built: Dictionary=generator.build(recipe,Color.WHITE,{},"Ягодный куст","vox_forest_berry_bush")
	assert(not built.has("error"),str(built))
	var source: EmberVoxelModelResource=built.geometry
	assert(ResourceSaver.save(source,"res://content/voxel_models/vox_forest_berry_bush.tres")==OK)
	assert(ResourceSaver.save(recipe,"res://content/editor/voxel_generators/vox_forest_berry_bush.tres")==OK)
	var packed:=EmberVoxelPrefab.prepare_resource(source);assert(packed!=null)
	assert(ResourceSaver.save(packed,"res://prefabs/voxels/vox_forest_berry_bush.tscn")==OK)
	var plant: EmberVoxelProp=load("res://prefabs/voxels/vox_forest_berry_bush.tscn").instantiate();plant.name="Plant";bush.add_child(plant);plant.owner=bush
	var berries:=Node3D.new();berries.name="Berries";bush.add_child(berries);berries.owner=bush
	var anchors:=preload("res://addons/ember_import/ember_voxel_fruit_placement.gd").clusters(source,recipe.seed,15,16.0,0.55)
	assert(not anchors.is_empty(),"No branch supports for berries")
	var stalks:=SurfaceTool.new();stalks.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cluster in anchors.size():
		var anchor: Dictionary=anchors[cluster]
		var direction: Vector3=anchor.outward
		var side:=Vector3(-direction.z,0,direction.x)
		stalk(stalks,anchor.wood,anchor.attachment)
		for j in 2:
			var berry: Node3D=load("res://prefabs/items/forest_berry.scn").instantiate()
			berry.name="Berry%d_%d"%[cluster,j];berry.scale=Vector3.ONE*5.5
			var top: Vector3=anchor.attachment+side*(float(j)-0.5)*0.75-Vector3.UP*float(j%2)*0.18
			berry.position=top-Vector3.UP*1.2375
			stalk(stalks,anchor.attachment,top)
			berries.add_child(berry);berry.owner=bush
	mesh(berries,stalks,"Stalks")
	var bounds: AABB=plant.get_node("Mesh").transform*plant.get_node("Mesh").mesh.get_aabb()
	var shape:=CollisionShape3D.new();shape.name="Shape";shape.shape=BoxShape3D.new();shape.shape.size=bounds.size;shape.position=bounds.get_center();bush.add_child(shape);shape.owner=bush
	save(bush,"res://prefabs/items/berry_bush.scn")
	print("PASS baked generated berry bush: native recipe/source/prefab, ",anchors.size()," automatic branch clusters");quit()

func append(s: SurfaceTool,primitive: PrimitiveMesh,t: Transform3D,c: Color) -> void:
	var arrays:=primitive.get_mesh_arrays()
	for i: int in arrays[Mesh.ARRAY_INDEX]:
		s.set_normal(t.basis*arrays[Mesh.ARRAY_NORMAL][i]);s.set_color(c.srgb_to_linear());s.add_vertex(t*arrays[Mesh.ARRAY_VERTEX][i])
func leaf(s: SurfaceTool,origin: Vector3,direction: Vector3,width: float,c: Color) -> void:
	var side:=direction.cross(Vector3.UP).normalized()*width
	var points:=[origin,origin+direction*0.25+side*0.75,origin+direction*0.55+side,origin+direction*0.82+side*0.55,origin+direction,origin+direction*0.82-side*0.55,origin+direction*0.55-side,origin+direction*0.25-side*0.75,origin+direction*0.48+Vector3.UP*width*0.24]
	for segment in 8:
		var tri:=[segment,(segment+1)%8,8]
		var n: Vector3=(points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]]).normalized()
		for i in tri:s.set_normal(n);s.set_color(c.srgb_to_linear());s.add_vertex(points[i])
		for i in [tri[2],tri[1],tri[0]]:s.set_normal(-n);s.set_color(c.srgb_to_linear());s.add_vertex(points[i])
func mesh(parent: Node3D,s: SurfaceTool,label: String) -> void:
	s.index();var node:=MeshInstance3D.new();node.name=label;node.mesh=s.commit();node.material_override=Paint;parent.add_child(node);node.owner=parent
	if parent.owner!=null:node.owner=parent.owner
func stalk(s: SurfaceTool,from: Vector3,to: Vector3) -> void:
	var delta:=to-from
	if delta.length()<0.001:return
	var cylinder:=CylinderMesh.new();cylinder.top_radius=0.018;cylinder.bottom_radius=0.025;cylinder.height=delta.length();cylinder.radial_segments=5
	var up:=delta.normalized();var across:=up.cross(Vector3.FORWARD).normalized()
	if across.is_zero_approx():across=up.cross(Vector3.RIGHT).normalized()
	append(s,cylinder,Transform3D(Basis(across,up,across.cross(up)),(from+to)*0.5),Color("72533d"))
func save(node: Node3D,path: String) -> void:
	var packed:=PackedScene.new();assert(packed.pack(node)==OK);assert(ResourceSaver.save(packed,path)==OK);node.free()
