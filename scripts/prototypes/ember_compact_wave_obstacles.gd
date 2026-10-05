@tool
extends RefCounted
## Local scattered-wave equation, not a bulk-flow solver. A reflecting obstacle
## supplies the missing incident normal derivative; sponge edges absorb the
## scattered wave. Both live and baked modes use this one finite-difference leaf.

const GRID := 33
const CELL := 4.0
const FRAMES := 64
const MAX_PATCHES := 4
const VERSION := 2
const CACHE_ROOT := "user://ember-water-wave-cache"
const Contact = preload("res://scripts/ember_water_contact_3d.gd")

var patches: Array[Dictionary] = []
var atlas: Image
var baked_texture: ImageTexture
var live_texture: ImageTexture
var live_image: Image
var ready := false
var cache_hit := false
var build_us := 0
var update_us := 0
var steps_taken := 0
var strength := 1.0
var mode := 0
var current_time := 0.0
var signature := ""
var _prepare_patch := 0
var _prepare_step := 0
var _build_started := 0
var _live_time := -1.0


func build(document: EmberTerrainPilotResource, shapes: Array[Dictionary], phase: Image,
		shore: Image, sea: RefCounted, settings: Dictionary) -> void:
	patches.clear()
	ready = false
	cache_hit = false
	_build_started = Time.get_ticks_usec()
	_prepare_patch = 0
	_prepare_step = 0
	_live_time = -1.0
	var groups: Array[Array] = []
	for shape in shapes:
		var center: Vector2 = shape.center
		var found := false
		for group in groups:
			if center.distance_to(group[0].center) < 52.0:
				group.append(shape)
				found = true
				break
		if not found and groups.size() < MAX_PATCHES: groups.append([shape])
	for group in groups:
		var center := Vector2.ZERO
		for shape in group: center += shape.center
		center /= group.size()
		var origin := (center - Vector2.ONE * CELL * (GRID - 1) * 0.5).snapped(Vector2.ONE * CELL)
		var center_cell := Vector2i(center)
		var river := document.flow_at_cell(center_cell.x, center_cell.y).length() > 0.08
		var coast: Dictionary = sea.sample(center_cell) if sea != null else {}
		var coastal := not river and not coast.is_empty() and float(coast.distance) < 0.0
		var clock: float = settings.wave_speed * 0.65 + settings.river_speed * 0.92 if river else settings.wave_speed
		var period: float = settings.sea_period if coastal else TAU / maxf(clock, 0.08)
		var wavelength: float = settings.spacing * 16.0 if river else (32.0 if coastal else TAU * 16.0 / 1.71)
		# Fixed CFL <= .48, and a whole number of steps between stored frames.
		var substeps := maxi(2, ceili(wavelength / CELL / (0.48 * FRAMES)))
		var cycle_steps := substeps * FRAMES
		var speed := wavelength / period
		var dt := period / cycle_steps
		var lambda2 := pow(speed * dt / CELL, 2.0)
		var fluid := PackedByteArray()
		var solid := PackedByteArray()
		fluid.resize(GRID * GRID)
		solid.resize(GRID * GRID)
		var incident := PackedFloat32Array()
		incident.resize(FRAMES * GRID * GRID)
		var amplitude: float = settings.sea_height if coastal else settings.wave_height * 0.58 * (settings.river_mix if river else 1.0)
		for z in GRID:
			for x in GRID:
				var index := x + z * GRID
				var point := origin + Vector2(x, z) * CELL
				var cell := Vector2i(point)
				if cell.x < 0 or cell.y < 0 or cell.x >= document.width or cell.y >= document.depth: continue
				var column := document.column_index(cell.x, cell.y)
				if document.column_value("water_materials", column) == 0 or document.column_value("water_levels", column) <= document.column_value("heights", column): continue
				# A local field cannot couple different authored water levels.
				if document.column_value("water_levels", column) != document.column_value("water_levels", document.column_index(clampi(center_cell.x, 0, document.width - 1), clampi(center_cell.y, 0, document.depth - 1))): continue
				fluid[index] = 1
				for shape in group:
					if Contact.footprint_signed_distance(point, shape) <= CELL * 0.25:
						fluid[index] = 0
						solid[index] = 1
				var spatial := point.dot(Vector2(0.78, 0.63).normalized()) / 16.0 * 1.71
				var taper := 1.0
				if river and phase != null:
					var channel := _bilinear(phase, point / 16.0 - Vector2.ONE * 0.5)
					var radius: float = lerpf(0.30, 3.0, settings.opening)
					spatial = (channel.r + (sqrt(channel.g * channel.g + radius * radius) - radius) * 1.35) * TAU / maxf(settings.spacing, 3.0)
					var depth := float(document.column_value("water_levels", column) - document.column_value("heights", column)) + float(settings.get("offset",0.0))
					var bank: float = sea.shore_distance(point) * 3.0 / 8.0 if sea != null and sea.has_method("shore_distance") else (shore.get_pixel(clampi(cell.x, 0, shore.get_width()-1), clampi(cell.y, 0, shore.get_height()-1)).r * 255.0 / 8.0 if shore != null else 20.0)
					taper = smoothstep(0.0, 12.0, depth) * smoothstep(0.25, 3.0, bank)
				for frame in FRAMES:
					var value := amplitude * sin(spatial - float(frame) * TAU / FRAMES) * taper
					if coastal: value = sea.incident_height(point, float(frame) * period / FRAMES, amplitude, period,
						settings.sea_reach, settings.get("sea_approach", 20.0), settings.get("sea_approach_strength", 0.65))
					incident[frame * GRID * GRID + index] = value
		var active := PackedInt32Array()
		var neighbors := PackedInt32Array()
		var boundary := PackedInt32Array()
		var forcing := PackedFloat32Array()
		var damping := PackedFloat32Array()
		damping.resize(GRID * GRID)
		for z in range(1, GRID - 1):
			for x in range(1, GRID - 1):
				var index := x + z * GRID
				if fluid[index] == 0: continue
				active.append(index)
				var edges := [index - 1, index + 1, index - GRID, index + GRID]
				var touches := false
				for n in edges:
					neighbors.append(n if fluid[n] != 0 else index)
					if solid[n] != 0: touches = true
				var rim := float(mini(mini(x, z), mini(GRID - 1 - x, GRID - 1 - z)))
				damping[index] = exp(-(0.06 + 5.0 * pow(1.0 - smoothstep(1.0, 7.0, rim), 2.0)) * dt)
				if touches:
					boundary.append(index)
					for frame in FRAMES:
						var force := 0.0
						for n in edges:
							if solid[n] != 0: force += incident[frame * GRID * GRID + index] - incident[frame * GRID * GRID + n]
						forcing.append(force)
		var state := PackedFloat32Array()
		state.resize(GRID * GRID)
		var ages := state.duplicate()
		ages.fill(8.0)
		patches.append({"origin": origin, "period": period, "dt": dt, "lambda2": lambda2,
			"cycle_steps": cycle_steps, "substeps": substeps, "active": active,
			"neighbors": neighbors, "boundary": boundary, "forcing": forcing,
			"damping": damping, "fluid": fluid, "incident": incident, "amplitude": maxf(amplitude, 0.01),
			"coastal": coastal, "age": ages, "velocity": state.duplicate(), "h": state.duplicate(), "prev": state.duplicate(), "next": state.duplicate()})
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var dependencies: Array = []
	for patch: Dictionary in patches: dependencies.append([patch.fluid, patch.incident, patch.origin, patch.period])
	digest.update(var_to_bytes([VERSION, dependencies, shapes, settings]))
	signature = digest.finish().hex_encode()
	if patches.is_empty():
		ready = true
		return
	atlas = Image.create_empty(GRID * 8, GRID * 8 * patches.size(), false, Image.FORMAT_RGBAF)
	live_image = Image.create_empty(GRID, GRID * patches.size(), false, Image.FORMAT_RGBAF)
	live_texture = ImageTexture.create_from_image(live_image)
	var cache := CACHE_ROOT.path_join(signature + ".res")
	if ResourceLoader.exists(cache):
		var cached := ResourceLoader.load(cache) as Image
		if cached != null and cached.get_size() == atlas.get_size() and cached.get_format() == Image.FORMAT_RGBAF:
			atlas = cached
			baked_texture = ImageTexture.create_from_image(atlas)
			ready = true
			cache_hit = true
			build_us = Time.get_ticks_usec() - _build_started


