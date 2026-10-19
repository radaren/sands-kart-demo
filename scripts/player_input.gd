class_name PlayerInput
extends Node
## Reads InputMap actions and writes the 4(+2) unified inputs into the kart.

func compute_input(kart, _delta: float) -> void:
	kart.in_steer = clampf(Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"), -1.0, 1.0)
	kart.in_throttle = maxf(Input.get_action_strength("throttle"), Input.get_action_strength("move_forward"))
	kart.in_brake = maxf(Input.get_action_strength("brake"), Input.get_action_strength("move_backward"))
	kart.in_drift = Input.is_action_pressed("drift")
	kart.in_use_item = Input.is_action_pressed("use_item")
	kart.in_respawn = Input.is_action_pressed("respawn")
