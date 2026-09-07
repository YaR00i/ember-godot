@tool
extends RefCounted
## Pure palette edits. Index 0 is empty terrain / automatic water tint.
## No duplicate palette owner and no material-channel changes.

static func plan(resource: EmberVoxelModelResource, operation: Dictionary) -> Dictionary:
	if resource == null or resource.palette.size() < 2:
		return {"error": "Палитра не загружена"}
	var palette := resource.palette.duplicate()
	var index := int(operation.get("index", -1))
	var kind := str(operation.get("kind", ""))
	if kind == "add":
		if palette.size() >= 256:
			return {"error": "В палитре уже 255 цветов. Замените или объедините существующие."}
		palette.append(_opaque(operation.get("color", Color.WHITE)))
		return {"label": "Добавить цвет", "selected": palette.size() - 1, "properties": {&"palette": palette}}
	if index < 1 or index >= palette.size():
		return {"error": "Нулевой цвет зарезервирован; выберите существующий цвет"}
	if kind == "set":
		palette[index] = _opaque(operation.get("color", palette[index]))
		return {"label": "Изменить цвет всей модели", "selected": index, "properties": {&"palette": palette}}
	if kind == "ramp":
		var ramp := operation.get("colors", PackedColorArray()) as PackedColorArray
		if ramp.size() not in [3, 5, 7] or ramp.size() % 2 == 0:
			return {"error": "Рамп должен содержать 3, 5 или 7 оттенков"}
		if palette.size() + ramp.size() - 1 > 256:
			return {"error": "Для рампа не хватает свободных мест в палитре"}
		var center := ramp.size() / 2
		ramp[center] = palette[index] # Existing references must keep their exact color.
		var next_palette := PackedColorArray()
		for palette_index in palette.size():
			if palette_index == index:
				for color in ramp:
					next_palette.append(_opaque(color))
			else:
				next_palette.append(palette[palette_index])
		var voxels := _remap_inserted_ramp(resource.voxels, index, ramp.size(), palette.size())
		if voxels.is_empty() and not resource.voxels.is_empty():
			return {"error": "Есть ссылка за пределы палитры. Исправьте ресурс перед созданием рампа."}
		var water := _remap_inserted_ramp(resource.surface_fill_palette, index, ramp.size(), palette.size())
		if water.is_empty() and not resource.surface_fill_palette.is_empty():
			return {"error": "Есть ссылка воды за пределы палитры. Исправьте ресурс перед созданием рампа."}
		return {
			"label": "Создать рамп оттенков",
			"selected": index + center,
			"properties": {
				&"palette": next_palette,
				&"voxels": voxels,
				&"surface_fill_palette": water,
			},
		}
	if kind != "merge":
		return {"error": "Неизвестная операция палитры"}
	var target := int(operation.get("target", -1))
	if target < 1 or target >= palette.size() or target == index or palette.size() <= 2:
		return {"error": "Выберите другой цвет для замены; последний цвет удалить нельзя"}
	var voxels := resource.voxels.duplicate()
	var water := resource.surface_fill_palette.duplicate()
	for channel in [voxels, water]:
		for i in channel.size():
			var value := int(channel[i])
			if value >= palette.size():
				return {"error": "Есть ссылка за пределы палитры. Исправьте ресурс перед объединением."}
			if value == index:
				value = target
			channel[i] = value - 1 if value > index else value
	palette.remove_at(index)
	return {
		"label": "Заменить и удалить цвет", "selected": target - 1 if target > index else target,
		"properties": {&"palette": palette, &"voxels": voxels, &"surface_fill_palette": water},
	}


static func _opaque(color: Color) -> Color:
	return Color(clampf(color.r, 0, 1), clampf(color.g, 0, 1), clampf(color.b, 0, 1), 1.0)


static func build_ramp(base: Color, steps: int, style: int) -> PackedColorArray:
	## Returns a complete odd ramp with the unmodified base in the center.
	steps = 3 if steps <= 3 else 5 if steps <= 5 else 7
	var center := steps / 2
	var result := PackedColorArray()
	for index in steps:
		var signed_distance := float(index - center) / float(center)
		var amount := absf(signed_distance)
		var hue := base.h
		if style == 1:
			# A small clockwise shift makes green shadows cyan and blue shadows violet;
			# highlights travel the other way toward a warmer neighbour.
			hue = fposmod(hue + (0.045 * amount if signed_distance < 0.0 else -0.03 * amount), 1.0)
		var saturation := base.s
		var value := base.v
		if signed_distance < 0.0:
			var shadow_target := maxf(0.035, base.v * (0.42 if style == 2 else 0.16))
			value = lerpf(base.v, shadow_target, amount)
			saturation = clampf(base.s + (0.06 if style == 2 else 0.16) * amount, 0.0, 1.0)
		elif signed_distance > 0.0:
			var light_target := 0.92 if style == 2 else 0.98
			value = lerpf(base.v, maxf(base.v, light_target), amount)
			saturation = lerpf(base.s, base.s * (0.68 if style == 2 else 0.48), amount)
		var color := Color.from_hsv(hue, saturation, value, 1.0)
		result.append(_opaque(base if index == center else color))
	return result


static func _remap_inserted_ramp(
	channel: PackedByteArray,
	index: int,
	ramp_size: int,
	old_palette_size: int,
) -> PackedByteArray:
	var result := channel.duplicate()
	var center := ramp_size / 2
	var shift := ramp_size - 1
	for cursor in result.size():
		var value := int(result[cursor])
		if value >= old_palette_size:
			return PackedByteArray()
		if value == index:
			result[cursor] = index + center
		elif value > index:
			result[cursor] = value + shift
	return result
