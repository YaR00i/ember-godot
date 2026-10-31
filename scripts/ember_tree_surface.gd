extends RefCounted
## A published tree surface belongs to the same voxel Source. Only bounded
## support geometry is read at runtime; editor recipes/generators are not run.
const Geometry=preload("res://scripts/ember_tree_surface_geometry.gd")
const Bark=preload("res://scripts/ember_tree_bark_surface.gd")
const Species=preload("res://scripts/ember_tree_species.gd")
const Profiles=preload("res://scripts/ember_voxel_material_profiles.gd")
const Provider=preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const CONTRACT:="painted-tree-surface-v2-shared-shaders"
const LEAF_BASE:="res://materials/ember_painted_tree_foliage.res"
static var _meshes: Dictionary={}

static func render_contract(model: Dictionary) -> String:
	# Material-only publication: old oak prefabs must refresh even though their
	# canonical Source/geometry did not change. Other species keep their contract.
	var data: Dictionary=model.get("treeSurface",{})
	return CONTRACT+":oak-bark-v3-painted" if data.get("settings",{}).get("tree_type",-1)==1 else CONTRACT

static func refresh_material_matches(original: Material,expected: Material,model: Dictionary,surface: int) -> bool:
	# Reloaded prefab materials have distinct Resource identities. Compare their
	# actual inputs, retaining the scene refresh guard against hand-edited materials.
	if not active(model) or model.treeSurface.settings.tree_type!=1 or not original is ShaderMaterial or not expected is ShaderMaterial:return false
	if original.shader==null or expected.shader==null or original.shader.code!=expected.shader.code:return false
	if original.render_priority!=expected.render_priority or original.next_pass!=expected.next_pass or original.resource_local_to_scene!=expected.resource_local_to_scene:return false
	var properties: Dictionary={}
	for material in [original,expected]:
		for property in material.get_property_list():
			if str(property.name).begins_with("shader_parameter/"):properties[property.name]=true
	for key in properties:
		var a: Variant=original.get(key);var b: Variant=expected.get(key)
		if a is Texture2D and b is Texture2D:
			if _same_texture(a,b):continue
			if surface==0 and model.treeSurface.settings.tree_type==1 and key=="shader_parameter/painted_bark_albedo":
				if _same_texture(a,Bark.artwork("res://content/material_studies/trees/bark_species_v1/oak-v2-calm.png")) and _same_texture(b,Bark.artwork(Species.BARK_ART[1])):continue
			return false
		# Text scene serialization rounds shader scalars; use the same bounded
		# numeric equivalence as the existing tree Source roundtrip checks.
		if not same_values(a,b):return false
	return true

static func _same_texture(a: Texture2D,b: Texture2D) -> bool:
	var x:=a.get_image();var y:=b.get_image()
	return x!=null and y!=null and x.get_width()==y.get_width() and x.get_height()==y.get_height() and x.get_format()==y.get_format() and x.has_mipmaps()==y.has_mipmaps() and x.get_data()==y.get_data()

static func occupancy_hash(voxels: PackedByteArray) -> String:
	var occupied:=voxels.duplicate()
	for index in occupied.size():occupied[index]=mini(occupied[index],1)
	return occupied.hex_encode().sha256_text()

static func revision(parameters: Dictionary,seed: int) -> String:
	var values: Array=[seed]
	for key in ["tree_type","generation_version","height","density","trunk_width","crown_shape","crown_spread","branch_curve","branch_thickness","branch_taper","branch_start","root_flare","main_branch_count","branch_splits","branch_levels","branch_count_variation"]:values.append(parameters.get(key))
	return JSON.stringify(values).sha256_text()

static func publish(built: Dictionary,parameters: Dictionary,seed: int) -> void:
	var source: EmberVoxelModelResource=built.geometry
	var settings:=parameters.duplicate(true)
	if settings.tree_leaf_revision!=revision(settings,seed):settings.tree_leaf_local={}
	source.tree_surface={"version":1,"structure":built.structure.duplicate(true),"settings":settings,
		"seed":seed,"pivot":built.pivot_bias,"occupancy":occupancy_hash(source.voxels),
		"paint_hash":source.voxels.hex_encode().sha256_text(),"paint_palette":source.palette.duplicate(),"paint_indices":source.voxels.compress(FileAccess.COMPRESSION_ZSTD)}
	source.material=Profiles.with_rim(source.material,"bark",settings.tree_rim_enabled,settings.tree_wood_rim/100.0)
	source.material=Profiles.with_rim(source.material,"foliage",settings.tree_rim_enabled,settings.tree_leaf_rim/100.0)

