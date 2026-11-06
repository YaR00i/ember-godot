extends Node3D
## Isolated Terrain3D field test. All positions, distances and densities are metres.
const Cover = preload("cover.gd")
const Scenery = preload("scenery.gd")
const MARKS := ["village","forest","meadow","rocks","lake","mountain"]
var spec: Dictionary
var terrain
var actor: EmberPlayer
var rig: EmberFollowCamera
var cover: Cover
const Meadow = preload("meadow.gd")
var meadow: Meadow
var population: Node3D
const SHAPES := ["Отдельные GPU-травинки","Прежние пучки · 8 треугольников","Карточки к камере","Широкие пучки полигона"]
var water_material: ShaderMaterial
var swash_height := 0.175
var shore_profile: ImageTexture
var scenery: Scenery
var dataset: String
var ui: Label
var grass_level := 1.0
var flower_level := 1.0
var shadow_level := 2
var ready_to_play := false
var stress := false
var surveying := false
var active_mark := "village"
var report := {"sites":{}, "rays":[], "errors":[]}
var last_label := 0
var last_frame_us:=0
var window_start_us:=0
var window_frames:=0
var window_peak_ms:=0.0
var frame_label:="Замер…"
var quality: VBoxContainer
var atlas_size := 4096
var filter_quality := 1
@export var water_settings: Dictionary

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--bake" in args and args.find("--bake")+1 < args.size():
		dataset = args[args.find("--bake")+1]
	else:dataset = FileAccess.get_file_as_string("res://active-world.txt").strip_edges()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dataset+"/world.json"))
	if not parsed is Dictionary or not ClassDB.class_exists("Terrain3D"):
		fail("Dataset or Terrain3D missing");return
	spec = parsed
	stress = "--stress" in OS.get_cmdline_user_args()
	if stress:
		report["focus_changes"]=[]
		get_window().focus_exited.connect(func():report.focus_changes.append([Time.get_ticks_usec(),false]))
		get_window().focus_entered.connect(func():report.focus_changes.append([Time.get_ticks_usec(),true]))
	var heights := FileAccess.get_file_as_bytes(dataset+"/height.f32")
	if heights.size() != int(spec.pixels)*int(spec.pixels)*4:
		fail("Height payload size differs from manifest");return
	var h := Image.create_from_data(spec.pixels,spec.pixels,false,Image.FORMAT_RF,heights)
	var colors := Image.load_from_file(dataset+"/color.png")
	var mask := Image.load_from_file(dataset+"/foliage.png")
	if colors == null or mask == null:
		fail("Missing terrain color or vegetation map");return
	var region_dir := dataset+"/regions"
	var loaded := DirAccess.dir_exists_absolute(region_dir) and DirAccess.get_files_at(region_dir).size() == 16
	var staging := Node3D.new()
	staging.position = location_point("village",h)
	add_child(staging)
	var startup_camera := Camera3D.new()
	staging.add_child(startup_camera)
	startup_camera.current = true
	terrain = ClassDB.instantiate("Terrain3D")
	terrain.name = "HeightTerrain"
	terrain.free_editor_textures = false
	terrain.vertex_spacing = float(spec.size_m)/int(spec.pixels)
	if loaded:terrain.data_directory = region_dir
	add_child(terrain)
	terrain.region_size = 256
	terrain.mesh_size = 32
	terrain.mesh_lods = 6
	terrain.material.world_background = 0
	terrain.set_camera(startup_camera)
	terrain.set_clipmap_target(staging)
	# This fixture already holds all sixteen immutable height regions. Build
	# their floor once, instead of moving a Jolt heightmap window during play.
	var floor_start:=Time.get_ticks_usec()
	var moving_reference: bool="--field-profile" in args and "--moving-floor-reference" in args
	terrain.collision.mode = 0 if "--bake" in args else 1 if moving_reference else 3
	report["floor_setup_ms"]=(Time.get_ticks_usec()-floor_start)/1000.
	report["terrain_collision_mode"]=terrain.collision.mode
	terrain.set_collision_target(staging)
	if not loaded:
		var images: Array[Image] = [h,null,colors]
		terrain.data.import_images(images,Vector3.ZERO)
		DirAccess.make_dir_recursive_absolute(region_dir)
		terrain.data.save_directory(region_dir)
	var regions: int = terrain.data.get_region_locations().size()
	if regions != 16 or not is_equal_approx(terrain.vertex_spacing*256.0*4.0,1000.0):
		fail("Terrain extent/region count mismatch: "+str(regions));return
	if "--bake" in OS.get_cmdline_user_args():
		if Scenery.bake_tree_lods(dataset) != OK or DirAccess.get_files_at(region_dir).size() != 16:
			fail("Saving tree LODs or terrain regions failed");return
		if not bake_water(h):fail("Cannot save lake mesh");return
		print("KILOMETRE_BAKED ",regions," regions, seed ",spec.seed)
		get_tree().quit();return
	var shader := Shader.new()
	var minimum := FileAccess.get_file_as_string("res://addons/terrain_3d/extras/shaders/minimum.gdshader")
	if not minimum.contains("ALBEDO = vec3(.2);"):
		fail("Unsupported Terrain3D minimum shader");return
	var bank_code:=FileAccess.get_file_as_string("res://kilometre/bank.gdshaderinc")
	var paint := bank_code+"\n"+FileAccess.get_file_as_string("res://kilometre/ground.gdshaderinc")
	shader.code = minimum.replace("specular_schlick_ggx","specular_disabled").replace("void fragment()",paint+"\nvoid fragment()").replace("ALBEDO = vec3(.2);","ALBEDO = ground_paint(v_vertex,w_normal); SPECULAR=0.0;")
	terrain.material.shader_override = shader
	terrain.material.shader_override_enabled = true
	terrain.material.show_checkered = false
	terrain.material.set_shader_param("ember_color",ImageTexture.create_from_image(colors))
	var layer_map := dataset+"/surface.png"
	if FileAccess.file_exists(layer_map):
		terrain.material.set_shader_param("surface_weights",ImageTexture.create_from_image(Image.load_from_file(layer_map)))
		terrain.material.set_shader_param("has_weights",true)
	terrain.material.set_shader_param("waterline",spec.water_y)
	for kind in ["grass","stone","sand"]:
		var pattern := load("res://content/terrain_materials/cartoon_"+kind+".tres") as EmberCompactTerrainPattern
		terrain.material.set_shader_param(kind+"_paint",pattern.albedo_texture)
		terrain.material.set_shader_param(kind+"_period",pattern.pattern_size_m)
	scenery = Scenery.new()
	add_child(scenery)
	scenery.setup(spec.props,terrain,dataset)
	cover = Cover.new()
	add_child(cover)
	var height_tex:=ImageTexture.create_from_image(h)
	shore_profile=make_shore_profile()
	terrain.material.set_shader_param("bank_profile",shore_profile)
	terrain.material.set_shader_param("bank_floor",height_tex)
	terrain.material.set_shader_param("bank_level",spec.water_y)
	var mask_tex:=ImageTexture.create_from_image(mask)
	var color_tex:=ImageTexture.create_from_image(colors)
	cover.setup(spec,height_tex,mask_tex,color_tex)
	meadow=Meadow.new()
	add_child(meadow)
	await meadow.setup(spec,height_tex,mask_tex,color_tex)
	if not meadow.ready_field:fail("QA grass renderer: "+meadow.state.error);return
	set_shape(1)
	population=preload("population.gd").new()
	add_child(population)
	make_water(h,height_tex,bank_code)
	actor = EmberPlayer.new()
	actor.tile_size = 1.0
	actor.walk_modifier_key = KEY_CTRL
	actor.boost_modifier_key = KEY_SHIFT
	actor.position = staging.position+Vector3.UP
	add_child(actor)
	actor.install_hoshi_test_visual()
	rig = EmberFollowCamera.new()
	rig.target = actor
	rig.follow_distance = 5.8
	rig.look_height = 1.15
	rig.polar_angle = 1.39
	rig.pitch_lock = false
	rig.polar_max = 1.53
	rig.fov = 70
	rig.cam_near = 0.12
	rig.cam_far = 1800
	add_child(rig)
	actor.camera_rig = rig
	terrain.set_camera(rig._cam)
	terrain.set_clipmap_target(actor)
	terrain.set_collision_target(actor)
	staging.queue_free()
	make_hud()
	ready_to_play = true
	await go_to("village")
	report["startup_s"] = Time.get_ticks_msec()/1000.0
	report["seed"] = spec.seed
	report["regions"] = regions
	report["props"] = spec.placed
	report["prop_batches"] = scenery.groups
	print("KILOMETRE_READY ",spec.seed," ",spec.props.size()," props, ",scenery.groups," batches")
	if stress:await benchmark()

func fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)

func location_point(key: String, image: Image = null) -> Vector3:
	var point: Array = spec.landmarks[key]
	var pos := Vector3(point[0],0,point[1])
	if image != null:
		pos.y = image.get_pixel(clampi(roundi(pos.x*1.024),0,1023),clampi(roundi(pos.z*1.024),0,1023)).r
	else:
		pos.y = terrain.data.get_surface_height(pos)
	return pos

func place(point: Vector3) -> void:
	actor.global_position = point+Vector3.UP*0.35
	actor.velocity = Vector3.ZERO
	rig.reset_follow_height()
	scenery.follow(actor.global_position)
	cover.follow(actor.global_position)
	if terrain.collision.mode==1:
		terrain.collision.update(Vector2i(2147483647,2147483647),true)
	for i in 3:await get_tree().physics_frame

func go_to(key: String) -> void:
	active_mark = key
	var pos := location_point(key)
	await place(pos)
	var target := location_point("village" if key == "mountain" else "mountain")
	rig.yaw = atan2(pos.x-target.x,pos.z-target.z)

func sunset_view() -> void:
	await go_to("lake")
	var towards_sun: Vector3 = $Sun.global_basis.z
	rig.yaw = atan2(-towards_sun.x,-towards_sun.z)

func bake_water(h: Image) -> bool:
	# Local coordinates match Ember's wave amplitude in voxels. Build only
	# wet cells and their immediate banks, with depth in the native colour lane.
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var ids := {}
	const STEP := 1
	for z in range(0,1000,STEP):
		for x in range(0,1000,STEP):
			var sample_x := mini(roundi((x+1)*1.024),1023)
			var sample_z := mini(roundi((z+1)*1.024),1023)
			if h.get_pixel(sample_x,sample_z).r > spec.water_y+2.0:continue
			var quad := PackedInt32Array()
			for corner: Vector2i in [Vector2i(x,z),Vector2i(x+STEP,z),Vector2i(x,z+STEP),Vector2i(x+STEP,z+STEP)]:
				if not ids.has(corner):
					ids[corner] = vertices.size()
					vertices.append(Vector3(corner.x,0,corner.y)*16.0)
					var floor_y := h.get_pixel(mini(roundi(corner.x*1.024),1023),mini(roundi(corner.y*1.024),1023)).r
					colors.append(Color(1,1,1,clampf((spec.water_y-floor_y)/4.0,0,1)))
					uv.append(Vector2.ZERO)
				quad.append(ids[corner])
			indices.append_array(PackedInt32Array([quad[0],quad[1],quad[2],quad[1],quad[3],quad[2]]))
	var mesh := ArrayMesh.new()
	mesh.set_meta("bank_step_m",STEP)
	if not indices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return ResourceSaver.save(mesh,dataset+"/water.res",ResourceSaver.FLAG_COMPRESS)==OK

