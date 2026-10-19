class_name KartPhysics
extends CharacterBody3D
## Shared arcade kart physics for player and AI.
## Inputs (written by a controller component every physics tick):
##   in_steer (-1..1, +1 = right), in_throttle (0..1), in_drift (bool), in_use_item (bool)
## Ground: raycast snapping (no physical floor collision -> no edge snagging).
## Body yaw = heading; Visual is aligned to the ground normal (global_basis.y).

signal boost_fired(kind: String)
signal item_changed(kart)
signal got_hit(kart, kind: String)
signal finished_race(kart)
signal respawned(kart)

const DEFAULT_CONFIG := preload("res://data/kart_config.tres")
const GROUND_MASK := 1

@export var config: KartConfig
@export var kart_color := Color(0.9, 0.15, 0.12)
@export var driver_name := "玩家"
@export var is_player := false

var track          # SandsTrack
var controller     # node with compute_input(kart, delta)
var race_manager   # RaceManager
var item_system    # ItemSystem

# ---- unified input ----
var in_steer := 0.0
var in_throttle := 0.0
var in_brake := 0.0
var in_drift := false
var in_use_item := false
var in_respawn := false
var _prev_throttle := 0.0
var _prev_use := false
var _prev_respawn := false

# ---- motion state ----
var can_drive := false
var speed := 0.0
var heading := 0.0
var move_heading := 0.0
var vy := 0.0
var grounded := true
var ground_normal := Vector3.UP
var ground_dist := 0.0
var airtime := 0.0
var air_boost_used := false
var landing_window := 0.0
var landing_count := 0

# ---- drift / mini boost ----
var drifting := false
var drift_side := 0.0       # +1 right, -1 left
var drift_time := 0.0
var drift_angle := 0.0      # accumulated degrees
var mini_window := 0.0
var mini_is_double := false
var chain_timer := 0.0
var mini_boost_count := 0
var double_boost_count := 0
var air_boost_count := 0
var landing_boost_count := 0
var start_boost := false

# ---- buffs ----
var boosts: Array = []      # [{bonus, time, kind}]
var speed_multiplier := 1.0 # rubber band (AI only)
var stun_time := 0.0
var slow_time := 0.0
var slow_factor := 1.0
var shield_time := 0.0
var fog_time := 0.0
var frozen_time := 0.0
var incoming_threat := false

# ---- items ----
var item_slots: Array = [null, null]

# ---- race ----
var progress := 0.0
var lap := 1
var next_checkpoint := 0
var finished := false
var finish_time := 0.0
var rank := 1
var wrong_way := false
var _wrong_timer := 0.0
var _stuck_timer := 0.0
var autopilot_after_finish := true

var visual: KartVisual
var _t := 0.0
var _spin_visual := 0.0


func _ready() -> void:
	if config == null:
		config = DEFAULT_CONFIG
	collision_layer = 4
	collision_mask = 2 | 4
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	visual = KartVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(kart_color, driver_name)
	add_to_group("karts")


func place_at(s: float, lateral: float) -> void:
	var p: Vector3 = track.point_at(s) + track.right_at(s) * lateral
	global_position = p
	heading = track.heading_at(s)
	move_heading = heading
	rotation = Vector3(0, heading, 0)
	progress = s
	speed = 0.0
	vy = 0.0


# ======================================================================
func _physics_process(delta: float) -> void:
	_t += delta
	if controller:
		controller.compute_input(self, delta)
	if finished and not is_player and controller == null:
		in_throttle = 0.0
	var throttle_edge := in_throttle > 0.5 and _prev_throttle <= 0.5
	_tick_timers(delta)

	if frozen_time > 0.0:
		speed = 0.0
		visual.visible = int(_t * 10.0) % 2 == 0
		_update_visual(delta)
		_prev_throttle = in_throttle
		return
	visual.visible = true

	if not can_drive:
		speed = move_toward(speed, 0.0, 20.0 * delta)
		_update_ground_state(delta)
		_update_visual(delta)
		_prev_throttle = in_throttle
		return

	if in_respawn and not _prev_respawn:
		respawn(true)
	_prev_respawn = in_respawn

	_update_ground_state(delta)
	_handle_drift(delta, throttle_edge)
	_handle_air_boosts(throttle_edge)
	_handle_pads()
	_integrate_speed(delta)
	_steer(delta)
	_move(delta)
	_update_progress(delta)

	if in_use_item and not _prev_use and item_system:
		item_system.use_item(self)
	_prev_use = in_use_item
	_prev_throttle = in_throttle
	_update_visual(delta)


