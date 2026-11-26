class_name ClockPanel
extends PanelContainer
## The simulator clock: the date, freezing and running, the speed, and setting a date. Every change goes through the simulator's
## clock functions (`set_date`, `set_speed`, `set_frozen`), so the planets always match the date shown.

## Speeds offered, in days per second, with their names.
const SPEEDS: Array = [
	[1.0 / 86400.0, "1 second / s"], [1.0 / 1440.0, "1 minute / s"], [1.0 / 24.0, "1 hour / s"], [0.25, "6 hours / s"], [1.0, "1 day / s"], [7.0, "1 week / s"], [10.0, "10 days / s"],
	[30.4375, "1 month / s"], [100.0, "100 days / s"], [365.25, "1 year / s"], [3652.5, "10 years / s"],
	[36525.0, "100 years / s"], [365250.0, "1000 years / s"],
]

var sim
var _date_label: Label
var _freeze_button: Button
var _real_time_button: Button
var _speed_menu: OptionButton
var _date_edit: LineEdit
var _note: Label
var _custom_index := -1


func _init(simulation = null) -> void:
	sim = simulation


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -300.0
	offset_right = -16.0
	offset_top = 12.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Clock"
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)

	_date_label = Label.new()
	_date_label.add_theme_font_size_override("font_size", 22)
	column.add_child(_date_label)

	var run_row := HBoxContainer.new()
	column.add_child(run_row)
	_freeze_button = Button.new()
	_freeze_button.toggle_mode = true
	_freeze_button.tooltip_text = "Stop or start the clock (Space)."
	_freeze_button.toggled.connect(func(frozen: bool) -> void: sim.set_frozen(frozen))
	_freeze_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_row.add_child(_freeze_button)
	var today := Button.new()
	today.text = "Today"
	today.tooltip_text = "Go to today's date (T)."
	today.pressed.connect(func() -> void: sim.set_date(OrbitMath.days_since_j2000(Time.get_unix_time_from_system())))
	run_row.add_child(today)
	_real_time_button = Button.new()
	_real_time_button.text = "Real time"
	_real_time_button.toggle_mode = true
	_real_time_button.tooltip_text = "Set the clock to the current date and time, and run it at one second per second (R)."
	# Turning it off leaves the clock running at one second per second from where it is.
	_real_time_button.toggled.connect(func(on: bool) -> void:
		if on:
			sim.set_real_time()
		else:
			sim.set_speed(sim.days_per_second))
	run_row.add_child(_real_time_button)

	var speed_row := HBoxContainer.new()
	column.add_child(speed_row)
	var slower := Button.new()
	slower.text = "◀◀"
	slower.tooltip_text = "Half the speed (- or Down)."
	slower.pressed.connect(func() -> void: sim.set_speed(sim.days_per_second / 2.0))
	speed_row.add_child(slower)
	_speed_menu = OptionButton.new()
	for speed in SPEEDS:
		_speed_menu.add_item(speed[1])
	_speed_menu.add_item("")
	_custom_index = SPEEDS.size()
	_speed_menu.set_item_disabled(_custom_index, true)
	_speed_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_menu.item_selected.connect(func(index: int) -> void:
		if index < SPEEDS.size():
			sim.set_speed(SPEEDS[index][0]))
	speed_row.add_child(_speed_menu)
	var faster := Button.new()
	faster.text = "▶▶"
	faster.tooltip_text = "Double the speed (+ or Up)."
	faster.pressed.connect(func() -> void: sim.set_speed(sim.days_per_second * 2.0))
	speed_row.add_child(faster)

	var date_row := HBoxContainer.new()
	column.add_child(date_row)
	_date_edit = LineEdit.new()
	_date_edit.placeholder_text = "YYYY-MM-DD [HH:MM]"
	_date_edit.tooltip_text = "A date, with an optional UTC time, such as 2031-07-04 or 2031-07-04 18:30."
	_date_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_edit.text_submitted.connect(func(_text: String) -> void: _apply_date())
	date_row.add_child(_date_edit)
	var go := Button.new()
	go.text = "Set date"
	go.pressed.connect(_apply_date)
	date_row.add_child(go)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(260, 0)
	_note.add_theme_font_size_override("font_size", 12)
	_note.modulate = Color(1, 1, 1, 0.75)
	column.add_child(_note)


func _process(_delta: float) -> void:
	var rate: float = sim.days_per_second
	_date_label.text = format_days(sim.sim_days, rate < 1.0, rate < 1.0 / 24.0)
	_freeze_button.set_pressed_no_signal(sim.paused)
	_real_time_button.set_pressed_no_signal(sim.real_time)
	_freeze_button.text = "Run" if sim.paused else "Freeze"
	var matched := -1
	for index in SPEEDS.size():
		if absf(SPEEDS[index][0] - sim.days_per_second) <= 1e-6 * SPEEDS[index][0]:
			matched = index
	if matched < 0:
		_speed_menu.set_item_text(_custom_index, "%s days / s" % _number(sim.days_per_second))
		matched = _custom_index
	if _speed_menu.selected != matched:
		_speed_menu.select(matched)
	if sim.is_playing_flight():
		_note.text = "Playing a flight. The speed goes back to %s / s when it arrives." % speed_name(sim._speed_before_flight)
	elif _note.text.begins_with("Playing"):
		_note.text = ""


func _apply_date() -> void:
	var parsed := parse_date(_date_edit.text)
	if not parsed["ok"]:
		_note.text = parsed["error"]
		return
	sim.set_date(parsed["days"])
	_date_edit.release_focus()
	var year: int = parsed["year"]
	_note.text = "" if year >= 1800 and year <= 2050 else \
		"The planet orbits are most accurate from 1800 to 2050; far from those years positions drift."


static func _number(value: float) -> String:
	return String.num(value, 0 if value >= 10.0 else (2 if value >= 0.1 else 3))


## A speed in days per second, named in the unit that reads best: "1 second", "30 minutes", "6 hours", "10 days".
static func speed_name(days_per_second: float) -> String:
	var units := [[86400.0, "second"], [1440.0, "minute"], [24.0, "hour"], [1.0, "day"]]
	for unit in units:
		var amount: float = days_per_second * unit[0]
		if amount < 60.0 or unit[1] == "day" or (unit[1] == "hour" and amount < 24.0):
			var whole := absf(amount - roundf(amount)) < 1e-6 * maxf(amount, 1.0)
			var text := str(int(roundf(amount))) if whole else _number(amount)
			return "%s %s%s" % [text, unit[1], "" if text == "1" else "s"]
	return ""


## Date text for a day count since J2000: "YYYY-MM-DD", with the time of day when `fine`, to the second when `seconds`.
static func format_days(days: float, fine: bool, seconds := false) -> String:
	var unix := OrbitMath.J2000_UNIX + days * OrbitMath.SECONDS_PER_DAY
	var parts := Time.get_datetime_dict_from_unix_time(int(floor(unix)))
	var text := "%04d-%02d-%02d" % [parts["year"], parts["month"], parts["day"]]
	if fine:
		text += "  %02d:%02d" % [parts["hour"], parts["minute"]]
		if seconds:
			text += ":%02d" % parts["second"]
	return text


## Reads "YYYY-MM-DD" or "YYYY-MM-DD HH:MM" (UTC). Returns {"ok": true, "days": days since J2000, "year": int} or
## {"ok": false, "error": String}.
static func parse_date(text: String) -> Dictionary:
	var found := RegEx.create_from_string("^\\s*(\\d{1,4})-(\\d{1,2})-(\\d{1,2})(?:[ T](\\d{1,2}):(\\d{2}))?\\s*$").search(text)
	if found == null:
		return {"ok": false, "error": "Type a date as YYYY-MM-DD, or YYYY-MM-DD HH:MM."}
	var wanted := {"year": int(found.get_string(1)), "month": int(found.get_string(2)), "day": int(found.get_string(3)),
		"hour": int(found.get_string(4)) if found.get_string(4) != "" else 12, "minute": int(found.get_string(5)) if found.get_string(5) != "" else 0,
		"second": 0}
	if wanted["year"] < 1 or wanted["month"] < 1 or wanted["month"] > 12 or wanted["day"] < 1 or wanted["hour"] > 23 or wanted["minute"] > 59:
		return {"ok": false, "error": "That is not a real date."}
	if wanted["day"] > _days_in_month(wanted["year"], wanted["month"]):
		return {"ok": false, "error": "That is not a real date."}
	var unix := Time.get_unix_time_from_datetime_dict(wanted)
	return {"ok": true, "days": OrbitMath.days_since_j2000(float(unix)), "year": wanted["year"]}


static func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if leap else 28
	return 30 if month in [4, 6, 9, 11] else 31
