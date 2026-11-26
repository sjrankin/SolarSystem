class_name FlightPlanner
extends RefCounted
## Plans a flight through a list of planets (origin, stops, destination).
##
## Every leg is a Lambert transfer between the planets' real positions at the departure and arrival times. A stop is an unpowered
## gravity assist where it can be, with an engine burn for whatever the planet's gravity cannot do. The cost of a plan mixes its
## total speed change (energy) and its duration, weighted by `time_weight`. The best plan is searched in two steps: a dynamic
## programme over a grid of times (exact for the grid, since each stop's cost depends only on the times before, at and after it), then
## a local refinement of the times themselves.
##
## Options (`plan`):
##   "time_weight": 0.0 (least speed change) to 1.0 (shortest time). Default 0.5.
##   "arrival": "capture" (end in a low orbit of the destination, the default) or "flyby" (just pass it).
##   "start_days": earliest departure, days since J2000.
##   "max_days": longest flight, days. 0 = no limit.
##   "max_dv_kms": most total speed change, km/s. 0 = no limit.
##   "grid": the number of grid steps (default 70), which sets how fine and how slow the search is.

const MIN_PERIHELION_AU := 0.12
## Reference speed change per leg and the default grid size.
const DV_REFERENCE_KMS := 6.0
const DEFAULT_GRID := 70
const SAMPLES_PER_LEG := 90

var _route: Array = []
var _legs := 0
var _time_weight := 0.5
var _capture := true
var _start := 0.0
var _step := 1.0
var _grid := 0
var _width := 0
var _min_steps: Array[int] = []
var _max_steps: Array[int] = []
var _dv_reference := 6.0
var _time_reference := 365.0
var _states := {}
var _leg_cache: Array[Dictionary] = []
var lambert_solves := 0


## Plans a flight through `route` (planet indices, at least two). Returns a Dictionary with "ok", and when it worked:
## "route" (names), "total_dv_kms", "total_days", "score", "times" (days since J2000 at each body), "events" (each with "body", "kind"
## `departure`, `flyby` or `arrival`, "time", "dv_kms", "v_inf_kms"), "legs" (each with "from", "to", "depart", "arrive", "samples":
## times and ecliptic positions in AU) and "lambert_solves". When it failed, "error" says why.
static func plan(route: Array, options: Dictionary = {}) -> Dictionary:
	var planner := FlightPlanner.new()
	var weight := clampf(float(options.get("time_weight", 0.5)), 0.03, 0.97)
	var max_dv := float(options.get("max_dv_kms", 0.0))
	var result := {"ok": false, "error": "No plan."}
	# A limit on the speed change is met by leaning towards energy until the plan fits.
	for _attempt in 5:
		var tried := options.duplicate()
		tried["time_weight"] = weight
		result = planner._run(route, tried)
		if not result["ok"] or max_dv <= 0.0 or float(result["total_dv_kms"]) <= max_dv:
			break
		weight *= 0.4
		planner = FlightPlanner.new()
		if _attempt == 4:
			result = {"ok": false, "error": "No plan within %.1f km/s was found." % max_dv}
	return result


## Plans flights for several candidate routes and picks the best one. The routes differ in length, so they are compared on a common
## scale (set by the first route, the one the user asked for) and not on the planner's own scores. Returns
## {"ok", "best": the plan, "all": every plan that worked with its "common_score", sorted best first, "failed": names of routes with
## no plan}.
static func plan_routes(routes: Array, options: Dictionary = {}) -> Dictionary:
	var weight := clampf(float(options.get("time_weight", 0.5)), 0.03, 0.97)
	var reference_dv: float = DV_REFERENCE_KMS * (routes[0].size() - 1)
	var reference_days: float = _reference_days(routes[0])
	var plans: Array = []
	var failed: Array = []
	for route in routes:
		var made := plan(route, options)
		if made["ok"]:
			var used_weight: float = made.get("time_weight", weight)
			made["common_score"] = (1.0 - used_weight) * float(made["total_dv_kms"]) / reference_dv \
				+ used_weight * float(made["total_days"]) / reference_days
			plans.append(made)
		else:
			var names: Array[String] = []
			for body in route:
				names.append(Astro.body_name(body))
			failed.append(" -> ".join(names))
	plans.sort_custom(func(a, b): return a["common_score"] < b["common_score"])
	if plans.is_empty():
		return {"ok": false, "error": "No flight was found for that request.", "failed": failed}
	return {"ok": true, "best": plans[0], "all": plans, "failed": failed}


