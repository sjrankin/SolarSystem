class_name Moon
extends Node3D
## A moon orbiting a planet, drawn well clear of the planet's sphere.
##
## The real orbit (from the JPL mean elements) is scaled radially about the planet: real distances
## would put the moons far outside or inside the exaggerated planet spheres. The scaled distance is
## planet_radius * (BASE + PER_SQRT * sqrt(real distance / planet's real radius)), which keeps the
## moons in their real order and phase while keeping them visible. Moons do not affect the
## gravity-well grid.

const BASE_DISTANCE := 1.6
const PER_SQRT_DISTANCE := 0.55
const ORBIT_POINTS := 96

var data: Dictionary
## The orbit line; the planet adds it as a sibling so it stays centred on the planet.
var orbit_line := MeshInstance3D.new()

var _label := Label3D.new()
## Scene units per kilometre for this moon's orbit.
var _scale := 1.0


func _init(moon_data: Dictionary, planet_radius: float, planet_radius_km: float) -> void:
	data = moon_data
	name = data["name"]
	var a_km: float = data["a_km"]
	var distance := planet_radius * (BASE_DISTANCE + PER_SQRT_DISTANCE * sqrt(a_km / planet_radius_km))
	_scale = distance / a_km
	var color: Color = data["color"]

	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = data["radius"]
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	body.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	body.material_override = material
	add_child(body)

	_label.text = data["name"]
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.pixel_size = 0.0004
	_label.font_size = 32
	_label.outline_size = 8
	_label.modulate = Color(0.85, 0.9, 1.0, 0.9)
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.offset = Vector2(8, 10)
	_label.render_priority = 10
	add_child(_label)

	orbit_line.name = "%sOrbit" % data["name"]
	orbit_line.mesh = ImmediateMesh.new()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(color.lerp(Color.WHITE, 0.4), 0.4)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orbit_line.material_override = line_material
	orbit_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Places the moon `days` after J2000. With `detail` the label and orbit line are shown
## (they are hidden when zoomed out, where they would only add clutter).
func update(days: float, detail: bool) -> void:
	position = OrbitMath.satellite_position_km(data, days) * _scale
	_label.visible = detail
	orbit_line.visible = detail
	if detail:
		_rebuild_orbit_line(days)


func _rebuild_orbit_line(days: float) -> void:
	var mesh := orbit_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in ORBIT_POINTS + 1:
		var ecc := TAU * float(i) / float(ORBIT_POINTS)
		mesh.surface_add_vertex(OrbitMath.satellite_position_km(data, days, ecc) * _scale)
	mesh.surface_end()
