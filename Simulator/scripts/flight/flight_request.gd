class_name FlightRequest
extends RefCounted
## What the user asked for, in a form the planner can use: building the prompts for the language model, checking what it answers
## (never trusted: every body name, number and route is validated), and a plain parser for when no model is available.

const MAX_ROUTE := 8
const MAX_ALTERNATIVES := 3
## The most bodies in an alternative route; longer ones take the planner too long and rarely win.
const MAX_ALTERNATIVE_ROUTE := 6


static func schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"route": {"type": "array", "items": {"type": "string"}},
			"time_weight": {"type": "number"},
			"arrival": {"type": "string", "enum": ["capture", "flyby"]},
			"max_duration_years": {"type": "number"},
			"max_delta_v_kms": {"type": "number"},
			"alternatives": {"type": "array", "items": {"type": "array", "items": {"type": "string"}}},
			"notes": {"type": "string"},
		},
		"required": ["route", "alternatives"],
	}


static func body_names() -> Array[String]:
	var names: Array[String] = []
	for index in Astro.body_count():
		names.append(Astro.body_name(index))
	return names


static func system_prompt() -> String:
	return "You turn a spaceflight request for a solar system simulator into JSON. Answer with JSON only.\n" \
		+ "Valid bodies: %s. No other body exists (not the Moon, not the Sun, not asteroids).\n" % ", ".join(body_names()) \
		+ "Fields:\n" \
		+ "- route: the bodies to visit in order, from the origin to the destination, including any stop the user names.\n" \
		+ "- time_weight: 0 to 1, only if the user states a preference. 1 = fastest possible whatever the fuel, 0 = least fuel/energy " \
		+ "whatever the time. 'favor time over energy' = 0.85, 'quick' = 0.8, balanced = 0.5, 'favor energy over time' = 0.15, " \
		+ "'save fuel' = 0.1. Leave it out if no preference is stated.\n" \
		+ "- arrival: 'capture' to enter orbit at the destination (the default), 'flyby' only if the user says fly past or flyby.\n" \
		+ "- max_duration_years and max_delta_v_kms: only if the user states a limit.\n" \
		+ "- alternatives: up to 3 other routes for the same request, each starting and ending at the same bodies and keeping every " \
		+ "stop the user named in order, but adding extra planets for gravity assists where that could save energy or time " \
		+ "(for example Venus or Earth on the way to the outer planets, Jupiter on the way to Saturn and beyond, Mars for Jupiter). " \
		+ "Use only bodies that are really useful. Use an empty list if no extra stop would help.\n" \
		+ "- notes: one short sentence about how you read the request.\n" \
		+ "Example: 'fly from Earth to Saturn, favor energy' -> {\"route\":[\"Earth\",\"Saturn\"],\"time_weight\":0.15," \
		+ "\"arrival\":\"capture\",\"alternatives\":[[\"Earth\",\"Venus\",\"Earth\",\"Jupiter\",\"Saturn\"],[\"Earth\",\"Jupiter\",\"Saturn\"]]," \
		+ "\"notes\":\"Low energy trip to Saturn.\"}"


static func explanation_system_prompt() -> String:
	return "You explain a computed spacecraft flight plan in plain language for the user of a solar system simulator. " \
		+ "Use only the facts and numbers given; do not add any. Each event has a 'what' field saying exactly what happens: " \
		+ "'engine burn leaving orbit', 'gravity assist' (a fly-by of a planet that bends the path without using fuel, " \
		+ "unless it lists a burn), or 'engine burn into orbit' (arriving and slowing down to orbit the planet) or 'fly-by without " \
		+ "stopping'. Only events of kind flyby are gravity assists; never call the departure or arrival one. " \
		+ "Write 3 to 5 sentences: the route and dates, why this route won among the others (compare their fuel and duration), " \
		+ "and the trade-off between time and energy (time_weight 0 means least fuel, 1 means fastest). No lists, no markdown."


