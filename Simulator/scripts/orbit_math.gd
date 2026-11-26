class_name OrbitMath
extends RefCounted
## Keplerian orbit maths: orbital elements + time -> heliocentric position.

## Unix timestamp of the J2000 epoch (2000-01-01 12:00 UTC).
const J2000_UNIX := 946728000.0
const SECONDS_PER_DAY := 86400.0

## Scene units per AU in linear mode.
const LINEAR_UNITS_PER_AU := 20.0
## In compressed mode the view distance is COMPRESSED_UNITS * sqrt(AU), so the
## inner planets stay readable next to Pluto. Directions are unchanged.
const COMPRESSED_UNITS := 60.0


## Solves Kepler's equation M = E - e sin E for the eccentric anomaly E (radians).
static func solve_kepler(mean_anomaly: float, e: float) -> float:
	var m := wrapf(mean_anomaly, -PI, PI)
	var ecc_anomaly := m if e < 0.8 else PI
	for _i in 20:
		var delta := (ecc_anomaly - e * sin(ecc_anomaly) - m) / (1.0 - e * cos(ecc_anomaly))
		ecc_anomaly -= delta
		if absf(delta) < 1e-12:
			break
	return ecc_anomaly


## Days elapsed since J2000 for a Unix timestamp.
static func days_since_j2000(unix_time: float) -> float:
	return (unix_time - J2000_UNIX) / SECONDS_PER_DAY


## Mean anomaly (radians) of a planet `days` after J2000.
static func mean_anomaly(planet: Dictionary, days: float) -> float:
	var m0 := deg_to_rad(float(planet["L"]) - float(planet["varpi"]))
	return m0 + TAU / float(planet["period"]) * days


## Position in the orbital frame for a given eccentric anomaly: x toward the reference node,
## z along the reference pole. Angles in radians; `a` in any length unit.
static func orbital_plane_position(a: float, e: float, inc: float, node: float, omega: float, ecc_anomaly: float) -> Vector3:
	# Position in the orbital plane, periapsis along +x.
	var xv := a * (cos(ecc_anomaly) - e)
	var yv := a * sqrt(1.0 - e * e) * sin(ecc_anomaly)

	var cw := cos(omega)
	var sw := sin(omega)
	var cn := cos(node)
	var sn := sin(node)
	var ci := cos(inc)
	var si := sin(inc)

	var x := (cw * cn - sw * sn * ci) * xv + (-sw * cn - cw * sn * ci) * yv
	var y := (cw * sn + sw * cn * ci) * xv + (-sw * sn + cw * cn * ci) * yv
	var z := (sw * si) * xv + (cw * si) * yv
	return Vector3(x, y, z)


## Heliocentric position in AU for a given eccentric anomaly, in scene axes
## (ecliptic plane is XZ, ecliptic north is +Y).
static func position_au(planet: Dictionary, ecc_anomaly: float) -> Vector3:
	var omega := deg_to_rad(float(planet["varpi"]) - float(planet["node"]))
	var v := orbital_plane_position(planet["a"], planet["e"], deg_to_rad(float(planet["i"])),
		deg_to_rad(float(planet["node"])), omega, ecc_anomaly)
	return Vector3(v.x, v.z, -v.y)


## Position in AU of a planet `days` after J2000.
static func position_at(planet: Dictionary, days: float) -> Vector3:
	var ecc := solve_kepler(mean_anomaly(planet, days), planet["e"])
	return position_au(planet, ecc)


## Converts a position in AU to scene units.
static func to_scene(au_position: Vector3, linear: bool) -> Vector3:
	var distance := au_position.length()
	if distance < 1e-9:
		return Vector3.ZERO
	var scaled := distance * LINEAR_UNITS_PER_AU if linear else sqrt(distance) * COMPRESSED_UNITS
	return au_position / distance * scaled


const OBLIQUITY := deg_to_rad(23.4392911)


## Scene-space unit vector for a direction given as J2000 equatorial right ascension and
## declination (degrees), e.g. a planet's north pole.
static func equatorial_to_scene(ra_deg: float, dec_deg: float) -> Vector3:
	var ra := deg_to_rad(ra_deg)
	var dec := deg_to_rad(dec_deg)
	return equatorial_vector_to_scene(Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)))


## Converts a vector in J2000 equatorial axes (x toward the equinox, z toward the celestial pole)
## to scene axes (ecliptic plane XZ, ecliptic north +Y).
static func equatorial_vector_to_scene(v: Vector3) -> Vector3:
	var ecliptic_y := v.y * cos(OBLIQUITY) + v.z * sin(OBLIQUITY)
	var ecliptic_z := -v.y * sin(OBLIQUITY) + v.z * cos(OBLIQUITY)
	return Vector3(v.x, ecliptic_z, -ecliptic_y)


const DAYS_PER_YEAR := 365.25


## Rates (degrees per day) of a satellite's apsidal advance, nodal motion and mean anomaly.
## Periapsis advances; the node regresses for prograde orbits and advances for retrograde ones
## (inclination above 90 degrees). The mean anomaly rate is what remains of the mean-longitude
## rate (360 / period) after removing both.
static func satellite_rates(sat: Dictionary) -> Dictionary:
	var omega_rate := 0.0
	if float(sat["papsis_years"]) > 0.0:
		omega_rate = 360.0 / (float(sat["papsis_years"]) * DAYS_PER_YEAR)
	var node_rate := 0.0
	if float(sat["pnode_years"]) > 0.0:
		var direction := -1.0 if cos(deg_to_rad(float(sat["i"]))) >= 0.0 else 1.0
		node_rate = direction * 360.0 / (float(sat["pnode_years"]) * DAYS_PER_YEAR)
	return {
		"omega": omega_rate,
		"node": node_rate,
		"mean_anomaly": 360.0 / float(sat["period_days"]) - omega_rate - node_rate,
	}


## Satellite position relative to its planet, in km, scene axes, `days` after J2000.
## `ecc_anomaly` may be passed (>= 0) to place the satellite elsewhere on the same orbit.
static func satellite_position_km(sat: Dictionary, days: float, ecc_anomaly_override: float = -1.0) -> Vector3:
	var rates := satellite_rates(sat)
	# Elements are given at an epoch (J2000 unless "epoch_days" says otherwise).
	var elapsed := days - float(sat.get("epoch_days", 0.0))
	var mean := deg_to_rad(float(sat["M"]) + float(rates["mean_anomaly"]) * elapsed)
	var node := deg_to_rad(float(sat["node"]) + float(rates["node"]) * elapsed)
	var omega := deg_to_rad(float(sat["omega"]) + float(rates["omega"]) * elapsed)
	var e: float = sat["e"]
	var ecc := ecc_anomaly_override if ecc_anomaly_override >= 0.0 else solve_kepler(mean, e)
	var local := orbital_plane_position(sat["a_km"], e, deg_to_rad(float(sat["i"])), node, omega, ecc)
	if sat.has("pole_ra"):
		# Laplace-plane frame: z along the plane's pole, x at the plane's node on the equator.
		var ra := deg_to_rad(float(sat["pole_ra"]))
		var dec := deg_to_rad(float(sat["pole_dec"]))
		var ez := Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
		var ex := Vector3(-sin(ra), cos(ra), 0.0)
		var ey := ez.cross(ex)
		return equatorial_vector_to_scene(ex * local.x + ey * local.y + ez * local.z)
	# Ecliptic frame (the Moon).
	return Vector3(local.x, local.z, -local.y)