static func _bilinear(image: Image, point: Vector2) -> Color:
	var low := Vector2i(floori(point.x), floori(point.y))
	var part := point - Vector2(low)
	var a := image.get_pixel(clampi(low.x, 0, image.get_width()-1), clampi(low.y, 0, image.get_height()-1))
	var b := image.get_pixel(clampi(low.x+1, 0, image.get_width()-1), clampi(low.y, 0, image.get_height()-1))
	var c := image.get_pixel(clampi(low.x, 0, image.get_width()-1), clampi(low.y+1, 0, image.get_height()-1))
	var d := image.get_pixel(clampi(low.x+1, 0, image.get_width()-1), clampi(low.y+1, 0, image.get_height()-1))
	return a.lerp(b, part.x).lerp(c.lerp(d, part.x), part.y)


func prepare(budget_us := 3000) -> void:
	if ready: return
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < budget_us and _prepare_patch < patches.size():
		var p: Dictionary = patches[_prepare_patch]
		_step(p, float(_prepare_step + 1) * p.dt)
		_prepare_step += 1
		# Four settling cycles, then record one seamless periodic cycle.
		if _prepare_step > 4 * int(p.cycle_steps) and _prepare_step % int(p.substeps) == 0:
			_store_frame(p, _prepare_patch, (_prepare_step / int(p.substeps)) % FRAMES)
		if _prepare_step >= 5 * int(p.cycle_steps):
			_prepare_patch += 1
			_prepare_step = 0
	if _prepare_patch == patches.size():
		ready = true
		baked_texture = ImageTexture.create_from_image(atlas)
		DirAccess.make_dir_recursive_absolute(CACHE_ROOT)
		ResourceSaver.save(atlas, CACHE_ROOT.path_join(signature + ".res"))
		build_us = Time.get_ticks_usec() - _build_started


