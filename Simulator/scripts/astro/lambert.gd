class_name Lambert
extends RefCounted
## Lambert's problem (the orbit through two points in a given time around the Sun, no complete revolutions) by the universal
## variable method, and propagation of an orbit by universal variables.


static func _stumpff_s(z: float) -> float:
	if z > 1e-6:
		var s := sqrt(z)
		return (s - sin(s)) / (s * s * s)
	if z < -1e-6:
		var s := sqrt(-z)
		return (sinh(s) - s) / (s * s * s)
	return 1.0 / 6.0 - z / 120.0 + z * z / 5040.0


static func _stumpff_c(z: float) -> float:
	if z > 1e-6:
		return (1.0 - cos(sqrt(z))) / z
	if z < -1e-6:
		return (cosh(sqrt(-z)) - 1.0) / -z
	return 0.5 - z / 24.0 + z * z / 720.0


## The orbit from `r1` to `r2` in `tof` days around a body with gravitational parameter `mu`.
## Returns {"ok": true, "v1": Vector3, "v2": Vector3} (velocities at the start and end), or {"ok": false}.
## `prograde` is the direction of travel about +z, which is how the planets go round.
static func solve(r1: Vector3, r2: Vector3, tof: float, mu: float, prograde: bool = true) -> Dictionary:
	var fail := {"ok": false}
	var r1m := r1.length()
	var r2m := r2.length()
	if tof <= 0.0 or r1m < 1e-9 or r2m < 1e-9:
		return fail
	var cross := r1.cross(r2)
	var angle := acos(clampf(r1.dot(r2) / (r1m * r2m), -1.0, 1.0))
	if (prograde and cross.z < 0.0) or (not prograde and cross.z >= 0.0):
		angle = TAU - angle
	var sin_angle := sin(angle)
	# A transfer straight out or straight back has no defined plane.
	if absf(sin_angle) < 1e-4:
		return fail
	var a_const := sin_angle * sqrt(r1m * r2m / (1.0 - cos(angle)))
	var sqrt_mu := sqrt(mu)

	var z_low := -4.0 * PI * PI
	var z_high := 4.0 * PI * PI - 1e-6
	# y must stay positive; raise the lower end until it does.
	var guard := 0
	while _y(z_low, r1m, r2m, a_const) < 0.0 and guard < 400:
		z_low += 0.25
		guard += 1
	var z := clampf(0.0, z_low, z_high)
	var converged := false
	for _i in 80:
		var y := _y(z, r1m, r2m, a_const)
		if y < 0.0:
			z_low = z
			z = 0.5 * (z + z_high)
			continue
		var s := _stumpff_s(z)
		var c := _stumpff_c(z)
		var f := pow(y / c, 1.5) * s + a_const * sqrt(y) - sqrt_mu * tof
		if f < 0.0:
			z_low = z
		else:
			z_high = z
		var df: float
		if absf(z) > 1e-6:
			df = pow(y / c, 1.5) * (1.0 / (2.0 * z) * (c - 1.5 * s / c) + 0.75 * s * s / c) \
				+ a_const / 8.0 * (3.0 * s / c * sqrt(y) + a_const * sqrt(c / y))
		else:
			df = sqrt(2.0) / 40.0 * pow(y, 1.5) + a_const / 8.0 * (sqrt(y) + a_const * sqrt(0.5 / y))
		var z_next := z - f / df
		if not is_finite(z_next) or z_next <= z_low or z_next >= z_high:
			z_next = 0.5 * (z_low + z_high)
		if absf(z_next - z) < 1e-11 * maxf(1.0, absf(z)):
			z = z_next
			converged = true
			break
		z = z_next
	if not converged:
		return fail
	var y_final := _y(z, r1m, r2m, a_const)
	if y_final <= 0.0:
		return fail
	var f_lagrange := 1.0 - y_final / r1m
	var g_lagrange := a_const * sqrt(y_final / mu)
	var g_dot := 1.0 - y_final / r2m
	if absf(g_lagrange) < 1e-14:
		return fail
	return {"ok": true, "v1": (r2 - f_lagrange * r1) / g_lagrange, "v2": (g_dot * r2 - r1) / g_lagrange}


static func _y(z: float, r1m: float, r2m: float, a_const: float) -> float:
	return r1m + r2m + a_const * (z * _stumpff_s(z) - 1.0) / sqrt(_stumpff_c(z))


## The position and velocity [Vector3, Vector3] `dt` days after the state (`r0`, `v0`), moving freely around a body.
static func propagate(r0: Vector3, v0: Vector3, dt: float, mu: float) -> Array:
	var r0m := r0.length()
	var sqrt_mu := sqrt(mu)
	var vr0 := r0.dot(v0) / r0m
	var alpha := 2.0 / r0m - v0.length_squared() / mu
	var chi := sqrt_mu * absf(alpha) * dt
	for _i in 100:
		var z := alpha * chi * chi
		var c := _stumpff_c(z)
		var s := _stumpff_s(z)
		var f := r0m * vr0 / sqrt_mu * chi * chi * c + (1.0 - alpha * r0m) * chi * chi * chi * s + r0m * chi - sqrt_mu * dt
		var df := r0m * vr0 / sqrt_mu * chi * (1.0 - alpha * chi * chi * s) + (1.0 - alpha * r0m) * chi * chi * c + r0m
		var ratio := f / df
		chi -= ratio
		if absf(ratio) < 1e-10:
			break
	var z_final := alpha * chi * chi
	var c_final := _stumpff_c(z_final)
	var s_final := _stumpff_s(z_final)
	var f_lagrange := 1.0 - chi * chi / r0m * c_final
	var g_lagrange := dt - chi * chi * chi / sqrt_mu * s_final
	var r := f_lagrange * r0 + g_lagrange * v0
	var rm := r.length()
	var f_dot := sqrt_mu / (rm * r0m) * (alpha * chi * chi * chi * s_final - chi)
	var g_dot := 1.0 - chi * chi / rm * c_final
	return [r, f_dot * r0 + g_dot * v0]


## Closest distance to the central body of the orbit through (`r`, `v`).
static func periapsis(r: Vector3, v: Vector3, mu: float) -> float:
	var h := r.cross(v)
	var e_vec := v.cross(h) / mu - r / r.length()
	return h.length_squared() / mu / (1.0 + e_vec.length())
