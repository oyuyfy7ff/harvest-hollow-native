class_name OfflineState
extends Node

const SAVE_PATH := "user://harvest_hollow_save.json"

var day: int = 1
var coins: int = 0
var player_position := Vector3(0.0, 0.0, 0.0)
var plots: Dictionary = {}

func _ready() -> void:
    load_game()

func plant_plot(plot_id: String) -> void:
    plots[plot_id] = {"crop": "turnip", "planted_day": day, "watered": true}
    save_game()

func harvest_plot(plot_id: String) -> bool:
    if not plots.has(plot_id):
        return false
    plots.erase(plot_id)
    coins += 1
    save_game()
    return true

func save_game() -> void:
    var payload := {
        "day": day,
        "coins": coins,
        "player_position": [player_position.x, player_position.y, player_position.z],
        "plots": plots,
    }
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(payload))

func load_game() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if not file:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    day = int(parsed.get("day", 1))
    coins = int(parsed.get("coins", 0))
    var position: Array = parsed.get("player_position", [0.0, 0.0, 0.0])
    if position.size() >= 3:
        player_position = Vector3(float(position[0]), float(position[1]), float(position[2]))
    plots = parsed.get("plots", {})
