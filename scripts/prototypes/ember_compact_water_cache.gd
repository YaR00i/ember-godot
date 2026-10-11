@tool
extends "res://scripts/prototypes/ember_derived_data_cache.gd"
## Existing coast-cache owner; binary transport is shared with terrain geometry.
const ROOT := "user://ember-water-region-cache"
const VERSION := 1
# Independent payload version: existing coast entries remain usable.
const COMPONENT_VERSION := 1
const MAGIC := "EWCACHE1"
const MAX_BYTES := 32 * 1024 * 1024
const BUDGET_BYTES := 256 * 1024 * 1024

func _init() -> void:
	directory = ROOT
	magic = MAGIC
	format_version = VERSION
	extension = ".ewc"
	max_bytes = MAX_BYTES
	packaged_directory = PACKAGED_ROOT.path_join("water")
	packaged_for_directory = ROOT
