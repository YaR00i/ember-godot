@tool
class_name EmberVnVisuals
extends RefCounted
## Visual-library projections for the existing EmberVnAssets resolver. These
## entries are editor-only views and never become a second VN asset registry.


static func background_entries(
	assets: EmberVnAssets,
	empty_label: String,
	empty_tooltip: String,
	empty_texture: Texture2D,
	current_id: String,
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = [{
		"id": "",
		"label": empty_label,
		"tooltip": empty_tooltip,
		"texture": empty_texture,
	}]
	var found := current_id.is_empty()
	for source in assets.art_entries():
		if str(source.get("kind", "")) == "portrait":
			continue
		var art_id := str(source.get("id", ""))
		var caption := str(source.get("captionRu", art_id)).strip_edges()
		if caption.is_empty():
			caption = art_id
		var exists := bool(source.get("exists", false))
		entries.append({
			"id": art_id,
			"label": "%s%s\n%s" % ["" if exists else "⚠ ", caption, art_id],
			"tooltip": "%s\nID: %s\n%s\n%s" % [
				caption,
				art_id,
				source.get("path", ""),
				(
					"Godot Resource · редактируемый"
					if bool(source.get("native", false))
					else "Legacy JSON · только чтение"
				) if exists else "ФАЙЛ ОТСУТСТВУЕТ",
			],
			"texture": assets.art_thumbnail(art_id, 56),
		})
		found = found or art_id == current_id
	if not found:
		entries.append(_missing_entry(current_id, "Неизвестный фон"))
	return entries


static func speaker_entries(assets: EmberVnAssets, current_speaker: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var found := false
	for speaker in assets.speaker_ids():
		var representative := (
			"neutral"
			if assets.has_portrait(speaker, "neutral")
			else assets.first_portrait_key(speaker)
		)
		var count := assets.portrait_entries(speaker).size()
		entries.append({
			"id": speaker,
			"label": "%s\n%d эмоций" % [speaker, count],
			"tooltip": "Персонаж: %s\nВыражений: %d" % [speaker, count],
			"texture": assets.portrait_thumbnail(speaker, representative, 56),
		})
		found = found or speaker == current_speaker
	if not found:
		entries.append(_missing_entry(current_speaker, "Нет portrait registry"))
	return entries


static func portrait_entries(
	assets: EmberVnAssets, speaker: String, current_key: String
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var found := false
	for source in assets.portrait_entries(speaker):
		var portrait_key := str(source.get("key", ""))
		var label := str(source.get("labelRu", portrait_key)).strip_edges()
		var exists := bool(source.get("exists", false))
		entries.append({
			"id": portrait_key,
			"label": "%s%s\n%s" % ["" if exists else "⚠ ", label, portrait_key],
			"tooltip": "%s\n%s / %s\n%s" % [
				label,
				speaker,
				portrait_key,
				source.get("path", "ФАЙЛ ОТСУТСТВУЕТ"),
			],
			"texture": assets.portrait_thumbnail(speaker, portrait_key, 56),
		})
		found = found or portrait_key == current_key
	if not found:
		entries.append(_missing_entry(current_key, "Нет у %s" % speaker))
	return entries


static func _missing_entry(value: String, reason: String) -> Dictionary:
	return {
		"id": value,
		"label": "⚠ %s\n%s" % [value if not value.is_empty() else "не выбран", reason],
		"tooltip": "%s: %s" % [reason, value],
		"texture": null,
	}
