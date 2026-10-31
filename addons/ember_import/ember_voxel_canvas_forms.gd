@tool
extends RefCounted
## Canvas routing over existing world drafts. Geometry stays in their Resources;
## Merge/Extract own the calculations and WorldEditSessions owns publication.
const Merge=preload("res://addons/ember_import/ember_voxel_merge.gd")
const Extract=preload("res://addons/ember_import/ember_voxel_fragment_extract.gd")
const Shapes=preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Surface=preload("res://scripts/ember_voxel_surface_mesher.gd")
const Assembly=preload("res://addons/ember_import/ember_voxel_scene_assembly.gd")
class Body extends RefCounted:
	var entry:Dictionary
	var node:Node3D
	var original_path:NodePath
	var mesh:ArrayMesh
var registry:RefCounted
var workspace:WeakRef
var scene:Node
var bodies:Array[Body]=[]
var all_bodies:Array[Body]=[]
var active:Body
var saved:Dictionary
var error:=""
var moving:=false
var move_before:Dictionary
var move_plane:Plane
var move_anchor:=Vector3.ZERO
var move_origin:=Vector3.ZERO
var mesh_builds:=0
var origin:=Transform3D.IDENTITY

func configure(view:Control,sessions:RefCounted,entry:Dictionary)->bool:
	registry=sessions;workspace=weakref(view);scene=entry.scene.get_ref()
	active=_body(entry);bodies=[active]
	origin=frame(active)
	entry.canvas_parent=weakref(active.node.get_parent())
	saved=capture([active])
	for row in saved.rows:
		row.data=_fields(active.entry.baseline)
	var layout:Dictionary=entry.get("canvas_layout",{})
	if not layout.is_empty():
		var group:String=layout.get("group","")
		var base:Node=scene.get_node_or_null(NodePath(group)) if not group.is_empty() else null
		if base is EmberVoxelProp and base!=active.node:
			var base_entry:Dictionary=registry.open_object(base,scene)
			if not base_entry.is_empty():base_entry.canvas_layout={"group":group}
		for other:Dictionary in registry.entries.values():
			if other==entry or other.get("canvas_layout",{}).get("group","")!=group:continue
			var body:=_body(other);bodies.append(body)
		saved={"rows":[],"active":null}
		var restored_nodes:Dictionary={}
		for body in bodies:
			body.entry.canvas_parent=weakref(body.node.get_parent())
			if not body.entry.get("created",false):
				saved.rows.append({"body":body,"pose":body.entry.get("canvas_pose_baseline",body.node.transform),"data":_fields(body.entry.baseline)})
			for removed in body.entry.get("canvas_removed_nodes",[]):
				if not removed.has("entry"):continue
				if restored_nodes.has(removed.node.get_instance_id()):continue
				restored_nodes[removed.node.get_instance_id()]=true
				var old:=_body(removed.entry,removed.path)
				saved.rows.append({"body":old,"pose":old.node.transform,"data":_fields(old.entry.baseline)})
		if not saved.rows.is_empty():saved.active=saved.rows[0].body
	return true

func _body(entry:Dictionary,original_path:=NodePath())->Body:
	var body:=Body.new();body.entry=entry;body.node=entry.target.get_ref()
	body.original_path=scene.get_path_to(body.node) if original_path.is_empty() else original_path;entry.canvas_forms=weakref(self)
	all_bodies.append(body)
	var reference:=weakref(body);var controller:=weakref(self)
	entry.resource.geometry_changed.connect(func(_indices):
		var current:Body=reference.get_ref();var forms:RefCounted=controller.get_ref()
		if current==null:return
		current.mesh=null
		if forms!=null and current!=forms.active:
			var view:Control=forms.workspace.get_ref()
			if view!=null and view._canvas_forms==forms:view._forms_panel.sync_preview())
	return body

func frame(body:Body)->Transform3D:return registry.frame(body.entry)
func _fields(source:Resource)->Dictionary:
	var result:Dictionary={}
	for key in registry.FIELDS:
		if key!="model_id":result[key]=EmberVoxelModelResource.copy_authoring_value(source.get(key))
	return result
func capture(with_data:Array=[])->Dictionary:
	var view:Control=workspace.get_ref()
	if view!=null:view._publish_world_guard()
	var rows:Array=[]
	for body in bodies:
		rows.append({"body":body,"pose":body.node.transform,"data":_fields(body.entry.resource) if body in with_data else {},"guard":body.entry.get("canvas_guard",{}).duplicate(true)})
	return {"rows":rows,"active":active}