func _tick_timers(delta: float) -> void:
	for b in boosts:
		b.time -= delta
	boosts = boosts.filter(func(b): return b.time > 0.0)
	mini_window = maxf(0.0, mini_window - delta)
	chain_timer = maxf(0.0, chain_timer - delta)
	landing_window = maxf(0.0, landing_window - delta)
	stun_time = maxf(0.0, stun_time - delta)
	slow_time = maxf(0.0, slow_time - delta)
	shield_time = maxf(0.0, shield_time - delta)
	fog_time = maxf(0.0, fog_time - delta)
	frozen_time = maxf(0.0, frozen_time - delta)


# ---------------------------------------------------------------- ground
func _ray_ground() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, GROUND_MASK)
	return space.intersect_ray(q)


func _update_ground_state(delta: float) -> void:
	var hit := _ray_ground()
	var was_grounded := grounded
	if hit.is_empty():
		ground_dist = 99.0
		grounded = false
	else:
		ground_dist = global_position.y - hit.position.y
		if grounded:
			grounded = ground_dist < config.air_threshold
		else:
			# landing: falling and the ground is within this frame's fall step (+0.2 m)
			grounded = ground_dist < maxf(0.2, -vy * delta + 0.05) and vy <= 0.5
		if grounded:
			ground_normal = ground_normal.slerp(hit.normal, clampf(12.0 * delta, 0.0, 1.0))
	if not grounded:
		airtime += delta
		ground_normal = ground_normal.slerp(Vector3.UP, clampf(2.0 * delta, 0.0, 1.0))
	if grounded and not was_grounded:
		if airtime > 0.25:
			landing_window = config.landing_window   # 落地喷就绪
			landing_count += 1
		airtime = 0.0
		air_boost_used = false
	if grounded:
		airtime = 0.0


# ---------------------------------------------------------------- drift
func _handle_drift(delta: float, throttle_edge: bool) -> void:
	if not drifting:
		if in_drift and grounded and stun_time <= 0.0 and absf(in_steer) > 0.2 and speed > config.drift_min_speed:
			drifting = true
			drift_side = signf(in_steer)
			drift_time = 0.0
			drift_angle = 0.0
	else:
		drift_time += delta
		if not in_drift or speed < 3.5 or stun_time > 0.0:
			drifting = false
			var ok_single := drift_time >= config.drift_min_time and drift_angle >= config.drift_min_angle_deg
			var ok_double := chain_timer > 0.0 and drift_time >= config.double_min_time and drift_angle >= config.double_min_angle_deg
			if ok_single or ok_double:
				mini_window = config.mini_window      # 小喷就绪
				mini_is_double = chain_timer > 0.0
	if mini_window > 0.0 and throttle_edge:
		mini_window = 0.0
		mini_boost_count += 1
		if mini_is_double:
			double_boost_count += 1
			chain_timer = 0.0
			add_boost(config.mini_bonus, config.mini_time, "double")
		else:
			chain_timer = config.double_chain_time
			add_boost(config.mini_bonus, config.mini_time, "mini")


func _handle_air_boosts(throttle_edge: bool) -> void:
	if not throttle_edge:
		return
	if not grounded and not air_boost_used and airtime > 0.05:
		air_boost_used = true
		air_boost_count += 1
		add_boost(config.air_bonus, config.air_time, "air")
	elif grounded and landing_window > 0.0:
		landing_window = 0.0
		landing_boost_count += 1
		add_boost(config.landing_bonus, config.landing_time, "landing")


func _handle_pads() -> void:
	if not grounded or track == null:
		return
	var lateral: float = track.lateral_of(global_position, progress)
	var pad: Dictionary = track.boost_pad_at(progress, lateral)
	if not pad.is_empty():
		add_boost(pad.bonus, pad.time, "pad", true)


