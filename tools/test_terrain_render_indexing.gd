extends SceneTree
const Surface=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Mesher=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const CHANNELS=[Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]
var errors:Array[String]=[]
var counts:Array=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("TERRAIN_INDEX_FAIL ",label)
func _initialize()->void:run.call_deferred()
func prepare(arrays:Array,detail:Dictionary,cancelled:=Callable())->Dictionary:
 var helper=Surface.new()
 if helper.has_method("prepare_render_upload"):return helper.call("prepare_render_upload",arrays,detail,cancelled)
 if cancelled.is_valid() and cancelled.call():return {}
 return {"arrays":arrays,"detail":detail}
func same_triangles(before:Array,old_indices:PackedInt32Array,after:Array,new_indices:PackedInt32Array)->bool:
 if old_indices.size()!=new_indices.size():return false
 for channel in CHANNELS:
  for i in old_indices.size():
   if before[channel][old_indices[i]]!=after[channel][new_indices[i]]:return false
 return true
func identity(size:int)->PackedInt32Array:
 var result:=PackedInt32Array();result.resize(size)
 for i in size:result[i]=i
 return result
func frames(n:int)->void:
 for i in n:await process_frame
func picture(viewport:SubViewport,visual:MeshInstance3D,mesh:ArrayMesh)->PackedByteArray:
 visual.mesh=mesh;await frames(10);await RenderingServer.frame_post_draw
 return viewport.get_texture().get_image().get_data()
func run()->void:
 var source=Fixture.base();source.width=64;source.depth=64
 source.heights.resize(4096);source.heights.fill(24);source.top_materials.resize(4096);source.top_materials.fill(1)
 source.cap_depths.resize(4096);source.water_levels.resize(4096)
 var bounds:=Rect2i(0,0,64,64)
 var viewport:SubViewport;var visual:MeshInstance3D
 if DisplayServer.get_name()!="headless":
  DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
  viewport=SubViewport.new();viewport.size=Vector2i(256,256);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
  var camera:=Camera3D.new();viewport.add_child(camera);camera.position=Vector3(90,80,90);camera.look_at(Vector3(32,24,32));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=90
  var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.shadow_enabled=true;viewport.add_child(sun)
  visual=MeshInstance3D.new();viewport.add_child(visual)
  var material:=Materials.compact_terrain_material();Materials.set_compact_terrain_roles(material,source.palette_surface_roles,source.palette_material_ids,source.palette);visual.material_override=material
 for kind in ["flat","slope","mixed"]:
  if kind=="mixed":
   for z in 64:
    for x in range(36,64):source.top_materials[x+z*64]=2
  var field:=Surface.field(source,bounds)
  if kind!="flat":
   for z in field.size.y:
    for x in field.size.x:
     var cell:Vector2i=field.start+Vector2i(x,z)
     field.heights[x+z*field.size.x]=24.0+0.0005*cell.x*cell.x+0.02*cell.y
  var data:=Surface.build_arrays(source,bounds,true,true,field,true)
  var original:Array=data.arrays.duplicate(true);var detail:Dictionary=data.render_detail.duplicate(true)
  var prepared:=prepare(data.arrays,data.render_detail)
  check(data.arrays==original and data.render_detail==detail,"canonical arrays/detail unchanged "+kind)
  var old_indices:PackedInt32Array=detail.indices if not detail.indices.is_empty() else identity(original[0].size())
  var new_indices:PackedInt32Array=prepared.detail.indices if not prepared.detail.indices.is_empty() else identity(prepared.arrays[0].size())
  check(same_triangles(original,old_indices,prepared.arrays,new_indices),"every base attribute/triangle exact "+kind)
  check(detail.lods.keys()==prepared.detail.lods.keys(),"native LOD thresholds unchanged "+kind)
  for error in detail.lods:check(same_triangles(original,detail.lods[error],prepared.arrays,prepared.detail.lods[error]),"every LOD attribute/triangle exact "+kind)
  if kind!="flat":check(prepared.arrays[0].size()<original[0].size()*0.8,"duplicate upload vertices removed "+kind)
  counts.append({"kind":kind,"before":original[0].size(),"after":prepared.arrays[0].size()})
  var tile_data:=Mesher.prepare_editor_tile({"source":source,"bounds":bounds,"start":Vector2i.ZERO},data,{"residency_edges":true},true)
  check(tile_data.top_arrays==original and tile_data.collision_faces==data.collision_faces,"worker tile keeps canonical geometry/physics "+kind)
  check(tile_data.get("render_upload",{}).get("arrays",[])==prepared.arrays,"worker supplies indexed upload "+kind)
  var edge:Dictionary=tile_data.residency_edge_upload
  check(same_triangles(tile_data.residency_edge_arrays,identity(tile_data.residency_edge_arrays[0].size()),edge.arrays,edge.detail.indices),"seam triangles and attributes exact "+kind)
  check(edge.arrays[0].size()<tile_data.residency_edge_arrays[0].size(),"duplicate seam vertices removed "+kind)
  var publication:=Mesher.EditorTilePublication.new(tile_data)
  while not publication.ready:publication.advance()
  check(publication.result.smooth_layout.arrays==data.layout.arrays,"alternate-look layout keeps original vertex IDs "+kind)
  check(not publication.result.has("render_upload"),"committed payload drops temporary upload arrays "+kind)
  if viewport!=null:
   var reference:=Surface.publish_render_mesh(original,detail)
   var indexed:=Surface.publish_render_mesh(prepared.arrays,prepared.detail)
   for bias in [1.0,1000.0]:
    visual.lod_bias=bias
    var expected:=await picture(viewport,visual,reference)
    check(expected==await picture(viewport,visual,indexed),"native terrain pixels/shadows exact "+kind+" bias"+str(bias))
   var seam_before:=await picture(viewport,visual,Mesher.publish_residency_edge(tile_data.residency_edge_arrays))
   check(seam_before==await picture(viewport,visual,Mesher.publish_residency_edge(edge.arrays)),"native seam pixels exact "+kind)
 check(prepare([],{},func():return true).is_empty(),"pre-cancel returns no upload")
 if viewport!=null:viewport.free()
 print("TERRAIN_RENDER_INDEXING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"counts":counts,"native":DisplayServer.get_name()!="headless"}))
 quit(0 if errors.is_empty() else 1)
