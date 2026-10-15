extends RefCounted
## Pure, bounded oak18 scaffold. Both voxel emission and the near-view LAB
## consume these same tapered supports. No renderer, Resource or UI owner.

static func sample(path: Array, t: float) -> Vector3:
	var at := clampf(t, 0, 1) * (path.size() - 1)
	var index := mini(floori(at), path.size() - 2)
	return (path[index] as Vector3).lerp(path[index + 1], at - index)

static func radius(branch: Dictionary, t: float) -> float:
	return lerpf(float(branch.radius), float(branch.tip_radius), pow(clampf(t, 0, 1), float(branch.get("radius_power", 0.85))))

static func _append(branches: Array, parent: int, attachment: float, order: int,
	start: Vector3, end: Vector3, bend: Vector3, r0: float, r1: float, segments: int) -> void:
	var path: Array[Vector3] = []
	for i in segments + 1:
		var t := float(i) / segments
		path.append(start.lerp(end, t) + bend * sin(PI * t))
	branches.append({"id": branches.size(), "parent": parent, "attachment": attachment,
		"order": order, "path": path, "radius": r0, "tip_radius": r1})

static func plan(settings: Dictionary, seed: int) -> Array:
	if int(settings.generation_version) == 25: return _spruce_plan(settings, seed)
	if int(settings.generation_version) == 24: return _savanna_plan(settings, seed)
	if int(settings.generation_version) == 23: return _maple_plan(settings, seed)
	if int(settings.generation_version) == 22: return _birch_plan(settings, seed)
	if int(settings.generation_version) == 21: return _recursive_plan(settings, seed)
	if int(settings.generation_version) == 20: return _branchy_plan(settings, seed)
	if int(settings.generation_version) == 19: return _crown_plan(settings, seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(seed, 0) + 982451659
	var branches: Array = []
	var height := float(settings.height)
	var r := float(settings.trunk_width) * 0.49
	var heading := rng.randf() * TAU
	var curve := float(settings.branch_curve) / 100.0
	var drift := Vector3(cos(heading), 0, sin(heading))
	_append(branches, -1, 0, 0, Vector3.ZERO,
		Vector3.UP * height * 0.86 + drift * height * 0.10,
		drift * height * curve * 0.075, r * 1.35, r * 0.025, 8)
	# Staggered insertions preserve a continuous leader, instead of one thick fork.
	for i in 4:
		var attachment := 0.40 + i * 0.08 + rng.randf_range(-0.015, 0.015)
		var angle := heading + i * 2.399963 + rng.randf_range(-0.20, 0.20)
		var outward := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-sin(angle), 0, cos(angle))
		var length := height * float(settings.crown_spread) / 220.0 * lerpf(1.03, 0.70, i / 3.0)
		var start := sample(branches[0].path, attachment)
		var end := start + outward * length
		end.y = height * (0.70 + i * 0.032 + rng.randf_range(-0.025, 0.025))
		var base_radius := radius(branches[0], attachment) * float(settings.branch_thickness) / 100.0 * 0.72
		var primary := branches.size()
		_append(branches, 0, attachment, 1, start, end,
			side * length * curve * rng.randf_range(-0.18, 0.18) - Vector3.UP * length * 0.09,
			base_radius, base_radius * 0.04, 5)
		for j in 3:
			var at := 0.42 + j * 0.21
			var turn: float = angle + [-0.85, 0.65, -0.25][j] + rng.randf_range(-0.20, 0.20)
			var direction := Vector3(cos(turn), 0, sin(turn))
			var anchor := sample(branches[primary].path, at)
			var extent := length * rng.randf_range(0.42, 0.62)
			var tip := anchor + direction * extent + Vector3.UP * height * rng.randf_range(0.14, 0.19)
			tip.y = minf(tip.y, height * 0.88)
			var secondary := branches.size()
			var secondary_radius := radius(branches[primary], at) * 0.60
			_append(branches, primary, at, 2, anchor, tip, side * extent * 0.12,
					secondary_radius, secondary_radius * 0.065, 3)
			for k in 2:
				var twig_at := 0.54 + k * 0.30
				var twig_start := sample(branches[secondary].path, twig_at)
				var twig_direction := direction.rotated(Vector3.UP, [-0.65, 0.70][k])
				var twig_length := extent * rng.randf_range(0.50, 0.75)
				var twig_tip := twig_start + twig_direction * twig_length + Vector3.UP * twig_length * rng.randf_range(0.30, 0.65)
				twig_tip.y = minf(twig_tip.y, height * 0.89)
				var twig_radius := radius(branches[secondary], twig_at) * 0.53
				_append(branches, secondary, twig_at, 3, twig_start, twig_tip,
					side * twig_length * 0.09, twig_radius, minf(0.045, twig_radius * 0.12), 2)
	# Fine upper leaders close the central crown without a straight leafy spike.
	for i in 2:
		var at := 0.78 + i * 0.10
		var angle := heading + 1.1 + i * 2.7
		var direction := Vector3(cos(angle), 0, sin(angle))
		var start := sample(branches[0].path, at)
		var base_radius := radius(branches[0], at) * 0.52
		_append(branches, 0, at, 1, start,
			start + direction * height * 0.13 + Vector3.UP * height * 0.055,
			direction * height * 0.012, base_radius, base_radius * 0.05, 2)
	# Short tapered roots stay on the ground; they are geometry, not a new collider.
	for i in 5:
		var angle := heading + i * TAU / 5.0
		_append(branches, 0, 0.035, -1, sample(branches[0].path, 0.035),
			Vector3(cos(angle), 0, sin(angle)) * r * 1.65,
			Vector3.UP * r * 0.06, r * 0.62, 0.045, 1)
	return branches

static func _spruce_plan(settings: Dictionary, seed: int) -> Array:
	if int(settings.crown_shape)==1:return _spruce_bough_plan(settings,seed)
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(seed,0)+982451727
	var result: Array=[];var h:=float(settings.height)
	var heading:=rng.randf()*TAU
	var curve:=float(settings.branch_curve)/100.0
	var variation:=float(settings.branch_count_variation)/100.0
	var width:=float(settings.trunk_width)*0.48
	var drift:=Vector3(cos(heading),0,sin(heading))*h*curve*0.025
	_append(result,-1,0,0,Vector3.ZERO,Vector3.UP*h*0.97+drift,drift*0.45,width*1.20,width*0.018,8)
	result[0].radius_power=1.25
	# One continuous leader, staggered limbs and overlapping branch-owned pads.
	# Count is the number of whorls, not a stack of detached foliage discs.
	var tiers:=int(settings.main_branch_count)
	for tier in tiers:
		var progress:=float(tier)/maxi(tiers-1,1)
		for arm in 3:
			var at:=lerpf(float(settings.branch_start)/100.0,0.92,progress)+rng.randf_range(-0.018,0.018)*variation
			var angle:=heading+tier*2.399963+arm*TAU/3.0+rng.randf_range(-0.20,0.20)*variation
			var radial:=Vector3(cos(angle),0,sin(angle));var side:=Vector3(-radial.z,0,radial.x)
			var reach:=h*0.30*pow(1.0-progress*0.85,1.05)*float(settings.crown_spread)/55.0
			reach*=1.0+rng.randf_range(-0.18,0.18)*variation
			var start:=sample(result[0].path,at)
			var end:=start+radial*reach+Vector3.DOWN*reach*0.15*curve
			var r:=radius(result[0],at)*float(settings.branch_thickness)/100.0*0.70
			var primary:=result.size()
			_append(result,0,at,1,start,end,Vector3.DOWN*reach*0.13*curve+side*reach*rng.randf_range(-0.08,0.08),r,r*0.035,4)
			result[-1]["crown_supports"]=[]
			for t in [0.36,0.84]:
				var span:=reach*(0.50 if t<0.5 else 0.32)
				span=maxf(span,h*0.035)
				result[primary].crown_supports.append({"center":sample(result[primary].path,t)+Vector3.UP*reach*0.09,"radii":Vector3(1.0,0.55,1.0)*span})
			_spruce_twigs(result,primary,radial,reach,settings,rng,2)
	result[0]["crown_supports"]=[]
	for tier in tiers+1:
		var progress:=float(tier)/tiers
		var at:=lerpf(float(settings.branch_start)/100.0,0.98,progress)
		var radial:=maxf(h*0.016,h*0.24*pow(1.0-progress*0.98,0.85)*float(settings.crown_spread)/55.0)
		var vertical:=minf(h*(0.98-float(settings.branch_start)/100.0)/tiers,h*(0.995-at*0.97))
		result[0].crown_supports.append({"center":sample(result[0].path,at),"radii":Vector3(radial,vertical,radial)})
	for i in 4:
		var radial:=Vector3(cos(heading+i*TAU/4.0),0,sin(heading+i*TAU/4.0))
		_append(result,0,0.025,-1,sample(result[0].path,0.025),radial*width*(1.0+float(settings.root_flare)/100.0),Vector3.ZERO,width*0.55,0.025,1)
	return result

