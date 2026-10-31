extends SceneTree
## One-shot authoring of canonical editable Sources. Never runs during paint/runtime.
const Preset = preload("res://addons/ember_import/ember_voxel_stamp_preset.gd")
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Vox = preload("res://scripts/vox_mesher.gd")
var source: EmberVoxelModelResource
var directions := PackedVector3Array()
var errors: Array[String] = []

func _init() -> void:
	for z in range(-1,2):
		for y in range(-1,2):
			for x in range(-1,2):
				if x != 0 or y != 0 or z != 0: directions.append(Vector3(x,y,z).normalized())
	for id in ["daisy","wildflowers","wheat","shell"]:
		if FileAccess.file_exists("res://content/voxel_models/vox_detail_"+id+".tres"):
			printerr("NATURE_BUILD refuses to overwrite an authored Source: ",id);quit(1);return
	make_daisy();publish("daisy","Ромашки")
	make_wildflowers();publish("wildflowers","Полевые цветы")
	make_wheat();publish("wheat","Колосья")
	make_shell();publish("shell","Ракушки")
	print("NATURE_BUILT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"sets":4}))
	quit(0 if errors.is_empty() else 1)

func begin(height: int,palette: PackedColorArray) -> void:
	source = EmberVoxelModelResource.new();source.voxels_per_block=32;source.height_voxels=height
	source.palette=palette;source.physical=false;source.tags=PackedStringArray(["stamp","natural-detail"])
	source.voxels.resize(32*32*height);source.voxel_part_ids.resize(source.voxels.size())

func part(title: String) -> int:
	source.merge_parts.append(title);return source.merge_parts.size()

func paint(cell: Vector3i,slot: int,owner_id: int) -> void:
	var grid:=source.grid_size()
	if cell.x<0 or cell.y<0 or cell.z<0 or cell.x>=grid.x or cell.y>=grid.y or cell.z>=grid.z:return
	var index:=Vox.cell_index(cell.x,cell.y,cell.z,grid.x,grid.z)
	source.voxels[index]=slot;source.voxel_part_ids[index]=owner_id

func pod(title: String,a: Vector3,b: Vector3,width: float,thickness: float,slot: int) -> void:
	var id:=part(title);var center:=(a+b)*0.5;var axis:=(b-a).normalized()
	var u:=axis.cross(Vector3.UP).normalized()
	if u.length_squared()<0.1:u=Vector3.RIGHT
	var v:=axis.cross(u).normalized();var half:=(a.distance_to(b)*0.5)+0.5
	var grid:=source.grid_size()
	for z in grid.z:
		for y in grid.y:
			for x in grid.x:
				var p:=Vector3(x+0.5,y+0.5,z+0.5)-center
				var q:=pow(p.dot(axis)/half,2)+pow(p.dot(u)/width,2)+pow(p.dot(v)/thickness,2)
				if q<=1.0:paint(Vector3i(x,y,z),slot,id)

func leaf(title: String,base: Vector3,end: Vector3) -> void:
	pod(title,base,end,1.65,0.85,2)

func flower(title: String,head: Vector3,petals: int,radius: float,slot: int) -> void:
	pod(title+" · стебель",Vector3(head.x,0,head.z),head,0.85,0.85,1)
	leaf(title+" · лист",Vector3(head.x,7,head.z),Vector3(head.x-5,10,head.z+2))
	for i in petals:
		var angle:=i*TAU/petals
		var dir:=Vector3(cos(angle),0,sin(angle))
		pod(title+" · лепесток "+str(i+1),head+dir*1.6,head+dir*radius,1.9,1.0,slot)
	pod(title+" · сердцевина",head+Vector3(-0.5,0.8,0),head+Vector3(0.5,0.8,0),2.15,1.25,3)

func make_daisy() -> void:
	begin(24,PackedColorArray([Color.TRANSPARENT,Color("47734b"),Color("79a75a"),Color("edb64a"),Color("fff5d7")]))
	flower("Ромашка",Vector3(16,18,16),7,7.0,4)
	leaf("Второй лист",Vector3(16,10,16),Vector3(21,13,15))

func make_wildflowers() -> void:
	begin(25,PackedColorArray([Color.TRANSPARENT,Color("4d7650"),Color("83ab65"),Color("f5cf80"),Color("ab9cdd"),Color("dc94b2")]))
	flower("Сиреневый цветок",Vector3(12,19,13),5,5.5,4)
	flower("Розовый цветок",Vector3(21,14,21),5,4.5,5)

func make_wheat() -> void:
	begin(32,PackedColorArray([Color.TRANSPARENT,Color("8b9550"),Color("bdac5d"),Color("edcc79"),Color("d9b463")]))
	for i in 3:
		var base:=Vector3(12+i*4,0,14+(i%2)*5);var head:=base+Vector3(i-1,23+(i%2)*4,0)
		pod("Стебель "+str(i+1),base,head,0.7,0.7,1)
		leaf("Лист "+str(i+1),base+Vector3(0,8,0),base+Vector3(-5 if i%2==0 else 5,13,1))
		for level in 3:
			for side in [-1,1]:
				var origin:=head+Vector3(0,-5+level*2,0)
				pod("Зерно %d/%d/%d" % [i,level,side],origin,origin+Vector3(side*2.2,2.1,0),0.95,1.2,3 if level>0 else 4)
		pod("Верхушка "+str(i+1),head+Vector3(0,-1,0),head+Vector3(0,3,0),0.85,1.0,3)

func make_shell() -> void:
	begin(9,PackedColorArray([Color.TRANSPARENT,Color("e8c6a4"),Color("f6e2bf"),Color("ca9485"),Color("ddb397")]))
	for rib in 9:
		var id:=part("Створка · ребро "+str(rib+1))
		for z in 25:
			for x in 32:
				var p:=Vector2(x+0.5-16,z+0.5-5);var angle:=atan2(p.x,p.y)
				var r:=p.length();var index:=clampi(floori((angle+1.15)/2.3*9),0,8)
				if absf(angle)>1.15 or index!=rib or r>14.0+0.6*cos(angle*9.0):continue
				var height:=1.0+3.5*sin(clampf(r/15.0,0,1)*PI)
				var local_angle:=fposmod((angle+1.15)/2.3*9,1.0)
				if absf(local_angle-0.5)<0.18:height+=0.8
				for y in range(1,ceili(height)+1):
					paint(Vector3i(x,y,z),2 if absf(local_angle-0.5)<0.22 else 1 if rib%2==0 else 4,id)

func publish(id: String,title: String) -> void:
	source.model_id="vox_detail_"+id;source.display_name=title
	var guides:Array=[]
	for name in source.merge_parts:guides.append(directions.duplicate())
	var roles:=PackedStringArray();roles.resize(source.palette.size())
	source.solid_surface={"version":1,"parts":guides,"occupancy":Solid.occupancy_hash(source.voxels),"roles":roles,"material_ids":roles.duplicate()}
	var validation:=source.validation_errors();validation.append_array(Solid.validation_errors(source.solid_surface,source.merge_parts.size(),source.palette.size()))
	if not validation.is_empty():errors.append(title+str(validation));return
	var source_path:="res://content/voxel_models/"+source.model_id+".tres"
	if ResourceSaver.save(source,source_path)!=OK:errors.append("save "+title);return
	var preset:=Preset.new();preset.display_name=title;preset.kind=Preset.KIND_VOLUME
	preset.geometry=load(source_path)
	if ResourceSaver.save(preset,"res://content/editor/voxel_stamps/"+source.model_id+".tres")!=OK:errors.append("preset "+title)
