@tool
class_name EmberVoxelMigrationBatches
extends RefCounted
## Reviewed, bounded G1 voxel batches. Lists are explicit so a scene edit cannot
## silently expand an already approved migration operation.

const DEFINITIONS := {
	"sandbox": {
		"label": "Sandbox-партия",
		"scene_path": "res://scenes/agent_sandbox.tscn",
		"model_ids": [
			"vox_ms8vsb53",
			"vox_vil_bush",
			"vox_vil_counter",
			"vox_vil_mailbox",
			"vox_vil_planter",
			"vox_vil_sign",
		],
	},
	"fan_town_ready": {
		"label": "fan_town: готовые prefab",
		"scene_path": "res://scenes/fan_town.tscn",
		"model_ids": [
			"vox_fan_barrel",
			"vox_fan_crate_old",
			"vox_fan_door",
			"vox_fan_horseshoe",
			"vox_fan_inn_sign",
			"vox_fan_lantern_stone",
			"vox_fan_window",
		],
	},
}


static func model_ids(batch_id: String) -> Array[String]:
	var result: Array[String] = []
	var definition: Dictionary = DEFINITIONS.get(batch_id, {})
	for value in definition.get("model_ids", []):
		result.append(str(value))
	return result


static func label(batch_id: String) -> String:
	return str((DEFINITIONS.get(batch_id, {}) as Dictionary).get("label", batch_id))


static func entry_matches(entry: Dictionary, batch_id: String) -> bool:
	if str(entry.get("domain", "")) != "voxel" or str(entry.get("kind", "model")) != "model":
		return false
	if not str(entry.get("id", "")) in model_ids(batch_id):
		return false
	var scene_path := str((DEFINITIONS.get(batch_id, {}) as Dictionary).get("scene_path", ""))
	return scene_path.is_empty() or scene_path in entry.get("referenced_in", [])
