extends SceneTree
## Focused material-editor contract. Only the user:// Pattern copy is saved.
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
var errors: Array[String]=[]
var roles:=PackedStringArray(["","grass","sand","stone"])
var ids:=PackedStringArray(["","cartoon_grass","cartoon_sand","cartoon_stone"])
var material: ShaderMaterial
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
 if not ok:errors.append(message)
func apply_preview(pattern: Resource,_id: String) -> void:
 Materials.update_grass_light_profile(material,1,pattern)
 Materials.set_terrain_depth_profiles(material,roles,ids,{"cartoon_grass":pattern})
func span() -> float:return material.get_meta("ember_grass_light_image").get_pixel(1,3).a
func depth() -> float:return material.get_meta("ember_depth_profiles").get_pixel(1,0).g
func run() -> void:
 if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
 DisplayServer.window_set_size(Vector2i(1440,900))
 var out:="user://ember-tests/grass-ground-material"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
 var original: Pattern=load("res://content/terrain_materials/cartoon_grass.tres")
 check(original.validation_errors().is_empty(),"authored grass validates")
 check(original.pattern_size_m==4.0 and original.depth_mm==2.0,"accepted candidate defaults are 4m/2mm")
 var fixture: Pattern=original.duplicate(true)
 var path:=out.path_join("cartoon_grass.tres")
 check(ResourceSaver.save(fixture,path)==OK,"material copy saves in user storage")
 print("GRASS_CONTROL_PHASE fixture")
 material=ShaderMaterial.new();material.shader=Materials.compact_terrain_bank_depth_shader()
 Materials.set_compact_terrain_roles(material,roles,ids,PackedColorArray(),{"cartoon_grass":fixture})
 Materials.set_terrain_depth_profiles(material,roles,ids,{"cartoon_grass":fixture})
 print("GRASS_CONTROL_PHASE material")
 var before_other: Array=[]
 for slot in [2,3]:before_other.append(material.get_meta("ember_depth_profiles").get_pixel(slot,0).g)
 var dialog:=Dialog.new();root.add_child(dialog);root.add_child(dialog.parameters_panel)
 dialog.position=Vector2(24,20);dialog.size=Vector2(750,700)
 dialog.parameters_panel.position=Vector2(800,20);dialog.parameters_panel.size=Vector2(440,700)
 dialog.theme=preload("res://addons/ember_import/ember_voxel_workshop_theme.gd").build(ThemeDB.get_default_theme());dialog.parameters_panel.theme=dialog.theme
 dialog.pattern_path_override=path
 dialog.light_profile_previewed.connect(apply_preview)
 for i in 5:await process_frame
 check(dialog.open_role("grass"),"existing editor opens material copy")
 print("GRASS_CONTROL_PHASE opened")
 var bank_id: int=material.get_shader_parameter("terrain_depth_bank").get_instance_id()
 print("GRASS_BANK_OPEN ",bank_id," ",material.get_meta("ember_depth_keys"))
 check(dialog._depth_sliders.depth_mm.editable and dialog._depth_sliders.depth_softness.editable,"ground grass depth controls enabled")
 check(not dialog._depth_sliders.form_pull_mm.editable,"tuft form is not edited by optical depth")
 check(not dialog._depth_texture_buttons[0].disabled,"optional grass height image stays editable")
 dialog._finish_sliders.pattern_size_m.value=8.0
 print("GRASS_BANK_SIZE ",material.get_shader_parameter("terrain_depth_bank").get_instance_id()," ",material.get_meta("ember_depth_keys"))
 check(span()==8.0 and dialog._draft.pattern_size_m==8.0,"size slider updates grass-light preview")
 check(material.get_meta("ember_png_lookup_image").get_pixel(1,0).g==8.0,"colour span follows same live edit")
 check(material.get_meta("ember_surface_lookup_image").get_pixel(1,0).r==8.0,"fallback span follows same live edit")
 check(material.get_shader_parameter("terrain_depth_bank").get_instance_id()==bank_id,"size preview reuses height image bank")
 dialog.undo_edit();check(span()==4.0,"size Undo restores material preview")
 dialog.redo_edit();check(span()==8.0,"size Redo restores material preview")
 print("GRASS_CONTROL_PHASE size")
 dialog._depth_sliders.depth_mm.value=0.0
 check(is_zero_approx(depth()),"zero depth disables only the grass depth profile")
 dialog.undo_edit();check(is_equal_approx(depth(),0.002),"depth Undo restores 2mm")
 dialog.redo_edit();check(is_zero_approx(depth()),"depth Redo restores disabled depth")
 dialog._depth_sliders.depth_mm.value=3.0
 check(is_equal_approx(depth(),0.003),"live depth uses metres in bank")
 dialog._depth_sliders.depth_softness.value=5.0
 dialog.undo_edit();check(dialog._draft.depth_softness==4.0,"softness Undo")
 dialog.redo_edit();check(dialog._draft.depth_softness==5.0,"softness Redo")
 check(dialog._save(),"existing Save writes the material copy")
 print("GRASS_CONTROL_PHASE saved")
 var reopened: Pattern=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
 check(reopened!=null and reopened.validation_errors().is_empty(),"fresh saved resource validates")
 check(reopened.pattern_size_m==8.0 and reopened.depth_mm==3.0 and reopened.depth_softness==5.0,"size/depth/softness survive fresh reopen")
 check(dialog.open_role("grass"),"native editor reopens saved copy")
 dialog._finish_sliders.pattern_size_m.value=12.0
 dialog._depth_sliders.depth_mm.value=0.0
 dialog.cancel_edit()
 check(span()==8.0 and is_equal_approx(depth(),0.003),"discard restores scale and depth together")
 var discarded: Pattern=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
 check(discarded.pattern_size_m==8.0 and discarded.depth_mm==3.0,"discard does not write unsaved values")
 check(original.pattern_size_m==4.0 and original.depth_mm==2.0,"author material resource not changed by fixture edits")
 for i in 2:check(is_equal_approx(material.get_meta("ember_depth_profiles").get_pixel(i+2,0).g,before_other[i]),"other material depth amplitude preserved")
 check(dialog.open_role("grass"),"editor ready for native control capture")
 for i in 8:await process_frame
 dialog._parameter_scroll.ensure_control_visible(dialog._depth_sliders.depth_mm)
 for i in 5:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(out.path_join("controls.png"))
 dialog.cancel_edit();dialog.queue_free()
 for i in 3:await process_frame
 print("GRASS_GROUND_MATERIAL ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"saved_copy":ProjectSettings.globalize_path(path),"images":ProjectSettings.globalize_path(out)}))
 quit(0 if errors.is_empty() else 1)
