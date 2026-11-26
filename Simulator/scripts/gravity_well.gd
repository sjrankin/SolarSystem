class_name GravityWell
extends MeshInstance3D
## A fine grid below the ecliptic that sags into the summed gravity wells of the Sun and planets.
##
## Depth is exaggerated and compressed so that planet-sized wells are visible next to the Sun's:
## each body's display depth is SUN_DEPTH * (mass / Sun mass) ^ DEPTH_EXPONENT, and its width is
## WIDTH_FACTOR times its drawn radius. The wells still add up, so they merge (with saddle points
## such as the Sun-Jupiter L1) where bodies are close together.

const GRID_RESOLUTION := 700
const SUN_DEPTH := 55.0
const DEPTH_EXPONENT := 0.2
const WIDTH_FACTOR := 3.0
## The Sun gets a wider well so its funnel has a gentler shoulder.
const SUN_WIDTH_FACTOR := 5.0
## Height of the undisturbed sheet relative to the ecliptic plane.
const SHEET_HEIGHT := -6.0
const COMPRESSED_EXTENT := 520.0
const LINEAR_EXTENT := 1100.0
## Smallest area (half-width, scene units) the mesh shrinks to when zoomed in.
const MIN_HALF_EXTENT := 25.0
## Mesh half-width as a multiple of the camera distance.
const EXTENT_PER_DISTANCE := 2.5
## How strongly vertices bunch toward the centre of the mesh (0 = uniform).
const CONCENTRATION := 2.0
## Grid-line spacing at the default view: 10% finer than the original 110 lines across.
const GRID_SPACING_SCALE := 0.9
const GRID_LINES_ACROSS := 110.0
const MAX_BODIES := 12

var _material := ShaderMaterial.new()
var _sun_radius: float
var _linear := false


func _init(sun_radius: float) -> void:
	name = "GravityWell"
	_sun_radius = sun_radius
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = GRID_RESOLUTION - 1
	plane.subdivide_depth = GRID_RESOLUTION - 1
	mesh = plane
	# Vertices are repositioned and displaced in the shader, so the culling box must be generous.
	custom_aabb = AABB(Vector3(-6000.0, -400.0, -6000.0), Vector3(12000.0, 500.0, 12000.0))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shader = load("res://shaders/gravity_well.gdshader")
	_material.set_shader_parameter("linear_units_per_au", OrbitMath.LINEAR_UNITS_PER_AU)
	_material.set_shader_parameter("compressed_units", OrbitMath.COMPRESSED_UNITS)
	_material.set_shader_parameter("max_depth", SUN_DEPTH * 1.1)
	_material.set_shader_parameter("concentration", CONCENTRATION)
	_material.set_shader_parameter("grid_base_spacing", GRID_SPACING_SCALE * 2.0 * COMPRESSED_EXTENT / GRID_LINES_ACROSS)
	material_override = _material
	position = Vector3(0.0, SHEET_HEIGHT, 0.0)
	set_linear(false)


## Switches between the linear and compressed distance scales.
func set_linear(linear: bool) -> void:
	_linear = linear
	_material.set_shader_parameter("linear_scale", linear)


## Re-centres the mesh on the camera target and sizes it to the zoom level, so vertices (and
## grid lines) get finer as the camera moves in.
func follow(camera: OrbitCamera) -> void:
	var max_extent := LINEAR_EXTENT if _linear else COMPRESSED_EXTENT
	var half_extent := clampf(camera.distance * EXTENT_PER_DISTANCE, MIN_HALF_EXTENT, max_extent)
	_material.set_shader_parameter("center", Vector2(camera.target.x, camera.target.z))
	_material.set_shader_parameter("half_extent", half_extent)
	# One octave of grid spacing per doubling of the covered area, relative to the default view.
	_material.set_shader_parameter("grid_level", log(half_extent / COMPRESSED_EXTENT) / log(2.0))


## Pushes the current body positions to the shader.
func update_bodies(planets: Array[Planet]) -> void:
	var bodies := PackedVector4Array()
	bodies.append(_body_vector(Vector3.ZERO, Vector3.ZERO, _sun_radius * SUN_WIDTH_FACTOR / WIDTH_FACTOR, 1.0))
	for planet in planets:
		bodies.append(_body_vector(planet.au_position, planet.position, planet.data["radius"], planet.data["mass"]))
	var count := bodies.size()
	bodies.resize(MAX_BODIES)
	_material.set_shader_parameter("body_count", count)
	_material.set_shader_parameter("bodies", bodies)


func _body_vector(au_position: Vector3, scene_position: Vector3, radius: float, mass: float) -> Vector4:
	# Softening length: the AU distance spanned by WIDTH_FACTOR drawn radii, measured radially
	# outward from the body, so wells look the same size in either distance mode.
	var scene_radius := Vector2(scene_position.x, scene_position.z).length()
	var width := WIDTH_FACTOR * radius
	var softening := maxf(_scene_to_au(scene_radius + width) - _scene_to_au(scene_radius), 1e-6)
	var depth := SUN_DEPTH * pow(mass, DEPTH_EXPONENT)
	return Vector4(au_position.x, au_position.z, softening, depth)


func _scene_to_au(scene_radius: float) -> float:
	if _linear:
		return scene_radius / OrbitMath.LINEAR_UNITS_PER_AU
	return pow(scene_radius / OrbitMath.COMPRESSED_UNITS, 2.0)
