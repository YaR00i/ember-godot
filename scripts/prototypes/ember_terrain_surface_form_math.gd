extends RefCounted
const GenerationMath=preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
## Pure surface-shape math. Callers provide artwork and base terrain samples;
## no scene, file access, serialization or second terrain owner.
var stone_image: Image
var stone_span:=3.2
var _noise: FastNoiseLite
var _broad: FastNoiseLite
var _seed:=7
var _soil_sites: Dictionary={}

func configure(seed_value: int,artwork: Image=null,span:=3.2) -> void:
	_seed=seed_value;stone_image=artwork;stone_span=span
	_soil_sites.clear()
	_noise=FastNoiseLite.new();_noise.seed=seed_value+731;_noise.frequency=0.9
	_broad=FastNoiseLite.new();_broad.seed=seed_value+291;_broad.frequency=0.55

func rock_wedge(p: Vector2,center: Vector2,height: float,radius: float) -> float:
	var d: Vector2=(p-center)/radius
	# Different planar cuts; shared smoothing rounds only their edges.
	var cut:=maxf(absf(d.x+0.22*d.y),maxf(absf(d.y-0.31*d.x),absf(0.64*d.x+0.73*d.y)))
	var top:=0.78-0.10*d.x+0.06*d.y
	return height*maxf(0.0,minf(top,1.12-cut))

func image_colour(uv: Vector2) -> Color:
	var q:=Vector2(fposmod(uv.x,1.0),fposmod(uv.y,1.0))*Vector2(stone_image.get_width(),stone_image.get_height())-Vector2(0.5,0.5)
	var x:=floori(q.x);var y:=floori(q.y);var t:=q-Vector2(x,y)
	var a:=stone_image.get_pixel(posmod(x,stone_image.get_width()),posmod(y,stone_image.get_height()))
	var b:=stone_image.get_pixel(posmod(x+1,stone_image.get_width()),posmod(y,stone_image.get_height()))
	var c:=stone_image.get_pixel(posmod(x,stone_image.get_width()),posmod(y+1,stone_image.get_height()))
	var d:=stone_image.get_pixel(posmod(x+1,stone_image.get_width()),posmod(y+1,stone_image.get_height()))
	return a.lerp(b,t.x).lerp(c.lerp(d,t.x),t.y)

func texture_height(p: Vector2) -> float:
	var uv:=p/stone_span
	var edge:=Vector2(minf(fposmod(uv.x,1.0),1.0-fposmod(uv.x,1.0)),minf(fposmod(uv.y,1.0),1.0-fposmod(uv.y,1.0)))
	var blend:=Vector2(1.0-smoothstep(0.0,0.018,edge.x),1.0-smoothstep(0.0,0.018,edge.y))
	# Same repeat/seam blending as native png_tile; brightness is only a study height heuristic.
	var a:=image_colour(uv).lerp(image_colour(uv+Vector2(0.5,0)),blend.x)
	var b:=image_colour(uv+Vector2(0,0.5)).lerp(image_colour(uv+Vector2(0.5,0.5)),blend.x)
	var rgb:=a.lerp(b,blend.y)
	var luminance:=rgb.r*0.2126+rgb.g*0.7152+rgb.b*0.0722
	return 0.60*(smoothstep(0.24,0.66,luminance)-0.5)


func role_at(p: Vector2,height_m: float,slope: float,sea_m: float,wet:=false) -> String:
	if wet:return "sand"
	var coast_noise:=_broad.get_noise_2dv(p)*0.2
	if height_m<sea_m+0.65+coast_noise:return "sand"
	var stone_score:=slope*3.8+_broad.get_noise_2dv(p+Vector2(13,5))*0.35
	if height_m>sea_m+0.9 and stone_score>0.45:return "stone"
	if _broad.get_noise_2dv(p+Vector2(7,19))>0.18 or (slope>0.07 and stone_score>0.30):return "soil"
	return "grass"

