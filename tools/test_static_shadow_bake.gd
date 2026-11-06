extends SceneTree
## Read prepared native-bake fixture in the disposable checkout only.
const Surface=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const OUT="C:/Users/novos/Documents/Codex/2026-11-01/ember-static-shadow-probe"
var errors:Array[String]=[]
var report:Dictionary={"scope":"bounded stock baked-shadow compatibility; no production integration or full FPS acceptance"}
var scene:Node3D
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("STATIC_RUNTIME_FAIL ",label)
func frames(n:int)->void:
	for i in n:await process_frame
func picture(name:String)->Image:
	await frames(20);await RenderingServer.frame_post_draw
	var value:=root.get_texture().get_image();value.save_png(OUT.path_join(name+".png"));return value
func difference(a:Image,b:Image)->Dictionary:
	var sum:=0.0;var changed:=0;var maximum:=0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y)
			var d:=maxf(absf(ca.r-cb.r),maxf(absf(ca.g-cb.g),absf(ca.b-cb.b)))
			sum+=d;maximum=maxf(maximum,d)
			if d>2.0/255.0:changed+=1
	return {"mean_max_channel_error":sum/float(a.get_width()*a.get_height()),"changed_over_2_levels":changed,"maximum":maximum}
func sample(label:String)->void:
	await frames(60)
	var gpu:Array[float]=[];var wall:Array[float]=[];var previous:=Time.get_ticks_usec()
	for i in 180:
		await process_frame
		var now:=Time.get_ticks_usec();wall.append(float(now-previous)/1000.0);previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	gpu.sort();wall.sort()
	report[label]={"gpu_median_ms":gpu[90],"gpu_p95_ms":gpu[170],"wall_median_ms":wall[90],"wall_p95_ms":wall[170],"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_draws":root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	print("STATIC_RUNTIME_SAMPLE ",label," ",JSON.stringify(report[label]))
func receiver_position(node:MeshInstance3D,ground_y:float)->Vector3:
	var light:DirectionalLight3D=scene.get_node("Sun")
	var to_sun:=light.global_basis.z.normalized()
	var faces:=node.mesh.get_faces()
	var bounds:=node.global_transform*node.get_aabb()
	var chosen:=Vector3(20,ground_y+2,10)
	var best:=0.0
	for i in range(0,faces.size(),3):
		var a:=node.global_transform*faces[i];var b:=node.global_transform*faces[i+1];var c:=node.global_transform*faces[i+2]
		var center:Vector3=(a+b+c)/3.0
		if center.y<=ground_y+6 or Plane(a,b,c).normal.dot(to_sun)<=0.1:continue
		var p:=center-to_sun*((center.y-ground_y-4)/to_sun.y)
		var flat:=Vector2(p.x,p.z)
		var nearest:=flat.clamp(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.end.x,bounds.end.z))
		var distance:=flat.distance_to(nearest)
		if distance>best and absf(p.x)<55 and absf(p.z)<55:
			best=distance;chosen=Vector3(p.x,ground_y+2,p.z)
			report.receiver_ray={"top":str(p),"occluding_triangle_center":str(center),"distance_to_rock_bounds":distance}
	check(best>2,"dynamic receiver is geometrically in static rock shadow")
	return chosen
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(2560,1440);root.scaling_3d_scale=1.0;root.use_taa=false;root.mesh_lod_threshold=0.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene=load("res://qa_static_shadow/probe.tscn").instantiate();root.add_child(scene);current_scene=scene
	var camera:Camera3D=scene.get_node("Camera");camera.fov=40;camera.make_current()
	var ground:MeshInstance3D=scene.get_node("Ground");var rock:MeshInstance3D=scene.get_node("Rock")
	var gi:LightmapGI=scene.get_node("LightmapGI");var baked:=gi.light_data
	var sun:DirectionalLight3D=scene.get_node("Sun")
	rock.material_override.set_shader_parameter("material_depth_sun_direction",sun.global_basis.z.normalized())
	report.baked_users=baked.get_user_count();report.shadowmask_textures=baked.get_shadowmask_textures().size()
	check(report.shadowmask_textures>0,"saved shadowmask loads in normal runtime")
	var texture_rows:Array=[]
	for texture:TextureLayered in baked.get_lightmap_textures()+baked.get_shadowmask_textures():
		var bytes:=0
		for layer in texture.get_layers():bytes+=texture.get_layer_data(layer).get_data_size()
		texture_rows.append({"width":texture.get_width(),"height":texture.get_height(),"layers":texture.get_layers(),"format":texture.get_format(),"has_mipmaps":texture.has_mipmaps(),"image_data_bytes":bytes})
	report.baked_texture_memory=texture_rows
	gi.light_data=null;sun.shadow_enabled=false
	var adapted:=await picture("adapted-paint")
	var converted_meshes:=[ground.mesh,rock.mesh];var converted_materials:=[ground.material_override,rock.material_override]
	var source:Resource=load("res://content/world_terrains/landscape_compact.res")
	var bounds:=Rect2i(Vector2i(source.width/2-64,source.depth/2-64),Vector2i(128,128))
	var data:=Surface.build_arrays(source,bounds,true,true,Surface.field(source,bounds),true)
	var upload:=Surface.prepare_render_upload(data.arrays,data.render_detail)
	ground.mesh=Surface.publish_render_mesh(upload.arrays,upload.detail)
	var material:=Materials.compact_terrain_material();Materials.set_compact_terrain_roles(material,source.palette_surface_roles,source.palette_material_ids,source.palette)
	material.set_shader_parameter("smooth_surface_enabled",true);ground.material_override=material
	var prop:EmberVoxelProp=load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate();scene.add_child(prop);prop.set_world_look(0)
	rock.mesh=prop.get_node("Mesh").mesh
	var original:ShaderMaterial=converted_materials[1].duplicate()
	var original_shader:=Shader.new();original_shader.code=original.shader.code.replace("(mod(CUSTOM0.w,256.0)/255.0)","UV2.x").replace("floor(CUSTOM0.w/256.0)","UV2.y")
	original.shader=original_shader;rock.material_override=original
	prop.free()
	var reference:=await picture("original-paint")
	report.paint_parity=difference(reference,adapted)
	check(report.paint_parity.changed_over_2_levels<root.size.x*root.size.y/1000,"paint/finish parity after derived UV2 adaptation")
	ground.mesh=converted_meshes[0];rock.mesh=converted_meshes[1];ground.material_override=converted_materials[0];rock.material_override=converted_materials[1]
	sun.shadow_enabled=true
	await sample("realtime")
	var realtime:=await picture("realtime-shadow")
	gi.light_data=baked;gi.shadowmask_mode=LightmapGIData.SHADOWMASK_MODE_OVERLAY
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;rock.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await sample("baked_static")
	var static_picture:=await picture("baked-shadow")
	check(report.baked_static.shadow_primitives==0,"baked static shadow does not rerender static casters")
	report.realtime_vs_baked=difference(realtime,static_picture)
	gi.shadowmask_mode=LightmapGIData.SHADOWMASK_MODE_NONE
	var no_shadow:=await picture("no-shadow")
	report.mask_visible=difference(no_shadow,static_picture)
	check(report.mask_visible.changed_over_2_levels>100,"saved static shadow is visibly present")
	gi.shadowmask_mode=LightmapGIData.SHADOWMASK_MODE_OVERLAY
	var moving:=MeshInstance3D.new();moving.name="MovingShadowProbe";var box:=BoxMesh.new();box.size=Vector3(4,4,4);moving.mesh=box
	var box_material:=StandardMaterial3D.new();box_material.albedo_color=Color.WHITE;moving.material_override=box_material
	scene.add_child(moving);moving.position=receiver_position(rock,0);moving.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	await sample("baked_plus_dynamic")
	var receiver_without:=await picture("baked-dynamic-a")
	rock.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var receiver_with:=await picture("dynamic-receives-static")
	var screen_rect:=Rect2(camera.unproject_position(moving.global_position),Vector2.ZERO)
	for corner in 8:screen_rect=screen_rect.expand(camera.unproject_position(moving.global_transform*moving.get_aabb().get_endpoint(corner)))
	# Camera projection uses logical content coordinates; screenshots contain physical pixels.
	var pixel_scale:=Vector2(root.size)/root.get_visible_rect().size
	screen_rect.position*=pixel_scale;screen_rect.size*=pixel_scale
	var roi:=Rect2i(screen_rect).intersection(Rect2i(Vector2i.ZERO,root.size))
	report.dynamic_receiver_roi=str(roi)
	report.static_caster_on_dynamic_receiver=difference(receiver_without.get_region(roi),receiver_with.get_region(roi))
	report.dynamic_receiver_requires_static_caster=report.static_caster_on_dynamic_receiver.changed_over_2_levels>10
	gi.light_data=null
	var receiver_realtime:=await picture("dynamic-receiver-realtime")
	report.receiver_baked_vs_realtime=difference(receiver_without.get_region(roi),receiver_realtime.get_region(roi))
	report.receiver_caster_with_bake_vs_realtime=difference(receiver_with.get_region(roi),receiver_realtime.get_region(roi))
	gi.light_data=baked
	rock.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moving.position=Vector3(-15,7,-15);await picture("baked-dynamic-b")
	check(report.baked_plus_dynamic.shadow_primitives>0,"moving probe retains dynamic shadow pass")
	for i in 3:
		camera.position=Vector3(155-i*65,120,155+i*25);camera.look_at(Vector3.ZERO)
		await picture("camera-%d"%i)
	var rebuilt:Dictionary=preload("res://tools/fixtures/ember_lightmap_probe.gd").rebuild_lods(ground.mesh)
	ground.mesh=rebuilt.mesh;rebuilt.erase("mesh");report.rebuilt_ground_lods=rebuilt
	check(rebuilt.levels>0 and rebuilt.vertex_bytes_unchanged,"rebuild native terrain LOD with exact baked vertex streams")
	await frames(20)
	var full_primitives:=root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	root.mesh_lod_threshold=1.0;await frames(20)
	report.lod_visible_primitives={"full":full_primitives,"automatic":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
	check(report.lod_visible_primitives.automatic<full_primitives,"baked ground actually uses native LOD")
	await picture("baked-native-lod")
	report.camera={"viewport":str(root.size),"scale":root.scaling_3d_scale,"fov":camera.fov,"near":camera.near,"far":camera.far}
	report.errors=errors
	FileAccess.open(OUT.path_join("runtime-result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("STATIC_RUNTIME_RESULT ",JSON.stringify(report))
	gi.light_data=null;scene.queue_free();await frames(3)
	quit(0 if errors.is_empty() else 1)