## Stacking buffs: each keeps its own timer; effective bonus = max of active.
func add_boost(bonus: float, time: float, kind: String, refresh := false) -> void:
	if refresh:
		for b in boosts:
			if b.kind == kind:
				b.time = maxf(b.time, time)
				b.bonus = maxf(b.bonus, bonus)
				return
	boosts.append({"bonus": bonus, "time": time, "kind": kind})
	boost_fired.emit(kind)


func current_bonus() -> float:
	var best := 0.0
	for b in boosts:
		best = maxf(best, b.bonus)
	return best


func has_boost(kind: String) -> bool:
	for b in boosts:
		if b.kind == kind:
			return true
	return false


# ---------------------------------------------------------------- speed
func _integrate_speed(delta: float) -> void:
	var bonus := current_bonus()
	var base := config.drift_speed if drifting else config.base_speed
	var target := 0.0
	if in_throttle > 0.1:
		target = base * speed_multiplier * in_throttle
	if bonus > 0.0:
		target = base * speed_multiplier + bonus
	if slow_time > 0.0:
		target *= slow_factor
	if stun_time > 0.0:
		speed = move_toward(speed, 0.0, 25.0 * delta)
		return
	if not grounded:
		# keep momentum in the air, boosts still push
		if bonus > 0.0 and speed < target:
			speed = move_toward(speed, target, config.boost_accel * 0.5 * delta)
		return
	if in_brake > 0.1 and in_throttle < 0.1:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, config.brake_decel * delta)
		else:
			speed = move_toward(speed, -config.reverse_speed, config.accel * 0.6 * delta)
		return
	if speed < target:
		speed = move_toward(speed, target, (config.boost_accel if bonus > 0.0 else config.accel) * delta)
	else:
		var dec := config.drift_decel if drifting else config.coast_decel
		if speed > target + 2.0:
			dec *= 2.0
		speed = move_toward(speed, target, dec * delta)


func _steer(delta: float) -> void:
	if stun_time > 0.0:
		_spin_visual += 14.0 * delta
		return
	var turn := 0.0
	var sp := absf(speed)
	if drifting:
		turn = -(drift_side * config.drift_turn_base + in_steer * config.drift_turn_steer)
		drift_angle += rad_to_deg(absf(turn * delta))
	else:
		var rate := lerpf(config.steer_rate, config.steer_rate_high, clampf(sp / 18.0, 0.0, 1.0))
		rate *= clampf(sp / 3.0, 0.0, 1.0)
		turn = -in_steer * rate * signf(speed if absf(speed) > 0.01 else 1.0)
	if not grounded:
		turn *= 0.4
	heading = wrapf(heading + turn * delta, -PI, PI)
	var g := config.drift_grip if drifting else config.grip
	move_heading = lerp_angle(move_heading, heading, clampf(g * delta, 0.0, 1.0))


func _move(delta: float) -> void:
	var fwd := Vector3(-sin(move_heading), 0.0, -cos(move_heading))
	if grounded:
		var on_plane := (fwd - ground_normal * fwd.dot(ground_normal)).normalized()
		velocity = on_plane * speed
		vy = velocity.y
	else:
		vy -= config.gravity * delta
		velocity = fwd * speed + Vector3.UP * vy
	rotation = Vector3(0.0, heading, 0.0)
	move_and_slide()
	# wall / kart contacts
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var other := c.get_collider()
		if other is KartPhysics:
			# bump: share speed a little
			var o: KartPhysics = other
			if speed > o.speed:
				o.speed = minf(o.speed + 1.0, speed)
				speed *= 0.92
		else:
			var hit_dot := fwd.dot(-n)
			if hit_dot > 0.35:
				speed *= lerpf(1.0, config.wall_speed_keep, hit_dot)
				if drifting and hit_dot > 0.6:
					drifting = false
			# slide along wall: rotate heading towards wall tangent slightly
			var tangent := Vector3(-n.z, 0, n.x)
			if tangent.dot(fwd) < 0:
				tangent = -tangent
			var th := atan2(-tangent.x, -tangent.z)
			heading = lerp_angle(heading, th, 0.15)
			move_heading = lerp_angle(move_heading, th, 0.3)
	# snap to ground
	if grounded:
		var hit := _ray_ground()
		if not hit.is_empty() and global_position.y - hit.position.y < config.air_threshold + 0.3:
			global_position.y = hit.position.y
	if global_position.y < -60.0:
		respawn(true)