## Checks a model's answer. Returns {"ok": true, "route": Array[int], "alternatives": Array (each Array[int]), "time_weight": float or
## -1.0 when none was stated, "arrival": String, "max_days": float, "max_dv_kms": float, "notes": String}, or {"ok": false, "error"}.
static func validate(data: Dictionary) -> Dictionary:
	var route_result := _to_route(data.get("route", []))
	if not route_result["ok"]:
		return route_result
	var route: Array = route_result["route"]
	var alternatives: Array = []
	var raw_alternatives: Variant = data.get("alternatives", [])
	if raw_alternatives is Array:
		for candidate in raw_alternatives:
			var converted := _to_route(candidate)
			# An alternative is only taken if it has the same ends, keeps the stops in order, and is not a repeat.
			if converted["ok"] and converted["route"].size() <= MAX_ALTERNATIVE_ROUTE and _keeps_stops(converted["route"], route) and converted["route"] != route \
					and not alternatives.has(converted["route"]):
				alternatives.append(converted["route"])
			if alternatives.size() >= MAX_ALTERNATIVES:
				break
	var weight := -1.0
	if data.has("time_weight") and (data["time_weight"] is float or data["time_weight"] is int):
		weight = clampf(float(data["time_weight"]), 0.0, 1.0)
	var max_days := 0.0
	if data.get("max_duration_years", null) is float or data.get("max_duration_years", null) is int:
		max_days = maxf(float(data["max_duration_years"]), 0.0) * 365.25
	var max_dv := 0.0
	if data.get("max_delta_v_kms", null) is float or data.get("max_delta_v_kms", null) is int:
		max_dv = maxf(float(data["max_delta_v_kms"]), 0.0)
	return {"ok": true, "route": route, "alternatives": alternatives, "time_weight": weight,
		"arrival": "flyby" if str(data.get("arrival", "capture")) == "flyby" else "capture",
		"max_days": max_days, "max_dv_kms": max_dv, "notes": str(data.get("notes", ""))}


static func _to_route(names: Variant) -> Dictionary:
	if not names is Array or names.size() < 2:
		return {"ok": false, "error": "A flight needs a start and a destination."}
	if names.size() > MAX_ROUTE:
		return {"ok": false, "error": "That route has too many stops (the most is %d)." % MAX_ROUTE}
	var route: Array[int] = []
	for entry in names:
		var index := Astro.find_body(str(entry))
		if index < 0:
			return {"ok": false, "error": "I do not know a body called '%s'. I know: %s." % [str(entry), ", ".join(body_names())]}
		route.append(index)
	return {"ok": true, "route": route}


## True if `candidate` has the same first and last body as `required`, and has all of `required` in order.
static func _keeps_stops(candidate: Array, required: Array) -> bool:
	if candidate.is_empty() or candidate[0] != required[0] or candidate[candidate.size() - 1] != required[required.size() - 1]:
		return false
	var next := 0
	for body in candidate:
		if next < required.size() and body == required[next]:
			next += 1
	return next == required.size()


## A plain reading of a request, used when no language model answers: the planets named, in the order named, and a time/energy
## preference from words such as "fast" and "fuel". Returns what `validate` returns.
static func fallback_parse(text: String) -> Dictionary:
	var lowered := text.to_lower()
	var found: Array = []
	for index in Astro.body_count():
		var from := 0
		var name := Astro.body_name(index).to_lower()
		while true:
			var at := lowered.find(name, from)
			if at < 0:
				break
			found.append([at, name])
			from = at + name.length()
	found.sort_custom(func(a, b): return a[0] < b[0])
	var names: Array = []
	for entry in found:
		if names.is_empty() or names[names.size() - 1] != entry[1]:
			names.append(entry[1])
	var data := {"route": names, "alternatives": []}
	var weight := -1.0
	var prefer := RegEx.create_from_string("favou?r(?:ing)?\\s+(\\w+)\\s+over\\s+(\\w+)").search(lowered)
	var time_words := ["time", "fast", "quick", "soon", "urgent", "shortest", "speed"]
	var energy_words := ["energy", "fuel", "efficient", "cheap", "delta-v", "delta v", "economical", "slow"]
	if prefer:
		weight = 0.85 if time_words.has(prefer.get_string(1)) else (0.15 if energy_words.has(prefer.get_string(1)) else -1.0)
	else:
		var time_hits := 0
		var energy_hits := 0
		for word in time_words:
			time_hits += 1 if lowered.contains(word) else 0
		for word in energy_words:
			energy_hits += 1 if lowered.contains(word) else 0
		if time_hits > energy_hits:
			weight = 0.85
		elif energy_hits > time_hits:
			weight = 0.15
	if weight >= 0.0:
		data["time_weight"] = weight
	if lowered.contains("flyby") or lowered.contains("fly by") or lowered.contains("fly past"):
		data["arrival"] = "flyby"
	return validate(data)


## Limits stated in the text itself, in case the model left them out: {"max_days": float, "max_dv_kms": float} (0 = none stated).
## Looks for "in/within/under/less than/no more than N years|months|days" and "N km/s".
static func limits_from_text(text: String) -> Dictionary:
	var lowered := text.to_lower()
	var limits := {"max_days": 0.0, "max_dv_kms": 0.0}
	var duration := RegEx.create_from_string("(?:in|within|under|less than|no more than|at most|fewer than)\\s+(?:about\\s+)?(\\d+(?:\\.\\d+)?)\\s*(year|yr|month|day)").search(lowered)
	if duration:
		var amount := float(duration.get_string(1))
		var unit := duration.get_string(2)
		limits["max_days"] = amount * (365.25 if unit.begins_with("y") else (30.44 if unit == "month" else 1.0))
	var speed := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)\\s*km\\s*/\\s*s").search(lowered)
	if speed:
		limits["max_dv_kms"] = float(speed.get_string(1))
	return limits
