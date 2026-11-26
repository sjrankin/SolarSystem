class_name FlightUI
extends CanvasLayer
## The flight planner panel: the user types a request ("fly from Pluto to Mars to Saturn, favor energy over time"), the local language
## model reads it and suggests extra gravity-assist routes, the solver plans each route, and the best one is drawn and described.

const PANEL_WIDTH := 480.0

var sim
var _client := OllamaClient.new()
var _path := FlightPath.new()
var _input: LineEdit
var _model_edit: LineEdit
var _weight_slider: HSlider
var _status: Label
var _result_label: Label
var _result_scroll: ScrollContainer
var _go_button: Button
var _plan_button: Button
var _follow_toggle: CheckButton
var _thread: Thread
var _busy := false
var _best: Dictionary = {}

signal _planned(results)


func _init(simulation = null) -> void:
	sim = simulation


func _ready() -> void:
	var settings := FlightSettings.load_settings()
	_client.model = settings["model"]
	_client.url = settings["url"]
	add_child(_client)
	sim.add_child(_path)
	_build_panel()


func on_scale_changed(linear: bool) -> void:
	_path.set_linear(linear)


func focus_input() -> void:
	_input.grab_focus()


## Turns Follow mode on or off (the F key).
func toggle_follow() -> void:
	_follow_toggle.button_pressed = not _follow_toggle.button_pressed


func is_following() -> bool:
	return _follow_toggle.button_pressed


func _process(_delta: float) -> void:
	_path.update_time(sim.sim_days)
	_update_follow()
	if _thread != null and not _thread.is_alive():
		var results: Variant = _thread.wait_to_finish()
		_thread = null
		_planned.emit(results)


## With Follow on, the camera chases the spacecraft only while the flight is in progress (from departure to arrival). Before
## departure it waits where it is; on arrival it stops and stays there.
func _update_follow() -> void:
	var craft := _path.spacecraft()
	var wanted := is_following() and _path.in_progress(sim.sim_days)
	var camera: OrbitCamera = sim._camera
	if wanted and camera.follow != craft:
		camera.start_following(craft)
	elif not wanted and camera.follow == craft:
		camera.stop_following()


func _unhandled_input(event: InputEvent) -> void:
	# A click in the 3D view gives the keyboard back to the simulator (Space pauses again, and so on).
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		get_viewport().gui_release_focus()


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 48)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Flight planner   (press / to type)"
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)

	_input = LineEdit.new()
	_input.placeholder_text = "fly from Earth to Jupiter, favor energy over time"
	_input.text_submitted.connect(func(_text: String) -> void: _on_plan_pressed())
	column.add_child(_input)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_plan_button = Button.new()
	_plan_button.text = "Plan"
	_plan_button.pressed.connect(_on_plan_pressed)
	buttons.add_child(_plan_button)
	_go_button = Button.new()
	_go_button.text = "Fly it"
	_go_button.disabled = true
	_go_button.tooltip_text = "Set the clock to the departure and run the flight."
	_go_button.pressed.connect(_on_go_pressed)
	buttons.add_child(_go_button)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(_on_clear_pressed)
	buttons.add_child(clear)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_follow_toggle = CheckButton.new()
	_follow_toggle.text = "Follow"
	_follow_toggle.tooltip_text = "While the flight is in progress, the camera chases the spacecraft from just behind it, along the plane of the solar system (F)."
	buttons.add_child(_follow_toggle)

	var weight_row := HBoxContainer.new()
	column.add_child(weight_row)
	var energy_label := Label.new()
	energy_label.text = "Energy"
	weight_row.add_child(energy_label)
	_weight_slider = HSlider.new()
	_weight_slider.min_value = 0.0
	_weight_slider.max_value = 1.0
	_weight_slider.step = 0.05
	_weight_slider.value = 0.5
	_weight_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_slider.tooltip_text = "Used when the request does not say whether to favor time or energy."
	weight_row.add_child(_weight_slider)
	var time_label := Label.new()
	time_label.text = "Time"
	weight_row.add_child(time_label)

	var model_row := HBoxContainer.new()
	column.add_child(model_row)
	var model_label := Label.new()
	model_label.text = "Model"
	model_row.add_child(model_label)
	_model_edit = LineEdit.new()
	_model_edit.text = _client.model
	_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_edit.tooltip_text = "The Ollama model that reads the request and suggests routes."
	_model_edit.text_submitted.connect(func(_text: String) -> void: _save_model())
	_model_edit.focus_exited.connect(_save_model)
	model_row.add_child(_model_edit)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 0)
	_status.modulate = Color(1, 1, 1, 0.8)
	column.add_child(_status)

	# The plan and its explanation can be long, so they scroll inside a box and never cover more than part of the view.
	_result_scroll = ScrollContainer.new()
	_result_scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 300)
	_result_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_result_scroll.visible = false
	column.add_child(_result_scroll)
	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 0)
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.add_theme_font_size_override("font_size", 13)
	_result_scroll.add_child(_result_label)