# ---------------------------------------------------------------- progress
func _update_progress(delta: float) -> void:
	if track == null:
		return
	var s: float = track.closest_offset(global_position, progress)
	progress = s
	var cps: Array = track.checkpoints
	while next_checkpoint < cps.size() and progress >= cps[next_checkpoint]:
		next_checkpoint += 1
	# wrong way detection
	var tan: Vector3 = track.tangent_at(progress)
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	if fwd.dot(tan) < -0.2 and absf(speed) > 2.0:
		_wrong_timer += delta
	else:
		_wrong_timer = maxf(0.0, _wrong_timer - delta * 2.0)
	wrong_way = _wrong_timer > 0.8
	# stuck detection (AI auto respawn)
	if absf(speed) < 1.0 and not finished:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	if not is_player and (_stuck_timer > 3.0 or _wrong_timer > 3.0):
		respawn(true)
	if not finished and progress >= track.length - 1.0 and next_checkpoint >= cps.size():
		finished = true
		finished_race.emit(self)


## Respawn on the centre line slightly behind the current progress; 3 s frozen penalty.
func respawn(penalty := true) -> void:
	var s := clampf(progress - 4.0, 1.0, track.length - 5.0)
	place_at(s, 0.0)
	drifting = false
	boosts.clear()
	stun_time = 0.0
	_wrong_timer = 0.0
	_stuck_timer = 0.0
	grounded = true
	if penalty:
		frozen_time = config.respawn_penalty
	respawned.emit(self)


# ---------------------------------------------------------------- items/hits
func give_item(item: String) -> bool:
	for i in item_slots.size():
		if item_slots[i] == null:
			item_slots[i] = item
			item_changed.emit(self)
			return true
	return false


func take_item() -> Variant:
	var it: Variant = item_slots[0]
	if it == null:
		return null
	item_slots[0] = item_slots[1]
	item_slots[1] = null
	item_changed.emit(self)
	return it


func has_free_slot() -> bool:
	return item_slots.has(null)


## Returns false if blocked by shield.
func apply_hit(kind: String, stun := 1.0, slow := 1.0, slow_dur := 0.0) -> bool:
	if shield_time > 0.0:
		shield_time = 0.0
		got_hit.emit(self, "blocked")
		return false
	if stun > 0.0:
		stun_time = maxf(stun_time, stun)
		drifting = false
		boosts.clear()
	if slow_dur > 0.0:
		slow_time = maxf(slow_time, slow_dur)
		slow_factor = slow
	got_hit.emit(self, kind)
	return true


# ---------------------------------------------------------------- visuals
func _update_visual(delta: float) -> void:
	if visual == null:
		return
	var yaw_offset := 0.0
	if drifting:
		yaw_offset = -drift_side * deg_to_rad(28.0)
	if stun_time > 0.0:
		yaw_offset += _spin_visual
	else:
		_spin_visual = 0.0
	var up := ground_normal.normalized()
	var fwd := Vector3(-sin(heading + yaw_offset), 0.0, -cos(heading + yaw_offset))
	var right := fwd.cross(up).normalized()
	var f2 := up.cross(right).normalized()
	var target := Basis(right, up, -f2).orthonormalized()
	visual.global_basis = visual.global_basis.orthonormalized().slerp(target, clampf(10.0 * delta, 0.0, 1.0))
	var dstate := 0
	if drifting:
		dstate = 2 if (drift_time >= config.drift_min_time and drift_angle >= config.drift_min_angle_deg) else 1
	if mini_window > 0.0 or landing_window > 0.0:
		dstate = 2
	visual.update_fx(current_bonus() > 0.0, dstate, shield_time > 0.0, speed * delta / 0.3, _t)


func total_progress() -> float:
	if track == null:
		return 0.0
	return (lap - 1) * track.length + progress


func speed_kmh() -> float:
	return absf(speed) * 3.6
