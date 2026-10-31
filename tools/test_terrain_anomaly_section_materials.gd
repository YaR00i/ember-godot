extends SceneTree
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Meshes=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
func fill(width:int,depth:int)->EmberTerrainPilotResource:
 var s:=Terrain.new();s.width=width;s.depth=depth;s.height_limit=64;s.origin_y=-32
 s.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.GREEN,Color.TAN,Color.WHITE,Color.BLUE,Color.GRAY])
 for key in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:
  var a:Variant=PackedInt32Array() if key in ["heights","water_levels"] else PackedByteArray()
  a.resize(width*depth);a.fill(40 if key=="heights" else 3 if key=="cap_depths" else 2 if key=="top_materials" else 1 if key=="base_materials" else 0);s.set(key,a)
 return s
func _initialize()->void:
 var dense:=fill(416,32);dense.column_material_overrides[385+416]={39:6}
 var part:=fill(32,32);part.column_material_overrides[1+32]={39:6}
 var sectioned:Terrain=part.sectioned_copy();sectioned.width=416;sectioned.sections={Vector2i.RIGHT:part}
 var a:=Meshes.Triangles.new();var b:=Meshes.Triangles.new()
 for side in 4:
  Meshes._add_side(dense,a,385,1,40,35,side);Meshes._add_side(sectioned,b,385,1,40,35,side)
 assert(a.vertices.size()>0 and a.vertices==b.vertices and a.colors==b.colors and a.normals==b.normals,"section risers must match dense positions/materials/overrides")
 print("ANOMALY_SECTION_MATERIALS PASS");quit()