func make_shore_profile() -> ImageTexture:
	var table:=Image.create_empty(128,128,false,Image.FORMAT_RGF)
	var swash:=preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
	for y in 128:
		for x in 128:
			var profile:=swash.wave_profile(-24.+40.*x/127.,y/127.,1.,10.)
			table.set_pixel(x,y,Color(profile.x,profile.y,0))
	return ImageTexture.create_from_image(table)

func make_water(h: Image,height_tex: Texture2D,bank_code: String) -> void:
	var path:=dataset+"/water.res"
	var mesh: ArrayMesh=load(path) if FileAccess.file_exists(path) else null
	if mesh==null or mesh.get_meta("bank_step_m",0)!=1:
		if not bake_water(h):fail("Cannot prepare lake geometry");return
		mesh=ResourceLoader.load(path,"ArrayMesh",ResourceLoader.CACHE_MODE_REPLACE)
	var water := MeshInstance3D.new()
	water.mesh = mesh
	var material := preload("res://materials/ember_compact_sky_reflection_study.tres").duplicate() as ShaderMaterial
	water_material=material
	var wave_shader:=Shader.new()
	# The compact ocean is driven by a voxel shoreline field. On Terrain3D
	# intersect that same wave profile with the metre heightfield instead.
	wave_shader.code=material.shader.code.replace("void vertex() {",bank_code+"\nvoid vertex() {").replace("water_world_position = (MODEL_MATRIX", "VERTEX.y += 16.0*bank_runup_m*bank_wave(water_point,bank_test_seconds<0.0 ? TIME : bank_test_seconds).x;\n water_world_position = (MODEL_MATRIX").replace("EMISSION = mix(surface_color, vec3(1.0), foam);","vec2 bank = bank_wave(water_point,bank_test_seconds<0.0 ? TIME : bank_test_seconds);\n foam = max(foam,bank.y*smoothstep(0.0,0.12,bank_runup_m));\n EMISSION = mix(surface_color,vec3(1.0),foam);")
	material.shader=wave_shader
	material.set_shader_parameter("bank_floor",height_tex)
	material.set_shader_parameter("bank_profile",shore_profile)
	material.set_shader_parameter("bank_level",spec.water_y)
	for key: String in water_settings:
		if key != "water_color_start_m":material.set_shader_parameter(key,water_settings[key])
	material.set_shader_parameter("deep_start_blocks",water_settings.get("water_color_start_m",0.31))
	material.set_shader_parameter("world_units_per_metre",1.0)
	material.set_shader_parameter("water_level_world",spec.water_y)
	material.set_shader_parameter("floor_camera_available",0.0)
	material.set_shader_parameter("ripple_cell_field",preload("res://scripts/prototypes/ember_compact_ripple_field.gd").texture())
	material.set_shader_parameter("ripple_field_available",1.0)
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.scale = Vector3.ONE/16.0
	water.position.y = spec.water_y
	add_child(water)

