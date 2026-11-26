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


static func save_settings(settings: Dictionary) -> void:
	var file := ConfigFile.new()
	file.set_value("llm", "model", settings["model"])
	file.set_value("llm", "url", settings["url"])
	file.save(PATH)