func _step(p: Dictionary, seconds: float) -> void:
	var h: PackedFloat32Array = p.h
	var previous: PackedFloat32Array = p.prev
	var next: PackedFloat32Array = p.next
	var phase: float = fposmod(seconds / p.period * FRAMES, FRAMES)
	var frame := floori(phase)
	var part := phase - frame
	var active: PackedInt32Array = p.active
	var neighbors: PackedInt32Array = p.neighbors
	var damping: PackedFloat32Array = p.damping
	var lambda2: float = p.lambda2
	for slot in active.size():
		var i := active[slot]
		var base := slot * 4
		var lap := h[neighbors[base]] + h[neighbors[base+1]] + h[neighbors[base+2]] + h[neighbors[base+3]] - h[i] * 4.0
		var drag := 1.0 - damping[i]
		next[i] = (2.0 * h[i] - (1.0 - drag) * previous[i] + lambda2 * lap) / (1.0 + drag)
	var boundary: PackedInt32Array = p.boundary
	var forcing: PackedFloat32Array = p.forcing
	for slot in boundary.size():
		var force := lerpf(forcing[slot * FRAMES + frame], forcing[slot * FRAMES + (frame + 1) % FRAMES], part)
		next[boundary[slot]] += lambda2 * force / (2.0 - damping[boundary[slot]])
	var ages: PackedFloat32Array = p.age
	var incident: PackedFloat32Array = p.incident
	var velocities: PackedFloat32Array = p.velocity
	var old_phase: float = fposmod((seconds - float(p.dt)) / p.period * FRAMES, FRAMES)
	var old_frame := floori(old_phase)
	var old_part := old_phase - old_frame
	for i in active:
		var total := next[i] + lerpf(incident[frame*GRID*GRID+i], incident[((frame+1)%FRAMES)*GRID*GRID+i], part)
		var old_total := h[i] + lerpf(incident[old_frame*GRID*GRID+i], incident[((old_frame+1)%FRAMES)*GRID*GRID+i], old_part)
		var velocity := (total-old_total)/float(p.dt)
		ages[i] = 0.0 if velocity <= 0.0 and velocities[i] > 0.0 and total > float(p.amplitude) * 0.2 else minf(8.0, ages[i] + float(p.dt))
		velocities[i] = velocity
	p.age = ages
	p.velocity = velocities
	p.prev = h
	p.h = next
	p.next = previous
	steps_taken += 1


func _store_frame(p: Dictionary, patch: int, frame: int) -> void:
	var offset := Vector2i((frame % 8) * GRID, (frame / 8 + patch * 8) * GRID)
	var h: PackedFloat32Array = p.h
	var incident: PackedFloat32Array = p.incident
	var fluid: PackedByteArray = p.fluid
	for z in GRID:
		for x in GRID:
			var i := x + z * GRID
			atlas.set_pixelv(offset + Vector2i(x, z), Color(h[i], incident[frame * GRID * GRID + i] + h[i], p.age[i], float(fluid[i])))