static func _spruce_bough_plan(settings: Dictionary,seed: int) -> Array:
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(seed,0)+982451749
	var result: Array=[];var h:=float(settings.height);var heading:=rng.randf()*TAU
	var curve:=float(settings.branch_curve)/100.0;var variation:=float(settings.branch_count_variation)/100.0
	var width:=float(settings.trunk_width)*0.48
	var drift:=Vector3(cos(heading),0,sin(heading))*h*curve*0.025
	_append(result,-1,0,0,Vector3.ZERO,Vector3.UP*h*0.97+drift,drift*0.4,width*1.2,width*0.018,8)
	result[0].radius_power=1.25
	var tiers:=int(settings.main_branch_count)
	for tier in tiers:
		var progress:=float(tier)/maxi(1,tiers-1)
		for arm in 3:
			var at:=lerpf(float(settings.branch_start)/100.0,0.93,progress)+rng.randf_range(-0.026,0.026)*variation
			var angle:=heading+tier*2.399963+arm*TAU/3.0+rng.randf_range(-0.20,0.20)*variation
			var radial:=Vector3(cos(angle),0,sin(angle));var side:=Vector3(-radial.z,0,radial.x)
			var reach:=h*0.30*pow(1.0-progress*0.86,0.72)*float(settings.crown_spread)/55.0
			reach*=1.0+rng.randf_range(-0.14,0.14)*variation
			var start:=sample(result[0].path,at)
			var r:=radius(result[0],at)*float(settings.branch_thickness)/100.0*0.72
			var primary:=result.size()
			_append(result,0,at,1,start,start+radial*reach-Vector3.UP*reach*0.20,
				Vector3.DOWN*reach*0.18*curve+side*reach*rng.randf_range(-0.05,0.05),r,r*0.035,3)
			result[primary]["crown_supports"]=[]
			for t in [0.40,0.82]:
				var span:=maxf(h*0.035,reach*(0.52 if t<0.5 else 0.32))
				result[primary].crown_supports.append({"center":sample(result[primary].path,t),"radii":Vector3(1.0,0.55,1.0)*span})
			for pair in int(settings.branch_splits):
				for sign in [-1.0,1.0]:
					var t:=0.18+pair*0.24+(0.035 if sign>0 else 0.0)
					var root:=sample(result[primary].path,t)
					var direction: Vector3=(radial*0.48+side*sign*0.88).normalized()
					var length:=reach*lerpf(0.52,0.27,t)*rng.randf_range(0.92,1.08)
					var secondary:=result.size();var sr:=radius(result[primary],t)*0.45
					_append(result,primary,t,2,root,root+direction*length-Vector3.UP*length*0.26,Vector3.ZERO,sr,sr*0.08,1)
					var parent:=secondary;var extent:=length
					for order in range(3,int(settings.branch_levels)+1):
						var q:=0.64 if order==3 else 0.72
						var anchor:=sample(result[parent].path,q)
						var twig_direction: Vector3=(direction*0.70+radial*0.35).normalized()
						var tr:=radius(result[parent],q)*0.44;extent*=0.56
						var twig:=result.size()
						_append(result,parent,q,order,anchor,anchor+twig_direction*extent-Vector3.UP*extent*0.40,Vector3.ZERO,tr,tr*0.08,1)
						parent=twig
	result[0]["crown_supports"]=[]
	for tier in tiers+1:
		var t:=lerpf(float(settings.branch_start)/100.0,0.98,float(tier)/tiers)
		var span:=maxf(h*0.016,h*0.24*pow(1.0-float(tier)/tiers*0.98,0.85)*float(settings.crown_spread)/55.0)
		result[0].crown_supports.append({"center":sample(result[0].path,t),"radii":Vector3(span,minf(h*(0.98-float(settings.branch_start)/100.0)/tiers,h*(0.995-t*0.97)),span)})
	for i in 4:
		var radial:=Vector3(cos(heading+i*TAU/4.0),0,sin(heading+i*TAU/4.0))
		_append(result,0,0.025,-1,sample(result[0].path,0.025),radial*width*(1.0+float(settings.root_flare)/100.0),Vector3.ZERO,width*0.55,0.025,1)
	return result

static func _spruce_twigs(result: Array,parent: int,direction: Vector3,reach: float,settings: Dictionary,rng: RandomNumberGenerator,order: int) -> void:
	if order>int(settings.branch_levels):return
	var count:=int(settings.branch_splits) if order==2 else 1
	for i in count:
		var t:=0.34+float(i)*0.20 if order==2 else 0.72
		var start:=sample(result[parent].path,t)
		var turn:=-0.85 if i%2==0 else 0.85
		var radial:=direction.rotated(Vector3.UP,turn+rng.randf_range(-0.12,0.12))
		var length:=reach*(0.40 if order==2 else 0.52)
		var r:=radius(result[parent],t)*0.48
		var id:=result.size()
		_append(result,parent,t,order,start,start+radial*length-Vector3.UP*length*0.16,Vector3.DOWN*length*0.08,r,r*0.05,3 if order==2 else 2)
		_spruce_twigs(result,id,radial,length,settings,rng,order+1)

static func _crown_plan(settings: Dictionary, seed: int) -> Array:
	var rng := RandomNumberGenerator.new(); rng.seed = maxi(seed, 0) + 982451671
	var branches: Array = []
	var height := float(settings.height)
	var heading := rng.randf() * TAU
	var width := float(settings.trunk_width) * 0.78
	_append(branches, -1, 0, 0, Vector3.ZERO, Vector3.UP * height * 0.76,
		Vector3.ZERO, width * 1.15, width * 0.025, 8)
	branches[0].radius_power = 1.55
	# A curved leader and unequal shoulders, not evenly spaced arms on a cone.
	var trunk: Array[Vector3] = [Vector3.ZERO, Vector3(0.015,0.15,-0.010),
		Vector3(-0.020,0.30,0.025), Vector3(0.025,0.47,0.035),
		Vector3(0.060,0.62,0.015), Vector3(0.095,0.76,0.045)]
	for i in range(1, trunk.size()): trunk[i] = (trunk[i] * height).rotated(Vector3.UP, heading)
	trunk = _curved_path(trunk,8)
	branches[0].path = trunk
	var insertions: Array[float] = [0.47, 0.61, 0.75, 0.83, 0.94]
	var angles: Array[float] = [-2.85, 0.20, 2.40, -0.75, 4.40]
	var reaches: Array[float] = [0.20, 0.34, 0.31, 0.27, 0.27]
	var heights: Array[float] = [0.45, 0.69, 0.78, 0.61, 0.80]
	for i in 5:
		var at := insertions[i]
		var angle := heading + angles[i] + rng.randf_range(-0.10, 0.10)
		var outward := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-sin(angle), 0, cos(angle))
		var reach := height * reaches[i] * float(settings.crown_spread) / 65.0
		var start := sample(trunk, at)
		var finish := start + outward * reach
		finish.y = height * (heights[i] + rng.randf_range(-0.015, 0.015))
		var base_radius := radius(branches[0], at) * (0.78 if i == 4 else 0.68)
		var primary := branches.size()
		_append(branches, 0, at, 1, start, finish,
			side * reach * rng.randf_range(-0.12, 0.12) + Vector3.UP * reach * 0.08,
			base_radius, base_radius * 0.07, 4)
		branches[-1].radius_power = 1.15
		for j in 3:
			var t := 0.46 + j * 0.24
			var anchor := sample(branches[primary].path, t)
			var turn: float = angle + [-0.65, 0.70, -0.10][j]
			var direction := Vector3(cos(turn), 0, sin(turn))
			var extent := height * rng.randf_range(0.095, 0.15)
			var tip := anchor + direction * extent
			tip.y = clampf(finish.y + height * rng.randf_range(-0.075, 0.055), height * 0.40, height * 0.88)
			var secondary := branches.size()
			var r := radius(branches[primary], t) * 0.58
			_append(branches, primary, t, 2, anchor, tip,
				side * extent * 0.13, r, r * 0.06, 2)
			branches[-1].crown_radii = Vector3(0.12,0.14,0.12) * height * rng.randf_range(0.92,1.12)
			for k in 2:
				var twig_at := 0.52 + k * 0.38
				var base := sample(branches[secondary].path, twig_at)
				var twig_direction := direction.rotated(Vector3.UP, -0.85 if k == 0 else 0.85)
				var terminal := base + twig_direction * height * rng.randf_range(0.055,0.095)
				terminal.y = clampf(tip.y + height * rng.randf_range(-0.09,0.09), height * 0.34, height * 0.90)
				var twig_radius := radius(branches[secondary], twig_at) * 0.52
				_append(branches, secondary, twig_at, 3, base, terminal,
					side * height * 0.012, twig_radius, twig_radius * 0.07, 2)
				branches[-1].crown_radii = Vector3(0.09,0.10,0.09) * height
	for i in 5:
		var angle := heading + i * TAU / 5.0
		_append(branches, 0, 0.055, -1, sample(trunk, 0.055),
			Vector3(cos(angle),0,sin(angle)) * width * 1.75,
			Vector3.UP * width * 0.08, width * 0.68, 0.045, 1)
	return branches

