class_name Astro
extends RefCounted
## Units and body data for trajectory planning. Distances are in AU, times in days, so speeds are
## AU/day (convert with KMS_PER_AU_DAY), and gravitational parameters are in AU^3/day^2.

## Gravitational parameter of the Sun (the Gaussian constant squared), AU^3/day^2.
const MU_SUN := 2.959122082855911e-4
const AU_KM := 149597870.7
## Multiply AU/day by this to get km/s.
const KMS_PER_AU_DAY := AU_KM / 86400.0


static func body_count() -> int:
	return PlanetData.PLANETS.size()


static func body_name(index: int) -> String:
	return PlanetData.PLANETS[index]["name"]


## Index into `PlanetData.PLANETS` for a name (any case), or -1.
static func find_body(planet_name: String) -> int:
	var wanted := planet_name.strip_edges().to_lower()
	for index in body_count():
		if body_name(index).to_lower() == wanted:
			return index
	return -1


## Gravitational parameter of a planet (AU^3/day^2). Planet masses in `PlanetData` are relative to the Sun, so for Earth this is
## the Earth-Moon system.
static func mu(index: int) -> float:
	return float(PlanetData.PLANETS[index]["mass"]) * MU_SUN


## Radius of the closest circular orbit used at a planet, and the closest a fly-by may come, in AU: 300 km above the surface or 20% of the
## radius above it, whichever is higher (so the gas giants are not entered at their cloud tops).
static func park_radius_au(index: int) -> float:
	var radius_km := float(PlanetData.PLANETS[index]["radius_km"])
	return maxf(radius_km + 300.0, radius_km * 1.2) / AU_KM


## Orbital period of a planet in days.
static func period(index: int) -> float:
	return float(PlanetData.PLANETS[index]["period"])


static func semi_major_axis(index: int) -> float:
	return float(PlanetData.PLANETS[index]["a"])


## Date text (YYYY-MM-DD) for a day count since J2000.
static func date_text(days: float) -> String:
	var unix := OrbitMath.J2000_UNIX + days * OrbitMath.SECONDS_PER_DAY
	return Time.get_date_string_from_unix_time(int(floor(unix)))
