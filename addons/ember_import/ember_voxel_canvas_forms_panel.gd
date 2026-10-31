@tool
extends VBoxContainer
const Model=preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
var preview_root:Node3D
var candidate:Dictionary={}
var candidate_visual:MeshInstance3D
var cancel:Button
## Compact controls in the existing Canvas; no independent document or viewport.
var workspace:WeakRef
var choice:OptionButton
var mode:Button
var join:Button
var detach:Button
var align_grid:CheckBox
var bake_orientation:CheckBox
var offsets:Array[SpinBox]=[]
var hint:Label
var position_row:Container
var advanced:Button
var options_row:Container
var updating:=false
var edit_before:Dictionary={}
func configure(view:Control)->void:
	updating=true;edit_before={};offsets.clear()
	for child in get_children():child.free()
	workspace=weakref(view);name="CanvasFormsPanel";add_theme_constant_override("separation",4)
	var row:=HFlowContainer.new();add_child(row)
	var target_label:=Label.new();target_label.text="Форма";row.add_child(target_label)
	choice=OptionButton.new();choice.custom_minimum_size.x=210;choice.clip_text=true
	choice.item_selected.connect(func(index):
		if not updating:view._canvas_forms.select(index);refresh())
	row.add_child(choice)
	var add:=MenuButton.new();add.text="+ Форма";row.add_child(add)
	add.get_popup().add_item("Блок",0);add.get_popup().add_item("Сфера",1);add.get_popup().add_item("Модель из библиотеки…",2)
	add.get_popup().id_pressed.connect(func(id):
		if id==2:choose_resource();return
		finish_input()
		if not view._canvas_forms.add_shape("block" if id==0 else "sphere"):view._set_status(view._canvas_forms.error,true)
		refresh())
	mode=Button.new();mode.text="Двигать";mode.toggle_mode=true;row.add_child(mode)
	mode.toggled.connect(func(enabled):
		finish_input()
		view._switch_canvas_mode(view.CanvasMode.FORMS if enabled else view.CanvasMode.BRUSH)
		refresh())
	var operations:=HFlowContainer.new();add_child(operations)
	var join_label:=Label.new();join_label.text="Соединение";operations.add_child(join_label)
	var prepare:=Button.new();prepare.text="Предпросмотр";prepare.tooltip_text="Показать точный результат соединения без изменения форм."
	prepare.pressed.connect(func():
		finish_input()
		candidate=view._canvas_forms.prepare_combine(align_grid.button_pressed,bake_orientation.button_pressed)
		if candidate.has("error"):view._set_status(candidate.error,true);candidate={};return
		view._switch_canvas_mode(view.CanvasMode.FORMS);sync_preview();refresh()
		view._set_status("Предпросмотр соединения · исходные формы не изменены · Применить или Отмена"))
	operations.add_child(prepare)
	join=Button.new();join.text="Соединить";join.tooltip_text="Все формы этого Canvas. Покрытие активной формы имеет приоритет в пересечении. Один Undo."
	join.pressed.connect(func():
		var prepared:=candidate
		finish_input()
		if not view._canvas_forms.combine(align_grid.button_pressed,bake_orientation.button_pressed,prepared):view._set_status(view._canvas_forms.error,true)
		else:mode.button_pressed=false;view._set_status("Формы соединены · можно продолжать лепку · Ctrl+Z отменяет")
		refresh())
	operations.add_child(join)
	cancel=Button.new();cancel.text="Отмена";cancel.pressed.connect(cancel_preview);operations.add_child(cancel)
	var separation:=HFlowContainer.new();add_child(separation)
	var separate_label:=Label.new();separate_label.text="Отделение";separation.add_child(separate_label)
	detach=Button.new();detach.text="Отделить выделение";detach.tooltip_text="Выделите часть прежним инструментом выделения; кусок останется в этом Canvas."
	detach.pressed.connect(func():
		finish_input()
		if not view._canvas_forms.separate(view._selection_panel.selection_indices()):view._set_status(view._canvas_forms.error,true)
		else:view._set_status("Кусок отделён · выберите его в списке или продолжайте лепить основу")
		refresh())
	separation.add_child(detach)
	var parts:=Button.new();parts.text="Разобрать части";parts.tooltip_text="Разделить склейку по сохранённым частям. Один Undo; результат остаётся в Canvas."
	parts.pressed.connect(func():
		finish_input()
		if not view._canvas_forms.separate_parts():view._set_status(view._canvas_forms.error,true)
		else:view._set_status("Части разделены · можно выбрать и продолжить лепку")
		refresh())
	separation.add_child(parts)
	var sculpt:=Button.new();sculpt.text="В лепку";sculpt.pressed.connect(func():mode.button_pressed=false;view._return_to_last_brush();refresh());row.add_child(sculpt)
	advanced=Button.new();advanced.text="Дополнительно";advanced.toggle_mode=true;operations.add_child(advanced)
	var options:=HFlowContainer.new();options_row=options;add_child(options);options.hide()
	advanced.toggled.connect(func(enabled):options.visible=enabled)
	align_grid=CheckBox.new();align_grid.text="Совместить сетки";align_grid.tooltip_text="Основная форма неподвижна. Остальные сдвигаются к ближайшей ячейке её сетки при соединении.";options.add_child(align_grid)
	bake_orientation=CheckBox.new();bake_orientation.text="Запечь поворот 90°";bake_orientation.tooltip_text="Перенести поворот сцены на 90° в сами ячейки. Произвольный угол, отражение и неравномерный масштаб не округляются.";options.add_child(bake_orientation)
	for option in [align_grid,bake_orientation]:option.toggled.connect(func(_enabled):cancel_preview())
	var position:=HFlowContainer.new();position_row=position;add_child(position)
	var caption:=Label.new();caption.text="Положение, м";position.add_child(caption)
	for axis in 3:
		var spin:=SpinBox.new();spin.prefix=["X ","Y ","Z "][axis];spin.min_value=-128;spin.max_value=128;spin.step=1.0/16.0;spin.custom_minimum_size.x=135
		spin.value_changed.connect(func(_value):
			if updating:return
			if edit_before.is_empty():edit_before=view._canvas_forms.capture()
			view._canvas_forms.set_position(Vector3(offsets[0].value,offsets[1].value,offsets[2].value)))
		spin.get_line_edit().focus_exited.connect(finish_position)
		spin.get_line_edit().text_submitted.connect(func(_text):finish_position())
		spin.gui_input.connect(func(event):
			if event is InputEventMouseButton and not event.pressed:finish_position())
		offsets.append(spin);position.add_child(spin)
	hint=Label.new();hint.text="Двигать: перетащи форму · Esc отменяет · в лепке работают прежние кисти";hint.modulate=Color(0.65,0.72,0.78);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	updating=false;refresh()