func apply_history_state(state:Dictionary)->void:
	var view:Control=workspace.get_ref()
	if view!=null:view._guard_transition=true
	var old_frame:=frame(active) if active!=null and active.node.is_inside_tree() else Transform3D.IDENTITY
	var next:Array[Body]=[]
	for row in state.rows:next.append(row.body)
	for body in bodies:
		if body not in next:
			registry.entries.erase(body.node.get_instance_id())
			if body.node.get_parent()!=null:body.node.get_parent().remove_child(body.node)
	bodies=next;active=state.active
	for row in state.rows:
		var body:Body=row.body
		if body.node.get_parent()==null:
			var parent:Node=body.entry.canvas_parent.get_ref()
			EmberSceneAuthoring.attach_model_instance(scene,parent,body.node)
		body.entry.canvas_guard=row.get("guard",{}).duplicate(true)
		body.node.transform=row.pose
		for key in row.data:body.entry.resource.set(key,EmberVoxelModelResource.copy_authoring_value(row.data[key]))
		registry.entries[body.node.get_instance_id()]=body.entry
		if not row.data.is_empty():
			body.mesh=null
			body.entry.resource.notify_geometry_changed(PackedInt32Array())
	_update_layout()
	if view!=null and view._canvas_forms==self:
		var rebuild:bool=view._resource!=active.entry.resource
		for row in state.rows:
			if row.body==active and not row.data.is_empty():rebuild=true
		view._bind_canvas_form(active.entry,old_frame,frame(active),rebuild)
	if view!=null:view._guard_transition=false
	registry.changed.emit()
	if Engine.is_editor_hint():EditorInterface.mark_scene_as_unsaved()

func _record(before:Dictionary,title:String)->bool:
	var view:Control=workspace.get_ref()
	var changed:Array=[]
	for row in before.rows:
		if not row.data.is_empty() and row.body in bodies:changed.append(row.body)
	var after:=capture(changed)
	_update_layout()
	view._actions.record_editor_state(scene,self,before,after,title)
	registry.changed.emit()
	return true

func select(index:int)->void:
	if index<0 or index>=bodies.size():return
	var view:Control=workspace.get_ref()
	if view!=null:view._forms_panel.finish_input()
	var old_frame:=frame(active);active=bodies[index]
	view._bind_canvas_form(active.entry,old_frame,frame(active))

