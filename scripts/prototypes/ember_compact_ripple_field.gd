@tool
extends RefCounted
## Derived, periodic optical field. No authored terrain or physical wave state.
const SIZE := 128
const PERIOD := 12
static var _texture: ImageTexture

static func texture() -> ImageTexture:
	if _texture != null: return _texture
	return install(build_image())


static func install(image: Image) -> ImageTexture:
	if _texture == null: _texture = ImageTexture.create_from_image(image)
	return _texture


static func build_image() -> Image:
	var seeds: Array[Vector3] = []
	var random := RandomNumberGenerator.new()
	random.seed = 417219
	for z in PERIOD:
		for x in PERIOD:
			seeds.append(Vector3(x + random.randf_range(0.08, 0.92), z + random.randf_range(0.08, 0.92), random.randf_range(-0.16, 0.16)))
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBAH)
	for z in SIZE:
		for x in SIZE:
			var point := (Vector2(x, z) + Vector2.ONE * 0.5) * (float(PERIOD) / SIZE)
			var cell := Vector2i(point.floor())
			var gradient := Vector2.ZERO
			var weight := 0.0
			# A compact support window makes the periodic field and its slope
			# continuous when the integer search neighbourhood changes.
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var neighbour := cell + Vector2i(dx, dz)
					var seed := seeds[posmod(neighbour.x, PERIOD) + posmod(neighbour.y, PERIOD) * PERIOD]
					var delta := point - Vector2(seed.x + neighbour.x - posmod(neighbour.x, PERIOD), seed.y + neighbour.y - posmod(neighbour.y, PERIOD))
					var distance := delta.length_squared()
					if distance >= 1.44: continue
					var support := maxf(1.0 - distance / 1.44, 0.0)
					var contribution := exp(-(distance + seed.z) * 5.0) * support * support * support
					gradient += delta * contribution
					weight += contribution
			gradient /= maxf(weight, 0.00001)
			image.set_pixel(x, z, Color(gradient.x, gradient.y, 0.0, 1.0))
	image.generate_mipmaps()
	return image