func _set_result(text: String) -> void:
	_result_label.text = text
	_result_scroll.visible = not text.is_empty()


func _save_model() -> void:
	var name := _model_edit.text.strip_edges()
	if name.is_empty():
		_model_edit.text = _client.model
		return
	if name == _client.model:
		return
	_client.model = name
	FlightSettings.save_settings({"model": name})


func _on_clear_pressed() -> void:
	sim.stop_flight_playback()
	_path.clear()
	_best = {}
	_go_button.disabled = true
	_set_result("")
	_status.text = ""


func _on_go_pressed() -> void:
	if _best.is_empty():
		return
	var times: Array = _best["times"]
	# The flight takes about 30 seconds to watch, wherever it is.
	sim.play_from(float(times[0]) - 3.0, (float(_best["total_days"]) + 6.0) / 30.0, float(times[times.size() - 1]))


func _on_plan_pressed() -> void:
	if _busy:
		# While the model is being waited for, the button skips it.
		if _client.is_busy():
			_client.cancel()
		return
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_busy = true
	_go_button.disabled = true
	_save_model()
	await _plan(text)
	_busy = false
	_show_waiting_for_model(false)
	_plan_button.disabled = false
	_go_button.disabled = _best.is_empty()


## While the model is being waited for, Plan becomes Skip model; otherwise it is Plan, and disabled during planning.
func _show_waiting_for_model(waiting: bool) -> void:
	_plan_button.text = "Skip model" if waiting else "Plan"
	_plan_button.tooltip_text = "Stop waiting for the language model and plan with what is there." if waiting else ""
	_plan_button.disabled = _busy and not waiting


func _plan(text: String) -> void:
	_set_result("")
	# The language model is a help, not a need: when it is missing, slow or confused, the plain reader takes the request instead
	# and the planner still plans. Nothing it does can stop the simulator.
	var model_ok := false
	var request: Dictionary = {}
	var note := ""
	_status.text = "Checking for %s…" % _client.model
	_show_waiting_for_model(true)
	var reachable := await _client.check()
	if not reachable["ok"]:
		note = _fallback_note(reachable)
	else:
		_status.text = "Asking %s to read the request…" % _client.model
		var reply := await _client.chat_json(FlightRequest.system_prompt(), text, FlightRequest.schema())
		if not reply["ok"]:
			note = _fallback_note(reply)
		else:
			request = FlightRequest.validate(reply["data"])
			model_ok = request["ok"]
			if not model_ok:
				note = "The model's reading could not be used (%s). Using the plain reader instead.\n" % request["error"]
	_show_waiting_for_model(false)
	if not model_ok:
		var plain := FlightRequest.fallback_parse(text)
		if not plain["ok"]:
			# Neither reader understood it; the model's complaint is usually the more useful one when it had one.
			_status.text = note + (plain["error"] if request.is_empty() or request["ok"] else request["error"])
			return
		request = plain
	var typed_limits := FlightRequest.limits_from_text(text)
	var max_days: float = request["max_days"] if request["max_days"] > 0.0 else typed_limits["max_days"]
	var max_dv: float = request["max_dv_kms"] if request["max_dv_kms"] > 0.0 else typed_limits["max_dv_kms"]
	var weight: float = request["time_weight"] if request["time_weight"] >= 0.0 else _weight_slider.value
	var options := {"time_weight": weight, "arrival": request["arrival"], "start_days": sim.sim_days, "max_days": max_days,
		"max_dv_kms": max_dv}
	var routes: Array = [request["route"]]
	routes.append_array(request["alternatives"])
	_status.text = note + "Planning %d route%s (time weight %.2f)…" % [routes.size(), "" if routes.size() == 1 else "s", weight]
	_thread = Thread.new()
	_thread.start(FlightPlanner.plan_routes.bind(routes, options))
	var outcome: Dictionary = await _planned
	if not outcome["ok"]:
		_status.text = note + outcome["error"]
		return
	_best = outcome["best"]
	_path.set_linear(sim.linear_scale)
	_path.show_result(_best)
	_status.text = note + "Planned. Press Fly it to watch it."
	_set_result(_describe(outcome, weight))
	if model_ok:
		await _explain(outcome)


