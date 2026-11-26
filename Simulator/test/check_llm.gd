extends SceneTree
## Live check against a running Ollama server (not part of the headless suite, since it needs the model):
## godot --headless --path . --script res://test/check_llm.gd -- --llm-model=devstral:24b "fly from Pluto to Mars to Saturn, favor energy"

func _initialize() -> void:
	var settings := FlightSettings.load_settings()
	var client := OllamaClient.new()
	client.model = settings["model"]
	client.url = settings["url"]
	root.add_child.call_deferred(client)
	await process_frame
	var text := "fly from Pluto to Mars to Saturn, favor time over energy"
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			text = argument
	print("model ", client.model, " asked: ", text)
	var started := Time.get_ticks_msec()
	var reply := await client.chat_json(FlightRequest.system_prompt(), text, FlightRequest.schema())
	print("answered in %d ms: %s" % [Time.get_ticks_msec() - started, reply])
	if reply["ok"]:
		var checked := FlightRequest.validate(reply["data"])
		print("validated: ", checked)
	quit()
