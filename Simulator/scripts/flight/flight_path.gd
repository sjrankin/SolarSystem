class_name FlightPath
extends Node3D
## Draws a planned flight in the scene: the path, a label at each departure, fly-by and arrival, and a spacecraft marker that moves
## along it as the simulation clock runs. The path is converted the same way as the planets (including the compressed distances), so
## it meets them where they are at those times.

const LEG_COLORS: Array[Color] = [Color(1.0, 0.85, 0.2), Color(0.3, 0.95, 0.85), Color(1.0, 0.5, 0.85), Color(0.6, 0.8, 1.0),
	Color(0.7, 1.0, 0.4), Color(1.0, 0.65, 0.3), Color(0.8, 0.6, 1.0)]

## Radius of the spacecraft's glow, in scene units: Neptune's drawn size for now. Change it here (or set `glow_radius`).
static var GLOW_RADIUS: float = _neptune_radius()

var glow_radius := GLOW_RADIUS:
	set(value):
		glow_radius = value
		_size_glow()

var _result: Dictionary = {}
var _origin_body := -1
var _destination_body := -1
var _linear := false
var _line := MeshInstance3D.new()
var _marker := Node3D.new()
var _core := MeshInstance3D.new()
var _halo := MeshInstance3D.new()
var _labels: Array[Label3D] = []
var _times := PackedFloat64Array()
var _points := PackedVector3Array()


func _init() -> void:
	_line.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_line.material_override = material
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)

	_build_glow()
	add_child(_marker)


static func _neptune_radius() -> float:
	for planet in PlanetData.PLANETS:
		if planet["name"] == "Neptune":
			return float(planet["radius"])
	return 2.7


## The spacecraft: a bright red sphere inside a soft red halo that always faces the camera. Both add light, so the glow shows on
## the dark background and over the grid. They are drawn over everything so the craft is never lost behind a planet.
func _build_glow() -> void:
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = Color(1.0, 0.25, 0.2)
	core_material.no_depth_test = true
	core_material.render_priority = 12
	_core.mesh = SphereMesh.new()
	_core.material_override = core_material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_core)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.15, 0.1, 1.0))
	gradient.set_color(1, Color(1.0, 0.0, 0.0, 0.0))
	gradient.add_point(0.35, Color(1.0, 0.1, 0.05, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.albedo_texture = texture
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.no_depth_test = true
	halo_material.render_priority = 11
	_halo.mesh = QuadMesh.new()
	_halo.material_override = halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_halo)
	_marker.visible = false
	_size_glow()


func _size_glow() -> void:
	var sphere := _core.mesh as SphereMesh
	if sphere == null:
		return
	sphere.radius = glow_radius
	sphere.height = glow_radius * 2.0
	# The halo reaches well past the sphere, so the craft reads as a glow and not as another planet.
	(_halo.mesh as QuadMesh).size = Vector2.ONE * glow_radius * 6.0


## Shows a plan made by `FlightPlanner` (needs its "legs" and "events").
func show_result(result: Dictionary) -> void:
	_result = result
	var route: Array = result["route"]
	_origin_body = Astro.find_body(route[0])
	_destination_body = Astro.find_body(route[route.size() - 1])
	_times = PackedFloat64Array()
	_points = PackedVector3Array()
	for leg in result["legs"]:
		var leg_times: PackedFloat64Array = leg["samples_t"]
		var leg_points: PackedVector3Array = leg["samples_p"]
		# The first point of a leg is the last of the one before.
		for index in leg_times.size():
			if not _times.is_empty() and index == 0:
				continue
			_times.append(leg_times[index])
			_points.append(leg_points[index])
	_rebuild()


func clear() -> void:
	_result = {}
	_times = PackedFloat64Array()
	_points = PackedVector3Array()
	_marker.visible = false
	(_line.mesh as ImmediateMesh).clear_surfaces()
	for label in _labels:
		label.queue_free()
	_labels.clear()


func has_result() -> bool:
	return not _result.is_empty()


func set_linear(linear: bool) -> void:
	_linear = linear
	if has_result():
		_rebuild()


func _to_scene(ecliptic: Vector3) -> Vector3:
	return OrbitMath.to_scene(Ephemeris.to_scene_axes(ecliptic), _linear)


func _rebuild() -> void:
	var mesh := _line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var leg_number := 0
	for leg in _result["legs"]:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var color := LEG_COLORS[leg_number % LEG_COLORS.size()]
		for point in leg["samples_p"]:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(_to_scene(point))
		mesh.surface_end()
		leg_number += 1
	for label in _labels:
		label.queue_free()
	_labels.clear()
	for event in _result["events"]:
		var at := _position_at(float(event["time"]))
		var label := Label3D.new()
		var heading: String = {"departure": "Depart", "flyby": "Fly-by", "arrival": "Arrive"}[event["kind"]]
		label.text = "%s %s\n%s" % [heading, event["body"], Astro.date_text(float(event["time"]))]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		label.pixel_size = 0.0004
		label.font_size = 34
		label.outline_size = 10
		label.modulate = Color(1.0, 0.95, 0.6)
		label.outline_modulate = Color(0, 0, 0, 0.9)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.offset = Vector2(12, -26)
		label.render_priority = 11
		label.position = at
		add_child(label)
		_labels.append(label)


## The point of the path at a time (clamped to the ends), in scene units.
func _position_at(days: float) -> Vector3:
	if _times.is_empty():
		return Vector3.ZERO
	if days <= _times[0]:
		return _to_scene(_points[0])
	if days >= _times[_times.size() - 1]:
		return _to_scene(_points[_points.size() - 1])
	var low := 0
	var high := _times.size() - 1
	while high - low > 1:
		var mid := (low + high) / 2
		if _times[mid] <= days:
			low = mid
		else:
			high = mid
	var along := (days - _times[low]) / maxf(_times[high] - _times[low], 1e-9)
	return _to_scene(_points[low].lerp(_points[high], along))


## Moves the glow to where the plan has the spacecraft at a simulation time (the simulator's clock). Before departure it waits at the
## planet it leaves from, and after arrival it stays with the planet it reached, so it is always on the plotted course.
func update_time(days: float) -> void:
	if _times.is_empty():
		_marker.visible = false
		return
	_marker.visible = true
	if days < _times[0] and _origin_body >= 0:
		_marker.position = _to_scene(Ephemeris.position(_origin_body, days))
	elif days > _times[_times.size() - 1] and _destination_body >= 0:
		_marker.position = _to_scene(Ephemeris.position(_destination_body, days))
	else:
		_marker.position = _position_at(days)
