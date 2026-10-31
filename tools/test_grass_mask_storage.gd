extends SceneTree
const Patch=preload("res://scripts/ember_grass_patch.gd")
const Detail=preload("res://scripts/ember_detail_scatter.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("GRASS_MASK_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var directory:="user://ember-tests/grass-mask-"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var cells:Dictionary={}
	for y in 16:
		for x in 16:cells[Vector2i(x,y)]=60
	cells[Vector2i(1,1)]=0.0;cells[Vector2i(2,2)]=73.125
	var legacy:="[gd_scene format=3]\n[ext_resource type=\"Script\" path=\"res://scripts/ember_grass_patch.gd\" id=\"1\"]\n[node name=\"Grass\" type=\"Node3D\"]\nscript = ExtResource(\"1\")\npainted_only = true\ndensity_cells = "+var_to_str(cells)+"\n"
	var old_path:=directory.path_join("legacy.tscn");FileAccess.open(old_path,FileAccess.WRITE).store_string(legacy)
	var node:Node=ResourceLoader.load(old_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(node.density_cells==cells,"legacy text masks load exactly")
	check(node.density_cells.is_read_only(),"loaded density is a stable snapshot")
	var assigned:=cells.duplicate();node.density_cells=assigned
	assigned[Vector2i(3,3)]=0
	check(node.density_cells==cells,"caller alias cannot mutate the validated saved snapshot")
	var packed:=PackedScene.new();check(packed.pack(node)==OK,"pack existing patch")
	var path:=directory.path_join("compact.tscn");check(ResourceSaver.save(packed,path)==OK,"save compact patch")
	var text:=FileAccess.get_file_as_string(path)
	check(not "density_cells =" in text,"new saves omit the long text dictionary")
	check(FileAccess.open(path,FileAccess.READ).get_length()<2200,"full mask stays compact")
	var reopened:Node=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(reopened.density_cells==cells,"save/reopen preserves every painted and explicit zero cell")
	for key in cells:check(typeof(reopened.density_cells[key])==typeof(cells[key]),"numeric type retained "+str(key))
	var duplicate:Node=node.duplicate();check(duplicate.density_cells==cells,"Node duplicate keeps mask")
	check(Detail.encode_mask(cells)==Detail.encode_mask(reopened.density_cells),"encoding deterministic")
	var invalid:=PackedByteArray([1,2,3]);reopened.density_mask=invalid
	check(not reopened.validation_errors().is_empty() and reopened.density_mask==invalid,"corrupt blob is reported and preserved")
	var bounded:=PackedByteArray();bounded.resize(9);bounded.encode_u32(0,Detail.MASK_MAGIC);bounded.encode_u32(4,Detail.MASK_MAX_BYTES+1)
	check(not Detail.decode_mask(bounded).error.is_empty(),"oversized declared payload rejected before decompression")
	var bad_cells:Dictionary={Vector2i(16,0):60};var raw:=var_to_bytes(bad_cells)
	bounded.resize(8);bounded.encode_u32(4,raw.size());bounded.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	check(not Detail.decode_mask(bounded).error.is_empty(),"decoded coordinates validate")
	# Invalid legacy data remains readable and cannot be silently saved as empty.
	node.density_cells=bad_cells;var bad_pack:=PackedScene.new();bad_pack.pack(node)
	var bad_node:Node=bad_pack.instantiate();check(bad_node.density_cells==bad_cells and not bad_node.validation_errors().is_empty(),"invalid legacy mask retained for repair")
	bad_node.free()
	print("GRASS_MASK_STORAGE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"bytes":FileAccess.open(path,FileAccess.READ).get_length()}))
	duplicate.free();reopened.free();node.free();await process_frame;quit(0 if errors.is_empty() else 1)
