extends RefCounted
## Derived alpha-contour recipe. No artwork edits, persistent Source or RGB bake.
## Only separated leaves are supported; connected clusters need an author mask.
static func build(source: Image) -> Dictionary:
	var image:=source.duplicate() as Image
	image.resize(512,512,Image.INTERPOLATE_BILINEAR)
	var size:=image.get_width();var visited:=PackedByteArray();visited.resize(size*size)
	# R: rhombus, G: triangle, B: rectangle aligned to each leaf's own axes.
	var field:=Image.create(size,size,false,Image.FORMAT_RGBF);field.fill(Color(3,3,3))
	var components:=0;var treated:=0
	for y in size:
		for x in size:
			var start:=y*size+x
			if visited[start]!=0 or image.get_pixel(x,y).a<0.4:continue
			var queue:=PackedInt32Array([start]);visited[start]=1;var cursor:=0
			while cursor<queue.size():
				var at:=queue[cursor];cursor+=1
				var px:=at%size;var py:=at/size
				for delta: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var p:=Vector2i(px,py)+delta
					if p.x<0 or p.y<0 or p.x>=size or p.y>=size:continue
					var next:=p.y*size+p.x
					if visited[next]==0 and image.get_pixelv(p).a>=0.4:
						visited[next]=1;queue.append(next)
			if queue.size()<20:continue
			components+=1
			var centre:=Vector2.ZERO
			for at in queue:centre+=Vector2(at%size,at/size)
			centre/=queue.size()
			var xx:=0.0;var yy:=0.0;var xy:=0.0
			for at in queue:
				var d:=Vector2(at%size,at/size)-centre
				xx+=d.x*d.x;yy+=d.y*d.y;xy+=d.x*d.y
			var axis:=Vector2.from_angle(0.5*atan2(2.0*xy,xx-yy));var side:=Vector2(-axis.y,axis.x)
			var low:=Vector2(INF,INF);var high:=-low
			for at in queue:
				var d:=Vector2(at%size,at/size)-centre;var p:=Vector2(d.dot(axis),d.dot(side))
				low=low.min(p);high=high.max(p)
			var half:=(high-low)*0.5+Vector2.ONE*0.5
			var middle:=(low+high)*0.5
			centre+=axis*middle.x+side*middle.y
			# Leave stems and suspiciously merged clusters alone instead of turning
			# an entire branch into one rhombus. This gate is deliberately conservative.
			var fill:=float(queue.size())/(half.x*half.y*4.0)
			var eligible:=half.x/half.y<5.0 and fill>0.5
			if eligible:treated+=1
			for at in queue:
				# Two texels of padding keep the high-resolution alpha edge covered.
				for dy in range(-2,3):
					for dx in range(-2,3):
						var p:=Vector2i(at%size+dx,at/size+dy)
						if p.x<0 or p.y<0 or p.x>=size or p.y>=size:continue
						var d:=Vector2(p)-centre
						var u:=d.dot(axis)/half.x;var v:=d.dot(side)/half.y
						var metric:=Vector3(absf(u)+absf(v),maxf(-u,u+2.0*absf(v)),maxf(absf(u),absf(v))/0.68) if eligible else Vector3.ZERO
						var old:=field.get_pixelv(p)
						field.set_pixelv(p,Color(minf(metric.x,old.r),minf(metric.y,old.g),minf(metric.z,old.b)))
	field.generate_mipmaps()
	return {"image":field,"components":components,"treated":treated}