func add_shape(kind:String)->bool:
	var view:Control=workspace.get_ref();var source:EmberVoxelModelResource=active.entry.resource
	var made:=Shapes.build(kind,Vector3i(16,16,16),16,Color.WHITE,"canvas_form_%d"%Time.get_ticks_usec(),"Сфера" if kind=="sphere" else "Блок")
	if not made.get("ok",false):error=made.get("error","");return false
	var shape:EmberVoxelModelResource=made.source
	shape.palette=source.palette.duplicate();shape.material=source.material.duplicate(true);shape.physical=source.physical
	var slot:=int(view._palette.get_selected_metadata()) if view._palette.selected>=0 else 1
	slot=clampi(slot,1,shape.palette.size()-1)
	for i in shape.voxels.size():
		if shape.voxels[i]>0:shape.voxels[i]=slot
	if not source.solid_surface.is_empty():
		shape.merge_parts=PackedStringArray([shape.display_name]);shape.voxel_part_ids.resize(shape.voxels.size())
		for i in shape.voxels.size():shape.voxel_part_ids[i]=1 if shape.voxels[i]>0 else 0
		shape.solid_surface={"version":1,"topology":"volume","parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],"roles":source.solid_surface.roles.duplicate(),"material_ids":source.solid_surface.material_ids.duplicate(),"occupancy":Solid.occupancy_hash(shape.voxels)}
	return add_source(shape)

func add_source(source:EmberVoxelModelResource)->bool:
	if not source.tree_surface.is_empty() or not source.surface_fill_levels.is_empty():
		error="Для этого цикла выберите обычную объёмную форму; деревья и водные поверхности сохраняют свой редактор.";return false
	var before:=capture();var old_frame:=frame(active)
	var position:=Vector3(active.entry.resource.size_blocks.x*0.5,active.entry.resource.grid_size().y/float(active.entry.resource.normalized_density())-0.25,active.entry.resource.size_blocks.z*0.5)
	var entry:Dictionary=registry.create_object(source,scene,active.node.get_parent(),old_frame*Transform3D(Basis.IDENTITY,position))
	if entry.is_empty():error=registry.error;return false
	entry.canvas_parent=weakref(active.node.get_parent())
	var body:=_body(entry);bodies.append(body);active=body
	_record(before,"Canvas · добавить форму")
	(workspace.get_ref() as Control)._bind_canvas_form(entry,old_frame,frame(active))
	return true

func include_nodes(nodes:Array)->bool:
	var guard:=Assembly.new();guard.source_directory=registry.source_directory
	if not guard._scene_valid(scene):error=guard.error;return false
	var incoming:Array[Dictionary]=[]
	for node in nodes:
		if bodies.any(func(body):return body.node==node):continue
		var known:Dictionary=registry.entries.get(node.get_instance_id(),{})
		if not guard._ordinary(node,scene,known.is_empty(),known.get("preview")):error=guard.error;return false
		if node.get_parent()!=active.node.get_parent():error="Выберите формы под одним родителем.";return false
		var entry:Dictionary=registry.open_object(node,scene)
		if entry.is_empty():error=registry.error;return false
		var other:WeakRef=entry.get("canvas_forms")
		if other!=null and other.get_ref()!=null and other.get_ref()!=self:error="Форма уже открыта в другом наборе Canvas. Завершите его или выберите формы этого набора.";return false
		incoming.append(entry)
	for entry in incoming:
		entry.canvas_parent=weakref(entry.target.get_ref().get_parent())
		var body:=_body(entry);bodies.append(body)
		saved.rows.append({"body":body,"pose":body.node.transform,"data":_fields(entry.baseline)})
	var view:Control=workspace.get_ref();view._forms_panel.sync_preview();view._forms_panel.refresh()
	return true

func _can_replace(nodes:Array)->bool:
	var guard:=Assembly.new();guard.source_directory=registry.source_directory
	if not guard._scene_valid(scene):error=guard.error;return false
	for body in bodies:
		if not is_instance_valid(body.node):error="Форма удалена. Выберите существующие формы заново.";return false
		if body.node not in nodes:continue
		if not guard._ordinary(body.node,scene,not body.entry.get("created",false),body.entry.get("preview")):error=guard.error;return false
		if not body.entry.object_session.can_replace_geometry():error=body.entry.object_session.error;return false
	if not guard._references_clear(scene,nodes):error=guard.error;return false
	return true

func prepare_combine(align_grid:=false,bake_orientation:=false)->Dictionary:
	if bodies.size()<2:return {"error":"Добавьте вторую форму."}
	if not _can_replace(bodies.map(func(body):return body.node)):return {"error":error}
	var selected:=active;var first_frame:=frame(selected);var inputs:Array[Dictionary]=[]
	inputs.append({"source":selected.entry.resource,"frame":first_frame})
	for body in bodies:
		if body!=selected:inputs.append({"source":body.entry.resource,"frame":frame(body)})
	var result:=Merge.plan(inputs,align_grid,bake_orientation)
	if not result.has("error"):
		result.source.display_name=selected.entry.resource.display_name;result["before"]=capture(bodies)
		var guard:Dictionary=selected.entry.get("canvas_guard",{})
		if not guard.is_empty():
			var relative:Transform3D=result.frame.affine_inverse()*first_frame
			var density:int=selected.entry.resource.normalized_density();var offset:=relative.origin*density
			if not relative.basis.is_equal_approx(Basis.IDENTITY) or density!=result.source.normalized_density() or not offset.is_equal_approx(offset.round()):
				if guard.selection.get("mask_enabled",false) or guard.get("region",Rect2i()).has_area() or guard.get("height",-1)>=0:return {"error":"Снимите маску/область/срез перед сменой плотности или запеканием поворота."}
				result.guard={}
			else:
				var translated:=preload("res://addons/ember_import/ember_voxel_selection.gd").translate_brush_guard(guard,selected.entry.resource.grid_size(),result.source.grid_size(),Vector3i(offset.round()),density)
				if translated.has("error"):return translated
				result.guard=translated.guard

	return result

func combine(align_grid:=false,bake_orientation:=false,prepared:Dictionary={})->bool:
	var result:=prepare_combine(align_grid,bake_orientation) if prepared.is_empty() else prepared
	if result.has("error"):error=result.error;return false
	if not prepared.is_empty() and not _can_replace(bodies.map(func(body):return body.node)):return false
	if result.before!=capture(bodies):error="Формы изменились. Обновите предпросмотр соединения.";return false
	var selected:=active;var first_frame:=frame(selected)
	var before:=capture([selected])
	(workspace.get_ref() as Control)._guard_transition=true
	selected.entry.canvas_guard=result.get("guard",{}).duplicate(true)
	var source:EmberVoxelModelResource=result.source
	source.display_name=selected.entry.resource.display_name
	for key in _fields(source):selected.entry.resource.set(key,EmberVoxelModelResource.copy_authoring_value(source.get(key)))
	var adapter:Transform3D=selected.node.global_transform.affine_inverse()*frame(selected)
	selected.node.global_transform=result.frame*adapter.affine_inverse()
	for body in bodies:
		if body!=selected:
			registry.entries.erase(body.node.get_instance_id());body.node.get_parent().remove_child(body.node)
	bodies=[selected];selected.mesh=null
	selected.entry.resource.notify_geometry_changed(PackedInt32Array())
	_record(before,"Canvas · соединить объёмы")
	(workspace.get_ref() as Control)._bind_canvas_form(selected.entry,first_frame,frame(selected))
	(workspace.get_ref() as Control)._guard_transition=false
	return true

func separate_parts()->bool:
	if not _can_replace([active.node]):return false
	var result:=Merge.separate(active.entry.resource)
	if result.has("error"):error=result.error;return false
	var before:=capture();var old_frame:=frame(active);var next:Array[Dictionary]=[]
	for item in result.pieces:
		var entry:Dictionary=registry.create_object(item.source,scene,active.node.get_parent(),old_frame*Transform3D(Basis.IDENTITY,Vector3(item.origin)/item.source.normalized_density()))
		if entry.is_empty():
			for prepared in next:registry.entries.erase(prepared.target.get_ref().get_instance_id());prepared.target.get_ref().free()
			error=registry.error;return false
		entry.canvas_parent=weakref(active.node.get_parent());next.append(entry)
	registry.entries.erase(active.node.get_instance_id());active.node.get_parent().remove_child(active.node);bodies.erase(active)
	for entry in next:bodies.append(_body(entry))
	active=bodies.back();_record(before,"Canvas · разобрать части")
	(workspace.get_ref() as Control)._bind_canvas_form(active.entry,old_frame,frame(active))
	return true

func separate(indices:PackedInt32Array,cut:=true)->bool:
	var result:=Extract.plan(active.entry.resource,indices,cut)
	if result.has("error"):error=result.error;return false
	var before:=capture([active]);var old_frame:=frame(active)
	var piece:EmberVoxelModelResource=result.piece;piece.model_id="canvas_piece_%d"%Time.get_ticks_usec()
	var entry:Dictionary=registry.create_object(piece,scene,active.node.get_parent(),old_frame*Transform3D(Basis.IDENTITY,Vector3(result.origin)/piece.normalized_density()))
	if entry.is_empty():error=registry.error;return false
	entry.canvas_parent=weakref(active.node.get_parent())
	(workspace.get_ref() as Control)._guard_transition=true
	for key in _fields(result.remainder):active.entry.resource.set(key,EmberVoxelModelResource.copy_authoring_value(result.remainder.get(key)))
	active.mesh=null;bodies.append(_body(entry));active.entry.resource.notify_geometry_changed(PackedInt32Array())
	_record(before,"Canvas · отделить выделение")
	(workspace.get_ref() as Control)._bind_canvas_form(active.entry,old_frame,frame(active))
	(workspace.get_ref() as Control)._guard_transition=false
	return true

func position_of(body:Body)->Vector3:return origin.affine_inverse()*frame(body).origin

func set_position(position:Vector3)->void:
	var current:=frame(active);var target:=origin*position
	active.node.global_position+=target-current.origin
	(workspace.get_ref() as Control)._bind_canvas_form(active.entry,current,frame(active),false)
	_update_layout()

func _update_layout()->void:
	var removed:Array=[]
	for row in saved.rows:
		if row.body not in bodies:
			var body:Body=row.body
			removed.append({"path":body.original_path,"id":body.node.model_id,"hash":body.entry.hash})
	for body in bodies:
		body.entry.canvas_parent=weakref(body.node.get_parent())
		body.entry.canvas_layout={"pose":body.node.transform,"parent":scene.get_path_to(body.node.get_parent()),"created":body.entry.get("created",false),"removed":removed,"group":str(saved.rows[0].body.original_path) if not saved.rows.is_empty() else str(body.original_path),"changed":dirty()}

func accept_save()->void:
	saved=capture(bodies)
	_update_layout()

func discard()->void:
	apply_history_state(saved)

func dirty()->bool:
	if saved.rows.size()!=bodies.size():return true
	for body in bodies:
		if body.entry.get("created",false):return true
	for row in saved.rows:
		if row.body not in bodies or row.pose!=row.body.node.transform or row.data!=_fields(row.body.entry.resource):return true
	return false

func mesh_for(body:Body)->ArrayMesh:
	if body.mesh==null:
		body.mesh=Surface.build_region(body.entry.resource,Vector3i.ZERO,body.entry.resource.grid_size(),1.0/body.entry.resource.normalized_density(),false,false,-1)
		mesh_builds+=1
	return body.mesh

func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:
		for body in all_bodies:
			if is_instance_valid(body.node) and body.node.get_parent()==null:body.node.free()
