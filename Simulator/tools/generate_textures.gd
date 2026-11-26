extends SceneTree
## Generates equirectangular surface textures for the Sun and planets into res://textures/.
## Run: godot --headless --path . --script res://tools/generate_textures.gd
## Then re-import: godot --headless --path . --import
##
## The textures are procedural approximations (noise on a sphere, so they are seamless and
## have no pole pinching). To use real maps instead, drop PNG/JPG files named
## textures/<Name>.png (e.g. Earth.png) over these and re-import.

const WIDTH := 1024
const HEIGHT := 512
const BODIES: Array[String] = [
	"Sun", "Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
]

var _noise := FastNoiseLite.new()
var _cells := FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	_noise.frequency = 1.0
	_cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	_cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_cells.frequency = 1.0

	var directory := ProjectSettings.globalize_path("res://textures")
	DirAccess.make_dir_recursive_absolute(directory)
	for body in BODIES:
		_noise.seed = hash(body)
		_cells.seed = hash(body) + 7
		var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
		for y in HEIGHT:
			var lat := (0.5 - (y + 0.5) / HEIGHT) * PI
			var cos_lat := cos(lat)
			var sin_lat := sin(lat)
			for x in WIDTH:
				var lon := (x + 0.5) / WIDTH * TAU
				var p := Vector3(cos_lat * cos(lon), sin_lat, cos_lat * sin(lon))
				image.set_pixel(x, y, _color(body, p, lat, lon))
		var path := directory.path_join("%s.png" % body)
		image.save_png(path)
		print("wrote ", path)
	quit()


## Fractal noise remapped to 0..1 at scale `freq`.
func _fbm(p: Vector3, freq: float) -> float:
	return clampf(_noise.get_noise_3d(p.x * freq, p.y * freq, p.z * freq) * 0.5 + 0.5, 0.0, 1.0)


## Soft 0..1 weight for a blob centred on (lon0, lat0) with radii in radians.
func _blob(lon: float, lat: float, lon0: float, lat0: float, radius_lon: float, radius_lat: float) -> float:
	var dx := angle_difference(lon0, lon) * cos(lat)
	var dy := lat - lat0
	var d := (dx / radius_lon) * (dx / radius_lon) + (dy / radius_lat) * (dy / radius_lat)
	return clampf(1.0 - d, 0.0, 1.0)


func _color(body: String, p: Vector3, lat: float, lon: float) -> Color:
	match body:
		"Sun": return _sun(p)
		"Mercury": return _mercury(p)
		"Venus": return _venus(p)
		"Earth": return _earth(p, lat)
		"Mars": return _mars(p, lat)
		"Jupiter": return _jupiter(p, lat, lon)
		"Saturn": return _banded(p, Color(0.62, 0.52, 0.36), Color(0.93, 0.84, 0.62), 11.0, 0.35)
		"Uranus": return _banded(p, Color(0.52, 0.78, 0.82), Color(0.68, 0.9, 0.92), 6.0, 0.12)
		"Neptune": return _neptune(p)
		"Pluto": return _pluto(p, lat, lon)
	return Color.MAGENTA


func _sun(p: Vector3) -> Color:
	var large := _fbm(p, 3.0)
	var fine := _fbm(p, 22.0)
	var heat := clampf(large * 1.3 + (fine - 0.5) * 0.5, 0.0, 1.0)
	return Color(0.95, 0.4, 0.05).lerp(Color(1.0, 0.95, 0.55), heat)


func _mercury(p: Vector3) -> Color:
	var shade := 0.42 + 0.3 * _fbm(p, 4.0) + 0.08 * (_fbm(p, 30.0) - 0.5)
	for scale in [5.0, 11.0]:
		var c := _cells.get_noise_3d(p.x * scale, p.y * scale, p.z * scale)
		shade *= lerpf(0.72, 1.0, smoothstep(-1.0, -0.45, c))
		shade += 0.12 * (1.0 - absf(c + 0.35) * 6.0) if absf(c + 0.35) < 0.16 else 0.0
	return Color(shade, shade * 0.97, shade * 0.93)


func _venus(p: Vector3) -> Color:
	var warped := Vector3(p.x, p.y * 3.0, p.z)
	var v := _fbm(warped, 2.5)
	var streak := _fbm(warped + Vector3(v, 0, v), 5.0)
	return Color(0.82, 0.6, 0.28).lerp(Color(0.96, 0.87, 0.62), clampf(v * 0.6 + streak * 0.5, 0.0, 1.0))


