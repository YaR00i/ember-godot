extends SceneTree
## Builds exact pixel-grid art drafts for comparing terrain texture resolution.

const OUTPUT := "res://assets/terrain_textures/drafts"
const PALETTES := {
	"grass": ["#83a953", "#90b65e", "#759a4c", "#9ebe68", "#6f914b"],
	"soil": ["#896847", "#96734d", "#795d42", "#a38155", "#6d573f"],
	"sand": ["#dec891", "#e8d49f", "#ceb87f", "#f0dbac", "#bea674"],
	"stone": ["#899298", "#9aa1a2", "#79868b", "#aaa69d", "#718087"],
}
const PATTERNS := {
	"grass": ["00011000", "00111000", "00030020", "00000220", "20000000", "22000300", "02003300", "00003000"],
	"soil":  ["00011000", "00111000", "00010020", "00000220", "30000000", "33000000", "03000200", "00002200"],
	"sand":  ["00010000", "00000000", "00000200", "00000000", "20000000", "00000030", "00000000", "00030000"],
	"stone": ["00011000", "00111000", "00110020", "00000220", "30000220", "33000000", "33000000", "00000000"],
}


func _initialize() -> void:
	var swatches := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	for size in [8, 16]:
		var directory := "%s/%d" % [OUTPUT, size]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		for role_index in 4:
			var role: String = ["soil", "grass", "sand", "stone"][role_index]
			var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
			var palette: Array = PALETTES[role]
			var pattern: Array = PATTERNS[role]
			for y in size:
				for x in size:
					var coarse_x: int = x * 8 / size
					var coarse_y: int = y * 8 / size
					var index := int(pattern[coarse_y].substr(coarse_x, 1))
					# The 16px version keeps the broad 8px shapes, then introduces
					# smaller square facets. Sand stays sparse like the art reference.
					if size == 16 and role != "sand":
						for facet in [Vector2i(2, 1), Vector2i(11, 2), Vector2i(8, 6), Vector2i(3, 9), Vector2i(13, 11), Vector2i(7, 14)]:
							if x >= facet.x and x < facet.x + 2 and y >= facet.y and y < facet.y + 2:
								index = 2 if (facet.x + facet.y) % 2 == 0 else 1
					elif size == 16 and (x * 7 + y * 11) % 79 == 0:
						index = 2
					image.set_pixel(x, y, Color.html(palette[index]))
			var path := "%s/%s.png" % [directory, role]
			var error := image.save_png(path)
			if error != OK:
				printerr("FAIL: ", path, " ", error_string(error))
				quit(1)
				return
			print("SAVED ", path, " ", size, "x", size)
			var enlarged := image.duplicate()
			enlarged.resize(128, 128, Image.INTERPOLATE_NEAREST)
			swatches.blit_rect(enlarged, Rect2i(0, 0, 128, 128), Vector2i(role_index * 128, 0 if size == 8 else 128))
	var swatch_path := "res://docs/art/references/compact-terrain-8-vs-16-swatches-20260929.png"
	if swatches.save_png(swatch_path) != OK:
		printerr("FAIL: swatches")
		quit(1)
		return
	quit()
