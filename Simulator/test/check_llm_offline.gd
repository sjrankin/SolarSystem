extends SceneTree
## The flight planner without a working language model: godot --headless --path . --script res://test/check_llm_offline.gd
## Needs no Ollama. (The missing-model case runs only if Ollama happens to be running.)

var failures := 0


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)


func _plan(ui: FlightUI, text: String, skip_after_ms := -1) -> int:
	ui._best = {}
	ui._input.text = text
	var started := Time.get_ticks_msec()
	ui._on_plan_pressed()
	var skipped := false
	while ui._busy:
		if skip_after_ms >= 0 and not skipped and Time.get_ticks_msec() - started > skip_after_ms:
			_expect(ui._plan_button.text == "Skip model" and not ui._plan_button.disabled, "Plan becomes Skip model while waiting")
			ui._on_plan_pressed()
			skipped = true
		await process_frame
	return Time.get_ticks_msec() - started


func _initialize() -> void:
	var installed: Array[String] = ["devstral:24b", "llama3:latest"]
	_expect(OllamaClient.has_model(installed, "devstral:24b"), "finds a tagged model")
	_expect(OllamaClient.has_model(installed, "llama3"), "an untagged name means :latest")
	_expect(not OllamaClient.has_model(installed, "devstral"), "devstral is not devstral:24b")

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(scene)
	await process_frame
	await process_frame
	var ui: FlightUI = null
	for child in scene.get_children():
		if child is FlightUI:
			ui = child
	var client: OllamaClient = ui._client
	var saved_url := client.url
	var saved_model := client.model

	# 1. Nothing listening: the plan is made with the plain reader, quickly, with no summary request.
	client.url = "http://127.0.0.1:9"
	var took := await _plan(ui, "fly from Earth to Mars, favor energy")
	print("no server: %d ms, status: %s" % [took, ui._status.text.replace("\n", " | ")])
	_expect(took < 5000, "no server fails fast (%d ms)" % took)
	_expect(ui._status.text.contains("not running"), "says Ollama is not running")
	_expect(not ui._best.is_empty() and ui._path.has_result(), "still plans and draws the flight without the model")
	_expect(not ui._go_button.disabled and ui._plan_button.text == "Plan" and not ui._plan_button.disabled, "buttons are back to normal")
	_expect(not ui._status.text.contains("summary"), "no summary is asked for")

	# 2. A server that accepts but never answers: the quick check gives up, it does not hang the planner.
	var silent := TCPServer.new()
	_expect(silent.listen(18734, "127.0.0.1") == OK, "test server listens")
	client.url = "http://127.0.0.1:18734"
	took = await _plan(ui, "fly from Earth to Venus")
	print("silent server: %d ms, status: %s" % [took, ui._status.text.replace("\n", " | ")])
	_expect(took < 8000, "a silent server is given up on (%d ms)" % took)
	_expect(not ui._best.is_empty(), "still plans after a silent server")

	# 3. Skipping: a slow chat is stopped with the button, and the plain reader takes over at once.
	client.check_timeout_seconds = 30.0
	took = await _plan(ui, "fly from Earth to Jupiter", 500)
	print("skipped: %d ms, status: %s" % [took, ui._status.text.replace("\n", " | ")])
	_expect(took < 3000, "skipping stops the wait (%d ms)" % took)
	_expect(ui._status.text.contains("Skipped the model"), "says the model was skipped")
	_expect(not ui._best.is_empty(), "still plans after skipping")
	silent.stop()
	client.check_timeout_seconds = 3.0

	# 4. Text that neither reader understands is reported, not planned.
	client.url = "http://127.0.0.1:9"
	await _plan(ui, "take me somewhere nice")
	_expect(ui._best.is_empty() and not ui._plan_button.disabled, "nonsense is reported and the panel recovers")

	# 5. Ollama running without the model (only if Ollama is running here).
	client.url = saved_url
	client.model = "no-such-model:1b"
	var reach := await client.check()
	if reach["ok"] or String(reach["error"]).contains("not running"):
		print("Ollama not running here; skipping the missing-model case")
	else:
		print("missing model: ", reach["error"])
		_expect(String(reach["error"]).contains("ollama pull no-such-model:1b"), "says how to install the model")
		await _plan(ui, "fly from Earth to Mars")
		_expect(not ui._best.is_empty(), "still plans without the model installed")
	client.model = saved_model

	print("offline LLM checks: ", "OK" if failures == 0 else "%d FAILED" % failures)
	quit(failures)