func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Label.new()
	ui.position = Vector2(16,12)
	ui.add_theme_constant_override("outline_size",5)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	quality = VBoxContainer.new()
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(14,102)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	layer.add_child(scroll)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,8)
	scroll.add_child(margin)
	margin.add_child(quality)
	var resize_panel:=func():
		var available:=get_viewport().get_visible_rect().size
		scroll.size=Vector2(minf(450.,available.x-18.),maxf(100.,available.y-112.))
	quality.visibility_changed.connect(func():scroll.visible=quality.visible)
	quality.minimum_size_changed.connect(resize_panel)
	get_viewport().size_changed.connect(resize_panel)
	resize_panel.call()
	var panel_style:=StyleBoxFlat.new()
	panel_style.bg_color=Color(0.055,0.073,0.072,0.92)
	panel_style.set_corner_radius_all(7)
	quality.draw.connect(func():quality.draw_style_box(panel_style,Rect2(Vector2.ZERO,quality.size).grow(8)))
	quality.visible = false
	for row in [["Атлас теней",["1024","2048","4096"],2],["Фильтр теней",["Hard","PCF Very Low","PCF Medium","PCF Ultra"],1],["Каскады",["2","4"],1]]:
		var button := OptionButton.new()
		for value: String in row[1]:button.add_item(row[0]+" · "+value)
		button.select(row[2])
		button.item_selected.connect(change_shadow.bind(row[0]))
		quality.add_child(button)
	change_shadow(2,"Атлас теней")
	change_shadow(1,"Каскады")
	var shadow_rows:=quality.get_children()
	var heading:=Label.new()
	heading.text="Трава, берег и атмосфера"
	quality.add_child(heading)
	var shapes := OptionButton.new()
	shapes.name="GrassShape"
	for title in SHAPES:shapes.add_item(title)
	shapes.select(meadow.style)
	shapes.item_selected.connect(set_shape)
	quality.add_child(shapes)
	var old_look:=Button.new()
	old_look.text="Проба со старой карты · низкая и широкая"
	old_look.tooltip_text="GPU-карточки, 50%, ширина 6×, высота 0,30×. Затем можно переключить только форму."
	old_look.pressed.connect(restore_old_field)
	quality.add_child(old_look)
	var lod_toggle:=CheckButton.new()
	lod_toggle.name="TuftLod"
	lod_toggle.text="Пучки · вдали 6 и 4 треугольника"
	lod_toggle.button_pressed=meadow.tuft_lod
	lod_toggle.toggled.connect(set_tuft_lod)
	quality.add_child(lod_toggle)
	for option in [["Плотность",0.,2.,0.05,grass_level],["Ширина",0.25,6.,0.05,meadow.width],["Высота",0.25,3.,0.05,meadow.height_scale],
			["Группировка в пятна",0.,1.,0.05,meadow.clumping],["Размер пятен, м",0.5,8.,0.25,meadow.patch_metres],
			["Примесь цвета",0.,1.,0.05,meadow.tint_mix],["Блик травы",0.,1.,0.05,meadow.gloss],["Ветер",0.,3.,0.05,meadow.wind],
			["Скорость ветра",0.,3.,0.05,meadow.wind_speed],["Направление ветра, °",0.,360.,5.,meadow.wind_degrees],["Набег берега, м",0.,0.4,0.025,swash_height]]:
		var row:=HBoxContainer.new()
		quality.add_child(row)
		var caption:=Label.new()
		caption.custom_minimum_size.x=180
		row.add_child(caption)
		var slider:=HSlider.new()
		slider.min_value=option[1];slider.max_value=option[2];slider.step=option[3]
		slider.value=option[4];slider.custom_minimum_size.x=180
		caption.text=setting_text(option[0],slider.value)
		slider.value_changed.connect(adjust.bind(option[0],caption))
		if option[0]=="Плотность":slider.name="GrassAmount"
		slider.set_meta("setting",option[0])
		row.add_child(slider)
	var paint:=ColorPickerButton.new()
	paint.name="GrassColor"
	var paint_label:=Label.new()
	paint_label.text="Цвет примеси"
	quality.add_child(paint_label)
	paint.custom_minimum_size.y=20
	paint.tooltip_text="При примеси 0% цвет берётся из земли и текстуры травы."
	paint.edit_alpha=false
	paint.color=meadow.tint_color
	paint.color_changed.connect(grass_color)
	quality.add_child(paint)
	var receive:=CheckButton.new()
	receive.name="ReceiveSun"
	receive.text="Трава принимает тени солнца"
	receive.button_pressed=meadow.sun_shadows
	receive.toggled.connect(grass_shadows)
	quality.add_child(receive)
	var save_button:=Button.new()
	save_button.text="Сохранить вид для следующего запуска"
	save_button.pressed.connect(save_look.bind(save_button))
	quality.add_child(save_button)
	var shadow_title:=Label.new()
	shadow_title.text="Солнечные тени"
	quality.add_child(shadow_title)
	for row in shadow_rows:quality.move_child(row,-1)
	var fog:=CheckButton.new()
	fog.text="Атмосферная дымка вдали"
	fog.name="DistantFog"
	fog.toggled.connect(set_fog)
	quality.add_child(fog)
	quality.move_child(fog,old_look.get_index()+1)
	var ao:=OptionButton.new()
	ao.name="AO"
	for title in ["SSAO · выкл","SSAO · слабое","SSAO · исходное"]:ao.add_item(title)
	ao.item_selected.connect(set_ao)
	ao.select(0)
	set_ao(0)
	quality.add_child(ao)
	var actors:=CheckButton.new()
	actors.text="Нагрузка · 8 NPC и 4 кабана рядом"
	actors.toggled.connect(func(enabled: bool):population.populate(self,enabled))
	quality.add_child(actors)
	if not stress and not "--field-profile" in OS.get_cmdline_user_args():
		var file:=ConfigFile.new()
		if file.load("user://kilometre-look.cfg")==OK:
			var selected:=clampi(int(file.get_value("grass","shape",1)),0,3)
			shapes.select(selected)
			set_shape(selected)
			lod_toggle.button_pressed=file.get_value("grass","tuft_lod",meadow.tuft_lod)
			fog.button_pressed=file.get_value("environment","fog",false)
			var ao_mode:=clampi(int(file.get_value("environment","ao",ao.selected)),0,2)
			ao.select(ao_mode)
			set_ao(ao_mode)
			paint.color=file.get_value("grass","color",Color.WHITE)
			grass_color(paint.color)
			receive.button_pressed=file.get_value("grass","receive_sun",true)
			for slider: Slider in quality.find_children("*","Slider",true,false):
				slider.value=float(file.get_value("appearance",slider.get_meta("setting"),slider.value))

