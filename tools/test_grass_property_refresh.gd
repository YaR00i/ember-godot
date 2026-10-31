extends SceneTree
## Exercise the property-list path used by Godot's scene tree/inspector while
## derived nodes are published. It must not rescan an unchanged full mask.
const Patch=preload("res://scripts/ember_grass_patch.gd")
func _initialize():run.call_deferred()
func run():
	var patch:=Patch.new();var mask:Dictionary={}
	for z in 16:
		for x in 16:mask[Vector2i(x,z)]=64.0
	patch.density_cells=mask
	var began:=Time.get_ticks_usec()
	for i in 5000:patch.get_property_list()
	var elapsed:=Time.get_ticks_usec()-began
	# Leave headroom for a shared machine; the original path takes about1.7s.
	var passed:=elapsed<800000
	print("GRASS_PROPERTY_REFRESH ",JSON.stringify({"pass":passed,"elapsed_us":elapsed,"refreshes":5000}))
	patch.free();quit(0 if passed else 1)
