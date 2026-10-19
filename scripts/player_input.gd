class_name PlayerInput
extends Node
## Reads keyboard / gamepad input and writes the kart's in_* fields each tick,
## so the player drives exactly the same physics as the AI.
## Accepts both the original `accelerate` action and the spec aliases
## `throttle` / `move_forward` (and `brake` / `move_backward`).

var kart: Kart

var _prev_accel := 0.0
var _prev_item := false


func _ready() -> void:
	if kart == null:
		kart = get_parent() as Kart


static func accel_strength() -> float:
	return maxf(Input.get_action_strength("accelerate"),
			maxf(Input.get_action_strength("throttle"), Input.get_action_strength("move_forward")))


static func brake_strength() -> float:
	return maxf(Input.get_action_strength("brake"), Input.get_action_strength("move_backward"))


func compute(_delta: float) -> void:
	if kart == null:
		return
	var accel := accel_strength()
	var brake := brake_strength()
	kart.in_throttle = accel - brake
	kart.in_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	kart.in_drift = Input.is_action_pressed("drift")
	# edge detection on the strength itself also catches Input.action_press() from tests
	kart.in_tap = accel > 0.5 and _prev_accel <= 0.5
	_prev_accel = accel
	var item := Input.is_action_pressed("use_item")
	kart.in_item = item and not _prev_item
	_prev_item = item
	kart.look_back = Input.is_action_pressed("look_back")
	if Input.is_action_just_pressed("respawn"):
		kart.respawn_on_track()