func save_look(button: Button) -> void:
	var file:=ConfigFile.new()
	file.set_value("grass","shape",meadow.style)
	file.set_value("grass","tuft_lod",meadow.tuft_lod)
	file.set_value("grass","color",meadow.tint_color)
	file.set_value("grass","receive_sun",meadow.sun_shadows)
	file.set_value("environment","fog",$Sky.environment.fog_enabled)
	file.set_value("environment","ao",quality.get_node("AO").selected)
	for slider: Slider in quality.find_children("*","Slider",true,false):
		file.set_value("appearance",slider.get_meta("setting"),slider.value)
	button.text="Вид сохранён" if file.save("user://kilometre-look.cfg")==OK else "Не удалось сохранить"

func set_shape(index: int) -> void:
	meadow.style=index
	for tile in cover.tiles:tile.get_child(0).visible=index==3
	meadow.configure()

func setting_text(setting: String,value: float) -> String:
	if setting in ["Плотность","Группировка в пятна","Примесь цвета"]:
		return "%s  %d%%" % [setting,roundi(value*100.)]
	return "%s  %.2f" % [setting,value]

func grass_color(color: Color) -> void:
	meadow.tint_color=color
	cover.materials[0].set_shader_parameter("tint_color",color)
	meadow.configure()

func grass_shadows(enabled: bool) -> void:
	meadow.sun_shadows=enabled
	cover.materials[0].set_shader_parameter("sun_shadows",enabled)
	meadow.configure()

func restore_old_field() -> void:
	var settings:={"Плотность":0.5,"Ширина":6.,"Высота":0.30,"Группировка в пятна":0.,"Размер пятен, м":0.5,
		"Ветер":1.,"Скорость ветра":1.,"Направление ветра, °":0.,"Примесь цвета":0.}
	quality.get_node("GrassShape").select(2)
	set_shape(2)
	quality.get_node("ReceiveSun").button_pressed=true
	for slider: Slider in quality.find_children("*","Slider",true,false):
		var setting: String=slider.get_meta("setting")
		if settings.has(setting):slider.value=settings[setting]

func set_tuft_lod(enabled: bool) -> void:
	meadow.tuft_lod=enabled
	meadow.configure()

func set_ao(mode: int) -> void:
	var env: Environment=$Sky.environment
	env.ssao_enabled=mode!=0
	env.ssao_intensity=0.30 if mode==1 else 0.8

func set_fog(enabled: bool) -> void:
	var env: Environment=$Sky.environment
	env.fog_mode=Environment.FOG_MODE_DEPTH
	env.fog_depth_begin=55.
	env.fog_depth_end=700.
	env.fog_density=0.20
	env.fog_sky_affect=0.0
	env.fog_light_color=Color("#cba998")
	env.fog_enabled=enabled

func adjust(value: float,setting: String,caption: Label) -> void:
	caption.text=setting_text(setting,value)
	match setting:
		"Плотность":
			grass_level=value;cover.set_density(0,value);meadow.density=value
		"Ширина":meadow.width=value
		"Высота":meadow.height_scale=value
		"Группировка в пятна":meadow.clumping=value
		"Размер пятен, м":meadow.patch_metres=value
		"Примесь цвета":meadow.tint_mix=value
		"Блик травы":meadow.gloss=value
		"Ветер":meadow.wind=value
		"Скорость ветра":meadow.wind_speed=value
		"Направление ветра, °":meadow.wind_degrees=value
		"Набег берега, м":
			swash_height=value
			water_material.set_shader_parameter("bank_runup_m",value)
			terrain.material.set_shader_param("bank_runup_m",value)
	for pair in [["width_scale",meadow.width],["height_scale",meadow.height_scale],["gloss",meadow.gloss],["wind_amount",meadow.wind],
			["patch_mix",meadow.clumping],["patch_size",meadow.patch_metres],["tint_mix",meadow.tint_mix],
			["wind_speed",meadow.wind_speed],["wind_direction",Vector2.from_angle(deg_to_rad(meadow.wind_degrees))]]:
		cover.materials[0].set_shader_parameter(pair[0],pair[1])
	meadow.configure()

func change_shadow(index: int, setting: String) -> void:
	match setting:
		"Атлас теней":atlas_size = [1024,2048,4096][index]
		"Фильтр теней":filter_quality = [0,1,3,5][index]
		"Каскады":$Sun.directional_shadow_mode = [DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][index]
	EmberLights.apply_shadow_atlas(atlas_size,2048,filter_quality,1)

