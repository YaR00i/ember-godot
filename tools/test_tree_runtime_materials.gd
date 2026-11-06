extends SceneTree
## Binding regression: real Prop/Map owners;synthetic named surfaces, no author maps.
class BindingMap extends EmberMapLoader:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func make_prop(map:BindingMap,meshes:Dictionary)->EmberVoxelProp:
	var prop:=EmberVoxelProp.new();prop.water_contact_enabled=false
	var visual:=MeshInstance3D.new();visual.name="Mesh";visual.mesh=meshes[0];prop.add_child(visual)
	prop._tree_meshes=meshes.duplicate();map.add_child(prop);prop.set_world_look(0)
	return prop
func active(prop:EmberVoxelProp)->ShaderMaterial:
	return prop.get_node("Mesh").get_surface_override_material(0) as ShaderMaterial
func run()->void:
	var shader:=Shader.new()
	shader.code="shader_type spatial;uniform vec4 pigment : source_color=vec4(1.0);uniform bool voxel_light_enabled=false;uniform bool voxel_light_anomaly=false;uniform float voxel_light_cell=1.0;uniform float voxel_light_levels=8.0;instance uniform float tint_factor=1.0;void fragment(){ALBEDO=pigment.rgb*tint_factor;}"
	var source:=ShaderMaterial.new();source.shader=shader;source.set_shader_parameter("pigment",Color.GREEN)
	source.set_shader_parameter("voxel_light_levels",8.0);source.set_shader_parameter("voxel_light_enabled",false)
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,PlaneMesh.new().get_mesh_arrays());mesh.surface_set_name(0,"tree_bark");mesh.surface_set_material(0,source)
	var meshes:Dictionary={0:mesh,1:mesh,2:mesh}
	var scene:=Node3D.new();root.add_child(scene)
	var map_a:=BindingMap.new();var map_b:=BindingMap.new();map_a.voxel_light_levels=8;map_b.voxel_light_levels=32
	scene.add_child(map_a);scene.add_child(map_b)
	var a:=make_prop(map_a,meshes);var b:=make_prop(map_a,meshes);var c:=make_prop(map_b,meshes)
	check(active(a)==active(b),"identical props share runtime material within map")
	a.get_node("Mesh").set_instance_shader_parameter("tint_factor",0.5)
	b.get_node("Mesh").set_instance_shader_parameter("tint_factor",1.0)
	check(a.get_node("Mesh").get_instance_shader_parameter("tint_factor")!=b.get_node("Mesh").get_instance_shader_parameter("tint_factor") and active(a)==active(b),"instance values stay independent on shared material")
	check(active(a)!=source and active(a)!=active(c),"source and different maps remain isolated")
	check(active(a).get_shader_parameter("voxel_light_levels")==8.0 and active(c).get_shader_parameter("voxel_light_levels")==32.0,"map lighting does not leak")
	var bindings:Array=[]
	for look in 3:
		a.set_world_look(look);b.set_world_look(look)
		check(active(a)==active(b),"same look shares material "+str(look))
		check(active(a).get_shader_parameter("voxel_light_enabled")== (look==2),"look lighting flag "+str(look))
		bindings.append(active(a))
	check(bindings[0]!=bindings[1] and bindings[1]!=bindings[2],"look caches stay separate even with same source")
	a.set_world_look(0);b.set_world_look(0)
	check(active(a)==bindings[0],"return to original look reuses binding")
	var override:=ShaderMaterial.new();override.shader=shader;override.set_shader_parameter("pigment",Color.RED)
	b.get_node("Mesh").set_surface_override_material(0,override);b.apply_voxel_light_settings(map_a)
	check(active(b)!=active(a) and active(b).get_shader_parameter("pigment")==Color.RED,"individual authored override stays distinct")
	var old_red:=active(b)
	override.set_shader_parameter("pigment",Color.BLUE);b._voxel_light_tree_meshes.clear();b.apply_voxel_light_settings(map_a)
	check(active(b).get_shader_parameter("pigment")==Color.BLUE and old_red.get_shader_parameter("pigment")==Color.RED,"changed source parameters produce new binding without mutating old one")
	check(source.get_shader_parameter("pigment")==Color.GREEN and source.get_shader_parameter("voxel_light_levels")==8.0 and source.get_shader_parameter("voxel_light_enabled")==false,"authored source values unchanged")
	var av:MeshInstance3D=a.get_node("Mesh");var bv:MeshInstance3D=b.get_node("Mesh")
	check(av.mesh==mesh and bv.mesh==mesh,"geometry stays shared and unchanged")
	var temporary:=ShaderMaterial.new();temporary.shader=shader
	var derived:=map_a.runtime_tree_material(temporary,0);var weak:WeakRef=weakref(derived)
	derived=null
	check(weak.get_ref()==null,"map registry does not pin unused material")
	temporary=null
	var map_ref:WeakRef=weakref(map_a)
	scene.free();await process_frame
	check(map_ref.get_ref()==null,"map and its registry release")
	print("TREE_RUNTIME_MATERIALS ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"scope":"bindings/private override/3looks/map isolation/source changes/release;editor native path still needs manual visual acceptance"}))
	quit(0 if failures.is_empty() else 1)
