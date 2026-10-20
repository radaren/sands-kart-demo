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
@export var steer_response := 7.0      ## K8: turning in
@export var steer_return := 14.0       ## K8: back to centre (keyboard release no longer "sticky")
@export var steer_soften := 0.25       ## K8: at top speed, input beyond 0.9 is scaled down by this much
@export var grip := 10.0
@export var air_control := 0.35
@export var gravity := 24.0

@export_group("Drift")
@export var drift_grip := 2.4
@export var drift_yaw_base := 1.05     ## K7 (was 1.3)
@export var drift_yaw_steer := 0.85    ## K7 (was 0.75): range 0.2-1.9 rad/s
@export var drift_yaw_min := 0.15      ## K7 (was a hard 0.35)
@export var k14_slack := 1.5           ## K14: speed may exceed the real forward velocity by this much
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
## K4: double boost timing (seconds after the mini-boost tap)
@export var double_window_time := 0.6
@export var double_min_delay := 0.12     ## tapping earlier fails ("太早")
@export var double_perfect_from := 0.15
@export var double_perfect_to := 0.30
@export var perfect_double_bonus := 10.5
@export var perfect_double_time := 1.2
## K5: mini-boost tiers by drift time: blue / orange / purple
@export var mini_tier_times := PackedFloat32Array([0.45, 1.1, 1.8])
@export var mini_tier_bonus := PackedFloat32Array([7.5, 9.0, 10.5])
@export var mini_tier_boost_time := PackedFloat32Array([1.2, 1.4, 1.6])
@export var super_start_bonus := 12.0
@export var super_start_time := 2.0
## K13: tap within 0.35 s before GO (or 0.1 s after); earlier taps disqualify
@export var super_start_early := 0.35
@export var super_start_late := 0.1
@export var super_start_kick := 0.25
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

@export_group("Drift charge (漂移集气)")
@export var charge_enabled := true
@export var charge_rate := 0.22          ## gauge per second of drifting at the reference slip and speed
@export var charge_slip_ref := 0.6       ## rad; sharper drifts fill faster (factor clamped 0.3-1.6)
@export var charge_speed_ref := 26.0     ## m/s; factor clamped 0-1.25
@export var charge_mini_bonus := 0.04    ## landed mini boost
@export var charge_double_bonus := 0.06  ## landed double (perfect double x1.5)

@export_group("Misc")
@export var respawn_freeze := 1.2
@export var shield_time := 10.0
