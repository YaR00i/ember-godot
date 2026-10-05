@tool
class_name EmberCompactTerrainPattern
extends Resource
## Shared 16x16 material artwork. Each pixel selects base, light or shadow.

const SIZE := 16
const ROLE_IDS := ["soil", "grass", "sand", "stone"]

@export var role_id := ""
@export var base_color := Color.WHITE
@export var light_color := Color.WHITE
@export var shadow_color := Color.WHITE
@export var pixels := PackedByteArray()
## Optional side artwork. Empty keeps the original top artwork on every face.
@export var side_pixels := PackedByteArray()
## Surface finish is independent of the painted tones and the semantic role.
## Zero values preserve the original fully matte terrain appearance.
@export_range(0.0, 1.0, 0.01) var gloss := 0.0
@export_range(0.0, 1.0, 0.01) var sheen := 0.0
@export_range(0.0, 0.3, 0.01) var pixel_relief := 0.0


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if role_id not in ROLE_IDS:
		errors.append("unknown compact terrain pattern role")
	if pixels.size() != SIZE * SIZE:
		errors.append("compact terrain pattern must contain 16x16 pixels")
	else:
		for value in pixels:
			if value > 2:
				errors.append("compact terrain pattern has an invalid tone index")
				break
	if not side_pixels.is_empty():
		if side_pixels.size() != SIZE * SIZE:
			errors.append("compact terrain side pattern must contain 16x16 pixels")
		else:
			for value in side_pixels:
				if value > 2:
					errors.append("compact terrain side pattern has an invalid tone index")
					break
	for color in [base_color, light_color, shadow_color]:
		if not is_equal_approx(color.a, 1.0):
			errors.append("compact terrain pattern tones must be opaque")
			break
	if not is_finite(gloss) or gloss < 0.0 or gloss > 1.0:
		errors.append("compact terrain gloss must be within 0..1")
	if not is_finite(sheen) or sheen < 0.0 or sheen > 1.0:
		errors.append("compact terrain sheen must be within 0..1")
	if not is_finite(pixel_relief) or pixel_relief < 0.0 or pixel_relief > 0.3:
		errors.append("compact terrain pixel relief must be within 0..0.3")
	return errors


func face_pixels(side := false) -> PackedByteArray:
	return side_pixels if side and not side_pixels.is_empty() else pixels


func to_image(side := false) -> Image:
	if not validation_errors().is_empty():
		return null
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var tones := [base_color, light_color, shadow_color]
	var artwork := face_pixels(side)
	for y in SIZE:
		for x in SIZE:
			image.set_pixel(x, y, tones[artwork[x + y * SIZE]])
	return image
