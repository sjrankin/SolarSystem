extends SceneTree
## Follow mode: godot --headless --path . --script res://test/check_follow.gd   (needs no Ollama)
## Optional: -- /path/shot.png saves a picture mid-flight (run without --headless for that).

var failures := 0


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


## Waits real time (headless frames run much faster than 60 a second, and the camera glides take 0.7 s).
func _seconds(length: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < length * 1000.0:
		await process_frame


func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(scene)
	await process_frame
	await process_frame
	var ui: FlightUI = scene._flight_ui
	var camera: OrbitCamera = scene._camera
	var craft := ui._path.spacecraft()
	var path := ui._path
	ui._client.url = "http://127.0.0.1:9"   # The plain reader is enough here.
	scene.set_frozen(true)

	# Follow on, flight planned but not flying: the camera stays put.
	var before := camera.transform
	ui.toggle_follow()
	ui._input.text = "fly from Earth to Mars"
	ui._on_plan_pressed()
	while ui._busy:
		await process_frame
	_expect(not ui._best.is_empty(), "the flight is planned")
	await _seconds(0.3)
	_expect(ui.is_following() and camera.transform.is_equal_approx(before) and camera.follow == null,
		"before the flight is in progress the camera does not move")

	# Fly it starts the clock a few days before departure: still waiting until the spacecraft leaves.
	var times: Array = ui._best["times"]
	var depart := float(times[0])
	var arrive := float(times[times.size() - 1])
	scene.set_date(depart - 2.0)
	await _frames(3)
	_expect(camera.follow == null and camera.transform.is_equal_approx(before), "not following before departure")

	# In flight: the camera glides in behind the spacecraft, low over the plane, looking the way it is going.
	scene.set_date(depart + (arrive - depart) * 0.3)
	await _seconds(1.0)
	_expect(camera.follow == craft, "following once the flight is in progress")
	_expect(camera.target.distance_to(craft.global_position) < 1e-3, "centred on the spacecraft")
	_expect(absf(camera.distance - OrbitCamera.FOLLOW_DISTANCE) < 1e-3, "close behind it (%.1f)" % camera.distance)
	var look := -camera.global_basis.z
	var heading := path.heading_at(scene.sim_days).normalized()
	var flat_look := Vector2(look.x, look.z).normalized()
	var flat_heading := Vector2(heading.x, heading.z).normalized()
	print("look·heading on the plane: %.3f; camera %.1f above the spacecraft" % [flat_look.dot(flat_heading),
		camera.global_position.y - craft.global_position.y])
	_expect(flat_look.dot(flat_heading) > 0.99, "looking along the direction of travel")
	_expect(camera.global_position.y - craft.global_position.y < OrbitCamera.FOLLOW_DISTANCE * 0.2,
		"low over the plane, not high above it")

	# Flying: the camera keeps on the spacecraft and turns with it as the path curves.
	scene.set_speed(20.0)
	scene.set_frozen(false)
	var worst_distance := 0.0
	var worst_dot := 1.0
	for _i in 120:
		await process_frame
		worst_distance = maxf(worst_distance, camera.target.distance_to(craft.global_position))
		look = -camera.global_basis.z
		heading = path.heading_at(scene.sim_days)
		worst_dot = minf(worst_dot, Vector2(look.x, look.z).normalized().dot(Vector2(heading.x, heading.z).normalized()))
	print("in flight: off the spacecraft by at most %.6f, look·heading at least %.3f" % [worst_distance, worst_dot])
	_expect(worst_distance < 1e-3, "stays on the spacecraft as it flies")
	_expect(worst_dot > 0.95, "keeps looking the way it is going")
	var shot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.ends_with(".png"):
			shot = argument
	if not shot.is_empty():
		scene.set_frozen(true)
		await _frames(3)
		root.get_viewport().get_texture().get_image().save_png(shot)
		print("saved ", shot)

	# Dragging swings the view round the spacecraft, and it keeps that angle as it turns; double-click comes back behind it.
	scene.set_frozen(true)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.relative = Vector2(-260, 0)
	camera._handle_motion(motion)
	await _frames(5)
	look = -camera.global_basis.z
	heading = path.heading_at(scene.sim_days)
	_expect(Vector2(look.x, look.z).normalized().dot(Vector2(heading.x, heading.z).normalized()) < 0.5, "dragging swings the view round")
	camera.reset_view()
	await _seconds(1.0)
	look = -camera.global_basis.z
	_expect(Vector2(look.x, look.z).normalized().dot(Vector2(heading.x, heading.z).normalized()) > 0.99, "double-click comes back behind it")

	# Arrival: the camera stops following and stays where it is.
	scene.set_date(arrive + 1.0)
	await _frames(2)
	var stopped := camera.transform
	await _seconds(0.3)
	_expect(camera.follow == null and camera.transform.is_equal_approx(stopped), "after arrival the camera stops and stays")

	# Follow off during a flight: no following.
	scene.set_date(depart + 10.0)
	await _frames(2)
	_expect(camera.follow == craft, "following again during the flight")
	ui.toggle_follow()
	await _frames(2)
	_expect(camera.follow == null, "Follow off stops following")
	print("follow checks: ", "OK" if failures == 0 else "%d FAILED" % failures)
	quit(failures)
