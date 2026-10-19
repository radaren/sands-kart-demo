class_name PlayerInput
extends Node
## Reads keyboard / gamepad input and writes the kart's in_* fields each tick,
## so the player drives exactly the same physics as the AI.

var kart: Kart

var _tap_held := false


func _ready() -> void:
	if kart == null:
		kart = get_parent() as Kart


func compute(_delta: float) -> void:
	if kart == null:
		return
	var accel := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	kart.in_throttle = accel - brake
	kart.in_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	kart.in_drift = Input.is_action_pressed("drift")
	kart.in_tap = Input.is_action_just_pressed("accelerate")
	kart.in_item = Input.is_action_just_pressed("use_item")
	kart.look_back = Input.is_action_pressed("look_back")
	if Input.is_action_just_pressed("respawn"):
		kart.respawn_on_track()
