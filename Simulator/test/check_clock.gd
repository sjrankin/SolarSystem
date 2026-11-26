extends SceneTree
## Headless checks of the clock: godot --headless --path . --script res://test/check_clock.gd

var failures := 0


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	# Dates are read and written back the same, before 1970 too.
	for text in ["2026-11-25", "1850-03-01", "2049-12-31 23:30", "1969-07-20 20:17"]:
		var parsed := ClockPanel.parse_date(text)
		_expect(parsed["ok"], "reads " + text)
		if parsed["ok"]:
			var shown := ClockPanel.format_days(parsed["days"], text.length() > 10)
			_expect(shown.replace("  ", " ") == (text if text.length() > 10 else text), "%s shown as %s" % [text, shown])
	_expect(not ClockPanel.parse_date("2027-02-30")["ok"], "Feb 30 is rejected")
	_expect(not ClockPanel.parse_date("next tuesday")["ok"], "words are rejected")
	_expect(absf(ClockPanel.parse_date("2000-01-01 12:00")["days"]) < 1e-9, "J2000 is day 0")

	# The planets follow a date set while frozen; a flight puts the speed back when it ends.
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(scene)
	await process_frame
	await process_frame
	scene.set_frozen(true)
	var day := float(ClockPanel.parse_date("2030-06-01")["days"])
	scene.set_date(day)
	var earth: Node3D = scene._planets[2]
	var expected := OrbitMath.to_scene(OrbitMath.position_at(PlanetData.PLANETS[2], day), scene.linear_scale)
	_expect(earth.position.distance_to(expected) < 1e-3, "Earth is where the set date puts it while frozen")
	scene.set_speed(7.0)
	scene.play_from(day, 500.0, day + 2.0)
	_expect(scene.days_per_second == 500.0 and not scene.paused, "a flight runs at its own speed")
	for _i in 30:
		await process_frame
	_expect(scene.days_per_second == 7.0 and not scene.is_playing_flight(), "speed is back to 7 days/s after the flight (got %s)" % scene.days_per_second)
	scene.play_from(day, 500.0, day + 1000.0)
	scene.set_speed(3.0)
	_expect(not scene.is_playing_flight(), "choosing a speed during a flight keeps it")

	# Real time: the current date and time, one second per second, following the computer's clock.
	scene.set_frozen(true)
	scene.set_date(day)
	scene.set_real_time()
	var now := OrbitMath.days_since_j2000(Time.get_unix_time_from_system())
	_expect(scene.real_time and not scene.paused, "real time runs the clock")
	_expect(absf(scene.sim_days - now) * 86400.0 < 1.0, "real time starts at the current time")
	_expect(absf(scene.days_per_second * 86400.0 - 1.0) < 1e-9, "real time is one second per second")
	var start_ms := Time.get_ticks_msec()
	var start_days: float = scene.sim_days
	while Time.get_ticks_msec() - start_ms < 1500:
		await process_frame
	var advanced: float = (scene.sim_days - start_days) * 86400.0
	var elapsed := (Time.get_ticks_msec() - start_ms) / 1000.0
	_expect(absf(advanced - elapsed) < 0.2, "real time advances %.2f s in %.2f s" % [advanced, elapsed])
	_expect(absf(scene.sim_days - OrbitMath.days_since_j2000(Time.get_unix_time_from_system())) * 86400.0 < 0.2, "real time stays on the computer's clock")
	scene.set_speed(10.0)
	_expect(not scene.real_time, "choosing a speed leaves real time")
	scene.set_real_time()
	scene.set_frozen(true)
	_expect(not scene.real_time, "freezing leaves real time")
	for pair in [[1.0 / 86400.0, "1 second"], [1.0 / 1440.0, "1 minute"], [0.25, "6 hours"], [1.0 / 48.0, "30 minutes"],
			[10.0, "10 days"], [0.75, "18 hours"], [365250.0, "365250 days"]]:
		_expect(ClockPanel.speed_name(pair[0]) == pair[1], "speed %s named %s (got %s)" % [pair[0], pair[1], ClockPanel.speed_name(pair[0])])
	_expect(ClockPanel.format_days(0.0, true, true) == "2000-01-01  12:00:00", "time shown to the second")
	print("clock checks: ", "OK" if failures == 0 else "%d FAILED" % failures)
	quit(failures)
