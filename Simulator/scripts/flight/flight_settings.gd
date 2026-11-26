class_name FlightSettings
extends RefCounted
## Settings of the flight planner that are kept between runs, in `user://flight_settings.cfg`.

const PATH := "user://flight_settings.cfg"
const DEFAULT_MODEL := "devstral:24b"
## 127.0.0.1, not "localhost": Godot tries the IPv6 address of localhost, which Ollama does not listen on.
const DEFAULT_URL := "http://127.0.0.1:11434"


## {"model": String, "url": String}. A `--llm-model=NAME` or `--llm-url=URL` on the command line wins over the file.
static func load_settings() -> Dictionary:
	var settings := {"model": DEFAULT_MODEL, "url": DEFAULT_URL}
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		settings["model"] = str(file.get_value("llm", "model", DEFAULT_MODEL))
		settings["url"] = str(file.get_value("llm", "url", DEFAULT_URL))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--llm-model="):
			settings["model"] = argument.trim_prefix("--llm-model=")
		elif argument.begins_with("--llm-url="):
			settings["url"] = argument.trim_prefix("--llm-url=")
	return settings


## Saves only the settings given (for example {"model": "devstral:24b"}), keeping the others in the file as they are. A value that is
## only in effect for this run (a command-line override, or an address a test points at) is never written by accident this way.
static func save_settings(settings: Dictionary) -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	for key in settings:
		file.set_value("llm", key, settings[key])
	file.save(PATH)