class CoverageField extends RefCounted:
	# Half-metre means separate broad slope from fine relief. A bounded
	# chamfer distance uses authored wet cells, not a fixed sea-height stripe.
	const STEP:=8
	var finished:=false
	var _source
	var _start: Vector2i
	var _size: Vector2i
	var _heights:=PackedFloat32Array()
	var _distances:=PackedFloat32Array()
	var _phase:=0
	var _cursor:=0
	func _init(source,bounds: Rect2i,sand_width: float) -> void:
		_source=source
		var expanded:=bounds.grow(ceili((maxf(2.0,sand_width)+1.0)*16)).intersection(Rect2i(0,0,source.width,source.depth))
		_start=Vector2i(expanded.position.x/STEP,expanded.position.y/STEP)
		_size=Vector2i(ceili(float(expanded.end.x)/STEP),ceili(float(expanded.end.y)/STEP))-_start
		_heights.resize(_size.x*_size.y);_distances.resize(_heights.size());_distances.fill(INF)
	func step(budget_us:=4000) -> void:
		var started:=Time.get_ticks_usec()
		while not finished and Time.get_ticks_usec()-started<budget_us:
			var i:=_cursor if _phase<2 else _heights.size()-1-_cursor
			var cell:=Vector2i(i%_size.x,i/_size.x)
			if _phase==0:
				var sum:=0.0;var count:=0;var wet:=false
				var begin:=(_start+cell)*STEP
				for z in range(begin.y,mini(begin.y+STEP,_source.depth)):
					for x in range(begin.x,mini(begin.x+STEP,_source.width)):
						if not _source.has_column(x,z):continue
						var index: int=_source.column_index(x,z)
						var h: int=_source.column_value("heights",index)
						if h>0:sum+=h;count+=1
						if _source.column_value("water_levels",index)>h and _source.column_value("water_materials",index)>0:wet=true
				_heights[i]=(sum/maxi(1,count)+_source.origin_y)/16.0
				if wet:_distances[i]=0.0
			else:
				var offsets: Array=[Vector2i.LEFT,Vector2i.UP,Vector2i(-1,-1),Vector2i(1,-1)] if _phase==1 else [Vector2i.RIGHT,Vector2i.DOWN,Vector2i(1,1),Vector2i(-1,1)]
				for offset: Vector2i in offsets:
					var next:=cell+offset
					if Rect2i(Vector2i.ZERO,_size).has_point(next):_distances[i]=minf(_distances[i],_distances[next.x+next.y*_size.x]+(0.70710678 if offset.x!=0 and offset.y!=0 else 0.5))
			_cursor+=1
			if _cursor<_heights.size():continue
			_cursor=0;_phase+=1
			if _phase==3:finished=true;_source=null
	func _sample(values: PackedFloat32Array,p: Vector2) -> float:
		var q:=p*2.0-Vector2(_start)-Vector2.ONE*0.5
		var cell:=Vector2i(floori(q.x),floori(q.y));var t:=q-Vector2(cell)
		var a: float=values[clampi(cell.x,0,_size.x-1)+clampi(cell.y,0,_size.y-1)*_size.x]
		var b: float=values[clampi(cell.x+1,0,_size.x-1)+clampi(cell.y,0,_size.y-1)*_size.x]
		var c: float=values[clampi(cell.x,0,_size.x-1)+clampi(cell.y+1,0,_size.y-1)*_size.x]
		var d: float=values[clampi(cell.x+1,0,_size.x-1)+clampi(cell.y+1,0,_size.y-1)*_size.x]
		# A dry field with no water has INF throughout; avoid INF-INF interpolation.
		if not is_finite(a) or not is_finite(b) or not is_finite(c) or not is_finite(d):return INF
		return lerpf(lerpf(a,b,t.x),lerpf(c,d,t.x),t.y)
	func water_distance(p: Vector2) -> float:return _sample(_distances,p)
	func progress() -> float:return 1.0 if finished else (float(_phase)+float(_cursor)/maxi(1,_heights.size()))/3.0
	func slope_percent(p: Vector2) -> float:
		var dx:=(_sample(_heights,p+Vector2(2,0))-_sample(_heights,p-Vector2(2,0)))/4.0
		var dz:=(_sample(_heights,p+Vector2(0,2))-_sample(_heights,p-Vector2(0,2)))/4.0
		return Vector2(dx,dz).length()*100.0