## The note shown when the plan goes on without the model.
static func _fallback_note(reply: Dictionary) -> String:
	if reply.get("cancelled", false):
		return "Skipped the model. Using the plain reader, with no extra routes.\n"
	return "%s Using the plain reader instead, with no extra routes.\n" % reply["error"]


## The plan as text: the best route with every event, and the other routes tried.
func _describe(outcome: Dictionary, weight: float) -> String:
	var best: Dictionary = outcome["best"]
	var lines: Array[String] = []
	lines.append("Best: %s" % " → ".join(best["route"]))
	for event in best["events"]:
		var burn := "burn %.2f km/s" % event["dv_kms"]
		match event["kind"]:
			"departure":
				lines.append("  Depart %s  %s   (%s, v∞ %.1f km/s)" % [event["body"], Astro.date_text(event["time"]), burn, event["v_inf_kms"]])
			"flyby":
				var how := "gravity assist" if event.get("free", false) and event["dv_kms"] < 0.01 else burn
				lines.append("  Fly-by %s  %s   (%s, v∞ %.1f km/s, closest %.0f km)" % [event["body"], Astro.date_text(event["time"]),
					how, event["v_inf_kms"], event.get("closest_km", 0.0)])
			_:
				lines.append("  Arrive %s  %s   (%s, v∞ %.1f km/s)" % [event["body"], Astro.date_text(event["time"]),
					burn if best["capture"] else "fly-by, no burn", event["v_inf_kms"]])
	lines.append("Total: %.1f km/s, %s" % [best["total_dv_kms"], _duration_text(best["total_days"])])
	if outcome["all"].size() > 1:
		lines.append("")
		lines.append("Routes tried (time weight %.2f):" % weight)
		for plan in outcome["all"]:
			lines.append("  %s%s: %.1f km/s, %s" % ["★ " if plan == best else "", " → ".join(plan["route"]), plan["total_dv_kms"],
				_duration_text(plan["total_days"])])
	for name in outcome["failed"]:
		lines.append("  (no flight found for %s)" % name)
	return "\n".join(lines)


static func _duration_text(days: float) -> String:
	if days >= 730.0:
		return "%.1f years" % (days / 365.25)
	return "%d days" % int(round(days))


## Asks the model to explain the result in words. The plan is already on screen, so a failure here only leaves it out.
func _explain(outcome: Dictionary) -> void:
	var summary := {"best": _summary(outcome["best"]), "others": []}
	for plan in outcome["all"]:
		if plan != outcome["best"]:
			summary["others"].append(_summary(plan))
	_status.text += "\nWriting a summary…"
	_show_waiting_for_model(true)
	var reply := await _client.chat_text(FlightRequest.explanation_system_prompt(), JSON.stringify(summary))
	_show_waiting_for_model(false)
	_status.text = _status.text.replace("\nWriting a summary…", "")
	if reply["ok"] and not String(reply["text"]).strip_edges().is_empty():
		_set_result(_result_label.text + "\n\n" + String(reply["text"]).strip_edges())


static func _summary(plan: Dictionary) -> Dictionary:
	var events: Array = []
	for event in plan["events"]:
		var what := "engine burn leaving orbit"
		if event["kind"] == "flyby":
			what = "gravity assist" if event["dv_kms"] < 0.01 else "gravity assist with an engine burn"
		elif event["kind"] == "arrival":
			what = "engine burn into orbit" if plan["capture"] else "fly-by without stopping"
		events.append({"body": event["body"], "kind": event["kind"], "what": what, "date": Astro.date_text(event["time"]),
			"burn_kms": snappedf(event["dv_kms"], 0.01), "v_infinity_kms": snappedf(event["v_inf_kms"], 0.1)})
	return {"route": plan["route"], "total_delta_v_kms": snappedf(plan["total_dv_kms"], 0.1),
		"duration_years": snappedf(plan["total_days"] / 365.25, 0.1), "time_weight": snappedf(plan["time_weight"], 0.01),
		"events": events}
