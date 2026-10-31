extends SceneTree
const Policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Builder=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Creation=preload("res://addons/ember_import/ember_compact_map_creation.gd")
class QueryProjection extends EmberTerrainPilotProjection:
	func _editor_residency_allowed()->bool:return true
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var policy:=Policy.new();policy.anchor=Vector2.ONE*32*16
	var counts:Array=[]
	for side in [72,144,288,576]:
		var wanted:=policy.ground_candidates(Vector2i.ONE*side*16,64,1572864,{},{});counts.append(wanted.size())
		check(wanted.size()<=384,"bounded idle fine preparation")
	check(counts[0]==counts[1] and counts[1]==counts[2] and counts[2]==counts[3],"same local workload regardless world extent")
	var old:=policy.ground_candidates(Vector2i.ONE*9216,64,262144,{},{});policy.anchor=Vector2.ONE*8000
	var next:=policy.ground_candidates(Vector2i.ONE*9216,64,262144,old,{Vector2i(8,8):true})
	check(next.size()<=65 and next.has(Vector2i(8,8)),"selection protected independently of observer")
	var overlap:=0
	for key in old:overlap+=int(next.has(key))
	check(overlap<=1,"camera travel releases former area")
	policy.anchor=Vector2.ONE*32*16
	check(policy.ground_candidates(Vector2i.ONE*9216,64,262144,{},{} )==old,"return restores deterministic tile set")
	var creator:=Creation.new();check(creator.prepare_sections("overview",2,1,24),"existing terrain creation")
	var source:Resource=creator.source
	var before:Resource=source.working_copy()
	var jobs:Array=[]
	for x in 2:
		var job:=Builder.OverviewJob.new(source.working_copy(),Rect2i(x*384,0,384,384));job.run(func():return false);jobs.append(job)
		check(job.result.patches.size()==36,"overview contains addressable fine-tile patches")
		check(job.result.arrays[Mesh.ARRAY_VERTEX].size()==24*24*6,"coarse geometry avoids fine columns")
		check(not job.result.has("collision_faces") and not job.result.has("smooth_field"),"overview prepares no fine physics or field")
	var borders:Array=[]
	for job in jobs:
		var border:Dictionary={}
		for p:Vector3 in job.result.arrays[Mesh.ARRAY_VERTEX]:
			if p.x==384:border[p.z]=p.y
		borders.append(border)
	check(not borders[0].is_empty() and borders[0]==borders[1],"actual adjacent coarse buffers share border heights")
	var join:=Builder.overview_edge(source,jobs[0].result,{Vector2i(2,2):true})
	var join_arrays:=join.surface_get_arrays(0);var join_points:PackedVector3Array=join_arrays[Mesh.ARRAY_VERTEX]
	check(join_points.size()==96,"coarse side closes all four directions around a fine tile")
	for i in range(0,join_points.size(),3):check((join_points[i+1]-join_points[i]).cross(join_points[i+2]-join_points[i]).dot(join_arrays[Mesh.ARRAY_NORMAL][i])<0,"coarse seam faces outward")
	var cancelled:=Builder.OverviewJob.new(source,Rect2i(0,0,384,384));cancelled.run(func():return true)
	check(cancelled.result.is_empty(),"cancelled overview cannot publish")
	var fine:=Builder.SmoothSurface.build_arrays(source,Rect2i(0,0,64,64),true)
	var mesh:=Builder.residency_edge(source,Rect2i(0,0,64,64),fine.smooth_field)
	var arrays:=mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i in range(0,vertices.size(),3):
		check((vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).dot(arrays[Mesh.ARRAY_NORMAL][i])<0,"seam closure faces outward")
	check(source.same_terrain_geometry(before),"derived overview/closure leave author geometry unchanged")
	var projection:=QueryProjection.new();root.add_child(projection);projection.set_process(false)
	projection.document=source;projection.ground_style=1
	for x in range(1,9):
		var sample:=projection.floor_surface_sample(Vector3(x*64+8,150,100))
		check(sample.get("solid",false) and not sample.get("physics_ready",true),"offscreen authoring query keeps the canonical floor without claiming physics ready")
		check(projection._smooth_fields.is_empty(),"offscreen queries do not accumulate fine fields")
	check(not projection._query_field.is_empty(),"at most the last offscreen field is retained")
	projection.free()
	print("TERRAIN_RESIDENCY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"fine_tiles_by_extent":counts,"far_vertices_per_section":jobs[0].result.arrays[Mesh.ARRAY_VERTEX].size()}))
	quit(0 if errors.is_empty() else 1)