func _baked(patch: int, point: Vector2, seconds: float) -> Color:
	var p: Dictionary = patches[patch]
	var phase: float = fposmod(seconds / p.period * FRAMES, FRAMES)
	var first := floori(phase)
	var local: Vector2 = (point - p.origin) / CELL
	var offset_a := Vector2((first % 8) * GRID, (first / 8 + patch * 8) * GRID)
	var second := (first + 1) % FRAMES
	var offset_b := Vector2((second % 8) * GRID, (second / 8 + patch * 8) * GRID)
	# Clamp within one frame so atlas bilinear filtering cannot cross frames.
	local = local.clamp(Vector2.ZERO, Vector2.ONE * (GRID - 1))
	return _bilinear(atlas, offset_a + local).lerp(_bilinear(atlas, offset_b + local), phase - first)


func advance(seconds: float, next_mode: int, next_strength: float, sea_seconds := -1.0) -> void:
	mode = next_mode
	strength = next_strength
	current_time = seconds
	for p in patches: p["clock"] = sea_seconds if p.coastal and sea_seconds >= 0.0 else seconds
	update_us = 0
	if not ready or patches.is_empty() or mode != 2 or strength <= 0.001:
		_live_time = -1.0
		return
	var started := Time.get_ticks_usec()
	# Seed from the cached periodic solution on mode changes/time seeks; never
	# integrate a giant elapsed step, or queue unlimited catch-up work.
	if _live_time < 0.0 or seconds < _live_time or seconds - _live_time > 0.25:
		for patch in patches.size():
			var p: Dictionary = patches[patch]
			var target: float = p.clock
			for z in GRID:
				for x in GRID:
					var point: Vector2 = p.origin + Vector2(x,z) * CELL
					p.h[x+z*GRID] = _baked(patch, point, target).r
					p.prev[x+z*GRID] = _baked(patch, point, target - p.dt).r
					p.age[x+z*GRID] = _baked(patch, point, target).b
					p.velocity[x+z*GRID] = (_baked(patch, point, target).g-_baked(patch, point, target-p.dt).g)/float(p.dt)
			p["time"] = target
		_live_time = seconds
	for patch in patches.size():
		var p: Dictionary = patches[patch]
		var ticks := mini(16, floori((float(p.clock) - float(p.get("time", p.clock))) / p.dt))
		for _tick in ticks:
			p.time += p.dt
			_step(p, p.time)
		var phase: float = fposmod(p.time / p.period * FRAMES, FRAMES)
		var frame := floori(phase)
		var part := phase - frame
		for z in GRID:
			for x in GRID:
				var i := x + z * GRID
				var incident: float = lerpf(p.incident[frame*GRID*GRID+i], p.incident[((frame+1)%FRAMES)*GRID*GRID+i], part)
				live_image.set_pixel(x, z+patch*GRID, Color(p.h[i], incident + p.h[i], p.age[i], float(p.fluid[i])))
	live_texture.update(live_image)
	_live_time = seconds
	update_us = Time.get_ticks_usec() - started


func sample(point: Vector2) -> Vector2:
	if not ready or mode == 0 or strength <= 0.001: return Vector2.ZERO
	for patch in patches.size():
		var p: Dictionary = patches[patch]
		var local: Vector2 = (point - p.origin) / CELL
		if local.x < 0 or local.y < 0 or local.x > GRID-1 or local.y > GRID-1: continue
		var value := _baked(patch, point, float(p.clock)) if mode == 1 else _bilinear(live_image, local + Vector2(0, patch*GRID))
		var rim := minf(minf(local.x,local.y), minf(GRID-1-local.x,GRID-1-local.y))
		return Vector2(value.r, value.g) * strength * smoothstep(0.0, 5.0, rim) * value.a
	return Vector2.ZERO


func bind(material: ShaderMaterial, world_origin: Vector2) -> void:
	material.set_shader_parameter("obstacle_patch_count", patches.size() if ready and mode != 0 and strength > 0.001 else 0)
	if not ready or patches.is_empty(): return
	var bounds := PackedVector4Array()
	var details := PackedVector2Array()
	bounds.resize(MAX_PATCHES)
	details.resize(MAX_PATCHES)
	for i in patches.size():
		var p: Dictionary = patches[i]
		bounds[i] = Vector4(p.origin.x + world_origin.x, p.origin.y + world_origin.y, p.period, p.amplitude)
		details[i] = Vector2(1.0 if p.coastal else 0.0, float(p.get("time", current_time)))
	material.set_shader_parameter("obstacle_bounds", bounds)
	material.set_shader_parameter("obstacle_details", details)
	material.set_shader_parameter("obstacle_baked_field", baked_texture)
	material.set_shader_parameter("obstacle_live_field", live_texture)
	material.set_shader_parameter("obstacle_mode", mode)
	material.set_shader_parameter("obstacle_strength", strength)
	material.set_shader_parameter("obstacle_time", current_time)
