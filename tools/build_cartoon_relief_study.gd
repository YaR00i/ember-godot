extends SceneTree
## Reproducible authored fixture, not a new terrain generator or surface owner.
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
const Map=preload("res://scripts/ember_map_loader.gd")
const SurfaceForms=preload("res://scripts/prototypes/ember_terrain_surface_form_math.gd")
var surface_forms:=SurfaceForms.new()
var stone_image: Image
const STONE_SPAN:=3.2

func _initialize() -> void:call_deferred("run")

func rock_wedge(p: Vector2,center: Vector2,height: float,radius: float) -> float:
	return surface_forms.rock_wedge(p,center,height,radius)
func texture_height(p: Vector2) -> float:
	return surface_forms.texture_height(p)

func pocket(p: Vector2,center: Vector2,radii: Vector2) -> float:
	var d: Vector2=(p-center)/radii
	return exp(-d.length_squared()*1.6)

func fixture(detail: bool) -> EmberTerrainPilotResource:
	var source:=Terrain.new();source.width=192;source.depth=128;source.height_limit=128
	source.palette=PackedColorArray([Color.TRANSPARENT,Color("a78a69"),Color("d7c08c"),Color("83867a")])
	source.palette_surface_roles=PackedStringArray(["","soil","sand","stone"])
	source.palette_material_ids=PackedStringArray(["","cartoon_soil","cartoon_sand","cartoon_relief_stone"])
	var count:=source.width*source.depth
	source.heights.resize(count);source.top_materials.resize(count);source.base_materials.resize(count);source.cap_depths.resize(count)
	source.water_levels.resize(count);source.water_materials.resize(count)
	source.base_materials.fill(1);source.cap_depths.fill(2)
	var noise:=FastNoiseLite.new();noise.seed=731;noise.frequency=0.9
	var broad:=FastNoiseLite.new();broad.seed=291; broad.frequency=0.55
	for z in source.depth:
		for x in source.width:
			var p:=Vector2((x+0.5)/16.0,(z+0.5)/16.0)
			var n:=broad.get_noise_2dv(p)
			var stone_edge:=4.15+0.9*sin(p.y*0.84)+1.3*n
			var soil_edge:=8.05+1.05*sin(p.y*0.75+1.0)+1.6*n
			var stone_score: float=(stone_edge-p.x)/1.2+0.22*noise.get_noise_2dv(p*0.65)
			stone_score-=2.6*pocket(p,Vector2(2.8,4.5),Vector2(1.6,1.35))
			stone_score-=1.9*pocket(p,Vector2(3.55,1.3),Vector2(1.25,1.0))
			stone_score+=2.3*pocket(p,Vector2(5.7,5.9),Vector2(1.0,1.25))
			var soil_score: float=(p.x-soil_edge)/1.2+0.24*noise.get_noise_2dv(p*0.7+Vector2(8,13))
			soil_score+=2.0*pocket(p,Vector2(6.3,2.05),Vector2(1.4,1.0))
			soil_score-=2.0*pocket(p,Vector2(9.4,5.85),Vector2(1.4,1.0))
			var stone:=smoothstep(-0.5,0.6,stone_score)
			var soil: float=smoothstep(-0.55,0.55,soil_score)*(1.0-stone)
			var sand: float=maxf(0.0,1.0-stone-soil)
			var h:=1.0+1.05*(1.0-smoothstep(0.6,5.5,p.x))+0.15*sin(p.y*0.45)+0.10*cos(p.x*0.6+p.y*0.3)
			if detail:
				var chips:=rock_wedge(p,Vector2(1.15,1.65),0.85,1.15)
				chips=maxf(chips,rock_wedge(p,Vector2(2.9,3.1),0.72,1.05))
				chips=maxf(chips,rock_wedge(p,Vector2(1.25,5.55),1.0,1.3))
				chips=maxf(chips,rock_wedge(p,Vector2(3.2,6.75),0.70,1.15))
				chips=maxf(chips,rock_wedge(p,Vector2(5.7,5.9),0.43,0.95))
				var fracture:=0.16*exp(-pow((p.x-(2.0+0.12*p.y))/0.18,2.0))
				var phase:=p.x*6.0+p.y*0.7+1.5*sin(p.y*0.85)+2.4*noise.get_noise_2dv(p*0.6)
				var lengths:=smoothstep(-0.26,0.25,broad.get_noise_2dv(p+Vector2(3,19)))
				var crests:=0.16*sin(phase)*(0.12+0.88*lengths)+0.11*broad.get_noise_2dv(p*0.65+Vector2(7,2))
				var earth:=0.11*noise.get_noise_2dv(p)+0.06*sin(p.x*2.2+p.y*1.8)
				h+=stone*(chips-fracture+texture_height(p))+sand*crests+soil*earth
			var index:=source.column_index(x,z)
			source.heights[index]=roundi(h*16.0)
			source.top_materials[index]=3 if stone_score>0.12 else (1 if soil_score>0.0 else 2)
	return source

func run() -> void:
	stone_image=Image.load_from_file("res://content/terrain_materials/textures/cartoon_rock.png")
	if stone_image==null or stone_image.is_empty():printerr("Rock artwork missing");quit(1);return
	surface_forms.configure(731,stone_image,STONE_SPAN)
	var rock=load("res://content/terrain_materials/cartoon_stone.tres").duplicate(true)
	rock.pattern_size_m=STONE_SPAN
	rock.pixel_relief=0.14
	if ResourceSaver.save(rock,"res://content/terrain_materials/cartoon_relief_stone.tres")!=OK:quit(1);return
	var sand:=Pattern.new();sand.role_id="sand";sand.pixels.resize(256)
	sand.base_color=Color("d7c08c");sand.light_color=Color("e3d09f");sand.shadow_color=Color("c3aa78")
	sand.pattern_size_m=1.5
	if ResourceSaver.save(sand,"res://content/terrain_materials/cartoon_sand.tres")!=OK:quit(1);return
	for detail in [false,true]:
		var source:=fixture(detail)
		if not source.validation_errors().is_empty():printerr(source.validation_errors());quit(1);return
		var path: String="res://content/world_terrains/cartoon_relief_"+("detail" if detail else "base")+".res"
		if ResourceSaver.save(source,path)!=OK:quit(1);return
	var base=load("res://content/world_terrains/cartoon_relief_base.res")
	var detail=load("res://content/world_terrains/cartoon_relief_detail.res")
	var original:=load("res://scenes/compact_cartoon_ground_study.tscn") as PackedScene
	var scene:=original.instantiate();scene.name="CartoonReliefStudy"
	scene.orbit_center=Vector3(6,1.2,4);scene.baseline_terrain=base
	var map:=scene.get_node("Map") as EmberMapLoader
	map.map_id="cartoon_relief_study";map.compact_terrain=detail;map.authored_size_blocks=Vector2i(12,8)
	map.compact_smooth_material_blend=true
	var camera:=scene.get_node("Camera3D") as Camera3D
	camera.fov=37;camera.look_at_from_position(Vector3(16,10,17),Vector3(6,1.2,4))
	scene.get_node("Instructions/Caption").text="Объёмная фактура · B — сравнить · ПКМ — камера · колесо — масштаб · L — свет"
	var packed:=PackedScene.new()
	if packed.pack(scene)!=OK or ResourceSaver.save(packed,"res://scenes/compact_cartoon_relief_study.tscn")!=OK:quit(1);return
	scene.free();print("CARTOON_RELIEF_FIXTURE PASS");quit()