static func _reference_days(route: Array) -> float:
	var total := 0.0
	for leg in route.size() - 1:
		total += _hohmann_days(route[leg], route[leg + 1])
	return maxf(total, 30.0)


func _run(route: Array, options: Dictionary) -> Dictionary:
	if route.size() < 2:
		return {"ok": false, "error": "A flight needs at least two bodies."}
	_route = route
	_legs = route.size() - 1
	_time_weight = float(options.get("time_weight", 0.5))
	_capture = String(options.get("arrival", "capture")) != "flyby"
	_start = float(options.get("start_days", 0.0))
	var max_days := float(options.get("max_days", 0.0))

	# Rough size of the problem: the textbook transfer time of each leg, and the wait for a launch window on the first.
	var hohmann: Array[float] = []
	var total_hohmann := 0.0
	for leg in _legs:
		var h := _hohmann_days(route[leg], route[leg + 1])
		hohmann.append(h)
		total_hohmann += h
	var window := _synodic_days(route[0], route[1])
	var horizon := window + 1.8 * total_hohmann
	if max_days > 0.0:
		horizon = minf(horizon, window + max_days)
	var wanted_grid := int(options.get("grid", DEFAULT_GRID))
	_step = maxf(horizon / float(wanted_grid), 1.0)
	_grid = int(ceil(horizon / _step))
	_width = _grid + 1
	_min_steps.clear()
	_max_steps.clear()
	for leg in _legs:
		_min_steps.append(maxi(int(floor(0.3 * hohmann[leg] / _step)), 1))
		var most := 2.4 * hohmann[leg]
		if max_days > 0.0:
			most = minf(most, max_days)
		_max_steps.append(maxi(int(ceil(most / _step)), _min_steps[leg]))
	_dv_reference = DV_REFERENCE_KMS * _legs
	_time_reference = maxf(total_hohmann, 30.0)

	for body in route:
		if not _states.has(body):
			var column := []
			for k in _width:
				column.append(Ephemeris.state(body, _start + k * _step))
			_states[body] = column
	_leg_cache.clear()
	for _leg in _legs:
		_leg_cache.append({})

	var found := _grid_search()
	if found.is_empty():
		return {"ok": false, "error": "No transfer was found in the time allowed."}
	var times: Array[float] = []
	for k in found:
		times.append(_start + k * _step)
	times = _refine(times, max_days)
	var best := _evaluate(times, true)
	if not best["ok"]:
		return {"ok": false, "error": "The best plan could not be checked."}
	best["lambert_solves"] = lambert_solves
	return best


# ---- Sizes ---------------------------------------------------------------------------------------------------------------

static func _hohmann_days(from_body: int, to_body: int) -> float:
	if from_body == to_body:
		return Astro.period(from_body)
	var a := (Astro.semi_major_axis(from_body) + Astro.semi_major_axis(to_body)) / 2.0
	return PI * sqrt(a * a * a / Astro.MU_SUN)


static func _synodic_days(from_body: int, to_body: int) -> float:
	if from_body == to_body:
		return Astro.period(from_body)
	return 1.0 / absf(1.0 / Astro.period(from_body) - 1.0 / Astro.period(to_body))


# ---- Cost pieces ---------------------------------------------------------------------------------------------------------

## Speed change to leave (or enter) a low orbit of a planet at a v-infinity (AU/day), in km/s.
func _orbit_burn_kms(body: int, v_inf: float) -> float:
	var mu := Astro.mu(body)
	var rp := Astro.park_radius_au(body)
	return (sqrt(v_inf * v_inf + 2.0 * mu / rp) - sqrt(mu / rp)) * Astro.KMS_PER_AU_DAY


func _flyby_kms(body: int, v_in: Vector3, v_out: Vector3, planet_velocity: Vector3) -> float:
	var result := Flyby.delta_v(v_in - planet_velocity, v_out - planet_velocity, Astro.mu(body), Astro.park_radius_au(body))
	return float(result["dv"]) * Astro.KMS_PER_AU_DAY


