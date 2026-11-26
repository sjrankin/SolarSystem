class_name OllamaClient
extends Node
## Calls a local Ollama server (https://ollama.com). Needs to be in the scene tree. Calls are asynchronous: `await` them.
## Nothing here ever stops the simulator: every failure (no server, no model, a slow or garbled answer, a cancelled call) comes back
## as {"ok": false, "error": String} with a message meant for the user.

var url := FlightSettings.DEFAULT_URL
var model := FlightSettings.DEFAULT_MODEL
## Seconds to wait for an answer. A large local model can take a while to load the first time.
var timeout_seconds := 240.0
## Seconds to wait when only checking that the server is there. A server that is running answers at once.
var check_timeout_seconds := 3.0

## Longest the simulator waits, when it quits, for Ollama to unload the model.
const UNLOAD_TIMEOUT_MS := 2000

## The request in flight, so it can be cancelled.
var _active: HTTPRequest
var _cancelled := false
## The models this session asked something of, to unload when the simulator quits.
var _used_models: Array[String] = []


func _notification(what: int) -> void:
	# The window is closing (close button or Cmd+Q). Godot quits as soon as this returns, so the unload is done here and now.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		unload_now()


## Asks Ollama to unload every model this session used, so their memory is free at once instead of after Ollama's idle timeout.
## Blocks for at most UNLOAD_TIMEOUT_MS in all; does nothing if no model was used. Returns true if Ollama confirmed every one.
func unload_now() -> bool:
	if _used_models.is_empty():
		return false
	var deadline := Time.get_ticks_msec() + UNLOAD_TIMEOUT_MS
	var all_done := true
	for name in _used_models.duplicate():
		if _unload(name, deadline):
			_used_models.erase(name)
		else:
			all_done = false
	return all_done


func _unload(name: String, deadline: int) -> bool:
	var found := RegEx.create_from_string("^(https?)://([^/:]+)(?::(\\d+))?").search(url)
	if found == null:
		return false
	var secure := found.get_string(1) == "https"
	var port := int(found.get_string(3)) if found.get_string(3) != "" else (443 if secure else 80)
	var client := HTTPClient.new()
	if client.connect_to_host(found.get_string(2), port, TLSOptions.client() if secure else null) != OK:
		return false
	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		if Time.get_ticks_msec() > deadline:
			return false
		client.poll()
		OS.delay_msec(5)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return false
	# keep_alive 0 tells Ollama to unload the model now; it answers once it has.
	var body := JSON.stringify({"model": name, "keep_alive": 0})
	if client.request(HTTPClient.METHOD_POST, "/api/generate", ["Content-Type: application/json"], body) != OK:
		return false
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() > deadline:
			client.close()
			return false
		client.poll()
		OS.delay_msec(5)
	var unloaded := client.has_response() and client.get_response_code() == 200
	client.close()
	return unloaded


## Checks, quickly, that Ollama is running and has the model. Returns {"ok": true} or {"ok": false, "error": String}.
func check() -> Dictionary:
	var reply := await _send("/api/tags", HTTPClient.METHOD_GET, "", check_timeout_seconds)
	if not reply["ok"]:
		return reply
	var parsed: Variant = JSON.parse_string(String(reply["text"]))
	if not (parsed is Dictionary and parsed.get("models") is Array):
		return {"ok": false, "error": "Something answered at %s, but it does not look like Ollama." % url}
	var installed: Array[String] = []
	for entry in parsed["models"]:
		if entry is Dictionary:
			installed.append(String(entry.get("name", entry.get("model", ""))))
	if not has_model(installed, model):
		return {"ok": false, "error": "Ollama is running but the model %s is not installed (ollama pull %s)." % [model, model]}
	return {"ok": true}


## True if `wanted` is among the `installed` model names. A name without a tag means ":latest", as Ollama reads it.
static func has_model(installed: Array[String], wanted: String) -> bool:
	var full := wanted if wanted.contains(":") else wanted + ":latest"
	return full in installed or wanted in installed


## Asks the model a question and expects JSON that fits `schema` (Ollama's structured output). Returns {"ok": true, "data": Dictionary}
## or {"ok": false, "error": String}.
func chat_json(system_prompt: String, user_prompt: String, schema: Dictionary) -> Dictionary:
	var reply := await _chat(system_prompt, user_prompt, schema)
	if not reply["ok"]:
		return reply
	var parsed: Variant = JSON.parse_string(String(reply["text"]))
	if parsed is Dictionary:
		return {"ok": true, "data": parsed}
	return {"ok": false, "error": "The model did not answer with JSON."}


## Asks the model a question and returns {"ok": true, "text": String} or {"ok": false, "error": String}.
func chat_text(system_prompt: String, user_prompt: String) -> Dictionary:
	return await _chat(system_prompt, user_prompt, {})


## True while a call is waiting for an answer.
func is_busy() -> bool:
	return _active != null


## Gives up on the call in flight; it returns {"ok": false, "cancelled": true}.
func cancel() -> void:
	if _active == null:
		return
	_cancelled = true
	_active.cancel_request()
	# cancel_request does not send request_completed, so the waiting call is woken here.
	_active.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())


func _chat(system_prompt: String, user_prompt: String, schema: Dictionary) -> Dictionary:
	var body := {
		"model": model,
		"messages": [{"role": "system", "content": system_prompt}, {"role": "user", "content": user_prompt}],
		"stream": false,
		# A flight request has one right reading, so the model is kept from wandering.
		"options": {"temperature": 0.0},
	}
	if not schema.is_empty():
		body["format"] = schema
	# From here Ollama may load the model, so it is unloaded on quit even if this call fails or is skipped.
	if not model in _used_models:
		_used_models.append(model)
	var reply := await _send("/api/chat", HTTPClient.METHOD_POST, JSON.stringify(body), timeout_seconds)
	if not reply["ok"]:
		return reply
	var parsed: Variant = JSON.parse_string(String(reply["text"]))
	if parsed is Dictionary and parsed.get("message") is Dictionary:
		return {"ok": true, "text": String(parsed["message"].get("content", ""))}
	return {"ok": false, "error": "Ollama's answer was not understood."}


## Sends one request. Returns {"ok": true, "text": String} for a 200 answer, otherwise {"ok": false, "error": String} (with
## "cancelled": true if `cancel` stopped it).
func _send(path: String, method: int, body: String, timeout: float) -> Dictionary:
	if _active != null:
		return {"ok": false, "error": "The model is still busy with the last question."}
	var request := HTTPRequest.new()
	request.timeout = timeout
	add_child(request)
	_active = request
	_cancelled = false
	var headers := PackedStringArray(["Content-Type: application/json"]) if not body.is_empty() else PackedStringArray()
	var started := request.request(url.rstrip("/") + path, headers, method, body)
	var finished: Array = [started, 0, PackedStringArray(), PackedByteArray()]
	if started == OK:
		finished = await request.request_completed
	_active = null
	request.queue_free()
	if _cancelled:
		_cancelled = false
		return {"ok": false, "cancelled": true, "error": "Stopped waiting for the model."}
	if started != OK:
		return {"ok": false, "error": "The model address %s cannot be used. Check the URL in the flight settings." % url}
	var outcome: int = finished[0]
	var code: int = finished[1]
	var text := (finished[3] as PackedByteArray).get_string_from_utf8()
	if outcome != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": _transport_error(outcome, timeout)}
	if code != 200:
		var parsed: Variant = JSON.parse_string(text)
		var detail := ""
		if parsed is Dictionary and parsed.has("error"):
			detail = ": %s" % parsed["error"]
		if code == 404:
			return {"ok": false, "error": "Ollama does not have the model %s (ollama pull %s)%s." % [model, model, detail]}
		return {"ok": false, "error": "Ollama answered with an error (%d)%s." % [code, detail]}
	return {"ok": true, "text": text}


func _transport_error(outcome: int, timeout: float) -> String:
	match outcome:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Ollama is not running at %s (start the Ollama app, or run ollama serve)." % url
		HTTPRequest.RESULT_TIMEOUT:
			return "Ollama at %s did not answer within %d seconds." % [url, int(timeout)]
		_:
			return "The model at %s could not be reached (error %d)." % [url, outcome]