func finish_position()->void:
	if edit_before.is_empty():return
	var view:Control=workspace.get_ref();var before:=edit_before;edit_before={}
	view._canvas_forms._record(before,"Canvas · положение формы")
func refresh()->void:
	var view:Control=workspace.get_ref()
	if view==null or view._canvas_forms==null:return
	updating=true;choice.clear()
	mode.set_pressed_no_signal(view._canvas_mode==view.CanvasMode.FORMS)
	var forms:RefCounted=view._canvas_forms
	for i in forms.bodies.size():
		var body=forms.bodies[i];choice.add_item("%d · %s"%[i+1,body.entry.resource.display_name])
		if body==forms.active:choice.select(i)
	join.disabled=forms.bodies.size()<2
	join.text="Применить" if not candidate.is_empty() else "Соединить"
	cancel.visible=not candidate.is_empty()
	var position:Vector3=forms.position_of(forms.active)
	for i in 3:offsets[i].set_value_no_signal(position[i])
	position_row.visible=mode.button_pressed and candidate.is_empty();hint.visible=mode.button_pressed and candidate.is_empty()
	updating=false

func clear_preview()->void:
	if is_instance_valid(preview_root):preview_root.free()
	preview_root=null;candidate_visual=null;candidate={}
	var view:Control=workspace.get_ref()
	if view!=null and is_instance_valid(view._surface_root):view._surface_root.show()

func cancel_preview()->void:
	candidate={}
	if is_instance_valid(candidate_visual):candidate_visual.free()
	candidate_visual=null
	sync_preview();refresh()

func finish_input()->void:
	var view:Control=workspace.get_ref()
	view._flush_pending_stroke_position();view._finish_stroke()
	if view._grab_interaction!=null and view._grab_interaction.active:view._grab_interaction.cancel("Переход к формам")
	if view._canvas_forms!=null and view._canvas_forms.moving:
		view._canvas_forms.moving=false;view._canvas_forms.apply_history_state(view._canvas_forms.move_before)
	finish_position()
	if not candidate.is_empty():cancel_preview()