func _cost(dv_kms: float, days: float) -> float:
	return (1.0 - _time_weight) * dv_kms / _dv_reference + _time_weight * days / _time_reference


# ---- Grid search ---------------------------------------------------------------------------------------------------------

## The transfer for leg `leg` (0-based) between grid steps `a` and `b`: {"ok", "v1", "v2"}.
func _leg_between(leg: int, a: int, b: int) -> Dictionary:
	var key := a * _width + b
	var cache := _leg_cache[leg]
	if cache.has(key):
		return cache[key]
	var from_state: Array = _states[_route[leg]][a]
	var to_state: Array = _states[_route[leg + 1]][b]
	var made := _transfer(from_state[0], to_state[0], (b - a) * _step)
	cache[key] = made
	return made


func _transfer(r1: Vector3, r2: Vector3, tof: float) -> Dictionary:
	lambert_solves += 1
	var made := Lambert.solve(r1, r2, tof, Astro.MU_SUN)
	if not made["ok"]:
		return made
	if Lambert.periapsis(r1, made["v1"], Astro.MU_SUN) < MIN_PERIHELION_AU:
		return {"ok": false}
	return made


func _grid_search() -> Array:
	var stages: Array[Dictionary] = []
	# Stage 0: leg 0 from step a to step b. Cost: leaving the first planet, and the time of the leg.
	var first := {}
	for a in _width:
		for b in range(a + _min_steps[0], mini(a + _max_steps[0], _grid) + 1):
			var leg := _leg_between(0, a, b)
			if not leg["ok"]:
				continue
			var departure: Array = _states[_route[0]][a]
			var burn := _orbit_burn_kms(_route[0], (leg["v1"] - departure[1]).length())
			first[a * _width + b] = [_cost(burn, (b - a) * _step), -1]
	stages.append(first)
	for leg_index in range(1, _legs):
		var before: Dictionary = stages[leg_index - 1]
		var arrivals := {}
		for key in before:
			var b: int = key % _width
			if not arrivals.has(b):
				arrivals[b] = []
			arrivals[b].append(key / _width)
		var current := {}
		for b in arrivals:
			var arriving: Array = arrivals[b]
			for c in range(b + _min_steps[leg_index], mini(b + _max_steps[leg_index], _grid) + 1):
				var out_leg := _leg_between(leg_index, b, c)
				if not out_leg["ok"]:
					continue
				var planet_velocity: Vector3 = _states[_route[leg_index]][b][1]
				var best_cost := INF
				var best_from := -1
				for a in arriving:
					var in_leg := _leg_between(leg_index - 1, a, b)
					var swing := _flyby_kms(_route[leg_index], in_leg["v2"], out_leg["v1"], planet_velocity)
					var total: float = before[a * _width + b][0] + _cost(swing, (c - b) * _step)
					if total < best_cost:
						best_cost = total
						best_from = a
				current[b * _width + c] = [best_cost, best_from]
		stages.append(current)
	# Finish: arriving at the last planet.
	var last: Dictionary = stages[_legs - 1]
	var best_total := INF
	var best_key := -1
	for key in last:
		var arrival_step: int = key % _width
		var leg := _leg_between(_legs - 1, key / _width, arrival_step)
		var burn := 0.0
		if _capture:
			var arrival_velocity: Vector3 = _states[_route[_legs]][arrival_step][1]
			burn = _orbit_burn_kms(_route[_legs], (leg["v2"] - arrival_velocity).length())
		var total: float = last[key][0] + _cost(burn, 0.0)
		if total < best_total:
			best_total = total
			best_key = key
	if best_key < 0:
		return []
	# Walk back for the step of every stop.
	var steps: Array[int] = []
	var later: int = best_key % _width
	var earlier: int = best_key / _width
	steps.append(later)
	steps.append(earlier)
	var key := best_key
	for leg_index in range(_legs - 1, 0, -1):
		var from_step: int = stages[leg_index][key][1]
		steps.append(from_step)
		key = from_step * _width + earlier
		earlier = from_step
	steps.reverse()
	return steps


# ---- Refinement and evaluation --------------------------------------------------------------------------------------------

