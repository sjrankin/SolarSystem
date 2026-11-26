extends SceneTree
## Headless checks of the trajectory solver: godot --headless --path . --script res://test/check_flight.gd

var failures := 0


func _init() -> void:
	_check_lambert_round_trip()
	_check_flyby()
	_check_earth_mars()
	_check_time_weight()
	_check_gravity_assist_route()
	_check_request_parsing()
	print("flight checks: ", "OK" if failures == 0 else "%d FAILED" % failures)
	quit(failures)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)


## An orbit is propagated, and Lambert's problem between the two ends must give back the starting velocity.
func _check_lambert_round_trip() -> void:
	var r0 := Vector3(1.0, 0.1, 0.02)
	var v0 := Vector3(-0.003, 0.0165, 0.0004)
	for days in [40.0, 120.0, 250.0, 330.0]:
		var end := Lambert.propagate(r0, v0, days, Astro.MU_SUN)
		var back := Lambert.solve(r0, end[0], days, Astro.MU_SUN)
		_expect(back["ok"], "Lambert solved for %d days" % int(days))
		if back["ok"]:
			_expect(back["v1"].distance_to(v0) < 1e-7, "Lambert start velocity for %d days (off by %s)" % [int(days), back["v1"].distance_to(v0)])
			_expect(back["v2"].distance_to(end[1]) < 1e-7, "Lambert end velocity for %d days" % int(days))
	# A circular orbit comes back to the same place after one period.
	var r := Vector3(1.0, 0.0, 0.0)
	var v := Vector3(0.0, sqrt(Astro.MU_SUN), 0.0)
	var period := TAU / sqrt(Astro.MU_SUN)
	var around := Lambert.propagate(r, v, period, Astro.MU_SUN)
	_expect(around[0].distance_to(r) < 1e-6, "circular orbit closes after one period (off by %s)" % around[0].distance_to(r))


func _check_flyby() -> void:
	var mu := Astro.mu(4)
	var rmin := Astro.park_radius_au(4)
	var vin := Vector3(0.004, 0.0, 0.0)
	# The same speed, turned a little: gravity alone does it.
	var turned := Flyby.delta_v(vin, vin.rotated(Vector3.UP, 0.3), mu, rmin)
	_expect(turned["free"] and float(turned["dv"]) < 1e-9, "equal-speed turn within reach is free")
	# A turn bigger than Jupiter can give at its closest allowed pass needs a burn.
	var too_much := Flyby.delta_v(vin, vin.rotated(Vector3.UP, 3.0), Astro.mu(1), Astro.park_radius_au(1))
	_expect(not too_much["free"] and float(too_much["dv"]) > 0.0, "turn beyond Venus's reach costs speed")
	# Leaving faster than arriving costs the difference in speed at closest approach.
	var faster := Flyby.delta_v(vin, vin.rotated(Vector3.UP, 0.3) * 1.2, mu, rmin)
	_expect(float(faster["dv"]) > 0.0, "leaving faster costs a burn")


func _plan(route_names: Array, options: Dictionary) -> Dictionary:
	var route := []
	for planet_name in route_names:
		route.append(Astro.find_body(planet_name))
	var started := Time.get_ticks_msec()
	var result := FlightPlanner.plan(route, options)
	print("  planned %s in %d ms (%d Lambert solves)" % [route_names, Time.get_ticks_msec() - started, result.get("lambert_solves", 0)])
	return result


func _start_2026() -> float:
	return OrbitMath.days_since_j2000(Time.get_unix_time_from_datetime_string("2026-11-25T00:00:00"))


func _check_earth_mars() -> void:
	var result := _plan(["Earth", "Mars"], {"time_weight": 0.2, "start_days": _start_2026()})
	_expect(result["ok"], "Earth to Mars found")
	if not result["ok"]:
		return
	print("  Earth->Mars: %.1f km/s, %.0f days, depart %s" % [result["total_dv_kms"], result["total_days"], Astro.date_text(result["times"][0])])
	_expect(result["total_days"] > 150.0 and result["total_days"] < 400.0, "Earth-Mars takes 150-400 days")
	_expect(result["total_dv_kms"] > 4.0 and result["total_dv_kms"] < 9.0, "Earth-Mars needs 4-9 km/s from and into low orbit")
	# The first event is the departure burn out of low Earth orbit: v-infinity about 3 km/s makes a 3.5-4.5 km/s burn.
	var burn: float = result["events"][0]["dv_kms"]
	_expect(burn > 3.0 and burn < 4.8, "Earth departure burn is 3-4.8 km/s (got %.2f)" % burn)


