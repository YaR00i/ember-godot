extends RefCounted
## Deterministic LAB artwork and a small authored Source; no runtime generator.
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const TEXTURE_SIZE:=256
const SPAN_M:=0.9

static func artwork() -> Dictionary:
	var color:=Image.create(TEXTURE_SIZE,TEXTURE_SIZE,false,Image.FORMAT_RGBA8)
	var height:=Image.create(TEXTURE_SIZE,TEXTURE_SIZE,false,Image.FORMAT_R8)
	var rng:=RandomNumberGenerator.new();rng.seed=73109
	var centers: Array[Vector2]=[]
	for z in 5:
		for x in 5:centers.append(Vector2((x+rng.randf_range(0.2,0.8))/5.0,(z+rng.randf_range(0.2,0.8))/5.0))
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var p:=Vector2((x+0.5)/TEXTURE_SIZE,(y+0.5)/TEXTURE_SIZE)
			var first:=10.0;var second:=10.0;var winner:=0;var local:=Vector2.ZERO
			for i in centers.size():
				var d:=p-centers[i];d.x=wrapf(d.x,-0.5,0.5);d.y=wrapf(d.y,-0.5,0.5)
				var distance:=d.length()
				if distance<first:second=first;first=distance;winner=i;local=d
				elif distance<second:second=distance
			var shoulder:=smoothstep(0.002,0.032,second-first)
			var facet:=clampf(local.dot(Vector2(sin(winner*2.17),cos(winner*1.39)))*1.6,-0.22,0.22)
			# Geometry data comes directly from bevel/facet construction. Colour
			# shares the drawn regions but is never read back to infer height.
			var h:=clampf(0.16+shoulder*(0.60+facet),0.08,0.92)
			var tone:=Color("aaa18f").lerp(Color("878777"),float(winner%7)/6.0)
			var pigment:=Color("756c5c").lerp(tone,smoothstep(0.001,0.019,second-first))
			color.set_pixel(x,y,pigment);height.set_pixel(x,y,Color(h,h,h,1))
	return {"color":color,"height":height}

static func source() -> EmberTerrainPilotResource:
	var result:=Terrain.new();result.width=80;result.depth=64;result.height_limit=64
	result.palette=PackedColorArray([Color.TRANSPARENT,Color("979184"),Color("d7c08c"),Color("25aacf")])
	result.palette_surface_roles=PackedStringArray(["","stone","sand",""])
	result.palette_material_ids=PackedStringArray(["","cartoon_stone","cartoon_sand",""])
	for channel: String in Terrain.Sections.CHANNELS:
		var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(result.width*result.depth);result.set(channel,data)
	for z in result.depth:
		for x in result.width:
			var p:=Vector2((x+0.5)/16.0,(z+0.5)/16.0)
			var edge:=2.7+0.18*sin(p.y*2.0)
			var stone:=p.x<edge
			var h:=0.85+0.65*(1.0-smoothstep(1.4,3.7,p.x))+0.035*sin(p.y*1.7)
			var i:=result.column_index(x,z)
			result.heights[i]=roundi(h*16.0)
			result.top_materials[i]=1 if stone else 2
			result.base_materials[i]=result.top_materials[i];result.cap_depths[i]=2
			if p.x>3.6 and p.y>3.2:
				result.water_levels[i]=18;result.water_materials[i]=3
	return result

static func coverage(source_resource) -> Image:
	var image:=Image.create(source_resource.width+1,source_resource.depth+1,false,Image.FORMAT_RF)
	var cache: Dictionary={}
	for z in source_resource.depth+1:
		for x in source_resource.width+1:
			var weights:=Smooth.material_weights(source_resource,Vector2i(x,z),cache)
			var stone: float=weights.get(1,0.0)
			var sand: float=weights.get(2,0.0)
			image.set_pixel(x,z,Color(stone/maxf(stone+sand,0.00001),0,0,1))
	return image
