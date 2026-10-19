class_name KartConfig
extends Resource
## Shared vehicle tuning (m, m/s, s). All 6 karts use the same config.

@export_group("Speed")
@export var base_speed := 12.0          ## m/s top speed holding throttle
@export var drift_speed := 9.0          ## m/s target while drifting
@export var reverse_speed := 4.0
@export var accel := 9.0                ## m/s^2 normal acceleration
@export var boost_accel := 30.0         ## m/s^2 while any boost buff is active
@export var coast_decel := 4.0
@export var brake_decel := 18.0
@export var drift_decel := 5.0
@export var mass_kg := 150.0

@export_group("Steering")
@export var steer_rate := 2.1           ## rad/s at low speed
@export var steer_rate_high := 1.35     ## rad/s at nitro speed
@export var grip := 10.0                ## how fast velocity follows heading (1/s)
@export var drift_grip := 2.6
@export var drift_turn_base := 1.1      ## rad/s auto-rotation into the drift
@export var drift_turn_steer := 0.8     ## extra rad/s from steering while drifting
@export var drift_min_speed := 6.0

@export_group("Mini boost (小喷)")
@export var drift_min_angle_deg := 30.0
@export var drift_min_time := 0.3
@export var mini_window := 0.3          ## seconds after releasing drift to press throttle
@export var mini_bonus := 3.0
@export var mini_time := 1.5
@export var double_chain_time := 1.0    ## time after a mini boost in which a short drift qualifies for 双喷
@export var double_min_time := 0.15
@export var double_min_angle_deg := 10.0

@export_group("Other boosts")
@export var start_bonus := 5.0
@export var start_time := 2.0
@export var air_bonus := 2.0
@export var air_time := 1.0
@export var landing_window := 0.3
@export var landing_bonus := 3.0
@export var landing_time := 1.5
@export var nitro_bonus := 6.0
@export var nitro_time := 3.0

@export_group("Physics")
@export var gravity := 22.0
@export var air_threshold := 0.5        ## ground distance above which the kart is airborne
@export var wall_speed_keep := 0.55
@export var respawn_penalty := 3.0
