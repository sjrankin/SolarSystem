extends SceneTree
## Saves a picture of the main scene after planning a flight (needs a window, so not --headless):
## godot --path . --script res://test/screenshot.gd -- "fly from Earth to Jupiter" /tmp/shot.png
func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(scene)
	await process_frame
	await process_frame
	var ui: FlightUI = null
	for child in scene.get_children():
		if child is FlightUI:
			ui = child
	var text := "fly from Earth to Jupiter"
	var out := "/tmp/shot.png"
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			if argument.ends_with(".png"):
				out = argument
			else:
				text = argument
	scene.paused = true
	ui._input.text = text
	ui._on_plan_pressed()
	while ui._busy:
		await process_frame
	var times: Array = ui._best["times"]
	scene.sim_days = (float(times[0]) + float(times[times.size() - 1])) / 2.0
	scene._update_planets()
	scene._camera.pitch = deg_to_rad(55.0)
	scene._camera.distance = 520.0
	scene._camera._apply()
	for _i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
