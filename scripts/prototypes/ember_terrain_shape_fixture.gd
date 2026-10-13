extends RefCounted
## One ordinary fine16 Source; fixture settings are not gameplay metadata.
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const PROTECTED_REGIONS=[Rect2(1.4,1.1,3.4,2.2),Rect2(4.75,3.15,2.0,1.0)]

static func source() -> EmberTerrainPilotResource:
	var result:=Terrain.new();result.width=128;result.depth=128;result.height_limit=96
	result.palette=PackedColorArray([Color.TRANSPARENT,Color("979184"),Color("d7c08c"),Color("637841")])
	result.palette_surface_roles=PackedStringArray(["","stone","sand","grass"])
	result.palette_material_ids=PackedStringArray(["","cartoon_stone","cartoon_sand","cartoon_grass"])
	for channel: String in Terrain.Sections.CHANNELS:
		var data=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
		data.resize(result.width*result.depth);result.set(channel,data)
	for z in result.depth:
		for x in result.width:
			var p:=Vector2((x+0.5)/16.0,(z+0.5)/16.0)
			var slope:=0.5+0.22*p.x
			var h:=lerpf(0.5,slope,smoothstep(5.1,6.4,p.y))
			var plateau:=Rect2(1.4,1.1,3.4,2.2)
			if plateau.has_point(p):h=2.25
			# Two source-aligned broad faces meet at an explicit crest, crossing
			# the z=4m tile seam. No material-dependent sharpening or new mesh.
			var rock:=maxf(0.0,minf(2.4-absf(p.x-5.75)*2.0,(1.3-absf(p.y-3.65))*3.5))
			h=maxf(h,0.5+rock)
			var slot:=1 if rock>0.02 or plateau.has_point(p) else 3
			var i:=result.column_index(x,z)
			result.heights[i]=roundi(h*16.0);result.top_materials[i]=slot
			result.base_materials[i]=slot;result.cap_depths[i]=2
	return result

static func profile(strength:=1.0,radius:=3,edges:=true,protection:=true) -> Dictionary:
	return {"passes":3,"radius_cells":radius,"strength":strength,"preserve_edges":edges,
		"edge_threshold_m":0.125,"protection_feather_m":0.15,
		"protected_regions":PROTECTED_REGIONS if protection else []}
