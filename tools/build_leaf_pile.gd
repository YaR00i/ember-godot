extends SceneTree
## Baked flat painted cards; PNG is artwork source, native texture/meshes are derived.
const OUTPUT := "res://prefabs/items/autumn_leaf_pile.scn"
const EFFECT := "res://prefabs/items/autumn_leaf_scatter.scn"
const FLAG := "autumn_leaf_pile_revealed"
const ART := "res://content/material_studies/foliage/autumn_leaf_atlas_v2.png"
const TEXTURE := "res://content/material_studies/foliage/autumn_leaf_atlas_v2.res"

func _init() -> void:
	var image := Image.load_from_file(ART)
	if image == null or image.is_empty() or image.detect_alpha() == Image.ALPHA_NONE: printerr("Leaf atlas requires transparent artwork"); quit(1); return
	var texture := preload("res://scripts/ember_tree_bark_surface.gd").artwork(ART, true)
	if ResourceSaver.save(texture, TEXTURE, ResourceSaver.FLAG_COMPRESS) != OK: quit(1); return
	var material := load("res://materials/ember_painted_tree_foliage.res").duplicate() as ShaderMaterial
	material.shader = load("res://shaders/ember_tree_leaf_cards.gdshader")
	material.set_shader_parameter("painted_leaf_card_albedo", load(TEXTURE))
	material.set_shader_parameter("painted_foliage_paint_reference", Vector3.ONE)
	material.set_shader_parameter("painted_leaf_artwork_strength", 1.0)
	material.set_shader_parameter("painted_leaf_palette_strength", 1.0)
	material.set_shader_parameter("painted_leaf_palette_primary", Color("c7a15c"))
	material.set_shader_parameter("painted_leaf_palette_secondary", Color("9a683c"))
	material.set_shader_parameter("painted_leaf_shadow_strength", 0.4)
	material.set_shader_parameter("surface_response_enabled", false)
	var rng := RandomNumberGenerator.new(); rng.seed = 29102026
	var pile_mesh := SurfaceTool.new(); pile_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	pile_mesh.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var effect := preload("res://scripts/ember_world_break_effect.gd").new()
	effect.name = "AutumnLeafScatter"
	effect.lifetime = 2.8; effect.gravity = 24.0; effect.launch_strength = 0.9; effect.ground_radius_ratio = 0.06
	for variant in 4:
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
		leaf(surface, Transform3D.IDENTITY, variant)
		var batch := MultiMeshInstance3D.new(); batch.name = "Leaves%d" % variant
		batch.multimesh = MultiMesh.new(); batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = surface.commit(); batch.multimesh.instance_count = 60
		batch.material_override = material
		effect.add_child(batch); batch.owner = effect
	for index in 240:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) if index < 192 else rng.randf_range(0.82, 1.15)
		var height := 0.18 + rng.randf() * 0.35
		if index >= 48 and index < 216:
			height += pow(maxf(0.0, 1.0 - radius * radius), 1.1) * 11.0 * rng.randf_range(0.78, 1.0)
		var point := Vector3(cos(angle) * radius * 15.0, height, sin(angle) * radius * 12.0)
		var size := rng.randf_range(6.5, 9.5)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.22, 0.22), rng.randf() * TAU, rng.randf_range(-0.22, 0.22))).scaled(Vector3.ONE * size)
		var transform := Transform3D(basis, point)
		leaf(pile_mesh, transform, index % 4)
		var normalized := transform.scaled(Vector3.ONE / 16.0)
		effect.leaf_transforms.append(normalized)
		effect.get_child(index % 4).multimesh.set_instance_transform(index / 4, normalized)
	var packed := PackedScene.new(); packed.pack(effect)
	var error := ResourceSaver.save(packed, EFFECT)
	effect.free()
	if error != OK: quit(1); return
	var pile := preload("res://scripts/ember_leaf_pile.gd").new()
	pile.name = "AutumnLeafPile"; pile.revealed_flag_id = FLAG
	pile.set_meta("painted_atlas", ART)
	pile.scatter_effect = load(EFFECT)
	pile.collision_layer = 4; pile.collision_mask = 2; pile.monitoring = true
	var visual := MeshInstance3D.new(); visual.name = "PileVisual"
	visual.mesh = pile_mesh.commit(); visual.material_override = material
	pile.add_child(visual); visual.owner = pile
	var shape := CollisionShape3D.new(); shape.name = "BodyShape"; shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(36, 13, 30); shape.position.y = 6.5
	pile.add_child(shape); shape.owner = pile
	var pickup := preload("res://scripts/ember_world_item_3d.gd").new()
	pickup.name = "HiddenPickup"; pickup.pickup_id = "autumn_leaf_bottle"; pickup.item_id = "shore_empty_bottle"
	pickup.available_flag_id = FLAG; pickup.position = Vector3(6, 3, 0); pickup.rotation.z = PI * 0.5
	pile.add_child(pickup); pickup.owner = pile
	packed = PackedScene.new(); packed.pack(pile)
	error = ResourceSaver.save(packed, OUTPUT)
	pile.free()
	print("PASS baked painted pile: 240 flat cards / 480 triangles / all 240 fly in four batches / shared tree shader" if error == OK else "FAIL leaf pile bake")
	quit(0 if error == OK else 1)

func leaf(surface: SurfaceTool, transform: Transform3D, variant: int) -> void:
	var points := [Vector3(-0.5,0,-0.5), Vector3(0.5,0,-0.5), Vector3(0.5,0,0.5), Vector3(-0.5,0,0.5)]
	var uv := [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]
	var tile := Vector2(variant % 2, variant / 2) * 0.5
	var normal := transform.basis.y.normalized()
	for index in [0,1,2,0,2,3]:
		surface.set_normal(normal)
		surface.set_color(Color.WHITE)
		surface.set_custom(1, Color(normal.x, normal.y, normal.z, 0.0))
		surface.set_uv(tile + Vector2.ONE * 0.001 + uv[index] * 0.498)
		surface.add_vertex(transform * points[index])
