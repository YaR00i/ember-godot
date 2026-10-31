@tool
extends RefCounted
const Grid=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
## Post-generation derived fruit supports. Canonical wood/foliage remain in Source.
## No saved branch graph or random runtime placement; coordinates use prefab frame.
static func clusters(source: EmberVoxelModelResource,seed: int,count:=6,world_size:=16.0,fruit_radius:=1.4) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if source==null or not source.validation_errors().is_empty() or not "bush" in source.tags or count<=0 or not is_finite(world_size) or world_size<=0 or not is_finite(fruit_radius) or fruit_radius<=0:return result
	if not source.tree_surface.is_empty():
		return _branch_clusters(source,seed,count,world_size,fruit_radius)
	var grid:=source.grid_size()
	var wood: Array[Vector3i]=[]
	var highest:=0
	for index in source.voxels.size():
		if source.voxels[index]!=1:continue
		var cell:=Vector3i(index%grid.x,index/(grid.x*grid.z),(index/grid.x)%grid.z)
		wood.append(cell);highest=maxi(highest,cell.y)
	if wood.is_empty():return result
	var unit:=world_size/float(source.normalized_density())
	var offset:=Vector3(-grid.x*unit*0.5,0,-grid.z*unit*0.5)
	var middle:=Vector3(float(grid.x-1)*0.5,0,float(grid.z-1)*0.5)
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(0,seed)
	var phase:=rng.randf_range(-PI,PI)
	var target:=clampi(count,1,32)
	for sector in target:
		var angle:=phase+TAU*float(sector)/float(target)
		var outward:=Vector3(cos(angle),0,sin(angle))
		var best:=Vector3i.ZERO;var score:=-INF;var found:=false
		for cell in wood:
			if cell.y<maxi(2,roundi(highest*0.35)):continue
			var local:=Vector3(cell)-middle
			var value:=local.dot(outward)-absf(local.cross(outward).y)*0.8+float(cell.y)*0.12
			if value>score:score=value;best=cell;found=true
		if not found:continue
		# Walk through the connected canopy from real wood; stop at its outer face.
		var end:=Vector3(best)+Vector3.ONE*0.5
		var saw_leaf:=false;var gap:=0
		for step in maxi(grid.x,grid.z)*2:
			var point:=Vector3(best)+Vector3.ONE*0.5+outward*float(step)*0.5
			var cell:=Vector3i(point.floor())
			if cell.x<0 or cell.y<0 or cell.z<0 or cell.x>=grid.x or cell.y>=grid.y or cell.z>=grid.z:break
			var value:=source.voxels[Grid.index_of(cell,grid)]
			if value>1:saw_leaf=true;end=point;gap=0
			elif value==0:
				gap+=1
				if gap>=3:break
		if not saw_leaf:continue
		var attachment:=end*unit+offset+outward*(fruit_radius*0.7+unit*0.5)
		if result.any(func(entry):return entry.attachment.distance_to(attachment)<fruit_radius*3.5):continue
		result.append({"wood_cell":best,"wood":(Vector3(best)+Vector3.ONE*0.5)*unit+offset,
			"attachment":attachment,"outward":outward})
	return result

static func _branch_clusters(source: EmberVoxelModelResource,seed: int,count: int,world_size: float,fruit_radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var data:=source.tree_surface
	if data.settings.get("plant_kind","")!="shrub":return result
	var geometry:=preload("res://scripts/ember_tree_surface_geometry.gd")
	var layout:=geometry.branches(data.structure)
	var tips: Array=[]
	for branch: Dictionary in layout:
		if branch.order==3:tips.append(branch)
	if tips.is_empty():return result
	var unit:=world_size/float(source.normalized_density())
	var offset:=Vector3(data.pivot.x,0,data.pivot.y)
	var target:=mini(clampi(count,1,32),tips.size())
	# Reserve half the fruit for upper shoots; the rest stays around the sides.
	var by_height:=tips.duplicate()
	by_height.sort_custom(func(a,b):return geometry.point_at(a,0.94).y>geometry.point_at(b,0.94).y)
	var selected: Array=[]
	var upper_count:=ceili(float(target)*0.5)
	for i in upper_count:selected.append(by_height[i])
	for i in tips.size():
		if selected.size()>=target:break
		var candidate: Dictionary=tips[(posmod(seed,tips.size())+i*17)%tips.size()]
		if not selected.any(func(branch):return branch.id==candidate.id):selected.append(candidate)
	for i in target:
		var branch: Dictionary=selected[i]
		var t:=0.91+float(posmod(seed+i*17,5))*0.015 if i<upper_count else 0.72+float(posmod(seed+i*17,11))*0.015
		var support: Vector3=(geometry.point_at(branch,t)+offset)*unit
		var growth: Vector3=(geometry.point_at(branch,minf(t+0.05,1.0))-geometry.point_at(branch,maxf(t-0.05,0.0))).normalized()
		result.append({"wood":support,"attachment":support-Vector3.UP*fruit_radius*0.45,"outward":growth,"branch_id":branch.id,"branch_t":t})
	return result
