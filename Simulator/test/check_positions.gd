extends SceneTree
## Headless sanity checks: godot --headless --path . --script res://test/check_positions.gd

var failures := 0


func _init() -> void:
	# At J2000 the Earth's heliocentric ecliptic longitude is ~100.46 - small eccentricity terms (~100.5 deg).
	var earth: Dictionary = PlanetData.PLANETS[2]
	_check_longitude(earth, 0.0, 100.4, 0.6, "Earth at J2000")

	# Earth on 2026-11-18: Sun's geocentric longitude ~236 deg, so Earth's heliocentric ~56 deg.
	var days := OrbitMath.days_since_j2000(Time.get_unix_time_from_datetime_string("2026-11-18T12:00:00"))
	_check_longitude(earth, days, 56.0, 1.5, "Earth on 2026-11-18")

	# Distances stay within perihelion/aphelion for every planet over a long span.
	for planet in PlanetData.PLANETS:
		var a: float = planet["a"]
		var e: float = planet["e"]
		for step in 400:
			var r := OrbitMath.position_at(planet, step * 97.0).length()
			if r < a * (1.0 - e) - 1e-6 or r > a * (1.0 + e) + 1e-6:
				failures += 1
				print("FAIL radius out of range for ", planet["name"])
				break

	# One full period returns a planet to the same place.
	for planet in PlanetData.PLANETS:
		var p0 := OrbitMath.position_at(planet, 1000.0)
		var p1 := OrbitMath.position_at(planet, 1000.0 + float(planet["period"]))
		if p0.distance_to(p1) > 1e-3 * float(planet["a"]):
			failures += 1
			print("FAIL period for ", planet["name"], " ", p0.distance_to(p1))

	# Saturn's ring tilt seen from Earth: about -26.7 deg at the 2002-10 maximum, ~0 at the 2025-03 crossing.
	_check_ring_tilt("2002-10-15T00:00:00", -26.7, 0.5)
	_check_ring_tilt("2025-03-23T00:00:00", 0.0, 1.0)

	# Angle between each IAU north pole and the orbit normal. For Venus, Uranus and Pluto this is
	# 180 deg minus the usual "obliquity" (177.36, 97.77), which is measured from the retrograde spin
	# direction; the IAU pole is the geographic north, so the tilt is the supplement.
	var tilts := {"Mercury": 0.03, "Venus": 2.64, "Earth": 23.44, "Mars": 25.19, "Jupiter": 3.13,
		"Saturn": 26.73, "Uranus": 82.23, "Neptune": 28.32, "Pluto": 119.6}
	for planet in PlanetData.PLANETS:
		_check_axial_tilt(planet, tilts[planet["name"]], 0.6)

	_check_moons()
	_check_rotation()

	print("position checks: ", "OK" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _check_longitude(planet: Dictionary, days: float, expected_deg: float, tolerance: float, label: String) -> void:
	var p := OrbitMath.position_at(planet, days)
	# Scene axes: x = ecliptic x, z = -ecliptic y.
	var longitude := fposmod(rad_to_deg(atan2(-p.z, p.x)), 360.0)
	var ok := absf(angle_difference(deg_to_rad(longitude), deg_to_rad(expected_deg))) < deg_to_rad(tolerance)
	if not ok:
		failures += 1
	print("%s: longitude %.2f deg (expected ~%.1f) %s" % [label, longitude, expected_deg, "ok" if ok else "FAIL"])


func _check_ring_tilt(date: String, expected_deg: float, tolerance: float) -> void:
	var days := OrbitMath.days_since_j2000(Time.get_unix_time_from_datetime_string(date))
	var saturn: Dictionary = PlanetData.PLANETS[5]
	var pole := OrbitMath.equatorial_to_scene(saturn["pole_ra"], saturn["pole_dec"])
	var to_earth := OrbitMath.position_at(PlanetData.PLANETS[2], days) - OrbitMath.position_at(saturn, days)
	var tilt := rad_to_deg(asin(pole.dot(to_earth.normalized())))
	var ok := absf(tilt - expected_deg) < tolerance
	if not ok:
		failures += 1
	print("Saturn ring tilt on %s: %.2f deg (expected ~%.1f) %s" % [date, tilt, expected_deg, "ok" if ok else "FAIL"])


func _check_axial_tilt(planet: Dictionary, expected_deg: float, tolerance: float) -> void:
	var pole := OrbitMath.equatorial_to_scene(planet["pole_ra"], planet["pole_dec"])
	var inc := deg_to_rad(float(planet["i"]))
	var node := deg_to_rad(float(planet["node"]))
	# Orbit normal in ecliptic axes, converted to scene axes (x, z, -y).
	var normal := Vector3(sin(inc) * sin(node), cos(inc), sin(inc) * cos(node))
	var tilt := rad_to_deg(pole.angle_to(normal))
	var ok := absf(tilt - expected_deg) < tolerance
	if not ok:
		failures += 1
	print("%s axial tilt %.2f deg (expected %.2f) %s" % [planet["name"], tilt, expected_deg, "ok" if ok else "FAIL"])


func _moon(name: String) -> Dictionary:
	for moon in MoonData.MOONS:
		if moon["name"] == name:
			return moon
	return {}


func _lon_lat(v: Vector3) -> Vector2:
	return Vector2(fposmod(rad_to_deg(atan2(-v.z, v.x)), 360.0), rad_to_deg(asin(v.y / v.length())))


func _expect(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
	print("%s %s" % [text, "ok" if ok else "FAIL"])


func _check_moons() -> void:
	var moon := _moon("Moon")
	# Geocentric ecliptic longitude of the Moon at J2000 was ~223.3 deg (mean elements: +/- ~1.5).
	var at_j2000 := _lon_lat(OrbitMath.satellite_position_km(moon, 0.0))
	_expect(absf(angle_difference(deg_to_rad(at_j2000.x), deg_to_rad(223.3))) < deg_to_rad(2.0),
		"Moon longitude at J2000: %.2f deg (expected ~223.3)" % at_j2000.x)

	# Full Moon 2026-11-24 ~14:53 UTC: the Moon is opposite the Sun (Sun longitude = Earth's + 180).
	var days := OrbitMath.days_since_j2000(Time.get_unix_time_from_datetime_string("2026-11-24T14:53:00"))
	var earth_lon := _lon_lat(OrbitMath.position_at(PlanetData.PLANETS[2], days)).x
	var moon_lon := _lon_lat(OrbitMath.satellite_position_km(moon, days)).x
	var elongation := absf(rad_to_deg(angle_difference(deg_to_rad(moon_lon), deg_to_rad(earth_lon))))
	_expect(absf(elongation) < 4.0, "Moon at the 2026-11-24 full moon: %.1f deg from Earth's heliocentric longitude (the Sun is opposite; expected ~0)" % elongation)

	# Each orbit's plane should sit near its planet's equator (tiny inclination to the Laplace plane).
	_check_plane("Io", 4, 1.0)
	_check_plane("Ganymede", 4, 1.0)
	_check_plane("Enceladus", 5, 1.0)
	_check_plane("Titan", 5, 1.5)
	# Uranian moons orbit in Uranus's equator (spin pole is opposite the IAU "north" pole).
	_check_plane_to_pole("Ariel", 77.311, 15.175, 0.0, 1.0)
	_check_plane_to_pole("Titania", 77.311, 15.175, 0.0, 1.0)
	_check_plane_to_pole("Miranda", 77.311, 15.175, 4.4, 1.0)
	# Triton is retrograde: its orbit normal is 157.3 deg from Neptune's pole.
	_check_plane_to_pole("Triton", 299.36, 43.46, 157.3, 1.0)
	_check_plane_to_pole("Proteus", 299.36, 43.46, 0.6, 1.0)

	# After one orbital period a moon is back near the same place.
	for sat in MoonData.MOONS:
		var p0 := OrbitMath.satellite_position_km(sat, 4000.0)
		var p1 := OrbitMath.satellite_position_km(sat, 4000.0 + float(sat["period_days"]))
		_expect(p0.distance_to(p1) < 0.05 * float(sat["a_km"]), "%s returns after one period (%.1f%% of a)" % [sat["name"], 100.0 * p0.distance_to(p1) / float(sat["a_km"])])

	# Radii stay between periapsis and apoapsis.
	for sat in MoonData.MOONS:
		var a: float = sat["a_km"]
		var e: float = sat["e"]
		var worst := true
		for step in 200:
			var r := OrbitMath.satellite_position_km(sat, step * 1.7).length()
			if r < a * (1.0 - e) - 1.0 or r > a * (1.0 + e) + 1.0:
				worst = false
		_expect(worst, "%s radius within periapsis/apoapsis" % sat["name"])


## The orbit normal of a moon should lie within `tolerance_deg` of its planet's pole.
func _check_plane(moon_name: String, planet_index: int, tolerance_deg: float) -> void:
	var sat := _moon(moon_name)
	var days := 3000.0
	var p0 := OrbitMath.satellite_position_km(sat, days)
	var p1 := OrbitMath.satellite_position_km(sat, days + float(sat["period_days"]) * 0.25)
	var normal := p0.cross(p1).normalized()
	var planet: Dictionary = PlanetData.PLANETS[planet_index]
	var pole := OrbitMath.equatorial_to_scene(planet["pole_ra"], planet["pole_dec"])
	var angle := rad_to_deg(normal.angle_to(pole))
	_expect(angle < tolerance_deg, "%s orbit normal is %.2f deg from %s's pole" % [moon_name, angle, planet["name"]])


func _check_rotation() -> void:
	# Spin angle over 0.1 day should be 0.1 * IAU rate (Earth: 36.1 deg/0.1 d; Venus retrograde).
	for entry in [["Earth", 36.09856], ["Jupiter", 87.0536], ["Venus", 0.14814], ["Uranus", 50.116]]:
		var planet: Planet
		for candidate in PlanetData.PLANETS:
			if candidate["name"] == entry[0]:
				planet = Planet.new(candidate)
		planet.update_position(1000.0, false)
		var before := planet._body.quaternion
		planet.update_position(1000.1, false)
		var turned := rad_to_deg(before.angle_to(planet._body.quaternion))
		_expect(absf(turned - fposmod(entry[1], 180.0) if entry[1] < 180.0 else 0.0) < 0.05,
			"%s spins %.3f deg in 0.1 day (expected %.3f)" % [entry[0], turned, entry[1]])
		# Direction: prograde spin turns counter-clockwise about the north pole (positive dot product);
		# Venus and Uranus rotate retrograde about the IAU north pole.
		var delta := planet._body.quaternion * before.inverse()
		var pole := OrbitMath.equatorial_to_scene(planet.data["pole_ra"], planet.data["pole_dec"])
		var prograde: bool = float(planet.data["w_rate"]) > 0.0
		_expect((delta.get_axis().dot(pole) > 0.0) == prograde or delta.get_angle() > PI, "%s spin direction %s" % [entry[0], "prograde" if prograde else "retrograde"])
		planet.free()


## The orbit normal should be `expected_deg` from the pole at (ra, dec).
func _check_plane_to_pole(moon_name: String, ra: float, dec: float, expected_deg: float, tolerance_deg: float) -> void:
	var sat := _moon(moon_name)
	var days := 3000.0
	var p0 := OrbitMath.satellite_position_km(sat, days)
	var p1 := OrbitMath.satellite_position_km(sat, days + float(sat["period_days"]) * 0.25)
	var angle := rad_to_deg(p0.cross(p1).normalized().angle_to(OrbitMath.equatorial_to_scene(ra, dec)))
	_expect(absf(angle - expected_deg) < tolerance_deg, "%s orbit normal is %.2f deg from the pole (expected %.1f)" % [moon_name, angle, expected_deg])
