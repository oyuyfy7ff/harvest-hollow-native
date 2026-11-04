class_name OfflineState
extends Node
## Offline save state for Harvest Hollow Native.
## Stores progress as JSON in user:// (no network, no server).

const SAVE_PATH := "user://harvest_hollow_save.json"
const SAVE_TMP_PATH := "user://harvest_hollow_save.json.tmp"

var day: int = 1
var coins: int = 0
var player_position: Vector3 = Vector3.ZERO
var plots: Dictionary = {}


func _ready() -> void:
	load_game()


func plant_plot(plot_id: String) -> bool:
	if plots.has(plot_id):
		return false
	plots[plot_id] = {
		"crop": "turnip",
		"planted_day": day,
		"watered": true,
	}
	save_game()
	return true


func harvest_plot(plot_id: String) -> bool:
	if not plots.has(plot_id):
		return false
	plots.erase(plot_id)
	coins += 1
	save_game()
	return true


func save_game() -> void:
	var data := {
		"day": day,
		"coins": coins,
		"player_position": [player_position.x, player_position.y, player_position.z],
		"plots": plots,
	}
	# Write to a temp file first so a crash mid-write can't corrupt the real save.
	var file := FileAccess.open(SAVE_TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot open save file for writing: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var err := DirAccess.rename_absolute(SAVE_TMP_PATH, SAVE_PATH)
	if err != OK:
		push_warning("Cannot finalize save file: %s" % error_string(err))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file is corrupt, starting fresh.")
		return
	var data: Dictionary = parsed

	# JSON numbers come back as float, so convert explicitly.
	day = maxi(1, int(data.get("day", 1)))
	coins = maxi(0, int(data.get("coins", 0)))
	player_position = _read_vector3(data.get("player_position", null))

	plots = {}
	var raw_plots: Variant = data.get("plots", {})
	if typeof(raw_plots) == TYPE_DICTIONARY:
		for key in raw_plots:
			var value: Variant = raw_plots[key]
			if typeof(value) == TYPE_DICTIONARY:
				plots[str(key)] = value
			else:
				plots[str(key)] = {"crop": "turnip", "planted_day": day, "watered": true}


func _read_vector3(value: Variant) -> Vector3:
	if typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if typeof(value) == TYPE_DICTIONARY and value.has("x") and value.has("z"):
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO
