extends SceneTree
## A voxelised plane must not become rows of bumps. No author assets are written.
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("VOLUME_FAIRING_FAIL ",label)
func _initialize()->void:
	var source:=EmberVoxelModelResource.new();source.size_blocks=Vector3i(2,2,2);source.height_voxels=32
	source.palette=PackedColorArray([Color.TRANSPARENT,Color(0.4,0.3,0.2)])
	source.voxels.resize(32768)
	for z in 32:
		for y in 32:
			for x in 32:
				if y+0.5<=8.0+(x+0.5)*0.5+(z+0.5)*0.25:source.voxels[x+z*32+y*1024]=1
	var original:=source.voxels.duplicate()
	var arrays:=Solid.volume_geometry(EmberVoxelPrefab.model_of(source.to_definition()))
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var expected:=Vector3(-0.5,1,-0.25).normalized()
	var count:=0;var sum_angle:=0.0;var sum_error:=0.0;var max_error:=0.0
	for i in range(0,vertices.size(),3):
		var a:=vertices[i]*16.0;var b:=vertices[i+1]*16.0;var c:=vertices[i+2]*16.0
		var centre:Vector3=(a+b+c)/3.0
		if centre.x<5 or centre.x>25 or centre.z<5 or centre.z>25 or absf(centre.y-8-centre.x*0.5-centre.z*0.25)>1.0:continue
		var normal:Vector3=(c-a).cross(b-a).normalized()
		sum_angle+=rad_to_deg(acos(clampf(normal.dot(expected),-1,1)));count+=1
		for p in [a,b,c]:
			var distance:float=absf((p.y-8-p.x*0.5-p.z*0.25)/Vector3(-0.5,1,-0.25).length())
			sum_error+=distance;max_error=maxf(max_error,distance)
	check(count>100,"representative sloping surface")
	var angle:=sum_angle/maxi(count,1)
	check(angle<8.0,"sloped plane has no voxel-frequency normal corrugation")
	check(max_error<0.55,"surface remains within sub-voxel error of its source plane")
	check(source.voxels==original,"Source unchanged")
	var lo:=Vector3(INF,INF,INF);var hi:=-lo
	var old_lo:=lo;var old_hi:=hi
	for vertex in vertices:
		var p:=vertex*16.0;lo=lo.min(p);hi=hi.max(p)
		var cell:=Vector3i((p-Vector3.ONE*0.5).floor())
		var initial:Vector3=Solid._volume_point(source.voxels,Vector3i(32,32,32),cell)
		old_lo=old_lo.min(initial);old_hi=old_hi.max(initial)
		check(p.distance_to(initial)<0.3501,"bounded cell-local movement")
	check(lo.is_equal_approx(old_lo) and hi.is_equal_approx(old_hi),"model bounds unchanged")
	print("VOLUME_FAIRING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"triangles":count,"mean_angle_deg":angle,"mean_distance_voxels":sum_error/maxi(count*3,1),"max_distance_voxels":max_error}))
	quit(0 if errors.is_empty() else 1)
