class_name OrbitCamera
extends Camera3D
## Camera that orbits a target point.
##
## - Drag with the left mouse button: rotate.
## - Drag with the right/middle button, or Option/Shift + left drag: move (pan).
## - Mouse wheel, trackpad scroll or pinch: zoom.
## - Double-click: smoothly restore the original view.

const RESET_DURATION := 0.7
const ROTATE_SPEED := 0.006
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 6000.0
const MAX_PITCH := deg_to_rad(89.0)

const INITIAL_TARGET := Vector3.ZERO
const INITIAL_YAW := 0.0
const INITIAL_PITCH := deg_to_rad(35.0)
const INITIAL_DISTANCE := 820.0

var target := INITIAL_TARGET
var yaw := INITIAL_YAW
var pitch := INITIAL_PITCH
var distance := INITIAL_DISTANCE

var _resetting := false
var _reset_time := 0.0
var _from_target := Vector3.ZERO
var _from_yaw := 0.0
var _from_pitch := 0.0
var _from_distance := 0.0


func _ready() -> void:
	fov = 45.0
	near = 0.5
	far = 30000.0
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event)
	elif event is InputEventMouseMotion:
		_handle_motion(event)
	elif event is InputEventPanGesture:
		_cancel_reset()
		_zoom(1.0 + event.delta.y * 0.05)
	elif event is InputEventMagnifyGesture:
		_cancel_reset()
		_zoom(1.0 / maxf(event.factor, 0.01))


func _process(delta: float) -> void:
	if not _resetting:
		return
	_reset_time += delta
	var t := clampf(_reset_time / RESET_DURATION, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	target = _from_target.lerp(INITIAL_TARGET, eased)
	yaw = lerp_angle(_from_yaw, INITIAL_YAW, eased)
	pitch = lerpf(_from_pitch, INITIAL_PITCH, eased)
	distance = lerpf(_from_distance, INITIAL_DISTANCE, eased)
	if t >= 1.0:
		_resetting = false
	_apply()


## Smoothly returns to the original view.
func reset_view() -> void:
	_from_target = target
	_from_yaw = wrapf(yaw, -PI, PI)
	yaw = _from_yaw
	_from_pitch = pitch
	_from_distance = distance
	_reset_time = 0.0
	_resetting = true


func _handle_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.double_click:
				reset_view()
			else:
				_cancel_reset()
		MOUSE_BUTTON_WHEEL_UP:
			_cancel_reset()
			_zoom(0.9)
		MOUSE_BUTTON_WHEEL_DOWN:
			_cancel_reset()
			_zoom(1.1)


func _handle_motion(event: InputEventMouseMotion) -> void:
	var mask := event.button_mask
	var panning := (mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0
	if (mask & MOUSE_BUTTON_MASK_LEFT) != 0 and (event.alt_pressed or event.shift_pressed):
		panning = true
	if panning:
		_cancel_reset()
		_pan(event.relative)
	elif (mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_cancel_reset()
		yaw -= event.relative.x * ROTATE_SPEED
		pitch = clampf(pitch + event.relative.y * ROTATE_SPEED, -MAX_PITCH, MAX_PITCH)
		_apply()


func _pan(relative: Vector2) -> void:
	# Scale so the scene follows the cursor regardless of zoom level.
	var units_per_pixel := 2.0 * distance * tan(deg_to_rad(fov) * 0.5) / get_viewport().get_visible_rect().size.y
	target += (-global_basis.x * relative.x + global_basis.y * relative.y) * units_per_pixel
	_apply()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func _cancel_reset() -> void:
	_resetting = false


func _apply() -> void:
	var orientation := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
	transform = Transform3D(orientation, target + orientation * Vector3(0.0, 0.0, distance))
