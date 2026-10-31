extends SceneTree
## Only tree look preparation, cold/warm reuse and the first visible switch.
const Bake=preload("res://scripts/ember_tree_look_bake.gd")
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
    if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
    var args=OS.get_cmdline_user_args()
    Bake.cache_directory=args[0] if args.size()>0 else "user://ember-tests/tree-looks-%d"%Time.get_ticks_usec()
    var source_path="res://content/voxel_models/vox_painted_oak.tres"
    var source_hash=FileAccess.get_sha256(source_path)
    var stage=Node3D.new();root.add_child(stage)
    var trees=[]
    var startup=[]
    for i in 2:
        var started=Time.get_ticks_usec()
        var tree=load("res://prefabs/voxels/vox_painted_oak.tscn").instantiate();stage.add_child(tree);tree.set_world_look(0);trees.append(tree)
        startup.append((Time.get_ticks_usec()-started)/1000.0)
    var stats=[]
    var map_a:=EmberMapLoader.new();map_a.voxel_light_cell_m=0.125
    var map_b:=EmberMapLoader.new();map_b.voxel_light_cell_m=0.25
    var original_signature:Dictionary=Grove.fingerprint(trees[0],stage)
    for look in [1,2,0,1,2]:
        var started=Time.get_ticks_usec()
        for tree in trees:tree.set_world_look(look)
        var command_ms=(Time.get_ticks_usec()-started)/1000.0
        check(command_ms<50.0,"first tree switch uses prepared geometry")
        if look>0:
            check(trees[0].get_node("Mesh").mesh.get("_surfaces")==trees[1].get_node("Mesh").mesh.get("_surfaces"),"same Source yields same geometry")
            check(trees[0].get_node("Mesh").mesh==trees[1].get_node("Mesh").mesh,"prepared geometry is shared, not copied per tree")
        var shared:Mesh=trees[0].get_node("Mesh").mesh
        var before:Variant=shared.surface_get_material(0).get_shader_parameter("voxel_light_cell")
        trees[0].apply_voxel_light_settings(map_a);trees[1].apply_voxel_light_settings(map_b)
        check(trees[0].get_node("Mesh").mesh==shared,"lighting never duplicates geometry")
        check(trees[0].get_node("Mesh").get_active_material(0)!=trees[1].get_node("Mesh").get_active_material(0),"instance lighting remains independent")
        check(trees[0].get_node("Mesh").get_active_material(0).get_shader_parameter("voxel_light_cell")==0.125 and trees[1].get_node("Mesh").get_active_material(0).get_shader_parameter("voxel_light_cell")==0.25,"different maps keep different light cells")
        check(shared.surface_get_material(0).get_shader_parameter("voxel_light_cell")==before,"published/cache material remains unchanged")
        check(Grove.fingerprint(trees[0],stage)==original_signature,"look and derived lighting are not manual author edits")
        stats.append({"look":look,"command_ms":command_ms})
    check(Bake.builds==2 or Bake.builds==0 and Bake.disk_hits==2,"identical trees share preparation and a fresh process reuses disk")
    if args.has("--warm"):check(Bake.builds==0 and Bake.disk_hits==2,"fresh process loads both prepared looks without rebuilding")
    check(trees[0].get_node("Mesh").mesh.get_faces().size()/3==338328,"accepted voxel tree shape retained")
    check(FileAccess.get_sha256(source_path)==source_hash,"Source remains unchanged")
    trees[0].notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
    check(trees[0].get_node("Mesh").mesh==trees[0]._tree_meshes[0] and trees[0].get_node("Mesh").get_surface_override_material(0)==null,"native save strips derived geometry/material overrides")
    trees[0].notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
    for tree in trees:tree.set_meta(PlanMarker(),{"region":"test","slot":tree.name});tree.owner=stage
    var snapshot:PackedScene=Grove.snapshot(stage)
    var saved:="user://ember-tests/shared-tree-snapshot.scn";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saved.get_base_dir()))
    check(ResourceSaver.save(snapshot,saved,ResourceSaver.FLAG_COMPRESS)==OK and FileAccess.get_file_as_bytes(saved).size()<65536,"recovery stores prefab references rather than per-instance meshes")
    var source=load(source_path)
    var ordinary:Dictionary=source.to_definition().model
    var packed:Dictionary=source.to_definition(true).model
    for key in ordinary:
        check(ordinary[key]==(Array(packed[key]) if ordinary[key] is Array else packed[key]),"packed snapshot preserves field "+key)
    var original_key=Bake.cache_key(packed,1)
    var edited=source.duplicate_model();edited.tree_surface.settings.tree_leaf_density-=1
    check(Bake.cache_key(edited.to_definition(true).model,1)!=original_key,"leaf edits invalidate the derived mesh")
    edited=source.duplicate_model();edited.palette[1]=Color.MAGENTA
    check(Bake.cache_key(edited.to_definition(true).model,1)!=original_key,"paint edits invalidate the derived mesh")
    var remembered:Dictionary=Bake.prepare(source,trees[0]._tree_meshes[0])
    source.notify_geometry_changed(PackedInt32Array())
    check(not Bake._prepared_sources.has(source.get_instance_id()),"authoring change invalidates fast source binding")
    var restored:Dictionary=Bake.prepare(source,trees[0]._tree_meshes[0])
    check(restored[1]==remembered[1] and restored[2]==remembered[2],"unchanged source rebinds the same immutable geometry")
    print("TREE_LOOK_PREPARATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"startup_ms":startup,"stats":stats,"builds":Bake.builds,"disk_hits":Bake.disk_hits}))
    map_a.free();map_b.free();stage.free();quit(0 if errors.is_empty() else 1)
func PlanMarker()->StringName:return &"_ember_grove_member"
