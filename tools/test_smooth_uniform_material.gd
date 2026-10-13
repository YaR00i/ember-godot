extends SceneTree
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func run() -> void:
	var source:=Fixture.base();source.top_materials.fill(2)
	var bounds:=Rect2i(32,32,64,64)
	var started:=Time.get_ticks_usec();var fast:=Smooth.build(source,bounds,true,true);var fast_us:=Time.get_ticks_usec()-started
	started=Time.get_ticks_usec();var reference:=Smooth.build(source,bounds,true,false);var reference_us:=Time.get_ticks_usec()-started
	for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:check(fast.terrain.surface_get_arrays(0)[slot]==reference.terrain.surface_get_arrays(0)[slot],"uniform exact mesh slot "+str(slot))
	check(fast.collision_faces==reference.collision_faces and fast.smooth_field.heights==reference.smooth_field.heights,"uniform preserves physical surface")
	# A single different colour just outside the tile must disable the shortcut.
	source.top_materials[source.column_index(97,48)]=1
	check(Smooth._uniform_material(source,bounds)==0,"material halo disables uniform path")
	fast=Smooth.build(source,bounds,true,true);reference=Smooth.build(source,bounds,true,false)
	check(fast.terrain.surface_get_arrays(0)==reference.terrain.surface_get_arrays(0),"mixed halo retains exact legacy path")
	source.top_materials.fill(2);source.top_materials[source.column_index(50,50)]=0
	check(Smooth._uniform_material(source,bounds)==0,"empty palette does not enter uniform shortcut")
	print("SMOOTH_UNIFORM_METRIC fast_ms=",fast_us/1000.0," reference_ms=",reference_us/1000.0)
	print("SMOOTH_UNIFORM ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
