extends SceneTree
## End to end with the language model: godot --headless --path . --script res://test/check_flight_ui.gd -- "fly from Earth to Jupiter, favor energy"
## Needs Ollama running with the model in the planner panel.

func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(scene)
	await process_frame
	await process_frame
	var ui: FlightUI = null
	for child in scene.get_children():
		if child is FlightUI:
			ui = child
	var text := "fly from Earth to Jupiter, favor energy over time"
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			text = argument
	ui._input.text = text
	var started := Time.get_ticks_msec()
	ui._on_plan_pressed()
	while ui._busy:
		await process_frame
	print("done in %d ms" % (Time.get_ticks_msec() - started))
	print("STATUS: ", ui._status.text)
	print(ui._result_label.text)
	print("path drawn: ", ui._path.has_result())
	quit()
