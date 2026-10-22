@tool
extends HBoxContainer
## One field in the existing Recipe panel. Part selection is transient UI;
## the density override and its geometry revision use the same Recipe/history.
signal value_changed(value: Dictionary,revision: String)
const Layout=preload("res://addons/ember_import/ember_tree_branch_layout.gd")
var parts: OptionButton
var amount: SpinBox
var _parameters: Dictionary={}
var _seed:=0
var _revision:=""
func _init() -> void:
	parts=OptionButton.new();parts.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parts.fit_to_longest_item=false;parts.clip_text=true;add_child(parts)
	amount=SpinBox.new();amount.min_value=0;amount.max_value=100;amount.step=5;amount.suffix="%";add_child(amount)
	parts.item_selected.connect(func(_index):_sync_amount())
	amount.value_changed.connect(_changed)
func configure(parameters: Dictionary,seed: int) -> void:
	_parameters=parameters;_seed=seed
	var current: String=load("res://scripts/ember_tree_surface.gd").revision(parameters,seed)
	if current!=_revision:
		_revision=current;parts.clear();parts.add_item("Выбери часть кроны");parts.set_item_metadata(0,-1)
		if int(parameters.tree_type)==4:parts.add_item("Верхушка · ствол");parts.set_item_metadata(1,0)
		for branch: Dictionary in Layout.plan(parameters,seed):
			if branch.order!=1:continue
			parts.add_item("Ветвь %d"%branch.id);parts.set_item_metadata(parts.item_count-1,branch.id)
		parts.select(0)
	_sync_amount()
func _sync_amount() -> void:
	var owner:=int(parts.get_selected_metadata())
	amount.editable=owner>=0
	var local: Dictionary=_parameters.tree_leaf_local if _parameters.tree_leaf_revision==_revision else {}
	amount.set_value_no_signal(float(local.get(str(owner),local.get(owner,100))))
func _changed(value: float) -> void:
	var owner:=int(parts.get_selected_metadata())
	if owner<0:return
	var local: Dictionary=_parameters.tree_leaf_local.duplicate(true) if _parameters.tree_leaf_revision==_revision else {}
	local[str(owner)]=int(value);value_changed.emit(local,_revision)
