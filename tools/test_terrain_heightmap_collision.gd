extends SceneTree
const Surface=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Mesher=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Cache=preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
class QuietProjection extends TerrainProjection:
 func _ready():pass
 func _process(_dt):pass
var errors:Array[String]=[]
var worst_height:=0.0
var worst_normal:=0.0
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func body(shape:Shape3D,position:Vector3,layer:int)->StaticBody3D:
 var host:=StaticBody3D.new();host.collision_layer=layer
 var collider:=CollisionShape3D.new();collider.name="Shape";collider.shape=shape;collider.position=position
 host.add_child(collider);root.add_child(host);return host
func _initialize():run.call_deferred()
func run():
 var source=Fixture.base();source.heights.fill(24);source.top_materials.fill(2)
 var bounds:=Rect2i(16,16,64,64)
 for mode in ["flat","slope","paint","hole","edge"]:
  var changed=source.working_copy()
  if mode=="slope":changed.heights[changed.column_index(40,40)]+=6
  elif mode=="paint":changed.top_materials[changed.column_index(40,40)]=3
  elif mode=="hole":changed.top_materials[changed.column_index(40,40)]=0
  var area:=Rect2i(0,0,64,64) if mode=="edge" else bounds
  var smooth:Dictionary=Surface.build_arrays(changed,area,true,true,{},true)
  var data:=Mesher.prepare_editor_tile({"source":changed,"bounds":area,"start":Vector2i.ZERO},smooth,{},false)
  var publication:=Mesher.EditorTilePublication.new(data)
  while not publication.ready:publication.advance()
  var result:Dictionary=publication.result
  check((result.collision is HeightMapShape3D)==(mode in ["flat","slope","paint"]),"height field versus exact triangle fallback: "+mode)
  check(result.collision_faces==smooth.collision_faces,"canonical faces unchanged: "+mode)
  var triangles:=ConcavePolygonShape3D.new();triangles.set_faces(smooth.collision_faces)
  var original:=body(triangles,Vector3.ZERO,1)
  var candidate:=body(result.collision,result.get("collision_position",Vector3.ZERO),2)
  await physics_frame;await physics_frame
  var world:=root.world_3d.direct_space_state
  for z in 32:
   for x in 32:
    var point:=Vector3(area.position.x+x*2+0.37,100,area.position.y+z*2+0.61)
    var a:=world.intersect_ray(PhysicsRayQueryParameters3D.create(point,point-Vector3(0,200,0),1))
    var b:=world.intersect_ray(PhysicsRayQueryParameters3D.create(point,point-Vector3(0,200,0),2))
    check(a.is_empty()==b.is_empty(),"ray coverage "+mode)
    if a.is_empty() or b.is_empty():continue
    worst_height=maxf(worst_height,a.position.distance_to(b.position));worst_normal=maxf(worst_normal,a.normal.distance_to(b.normal))
  original.free();candidate.free()
 check(worst_height<0.0001 and worst_normal<0.00001,"physical height and triangle normals match through slopes/cell diagonals")
 var wide=source.working_copy();wide.width=256;wide.depth=256
 for channel:String in source.Sections.CHANNELS:
  var values=wide.get(channel);var value=values[0];values.resize(256*256);values.fill(value);wide.set(channel,values)
 var cache:=Cache.new();cache.directory="user://ember-tests/heightmap-collision-"+str(OS.get_process_id())
 var sectioned=wide.sectioned_copy()
 var cold=cache.editor_job(sectioned,Vector2i(1,1),true,{"step":0});cold.run(func():return false)
 var warm=cache.editor_job(sectioned,Vector2i(1,1),true,{"step":0});warm.run(func():return false)
 check(warm.cache_hit and not cold.tile_data.heightmap_collision.is_empty() and cold.tile_data.heightmap_collision==warm.tile_data.heightmap_collision,"cold/cache physics payload parity")
 check(warm.tile_data.heightmap_collision.position==Vector3(96,0,96),"section collision offset preserved")
 var projection:=QuietProjection.new();root.add_child(projection);projection.ground_style=1
 var tile:=Node3D.new();projection.add_child(tile)
 var host:=StaticBody3D.new();host.name="GroundPhysics";tile.add_child(host)
 var collider:=CollisionShape3D.new();collider.name="Shape";collider.shape=HeightMapShape3D.new();collider.position=Vector3(96,0,96);host.add_child(collider)
 projection._tiles[Vector2i.ZERO]=tile
 var full:=Surface.build_arrays(source,bounds,true)
 check(projection.apply_study_smooth_tile(Vector2i.ZERO,full.smooth_field,full.collision_faces) and collider.shape is ConcavePolygonShape3D and collider.position==Vector3.ZERO,"existing deform study returns to exact arbitrary triangle collision")
 projection.free()
 var affine:=QuietProjection.new();root.add_child(affine);affine.document=source;affine.ground_style=1;affine.scale=Vector3(2,1,1)
 var prepared:Dictionary=Surface.build_arrays(source,bounds,true,true,{},true)
 var publish:=Mesher.EditorTilePublication.new(Mesher.prepare_editor_tile({"source":source,"bounds":bounds,"start":Vector2i.ZERO},prepared,{},false))
 while not publish.ready:publish.advance()
 check(publish.result.collision is HeightMapShape3D,"nonuniform fallback starts with a heightmap candidate")
 affine._rebuild_tile(Vector2i.ZERO,{},prepared,publish.result)
 var affine_collider:=affine._tiles[Vector2i.ZERO].get_node("GroundPhysics/Shape") as CollisionShape3D
 check(affine_collider.shape is ConcavePolygonShape3D and affine_collider.position==Vector3.ZERO and affine_collider.shape.get_faces()==prepared.collision_faces,"nonuniform maps preserve exact triangle placement")
 affine.free()
 print("TERRAIN_HEIGHTMAP_COLLISION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"rays":5120,"max_height_error":worst_height,"max_normal_error":worst_normal}))
 quit(0 if errors.is_empty() else 1)
