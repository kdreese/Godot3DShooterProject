extends Node


const VERSION := "v0.1"

const CONFIG_PATH := "user://config.cfg"

const DEFAULT_CONFIG := {
	"name": "Guest",
	"address": "localhost",
	"port": 8380,
	"mouse_sensitivity": 0.5,
	"sfx_volume": 1.0,
	"max_players": 8,
}

const MAX_SFX_VOLUME_DB = 0.0


var config := DEFAULT_CONFIG.duplicate(true)
var menu_to_load := "main_menu"
var server_kicked := false


func _ready() -> void:
	randomize()
	load_config()
	process_mode = Node.PROCESS_MODE_ALWAYS


# When the user quits the game, save the game before the engine fully quits
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_config()
		get_tree().quit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (not ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN))) else Window.MODE_WINDOWED
		get_viewport().set_input_as_handled()


func load_config() -> void:
	var config_file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if FileAccess.get_open_error() == ERR_FILE_NOT_FOUND:
		print("No config file found, using default settings")
		return
	else:
		push_warning("Could not open config file for reading! Using default settings")
		return

	var new_config_variant = config_file.get_var()
	config_file.close()

	if typeof(new_config_variant) != TYPE_DICTIONARY:
		push_warning("Config file was corrupted! Using default settings")
		return
	var new_config := new_config_variant as Dictionary

	for key in config.keys():
		if new_config.has(key) and typeof(new_config[key]) == typeof(config[key]):
			var new_value = new_config[key]
			if key == "port":
				new_value = int(clamp(new_value, 0, 65535))
			elif key == "max_players":
				new_value = int(clamp(new_value, 2, 8))
			config[key] = new_value


func save_config() -> void:
	var config_file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if not config_file:
		push_error("Could not open config file for writing!")
		return

	config_file.store_var(config)
	config_file.close()


func update_volume() -> void:
	# Volume is given as a percent, so change that to dB.
	var sound_volume_pct := config["sfx_volume"] as float
	var sounds_bus_index := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sounds_bus_index, MAX_SFX_VOLUME_DB + (20 * log(sound_volume_pct) / log(10)))
