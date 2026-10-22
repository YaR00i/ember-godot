extends RefCounted
## LAB optical height paired to accepted pigment. No physical Source mutation.
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")

static func height_image(master: Image) -> Image:
	var broad:=master.duplicate() as Image
	if broad.is_compressed():broad.decompress()
	broad.clear_mipmaps()
	# Suppress small paint grain; retain the large worn forms and creases only.
	broad.resize(64,64,Image.INTERPOLATE_LANCZOS)
	broad.resize(master.get_width(),master.get_height(),Image.INTERPOLATE_BILINEAR)
	var values:=PackedFloat32Array()
	for y in broad.get_height():
		for x in broad.get_width():
			var c:=broad.get_pixel(x,y);values.append(c.r*0.2126+c.g*0.7152+c.b*0.0722)
	var sorted:=values.duplicate();sorted.sort()
	var low:=sorted[int(sorted.size()*0.08)];var high:=sorted[int(sorted.size()*0.92)]
	var result:=Image.create(master.get_width(),master.get_height(),false,Image.FORMAT_R8)
	for y in result.get_height():
		for x in result.get_width():
			var h:=0.5
			if high-low>0.001:
				var tone:=clampf((values[y*result.get_width()+x]-low)/(high-low),0.0,1.0)
				h=lerpf(0.28,0.72,smoothstep(0.08,0.92,tone))
			result.set_pixel(x,y,Color(h,0,0,1))
	result.generate_mipmaps();return result

static func heights(master: Image) -> Array[Image]:
	var height:=height_image(master)
	return [height,height,TerrainLook.pixel_image(height,8)]

static func coverage(source_resource,slot:=4) -> Image:
	# Exact same corner weights and fine16 grid as the existing terrain mesh.
	var result:=Image.create(source_resource.width+1,source_resource.depth+1,false,Image.FORMAT_RF)
	var cache: Dictionary={}
	for z in source_resource.depth+1:
		for x in source_resource.width+1:
			var weights:=Smooth.material_weights(source_resource,Vector2i(x,z),cache)
			result.set_pixel(x,z,Color(float(weights.get(slot,0.0)),0,0,1))
	return result
