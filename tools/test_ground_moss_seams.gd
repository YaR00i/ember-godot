extends SceneTree
## Checks the actual decal textures at a shared tile edge, with uneven paint and an erased neighbor.
const Moss := preload("res://scripts/ember_object_moss.gd")
const Detail := preload("res://scripts/ember_detail_scatter.gd")

func _initialize() -> void:
	var left := {}
	var right := {}
	var east := {}
	var west := {}
	for y in Detail.CELLS:
		for x in Detail.CELLS:
			left[Vector2i(x, y)] = 40 + 4 * y
			right[Vector2i(x, y)] = 128 - 3 * y
		for x in Moss.GROUND_HALO:
			east[Vector2i(Detail.CELLS + x, y)] = right[Vector2i(x, y)]
			west[Vector2i(-1 - x, y)] = left[Vector2i(Detail.CELLS - 1 - x, y)]
	var a := Moss.ground_texture(left, east).get_image()
	var b := Moss.ground_texture(right, west).get_image()
	var max_error := 0.0
	var colors_match := true
	var row := Moss.GROUND_APRON + Moss.GROUND_TEXTURE_SIZE / 2
	var pixels_per_cell := float(Moss.GROUND_TEXTURE_SIZE) / Detail.CELLS
	var sample_y := (float(row - Moss.GROUND_APRON) + 0.5) / pixels_per_cell - 0.5
	for x in 2 * Moss.GROUND_APRON:
		var first := a.get_pixel(Moss.GROUND_TEXTURE_SIZE + x, row)
		var second := b.get_pixel(x, row)
		var t := clampf(0.5 + (float(x) + 0.5 - Moss.GROUND_APRON) / pixels_per_cell, 0.0, 1.0)
		var expected := lerpf(40.0 + 4.0 * sample_y, 128.0 - 3.0 * sample_y, t) / 200.0
		var composed := 1.0 - (1.0 - first.a) * (1.0 - second.a)
		max_error = maxf(max_error, absf(expected - composed))
		colors_match = colors_match and Color(first, 1.0) == Color(second, 1.0)
	var erased := Moss.ground_texture(left).get_image()
	var edge := erased.get_width() - 1
	var full := {}
	var full_halo := {}
	for y in Detail.CELLS:
		for x in Detail.CELLS:
			full[Vector2i(x, y)] = 200
		for x in Moss.GROUND_HALO:
			full_halo[Vector2i(Detail.CELLS + x, y)] = 200
	var saturated := Moss.ground_texture(full, full_halo).get_image()
	var soft_erase := erased.get_pixel(edge, row).a < 0.03 and erased.get_pixel(edge - 2 * Moss.GROUND_APRON - 1, row).a > 0.3
	var clear_border := saturated.get_pixel(edge, row).a == 0.0
	var ok := colors_match and max_error < 0.01 and soft_erase and clear_border
	print("GROUND_MOSS_SEAMS colors=", colors_match, " composited_error=", max_error, " pass=", ok)
	quit(0 if ok else 1)
