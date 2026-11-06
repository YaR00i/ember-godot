extends SceneTree
## Rebuild an already staged private avatar, without touching the companion source/config.
const Lod=preload("res://tools/fixtures/hoshi_native_lods.gd")
func _initialize()->void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):output=arg.trim_prefix("output=")
	if output.is_empty():printerr("Provide -- output=<candidate.scn>; the source is never overwritten by default");quit(2);return
	var packed:PackedScene=load("res://assets/local_characters/hoshi/avatar.scn")
	var avatar:=packed.instantiate()
	var changed:=0
	for visual:MeshInstance3D in avatar.find_children("*","MeshInstance3D",true,false):
		var next:=Lod.prepare(visual.mesh)
		if next!=visual.mesh:visual.mesh=next;changed+=1
	var candidate:=PackedScene.new()
	var error:=candidate.pack(avatar)
	if error==OK:error=ResourceSaver.save(candidate,output,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)
	avatar.free()
	print("HOSHI_NATIVE_LODS ",JSON.stringify({"error":error,"changed_meshes":changed,"output":output}))
	quit(0 if error==OK else 1)
