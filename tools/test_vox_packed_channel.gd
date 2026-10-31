extends SceneTree
## Native packed copy/resize must preserve the legacy Array channel contract.
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:
	var model:Dictionary={"sizeBlocks":{"x":1,"y":1,"z":1},"heightVoxels":1}
	for count:int in [0,1,255,256,257,300]:
		var bytes:=PackedByteArray();bytes.resize(count)
		for i in count:bytes[i]=i%256
		model.voxels=Array(bytes)
		var expected:=VoxMesher.model_channel(model,"voxels")
		model.voxels=bytes
		var actual:=VoxMesher.model_channel(model,"voxels")
		check(actual==expected,"packed padding/truncation matches Array at size "+str(count))
		actual[0]=255 if bytes.is_empty() or bytes[0]!=255 else 0
		check(model.voxels==bytes,"caller mutation never changes Source")
		if not bytes.is_empty():
			var detached:=VoxMesher.model_channel(model,"voxels")
			model.voxels[0]=123
			check(detached==expected,"later Source mutation never changes a detached snapshot")
	print("VOX_PACKED_CHANNEL ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
