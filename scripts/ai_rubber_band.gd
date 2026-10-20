class_name AIRubberBand
extends Node
## A6: elastic catch-up towards a per-AI target gap to the player (not the
## player's position itself), with a dead zone, a smaller cap, and fading out
## over the last 15 % of the race.
##   gap   = kart.progress - player.progress       (+ = AI ahead)
##   error = gap - target_gap
##   |error| <= dead_zone            -> 1.0
##   error < 0 (too far back)        -> 1 + max_boost * ramp
##   error > 0 (too far ahead)       -> 1 - max_slow  * ramp
##   ramp = clamp((|error| - dead_zone) / range_m, 0, 1)
## Enabled 10 s after GO, eased. kart.speed_scale = rubber * base_speed_bias.

@export var max_boost := 0.08
@export var max_slow := 0.08
@export var dead_zone := 25.0
@export var range_m := 150.0
@export var enable_after := 10.0
@export var update_interval := 0.5
@export var ease_per_second := 0.08
@export var fade_from := 0.85       ## race fraction where the band starts fading out

var kart: Kart
var player: Kart
var race_manager
var target := 1.0
var target_gap := 0.0              ## set by the race manager (rival +20 m)
var last_delta := 0.0
var last_error := 0.0
var _timer := 0.0


func _physics_process(delta: float) -> void:
	if kart == null or player == null or race_manager == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval
		target = compute_target()
	kart.rubber = move_toward(kart.rubber, target, ease_per_second * delta)
	kart.speed_scale = kart.rubber * kart.base_speed_bias


func compute_target() -> float:
	if not race_manager.is_racing() or race_manager.race_time < enable_after or player.finished or kart.finished:
		return 1.0
	last_delta = player.progress - kart.progress
	last_error = (kart.progress - player.progress) - target_gap
	var ramp := clampf((absf(last_error) - dead_zone) / range_m, 0.0, 1.0)
	var t := 1.0
	if last_error < 0.0:
		t = 1.0 + max_boost * ramp
	else:
		t = 1.0 - max_slow * ramp
	var length: float = race_manager.track.length if race_manager.track else 0.0
	if length > 0.0:
		var frac := clampf(maxf(player.progress, kart.progress) / length, 0.0, 1.0)
		var fade := clampf((1.0 - frac) / (1.0 - fade_from), 0.0, 1.0)
		t = lerpf(1.0, t, fade)
	return t