func zone_role_at(p: Vector2,field: CoverageField,values: Dictionary) -> String:
	var size: float=values.get("coverage_zone_m",GenerationMath.ZONE_DEFAULTS.coverage_zone_m)
	var width: float=values.get("coverage_sand_width_m",GenerationMath.ZONE_DEFAULTS.coverage_sand_width_m)
	var wobble:=_broad.get_noise_2dv(p/size)*0.15
	if width>0.0 and field.water_distance(p)<width*(1.0+wobble):return "sand"
	var stone_slope: float=values.get("coverage_stone_slope",GenerationMath.ZONE_DEFAULTS.coverage_stone_slope)
	if field.slope_percent(p)>stone_slope*(1.0+wobble):return "stone"
	var amount: float=values.get("coverage_soil_amount",GenerationMath.ZONE_DEFAULTS.coverage_soil_amount)
	if amount<=0.0:return "grass"
	var warped:=p+Vector2(_broad.get_noise_2dv(p/size),_broad.get_noise_2dv(p/size+Vector2(19,7)))*size*0.22
	var cell:=Vector2i(floori(warped.x/size),floori(warped.y/size))
	for z in range(cell.y-1,cell.y+2):
		for x in range(cell.x-1,cell.x+2):
			var key:=Vector2i(x,z)
			if not _soil_sites.has(key):
				var jitter:=Vector2(GenerationMath._site_random(key,_seed+611),GenerationMath._site_random(key,_seed+617))-Vector2.ONE*0.5
				_soil_sites[key]={"point":(Vector2(key)+Vector2.ONE*0.5+jitter*0.7)*size,"choice":GenerationMath._site_random(key,_seed+631),"radius":size*(0.36+GenerationMath._site_random(key,_seed+641)*0.12)}
			var site: Dictionary=_soil_sites[key]
			if site.choice<amount and warped.distance_to(site.point)<site.radius:return "soil"
	return "grass"

func offset_m(p: Vector2,role: String,detail_scale:=1.0) -> float:
	var artwork_point:=p
	p/=detail_scale # Shape size changes independently of height amplitude.
	if role=="grass":return _noise.get_noise_2dv(p*0.55)*0.035
	if role=="soil":return _noise.get_noise_2dv(p)*0.10+sin(p.x*2.2+p.y*1.8)*0.04
	if role=="sand":
		var phase:=p.x*6.0+p.y*0.7+sin(p.y*0.85)*1.5+_noise.get_noise_2dv(p*0.6)*2.4
		var lengths:=smoothstep(-0.26,0.25,_broad.get_noise_2dv(p+Vector2(3,19)))
		return sin(phase)*0.16*(0.12+0.88*lengths)+_broad.get_noise_2dv(p*0.65+Vector2(7,2))*0.11
	if role!="stone":return 0.0
	var chips:=0.0
	var cell:=Vector2i((p/2.3).floor())
	for z in range(-1,2):
		for x in range(-1,2):
			var at:=cell+Vector2i(x,z)
			var random:=_random(at,1)
			if random<0.45:continue
			var center: Vector2=(Vector2(at)+Vector2(_random(at,2),_random(at,3)))*2.3
			chips=maxf(chips,rock_wedge(p,center,0.3+0.4*random,0.8+0.35*_random(at,4)))
	# Baked artwork stays aligned with the selected material's PNG repeat size.
	return chips+(texture_height(artwork_point) if stone_image!=null else 0.0)

func brush_offset_voxels(point: Vector2,role: String,scale: float,amplitude: int,influence: float,height_step: int,direction: int) -> int:
	# Existing material identity chooses the shape; no coverage reclassification.
	var value:=clampf(offset_m(point,role,scale)/0.7,-1.0,1.0) if role in ["grass","soil","sand","stone"] else 0.0
	if direction>0:value=absf(value)
	elif direction<0:value=-absf(value)
	return roundi(value*float(amplitude)*influence/float(height_step))*height_step

func _random(cell: Vector2i,channel: int) -> float:
	return float(hash(Vector3i(cell.x,cell.y,_seed+channel*1777))&0x7fffffff)/2147483648.0
