extends RefCounted
## Pure derivation of an optical height map from the painted colour texture. Colour, height and
## normals therefore describe the same features: dark patches sink, light patches rise, and where
## the painted tone changes abruptly the height jumps; elsewhere it stays soft. The result is derived
## data (periodic, 8 bit, mipmapped), never authored or saved; the albedo texture stays the source.
const CONTRACT := "height-from-paint-v1"
const MAX_SIZE := 1024
static var _cache := {}


## softness: blur radius in texels for the soft base (0.5..6). sharpness 0..1: share of the strongest
## painted edges that become steps (0 = fully soft, ~0.1 = a few deliberate folds, ~0.8 = crumpled).
static func bake(texture: Image, softness := 2.5, sharpness := 0.1) -> Image:
	var image := texture.duplicate() as Image
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if maxi(image.get_width(), image.get_height()) > MAX_SIZE:
		var scale := float(MAX_SIZE) / maxi(image.get_width(), image.get_height())
		image.resize(int(image.get_width() * scale), int(image.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	var width := image.get_width(); var height := image.get_height()
	var count := width * height
	var luminance := PackedFloat32Array(); luminance.resize(count)
	var mean := 0.0
	for y in height:
		for x in width:
			var c := image.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			luminance[x + width * y] = l; mean += l
	mean /= count
	var variance := 0.0
	for l in luminance: variance += (l - mean) * (l - mean)
	var deviation := maxf(sqrt(variance / count), 1.0e-5)
	for i in count: luminance[i] = (luminance[i] - mean) / deviation
	var scale_px := float(width) / 256.0  # radii are given for a 256 px tile
	var soft := _blur(luminance, width, height, softness * scale_px)
	var edges := _blur(luminance, width, height, 1.0 * scale_px)
	var local_mean := _blur(luminance, width, height, 5.0 * scale_px)
	var strength := PackedFloat32Array(); strength.resize(count)
	var sorted: Array[float] = []
	for y in height:
		for x in width:
			var gx := edges[posmod(x + 1, width) + width * y] - edges[posmod(x - 1, width) + width * y]
			var gy := edges[x + width * posmod(y + 1, height)] - edges[x + width * posmod(y - 1, height)]
			var g := sqrt(gx * gx + gy * gy)
			strength[x + width * y] = g; sorted.append(g)
	sorted.sort()
	var percentile := clampf(0.995 - 0.10 * sharpness, 0.5, 0.999)
	var reference := maxf(sorted[mini(int(count * percentile), count - 1)], 1.0e-6)
	var result := Image.create(width, height, true, Image.FORMAT_R8)
	for y in height:
		for x in width:
			var i := x + width * y
			var edge := clampf(strength[i] / reference, 0.0, 1.0)
			var k := 0.8 + 6.0 * edge
			var d := (soft[i] - local_mean[i]) * 1.2
			result.set_pixel(x, y, Color(clampf(0.5 + 0.5 * tanh(k * d), 0.0, 1.0), 0.0, 0.0))
	return result


static func texture_for(albedo: Texture2D, softness: float, sharpness: float) -> ImageTexture:
	if albedo == null: return null
	var key := "%d|%.3f|%.3f" % [albedo.get_instance_id(), softness, sharpness]
	if _cache.has(key): return _cache[key]
	var source := albedo.get_image()
	if source == null: return null
	var image := bake(source, softness, sharpness)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func clear_cache() -> void:
	_cache.clear()


static func _blur(source: PackedFloat32Array, width: int, height: int, sigma: float) -> PackedFloat32Array:
	sigma = maxf(sigma, 0.3)
	var radius := int(ceil(sigma * 2.5))
	var kernel := PackedFloat32Array(); var sum := 0.0
	for i in range(-radius, radius + 1):
		var w := exp(-0.5 * float(i * i) / (sigma * sigma)); kernel.append(w); sum += w
	for i in kernel.size(): kernel[i] /= sum
	var pass_x := PackedFloat32Array(); pass_x.resize(source.size())
	for y in height:
		for x in width:
			var a := 0.0
			for i in range(-radius, radius + 1): a += source[posmod(x + i, width) + width * y] * kernel[i + radius]
			pass_x[x + width * y] = a
	var out := PackedFloat32Array(); out.resize(source.size())
	for y in height:
		for x in width:
			var a := 0.0
			for i in range(-radius, radius + 1): a += pass_x[x + width * posmod(y + i, height)] * kernel[i + radius]
			out[x + width * y] = a
	return out