func _process(_dt: float) -> void:
	if not ready_to_play:return
	var now:=Time.get_ticks_usec()
	if last_frame_us!=0:
		window_frames+=1
		window_peak_ms=maxf(window_peak_ms,(now-last_frame_us)/1000.)
	else:window_start_us=now
	last_frame_us=now
	if now-window_start_us>=1000000:
		frame_label="%.0f FPS · макс за секунду %.2f мс" % [window_frames*1000000./(now-window_start_us),window_peak_ms]
		window_frames=0
		window_peak_ms=0.
		window_start_us=now
	var p := actor.global_position
	if population.active:population.follow(p)
	cover.follow(p)
	meadow.follow(p,rig._cam)
	scenery.follow(p)
	if Time.get_ticks_msec() < last_label+250:return
	last_label = Time.get_ticks_msec()
	ui.text = "Ember · 1 км²   |   %s   |   %s   |   X %.0f  Z %.0f м\nWASD · Shift бег · ПКМ камера · 1–6 районы · 7 закат · G трава %.0f%% · F цветы %.0f%% · T тени %d/2 · F3 настройки\n%s" % [active_mark,frame_label,p.x,p.z,grass_level*100,flower_level*100,shadow_level,SHAPES[meadow.style]]
	if p.y < float(spec.height_min_m)-10 or p.x<0 or p.z<0 or p.x>=1000 or p.z>=1000:
		go_to(active_mark)

func _unhandled_key_input(event: InputEvent) -> void:
	if not ready_to_play or stress or not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode >= KEY_1 and event.keycode <= KEY_6:
		go_to(MARKS[event.keycode-KEY_1])
	match event.keycode:
		KEY_7:sunset_view()
		KEY_G:
			var slider:=quality.find_child("GrassAmount",true,false) as HSlider
			slider.value=0.5 if grass_level>0.5 else 0.0 if grass_level>0.0 else 1.0
		KEY_F:
			flower_level = 0.5 if flower_level==1 else 0.0 if flower_level==0.5 else 1.0
			cover.set_density(1,flower_level)
		KEY_T:
			shadow_level = (shadow_level+1)%3
			$Sun.shadow_enabled = shadow_level>0
			$Sun.directional_shadow_max_distance = 100.0 if shadow_level==2 else 40.0
		KEY_TAB:ui.visible=not ui.visible
		KEY_F3:quality.visible=not quality.visible

func benchmark() -> void:
	var vp := get_viewport()
	report["pixels"] = str(vp.get_texture().get_image().get_size())
	report["scale"] = vp.scaling_3d_scale
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["worker_limit"] = ProjectSettings.get_setting("threading/worker_pool/max_threads")
	report["tree_lod_files"] = FileAccess.file_exists(dataset+"/tree.res") and FileAccess.file_exists(dataset+"/birch.res")
	var out := OS.get_environment("EMBER_KM_EVIDENCE")
	if out.is_empty():fail("Missing evidence directory");return
	DirAccess.make_dir_recursive_absolute(out)
	quality.visible = true
	change_shadow(0,"Атлас теней")
	change_shadow(0,"Каскады")
	cover.set_density(0,0.5)
	report["controls_checked"] = atlas_size == 1024 and $Sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and cover.carriers[0].visible_instance_count == ceili(cover.prepared_counts[0]*0.5)
	if not report.controls_checked:report.errors.append("quality controls")
	change_shadow(2,"Атлас теней")
	change_shadow(1,"Каскады")
	cover.set_density(0,1.0)
	quality.visible = false
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
	for key: String in MARKS:
		await go_to(key)
		for i in 20:await get_tree().process_frame
		check_floor(actor.position,key)
		for lens in [40,70]:
			rig.fov = lens
			var yaw := rig.yaw
			var start := Time.get_ticks_usec()
			var prev := start
			var wall: Array[float] = []
			var gpu: Array[float] = []
			var render_cpu: Array[float] = []
			var slowest:=0.
			var observation: Dictionary={}
			var origin := actor.position
			var boost := InputEventKey.new()
			boost.physical_keycode = KEY_SHIFT
			boost.pressed = lens==70
			Input.parse_input_event(boost)
			if lens == 70:Input.action_press("move_north")
			while Time.get_ticks_usec()-start < 2200000:
				rig.yaw = yaw + 1.7*sin((Time.get_ticks_usec()-start)*0.000003)
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				wall.append((now-prev)/1000.0);prev=now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
				render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()))
				if wall[-1]>slowest:
					slowest=wall[-1]
					observation={"tick_us":now,"seconds":(now-start)/1000000.,"position":str(actor.position),
						"gpu_ms":gpu[-1],"render_cpu_ms":render_cpu[-1],"focus":get_window().has_focus(),
						"shift":Input.is_physical_key_pressed(KEY_SHIFT)}
			var shift_held := Input.is_physical_key_pressed(KEY_SHIFT)
			Input.action_release("move_north")
			boost.pressed = false
			Input.parse_input_event(boost)
			rig.yaw = yaw
			report.sites[key+str(lens)] = summary(wall,gpu)
			report.sites[key+str(lens)]["displacement_m"] = origin.distance_to(actor.position)
			report.sites[key+str(lens)]["physical_shift"] = shift_held
			report.sites[key+str(lens)]["peak_observation"] = observation
			render_cpu.sort()
			report.sites[key+str(lens)]["render_cpu_p95"] = render_cpu[ceili(render_cpu.size()*0.95)-1]
		for i in 6:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out.path_join(key+".png"))
		save_report(out)
	await traverse(vp,"village","mountain")
	await traverse(vp,"mountain","village")
	# Independent stratified physics samples cover the map edges and region seams.
	for z in [2,248,501,749,997]:
		for x in [2,248,501,749,997]:
			var point := Vector3(x,0,z)
			point.y = terrain.data.get_surface_height(point)
			await place(point)
			check_floor(point,"grid")
	await go_to("village")
	report["video_memory_mib"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0
	save_report(out)
	print("KILOMETRE_STRESS_DONE ",report.errors)
	get_tree().quit(0 if report.errors.is_empty() else 1)

func traverse(vp: Viewport, from: String, to: String) -> void:
	await go_to(from)
	var begin := actor.position
	var end := location_point(to)
	var length := Vector2(begin.x,begin.z).distance_to(Vector2(end.x,end.z))
	var start := Time.get_ticks_usec()
	var prev := start
	var wall: Array[float] = []
	var gpu: Array[float] = []
	var peak_ms:=0.
	var peak: Dictionary={}
	actor.set_physics_process(false)
	surveying=true
	while true:
		var fraction := minf(1.0,(Time.get_ticks_usec()-start)*0.000001*40.0/length)
		var point := begin.lerp(end,fraction)
		point.y = terrain.data.get_surface_height(point)+0.35
		actor.position = point
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		wall.append((now-prev)/1000.0);prev=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
		if wall[-1]>peak_ms:
			peak_ms=wall[-1]
			peak={"x":point.x,"z":point.z,"seconds":(now-start)/1000000.,"gpu_ms":gpu[-1],
				"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()),
				"collision_cell":str(scenery.last_cell),"grass_cell":str(meadow.cell)}
		if fraction >= 1.0:break
	actor.set_physics_process(true)
	surveying=false
	var label := from+"_"+to+"_40mps"
	report[label] = summary(wall,gpu)
	report[label]["metres"] = length
	report[label]["peak_observation"]=peak

func check_floor(point: Vector3,label: String) -> void:
	var expected: float = terrain.data.get_surface_height(point)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x,expected+4,point.z),Vector3(point.x,expected-4,point.z),1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var error := absf(hit.position.y-expected) if not hit.is_empty() else INF
	report.rays.append({"site":label,"x":point.x,"z":point.z,"error_m":error if is_finite(error) else -1.0})
	if error>0.18:report.errors.append("floor "+label+" "+str(point)+" "+str(error))

func summary(wall: Array[float],gpu: Array[float]) -> Dictionary:
	wall.sort();gpu.sort()
	var n := wall.size()
	var late := 0
	for ms in wall:late+=int(ms>8.3333)
	return {"frames":n,"median":wall[n/2],"p95":wall[ceili(n*0.95)-1],"p99":wall[ceili(n*0.99)-1],"max":wall[-1],"gpu_p95":gpu[ceili(n*0.95)-1],"late_percent":100.0*late/n}

func save_report(out: String) -> void:
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
