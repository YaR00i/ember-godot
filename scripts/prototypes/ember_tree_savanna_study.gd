extends "res://scripts/prototypes/ember_tree_maple_study.gd"
## Same Recipe/foliage controller, with the three accepted species as references.
func trial_kind() -> int:return 0
func trial_title() -> String:return "Саванна24"
func trial_short_title() -> String:return "Саванна"
func trial_inputs() -> Dictionary:return Species.savanna()
func trial_field_keys() -> Array[String]:return KEYS
func trial_art() -> String:return Species.SAVANNA_ART
func trial_bark() -> String:return Species.SAVANNA_BARK
func trial_card_size() -> float:return 0.88
func trial_recipe_directory() -> String:return "user://savanna24-lab"
var accepted_maple: Node3D
func prepare() -> void:
	await super.prepare()
	accepted_maple=accepted_reference(Species.maple(7,{"crown_shape":1}),Species.MAPLE_ART,Species.MAPLE_BARK,"AcceptedMaple23Upright")
	choose_species(trial_kind())
func choose_species(kind: int) -> void:
	super.choose_species(kind)
	if accepted_maple!=null:
		accepted_maple.visible=kind==3
		if kind==3:species_roots[3].hide();species_label.text="Клён23 · вытянутая принятая основа · 730"
