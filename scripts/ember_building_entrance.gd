@tool
extends Node3D
## Derived placement from the prepared mesh. Never reads an editor recipe.
## Children own the authored destination/return ID; the building owns this frame.
var _last_frame:=Transform3D(Basis.IDENTITY,Vector3(INF,INF,INF))
func _ready()->void:_sync_frame()
func _process(_delta:float)->void:
	_sync_frame()
	if not Engine.is_editor_hint() and _last_frame.origin.is_finite():set_process(false)
func _sync_frame()->void:
	var visual=get_parent().get_node_or_null("Mesh") as MeshInstance3D
	if visual==null or visual.mesh==null:return
	var published:Dictionary=get_parent().authoring_visual_state() if get_parent().has_method("authoring_visual_state") else {}
	var mesh:Mesh=published.get("mesh",visual.mesh)
	var entry:Variant=mesh.get_meta("ember_building_entry",{})
	if not entry is Dictionary or not entry.get("point") is Vector3 or not entry.get("normal") is Vector3:return
	var direction:Vector3=entry.normal
	var frame=Transform3D(Basis(Vector3.UP,atan2(direction.x,direction.z)),visual.transform*entry.point)
	if frame==_last_frame:return
	_last_frame=frame;transform=frame