func sync_preview()->void:
	var view:Control=workspace.get_ref()
	if view._canvas_forms==null:return
	if not is_instance_valid(preview_root):
		preview_root=Node3D.new();preview_root.name="CanvasOtherForms";view._viewport.add_child(preview_root)
	if not candidate.is_empty():
		if candidate.before!=view._canvas_forms.capture(view._canvas_forms.bodies):
			cancel_preview();view._set_status("Формы изменились · прежний предпросмотр снят. Обновите его.");return
		for child in preview_root.get_children():child.visible=false
		if not is_instance_valid(candidate_visual):
			candidate_visual=MeshInstance3D.new();preview_root.add_child(candidate_visual)
			candidate_visual.mesh=preload("res://scripts/ember_voxel_surface_mesher.gd").build_region(candidate.source,Vector3i.ZERO,candidate.source.grid_size(),1.0/candidate.source.normalized_density(),false,false,-1)
		candidate_visual.transform=view._canvas_forms.frame(view._canvas_forms.active).affine_inverse()*candidate.frame
		candidate_visual.show();view._surface_root.hide();return
	view._surface_root.show()
	var visuals:Dictionary={}
	for child in preview_root.get_children():child.show();visuals[child.get_meta("form_key")]=child
	var inverse:Transform3D=view._canvas_forms.frame(view._canvas_forms.active).affine_inverse()
	for body in view._canvas_forms.bodies:
		if body==view._canvas_forms.active:continue
		var key:int=body.get_instance_id()
		var visual:MeshInstance3D=visuals.get(key)
		if visual==null:
			visual=MeshInstance3D.new();visual.set_meta("form_key",key);preview_root.add_child(visual)
		visual.mesh=view._canvas_forms.mesh_for(body)
		visual.transform=inverse*view._canvas_forms.frame(body);visuals.erase(key)
	for visual in visuals.values():visual.free()


func choose_resource()->void:
	var view:Control=workspace.get_ref()
	var dialog:=EditorFileDialog.new() if Engine.is_editor_hint() else FileDialog.new()
	dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.access=FileDialog.ACCESS_RESOURCES
	dialog.filters=PackedStringArray(["*.tres,*.res ; Сохранённая voxel-модель"])
	dialog.current_dir="res://content/voxel_models"
	dialog.file_selected.connect(func(path:String):
		var source:=load(path) as EmberVoxelModelResource
		if source==null or not source.validation_errors().is_empty():view._set_status("Выберите сохранённую voxel-модель.",true)
		elif not view._canvas_forms.add_source(source.duplicate_model()):view._set_status(view._canvas_forms.error,true)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);add_child(dialog);dialog.popup_centered(Vector2i(850,600))


func _ray(position:Vector2)->Dictionary:
	var view:Control=workspace.get_ref()
	var pixel:Vector2=position*Vector2(view._viewport.size)/view._viewport_container.size.max(Vector2.ONE)
	var frame:Transform3D=view._canvas_forms.frame(view._canvas_forms.active)
	return {"origin":frame*view._camera.project_ray_origin(pixel),"direction":(frame.basis*view._camera.project_ray_normal(pixel)).normalized()}


func handle(event:InputEvent)->bool:
	var view:Control=workspace.get_ref()
	if view._canvas_forms==null or view._canvas_mode!=view.CanvasMode.FORMS:return false
	if not candidate.is_empty():return event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT
	var forms:RefCounted=view._canvas_forms
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and forms.moving:
		forms.moving=false;forms.apply_history_state(forms.move_before);return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var ray:=_ray(event.position);var closest:=INF;var chosen:=-1;var point:=Vector3.ZERO
			for i in forms.bodies.size():
				var body=forms.bodies[i];var inverse:Transform3D=forms.frame(body).affine_inverse()
				var pick:=Model.pick(body.entry.resource,inverse*ray.origin,(inverse.basis*ray.direction).normalized())
				if not pick.has("hit"):continue
				var hit:Vector3=forms.frame(body)*((Vector3(pick.hit)+Vector3.ONE*0.5)/body.entry.resource.normalized_density())
				var distance:float=hit.distance_squared_to(ray.origin)
				if distance<closest:closest=distance;chosen=i;point=hit
			if chosen<0:return true
			forms.select(chosen);ray=_ray(event.position)
			forms.move_plane=Plane(ray.direction,point)
			forms.move_anchor=forms.move_plane.intersects_ray(ray.origin,ray.direction)
			forms.move_origin=forms.position_of(forms.active);forms.move_before=forms.capture();forms.moving=true
		elif forms.moving:
			forms.moving=false;forms._record(forms.move_before,"Canvas · переместить форму")
		return true
	if event is InputEventMouseMotion and forms.moving:
		var ray:=_ray(event.position)
		var point:Variant=forms.move_plane.intersects_ray(ray.origin,ray.direction)
		if point!=null:
			var position:Vector3=forms.move_origin+forms.origin.basis.inverse()*(point-forms.move_anchor)
			var density:float=forms.active.entry.resource.normalized_density()
			forms.set_position((position*density).round()/density)
		return true
	return event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT
