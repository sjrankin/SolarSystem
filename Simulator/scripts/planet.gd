class_name Planet
extends Node3D
## A planet: a rotating sphere (plus rings for Saturn), a screen-facing name label and its moons.

## Moon labels and orbit lines appear when the camera is closer to the planet than this.
const MOON_DETAIL_DISTANCE := 110.0

var data: Dictionary
var orbit_color: Color
## Heliocentric position in AU (scene axes) as of the last update.
var au_position := Vector3.ZERO

var _body := MeshInstance3D.new()
var _pole_rotation := Quaternion.IDENTITY
var _moons: Array[Moon] = []


func _init(planet_data: Dictionary) -> void:
	data = planet_data
	name = data["name"]
	var color: Color = data["color"]
	orbit_color = color.lerp(Color.WHITE, 0.25)
	orbit_color.a = 0.55

	var radius: float = data["radius"]
	var body := _body
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	body.mesh = sphere
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	var texture_path := "res://textures/%s.png" % data["name"]
	if ResourceLoader.exists(texture_path):
		material.albedo_texture = load(texture_path)
	else:
		material.albedo_color = color
	body.material_override = material
	add_child(body)

	# Align the planet's axis (and ring plane) with its real north pole direction.
	var pole := Vector3.UP
	if data.has("pole_ra"):
		pole = OrbitMath.equatorial_to_scene(data["pole_ra"], data["pole_dec"])
		_pole_rotation = Quaternion(Vector3.UP, pole)
		body.quaternion = _pole_rotation

	if data.get("rings", false):
		var rings := _make_rings(radius)
		rings.quaternion = Quaternion(Vector3.UP, pole)
		add_child(rings)

	for moon_data in MoonData.MOONS:
		if moon_data["planet"] == data["name"]:
			var moon := Moon.new(moon_data, radius, data["radius_km"])
			add_child(moon)
			add_child(moon.orbit_line)
			_moons.append(moon)

	var label := Label3D.new()
	label.text = data["name"]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.pixel_size = 0.0004
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(1, 1, 1, 0.95)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.offset = Vector2(10, 12)
	label.render_priority = 10
	add_child(label)


## Moves the planet to where it is `days` after J2000.
func update_position(days: float, linear: bool) -> void:
	au_position = OrbitMath.position_at(data, days)
	position = OrbitMath.to_scene(au_position, linear)
	if data.has("w_rate"):
		# Spin about the (tilted) north pole: IAU prime meridian angle W = W0 + rate * days.
		var spin := deg_to_rad(fposmod(float(data["w0"]) + float(data["w_rate"]) * days, 360.0))
		_body.quaternion = _pole_rotation * Quaternion(Vector3.UP, spin)


## Moves the moons to where they are `days` after J2000. `camera_position` is in world space and
## decides whether moon labels and orbit lines are shown.
func update_moons(days: float, camera_position: Vector3) -> void:
	if _moons.is_empty():
		return
	var detail := global_position.distance_to(camera_position) < MOON_DETAIL_DISTANCE
	for moon in _moons:
		moon.update(days, detail)


## Points on the orbit ellipse in scene units, closed (first point repeated).
func orbit_points(linear: bool, segments: int = 256) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in segments + 1:
		var ecc := TAU * float(i) / float(segments)
		points.append(OrbitMath.to_scene(OrbitMath.position_au(data, ecc), linear))
	return points


func _make_rings(planet_radius: float) -> MeshInstance3D:
	var rings := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = planet_radius * 1.3
	torus.outer_radius = planet_radius * 2.0
	torus.rings = 64
	torus.ring_segments = 8
	rings.mesh = torus
	rings.scale = Vector3(1.0, 0.03, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.78, 0.6)
	material.roughness = 1.0
	rings.material_override = material
	return rings
