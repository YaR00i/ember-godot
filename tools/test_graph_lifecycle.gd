extends SceneTree
## Stress native frame retirement and objective focus without writing content.
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var workspace_host := Control.new()
	workspace_host.name = "GraphLifecycleTestHost"
	workspace_host.size = Vector2(1280.0, 720.0)
	root.add_child(workspace_host)
	await process_frame
	var baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle in 3:
		var workspace := Workspace.new()
		workspace_host.add_child(workspace)
		workspace.open_resource("dialogue", "sandbox_branch")
		var document: Dictionary = (workspace.get("_dialogue_draft") as Dictionary).duplicate(true)
		document["editorGroups"] = [{
			"id": "lifecycle_group", "title": "Lifecycle test",
			"members": ["agent_r", "walk_r"], "collapsed": false,
		}]
		workspace.set("_dialogue_draft", document)
		var graph: GraphEdit = workspace.get("_graph")
		var retired: Array[int] = []
		for rebuild in 6:
			workspace.call("_render_document", document)
			var live_frames := 0
			for element in workspace.call("_graph_elements"):
				if element is GraphFrame:
					live_frames += 1
					_check(graph.get_attached_nodes_of_frame(element.name).size() == 2,
						"frame lost its members during a same-frame rebuild")
					retired.append(element.get_instance_id())
					# This also queues native frame-order commands before retirement.
					element.raise_request.emit()
			_check(live_frames == 1, "retired frames leaked into active selection")
		# Switching resource in the same tick must release all original names,
		# but retain retired frames' parent until deferred native calls finish.
		workspace.open_resource("action", "sandbox_notice_quest")
		for id in retired:
			var frame := instance_from_id(id) as GraphFrame
			_check(frame != null and frame.get_parent() == graph and not frame.visible
				and frame.is_queued_for_deletion(), "frame detached before native deferred calls drained")
		await process_frame
		await process_frame
		for id in retired:
			_check(not is_instance_id_valid(id), "retired frame survived the frame boundary")
		# Repeated focused quest views used to allocate an unparented root card.
		workspace.open_resource("quest", "sandbox_notice_quest")
		var quest: Dictionary = workspace.get("_quest_draft")
		var objectives: Array = quest.get("objectives", [])
		_check(not objectives.is_empty(), "missing quest fixture")
		if not objectives.is_empty():
			for visit in 8:
				workspace.call("_open_quest_event_focus", str(objectives[0]["id"]))
				workspace.call("_render_document", quest)
				_check(graph.get_node_or_null("quest_root") == null, "objective focus rendered a root card")
				workspace.call("_open_quest_overview")
		await process_frame
		await process_frame
		_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == baseline,
			"quest focus leaked orphan nodes while workspace was alive (cycle %d)" % cycle)
		if "--visual" in OS.get_cmdline_user_args() and cycle == 0:
			workspace.open_resource("dialogue", "sandbox_branch")
			workspace.set("_dialogue_draft", document)
			workspace.call("_render_document", document)
			var secondary_tools := workspace.find_child("GraphSecondaryTools", true, false) as Button
			if secondary_tools != null:
				secondary_tools.pressed.emit()
			for frame in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			screenshot.crop(1280, 720)
			screenshot.save_png("user://ember_graph_lifecycle_test.png")
			print("VISUAL: ", ProjectSettings.globalize_path("user://ember_graph_lifecycle_test.png"))
		var workspace_id := workspace.get_instance_id()
		workspace.queue_free()
		await process_frame
		await process_frame
		_check(not is_instance_id_valid(workspace_id), "workspace survived closing")
		_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == baseline,
			"reopening workspace accumulated orphan nodes (cycle %d)" % cycle)
	workspace_host.queue_free()
	await process_frame
	if errors.is_empty():
		print("PASS Graph lifecycle: narrow 1280x720 host, 3 mount/unmount cycles, same-frame frame retirement, quest focus, no orphan growth")
	else:
		for error in errors:
			printerr(error)
	quit(0 if errors.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