static func settings_errors(p: Dictionary) -> Array[String]:
	var errors: Array[String]=[]
	if p.has("plant_kind"):
		if p.plant_kind!="shrub":errors.append("invalid branch plant kind")
		var scale: Variant=p.get("shrub_leaf_scale")
		if (not scale is float and not scale is int) or not is_finite(float(scale)) or scale<0.15 or scale>0.65:errors.append("invalid shrub leaf scale")
	var kind: Variant=p.get("tree_type")
	if not kind is int or kind<0 or kind>=5:return ["invalid painted tree species"]
	if p.get("painted_tree")!=true or p.get("generation_version")!=[24,21,22,23,25][kind]:errors.append("tree surface requires matching painted species/version")
	if p.get("density")!=16:errors.append("painted tree supports require density 16")
	var normalized:=Provider.normalize(p)
	for key in ["height","trunk_width","crown_shape","crown_spread","branch_curve","branch_thickness","branch_taper","branch_start","root_flare","main_branch_count","branch_splits","branch_levels","branch_count_variation"]:
		var value: Variant=p.get(key)
		if not value is int or value!=normalized.get(key):errors.append("invalid tree geometry control "+key)
	for key in ["bark_color","foliage_color"]:
		if not p.get(key) is Color or not Vector4(p[key].r,p[key].g,p[key].b,p[key].a).is_finite():errors.append("invalid tree colour "+key)
	if p.has("tree_leaf_secondary_color"):
		var colour: Variant=p.tree_leaf_secondary_color
		if not colour is Color or not Vector4(colour.r,colour.g,colour.b,colour.a).is_finite():errors.append("invalid secondary leaf colour")
	if p.has("tree_leaf_palette_strength"):
		var strength: Variant=p.tree_leaf_palette_strength
		if (not strength is int and not strength is float) or not is_finite(float(strength)) or strength<0 or strength>100:errors.append("invalid leaf palette strength")
	for key in ["tree_leaf_density","tree_leaf_depth","tree_leaf_receive","tree_wood_rim","tree_leaf_rim"]:
		var value: Variant=p.get(key)
		if (not value is float and not value is int) or not is_finite(float(value)) or float(value)<0 or float(value)>100:errors.append("invalid tree surface "+key)
	if not p.get("tree_rim_enabled") is bool or not p.get("tree_leaf_local") is Dictionary:errors.append("invalid tree surface controls")
	var saved_revision: Variant=p.get("tree_leaf_revision")
	if not saved_revision is String or (not saved_revision.is_empty() and (saved_revision.length()!=64 or not saved_revision.is_valid_hex_number())):errors.append("invalid local crown revision")
	if p.get("tree_leaf_local") is Dictionary:
		if p.tree_leaf_local.size()>128:errors.append("too many local crown parts")
		for key in p.tree_leaf_local:
			var amount: Variant=p.tree_leaf_local[key]
			if not str(key).is_valid_int() or int(key)<0 or (not amount is int and not amount is float) or not is_finite(float(amount)) or float(amount)<0 or float(amount)>100:errors.append("invalid local crown density")
	return errors

static func validation_errors(data: Dictionary) -> Array[String]:
	var errors: Array[String]=[]
	if data.is_empty():return errors
	if data.get("version")!=1 or not data.get("structure") is Dictionary or not data.get("settings") is Dictionary:
		return ["invalid tree surface version or support record"]
	errors.append_array(Provider.structure_errors(data.structure));errors.append_array(settings_errors(data.settings))
	if not data.get("pivot") is Vector2i or data.pivot!=data.structure.get("pivot_bias") or not data.get("seed") is int or int(data.get("seed",-1))<0:errors.append("invalid tree surface pivot/seed")
	for key in ["occupancy","paint_hash"]:
		if not data.get(key) is String or not str(data[key]).is_valid_hex_number() or str(data[key]).length()!=64:errors.append("invalid tree surface "+key)
	if not data.get("paint_palette") is PackedColorArray or data.paint_palette.size()<2 or data.paint_palette.size()>256:errors.append("invalid tree paint palette")
	if not data.get("paint_indices") is PackedByteArray or data.paint_indices.is_empty() or data.paint_indices.size()>Provider.MAX_STORAGE_CELLS:errors.append("invalid tree paint reference")
	return errors

