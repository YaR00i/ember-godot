extends SceneTree
## Actual contact-foam fragment: patches from a wave, never a uniform contour stroke.
var failures: Array[String] = []
var viewport: SubViewport
var material: ShaderMaterial
var image: Image
var texture: ImageTexture
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); printerr("FOAM_CONTACT FAIL ", label)
func sample(response: Color) -> Image:
	image.fill(response); texture.update(image)
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func mean(value: Image) -> float:
	var total := 0.0
	for y in value.get_height():
		for x in value.get_width(): total += value.get_pixel(x, y).r
	return total/(value.get_width()*value.get_height())
func ring_coverage(value: Image) -> float:
	var count := 0
	for i in 180:
		var point := Vector2(127.5,127.5) + Vector2.from_angle(i*TAU/180.0)*66.4
		if value.get_pixel(roundi(point.x),roundi(point.y)).r>0.03: count+=1
	return count/180.0
func difference(a: Image, b: Image) -> float:
	var total:=0.0
	for y in a.get_height():
		for x in a.get_width():total+=absf(a.get_pixel(x,y).r-b.get_pixel(x,y).r)
	return total/(a.get_width()*a.get_height())
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	viewport=SubViewport.new(); viewport.size=Vector2i(256,256); viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var mesh:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(64,64); mesh.mesh=plane; viewport.add_child(mesh)
	var code:=FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader")
	var shader:=Shader.new()
	shader.code=code.substr(0,code.find("void vertex()"))+"""
void vertex() { water_point=VERTEX.xz/16.0; }
void fragment() {
 float foam=study_object_foam(water_point,0.0,0.0);
 EMISSION=vec3(foam); ALBEDO=vec3(0.0); SPECULAR=0.0; ALPHA=1.0;
}
"""
	material=ShaderMaterial.new(); material.shader=shader; mesh.material_override=material
	image=Image.create_empty(33,33,false,Image.FORMAT_RGBAF); texture=ImageTexture.create_from_image(image)
	var shapes:=PackedVector4Array(); shapes.resize(8); shapes[0]=Vector4(0,0,0.5,0.5)
	var meta:=PackedVector2Array(); meta.resize(8); meta[0]=Vector2(1,0)
	var bounds:=PackedVector4Array(); bounds.resize(4); bounds[0]=Vector4(-64,-64,9,1)
	var parameters: Dictionary={"object_contact_available":1.0,"object_wave_interaction":1.0,"object_shape_count":1,"object_shapes":shapes,
		"object_shape_meta":meta,"object_foam_strength":0.5,"object_foam_width_voxels":0.55,"obstacle_mode":2,
		"obstacle_patch_count":1,"obstacle_strength":1.0,"obstacle_bounds":bounds,"obstacle_live_field":texture}
	for key in parameters: material.set_shader_parameter(key,parameters[key])
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=32; camera.position=Vector3(0,32,0); camera.look_at(Vector3.ZERO,Vector3.FORWARD); camera.make_current()
	check(mean(await sample(Color(0,0,8,1)))<0.0001,"quiet water creates a permanent outline")
	check(mean(await sample(Color(0,0.8,0.2,1)))<0.0001,"ambient height alone paints an outline without local disturbance")
	var active: Image=await sample(Color(0.4,0.8,0.2,1)); var active_mean:=mean(active); var coverage:=ring_coverage(active)
	check(active_mean>0.0005,"local crest produces no visible contact foam")
	check(coverage<0.65,"contact foam is a closed geometric ring")
	check(mean(await sample(Color(0.4,0.8,8,1)))<0.0001,"expired contact foam does not disappear")
	material.set_shader_parameter("object_foam_sharpness",0.0);var soft: Image=await sample(Color(0.4,0.8,0.2,1))
	material.set_shader_parameter("object_foam_sharpness",1.0)
	check(difference(soft,await sample(Color(0.4,0.8,0.2,1)))>0.0001,"existing sharpness control has no visible effect")
	material.set_shader_parameter("object_foam_width_voxels",2.0)
	check(mean(await sample(Color(0.4,0.8,0.2,1)))>active_mean*1.15,"existing width control has no visible effect")
	camera.size=48
	var wide: float=mean(await sample(Color(0.4,0.8,0.2,1)))
	material.set_shader_parameter("object_foam_width_voxels",3.0)
	check(mean(await sample(Color(0.4,0.8,0.2,1)))>wide*1.05,"upper width range is silently clipped")
	material.set_shader_parameter("object_foam_strength",0.0)
	check(mean(await sample(Color(0.4,0.8,0.2,1)))<0.0001,"existing strength zero does not disable foam")
	material.set_shader_parameter("object_foam_strength",0.5); material.set_shader_parameter("object_wave_interaction",0.0)
	check(mean(await sample(Color(0,0,8,1)))>0.001,"legacy contact path changed")
	print("FOAM_CONTACT ","PASS" if failures.is_empty() else "FAIL"," mean=",active_mean," ring_coverage=",coverage," failures=",failures.size())
	viewport.free(); quit(0 if failures.is_empty() else 1)
