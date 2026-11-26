extends SceneTree
## Unloading the model when the simulator quits: godot --headless --path . --script res://test/check_unload.gd
## The live part needs Ollama running with the model; it loads the model, then unloads it as closing the window does.

var failures := 0


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)


func _loaded(client: OllamaClient) -> Array:
	var reply := await client._send("/api/ps", HTTPClient.METHOD_GET, "", 3.0)
	var names: Array = []
	if reply["ok"]:
		var parsed: Variant = JSON.parse_string(String(reply["text"]))
		if parsed is Dictionary:
			for entry in parsed.get("models", []):
				names.append(String(entry.get("name", "")))
	return names


func _initialize() -> void:
	var client := OllamaClient.new()
	root.add_child.call_deferred(client)
	await process_frame
	var settings := FlightSettings.load_settings()
	client.url = settings["url"]
	client.model = settings["model"]

	# A session that never used the model leaves Ollama alone.
	_expect(not client.unload_now(), "nothing is unloaded if the model was never used")

	# Ollama not reachable: quitting is not held up.
	var dead := OllamaClient.new()
	dead.url = "http://127.0.0.1:9"
	dead._used_models.append("devstral:24b")
	var started := Time.get_ticks_msec()
	_expect(not dead.unload_now(), "unloading with no Ollama reports failure")
	_expect(Time.get_ticks_msec() - started <= OllamaClient.UNLOAD_TIMEOUT_MS + 100, "and does not hold up quitting")
	dead.free()

	if not (await client.check())["ok"]:
		print("Ollama with %s not available here (%s); skipping the live part" % [client.model, (await client.check())["error"]])
	else:
		var reply := await client.chat_text("Answer with one word.", "Say ok.")
		_expect(reply["ok"], "the model answers")
		var before := await _loaded(client)
		print("loaded before closing: ", before)
		_expect(client.model in before, "the model is loaded after being used")
		# What the window close button and Cmd+Q send to every node.
		started = Time.get_ticks_msec()
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		print("unload took %d ms" % (Time.get_ticks_msec() - started))
		var after := await _loaded(client)
		print("loaded after closing: ", after)
		_expect(not client.model in after, "the model is unloaded when the window closes")
	print("unload checks: ", "OK" if failures == 0 else "%d FAILED" % failures)
	quit(failures)