func _earth(p: Vector3, lat: float) -> Color:
	var elevation := _fbm(p, 2.0)
	var sea_level := 0.55
	var color: Color
	if elevation < sea_level:
		var depth := elevation / sea_level
		color = Color(0.02, 0.07, 0.28).lerp(Color(0.1, 0.38, 0.65), depth * depth)
	else:
		var height := (elevation - sea_level) / (1.0 - sea_level)
		var dryness := _fbm(p + Vector3(5, 5, 5), 3.0)
		var green := Color(0.16, 0.42, 0.14).lerp(Color(0.36, 0.45, 0.2), dryness)
		if absf(lat) < deg_to_rad(35.0) and dryness > 0.5:
			green = green.lerp(Color(0.78, 0.66, 0.4), smoothstep(0.5, 0.65, dryness))
		color = green.lerp(Color(0.45, 0.38, 0.3), smoothstep(0.25, 0.7, height))
		color = color.lerp(Color(0.95, 0.95, 0.97), smoothstep(0.75, 0.95, height))
	var ice_edge := deg_to_rad(74.0) - _fbm(p, 6.0) * deg_to_rad(8.0)
	if absf(lat) > ice_edge:
		color = Color(0.93, 0.96, 0.98)
	var cloud := smoothstep(0.55, 0.78, _fbm(p + Vector3(9, 1, 3), 3.5))
	return color.lerp(Color.WHITE, cloud * 0.75)


func _mars(p: Vector3, lat: float) -> Color:
	var base := Color(0.66, 0.32, 0.16).lerp(Color(0.8, 0.5, 0.3), _fbm(p, 6.0))
	var dark := smoothstep(0.52, 0.68, _fbm(p, 1.8))
	var color := base.lerp(Color(0.3, 0.16, 0.1), dark * 0.7)
	var cap_edge := deg_to_rad(82.0) - _fbm(p, 8.0) * deg_to_rad(4.0)
	if absf(lat) > cap_edge:
		color = Color(0.95, 0.94, 0.92)
	return color


func _jupiter(p: Vector3, lat: float, lon: float) -> Color:
	var turbulence := _fbm(Vector3(p.x * 2.0, p.y * 0.5, p.z * 2.0), 3.0) - 0.5
	var band := 0.5 + 0.5 * sin(p.y * 16.0 + turbulence * 7.0)
	var detail := _fbm(Vector3(p.x, p.y * 6.0, p.z), 8.0)
	var color := Color(0.62, 0.38, 0.24).lerp(Color(0.93, 0.85, 0.7), clampf(band * 0.8 + detail * 0.3 - 0.1, 0.0, 1.0))
	var spot := _blob(lon, lat, PI, deg_to_rad(-22.0), 0.3, deg_to_rad(8.0))
	return color.lerp(Color(0.74, 0.3, 0.2), smoothstep(0.0, 0.5, spot))


## Soft horizontal bands, used for Saturn and Uranus.
func _banded(p: Vector3, dark: Color, light: Color, frequency: float, contrast: float) -> Color:
	var turbulence := _fbm(Vector3(p.x * 2.0, p.y * 0.4, p.z * 2.0), 3.0) - 0.5
	var band := 0.5 + 0.5 * sin(p.y * frequency + turbulence * 5.0)
	var detail := _fbm(Vector3(p.x, p.y * 5.0, p.z), 7.0)
	return dark.lerp(light, clampf(0.5 + (band - 0.5) * contrast * 2.0 + (detail - 0.5) * 0.2, 0.0, 1.0))


func _neptune(p: Vector3) -> Color:
	var color := _banded(p, Color(0.14, 0.26, 0.72), Color(0.24, 0.42, 0.92), 8.0, 0.4)
	var streaks := smoothstep(0.62, 0.8, _fbm(Vector3(p.x, p.y * 4.0, p.z), 5.0))
	return color.lerp(Color(0.85, 0.92, 1.0), streaks * 0.6)


func _pluto(p: Vector3, lat: float, lon: float) -> Color:
	var mottling := _fbm(p, 4.0)
	var color := Color(0.5, 0.36, 0.28).lerp(Color(0.78, 0.64, 0.5), mottling)
	color = color.lerp(Color(0.3, 0.2, 0.17), smoothstep(0.62, 0.78, _fbm(p, 2.0)) * 0.6)
	var heart := _blob(lon, lat, PI, deg_to_rad(15.0), 0.6, deg_to_rad(28.0))
	return color.lerp(Color(0.96, 0.9, 0.84), smoothstep(0.0, 0.4, heart) * 0.85)
