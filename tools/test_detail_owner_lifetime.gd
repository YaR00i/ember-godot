extends SceneTree
const Patch=preload("res://scripts/ember_grass_patch.gd")
class Map extends EmberMapLoader:
	func _ready()->void:pass
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("DETAIL_OWNER_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var first:=Map.new();var second:=Map.new();root.add_child(first);root.add_child(second)
	first.set_process(false);second.set_process(false)
	var container:=Node3D.new();first.add_child(container)
	var patch:=Patch.new();container.add_child(patch);patch.set_process(false)
	check(patch._map()==first,"initial nearest map")
	container.reparent(second)
	check(patch._map()==second,"ancestor reparent invalidates cached owner")
	second.remove_child(container)
	check(patch._map()==null,"detached subtree has no stale owner")
	first.add_child(container)
	check(patch._map()==first,"Undo style reattachment resolves owner")
	container.remove_child(patch)
	check(patch._map()==null,"detached patch has no owner")
	container.add_child(patch)
	check(patch._map()==first,"same patch reattachment works without another ready")
	var detached:=Map.new();container.remove_child(patch);detached.add_child(patch)
	check(patch._map()==detached,"off-tree authoring resolves current ancestry")
	detached.remove_child(patch);container.add_child(patch)
	check(patch._map()==first,"off-tree query does not poison later runtime owner")
	detached.free();first.free();second.free();await process_frame
	print("DETAIL_OWNER_LIFETIME ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
