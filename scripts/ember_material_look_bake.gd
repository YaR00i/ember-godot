extends RefCounted
## Pure derived artwork math. Pattern/Surface Canvas remain the authoring owners.
## This pilot preserves the supplied height image exactly. Relief edges protect
## colour from flattening, so a new colour facet cannot erase a deep groove.
const VERSION:=1

static func calm_variant(source: Image, cells:=12, contrast:=0.35) -> Image:
	# Derived low-detail pigment. Keep the source and relief owner untouched.
	var result:=source.duplicate() as Image
	if result.is_compressed():result.decompress()
	result.clear_mipmaps();result.convert(Image.FORMAT_RGBA8)
	var size:=result.get_size();var mean:=Vector3.ZERO;var samples:=0
	for y in size.y:
		for x in size.x:
			var c:=result.get_pixel(x,y)
			if c.a>0.4:mean+=Vector3(c.r,c.g,c.b);samples+=1
	mean/=maxi(samples,1)
	result.resize(cells,cells,Image.INTERPOLATE_LANCZOS)
	result.resize(size.x,size.y,Image.INTERPOLATE_BILINEAR)
	for y in size.y:
		for x in size.x:
			var c:=result.get_pixel(x,y);var tone:=mean.lerp(Vector3(c.r,c.g,c.b),contrast)
			result.set_pixel(x,y,Color(tone.x,tone.y,tone.z,c.a))
	result.generate_mipmaps()
	return result

static func image_variant(source: Image, look: int, recipe: Dictionary, height: Image=null) -> Dictionary:
	assert(look in [0,1,2])
	var started:=Time.get_ticks_usec()
	var result:=source.duplicate() as Image
	if result.is_compressed():result.decompress()
	result.convert(Image.FORMAT_RGBA8)
	if look==0:return {"image":result,"regions":0,"build_ms":0.0}
	var n:=int(recipe.get("resolution",256))
	result.resize(n,n,Image.INTERPOLATE_BILINEAR)
	var original:=result.duplicate() as Image
	var relief: Image=null
	if height!=null:
		relief=height.duplicate();relief.resize(n,n,Image.INTERPOLATE_BILINEAR)
	var step:=int(recipe.get("cell",16));var count:=0
	for y in range(0,n,step):
		for x in range(0,n,step):
			count+=_region(original,result,relief,Rect2i(x,y,mini(step,n-x),mini(step,n-y)),look,recipe)
	result.generate_mipmaps()
	return {"image":result,"regions":count,"build_ms":(Time.get_ticks_usec()-started)/1000.0}

static func _region(source: Image,target: Image,height: Image,box: Rect2i,look: int,recipe: Dictionary) -> int:
	var lo:=Vector3(INF,INF,INF);var hi:=-lo
	for p: Vector2i in [box.position,box.position+Vector2i(box.size.x-1,0),box.end-Vector2i.ONE,box.position+Vector2i(0,box.size.y-1),box.get_center()]:
		var c:=source.get_pixelv(p)
		if c.a<0.4:continue
		lo=lo.min(Vector3(c.r,c.g,c.b));hi=hi.max(Vector3(c.r,c.g,c.b))
	# Colour-aware subdivision: featureless areas stay broad, detailed borders
	# get smaller triangles. No randomly coloured tessellation over the picture.
	if look==1 and box.size.x>int(recipe.get("min_cell",4)) and lo.x!=INF and (hi-lo).length()>float(recipe.get("tolerance",0.08)):
		var half:=box.size/2;var regions:=0
		for dy in 2:
			for dx in 2:regions+=_region(source,target,height,Rect2i(box.position+Vector2i(dx,dy)*half,half),look,recipe)
		return regions
	var sums: Array[Vector3]=[Vector3.ZERO,Vector3.ZERO];var counts: Array[int]=[0,0]
	var diagonal:=posmod(box.position.x/box.size.x+box.position.y/box.size.y+int(recipe.get("seed",0)),2)
	for y in box.size.y:
		for x in box.size.x:
			var c:=source.get_pixelv(box.position+Vector2i(x,y))
			if c.a<0.4:continue
			var side:=_side(x,y,box.size,diagonal) if look==1 else 0
			sums[side]+=Vector3(c.r,c.g,c.b);counts[side]+=1
	for i in 2:
		if counts[i]>0:sums[i]/=counts[i]
	for y in box.size.y:
		for x in box.size.x:
			var p:=box.position+Vector2i(x,y);var c:=source.get_pixelv(p)
			var side:=_side(x,y,box.size,diagonal) if look==1 else 0
			if counts[side]==0 or c.a<0.4:continue
			var strength:=float(recipe.get("strength",0.85))
			if recipe.get("periodic",false):
				var edge:=mini(mini(p.x,p.y),mini(source.get_width()-1-p.x,source.get_height()-1-p.y))
				strength*=smoothstep(0.0,3.0,float(edge))
			if height!=null:
				var n:=height.get_width();var h:=height.get_pixelv(p).r;var delta:=0.0
				for d: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var q:=p+d*2;q=Vector2i(posmod(q.x,n),posmod(q.y,n))
					delta=maxf(delta,absf(h-height.get_pixelv(q).r))
				strength*=1.0-smoothstep(0.015,0.07,delta)
			var colour:=Vector3(c.r,c.g,c.b).lerp(sums[side],strength)
			target.set_pixelv(p,Color(colour.x,colour.y,colour.z,c.a))
	return 2 if look==1 else 1