## Moves each time by smaller and smaller steps while that lowers the cost.
func _refine(times: Array[float], max_days: float) -> Array[float]:
	var current := times.duplicate()
	var best := _evaluate(current, false)
	if not best["ok"]:
		return times
	var move := _step / 2.0
	while move > 0.25:
		var improved := true
		var rounds := 0
		while improved and rounds < 20:
			improved = false
			rounds += 1
			for index in current.size():
				for direction in [-1.0, 1.0]:
					var trial := current.duplicate()
					trial[index] += direction * move
					if max_days > 0.0 and trial[trial.size() - 1] - trial[0] > max_days:
						continue
					var tried := _evaluate(trial, false)
					if tried["ok"] and tried["score"] < best["score"] - 1e-12:
						best = tried
						current = trial
						improved = true
		move /= 2.0
	return current


## The full plan for exact times (days since J2000 at each body of the route). With `detail` the path samples are made too.
func _evaluate(times: Array[float], detail: bool) -> Dictionary:
	var fail := {"ok": false}
	var count := times.size()
	for index in range(1, count):
		if times[index] <= times[index - 1] + 1.0:
			return fail
	var states: Array = []
	for index in count:
		states.append(Ephemeris.state(_route[index], times[index]))
	var transfers: Array = []
	for leg in _legs:
		var made := _transfer(states[leg][0], states[leg + 1][0], times[leg + 1] - times[leg])
		if not made["ok"]:
			return fail
		transfers.append(made)

	var events: Array = []
	var total_dv := 0.0
	var departure_inf: float = (transfers[0]["v1"] - states[0][1]).length()
	var burn := _orbit_burn_kms(_route[0], departure_inf)
	total_dv += burn
	events.append({"body": Astro.body_name(_route[0]), "kind": "departure", "time": times[0], "dv_kms": burn,
		"v_inf_kms": departure_inf * Astro.KMS_PER_AU_DAY})
	for stop in range(1, _legs):
		var v_in: Vector3 = transfers[stop - 1]["v2"] - states[stop][1]
		var v_out: Vector3 = transfers[stop]["v1"] - states[stop][1]
		var swing := Flyby.delta_v(v_in, v_out, Astro.mu(_route[stop]), Astro.park_radius_au(_route[stop]))
		var swing_kms := float(swing["dv"]) * Astro.KMS_PER_AU_DAY
		total_dv += swing_kms
		events.append({"body": Astro.body_name(_route[stop]), "kind": "flyby", "time": times[stop], "dv_kms": swing_kms,
			"v_inf_kms": v_in.length() * Astro.KMS_PER_AU_DAY, "free": swing["free"],
			"closest_km": float(swing["rp"]) * Astro.AU_KM})
	var arrival_inf: float = (transfers[_legs - 1]["v2"] - states[_legs][1]).length()
	var arrival_burn := _orbit_burn_kms(_route[_legs], arrival_inf) if _capture else 0.0
	total_dv += arrival_burn
	events.append({"body": Astro.body_name(_route[_legs]), "kind": "arrival", "time": times[_legs], "dv_kms": arrival_burn,
		"v_inf_kms": arrival_inf * Astro.KMS_PER_AU_DAY})

	var days := times[count - 1] - times[0]
	var names: Array[String] = []
	for body in _route:
		names.append(Astro.body_name(body))
	var result := {"ok": true, "route": names, "total_dv_kms": total_dv, "total_days": days, "score": _cost(total_dv, days),
		"times": times.duplicate(), "events": events, "time_weight": _time_weight, "capture": _capture}
	if detail:
		var legs: Array = []
		for leg in _legs:
			var samples_t := PackedFloat64Array()
			var samples_p := PackedVector3Array()
			var span := times[leg + 1] - times[leg]
			for sample in SAMPLES_PER_LEG + 1:
				var along := span * sample / float(SAMPLES_PER_LEG)
				var moved := Lambert.propagate(states[leg][0], transfers[leg]["v1"], along, Astro.MU_SUN)
				samples_t.append(times[leg] + along)
				samples_p.append(moved[0])
			legs.append({"from": names[leg], "to": names[leg + 1], "depart": times[leg], "arrive": times[leg + 1],
				"samples_t": samples_t, "samples_p": samples_p})
		result["legs"] = legs
	return result
