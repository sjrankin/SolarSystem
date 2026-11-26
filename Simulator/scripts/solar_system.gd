extends Node3D
## Root scene: builds the Sun, planets, orbit lines, camera and HUD, and advances time.

const SUN_RADIUS := 4.5
const DEFAULT_DAYS_PER_SECOND := 10.0
## One simulated second per second: real time.
const REAL_TIME_DAYS_PER_SECOND := 1.0 / 86400.0
## From real time to a thousand simulated years per second.
const MIN_DAYS_PER_SECOND := REAL_TIME_DAYS_PER_SECOND
const MAX_DAYS_PER_SECOND := 365250.0

## Simulation clock, in days since J2000. Starts at the current real date.
var sim_days := OrbitMath.days_since_j2000(Time.get_unix_time_from_system())
var days_per_second := DEFAULT_DAYS_PER_SECOND
var paused := false
## True while the clock follows the computer's clock (real time). Any other change to the clock turns it off.
var real_time := false
var linear_scale := false

var _planets: Array[Planet] = []
var _orbit_lines: Dictionary = {}
var _camera: OrbitCamera
var _gravity_well: GravityWell
var _sun := MeshInstance3D.new()
var _sun_pole_rotation := Quaternion.IDENTITY
var _status_label: Label
var _flight_ui: FlightUI
var _clock_panel: ClockPanel
## While a planned flight is being played: the day it arrives, and the speed to go back to then. NAN when no flight is playing.
var _flight_end_days := NAN
var _speed_before_flight := DEFAULT_DAYS_PER_SECOND


func _ready() -> void:
	_apply_command_line()
	_build_environment()
	_build_sun()
	for planet_data in PlanetData.PLANETS:
		var planet := Planet.new(planet_data)
		add_child(planet)
		_planets.append(planet)
		_orbit_lines[planet.name] = _make_orbit_line(planet)
	_gravity_well = GravityWell.new(SUN_RADIUS)
	_gravity_well.set_linear(linear_scale)
	add_child(_gravity_well)
	_camera = OrbitCamera.new()
	add_child(_camera)
	_build_hud()
	_flight_ui = FlightUI.new(self)
	add_child(_flight_ui)
	_rebuild_orbits()
	_update_planets()
	_focus_from_command_line()


func _process(delta: float) -> void:
	if not paused:
		# In real time the date is read from the computer's clock each frame, so it never drifts from it.
		sim_days = _now_days() if real_time else sim_days + delta * days_per_second
		_update_planets()
		# The flight is over: the clock goes back to the speed it had before it.
		if is_finite(_flight_end_days) and sim_days >= _flight_end_days:
			days_per_second = _speed_before_flight
			_flight_end_days = NAN
	_gravity_well.follow(_camera)
	for planet in _planets:
		planet.update_moons(sim_days, _camera.global_position)
	_update_status()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			set_frozen(not paused)
		KEY_EQUAL, KEY_KP_ADD, KEY_UP:
			set_speed(days_per_second * 2.0)
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_DOWN:
			set_speed(days_per_second / 2.0)
		KEY_L:
			linear_scale = not linear_scale
			_gravity_well.set_linear(linear_scale)
			_rebuild_orbits()
			_update_planets()
			_flight_ui.on_scale_changed(linear_scale)
		KEY_SLASH:
			_flight_ui.focus_input()
			get_viewport().set_input_as_handled()
		KEY_G:
			_gravity_well.visible = not _gravity_well.visible
		KEY_T:
			set_date(_now_days())
		KEY_R:
			set_real_time()


# ---- The clock. The clock panel, the keys and the flight planner all change it through these, so the planets always match. ----

## Today's date and time from the computer's clock, in days since J2000.
func _now_days() -> float:
	return OrbitMath.days_since_j2000(Time.get_unix_time_from_system())


## Real time: sets the clock to the current date and time and runs it at one second per second, following the computer's clock.
## Ends a flight being played without changing the speed back.
func set_real_time() -> void:
	set_date(_now_days())
	days_per_second = REAL_TIME_DAYS_PER_SECOND
	paused = false
	real_time = true


## Sets the date (days since J2000) and moves every planet and moon there at once, running or frozen. A flight being played is
## left to the user: the speed is no longer changed back when it arrives.
func set_date(days: float) -> void:
	sim_days = days
	real_time = false
	_flight_end_days = NAN
	_update_planets()
	for planet in _planets:
		planet.update_moons(sim_days, _camera.global_position)


## Sets the speed in days per second. Choosing a speed during a flight keeps it after the flight.
func set_speed(rate: float) -> void:
	days_per_second = clampf(rate, MIN_DAYS_PER_SECOND, MAX_DAYS_PER_SECOND)
	real_time = false
	_flight_end_days = NAN


## Freezes (true) or runs (false) the clock. Freezing leaves real time; running again carries on from the frozen date.
func set_frozen(frozen: bool) -> void:
	paused = frozen
	if frozen:
		real_time = false


## True while a planned flight is playing at its own speed.
func is_playing_flight() -> bool:
	return is_finite(_flight_end_days)


## Plays a planned flight: sets the clock to `days`, runs it at `rate` days per second, and when the clock reaches `end_days` puts
## the speed back to what it was before.
func play_from(days: float, rate: float, end_days: float) -> void:
	if not is_playing_flight():
		_speed_before_flight = days_per_second
	sim_days = days
	real_time = false
	days_per_second = clampf(rate, MIN_DAYS_PER_SECOND, MAX_DAYS_PER_SECOND)
	_flight_end_days = end_days
	paused = false
	_update_planets()


## Stops playing a flight (when it is cleared), putting the speed back.
func stop_flight_playback() -> void:
	if is_playing_flight():
		days_per_second = _speed_before_flight
		_flight_end_days = NAN


func _apply_command_line() -> void:
	# Optional testing aid: --date=YYYY-MM-DD starts the simulation on that date.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--date="):
			var unix := Time.get_unix_time_from_datetime_string(argument.trim_prefix("--date="))
			sim_days = OrbitMath.days_since_j2000(unix)
		elif argument == "--paused":
			paused = true
		elif argument == "--linear":
			linear_scale = true


## Testing aids: --focus=Earth frames that planet close up; --view=pitch,distance[,yaw] frames the
## whole system from an angle (use with --paused).
func _focus_from_command_line() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--view="):
			# --view=pitch_degrees,distance : overall view from a chosen angle.
			var parts := argument.trim_prefix("--view=").split(",")
			_camera.pitch = deg_to_rad(float(parts[0]))
			_camera.distance = float(parts[1])
			_camera.yaw = deg_to_rad(float(parts[2])) if parts.size() > 2 else 0.0
			_camera._apply()
		if not argument.begins_with("--focus="):
			continue
		var wanted := argument.trim_prefix("--focus=")
		for planet in _planets:
			if planet.name == wanted:
				_camera.target = planet.position
				_camera.distance = float(planet.data["radius"]) * 6.0
				_camera.pitch = deg_to_rad(10.0)
				_camera.yaw = atan2(planet.position.x, planet.position.z) + PI - 0.6
				_camera._apply()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pitch="):
			_camera.pitch = deg_to_rad(float(argument.trim_prefix("--pitch=")))
			_camera.distance *= 5.0
			_camera._apply()


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.38, 0.5)
	environment.ambient_light_energy = 0.35
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


func _build_sun() -> void:
	var sun := _sun
	sun.name = "Sun"
	var sphere := SphereMesh.new()
	sphere.radius = SUN_RADIUS
	sphere.height = SUN_RADIUS * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	sun.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.4)
	if ResourceLoader.exists("res://textures/Sun.png"):
		material.albedo_color = Color.WHITE
		material.albedo_texture = load("res://textures/Sun.png")
	sun.material_override = material
	_sun_pole_rotation = Quaternion(Vector3.UP, OrbitMath.equatorial_to_scene(PlanetData.SUN_POLE_RA, PlanetData.SUN_POLE_DEC))
	sun.quaternion = _sun_pole_rotation
	add_child(sun)

	var light := OmniLight3D.new()
	light.omni_range = 5000.0
	light.omni_attenuation = 0.0
	light.light_energy = 2.2
	light.shadow_enabled = false
	add_child(light)

	var label := Label3D.new()
	label.text = "Sun"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.pixel_size = 0.0004
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(1.0, 0.92, 0.6)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.offset = Vector2(10, 12)
	label.render_priority = 10
	sun.add_child(label)


func _make_orbit_line(planet: Planet) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	line.name = "%sOrbit" % planet.name
	line.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = planet.orbit_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	return line


func _rebuild_orbits() -> void:
	for planet in _planets:
		var line: MeshInstance3D = _orbit_lines[planet.name]
		var mesh := line.mesh as ImmediateMesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point in planet.orbit_points(linear_scale):
			mesh.surface_add_vertex(point)
		mesh.surface_end()


func _update_planets() -> void:
	for planet in _planets:
		planet.update_position(sim_days, linear_scale)
	var sun_spin := deg_to_rad(fposmod(PlanetData.SUN_W0 + PlanetData.SUN_W_RATE * sim_days, 360.0))
	_sun.quaternion = _sun_pole_rotation * Quaternion(Vector3.UP, sun_spin)
	_gravity_well.update_bodies(_planets)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_clock_panel = ClockPanel.new(self)
	layer.add_child(_clock_panel)

	_status_label = Label.new()
	_status_label.position = Vector2(16, 12)
	_status_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(_status_label)

	var hint := Label.new()
	hint.text = "Drag: rotate   Right-drag / Option-drag: move   Scroll or pinch: zoom   Double-click: reset view\n" \
		+ "Space: pause   +/-: speed   L: linear / compressed distances   G: gravity wells   T: jump to today   R: real time"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 16
	hint.offset_top = -52
	layer.add_child(hint)


func _update_status() -> void:
	var unix := OrbitMath.J2000_UNIX + sim_days * OrbitMath.SECONDS_PER_DAY
	var date := Time.get_datetime_string_from_unix_time(int(floor(unix))).split("T")[0]
	var speed := "paused" if paused else ("real time" if real_time else "%s / sec" % ClockPanel.speed_name(days_per_second))
	var scale_name := "linear distances" if linear_scale else "compressed distances"
	_status_label.text = "%s    %s    %s" % [date, speed, scale_name]
