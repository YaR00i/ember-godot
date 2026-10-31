extends SceneTree
## Local cartoon apple geometry and an ordinary accepted tree instance.
func _init() -> void:
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere:=SphereMesh.new(); sphere.radius=0.12; sphere.height=0.24; sphere.radial_segments=24; sphere.rings=12
	var arrays:=sphere.get_mesh_arrays()
	var body_points:=PackedVector3Array()
	for index: int in arrays[Mesh.ARRAY_INDEX]:
		var p: Vector3=arrays[Mesh.ARRAY_VERTEX][index]
		var n: Vector3=arrays[Mesh.ARRAY_NORMAL][index]
		var angle:=atan2(p.z,p.x)
		var lobes:=(1.0+0.035*cos(angle*5.0)*(1.0-n.y*n.y))*(1.0+n.y*0.10)
		p.x*=lobes; p.z*=lobes; p.y*=0.95
		p.y-=0.035*pow(maxf(0.0,n.y),12.0)
		p.y+=0.13+0.008*pow(maxf(0.0,(-n.y-0.7)/0.3),2.0)
		body_points.append(p)
		surface.set_normal(n); surface.set_color(Color("b92e30").lerp(Color("dc5140"),clampf(0.4+n.y*0.35+sin(angle)*0.15,0,1)).srgb_to_linear()); surface.add_vertex(p)
	var stem:=CylinderMesh.new(); stem.top_radius=0.006; stem.bottom_radius=0.009; stem.height=0.06; stem.radial_segments=8
	append_coloured(surface,stem,Basis(Vector3.FORWARD,-0.18),Vector3(0,0.24,0),Color("71503a").srgb_to_linear())
	var points:=[Vector3(0,0.25,0),Vector3(0.025,0.285,0.035),Vector3(0.095,0.30,0.015),Vector3(0.045,0.255,-0.025)]
	for i in [0,1,2,0,2,3,2,1,0,3,2,0]:
		surface.set_normal(Vector3.UP); surface.set_color(Color("659347").srgb_to_linear()); surface.add_vertex(points[i])
	surface.index()
	var apple:=preload("res://scripts/ember_item_presentation.gd").new(); apple.name="Apple"
	apple.body_center=Vector3(0,0.13,0)
	for i in body_points.size():body_points[i]-=apple.body_center
	apple.body_shape=ConvexPolygonShape3D.new(); apple.body_shape.points=body_points; apple.body_shape.margin=0.002
	apple.surface=PhysicsMaterial.new(); apple.surface.friction=0.55; apple.surface.bounce=0.22
	apple.linear_damping=0.25; apple.angular_damping=0.45
	var model:=MeshInstance3D.new(); model.name="Mesh"; model.mesh=surface.commit(); model.material_override=load("res://materials/ember_voxel_toon.tres")
	apple.add_child(model); model.owner=apple
	save_scene(apple,"res://prefabs/items/apple.scn")
	var tree:=preload("res://scripts/ember_fruit_tree.gd").new(); tree.name="FruitTree"; tree.dropped_flag_id="fruit_tree_apple_dropped"; tree.collision_layer=4; tree.collision_mask=0; tree.monitoring=false
	var display: Node3D=load("res://prefabs/voxels/vox_painted_oak.tscn").instantiate(); display.name="Tree"; tree.add_child(display); display.owner=tree
	var shape:=CollisionShape3D.new(); shape.name="BodyShape"; shape.shape=CylinderShape3D.new(); shape.shape.radius=9; shape.shape.height=36; shape.position.y=18
	tree.add_child(shape); shape.owner=tree
	var fruit_position:=Vector3(28,56,16)
	var hanging: Node3D=load("res://prefabs/items/apple.scn").instantiate(); hanging.name="HangingFruit"; hanging.scale=Vector3.ONE*16; hanging.position=fruit_position
	tree.add_child(hanging); hanging.owner=tree
	var pickup:=preload("res://scripts/ember_world_item_3d.gd").new(); pickup.name="ApplePickup"; pickup.item_id="apple"; pickup.pickup_id="fruit_tree_apple"; pickup.available_flag_id=tree.dropped_flag_id; pickup.position=fruit_position
	tree.add_child(pickup); pickup.owner=tree
	save_scene(tree,"res://prefabs/items/fruit_tree.scn")
	print("PASS baked cartoon apple and fruit tree: shared toon shader, accepted oak, authored gated WorldItem")
	quit()

func append_coloured(surface: SurfaceTool,mesh: PrimitiveMesh,basis: Basis,origin: Vector3,colour: Color) -> void:
	var arrays:=mesh.get_mesh_arrays()
	for index: int in arrays[Mesh.ARRAY_INDEX]:
		surface.set_normal(basis*arrays[Mesh.ARRAY_NORMAL][index]); surface.set_color(colour); surface.add_vertex(basis*arrays[Mesh.ARRAY_VERTEX][index]+origin)

func save_scene(node: Node3D,path: String) -> void:
	var packed:=PackedScene.new(); assert(packed.pack(node)==OK)
	assert(ResourceSaver.save(packed,path)==OK); node.free()
