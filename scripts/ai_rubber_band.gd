class_name AIRubberBand
extends Node
## Elastic catch-up. Every 0.5 s compares race progress with the player:
##   AI behind (delta > 0): rubber -> 1.0 + 0.15 * min(delta / 200 m, 1)
##   AI ahead  (delta < 0): rubber -> 1.0 - 0.10 * min(-delta / 200 m, 1)
## Enabled 10 s after GO, eased (never snaps). kart.speed_scale = rubber * base_speed_bias
## (the rival's base_speed_bias is 1.03).

@export var max_boost := 0.15
@export var max_slow := 0.10
@export var range_m := 200.0
@export var enable_after := 10.0
@export var update_interval := 0.5
@export var ease_per_second := 0.08

var kart: Kart
var player: Kart
var race_manager
var target := 1.0
var last_delta := 0.0
var _timer := 0.0


func _physics_process(delta: float) -> void:
	if kart == null or player == null or race_manager == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		if not race_manager.is_racing() or race_manager.race_time < enable_after or player.finished or kart.finished:
			target = 1.0
		else:
			last_delta = player.progress - kart.progress
			if last_delta > 0.0:
				target = 1.0 + max_boost * minf(last_delta / range_m, 1.0)
			else:
				target = 1.0 - max_slow * minf(-last_delta / range_m, 1.0)
	kart.rubber = move_toward(kart.rubber, target, ease_per_second * delta)
	kart.speed_scale = kart.rubber * kart.base_speed_bias