func _check_time_weight() -> void:
	var start := _start_2026()
	var slow := _plan(["Earth", "Mars"], {"time_weight": 0.1, "start_days": start})
	var fast := _plan(["Earth", "Mars"], {"time_weight": 0.9, "start_days": start})
	_expect(slow["ok"] and fast["ok"], "both weights find a plan")
	if slow["ok"] and fast["ok"]:
		print("  energy-first: %.1f km/s %.0f d; time-first: %.1f km/s %.0f d" % [slow["total_dv_kms"], slow["total_days"], fast["total_dv_kms"], fast["total_days"]])
		_expect(fast["total_days"] <= slow["total_days"] + 1.0, "favoring time is not slower")
		_expect(fast["total_dv_kms"] >= slow["total_dv_kms"] - 0.05, "favoring energy does not cost more speed")
	var jupiter := _plan(["Earth", "Jupiter"], {"time_weight": 0.2, "start_days": start, "arrival": "flyby"})
	_expect(jupiter["ok"], "Earth to Jupiter found")
	if jupiter["ok"]:
		print("  Earth->Jupiter flyby: %.1f km/s, %.0f days" % [jupiter["total_dv_kms"], jupiter["total_days"]])
		_expect(jupiter["total_days"] > 500.0 and jupiter["total_days"] < 1800.0, "Earth-Jupiter takes 500-1800 days")


func _check_gravity_assist_route() -> void:
	var result := _plan(["Earth", "Mars", "Jupiter"], {"time_weight": 0.3, "start_days": _start_2026(), "arrival": "flyby"})
	_expect(result["ok"], "Earth-Mars-Jupiter found")
	if result["ok"]:
		for event in result["events"]:
			print("  %s %s %s dv %.2f km/s, v-inf %.1f km/s" % [event["kind"], event["body"], Astro.date_text(event["time"]), event["dv_kms"], event["v_inf_kms"]])
		_expect(result["events"].size() == 3, "three events")
		_expect(result["legs"].size() == 2 and result["legs"][0]["samples_p"].size() > 10, "path samples exist")


func _names(route: Array) -> Array:
	var names := []
	for body in route:
		names.append(Astro.body_name(body))
	return names


func _check_request_parsing() -> void:
	var plain := FlightRequest.fallback_parse("fly from Pluto to Mars to Saturn, favor energy over time")
	_expect(plain["ok"] and _names(plain["route"]) == ["Pluto", "Mars", "Saturn"], "plain parser finds the route in order")
	_expect(plain["time_weight"] == 0.15, "plain parser reads 'favor energy over time'")
	var quick := FlightRequest.fallback_parse("Get me from Earth to Jupiter as fast as possible")
	_expect(quick["ok"] and quick["time_weight"] == 0.85, "plain parser reads 'fast'")
	_expect(not FlightRequest.fallback_parse("go somewhere nice")["ok"], "no planets is an error")
	# What a language model answers is checked: unknown bodies are rejected; alternatives must keep the ends and stops.
	var bad := FlightRequest.validate({"route": ["Earth", "Krypton"], "alternatives": []})
	_expect(not bad["ok"], "an unknown body is rejected")
	var good := FlightRequest.validate({"route": ["earth", "Saturn"], "time_weight": 7, "arrival": "orbit",
		"alternatives": [["Earth", "Venus", "Saturn"], ["Mars", "Saturn"], ["Earth", "Saturn"], ["Earth", "Pluto"], ["Earth", "Jupiter", "Saturn"]],
		"max_duration_years": 12})
	_expect(good["ok"] and good["time_weight"] == 1.0, "time weight is clamped")
	_expect(good["alternatives"].size() == 2, "only alternatives with the same ends that differ are kept (got %d)" % good["alternatives"].size())
	_expect(good["arrival"] == "capture" and absf(good["max_days"] - 12.0 * 365.25) < 1e-6, "arrival and limits are read")
	var kept := FlightRequest.validate({"route": ["Earth", "Mars", "Saturn"], "alternatives": [["Earth", "Jupiter", "Saturn"], ["Earth", "Mars", "Jupiter", "Saturn"]]})
	_expect(kept["alternatives"].size() == 1, "an alternative must keep the named stops")
