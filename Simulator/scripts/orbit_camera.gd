class_name OrbitCamera
extends Camera3D
## Camera that orbits a target point.
##
## - Drag with the left mouse button: rotate.
## - Drag with the right/middle button, or Option/Shift + left drag: move (pan).
## - Mouse wheel, trackpad scroll or pinch: zoom.
## - Double-click: smoothly restore the original view.
##
## It can also follow a node (the spacecraft) as a chase camera: it sits low and close behind it, near the plane of the solar
## system, looking the way it is heading (the node's -Z axis), and turns smoothly as its path curves. Dragging swings the view around
## it, zooming and moving still work, and double-click comes back to the chase view.

const RESET_DURATION := 0.7
const ROTATE_SPEED := 0.006
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 6000.0
const MAX_PITCH := deg_to_rad(89.0)

const INITIAL_TARGET := Vector3.ZERO
const INITIAL_YAW := 0.0
const INITIAL_PITCH := deg_to_rad(35.0)
const INITIAL_DISTANCE := 820.0
## The chase view: this far behind the spacecraft, looking down at it from just this far above the plane of its travel.
const FOLLOW_DISTANCE := 110.0
const FOLLOW_PITCH := deg_to_rad(10.0)
## How quickly the chase view turns to keep up with the spacecraft's heading (per second); higher is stiffer.
const FOLLOW_TURN_RATE := 3.0

var target := INITIAL_TARGET
var yaw := INITIAL_YAW
var pitch := INITIAL_PITCH
var distance := INITIAL_DISTANCE
## The node being followed, or null.
var follow: Node3D = null

## Where the view is moved from the followed node by panning while following.
var _follow_offset := Vector3.ZERO
## How far the user has swung the view around the followed node, from straight behind it.
var _follow_yaw_offset := 0.0
var _resetting := false
var _reset_time := 0.0
var _from_target := Vector3.ZERO
var _from_yaw := 0.0
var _from_pitch := 0.0
var _from_distance := 0.0
var _to_pitch := INITIAL_PITCH
var _to_distance := INITIAL_DISTANCE


func _ready() -> void:
	fov = 45.0
	near = 0.5
	far = 30000.0
	# Runs after the simulator and the flight have moved things this frame, so a followed node never lags a frame behind.
	process_priority = 100
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
	var following := is_following()
	if not _resetting and not following:
		return
	# What the view is heading for: behind the followed node, or the original view of the whole system.
	var anchor := INITIAL_TARGET
	var goal_yaw := INITIAL_YAW
	if following:
		anchor = follow.global_position + _follow_offset
		goal_yaw = heading_yaw(-follow.global_basis.z) + _follow_yaw_offset
	if _resetting:
		_reset_time += delta
		var t := clampf(_reset_time / RESET_DURATION, 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		target = _from_target.lerp(anchor, eased)
		yaw = lerp_angle(_from_yaw, goal_yaw, eased)
		pitch = lerpf(_from_pitch, _to_pitch, eased)
		distance = lerpf(_from_distance, _to_distance, eased)
		if t >= 1.0:
			_resetting = false
	else:
		target = anchor
		# Eased, so a sharp turn (a fly-by) swings the view round instead of snapping it.
		yaw = lerp_angle(yaw, goal_yaw, 1.0 - exp(-FOLLOW_TURN_RATE * delta))
	_apply()


## The yaw that puts the camera behind something moving along `heading`, looking the same way.
static func heading_yaw(heading: Vector3) -> float:
	if Vector2(heading.x, heading.z).length() < 1e-9:
		return 0.0
	return atan2(-heading.x, -heading.z)


## True while a visible node is being followed.
func is_following() -> bool:
	return follow != null and is_instance_valid(follow) and follow.is_visible_in_tree()


## Follows `node` with the chase view, gliding there from wherever the camera is.
func start_following(node: Node3D) -> void:
	follow = node
	_follow_offset = Vector3.ZERO
	_follow_yaw_offset = 0.0
	if is_following():
		_glide(FOLLOW_DISTANCE, FOLLOW_PITCH)


## Stops following; the view stays where it is.
func stop_following() -> void:
	follow = null
	_follow_offset = Vector3.ZERO
	_follow_yaw_offset = 0.0
	# A glide towards the spacecraft would otherwise carry on towards the Sun.
	_resetting = false


## Smoothly returns to the original view, or, while following, to the chase view.
func reset_view() -> void:
	_follow_offset = Vector3.ZERO
	_follow_yaw_offset = 0.0
	if is_following():
		_glide(FOLLOW_DISTANCE, FOLLOW_PITCH)
	else:
		_glide(INITIAL_DISTANCE, INITIAL_PITCH)


func _glide(to_distance: float, to_pitch: float) -> void:
	_from_target = target
	_from_yaw = wrapf(yaw, -PI, PI)
	yaw = _from_yaw
	_from_pitch = pitch
	_from_distance = distance
	_to_pitch = to_pitch
	_to_distance = to_distance
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
		var turn := -event.relative.x * ROTATE_SPEED
		yaw += turn
		# While following, the swing is kept relative to the heading, so the view keeps turning with the spacecraft.
		if is_following():
			_follow_yaw_offset += turn
		pitch = clampf(pitch + event.relative.y * ROTATE_SPEED, -MAX_PITCH, MAX_PITCH)
		_apply()
func _pan(relative: Vector2) -> void:
	# Scale so the scene follows the cursor regardless of zoom level.
	var units_per_pixel := 2.0 * distance * tan(deg_to_rad(fov) * 0.5) / get_viewport().get_visible_rect().size.y
	var move := (-global_basis.x * relative.x + global_basis.y * relative.y) * units_per_pixel
	target += move
	# While following, moving shifts the view from the followed point and keeps following.
	if is_following():
		_follow_offset += move
	_apply()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func _cancel_reset() -> void:
	_resetting = false


func _apply() -> void:
	var orientation := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
	transform = Transform3D(orientation, target + orientation * Vector3(0.0, 0.0, distance))
