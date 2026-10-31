extends SceneTree
## Real fragment output: rare patches, crest birth/decay and the author controls.
var failures: Array[String]=[]
var viewport: SubViewport
var material: ShaderMaterial
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);printerr("CREST_FOAM FAIL ",label)
func image_difference(a: Image,b: Image) -> float:
	var total:=0.0
	for y in a.get_height():
		for x in a.get_width():total+=absf(a.get_pixel(x,y).r-b.get_pixel(x,y).r)
	return total/(a.get_width()*a.get_height())
func sample(age: float) -> float:
	var speed: float=material.get_shader_parameter("wave_speed")
	material.set_shader_parameter("test_crest_phase",PI*0.5-age*speed)
	material.set_shader_parameter("test_seconds",age)
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	var total:=0.0
	for y in image.get_height():
		for x in image.get_width():total+=image.get_pixel(x,y).r
	return total/(image.get_width()*image.get_height())
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	viewport=SubViewport.new();viewport.size=Vector2i(256,256);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(128,128)
	mesh.mesh=plane;mesh.position=Vector3(48,0,48);viewport.add_child(mesh)
	var code:=FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader")
	var shader:=Shader.new()
	shader.code=code.substr(0,code.find("void fragment()"))+"""
uniform float test_crest_phase;
uniform float test_amplitude = 3.2;
uniform float test_seconds;
void fragment() {
 float foam=study_sea_crest_foam(water_point,test_seconds,test_crest_phase,test_amplitude);
 EMISSION=vec3(foam);ALBEDO=vec3(0.0);SPECULAR=0.0;ALPHA=1.0;
}
"""
	material=ShaderMaterial.new();material.shader=shader
	var parameters: Dictionary={"sea_crest_foam_strength":0.55,"sea_crest_foam_amount":0.35,"sea_foam_trail_lifetime":2.9,"wave_speed":0.42,"wave_height_voxels":3.2}
	for key in parameters:material.set_shader_parameter(key,parameters[key])
	mesh.material_override=material
	var camera:=Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=96;camera.position=Vector3(48,64,48);camera.look_at(Vector3(48,0,48),Vector3.FORWARD);camera.current=true
	var peak: float=await sample(0.0)
	check(peak>0.005 and peak<0.25,"foam is visible at the crest without filling the surface")
	check(await sample(-1.5)<0.001,"foam starts before the rise window")
	var rise: float=await sample(-0.5)
	check(rise>0.001 and rise<peak*0.95,"foam grows toward the crest")
	check(absf(await sample(-0.02)-await sample(0.02))<maxf(peak*0.1,0.0001),"patch seed changes at the crest")
	check(await sample(0.8)<peak*0.95,"foam does not subside after the crest")
	check(await sample(3.0)<0.001,"foam did not expire")
	check(await sample(1.5)>0.0001,"residual foam vanishes with the descending crest")
	material.set_shader_parameter("test_amplitude",0.0)
	check(await sample(0.4)<0.001,"foam appeared without wave amplitude")
	material.set_shader_parameter("test_amplitude",0.2)
	check(await sample(0.0)<peak*0.3,"low wave shoulders are as foamy as high crests")
	material.set_shader_parameter("test_amplitude",3.2)
	for key in ["sea_crest_foam_strength","sea_crest_foam_amount","wave_height_voxels","wave_speed"]:
		var previous: Variant=material.get_shader_parameter(key);material.set_shader_parameter(key,0.0)
		check(await sample(0.4)<0.001,key+" zero did not disable crest foam")
		material.set_shader_parameter(key,previous)
	material.set_shader_parameter("sea_crest_foam_amount",0.7)
	check(await sample(0.0)>peak*1.2,"amount did not grow sparse patches")
	material.set_shader_parameter("wave_speed",2.0);material.set_shader_parameter("sea_foam_trail_lifetime",4.0)
	var before_trough: float=await sample(PI/2.0-0.01)
	var before_image:=viewport.get_texture().get_image()
	var after_trough: float=await sample(PI/2.0+0.01)
	check(before_trough>0.0001 and after_trough>0.0001,"residual foam was cut off at the trough")
	check(absf(before_trough-after_trough)<peak*0.1,"residual foam changes seed at the trough")
	check(image_difference(before_image,viewport.get_texture().get_image())<peak*0.15,"individual residual patches jump at the trough")
	print("CREST_FOAM ","PASS" if failures.is_empty() else "FAIL"," peak=",peak," rise=",rise," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
