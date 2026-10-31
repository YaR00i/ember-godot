@tool
extends RefCounted
## Distance decisions only. Resources, jobs and history stay with their owners.
var enabled := true
var ground_lod_enabled := true
var material_lod_enabled := true
var ground_near_m := 18.0
var ground_release_m := 24.0
var detail_fade_begin_m := 16.0
var detail_fade_end_m := 24.0
var detail_prepare_m := 30.0 # Preparation lead for budgeted worker resumes; visible fade stays 16–24 m.
var detail_release_m := 32.0
var object_prepare_m := 36.0
var object_release_m := 44.0
var anchor := Vector2.ZERO # Projection/source units, not world metres.
var cells_per_m := 16.0

## Conservative bounds of the same world XZ rectangle in source space.
## All four corners matter under rotation; the diagonal alone can collapse.
static func local_area(area: Rect2, inverse: Transform3D, world_y: float) -> Rect2:
	# Native affine AABB projection contains the same four corners, including
	# rotation, nonuniform scale and shear, without allocating/iterating an Array.
	if area.size.x<0 or area.size.y<0:area=area.abs()
	var local := inverse * AABB(Vector3(area.position.x, world_y, area.position.y), Vector3(area.size.x, 0, area.size.y))
	return Rect2(Vector2(local.position.x, local.position.z), Vector2(local.size.x, local.size.z))

func distance_m(area: Rect2) -> float:
	var closest := anchor.clamp(area.position, area.end)
	return anchor.distance_to(closest) / maxf(cells_per_m, 0.001)

func ground_full(area: Rect2, retained: bool, protected := false) -> bool:
	return not enabled or protected or distance_m(area) <= (ground_release_m if retained else ground_near_m)

func detail_resident(area: Rect2, retained: bool) -> bool:
	return not enabled or distance_m(area) <= (detail_release_m if retained else detail_prepare_m)

func preparation_band(area:Rect2)->int:
	# One painted patch per band. Preserve fairness within the visible band,
	# rather than partially preparing the entire distant reserve first.
	return floori(distance_m(area)/4.0) if enabled else 0

func object_resident(area: Rect2, retained: bool, protected := false) -> bool:
	return not enabled or protected or distance_m(area)<=(object_release_m if retained else object_prepare_m)

func material_depth_required(nearest_m:float,fade_end_m:float,far_retained:bool)->bool:
	# Both thresholds are beyond the shader's completely flat endpoint.
	# Return to the full path before any fragment could regain visible depth.
	return not enabled or not material_lod_enabled or nearest_m<=fade_end_m+(0.5 if far_retained else 1.0)

func ground_candidates(extent:Vector2i,tile_cells:int,column_budget:int,retained:Dictionary,protected:Dictionary)->Dictionary:
	# Budget is for prepared fine tiles, never for the authored world's area.
	var capacity:=maxi(1,column_budget/(tile_cells*tile_cells))
	var half:=maxi(1,floori((sqrt(float(capacity))-1.0)*0.5))
	# A retained four-metre painted patch extends beyond its nearest edge.
	# Keep a full tile of ground ahead of the old circle so its far corners
	# cannot wait forever outside the fine preparation set. Capacity is unchanged.
	var release:=float((half+1)*tile_cells)
	var prepare:=maxf(float(tile_cells),release-tile_cells)
	# An admitted painted patch must have ground at its far corner as well.
	# One patch spans a fine tile; the extra metre covers its tuft-size halo.
	# Preserve the fixed fine-tile capacity and the existing release circle.
	prepare=maxf(prepare,minf(release,detail_prepare_m*cells_per_m+sqrt(2.0)*tile_cells+cells_per_m))
	var centre:=Vector2i(floori(anchor.x/tile_cells),floori(anchor.y/tile_cells))
	var candidates:Array[Vector2i]=[]
	for z in range(maxi(0,centre.y-half-1),mini(ceili(float(extent.y)/tile_cells),centre.y+half+2)):
		for x in range(maxi(0,centre.x-half-1),mini(ceili(float(extent.x)/tile_cells),centre.x+half+2)):
			var key:=Vector2i(x,z)
			var area:=Rect2(Vector2(key*tile_cells),Vector2.ONE*tile_cells)
			if distance_m(area)*cells_per_m<=(release if retained.has(key) else prepare):candidates.append(key)
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):return (Vector2(a*tile_cells)+Vector2.ONE*tile_cells*0.5-anchor).length_squared()<(Vector2(b*tile_cells)+Vector2.ONE*tile_cells*0.5-anchor).length_squared())
	var result:Dictionary={}
	for i in mini(capacity,candidates.size()):result[candidates[i]]=true
	# An active brush/selection is allowed to exceed the idle budget temporarily.
	for key:Vector2i in protected:
		if key.x>=0 and key.y>=0 and key.x*tile_cells<extent.x and key.y*tile_cells<extent.y:result[key]=true
	return result
