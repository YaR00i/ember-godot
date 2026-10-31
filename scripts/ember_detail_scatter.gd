@tool
extends RefCounted
## Shared coordinates for the painted detail layer; derived instances never become Source.
const CELL_M := 0.25
const PATCH_M := 4.0
const CELLS := 16
const CANDIDATES := 16
const MAX_DENSITY := 200.0
const MASK_MAGIC := 0x314d4445 # EDM1; the existing density dictionary, losslessly compressed.
const MASK_MAX_BYTES := 65536
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const LookBake=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")

class TerrainJob extends RefCounted:
	signal ready
	var input:Dictionary
	var result:Dictionary={}
	var elapsed_us:=0
	var collect_ranges:=false
	var cell_ranges:Dictionary={}
	var _mutex:=Mutex.new()
	var _cancelled:=false
	var _notified:=false # Main-thread signal delivery; worker only computes.
	func notify_ready()->void:
		if _notified:return
		_notified=true;ready.emit()
	func cancel()->void:
		_mutex.lock();_cancelled=true;_mutex.unlock()
	func cancelled()->bool:
		_mutex.lock();var value:=_cancelled;_mutex.unlock();return value
	func _index(cell:Vector2i)->int:
		if cell.x<0 or cell.y<0 or cell.x>=input.extent.x or cell.y>=input.extent.y or not input.bounds.has_point(cell):return -1
		var offset:Vector2i=cell-input.bounds.position
		return offset.x+offset.y*input.bounds.size.x
	func _height(local:Vector3,cell:Vector2i)->float:
		return Smooth.sample(input.fields[Vector2i(cell.x/64,cell.y/64)],Vector2(local.x,local.z))
	func _role(index:int)->String:
		var slot:int=input.tops[index]
		return input.roles[slot] if slot<input.roles.size() else ""
	func _footprint(center:Vector3,radius:float)->bool:
		for i in 8:
			var offset:=Vector2.from_angle(i*TAU/8.0)*radius
			var local:Vector3=input.projection_inverse*(center+Vector3(offset.x,0,offset.y))
			var cell:=Vector2i(floori(local.x),floori(local.z));var index:=_index(cell)
			if index<0 or input.heights[index]<=0 or _role(index)=="stone":return false
			var position:Vector3=input.projection*Vector3(local.x,_height(local,cell),local.z)
			if absf(position.y-center.y)>0.055*input.unit:return false
		return true
	func run()->void:
		var began:=Time.get_ticks_usec()
		var detailed:Array[Transform3D]=[];var low_poly:Array[Transform3D]=[];var voxel:Array[Transform3D]=[]
		var variants:Dictionary={0:detailed,1:low_poly,2:voxel}
		var ordered:Array=input.cells.keys();ordered.sort()
		for cell:Vector2i in ordered:
			if cancelled():return
			var begin:=detailed.size()
			var density:float=input.cells[cell]
			for candidate in CANDIDATES:
				var rng:=RandomNumberGenerator.new();rng.seed=hash([cell+input.absolute_cell,candidate,input.seed])
				if rng.randf()>=density*CELL_M*CELL_M/CANDIDATES:continue
				var offset:=Vector2(candidate%4+0.5,floori(candidate/4.0)+0.5)
				offset+=Vector2(rng.randf_range(-0.45,0.45),rng.randf_range(-0.45,0.45))*input.jitter
				var p:=Vector2(cell)*CELL_M+offset*CELL_M/4.0
				var point:Vector3=input.patch*Vector3(p.x*input.unit,0,p.y*input.unit)
				var local:Vector3=input.projection_inverse*point
				var column:=Vector2i(floori(local.x),floori(local.z));var index:=_index(column)
				if index<0 or input.heights[index]<=0 or _role(index) not in ["grass","soil"]:continue
				point=input.projection*Vector3(local.x,_height(local,column),local.z)
				var water:int=input.water[index]
				var water_position:Vector3=input.projection*Vector3(0,input.origin_y+water,0)
				if water>input.heights[index] and point.y<water_position.y:continue
				var size_random:float=rng.randf_range(1.0-input.variation,1.0+input.variation)*input.size
				var yaw:=rng.randf_range(-deg_to_rad(input.yaw),deg_to_rad(input.yaw))
				if not _footprint(point,0.035*input.unit*size_random):continue
				var shape_scale:=Vector3(1,1.6,1) if input.kind==0 else Vector3.ONE
				var basis:=Basis(Vector3.UP,yaw).scaled(shape_scale*size_random*input.unit)
				for variant in [0,1,2]:
					var placed:=point
					if variant>0:
						var target:Vector3=input.projection_inverse*point
						target.y=float(input.origin_y+input.heights[index]) if variant==2 else float(LookBake.plane(input.fields[Vector2i(column.x/64,column.y/64)],Vector2(target.x,target.z)).height)
						placed=input.projection*target
					variants[variant].append(input.patch_inverse*Transform3D(basis,placed))
			if collect_ranges:cell_ranges[cell]=Vector2i(begin,detailed.size()-begin)
		if cancelled():return
		result=variants;elapsed_us=Time.get_ticks_usec()-began

static func merge_cells(cells:Dictionary,worker:Dictionary,worker_ranges:Dictionary,foreground:Dictionary,foreground_ranges:Dictionary)->Dictionary:
	var detailed:Array[Transform3D]=[];var low_poly:Array[Transform3D]=[];var voxel:Array[Transform3D]=[]
	var result:Dictionary={0:detailed,1:low_poly,2:voxel}
	var ordered:=cells.keys();ordered.sort()
	for cell:Vector2i in ordered:
		var from_worker:=worker_ranges.has(cell)
		var source:Dictionary=worker if from_worker else foreground
		var span:Vector2i=worker_ranges[cell] if from_worker else foreground_ranges[cell]
		for look in 3:result[look].append_array(source[look].slice(span.x,span.x+span.y))
	return result

static func encode_mask(cells:Dictionary)->PackedByteArray:
	if cells.is_empty() or not validation_errors(cells).is_empty():return PackedByteArray()
	var ordered:Dictionary={};var keys:=cells.keys();keys.sort()
	for key in keys:ordered[key]=cells[key]
	var raw:=var_to_bytes(ordered)
	var result:=PackedByteArray();result.resize(8)
	result.encode_u32(0,MASK_MAGIC);result.encode_u32(4,raw.size())
	result.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD));return result

static func decode_mask(bytes:PackedByteArray)->Dictionary:
	if bytes.is_empty():return {"cells":{},"error":""}
	if bytes.size()<=8 or bytes.decode_u32(0)!=MASK_MAGIC:return {"error":"Неизвестный формат маски деталей."}
	var size:=bytes.decode_u32(4)
	if size<=0 or size>MASK_MAX_BYTES:return {"error":"Некорректный размер маски деталей."}
	var raw:=bytes.slice(8).decompress(size,FileAccess.COMPRESSION_ZSTD)
	if raw.size()!=size:return {"error":"Не удалось распаковать маску деталей."}
	var cells:Variant=bytes_to_var(raw) # Objects are never decoded.
	if not cells is Dictionary:return {"error":"Повреждены ячейки маски деталей."}
	var errors:=validation_errors(cells)
	return {"cells":cells,"error":""} if errors.is_empty() else {"error":errors[0]}

static func patch_address(point_m: Vector2) -> Vector2i:
	return Vector2i(floori(point_m.x / PATCH_M), floori(point_m.y / PATCH_M))

static func cell_address(point_m: Vector2) -> Vector2i:
	return Vector2i(floori(point_m.x / CELL_M), floori(point_m.y / CELL_M))

static func sample_seed(cell: Vector2i, candidate: int, seed_value: int) -> int:
	return hash([cell, candidate, seed_value])

static func sample_variant(cell: Vector2i, candidate: int, seed_value: int, count: int) -> int:
	return posmod(hash([cell,candidate,seed_value,0x51A7]),maxi(1,count))

static func validation_errors(cells: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if cells.size() > CELLS * CELLS: errors.append("Слишком большая плитка деталей.")
	for cell in cells:
		if not cell is Vector2i or cell.x < 0 or cell.y < 0 or cell.x >= CELLS or cell.y >= CELLS:
			errors.append("Некорректная ячейка деталей."); continue
		if not (cells[cell] is float or cells[cell] is int) or not is_finite(float(cells[cell])) or cells[cell] < 0 or cells[cell] > MAX_DENSITY:
			errors.append("Плотность деталей должна быть 0–200 на м².")
	return errors
