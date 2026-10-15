extends "res://scripts/prototypes/ember_tree_spruce_needles_study.gd"
## One real primary subtree, shown independently and reused by the whole tree.
var limb_root: Node3D
var limb_wood: MeshInstance3D
var limb_leaves: MeshInstance3D
var previous_needles: Node3D
var limb_mode:=false
var limb_view:=0
func trial_title() -> String:return "Ель · разветвлённые лапы"
func trial_inputs() -> Dictionary:return Species.spruce_boughs()
func trial_card_options() -> Dictionary:return {"branch_growth":true,"size":trial_card_size(),"needle_sprays":true,"needle_boughs":true}
func trial_field_keys() -> Array[String]:return ["crown_shape","main_branch_count","branch_splits","branch_levels","branch_count_variation","crown_spread","branch_start"]
func trial_recipe_directory() -> String:return "user://spruce25-bough-lab"
func prepare() -> void:
	await super.prepare()
	previous_needles=accepted_reference(Species.spruce_needles(),Species.SPRUCE_ART,Species.SPRUCE_BARK,"PreviousSpruceNeedles")
	limb_root=Node3D.new();limb_root.name="PrimaryBoughSample";smooth_tree.add_child(limb_root)
	limb_wood=MeshInstance3D.new();limb_root.add_child(limb_wood)
	limb_leaves=MeshInstance3D.new();limb_root.add_child(limb_leaves);limb_root.hide()
	var column:=species_panel.get_child(0)
	for child in column.get_children():
		if not child is Button:continue
		if child.text=="A · пробный объём":child.text="A · предыдущая ель"
		elif child.text in ["Одна хвойная плоскость","Группа · 6 плоскостей"]:child.hide()
	for pair in [["Лапа · сверху",0],["Лапа · сбоку",1],["Лапа · каркас",2]]:
		var button:=Button.new();button.text=pair[0];column.add_child(button);column.move_child(button,10+int(pair[1]));button.pressed.connect(show_limb.bind(pair[1]))
	choose_species(trial_kind())
func choose_species(kind: int) -> void:
	super.choose_species(kind)
	if previous_needles!=null:previous_needles.hide()
	if limb_root==null:return
	limb_root.hide()
	if kind!=trial_kind():limb_mode=false
	elif limb_mode:_refresh_limb()
func set_birch_revision(revision: int) -> void:
	limb_mode=false;super.set_birch_revision(revision)
func set_species_view(view: int) -> void:
	var was_limb:=limb_mode
	limb_mode=false
	if limb_root!=null:limb_root.hide()
	if was_limb:choose_species(trial_kind())
	super.set_species_view(view)
func show_canopy_reference() -> void:
	if previous_needles==null:return
	limb_mode=false;choose_species(trial_kind());birch_root.hide();previous_needles.show();set_species_view(1)
	species_label.text="Предыдущая ель · отклонённая проба"
func show_limb(view: int) -> void:
	limb_view=clampi(view,0,2);limb_mode=true;choose_species(trial_kind())
func _refresh_limb() -> void:
	var limb:=Species.spruce_limb(birch_inputs,1)
	birch_root.hide();limb_root.show();limb_root.position=birch_root.position+Vector3(25,0,0)
	limb_wood.mesh=PaintedBark.mesh(limb.wood,birch_inputs.structure,birch_inputs.pivot_bias)
	limb_wood.material_override=birch_wood.material_override
	limb_leaves.mesh=limb.leaves.mesh;limb_leaves.material_override=birch_painted;limb_leaves.visible=limb_view!=2 and limb.leaves.cards>0
	var bounds: AABB=limb.wood.get_aabb()
	if limb.leaves.cards>0:bounds=bounds.merge(limb.leaves.mesh.get_aabb())
	var centre: Vector3=limb_root.global_transform*bounds.get_center()
	var branch: Dictionary=birch_inputs.layout[1]
	var across: Vector3=((branch.path[-1] as Vector3)-(branch.path[0] as Vector3)).cross(Vector3.UP).normalized()
	if across.length_squared()<0.1:across=Vector3.RIGHT
	var distance:=maxf(bounds.size.length()*1.25,1.5)
	var camera: Camera3D=follow_camera._cam;camera.fov=42
	camera.global_position=centre+(Vector3.UP if limb_view==0 else (across+Vector3.UP*0.10).normalized())*distance
	camera.look_at(centre,Vector3.FORWARD if limb_view==0 else Vector3.UP)
	species_label.text="Одна лапа · "+["сверху","сбоку","каркас"][limb_view]+"\n%d ветвей · %d плоскостей"%[limb.layout.size(),limb.leaves.cards]
