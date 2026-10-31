@tool
extends RefCounted
## One immutable local volume calculation. Only Canvas applies/publishes its delta.
## A summed volume gives a box-filtered occupancy in O(1) per sample, independent
## of kernel size. Labels remain discrete; newly filled cells inherit a donor.
var values:PackedByteArray
var parts:PackedInt32Array
var size:Vector3i
var segments:Array[Dictionary]=[]
var radius:=4
var kernel:=2
var cancelled:=false
var task_id:=-1
var changes:Dictionary={}
var owners:Dictionary={}
var elapsed_usec:=0
var sampled_cells:=0

func _index(p:Vector3i)->int:return p.x+size.x*(p.z+size.z*p.y)
func _filled(p:Vector3i)->bool:
	return p.x>=0 and p.y>=0 and p.z>=0 and p.x<size.x and p.y<size.y and p.z<size.z and values[_index(p)]>0
func _distance_squared(point:Vector3)->float:
	var nearest:=INF
	for segment in segments:
		var start:Vector3=segment.from;var delta:Vector3=Vector3(segment.to)-start
		var t:=clampf((point-start).dot(delta)/delta.length_squared(),0,1) if delta.length_squared()>0 else 0.0
		nearest=minf(nearest,point.distance_squared_to(start+delta*t))
	return nearest
func _donor(p:Vector3i)->int:
	# Most additions fill concave edges and have a donor one cell away. Compare
	# all six directions at each distance; never invent or average material IDs.
	for distance in range(1,kernel*2+2):
		for direction in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
			var candidate:Vector3i=p+direction*distance
			if _filled(candidate):return _index(candidate)
	return -1
func run()->void:
	var started:=Time.get_ticks_usec()
	if segments.is_empty() or values.size()!=size.x*size.y*size.z:return
	radius=clampi(radius,1,256);kernel=clampi(kernel,1,8)
	var low:=size;var high:=Vector3i.ZERO
	for segment in segments:
		var a:Vector3i=segment.from;var b:Vector3i=segment.to
		low=low.min(a.min(b)-Vector3i.ONE*radius)
		high=high.max(a.max(b)+Vector3i.ONE*(radius+1))
	low=low.max(Vector3i.ZERO);high=high.min(size)
	var origin:Vector3i=(low-Vector3i.ONE*kernel).max(Vector3i.ZERO)
	var end:Vector3i=(high+Vector3i.ONE*kernel).min(size)
	var extent:=end-origin
	var pitch:=Vector3i(extent.x+1,extent.y+1,extent.z+1)
	var plane:=pitch.x*pitch.z
	var integral:=PackedInt32Array();integral.resize(plane*pitch.y)
	# Prefix layout matches the existing Source (x, z, y). All reads below are
	# from pointer-down data, so neither threading nor input packet order feeds
	# half-written samples into the filter.
	for y in range(1,pitch.y):
		if cancelled:return
		for z in range(1,pitch.z):
			if cancelled:return
			var row:=0
			for x in range(1,pitch.x):
				var at:=x+pitch.x*z+plane*y
				row+=1 if values[_index(origin+Vector3i(x-1,y-1,z-1))]>0 else 0
				integral[at]=row+integral[at-pitch.x]+integral[at-plane]-integral[at-plane-pitch.x]
	var denominator:=float((kernel*2+1)*(kernel*2+1)*(kernel*2+1))
	var radius_squared:=float(radius*radius)
	for y in range(low.y,high.y):
		if cancelled:return
		for z in range(low.z,high.z):
			if cancelled:return
			for x in range(low.x,high.x):
				var point:=Vector3i(x,y,z)
				var distance:=_distance_squared(Vector3(point))
				if distance>=radius_squared:continue
				var lo:Vector3i=(point-Vector3i.ONE*kernel-origin).max(Vector3i.ZERO)
				var hi:Vector3i=(point+Vector3i.ONE*(kernel+1)-origin).min(extent)
				var ax:=lo.x;var az:=lo.z*pitch.x;var ay:=lo.y*plane
				var bx:=hi.x;var bz:=hi.z*pitch.x;var by:=hi.y*plane
				var count:=integral[bx+bz+by]-integral[ax+bz+by]-integral[bx+az+by]-integral[bx+bz+ay]+integral[ax+az+by]+integral[ax+bz+ay]+integral[bx+az+ay]-integral[ax+az+ay]
				var index:=_index(point);var before:=int(values[index])
				var weight:=1.0-smoothstep(0.25,1.0,distance/radius_squared)
				var occupancy:=lerpf(1.0 if before>0 else 0.0,count/denominator,weight)
				var filled:=occupancy>=0.5
				sampled_cells+=1
				if filled==(before>0):continue
				var after:=0
				if filled:
					var donor:=_donor(point)
					if donor<0:continue
					after=int(values[donor])
					if not parts.is_empty():owners[index]=int(parts[donor])
				changes[index]={"before":before,"after":after}
	elapsed_usec=Time.get_ticks_usec()-started
