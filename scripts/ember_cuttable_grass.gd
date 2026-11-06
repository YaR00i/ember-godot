extends "res://scripts/ember_leaf_pile.gd"
## Same cover flag/pickup/save owner; grass needs a strike rather than a footstep.
func _ready() -> void:
	super._ready()
	monitoring = false
	collision_mask = 0
	# Use the existing grass feature program; do not leave inactive material
	# branches in the collectible tuft's shader. Shared material stays shared.
	for name in ["PileVisual", "CutStubble"]:
		var visual := get_node_or_null(name) as MeshInstance3D
		if visual != null and visual.material_override is ShaderMaterial:
			var material := visual.material_override as ShaderMaterial
			if not material.shader.has_meta("ember_feature_base"):
				EmberVoxelSurfaceMaterials.refresh_terrain_features(material)

func _refresh() -> void:
	super._refresh()
	var stubble := get_node_or_null("CutStubble") as Node3D
	if stubble != null:
		stubble.visible = progress_state != null and progress_state.flags.get(revealed_flag_id,false) == true

func world_hit_feedback() -> String:
	return "Трава скошена — среди стеблей что-то лежит"

func world_cover_action() -> String:
	return "cut_grass"
