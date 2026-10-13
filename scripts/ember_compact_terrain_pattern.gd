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
## Optional full-colour project texture. Existing 16x16 artwork remains editable
## and supplies the fallback when no texture is selected.
@export var albedo_texture: Texture2D
## Optional side artwork. Empty keeps the original top artwork on every face.
@export var side_pixels := PackedByteArray()
## Optional independent three-level artwork. Empty retains legacy colour heights.
@export var relief_pixels := PackedByteArray()
@export var side_relief_pixels := PackedByteArray()
@export var roughness_pixels := PackedByteArray()
@export var side_roughness_pixels := PackedByteArray()
@export_range(0.125,16.0,0.025) var pattern_size_m := 4.0
@export_range(0.0,0.5,0.01) var roughness_variation := 0.0
## Surface finish is independent of the painted tones and the semantic role.
## Zero values preserve the original fully matte terrain appearance.
@export_range(0.0, 1.0, 0.01) var gloss := 0.0
@export_range(0.0, 1.0, 0.01) var sheen := 0.0
@export_range(0.0, 0.3, 0.01) var pixel_relief := 0.0
## Independent light detail, in metres; zero strength keeps authored legacy finish.
@export_range(0.0, 0.3, 0.01) var micro_relief := 0.0
@export_range(0.03, 1.0, 0.01) var micro_size_m := 0.09
@export_range(0.0, 0.5, 0.01) var micro_roughness := 0.0

## Light response belongs to this variant, separate from artwork colours.
## Relative linear tints may exceed one. Legacy materials remain opt-out.
@export_group("Grass light response")
@export var grass_light_enabled := false
@export_range(0.52,0.85,0.01) var grass_light_low := 0.64
@export_range(0.0,1.0,0.01) var grass_light_tint_strength := 1.0
@export var grass_light_cool := Color(0.96,1.0,1.04)
@export var grass_light_warm := Color(1.075,1.0,0.94)
@export var grass_light_shadow_color := Color(0.62,0.90,1.02)
@export_range(0.0,0.15,0.005) var grass_light_shadow_fill := 0.07
@export_group("")

func suggested_grass_light_tones() -> Dictionary:
	# Relative to the authored base pigment. Explicit suggestion, not image
	# analysis and never automatically applied when base_color changes.
	return {"grass_light_cool":Color(0.96,1.0,1.04),"grass_light_warm":Color(1.075,1.0,0.94),"grass_light_shadow_color":Color(0.62,0.90,1.02)}


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if albedo_texture != null and (albedo_texture.get_width()<=0 or albedo_texture.get_height()<=0 or albedo_texture.get_width()>4096 or albedo_texture.get_height()>4096):
		errors.append("terrain PNG texture must be within 1..4096 pixels per side")
	if role_id not in ROLE_IDS:
		errors.append("unknown compact terrain pattern role")
	if grass_light_enabled and role_id != "grass": errors.append("grass light response requires grass role")
	for spec in [["grass_light_low",0.52,0.85],["grass_light_tint_strength",0.0,1.0],["grass_light_shadow_fill",0.0,0.15]]:
		var value: float=get(spec[0])
		if not is_finite(value) or value < spec[1] or value > spec[2]:errors.append(str(spec[0])+" outside range")
	for field in ["grass_light_cool","grass_light_warm","grass_light_shadow_color"]:
		var tint: Color=get(field)
		if not Vector3(tint.r,tint.g,tint.b).is_finite() or not is_finite(tint.a) or not is_equal_approx(tint.a,1.0) or minf(tint.r,minf(tint.g,tint.b))<0.0 or maxf(tint.r,maxf(tint.g,tint.b))>2.0:
			errors.append(field+" must be an opaque relative tint within 0..2")
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
	for field in ["relief_pixels","side_relief_pixels","roughness_pixels","side_roughness_pixels"]:
		var artwork: PackedByteArray = get(field)
		if not artwork.is_empty():
			if artwork.size()!=SIZE*SIZE: errors.append(field+" must contain 16x16 levels")
			else:
				for value in artwork:
					if value>2: errors.append(field+" has invalid level"); break
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
	for spec in [["micro_relief",0.0,0.3],["micro_size_m",0.03,1.0],["micro_roughness",0.0,0.5],["pattern_size_m",0.125,16.0],["roughness_variation",0.0,0.5]]:
		var value: float = get(spec[0])
		if not is_finite(value) or value < spec[1] or value > spec[2]:
			errors.append("compact terrain " + str(spec[0]) + " outside range")
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


func surface_pixels(channel: String, side := false) -> PackedByteArray:
	if channel=="color": return face_pixels(side)
	var top: PackedByteArray=relief_pixels if channel=="relief" else roughness_pixels
	var sides: PackedByteArray=side_relief_pixels if channel=="relief" else side_roughness_pixels
	if side and not sides.is_empty(): return sides
	if not top.is_empty(): return top
	if channel=="relief": return face_pixels(side)
	var neutral:=PackedByteArray(); neutral.resize(SIZE*SIZE); return neutral

func surface_image(channel: String, side := false) -> Image:
	if channel=="color": return to_image(side)
	if not validation_errors().is_empty(): return null
	var image:=Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	var artwork:=surface_pixels(channel,side)
	for y in SIZE:
		for x in SIZE:
			var level: float=[0.5,1.0,0.0][artwork[x+y*SIZE]]
			image.set_pixel(x,y,Color(level,level,level,1.0))
	return image
