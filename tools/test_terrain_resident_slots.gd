extends SceneTree
class Probe extends EmberTerrainPilotProjection:
 func _editor_residency_allowed()->bool:return true
 func _publish_overview(_key:Vector2i,_covered:Dictionary)->void:pass
 func _apply_region_materials(_key:Vector2i,_tile:Node3D)->void:pass
 func _region_ground_material(_key:Vector2i)->ShaderMaterial:return ShaderMaterial.new()
 func _far_material(base:ShaderMaterial)->ShaderMaterial:return base
var changes:=0
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);printerr("TERRAIN_SLOT_FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var projection:=Probe.new();root.add_child(projection);projection.set_process(false)
 projection.ground_style=1
 projection.document=EmberTerrainPilotResource.new();projection.document.width=128;projection.document.depth=64
 projection.smooth_column_limit=8192;projection._ground_material=ShaderMaterial.new();projection._water_material=ShaderMaterial.new()
 if projection.has_method("_prepare_resident_tile_slots"):projection._prepare_resident_tile_slots()
 var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
 var faces:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD,Vector3.RIGHT,Vector3(1,0,1),Vector3.FORWARD])
 arrays[Mesh.ARRAY_VERTEX]=faces
 arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,3,4,5])
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{1.0:PackedInt32Array([0,1,2])})
 var generated:Dictionary={"terrain":mesh,"water":ArrayMesh.new(),"collision_faces":faces,"residency_edge_arrays":arrays}
 projection._overviews[Vector2i.ZERO]={}
 projection._rebuild_tile(Vector2i.ZERO,{},{},generated)
 var original:Node3D=projection._tiles[Vector2i.ZERO]
 var ground:=original.get_node("Ground") as MeshInstance3D
 var hover:=StandardMaterial3D.new()
 projection.set_editor_hover_overlay(hover,[Vector2i.ZERO])
 check(ground.lod_bias>=100000.0,"brush hover keeps the exact render surface")
 projection._rebuild_tile(Vector2i.ZERO,{},{},generated)
 check(ground.lod_bias>=100000.0,"rebuilt brush tile retains exact render surface")
 projection.set_editor_hover_overlay(null,[])
 check(is_equal_approx(ground.lod_bias,projection.RUNTIME_GROUND_LOD_BIAS),"leaving brush restores ordinary distance LOD")
 if DisplayServer.get_name()!="headless":
  var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.cull_mode=BaseMaterial3D.CULL_DISABLED
  ground.material_override=material;ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  original.get_node("ResidencyEdge").hide()
  var camera:=Camera3D.new();root.add_child(camera);camera.far=20000.0;camera.make_current()
  camera.look_at_from_position(Vector3(0.5,10000,6000),Vector3(0.5,0,0.5))
  var rendered:Array[int]=[]
  for protected in [false,true,false]:
   var hovered:Array[Vector2i]=[]
   if protected:hovered.append(Vector2i.ZERO)
   projection.set_editor_hover_overlay(hover if protected else null,hovered)
   # Count the terrain indices alone, without the overlay's extra draw pass.
   ground.material_overlay=null
   for frame in 8:await process_frame
   await RenderingServer.frame_post_draw
   rendered.append(root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
  check(rendered==[1,2,1],"native renderer selects coarse/fine/coarse indices under brush: %s"%[rendered])
  print("TERRAIN_BRUSH_RENDER ",rendered)
  camera.free()
 projection.set_editor_hover_overlay(hover,[Vector2i.ZERO])
 tree_changed.connect(func():changes+=1)
 projection._forget_fine_tile(Vector2i.ZERO)
 check((original.get_node("Ground") as MeshInstance3D).mesh==null,"departed slot releases its mesh")
 check((original.get_node("GroundPhysics/Shape") as CollisionShape3D).shape==null,"departed slot releases physics")
 check(not original.visible,"departed slot is hidden")
 projection._rebuild_tile(Vector2i(1,0),{},{},generated)
 check(changes==0,"release and reuse do not change the editor scene tree")
 check(projection._tiles[Vector2i(1,0)]==original,"released host reused for another tile")
 check(is_equal_approx(ground.lod_bias,projection.RUNTIME_GROUND_LOD_BIAS),"reused host does not inherit another tile's brush protection")
 projection.set_editor_hover_overlay(null,[])
 check((original.get_node("GroundPhysics/Shape") as CollisionShape3D).shape.get_faces()==faces,"reused slot restores exact physics")
 for i in 32:
  projection._forget_fine_tile(Vector2i(1,0));projection._rebuild_tile(Vector2i(1,0),{},{},generated)
 check(changes==0 and projection._resident_tile_slots.size()==1,"repeated travel keeps a bounded fixed topology")
 var packed:=PackedScene.new();check(packed.pack(projection)==OK and packed.get_state().get_node_count()==1,"disposable slots do not enter scene serialization")
 var travel_changes:=changes
 projection._rebuild_tile(Vector2i.ZERO,{},{},generated)
 projection._rebuild_tile(Vector2i(2,0),{},{},generated)
 projection._forget_fine_tile(Vector2i(2,0))
 check(projection._tiles.size()+projection._resident_tile_slots.size()==2,"temporary protected overflow does not retain extra empty hosts")
 projection._overviews.clear();projection.free();await process_frame
 print("TERRAIN_RESIDENT_SLOTS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"changes":travel_changes}));quit(0 if errors.is_empty() else 1)
