extends SceneTree
class QuietProp extends EmberVoxelProp:
	func _ready()->void:
		set_process(false);set_notify_transform(true)
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FLOOR_SIGNATURE_FAIL ",label)
func mesh_at(height:float,extent:=2.0)->ArrayMesh:
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-extent,height,-extent),Vector3(-extent,height,extent),Vector3(extent,height,-extent),Vector3(-extent,height,extent),Vector3(extent,height,extent),Vector3(extent,height,-extent)])
	var colours:=PackedColorArray();colours.resize(6);colours.fill(Color(0,1,0,1.0/255.0));arrays[Mesh.ARRAY_COLOR]=colours
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.set_meta("solid_surface_roles",PackedStringArray(["soil","grass"]))
	return mesh
func _initialize()->void:run.call_deferred()
func run()->void:
	var prop:=QuietProp.new();prop.model_id="floor-signature-fixture"
	var visual:=MeshInstance3D.new();visual.name="Mesh";visual.mesh=mesh_at(0);prop.add_child(visual)
	prop._hull_mesh=visual.mesh
	var body:=StaticBody3D.new();body.name="Collision";body.collision_layer=1;prop.add_child(body)
	var shape:=CollisionShape3D.new();shape.name="Shape";shape.shape=ConcavePolygonShape3D.new();shape.shape.set_faces(visual.mesh.get_faces());body.add_child(shape)
	root.add_child(prop)
	var before:=prop.detail_surface_signature()
	var expected:=hash([visual.mesh.get_faces(),PackedByteArray([1,1]),PackedStringArray(["soil","grass"])])
	check(before[1]==expected,"signature retains original faces/slots/roles hash")
	check(prop._floor_grid.is_empty(),"signature alone does not build spatial query bins")
	var hit:=prop.surface_floor_sample(Vector3(0,100,0))
	check(hit.get("solid",false) and hit.get("material_role")=="grass" and is_equal_approx(hit.position.y,0),"first actual query preserves physical height and role")
	check(not prop._floor_grid.is_empty() and prop.detail_surface_signature()==before,"query builds bins without changing signature")
	prop.position=Vector3(8,2,0);prop._floor_grid.clear()
	var moved:=prop.detail_surface_signature()
	check(moved[1]==expected and moved[2]==visual.global_transform and prop._floor_grid.is_empty(),"moving changes transform signature without eagerly rebuilding bins")
	hit=prop.surface_floor_sample(Vector3(8,100,0))
	check(hit.get("solid",false) and is_equal_approx(hit.position.y,2),"query rebuilds bins at moved transform")
	shape.disabled=true
	check(prop.detail_surface_signature()[3],"disabled collision remains part of signature")
	shape.disabled=false;body.collision_layer=2
	check(prop.detail_surface_signature()[4]==2,"collision layers remain part of signature")
	body.collision_layer=1
	visual.mesh=mesh_at(1);prop._hull_mesh=visual.mesh;shape.shape.set_faces(visual.mesh.get_faces())
	var changed:=prop.detail_surface_signature()
	check(changed[1]!=before[1] and prop._floor_grid.is_empty(),"new physical mesh invalidates data without preparing bins")
	hit=prop.surface_floor_sample(Vector3(8,100,0))
	check(hit.get("solid",false) and is_equal_approx(hit.position.y,3),"changed physical mesh updates query height")
	visual.mesh.set_meta("solid_volume_boundary",true)
	shape.shape.set_faces(mesh_at(1.5).get_faces())
	var volume:=prop.detail_surface_signature()
	expected=hash([shape.shape.get_faces(),PackedByteArray([0,0]),PackedStringArray(["soil","grass"])])
	check(volume[1]==expected and prop._floor_grid.is_empty(),"volume signature still uses physical collider faces")
	hit=prop.surface_floor_sample(Vector3(8,100,0))
	check(hit.get("solid",false) and is_equal_approx(hit.position.y,3.5) and hit.get("material_role")=="soil","volume query retains collider height and role")
	visual.mesh=mesh_at(0,256);prop._hull_mesh=visual.mesh;shape.shape.set_faces(visual.mesh.get_faces())
	var wide_stamp:=prop.detail_surface_signature()
	var started:=Time.get_ticks_usec()
	hit=prop.surface_floor_sample(Vector3(8,100,0))
	var first_query_us:=Time.get_ticks_usec()-started
	check(hit.get("solid",false) and is_equal_approx(hit.position.y,2),"wide surface still supplies exact floor")
	check(prop._floor_grid.size()==1,"first root prepares one queried bin instead of the entire wide surface")
	hit=prop.surface_floor_sample(Vector3(12,100,0))
	check(prop._floor_grid.size()==2 and hit.get("solid",false),"another root extends the index only where queried")
	check(prop.detail_surface_signature()==wide_stamp,"lazy bins preserve the existing content key")
	visual.mesh=mesh_at(0,4);prop._hull_mesh=visual.mesh;shape.shape.set_faces(visual.mesh.get_faces())
	for angle in [PI/4,-PI/4]:
		prop.transform=Transform3D(Basis.from_euler(Vector3(0.3,angle,0.1)).scaled(Vector3(1.3,0.7,0.9)),Vector3(-12,3,-17))
		for unit in [16.0,4.0]:
			prop.block_world_size=unit
			for z in [-3.5,-1.0,0.0,1.0,3.5]:
				for x in [-3.5,-1.0,0.0,1.0,3.5]:
					var expected_point:=visual.to_global(Vector3(x,0,z))
					hit=prop.surface_floor_sample(Vector3(expected_point.x,1000,expected_point.z))
					check(hit.get("solid",false) and absf(hit.position.y-expected_point.y)<0.0001 and hit.get("material_role")=="grass","lazy bins preserve tilted/scaled/negative-coordinate floor and size changes")
	prop.free()
	print("OBJECT_FLOOR_SIGNATURE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"wide_first_query_us":first_query_us}))
	quit(0 if errors.is_empty() else 1)
