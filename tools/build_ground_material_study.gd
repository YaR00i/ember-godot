extends SceneTree
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var painted := "--painted" in OS.get_cmdline_user_args()
	var finish := "--finish" in OS.get_cmdline_user_args()
	var study_id := "ground_finish_study" if finish else "ground_grass_painted_study" if painted else "ground_material_study"
	var scene:=Node3D.new(); scene.name="GroundFinishStudy" if finish else "GroundGrassPaintedStudy" if painted else "GroundMaterialStudy"
	scene.set_script(load("res://scripts/prototypes/ember_ground_material_study.gd"))
	var map:=EmberMapLoader.new(); map.name="Map"; map.hydrate_legacy_regions=false
	map.compact_material_light_mode=1; map.imported_tile_size=1.0; map.map_id=study_id; map.authored_size_blocks=Vector2i(8,8)
	var terrain:=Terrain.new(); terrain.width=128; terrain.depth=128; terrain.height_limit=48
	terrain.palette=PackedColorArray([Color.TRANSPARENT]); terrain.palette_surface_roles=PackedStringArray([""]); terrain.palette_material_ids=PackedStringArray([""])
	for id in (["grass_painted","grass_impasto","soil_surface","soil_grain"] if finish else ["grass_surface","grass_painted","soil_relief","soil_surface"] if painted else ["grass_relief","grass_surface","soil_relief","soil_surface"]):
		var pattern=Materials.load_compact_terrain_variant(id)
		terrain.palette.append(pattern.base_color); terrain.palette_surface_roles.append(pattern.role_id); terrain.palette_material_ids.append(id)
	for field in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:
		var channel: Variant=PackedInt32Array() if field in ["heights","water_levels"] else PackedByteArray()
		channel.resize(128*128); terrain.set(field,channel)
	for z in 128:
		for x in 128:
			var i=x+z*128; var id=1+(1 if x>=64 else 0)+(2 if z>=64 else 0)
			terrain.heights[i]=16+(4 if x%64>=40 and z%64>=40 else 0)
			terrain.top_materials[i]=id; terrain.base_materials[i]=id; terrain.cap_depths[i]=1
	assert(terrain.validation_errors().is_empty())
	assert(ResourceSaver.save(terrain,"res://content/world_terrains/"+study_id+".res",ResourceSaver.FLAG_COMPRESS)==OK)
	map.compact_terrain=load("res://content/world_terrains/"+study_id+".res"); scene.add_child(map); map.owner=scene
	var look:=Node3D.new(); look.name="Look"; map.add_child(look); look.owner=scene
	var world:=WorldEnvironment.new(); world.name="WorldEnvironment"; world.environment=Environment.new()
	var env=world.environment; env.background_mode=Environment.BG_COLOR; env.background_color=Color("283d49")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color("d3dce2"); env.ambient_light_energy=0.32
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY; env.sky=Sky.new(); env.sky.sky_material=ProceduralSkyMaterial.new()
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC; env.ssao_enabled=true
	look.add_child(world); world.owner=scene
	var sun:=DirectionalLight3D.new(); sun.name="Sun"; sun.rotation_degrees=Vector3(-38,-25,0); sun.light_energy=1.3; sun.light_color=Color.WHITE; sun.shadow_enabled=true
	look.add_child(sun); sun.owner=scene
	var camera:=Camera3D.new(); camera.name="Camera3D"; scene.add_child(camera); camera.owner=scene
	camera.position=Vector3(10,9,13); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=12
	root.add_child(scene); camera.look_at(Vector3(4,0.5,4)); camera.current=true
	for i in 4:
		var label:=Label3D.new(); label.name="Caption"+str(i); label.text=(["Трава · цветные мазки","Трава · рельефные мазки","Грунт · нынешний","Грунт · зерно"] if finish else ["Трава · нынешняя","Трава · мазки","Грунт · прежний","Грунт · фактура"] if painted else ["Трава · прежняя","Трава · фактура","Грунт · прежний","Грунт · фактура"])[i]
		label.position=Vector3(2+(i%2)*4,1.45,2+(i/2)*4); label.font_size=36; label.pixel_size=0.005; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		scene.add_child(label); label.owner=scene
	var layer:=CanvasLayer.new(); layer.name="Instructions"; scene.add_child(layer); layer.owner=scene
	var hint:=Label.new(); hint.name="Caption"; hint.text="Трава и грунт · один свет, прежняя палитра\nF — фактура · G — серый цвет · L — повернуть свет · ПКМ — камера"; hint.position=Vector2(22,20)
	layer.add_child(hint); hint.owner=scene
	await process_frame
	var packed:=PackedScene.new(); assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/"+study_id+".tscn")==OK)
	scene.free(); print("GROUND_STUDY PASS 8x8m four swatches, one Map, no water"); quit()