static func same_values(a: Variant,b: Variant) -> bool:
	# Resource text stores float values with finite precision. Bytes, IDs and
	# occupancy remain exact; support coordinates tolerate only that roundtrip.
	if a is float and b is float:return absf(a-b)<=0.000001
	if a is Vector3 and b is Vector3:return a.distance_to(b)<=0.000001
	if a is Color and b is Color:return a.is_equal_approx(b)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same_values(a[key],b[key]):return false
		return true
	if (a is Array or a is PackedColorArray) and (b is Array or b is PackedColorArray):
		if a.size()!=b.size():return false
		for i in a.size():
			if not same_values(a[i],b[i]):return false
		return true
	return a==b

static func active(model: Dictionary) -> bool:
	var data: Dictionary=model.get("treeSurface",{})
	if data.is_empty():return false
	# Geometry edits keep the authored voxel result; palette/paint edits retain
	# the branch surface. No stale decorative surface may hide a sculpted voxel.
	return str(data.occupancy)==occupancy_hash(PackedByteArray(model.get("voxels",[])))

static func build(model: Dictionary) -> ArrayMesh:
	var data: Dictionary=model.treeSurface;var p: Dictionary=data.settings
	var key: int=hash([render_contract(model),data,model.get("palette"),model.get("voxels")])
	if _meshes.has(key):return _meshes[key].duplicate() as ArrayMesh
	var structure: Dictionary=data.structure
	var layout:=Geometry.branches(structure)
	var offset:=Vector3(data.pivot.x,0,data.pivot.y)
	var kind:=int(p.tree_type);var density:=float(p.density)
	var wood:=Bark.mesh(Geometry.rounded_crown_wood(layout,offset,density),structure,data.pivot)
	var painted: bool=PackedByteArray(model.voxels).hex_encode().sha256_text()!=str(data.paint_hash) or palette_changed(VoxMesher._model_colors(model),data.paint_palette)
	if painted:wood=painted_wood(wood,model,data)
	var leaves:=leaf_layout(model)
	var result:=ArrayMesh.new()
	var bark_material:=Bark.material(structure,data.pivot,Species.BARK_ART[kind])
	var reference:=Species.accepted_parameters(kind)
	var bark_colour: Color=p.bark_color;var bark_reference: Color=reference.bark_color
	bark_material.set_shader_parameter("painted_bark_tint",Color(bark_colour.r/maxf(bark_reference.r,0.01),bark_colour.g/maxf(bark_reference.g,0.01),bark_colour.b/maxf(bark_reference.b,0.01)))
	bark_material.set_shader_parameter("painted_bark_source_paint",painted)
	append_surface(result,wood,"tree_bark",bark_material)
	if leaves.cards>0:
		var material:=load(LEAF_BASE).duplicate() as ShaderMaterial
		material.shader=load("res://shaders/ember_tree_leaf_cards.gdshader")
		material.set_shader_parameter("painted_leaf_card_albedo",Bark.artwork(Species.LEAF_ART[kind],true))
		material.set_shader_parameter("painterly_grass_low",lerpf(1.0,float(material.get_shader_parameter("painterly_grass_low")),p.tree_leaf_depth/100.0))
		material.set_shader_parameter("painted_leaf_shadow_strength",p.tree_leaf_receive/100.0)
		if float(p.get("tree_leaf_palette_strength",0))>0.0:
			material.set_shader_parameter("painted_leaf_palette_strength",float(p.tree_leaf_palette_strength)/100.0)
			material.set_shader_parameter("painted_leaf_palette_primary",p.foliage_color)
			material.set_shader_parameter("painted_leaf_palette_secondary",p.get("tree_leaf_secondary_color",p.foliage_color.darkened(0.35)))
		var pigment: Color=p.foliage_color.srgb_to_linear();var pigment_reference: Color=reference.foliage_color.srgb_to_linear()
		var mean: Vector3=material.get_shader_parameter("painted_foliage_paint_reference")
		material.set_shader_parameter("painted_foliage_paint_reference",mean/Vector3(maxf(pigment.r,0.0001)/maxf(pigment_reference.r,0.0001),maxf(pigment.g,0.0001)/maxf(pigment_reference.g,0.0001),maxf(pigment.b,0.0001)/maxf(pigment_reference.b,0.0001)))
		append_surface(result,leaves.mesh,"tree_leaves",material)
	result.set_meta("tree_surface_contract",render_contract(model))
	result.set_meta("tree_leaf_cards",leaves.cards)
	if _meshes.size()>=8:_meshes.clear()
	_meshes[key]=result
	return result.duplicate() as ArrayMesh

static func leaf_layout(model: Dictionary) -> Dictionary:
	# Same deterministic supports and thinning as the accepted smooth projection.
	var data: Dictionary=model.treeSurface;var p: Dictionary=data.settings
	var layout:=Geometry.branches(data.structure)
	var options:=Species.card_options(int(p.tree_type))
	if p.get("plant_kind","")=="shrub":options["size"]*=float(p.shrub_leaf_scale)
	var full:=Geometry.crown_cards(layout,data.structure,Vector3(data.pivot.x,0,data.pivot.y),float(p.density),int(data.seed),options)
	var factors: Dictionary={}
	for owner in p.tree_leaf_local:factors[int(owner)]=float(p.tree_leaf_local[owner])/100.0
	return Geometry.thin_crown_cards(full,p.tree_leaf_density/100.0,factors)

static func painted_wood(mesh: ArrayMesh,model: Dictionary,data: Dictionary) -> ArrayMesh:
	var arrays:=mesh.surface_get_arrays(0)
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var size:=VoxMesher.ember_grid_size(model);var density:=VoxMesher.voxels_per_block(model)
	var voxels:=PackedByteArray(model.voxels)
	var original: PackedByteArray=data.paint_indices.decompress(voxels.size(),FileAccess.COMPRESSION_ZSTD)
	var palette:=VoxMesher._model_colors(model);var before: PackedColorArray=data.paint_palette
	for i in colors.size():
		# Support meshes are trunk-centred; Source voxels use a positive grid.
		var cell:=Vector3i((arrays[Mesh.ARRAY_VERTEX][i] as Vector3)*density)+Vector3i(size.x/2,0,size.z/2)
		var found:=-1
		for radius in 3:
			for y in range(cell.y-radius,cell.y+radius+1):
				for z in range(cell.z-radius,cell.z+radius+1):
					for x in range(cell.x-radius,cell.x+radius+1):
						if x<0 or y<0 or z<0 or x>=size.x or y>=size.y or z>=size.z:continue
						var index:=x+size.x*(z+size.z*y)
						if voxels[index]>0:found=index;break
					if found>=0:break
				if found>=0:break
			if found>=0:break
		if found<0 or original.size()!=voxels.size():continue
		var old: Color=Color("#"+before[int(original[found])].to_html(false)).srgb_to_linear();var colour: Color=palette[int(voxels[found])].srgb_to_linear()
		var base:=colors[i].srgb_to_linear()
		colors[i]=Color(base.r*colour.r/maxf(old.r,0.0001),base.g*colour.g/maxf(old.g,0.0001),base.b*colour.b/maxf(old.b,0.0001)).linear_to_srgb()
	arrays[Mesh.ARRAY_COLOR]=colors
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mesh.surface_get_format(0));return result

static func palette_changed(a: PackedColorArray,b: PackedColorArray) -> bool:
	if a.size()<b.size():return true
	# VoxMesher expands the authored palette to 256 entries and supplies its own
	# transparent index zero; neither is a user paint edit.
	for i in range(1,b.size()):
		if a[i].to_html(false)!=b[i].to_html(false):return true
	return false

static func append_surface(target: ArrayMesh,mesh: ArrayMesh,name: String,material: ShaderMaterial) -> void:
	# Copy Godot's serialized surface buffers, as Resource duplication does.
	# Decoding/re-encoding normals/tangents quantizes them a second time and
	# changes the accepted lighting. This property is covered by parity tests.
	var surfaces: Array=target.get("_surfaces")
	surfaces.append((mesh.get("_surfaces") as Array)[0])
	target.set("_surfaces",surfaces)
	var index:=target.get_surface_count()-1
	target.surface_set_name(index,name);target.surface_set_material(index,material)

static func apply_materials(mesh: ArrayMesh,material: Dictionary) -> void:
	for index in mesh.get_surface_count():
		if mesh.surface_get_name(index) not in ["tree_bark","tree_leaves"]:continue
		var applied:=mesh.surface_get_material(index).duplicate() as ShaderMaterial
		Profiles.apply_rim(applied,material)
		var rim:=Profiles.rim_parameters(material,"bark" if mesh.surface_get_name(index)=="tree_bark" else "foliage")
		applied.set_shader_parameter("object_style_rim_enabled",rim.enabled)
		applied.set_shader_parameter("object_style_rim_strength",rim.strength)
		mesh.surface_set_material(index,applied)
