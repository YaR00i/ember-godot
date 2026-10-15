extends RefCounted
## Derived near-view LAB leaves on the existing saved generator scaffold.
## Source, branch geometry, guide shapes and authoring paint stay immutable.
const Restored=preload("res://scripts/prototypes/ember_smooth_tree_material_fixture.gd")
const Profiles=preload("res://scripts/ember_voxel_material_profiles.gd")

static func build(inputs: Dictionary) -> Dictionary:
	var guide:=Restored.new()
	guide.prepare_shape(inputs.structure.groups,inputs.structure.lines,Vector3(inputs.pivot_bias.x,0,inputs.pivot_bias.y))
	var rng:=RandomNumberGenerator.new();rng.seed=73014
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colours:=PackedColorArray()
	var uvs:=PackedVector2Array();var indices:=PackedInt32Array();var roles:=PackedFloat32Array();var group_normals:=PackedFloat32Array()
	var cards:=0
	for group in guide.cloud_caps.size():
		var cap: Dictionary=guide.cloud_caps[group]
		var parent: Dictionary=guide.cloud_caps[group-group%3]
		var count:=clampi(roundi(cap.radii.x*cap.radii.z*22.0),9,28)
		var branch_axis:=Vector3.RIGHT;var best:=INF
		for line: Dictionary in guide.wood_lines:
			var axis: Vector3=line.b-line.a
			var t:=clampf((cap.centre-line.a).dot(axis)/maxf(axis.length_squared(),0.00001),0,1)
			var distance: float=cap.centre.distance_squared_to(line.a+axis*t)
			if distance<best:best=distance;branch_axis=axis.normalized()
		var heading:=Vector3(branch_axis.x,0,branch_axis.z).normalized()
		if heading.length_squared()<0.1:heading=Vector3(cos(cap.phase),0,sin(cap.phase))
		var side:=Vector3(-heading.z,0,heading.x)
		for i in count:
			var phi: float=float(i)*2.39996323+cap.phase+rng.randf_range(-0.22,0.22)
			var radius:=sqrt((float(i)+0.6)/float(count))*rng.randf_range(0.72,1.04)
			var radial:=heading*cos(phi)+side*sin(phi)
			var centre: Vector3=cap.centre+Vector3(radial.x*cap.radii.x*radius,rng.randf_range(-0.35,0.55)*cap.radii.y,radial.z*cap.radii.z*radius)
			# A few overlapping fixed layers form each fan. The quads never face
			# the camera; tilt diversity keeps gaps natural from below and above.
			var tilt: float=[0.25,0.80,1.28][i%3]+rng.randf_range(-0.14,0.14)
			var normal: Vector3=(radial*sin(tilt)+Vector3.UP*cos(tilt)).normalized()
			# The atlas stem sits at its bottom-left. Its diagonal must point
			# away from the branch, so bare stems do not poke out of the crown.
			var forward: Vector3=(radial-normal*radial.dot(normal)).normalized()
			var across:=forward.cross(normal).normalized()
			var x: Vector3=(forward+across).normalized()
			var y: Vector3=(forward-across).normalized()
			var spin:=rng.randf_range(-0.25,0.25)
			var rotated_x:=x*cos(spin)+y*sin(spin);y=-x*sin(spin)+y*cos(spin);x=rotated_x
			var size:=clampf(minf(cap.radii.x,cap.radii.z)*rng.randf_range(0.82,1.16),0.50,1.15)
			var width:=size*rng.randf_range(0.92,1.15);var height:=size
			var base:=vertices.size()
			var positions: Array[Vector3]=[centre-x*width*0.5-y*height*0.5,centre+x*width*0.5-y*height*0.5,centre+x*width*0.5+y*height*0.5,centre-x*width*0.5+y*height*0.5]
			var coordinates: Array[Vector2]=[Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
			for j in 4:
				var point: Vector3=positions[j]
				var relative: Vector3=(point-parent.centre)/(parent.radii*parent.radii)
				# Group envelope supplies soft light, not a visible sphere. Normal
				# interpolation is independent of both card faces and camera yaw.
				var macro: Vector3=(relative+Vector3.UP*0.75).normalized()
				if macro.length_squared()<0.1:macro=Vector3.UP
				vertices.append(point);normals.append(normal);colours.append(cap.tone);uvs.append(coordinates[j])
				var role: Vector4=Profiles.PROFILES.foliage
				roles.append_array(PackedFloat32Array([role.x,role.y,role.z,0.0]))
				group_normals.append_array(PackedFloat32Array([macro.x,macro.y,macro.z,float(group-group%3)]))
			indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]));cards+=1
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_INDEX]=indices;arrays[Mesh.ARRAY_CUSTOM0]=roles;arrays[Mesh.ARRAY_CUSTOM1]=group_normals
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return {"mesh":mesh,"cards":cards,"triangles":cards*2,"groups":guide.cloud_caps.size()/3,"seed":73014}