static func _side(x: int,y: int,size: Vector2i,diagonal: int) -> int:
	return int(x+y>=size.x) if diagonal==0 else int(x>=y)

static func grass_mesh(source: ArrayMesh, look: int, outline: PackedVector2Array, recipe: Dictionary={}) -> ArrayMesh:
	if look==0:return source
	var polygons: Array[PackedVector2Array]=[]
	if look==1:
		var reduced:=outline.duplicate()
		while reduced.size()>int(recipe.get("corners",9)):
			var smallest:=INF;var chosen:=-1
			for i in range(1,reduced.size()-1):
				if reduced[i].y>0.13:continue
				var area:=absf((reduced[i]-reduced[i-1]).cross(reduced[i+1]-reduced[i-1]))
				if area<smallest:smallest=area;chosen=i
			if chosen<0:break
			reduced.remove_at(chosen)
		polygons.append(reduced)
	else:
		# Rasterise the existing flat clump, merge each row into rectangles.
		# Pixel bands, not thousands of miniature solid cubes.
		var step:=float(recipe.get("pixel_m",0.015625))
		var top:=0.0
		for point in outline:top=maxf(top,point.y)
		var half_width:=ceili(0.13/step)
		for y in ceili(0.14/step):
			var begin:=-100
			for x in range(-half_width,half_width+1):
				var occupied:=x<half_width and Geometry2D.is_point_in_polygon(Vector2((x+0.5)*step,(y+0.5)*step),outline)
				# Large pixels retain thin blade tips with deterministic coverage.
				if recipe.get("coverage",false) and x<half_width:
					for offset in [Vector2(0.25,0.25),Vector2(0.75,0.25),Vector2(0.25,0.75),Vector2(0.75,0.75)]:
						occupied=occupied or Geometry2D.is_point_in_polygon((Vector2(x,y)+offset)*step,outline)
				if occupied and begin==-100:begin=x
				if not occupied and begin!=-100:
					var row_top:=minf((y+1)*step,top) if recipe.get("preserve_height",false) else (y+1)*step
					polygons.append(PackedVector2Array([Vector2(begin*step,y*step),Vector2(begin*step,row_top),Vector2(x*step,row_top),Vector2(x*step,y*step)]));begin=-100
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colours:=PackedColorArray();var uv:=PackedVector2Array();var uv2:=PackedVector2Array()
	for card in 2:
		var across:=Vector3(cos(card*1.45),0,sin(card*1.45))
		for polygon in polygons:
			var triangles:=Geometry2D.triangulate_polygon(polygon)
			for t in range(0,triangles.size(),3):
				for corner in [0,1,2,2,1,0]:
					var p:=polygon[triangles[t+corner]]
					vertices.append(across*p.x+Vector3.UP*p.y*(1.0 if card==0 else 0.82))
					normals.append((Vector3.UP+across*signf(p.x)*0.28).normalized())
					colours.append(Color(1,0,0,3.0/255.0));uv.append(Vector2(3,3)/255.0);uv2.append(Vector2(3.0/255.0,0))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh
