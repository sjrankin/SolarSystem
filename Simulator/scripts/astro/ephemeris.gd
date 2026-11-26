class_name Ephemeris
extends RefCounted
## Planet positions and velocities for trajectory planning, in the ecliptic frame (x toward the equinox, z toward ecliptic north),
## AU and AU/day. The simulator's scene axes are (x, z, -y) of this frame (see `OrbitMath.position_au`).


static func position(body: int, days: float) -> Vector3:
	var scene := OrbitMath.position_at(PlanetData.PLANETS[body], days)
	return Vector3(scene.x, -scene.z, scene.y)


## Position and velocity of a planet: [Vector3, Vector3]. The velocity is a central difference of the orbit, which is as exact as
## the orbit itself for this purpose.
static func state(body: int, days: float) -> Array:
	var h := 0.05
	var ahead := position(body, days + h)
	var behind := position(body, days - h)
	return [position(body, days), (ahead - behind) / (2.0 * h)]


## A point of the ecliptic frame in the simulator's scene axes (still in AU).
static func to_scene_axes(ecliptic: Vector3) -> Vector3:
	return Vector3(ecliptic.x, ecliptic.z, -ecliptic.y)
