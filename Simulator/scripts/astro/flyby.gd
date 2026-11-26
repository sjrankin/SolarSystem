class_name Flyby
extends RefCounted
## Passing a planet: the speed change a spacecraft needs, on top of what the planet's gravity gives free, to leave on the
## trajectory wanted. Patched conics: the planet's pull is a hyperbola around it, and the velocities relative to the planet far
## away ("v-infinity") are what the heliocentric legs give.


## Total angle the path turns through a hyperbolic pass with closest distance `rp`, arriving at speed `vi` and leaving at `vo`
## (relative to the planet; they differ if there is an engine burn at closest approach).
static func turn_angle(rp: float, vi: float, vo: float, mu: float) -> float:
	return asin(1.0 / (1.0 + rp * vi * vi / mu)) + asin(1.0 / (1.0 + rp * vo * vo / mu))


## The speed change needed to arrive with relative velocity `vin` and leave with `vout` (AU/day, relative to the planet), passing
## no closer than `rmin` to the planet's center. Returns {"dv": AU/day, "rp": closest distance used, "free": true if gravity alone
## could do the turn (the burn is only the speed difference at closest approach)}.
static func delta_v(vin: Vector3, vout: Vector3, mu: float, rmin: float) -> Dictionary:
	var vi := vin.length()
	var vo := vout.length()
	if vi < 1e-12 or vo < 1e-12:
		return {"dv": absf(vo - vi), "rp": rmin, "free": false}
	var wanted := vin.angle_to(vout)
	var most := turn_angle(rmin, vi, vo, mu)
	if wanted <= most:
		# Gravity turns the path enough. Find how close the pass must be, then burn only to change the speed there.
		var low := rmin
		var high := rmin * 1e6
		for _i in 60:
			var mid := sqrt(low * high)
			if turn_angle(mid, vi, vo, mu) > wanted:
				low = mid
			else:
				high = mid
		var rp := low
		return {"dv": absf(sqrt(vo * vo + 2.0 * mu / rp) - sqrt(vi * vi + 2.0 * mu / rp)), "rp": rp, "free": true}
	# The planet cannot turn the path far enough: take the biggest turn, and burn for the rest.
	var axis := vin.cross(vout)
	if axis.length() < 1e-12:
		axis = vin.cross(Vector3.UP)
		if axis.length() < 1e-12:
			axis = vin.cross(Vector3.RIGHT)
	var turned := vin.rotated(axis.normalized(), most)
	return {"dv": (vout - turned).length(), "rp": rmin, "free": false}
