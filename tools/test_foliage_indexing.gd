extends SceneTree
## Native mesh/index/vertex-ID regression. Optional before snapshot is a user://
## or external disposable fixture recorded before the optimization, never a map.
const Fixture = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const Cover = preload("res://scripts/ember_flowered_grass.gd")
const Patch = preload("res://scripts/ember_grass_patch.gd")
const Correspondence = preload("res://scripts/ember_anomaly_correspondence.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String] = []
var output := "user://ember-tests/foliage-indexing"
var recording := false
var before: Dictionary = {}
var result: Dictionary = {}
var scene: Node3D

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: errors.append(label); printerr("FOLIAGE_INDEX_FAIL ",label)
func frames(count: int) -> void:
	for i in count: await process_frame

func expanded(arrays: Array) -> Dictionary:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count: int = indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
	var data: Dictionary = {}
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		if arrays[channel] == null: continue
		var values: Array = []; var stride := 4 if channel == Mesh.ARRAY_TANGENT else 1
		for i in count:
			var index: int = indices[i] if not indices.is_empty() else i
			for k in stride: values.append(arrays[channel][index*stride+k])
		data[channel] = values
	return data

func table_rows(mesh: ArrayMesh, texture: Texture2D) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var image := texture.get_image(); var rows: Dictionary = {}
	for i in points.size():
		var values: Array[Color] = []
		for k in 4:
			var index := i*4+k
			values.append(image.get_pixel(index%Correspondence.WIDTH,index/Correspondence.WIDTH))
		var key := var_to_bytes([points[i],normals[i]]).hex_encode()
		if rows.has(key): check(rows[key] == values,"seam shares morph target")
		rows[key] = values
	return rows

func render_cases(label: String, mesh: ArrayMesh, low: ArrayMesh, aligned: bool, pattern: Resource) -> void:
	var targets: Array[Texture2D] = await Correspondence.prepare(mesh,low,mesh,scene,aligned,true)
	var rows := table_rows(mesh,targets[0])
	if not recording and before.has(label): check(rows == before[label].rows,label+" vertex-ID target rows exact")
	result[label].rows = rows
	var visual := MultiMeshInstance3D.new(); scene.add_child(visual)
	var scatter := MultiMesh.new(); scatter.transform_format=MultiMesh.TRANSFORM_3D;scatter.mesh=mesh;scatter.instance_count=3
	for i in 3: scatter.set_instance_transform(i,Transform3D(Basis.IDENTITY,Vector3((i-1)*0.25,0,0)))
	visual.multimesh = scatter
	var material := Materials.compact_flower_material() if pattern != null else Materials.compact_grass_material()
	Materials.set_compact_terrain_roles(material,PackedStringArray(["","","","grass"]),PackedStringArray(["","","","cartoon_grass"]))
	material.set_shader_parameter("smooth_surface_enabled",true)
	material.set_shader_parameter("painterly_blades",true)
	material.set_shader_parameter("ember_anomaly_prepared",true)
	material.set_shader_parameter("ember_anomaly_targets",targets[0])
	material.set_shader_parameter("ember_anomaly_grass_roots",true)
	material.set_shader_parameter("ember_anomaly_grass_form",1 if pattern == null else 0)
	if pattern != null: Cover.bind(material,pattern,3)
	visual.material_override = material
	var camera := scene.get_node("Camera") as Camera3D
	camera.look_at_from_position(Vector3(0.5,0.42,0.8),Vector3(0,0.13,0))
	for look in [1,2]:
		for centre in [-0.45,0.0,0.45]:
			visual.set_instance_shader_parameter("ember_anomaly_sphere",Vector4(centre,0.08,0,0.27))
			visual.set_instance_shader_parameter("ember_anomaly_band_look",Vector2(0.16,look))
			await frames(6); await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			if look==1 and centre==0.0:
				var background:=picture.get_pixel(0,0);var coverage:=0
				for y in picture.get_height():
					for x in picture.get_width():
						var pixel:=picture.get_pixel(x,y)
						if maxf(absf(pixel.r-background.r),maxf(absf(pixel.g-background.g),absf(pixel.b-background.b)))>0.01:coverage+=1
				check(coverage>128,label+" GPU fixture is visible")
				result[label].coverage=coverage
			var file := output.path_join("%s-%d-%s.png" % [label,look,str(centre)])
			if recording: picture.save_png(file)
			elif FileAccess.file_exists(file):
				var reference := Image.load_from_file(file);var changed:=0;var maximum:=0.0
				for y in picture.get_height():
					for x in picture.get_width():
						var a:=picture.get_pixel(x,y);var b:=reference.get_pixel(x,y)
						var delta:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
						if delta>0.0:changed+=1
						maximum=maxf(maximum,delta)
				check(maximum<=1.0/255.0+0.000001 and changed<100,label+" GPU indexed morph coverage/light exact within 1/255")
				result[label][str([look,centre])] = {"pixels":changed,"max":maximum}
	visual.free()

func run() -> void:
	if DisplayServer.get_name()=="headless": printerr("Native Forward+ required");quit(2);return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output=args[0]
	if args.size()>1:recording=args[1]=="record"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file:=output.path_join("before.bin")
	if not recording and FileAccess.file_exists(file):before=bytes_to_var(FileAccess.get_file_as_bytes(file))
	DisplayServer.window_set_size(Vector2i(640,480));root.size=Vector2i(640,480);Engine.max_fps=60
	scene=Node3D.new();root.add_child(scene);current_scene=scene
	var camera:=Camera3D.new();camera.name="Camera";scene.add_child(camera);camera.make_current()
	var sun:=DirectionalLight3D.new();scene.add_child(sun);sun.rotation_degrees=Vector3(-50,-25,0)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(0.12,0.15,0.18);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4;scene.add_child(environment)
	var patch:=Patch.new();var meshes:Dictionary={"grass":Fixture.grass_blade_mesh(false),"grass-low-generator":Fixture.grass_blade_mesh(true)}
	var patterns:Dictionary={}
	for i in Cover.SETS.size():
		var pattern:Resource=load(Cover.SETS[i][1]);patterns["flower"+str(i)]=pattern;meshes["flower"+str(i)]=Cover.mesh(pattern)
	for label:String in meshes:
		var mesh:ArrayMesh=meshes[label];var arrays:=mesh.surface_get_arrays(0);var geometry:=expanded(arrays)
		var count:int=mesh.surface_get_array_len(0);var indices:int=mesh.surface_get_array_index_len(0)
		result[label]={"geometry":geometry,"vertices":count,"indices":indices,"bounds":mesh.get_aabb()}
		if not recording:
			check(indices>0 and count<indices/2,label+" compact indexed geometry")
			if before.has(label):check(geometry==before[label].geometry and mesh.get_aabb()==before[label].bounds,label+" expanded attributes/order/bounds unchanged")
		if label=="grass" or label=="flower2":await render_cases(label,mesh,patch.prepared_look_mesh(1) if label=="grass" else mesh,label!="grass",patterns.get(label))
	patch.free()
	if recording:FileAccess.open(file,FileAccess.WRITE).store_buffer(var_to_bytes(result))
	var summary:Dictionary={"pass":errors.is_empty(),"errors":errors,"recording":recording}
	for label in result:summary[label]=result[label].duplicate();summary[label].erase("geometry");summary[label].erase("rows")
	FileAccess.open(output.path_join("record.json" if recording else "check.json"),FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	print("FOLIAGE_INDEXING ",JSON.stringify(summary));quit(0 if errors.is_empty() else 1)
