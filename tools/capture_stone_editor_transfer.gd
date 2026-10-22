extends "res://tools/capture_soil_editor_transfer.gd"
const StoneRecipe=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
const PaintBake=preload("res://scripts/ember_material_look_bake.gd")
const PixelBake=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")

func _init() -> void:
	target_id="cartoon_stone";target_role="stone";target_slot=1;target_span=2.4;target_role_code=-4.0
	saved_pattern_file="saved-stone.tres";result_prefix="STONE_EDITOR"

func colour_variants() -> Array[Image]:
	var master:=StoneRecipe.painted_image()
	return [master,PaintBake.calm_variant(master,256,0.65),PixelBake.pixel_image(master,16)]

func camera_specs() -> Array:
	return [[Vector3(2.4,1.7,2.9),Vector3(0.9,1.0,2.3)],[Vector3(3.1,1.1,4.0),Vector3(2.4,2.5,4.5)]]

func material_base(_look: int,production: ShaderMaterial) -> ShaderMaterial:
	# Main matrix uses the actual normal editor/runtime material. The historical
	# 4cm POM is checked separately, without silently promoting it to production.
	return production

func legacy_shader_for(current: Shader,code: String) -> Shader:
	# No shader change in this slice. Verify exact frozen source, then keep the
	# existing compiled resource; a new binary adds an irrelevant rounding delta.
	check(current.code==code,"runtime shader source is byte-identical to frozen pre-transfer shader")
	return current

func reference_pattern_material(current: ShaderMaterial,accepted: Resource,colour: Image) -> ShaderMaterial:
	# Replay the stored LAB colour recipe through the same unmodified renderer.
	# Production has zero stone relief; no probe-only shader macro is required.
	return road_material(current,colour,{"slot":target_slot,"material_id":target_id,"pattern":accepted,"span_m":target_span})

func previous_pattern_material(current: ShaderMaterial,old: Resource) -> ShaderMaterial:
	var previous:=current.duplicate() as ShaderMaterial
	var terrain=scene._projection.document
	Materials.set_compact_terrain_roles(previous,terrain.palette_surface_roles,terrain.palette_material_ids,terrain.palette,{target_id:old})
	return previous

func depth_control_material() -> ShaderMaterial:
	var control: ShaderMaterial=scene.material_variants[0]
	check(control.get_shader_parameter("material_depth_height")==scene.height_texture,"historical POM retains its original height")
	check(is_equal_approx(control.get_shader_parameter("material_depth_amplitude_m"),0.04),"historical POM retains 4cm")
	check(control.get_shader_parameter("material_depth_steps")==32,"historical POM retains32 steps")
	check(current_materials[0].shader==scene._projection._ground_material.shader,"normal runtime shader is unchanged")
	return control
