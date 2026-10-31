extends RefCounted
## One scene-binding projection for Action authoring and runtime lookup.

static func entries(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if root == null:
		return result
	var supports_presentation := root.has_method("start_for_action")
	var script: Script = root.get_script()
	if script != null and not supports_presentation:
		# Non-tool scene scripts are placeholders in the native editor.
		for method in script.get_script_method_list():
			if str(method.name) == "start_for_action":
				supports_presentation = true
	if supports_presentation:
		var id := str(root.get("presentation_id")).strip_edges()
		if not id.is_empty():
			result.append({"id": id, "name": str(root.get("presentation_name")), "node": root})
	for child in root.get_children():
		result.append_array(entries(child))
	return result


static func resolve(root: Node, id: String) -> Dictionary:
	var matches: Array[Node] = []
	for entry in entries(root):
		if entry.id == id:
			matches.append(entry.node)
	if matches.size() != 1:
		return {"ok": false, "error": "Сценка «%s»: %s" % [id, "не найдена на этой карте" if matches.is_empty() else "несколько сценок с одинаковым ключом"]}
	return {"ok": true, "node": matches[0]}