static func _curved_path(knots: Array[Vector3], segments: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in segments+1:
		var at := float(i)/segments*(knots.size()-1)
		var index := mini(floori(at),knots.size()-2)
		var t := at-index
		var a := knots[maxi(0,index-1)]; var b := knots[index]
		var c := knots[index+1]; var d := knots[mini(knots.size()-1,index+2)]
		result.append((b*2.0+(-a+c)*t+(a*2.0-b*5.0+c*4.0-d)*t*t+(-a+b*3.0-c*3.0+d)*t*t*t)*0.5)
	return result

static func _branchy_plan(settings: Dictionary, seed: int) -> Array:
	var rng := RandomNumberGenerator.new(); rng.seed = maxi(seed, 0) + 982451683
	var result: Array = []
	var h := float(settings.height)
	var heading := rng.randf() * TAU
	var width := float(settings.trunk_width) * 0.72
	var spread := float(settings.crown_spread) / 65.0
	var curve := float(settings.branch_curve) / 55.0
	var thickness := float(settings.branch_thickness) / 75.0
	_append(result, -1, 0, 0, Vector3.ZERO, Vector3.UP * h * 0.90,
		Vector3.ZERO, width, width * 0.018, 8)
	var knots: Array[Vector3] = [Vector3.ZERO, Vector3(0.005,0.17,-0.012),
		Vector3(-0.016,0.34,0.018), Vector3(0.028,0.52,0.028),
		Vector3(0.090,0.72,-0.025), Vector3(0.200,0.87,-0.065)]
	for i in knots.size(): knots[i] = (knots[i] * h).rotated(Vector3.UP, heading)
	result[0].path = _curved_path(knots,8); result[0].radius_power = 1.25
	# Unequal scaffold limbs spiral around the leader at staggered heights.
	# Each keeps growing beyond its side forks; descendants inherit its sweep.
	for i in 5:
		var at: float = [0.40,0.51,0.63,0.75,0.86][i]
		var angle := heading + i * 2.399963 + rng.randf_range(-0.24,0.24)
		var direction := Vector3(cos(angle),0,sin(angle))
		var side := direction.cross(Vector3.UP)
		var reach: float = h * [0.31,0.34,0.29,0.25,0.18][i] * spread
		var start := sample(result[0].path,at)
		var end := start + direction * reach
		end.y = h * ([0.61,0.72,0.80,0.86,0.91][i] + rng.randf_range(-0.02,0.02))
		var r := radius(result[0],at) * minf(0.82,0.71 * thickness)
		var primary := result.size()
		_append(result,0,at,1,start,end,side*reach*rng.randf_range(-0.16,0.16)*curve-Vector3.UP*reach*0.12*curve,r,r*0.025,5)
		var rise := end.y-start.y
		var limb_knots: Array[Vector3] = [start,
			start+direction*reach*0.24+Vector3.UP*rise*0.12+side*reach*0.08*curve,
			start+direction*reach*0.65+Vector3.UP*rise*0.52-side*reach*0.06*curve,end]
		result[-1].path = _curved_path(limb_knots,5)
		result[-1].radius_power = 0.78
		for j in 3:
			var t := 0.30 + j * 0.24 + rng.randf_range(-0.035,0.035)
			var turn := angle + (-1.0 if j%2==0 else 0.80) + rng.randf_range(-0.20,0.20)
			var outward := Vector3(cos(turn),0,sin(turn))
			var anchor := sample(result[primary].path,t)
			var extent := reach * rng.randf_range(0.55,0.78)
			var tip := anchor + outward*extent + Vector3.UP*h*rng.randf_range(0.07,0.14)
			var secondary := result.size()
			var sr := radius(result[primary],t) * rng.randf_range(0.76,0.86)
			_append(result,primary,t,2,anchor,tip,direction*extent*0.12*curve-Vector3.UP*extent*0.10*curve,sr,sr*0.035,3)
			var fork_knots: Array[Vector3] = [anchor,
				anchor+outward*extent*0.38+Vector3.UP*(tip.y-anchor.y)*0.22+direction*extent*0.12*curve,tip]
			result[-1].path = _curved_path(fork_knots,3)
			for k in 3:
				var q := 0.33 + k*0.25 + rng.randf_range(-0.03,0.03)
				var base := sample(result[secondary].path,q)
				var twig_dir := outward.rotated(Vector3.UP,(-0.90 if k%2==0 else 0.85)+rng.randf_range(-0.22,0.22))
				var length := extent*rng.randf_range(0.55,0.78)
				var terminal := base+twig_dir*length+Vector3.UP*length*rng.randf_range(0.35,0.80)
				var tertiary := result.size()
				var tr := radius(result[secondary],q)*rng.randf_range(0.70,0.82)
				_append(result,secondary,q,3,base,terminal,outward*length*0.15*curve,tr,tr*0.045,2)
				# Alternating short shoots give leaf attachment sites across each
				# limb, rather than attaching a whole canopy to five endpoints.
				for n in (2 if k==1 else 1):
					var s := 0.52+n*0.28+rng.randf_range(-0.07,0.07)
					var root := sample(result[tertiary].path,s)
					var shoot_dir := twig_dir.rotated(Vector3.UP,(-0.85 if n==0 else 0.85))
					var size := length*rng.randf_range(0.40,0.63)
					var shoot_radius := radius(result[tertiary],s)*0.62
					_append(result,tertiary,s,4,root,root+shoot_dir*size+Vector3.UP*size*0.65,
						Vector3.ZERO,shoot_radius,shoot_radius*0.08,1)
	for i in 5:
		var angle := heading+i*TAU/5.0+rng.randf_range(-0.16,0.16)
		_append(result,0,0.04,-1,sample(result[0].path,0.04),
			Vector3(cos(angle),0,sin(angle))*width*rng.randf_range(1.7,2.2),
			Vector3.UP*width*0.06,width*0.63,0.045,1)
	return result

## Recursive growth, depth falloff and seeded variation follow tree-gen's
## _grow/_child_length/_child_radius (MIT, Flow Construct Studios, 2026).
## Adaptation emits provider supports, not another mesh/Resource owner.
static func _recursive_plan(settings: Dictionary, seed: int) -> Array:
	var result: Array = []
	var rng := RandomNumberGenerator.new(); rng.seed=maxi(seed,0)+982451699
	var h := float(settings.height)
	var heading := rng.randf()*TAU
	var width := float(settings.trunk_width)*0.66
	var knots: Array[Vector3]=[Vector3.ZERO,Vector3(0.005,0.17,-0.012),
		Vector3(-0.016,0.34,0.018),Vector3(0.028,0.52,0.028),
		Vector3(0.090,0.72,-0.025),Vector3(0.170,0.85,-0.060)]
	for i in knots.size():knots[i]=(knots[i]*h).rotated(Vector3.UP,heading)
	_append(result,-1,0,0,Vector3.ZERO,knots[-1],Vector3.ZERO,width,width*0.06,8)
	result[0].path=_curved_path(knots,8);result[0].radius_power=1.10
	var count := int(settings.main_branch_count)
	for i in count:
		var rank := float(i)/maxi(1,count-1)
		var local_rng := RandomNumberGenerator.new();local_rng.seed=maxi(seed,0)+i*104729+821
		var at := lerpf(0.34,0.88,rank)+local_rng.randf_range(-0.015,0.015)
		if i==count-1:at=1.0 # Continue the leader into a real shoot, not a cut pole.
		var angle := heading+i*2.399963+local_rng.randf_range(-0.22,0.22)
		var outward := Vector3(cos(angle),0,sin(angle))
		var start := sample(result[0].path,at)
		var reach := h*lerpf(0.29,0.17,rank)*float(settings.crown_spread)/65.0
		var growth := (outward+Vector3.UP*lerpf(0.36,0.60,rank)).normalized()
		var r := radius(result[0],at)*minf(0.78,float(settings.branch_thickness)/100.0)
		_grow_recursive(result,settings,0,at,1,start,growth,reach,r,local_rng.seed)
	for i in 5:
		var angle := heading+i*TAU/5.0
		_append(result,0,0.04,-1,sample(result[0].path,0.04),
			Vector3(cos(angle),0,sin(angle))*width*1.9,
			Vector3.UP*width*0.06,width*0.63,0.045,1)
	return result

## Birch keeps a narrow continuous leader and ascending main limbs whose fine
## outer shoots hang. Only opt-in22 reaches this plan; oak21 is unchanged.
static func _birch_plan(settings: Dictionary,seed: int) -> Array:
	var result: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(seed,0)+982451699
	var heading:=rng.randf()*TAU
	var h:=float(settings.height);var width:=float(settings.trunk_width)*0.47
	var knots: Array[Vector3]=[Vector3.ZERO,Vector3(0.005,0.20,-0.008),
		Vector3(-0.014,0.40,0.012),Vector3(0.017,0.63,0.025),
		Vector3(0.038,0.80,0.010),Vector3(0.050,0.95,-0.025)]
	for i in knots.size():knots[i]=(knots[i]*h).rotated(Vector3.UP,heading)
	_append(result,-1,0,0,Vector3.ZERO,knots[-1],Vector3.ZERO,width,width*0.045,10)
	result[0].path=_curved_path(knots,10);result[0].radius_power=0.95
	var count:=int(settings.main_branch_count)
	for i in count:
		var local_rng:=RandomNumberGenerator.new();local_rng.seed=maxi(seed,0)+i*104729+821
		var rank:=float(i)/maxi(count-1,1)
		var at:=lerpf(float(settings.branch_start)/100.0,0.88,rank)+local_rng.randf_range(-0.025,0.025)
		if i==count-1:at=1.0
		var angle:=heading+i*2.399963+local_rng.randf_range(-0.35,0.35)
		var outward:=Vector3(cos(angle),0,sin(angle))
		var start:=sample(result[0].path,at)
		var length:=h*lerpf(0.24,0.10,rank)*float(settings.crown_spread)/55.0
		var direction:=(outward+Vector3.UP*lerpf(0.62,0.96,rank)).normalized()
		var r:=radius(result[0],at)*minf(0.65,float(settings.branch_thickness)/100.0)
		_grow_recursive(result,settings,0,at,1,start,direction,length,r,local_rng.seed)
	for i in 3:
		var angle:=heading+i*TAU/3.0
		_append(result,0,0.02,-1,sample(result[0].path,0.02),
			Vector3(cos(angle),0,sin(angle))*width*(1.0+float(settings.root_flare)/100.0),
			Vector3.ZERO,width*0.50,0.025,1)
	return result

## Maple opens into low ascending forks and a broad arched crown. Shared
## recursive growth supplies connected secondary/terminal shoots.
static func _maple_plan(settings: Dictionary,seed: int) -> Array:
	if int(settings.crown_shape)==1:return _maple_upright_plan(settings,seed)
	var result: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(seed,0)+982451699
	var heading:=rng.randf()*TAU
	var h:=float(settings.height);var width:=float(settings.trunk_width)*0.56
	var knots: Array[Vector3]=[Vector3.ZERO,Vector3(0.015,0.16,-0.008),
		Vector3(-0.025,0.30,0.012),Vector3(0.025,0.47,0.020),Vector3(0.045,0.63,-0.020)]
	for i in knots.size():knots[i]=(knots[i]*h).rotated(Vector3.UP,heading)
	_append(result,-1,0,0,Vector3.ZERO,knots[-1],Vector3.ZERO,width,width*0.18,8)
	result[0].path=_curved_path(knots,8);result[0].radius_power=0.90
	var count:=int(settings.main_branch_count)
	for i in count:
		var local_rng:=RandomNumberGenerator.new();local_rng.seed=maxi(seed,0)+i*104729+821
		var rank:=float(i)/maxi(count-1,1)
		var at:=lerpf(clampf(float(settings.branch_start)/63.0,0.35,0.65),0.92,rank)+local_rng.randf_range(-0.025,0.025)
		if i==count-1:at=1.0
		var angle:=heading+i*2.399963+local_rng.randf_range(-0.30,0.30)
		var outward:=Vector3(cos(angle),0,sin(angle))
		var start:=sample(result[0].path,at)
		var reach:=h*lerpf(0.30,0.21,rank)*float(settings.crown_spread)/65.0
		var direction:=(outward+Vector3.UP*lerpf(0.75,1.15,rank)).normalized()
		var r:=radius(result[0],at)*minf(0.78,float(settings.branch_thickness)/100.0)
		_grow_recursive(result,settings,0,at,1,start,direction,reach,r,local_rng.seed)
	for i in 5:
		var angle:=heading+i*TAU/5.0
		_append(result,0,0.03,-1,sample(result[0].path,0.03),
			Vector3(cos(angle),0,sin(angle))*width*(1.0+float(settings.root_flare)/100.0),
			Vector3.ZERO,width*0.55,0.035,1)
	return result

## Upright maple: an intact leader and progressively shorter upper limbs.
## This is real support geometry, not scaling the accepted wide tree mesh.
static func _maple_upright_plan(settings: Dictionary,seed: int) -> Array:
	var result: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(seed,0)+982451699
	var heading:=rng.randf()*TAU
	var h:=float(settings.height);var width:=float(settings.trunk_width)*0.52
	var knots: Array[Vector3]=[Vector3.ZERO,Vector3(0.010,0.18,-0.008),
		Vector3(-0.012,0.39,0.008),Vector3(0.015,0.61,0.015),
		Vector3(0.028,0.80,0.005),Vector3(0.036,0.95,-0.018)]
	for i in knots.size():knots[i]=(knots[i]*h).rotated(Vector3.UP,heading)
	_append(result,-1,0,0,Vector3.ZERO,knots[-1],Vector3.ZERO,width,width*0.10,10)
	result[0].path=_curved_path(knots,10);result[0].radius_power=1.0
	var count:=int(settings.main_branch_count)
	for i in count:
		var local_rng:=RandomNumberGenerator.new();local_rng.seed=maxi(seed,0)+i*104729+821
		var rank:=float(i)/maxi(count-1,1)
		var at:=lerpf(float(settings.branch_start)/95.0,0.91,rank)+local_rng.randf_range(-0.02,0.02)
		if i==count-1:at=1.0
		var angle:=heading+i*2.399963+local_rng.randf_range(-0.24,0.24)
		var outward:=Vector3(cos(angle),0,sin(angle))
		var start:=sample(result[0].path,at)
		var reach:=h*lerpf(0.20,0.065,rank)*float(settings.crown_spread)/65.0
		var direction:=(outward+Vector3.UP*lerpf(0.50,1.60,rank)).normalized()
		var r:=radius(result[0],at)*minf(0.72,float(settings.branch_thickness)/100.0)
		_grow_recursive(result,settings,0,at,1,start,direction,reach,r,local_rng.seed)
	for i in 5:
		var angle:=heading+i*TAU/5.0
		_append(result,0,0.025,-1,sample(result[0].path,0.025),
			Vector3(cos(angle),0,sin(angle))*width*(1.0+float(settings.root_flare)/100.0),
			Vector3.ZERO,width*0.55,0.035,1)
	return result

## Savanna: a crooked high fork carries outward scaffolds. Descendants spread
## in shallow fans; the same recursion, attachment and Recipe own every limb.
static func _savanna_plan(settings: Dictionary,seed: int) -> Array:
	if int(settings.crown_shape)==1:return _savanna_umbrella_plan(settings,seed)
	var result: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(seed,0)+982451699
	var heading:=rng.randf()*TAU
	var h:=float(settings.height);var width:=float(settings.trunk_width)*0.62
	var knots: Array[Vector3]=[Vector3.ZERO,Vector3(0.020,0.17,-0.008),
		Vector3(-0.022,0.34,0.025),Vector3(0.040,0.49,0.020),Vector3(0.075,0.64,-0.025)]
	for i in knots.size():knots[i]=(knots[i]*h).rotated(Vector3.UP,heading)
	_append(result,-1,0,0,Vector3.ZERO,knots[-1],Vector3.ZERO,width,width*0.23,8)
	result[0].path=_curved_path(knots,8);result[0].radius_power=0.85
	var count:=int(settings.main_branch_count)
	for i in count:
		var local_rng:=RandomNumberGenerator.new();local_rng.seed=maxi(seed,0)+i*104729+821
		var rank:=float(i)/maxi(count-1,1)
		var at:=lerpf(clampf(float(settings.branch_start)/64.0,0.45,0.85),1.0,rank)
		var angle:=heading+i*2.399963+local_rng.randf_range(-0.28,0.28)
		var outward:=Vector3(cos(angle),0,sin(angle))
		var start:=sample(result[0].path,at)
		var reach:=h*lerpf(0.39,0.23,rank)*float(settings.crown_spread)/80.0
		var top:=h*(0.78+local_rng.randf_range(-0.035,0.035))
		var direction:=(outward*reach+Vector3.UP*(top-start.y)).normalized()
		var r:=radius(result[0],at)*minf(0.78,float(settings.branch_thickness)/100.0)
		_grow_recursive(result,settings,0,at,1,start,direction,Vector2(reach,top-start.y).length(),r,local_rng.seed)
	for i in 4:
		var angle:=heading+i*TAU/4.0
		_append(result,0,0.025,-1,sample(result[0].path,0.025),
			Vector3(cos(angle),0,sin(angle))*width*(1.0+float(settings.root_flare)/100.0),
			Vector3.ZERO,width*0.55,0.035,1)
	return result

## Umbrella blockout: low major forks rise together to support one crown.
## The rejected shape0 remains exactly reproducible for comparison.
static func _savanna_umbrella_plan(settings: Dictionary,seed: int) -> Array:
	var result: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=maxi(seed,0)+982451699
	var heading:=rng.randf()*TAU
	var h:=float(settings.height);var width:=float(settings.trunk_width)*0.62
	var knots: Array[Vector3]=[Vector3.ZERO,Vector3(0.010,0.14,-0.008),
		Vector3(-0.018,0.27,0.015),Vector3(0.025,0.42,0.008)]
	for i in knots.size():knots[i]=(knots[i]*h).rotated(Vector3.UP,heading)
	_append(result,-1,0,0,Vector3.ZERO,knots[-1],Vector3.ZERO,width,width*0.30,8)
	result[0].path=_curved_path(knots,8);result[0].radius_power=0.80
	var count:=int(settings.main_branch_count)
	for i in count:
		var local_rng:=RandomNumberGenerator.new();local_rng.seed=maxi(seed,0)+i*104729+821
		var rank:=float(i)/maxi(count-1,1)
		var at:=lerpf(clampf(float(settings.branch_start)/55.0,0.48,0.85),1.0,rank)
		var angle:=heading+i*2.399963+local_rng.randf_range(-0.22,0.22)
		var start:=sample(result[0].path,at)
		var reach:=h*lerpf(0.36,0.24,rank)*float(settings.crown_spread)/80.0
		var target:=Vector3(cos(angle)*reach,h*(0.68+local_rng.randf_range(-0.025,0.025)),sin(angle)*reach)
		var delta:=target-start
		var r:=radius(result[0],at)*minf(0.84,float(settings.branch_thickness)/100.0)
		_grow_recursive(result,settings,0,at,1,start,delta.normalized(),delta.length(),r,local_rng.seed)
	for i in 4:
		var angle:=heading+i*TAU/4.0
		_append(result,0,0.025,-1,sample(result[0].path,0.025),
			Vector3(cos(angle),0,sin(angle))*width*(1.0+float(settings.root_flare)/100.0),
			Vector3.ZERO,width*0.55,0.035,1)
	return result

static func _grow_recursive(result: Array,settings: Dictionary,parent: int,attachment: float,
	order: int,start: Vector3,direction: Vector3,length: float,r: float,seed: int) -> void:
	var rng := RandomNumberGenerator.new();rng.seed=seed
	var terminal := order>=int(settings.branch_levels)
	var variation := float(settings.branch_count_variation)/100.0
	var curve := float(settings.branch_curve)/100.0
	var segments: int=[0,5,3,2,1][order]
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared()<0.1:side=Vector3.RIGHT
	if int(settings.generation_version)==22 and order>=2:
		direction=(direction-Vector3.UP*(0.36 if terminal else 0.16)).normalized()
	if int(settings.generation_version)==24 and int(settings.crown_shape)!=1 and order>=2:
		direction.y*=0.18
		direction=direction.normalized()
	if int(settings.generation_version)==24 and int(settings.crown_shape)==1 and order>=2:
		var horizontal:=Vector3(direction.x,0,direction.z).normalized()
		if horizontal.length_squared()<0.1:horizontal=Vector3.RIGHT
		var roof:=float(settings.height)*(0.74+sin(float(seed))*0.012)
		var rise:=clampf((roof-start.y)/maxf(length,0.001),-0.20,0.65)
		direction=horizontal*sqrt(1.0-rise*rise)+Vector3.UP*rise
	var end := start+direction*length
	var knee := start+direction*length*0.46-Vector3.UP*length*curve*0.18+side*length*rng.randf_range(-0.18,0.18)*curve
	var id := result.size()
	_append(result,parent,attachment,order,start,end,Vector3.ZERO,r,r*(0.035 if terminal else 0.48),segments)
	var knots: Array[Vector3]=[start,knee,end]
	result[-1].path=_curved_path(knots,segments)
	result[-1].radius_power=0.85
	if terminal:return
	var children := int(settings.branch_splits)
	if rng.randf()<variation*0.80:children=clampi(children+(-1 if rng.randf()<0.5 else 1),1,3)
	var axis := (end-knee).normalized()
	var reference := Vector3.UP if absf(axis.dot(Vector3.UP))<0.95 else Vector3.RIGHT
	var lateral := reference.cross(axis).normalized()
	var spin_base := rng.randf()*TAU
	for i in children:
		# Two terminal children form a real fork. A third may be a side shoot.
		var at := 0.58 if children==3 and i==0 else 1.0
		if int(settings.generation_version)==24 and int(settings.crown_shape)==1 and children==3 and i==0:at=0.86
		var anchor := sample(result[id].path,at)
		var spin := spin_base+i*TAU/children+rng.randf_range(-0.20,0.20)*variation
		var spread := deg_to_rad(rng.randf_range(28.0,49.0))
		var child_direction := axis.rotated(lateral,spread).rotated(axis,spin)
		child_direction=(child_direction+Vector3.UP*(-0.04 if int(settings.generation_version)==22 else 0.13)).normalized()
		if int(settings.generation_version)==24:
			# Side forks remain a shallow umbrella rather than another oak ball.
			if int(settings.crown_shape)==1:child_direction.y=clampf(child_direction.y,0.06,0.20)
			else:child_direction.y*=0.35
			child_direction=child_direction.normalized()
		var child_length := length*rng.randf_range(0.52,0.69)*(1.0+rng.randf_range(-0.13,0.13)*variation)
		var child_radius := radius(result[id],at)*(0.56 if children==3 else 0.66)*(1.0+rng.randf_range(-0.06,0.06)*variation)
		_grow_recursive(result,settings,id,at,order+1,anchor,child_direction,child_length,child_radius,seed*31+i+1)

static func structure_errors(lines: Array, max_order := 3) -> Array[String]:
	var paths: Array = []
	for line: Dictionary in lines:
		if not line.get("branch_id") is int or not line.get("parent_id") is int or not line.get("order") is int or not line.get("parent_t") is float:
			return ["У нового каркаса нет иерархии ветвей."]
		var id := int(line.branch_id)
		if id < 0: return ["Некорректный номер ветви нового каркаса."]
		if id == paths.size():
			if line.parent_id >= id or line.parent_id < -1 or not is_finite(line.parent_t) or line.parent_t < 0 or line.parent_t > 1 or line.order < -1 or line.order > max_order or line.t0 != 0.0:
				return ["Некорректная связь ветвей нового каркаса."]
			paths.append({"parent": line.parent_id, "attachment": line.parent_t, "order": line.order,
				"path": [line.start], "radii": [line.r0], "last_t": 0.0, "last_r": line.r0})
		if id != paths.size() - 1:
			return ["Нарушен порядок ветвей нового каркаса."]
		var branch: Dictionary = paths[id]
		if branch.path[-1].distance_to(line.start) > 0.002 or absf(branch.last_t - line.t0) > 0.0001 or absf(branch.last_r - line.r0) > 0.0001 or line.r1 > line.r0 or line.parent_id != branch.parent or line.parent_t != branch.attachment or line.order != branch.order:
			return ["В новом каркасе есть разрыв или обратное утолщение."]
		branch.path.append(line.finish); branch.radii.append(line.r1)
		branch.last_t = line.t1; branch.last_r = line.r1
	for id in paths.size():
		var branch: Dictionary = paths[id]
		if branch.last_t != 1.0 or (id == 0 and (branch.parent != -1 or branch.order != 0)) or (id > 0 and branch.parent < 0):
			return ["В новом каркасе не завершена ветвь."]
		if branch.parent >= 0:
			var parent: Dictionary = paths[branch.parent]
			if (branch.order >= 0 and branch.order != parent.order + 1) or branch.path[0].distance_to(sample(parent.path, branch.attachment)) > 0.002:
				return ["Ответвление не прикреплено к родительской ветви."]
			var at: float = branch.attachment * (parent.radii.size() - 1)
			var segment := mini(floori(at), parent.radii.size() - 2)
			var parent_radius := lerpf(parent.radii[segment], parent.radii[segment + 1], at - segment)
			if branch.radii[0] >= parent_radius:
				return ["Ответвление толще родительской ветви."]
	return []
