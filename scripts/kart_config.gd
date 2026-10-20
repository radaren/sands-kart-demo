class_name KartConfig
extends Resource
## Shared tuning for every kart. Speeds are metres per second.

@export_group("Speed")
@export var max_speed := 30.0
@export var accel := 15.0
@export var boost_accel := 38.0
@export var brake := 34.0
@export var coast_drag := 5.0
@export var overspeed_drag := 8.0
@export var reverse_speed := 9.0
@export var stun_decel := 42.0
@export var hit_invuln_time := 1.2   ## invulnerable after a hit wears off (K12)
@export var wall_speed_loss := 0.55   ## legacy (unused since K9)
@export var wall_loss_base := 0.12     ## K9: loss = base + quad * impact^2
@export var wall_loss_quad := 0.43
@export var wall_push_base := 0.8      ## K9: push-out = base + per_impact * impact
@export var wall_push_impact := 2.5
@export var wall_cooldown := 0.15

@export_group("Handling")
@export var turn_rate_low := 2.3
@export var turn_rate_high := 1.15
@export var steer_response := 7.5
@export var grip := 10.0
@export var air_control := 0.35
@export var gravity := 24.0

@export_group("Drift")
@export var drift_grip := 2.4
@export var drift_yaw_base := 1.3
@export var drift_yaw_steer := 0.75
@export var drift_speed_factor := 0.96
@export var drift_min_speed := 11.0
@export var drift_slip_drag := 2.4
@export var mini_boost_min_drift := 0.45
@export var tap_window := 0.35
@export var exit_grip_time := 0.3      ## K6: grip ramps drift_grip -> grip after a drift
@export var exit_facing_share := 0.4   ## K6: nose swings back this share of the slip

@export_group("Boosts")
@export var mini_boost_bonus := 7.5
@export var mini_boost_time := 1.2
@export var double_boost_bonus := 9.0
@export var double_boost_time := 1.0
@export var super_start_bonus := 12.0
@export var super_start_time := 2.0
@export var super_start_early := 0.45
@export var super_start_late := 0.3
@export var air_boost_bonus := 5.0
@export var air_boost_time := 1.0
@export var air_boost_min_air := 0.22
@export var landing_boost_bonus := 3.0   ## 落地喷: +3 m/s for 1.5 s (user spec)
@export var landing_boost_time := 1.5
@export var landing_min_air := 0.25      ## meaningful air (was 0.35: 2 of 3 ramps never qualified)
@export var landing_window_time := 0.3   ## tap W within this after touchdown
@export var takeoff_lift := 0.7          ## K2: lip launch vy = speed * lip slope * this
@export var air_gap := 0.5               ## airborne when no ground within this below the kart
@export var nitro_bonus := 12.0
@export var nitro_time := 3.0
@export var pad_bonus := 10.0
@export var pad_time := 1.2

@export_group("Misc")
@export var respawn_freeze := 1.2
@export var shield_time := 10.0
