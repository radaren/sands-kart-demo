class_name Kart
extends CharacterBody3D
## Arcade kart built on CharacterBody3D.
##
## Controllers (PlayerInput / AIDriver) only write the in_* fields each tick, so
## the player and the AI drive exactly the same physics.
## Speeds are metres per second, yaw follows Godot's rotation.y convention
## (positive = turn left when seen from above).

signal announced(kart: Kart, text: String, tone: int)
signal hit_taken(kart: Kart, kind: String)
signal items_changed(kart: Kart)
signal boosted(kart: Kart, kind: String)
signal wall_hit(kart: Kart, strength: float)
signal landed(kart: Kart, air_time: float)
signal landing_window_opened(kart: Kart)
signal shield_blocked(kart: Kart, kind: String)
signal bumped(kart: Kart, other: Kart, strength: float, point: Vector3)

enum Tone { GOOD, BAD, INFO }

const LAYER_WORLD := 1
const LAYER_KART := 2
const LAYER_WALL := 8
const MAX_ITEMS := 2
## K12: share of the entry speed a hit leaves you with (instead of stopping dead).
const HIT_RETAIN := {"banana": 0.45, "lightning": 0.6, "missile": 0.15}
const HIT_RETAIN_DEFAULT := 0.35

@export var config: KartConfig

var display_name := "车手"
var body_color := Color(0.95, 0.5, 0.1)
var is_player := false
var race: Node = null
var track: TrackData = null
var controller: Node = null

# --- controller outputs -----------------------------------------------------
var in_steer := 0.0
var in_throttle := 0.0
var in_drift := false
var in_tap := false        ## accelerate was pressed this tick (mini boost / starts)
var in_item := false
var in_item_forward := false   ## I8: Q + item / Q alone throws a banana forward
var item_aim := -1            ## -1 behind (default), +1 forward; read by the item on spawn
var look_back := false

# --- race bookkeeping (written by RaceManager) --------------------------------
var progress := 0.0
var lateral := 0.0          ## signed offset from the centre line, + is right
var track_index := 0
var rank := 1
var finished := false
var finish_time := 0.0
var wrong_way_time := 0.0
var speed_scale := 1.0      ## AI rubber band x personal bias
var rubber := 1.0
var base_speed_bias := 1.0
var last_tap_clock := -99.0
var controls_locked := true

# --- motion ---------------------------------------------------------------------
var speed := 0.0
var facing_yaw := 0.0
var move_yaw := 0.0
var grounded := true
var ground_normal := Vector3.UP
var air_time := 0.0
var last_air_time := 0.0
var steer_state := 0.0
var freeze_time := 0.0
var external := Vector3.ZERO
var slip := 0.0
var exit_grip_left := 0.0      ## K6: time left in the post-drift grip ramp
var _wall_cd := 0.0            ## K9: wall impact cooldown
var scraping := false          ## V1: grinding along a wall this tick (sparks + scrape sound)
var wall_point := Vector3.ZERO ## last wall contact point (world)
var stat_bumps := 0
static var _pair_tick := {}    ## K10: "idA:idB" -> physics frame it was resolved

# --- drift / boost ----------------------------------------------------------------
var drifting := false
var drift_dir := 0
var drift_time := 0.0
var mini_window := 0.0
var double_window := 0.0
var double_delay := 0.0
var landing_window := 0.0
var air_boost_ready := false
var air_boost_used := false     ## once per airtime
var _snap_off := 0.0
var _tap_buffer := 0.0            ## floor snap disabled right after a launch
var stat_landing_boosts := 0
var stat_launches := 0
var start_window := 0.0
var start_jumped := false      ## K13: tapped too early in the countdown
var mini_tier := 0             ## K5: tier of the pending / last mini boost (1..3)
var stat_wall_hits := 0
var boost_full := {}           ## kind -> duration when it was (re)filled (H5)
var double_elapsed := 0.0      ## K4: time since the mini-boost tap
var stat_perfect_doubles := 0
var stat_doubles := 0
var boosts := {}            ## kind -> Vector2(bonus, remaining)
var slows := {}             ## kind -> Vector2(amount, remaining)
var stun_time := 0.0
var stun_total := 0.0
var stun_kind := ""
var stun_floor := 0.0          ## speed a stun decelerates to (K12)
var invuln_time := 0.0         ## post-hit invulnerability (K12)
var shield_time := 0.0
var cloud_time := 0.0
var items: Array[int] = []
## Spec/test view of the 2 item slots: [item_or_null, item_or_null].
var item_slots: Array:
	get:
		return [items[0] if items.size() > 0 else null, items[1] if items.size() > 1 else null]

# --- stats ------------------------------------------------------------------------
var stat_mini_boosts := 0
var stat_hits := 0


func _ready() -> void:
	if config == null:
		config = KartConfig.new()
	collision_layer = LAYER_KART
	collision_mask = LAYER_WORLD | LAYER_KART | LAYER_WALL
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = true
	floor_stop_on_slope = true
	max_slides = 4
	wall_min_slide_angle = deg_to_rad(8.0)
	safe_margin = 0.02


# ---------------------------------------------------------------------------
# public helpers
# ---------------------------------------------------------------------------
func forward_dir() -> Vector3:
	return Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))


func move_dir() -> Vector3:
	return Vector3(-sin(move_yaw), 0.0, -cos(move_yaw))


func boost_bonus() -> float:
	var bonus := 0.0
	for v: Vector2 in boosts.values():
		bonus = maxf(bonus, v.x)
	return bonus


## I4: slowdowns take the strongest one (like boosts), they don't add up.
func slow_amount() -> float:
	var worst := 0.0
	for v: Vector2 in slows.values():
		worst = maxf(worst, v.x)
	return worst


func is_boosting() -> bool:
	return not boosts.is_empty()


func base_top_speed() -> float:
	var top := config.max_speed * speed_scale
	if drifting:
		top *= config.drift_speed_factor
	return top


func drift_charged() -> bool:
	return drifting and drift_time >= config.mini_boost_min_drift


## K5: 0 = not charged, 1 blue (>=0.45 s), 2 orange (>=1.1 s), 3 purple (>=1.8 s)
func drift_tier() -> int:
	if not drifting:
		return 0
	var t := 0
	for i in config.mini_tier_times.size():
		if drift_time >= config.mini_tier_times[i]:
			t = i + 1
	return t


func kmh() -> float:
	return absf(speed) * 3.6


func place(at: Transform3D) -> void:
	global_position = at.origin
	var fwd := -at.basis.z
	facing_yaw = atan2(-fwd.x, -fwd.z)
	move_yaw = facing_yaw
	rotation = Vector3(0.0, facing_yaw, 0.0)
	velocity = Vector3.ZERO
	speed = 0.0
	external = Vector3.ZERO
	reset_physics_interpolation()


# ---------------------------------------------------------------------------
# main loop
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if controller != null and controller.has_method("compute"):
		controller.compute(delta)
	if in_tap and race != null:
		last_tap_clock = race.race_clock
		if controls_locked and race.get("go_clock") != null:
			countdown_tap(race.race_clock, float(race.get("go_clock")))
	_tick_effects(delta)
	var can_drive := not controls_locked and freeze_time <= 0.0 and stun_time <= 0.0
	var steer := clampf(in_steer, -1.0, 1.0) if can_drive else 0.0
	# K8: soften the last 10 % of input at speed (keyboard on/off feel)
	var sfrac := clampf(absf(speed) / config.max_speed, 0.0, 1.0)
	if absf(steer) > 0.9:
		steer = signf(steer) * (0.9 + (absf(steer) - 0.9) * (1.0 - config.steer_soften * sfrac))
	# K8: return to centre twice as fast as turning in
	var returning := absf(steer) < absf(steer_state) or signf(steer) != signf(steer_state)
	steer_state = move_toward(steer_state, steer, (config.steer_return if returning else config.steer_response) * delta)
	if can_drive:
		_update_drift(delta)
		_update_taps(delta)
		if in_item or in_item_forward:
			item_aim = 1 if in_item_forward else -1
			use_item()
	elif drifting:
		_end_drift(false)
	_update_speed(delta, in_throttle if can_drive else 0.0)
	_update_heading(delta)
	_move(delta)
	in_tap = false
	in_item = false


func _tick_effects(delta: float) -> void:
	for key: String in boosts.keys():
		var v: Vector2 = boosts[key]
		v.y -= delta
		if v.y <= 0.0:
			boosts.erase(key)
		else:
			boosts[key] = v
	for key: String in slows.keys():
		var v: Vector2 = slows[key]
		v.y -= delta
		if v.y <= 0.0:
			slows.erase(key)
		else:
			slows[key] = v
	if stun_time > 0.0:
		stun_time = maxf(0.0, stun_time - delta)
		if stun_time <= 0.0:
			invuln_time = config.hit_invuln_time
	else:
		invuln_time = maxf(0.0, invuln_time - delta)
	freeze_time = maxf(0.0, freeze_time - delta)
	shield_time = maxf(0.0, shield_time - delta)
	cloud_time = maxf(0.0, cloud_time - delta)


# ---------------------------------------------------------------------------
# drift + timing based boosts
# ---------------------------------------------------------------------------
func _update_drift(delta: float) -> void:
	if not drifting:
		if in_drift and grounded and absf(steer_state) > 0.25 and speed > config.drift_min_speed:
			drifting = true
			drift_dir = 1 if steer_state > 0.0 else -1
			drift_time = 0.0
			mini_window = 0.0
			double_window = 0.0
		return
	drift_time += delta
	if not in_drift or speed < config.drift_min_speed * 0.55:
		_end_drift(drift_time >= config.mini_boost_min_drift and speed >= config.drift_min_speed * 0.55)


func _end_drift(qualified: bool) -> void:
	if drifting:
		exit_grip_left = config.exit_grip_time
		mini_tier = maxi(1, drift_tier())
	drifting = false
	drift_dir = 0
	if qualified:
		mini_window = config.tap_window
	drift_time = 0.0


func _update_taps(delta: float) -> void:
	if start_window > 0.0:
		start_window -= delta
		if in_tap:
			start_window = 0.0
			_super_start()
			return
	if mini_window > 0.0:
		mini_window -= delta
		if in_tap:
			mini_window = 0.0
			var ti := clampi(mini_tier, 1, config.mini_tier_bonus.size()) - 1
			add_boost("mini", config.mini_tier_bonus[ti], config.mini_tier_boost_time[ti])
			double_window = config.double_window_time
			double_delay = config.double_min_delay
			double_elapsed = 0.0
			stat_mini_boosts += 1
			announced.emit(self, ["小喷!", "橙色小喷!", "紫色小喷!"][ti], Tone.GOOD)
			return
	elif double_window > 0.0:
		double_window -= delta
		double_delay -= delta
		double_elapsed += delta
		if in_tap:
			double_window = 0.0
			if double_elapsed < config.double_min_delay:
				announced.emit(self, "太早!", Tone.BAD)     # K4: mashing fails
				return
			var remaining: Vector2 = boosts.get("mini", Vector2.ZERO)
			stat_doubles += 1
			if double_elapsed >= config.double_perfect_from and double_elapsed <= config.double_perfect_to:
				stat_perfect_doubles += 1
				add_boost("mini", config.perfect_double_bonus, remaining.y + config.perfect_double_time)
				announced.emit(self, "完美双喷!", Tone.GOOD)
			else:
				add_boost("mini", config.double_boost_bonus, remaining.y + config.double_boost_time)
				announced.emit(self, "双喷!", Tone.GOOD)
			return
	if landing_window > 0.0:
		landing_window -= delta
		if in_tap or _tap_buffer > 0.0:
			_tap_buffer = 0.0
			landing_window = 0.0
			add_boost("landing", config.landing_boost_bonus, config.landing_boost_time, 1.0)
			stat_landing_boosts += 1
			announced.emit(self, "落地喷!", Tone.GOOD)
			return
	_tap_buffer = maxf(0.0, _tap_buffer - delta)
	if not grounded and in_tap and not (air_boost_ready and not air_boost_used and air_time >= config.air_boost_min_air):
		_tap_buffer = 0.1   # a tap just before touchdown still counts as the landing tap
	if not grounded and air_boost_ready and not air_boost_used and air_time >= config.air_boost_min_air and in_tap:
		air_boost_ready = false
		air_boost_used = true
		add_boost("air", config.air_boost_bonus, config.air_boost_time)
		announced.emit(self, "空喷!", Tone.GOOD)


## Called by the race manager the moment the light turns green.
## K13: a tap in the countdown more than super_start_early before GO jumps the
## start (no boost this race start); a tap in [GO-0.35, GO] or up to 0.1 s after
## GO gives the super start.
func countdown_tap(clock: float, go_clock: float) -> void:
	if clock < go_clock - config.super_start_early and clock > go_clock - 1.5:
		if not start_jumped:
			start_jumped = true
			announced.emit(self, "起步过早!", Tone.BAD)


func on_race_go(clock: float) -> void:
	controls_locked = false
	var pressed_recently := last_tap_clock >= clock - config.super_start_early and last_tap_clock <= clock + 0.02
	if start_jumped:
		start_window = 0.0
	elif in_throttle > 0.5 and pressed_recently:
		_super_start()
	else:
		start_window = config.super_start_late


func _super_start() -> void:
	start_window = 0.0
	add_boost("start", config.super_start_bonus, config.super_start_time, config.super_start_kick)
	announced.emit(self, "超级起步!", Tone.GOOD)


# ---------------------------------------------------------------------------
# longitudinal + lateral motion
# ---------------------------------------------------------------------------
func _update_speed(delta: float, throttle: float) -> void:
	if freeze_time > 0.0:
		speed = 0.0
		return
	if stun_time > 0.0:
		speed = move_toward(speed, stun_floor, config.stun_decel * delta)
		return
	var bonus := boost_bonus()
	var top := maxf(5.0, base_top_speed() + bonus - slow_amount())
	if not grounded:
		if speed > top:
			speed = move_toward(speed, top, config.overspeed_drag * 0.5 * delta)
		return
	if bonus > 0.0 and speed < top and throttle > -0.05:
		speed = minf(top, speed + config.boost_accel * delta)
	elif throttle > 0.05:
		var target := top * throttle
		if speed < target:
			var curve := clampf(1.25 - speed / maxf(target, 1.0), 0.3, 1.0)
			speed = minf(target, speed + config.accel * curve * delta)
		else:
			speed = move_toward(speed, target, config.overspeed_drag * delta)
	elif throttle < -0.05:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, config.brake * -throttle * delta)
		else:
			speed = move_toward(speed, -config.reverse_speed, config.accel * 0.5 * delta)
	else:
		speed = move_toward(speed, 0.0, config.coast_drag * delta)
		if speed > top:
			speed = move_toward(speed, top, config.overspeed_drag * delta)
	if drifting:
		var slip_factor := clampf(absf(slip) / 0.7, 0.0, 1.0)
		speed = maxf(0.0, speed - config.drift_slip_drag * slip_factor * delta)


func _update_heading(delta: float) -> void:
	var spd := absf(speed)
	var frac := clampf(spd / config.max_speed, 0.0, 1.0)
	if drifting:
		var rate := config.drift_yaw_base + steer_state * float(drift_dir) * config.drift_yaw_steer
		rate = maxf(rate, config.drift_yaw_min) * lerpf(1.15, 0.9, frac)   # K7: speed-dependent
		facing_yaw -= float(drift_dir) * rate * delta
		move_yaw = lerp_angle(move_yaw, facing_yaw, 1.0 - exp(-config.drift_grip * delta))
	else:
		var rate := lerpf(config.turn_rate_low, config.turn_rate_high, frac) * clampf(spd / 4.0, 0.0, 1.0)
		if not grounded:
			rate *= config.air_control
		var dir_sign := 1.0 if speed >= 0.0 else -1.0
		facing_yaw -= steer_state * rate * dir_sign * delta
		if exit_grip_left > 0.0:
			# K6: leaving a drift, grip ramps up over exit_grip_time and the nose
			# swings back part of the way, so the exit doesn't "snap"
			var k := 1.0 - exit_grip_left / maxf(config.exit_grip_time, 0.001)
			var g := lerpf(config.drift_grip, config.grip, k * k)
			exit_grip_left = maxf(0.0, exit_grip_left - delta)
			var a := 1.0 - exp(-g * delta)
			var gap := wrapf(facing_yaw - move_yaw, -PI, PI)
			move_yaw = wrapf(move_yaw + gap * a * (1.0 - config.exit_facing_share), -PI, PI)
			facing_yaw = wrapf(facing_yaw - gap * a * config.exit_facing_share, -PI, PI)
		else:
			move_yaw = lerp_angle(move_yaw, facing_yaw, 1.0 - exp(-config.grip * delta))
	facing_yaw = wrapf(facing_yaw, -PI, PI)
	move_yaw = wrapf(move_yaw, -PI, PI)
	slip = wrapf(facing_yaw - move_yaw, -PI, PI)


func _move(delta: float) -> void:
	var dir := move_dir()
	var h := dir * speed + external
	external = external.move_toward(Vector3.ZERO, 9.0 * delta)
	var vy := velocity.y
	var launched := false
	if grounded:
		vy = minf(vy, 0.0) - 4.0 if not _on_ramp_rise() else maxf(vy, -3.0)
		# K2: explicit kicker launch at the lip so the jump (and the landing
		# boost) doesn't depend on how the slide projection happened to go
		if track != null and speed > 8.0:
			var lip := track.ramp_lip_near(progress)
			if lip > 0.0:
				vy = minf(6.0, speed * maxf(0.0, track.slope_before(lip)) * config.takeoff_lift)
				launched = true
	else:
		vy -= config.gravity * delta
	velocity = Vector3(h.x, vy, h.z)
	_snap_off = maxf(0.0, _snap_off - delta)
	if launched:
		_snap_off = 0.25
		stat_launches += 1
	floor_snap_length = 0.0 if _snap_off > 0.0 else 0.45
	var was_grounded := grounded
	var air_before := air_time
	move_and_slide()
	_handle_collisions()
	# K14: blocked by a kart or a wall, the speed value follows the real motion
	if is_on_floor() and speed > 0.0 and not launched:
		var n := get_floor_normal()
		var along := (dir - n * dir.dot(n)).normalized()     # along the slope (ramps!)
		var real_fwd := get_real_velocity().dot(along)
		speed = minf(speed, maxf(real_fwd, 0.0) + config.k14_slack)
	grounded = is_on_floor() and _snap_off <= 0.0
	if grounded and not _ground_below(config.air_gap + 0.3):
		grounded = false   # dune crest: floor flag stuck but nothing under the wheels
	if grounded:
		ground_normal = get_floor_normal()
		if not was_grounded:
			_on_landed(air_before)
		air_time = 0.0
	else:
		if was_grounded:
			air_boost_ready = true
			air_boost_used = false
		air_time += delta
	rotation = Vector3(0.0, facing_yaw, 0.0)


func _on_ramp_rise() -> bool:
	if track == null:
		return false
	for r in track.ramps:
		if progress >= r - 1.0 and progress <= r + track.ramp_length + 0.5:
			return true
	return false


func _ground_below(dist: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (dist + 0.3), LAYER_WORLD)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


func _on_landed(air: float) -> void:
	last_air_time = air
	if air > 0.2:
		landed.emit(self, air)
	air_boost_ready = false
	if air >= config.landing_min_air:
		landing_window = config.landing_window_time
		landing_window_opened.emit(self)


func _handle_collisions() -> void:
	# K9: resolve only the strongest wall contact per tick (corners used to
	# stack up to 4 speed cuts), gentle nose re-alignment, impact-scaled push,
	# short cooldown so scraping along a wall doesn't keep re-triggering.
	_wall_cd = maxf(0.0, _wall_cd - get_physics_process_delta_time())
	var best_impact := 0.0
	var best_n := Vector3.ZERO
	var touching := false
	var dir := move_dir()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		var other := col.get_collider()
		if other is Kart:
			_bump(other as Kart, n, col.get_position())
			continue
		if absf(n.y) > 0.6:
			continue
		var hn := Vector3(n.x, 0.0, n.z)
		if hn.length_squared() < 0.0001:
			continue
		hn = hn.normalized()
		var impact := -dir.dot(hn)
		touching = true
		wall_point = col.get_position()
		if impact > best_impact:
			best_impact = impact
			best_n = hn
	scraping = touching and absf(speed) > 6.0
	if best_impact <= 0.05:
		return
	var tangent := dir - best_n * dir.dot(best_n)
	if tangent.length_squared() > 0.0001:
		tangent = tangent.normalized()
		move_yaw = atan2(-tangent.x, -tangent.z)
		facing_yaw = lerp_angle(facing_yaw, move_yaw, 0.25)
	if _wall_cd > 0.0:
		return
	_wall_cd = config.wall_cooldown
	var impact := clampf(best_impact, 0.0, 1.0)
	speed *= 1.0 - (config.wall_loss_base + config.wall_loss_quad * impact * impact)
	external += best_n * (config.wall_push_base + config.wall_push_impact * impact)
	if drifting and impact > 0.3:
		_end_drift(false)
	stat_wall_hits += 1
	wall_hit.emit(self, impact)


## K10: one resolution per kart pair per tick (whichever kart detects it first),
## impulse from the closing speed, and rear-ending hands 30% of the speed
## difference to the kart in front instead of both just bouncing.
func _bump(other: Kart, n: Vector3, point: Vector3) -> void:
	var hn := Vector3(n.x, 0.0, n.z)        # points from other towards self
	if hn.length_squared() < 0.0001:
		return
	hn = hn.normalized()
	var a := mini(get_instance_id(), other.get_instance_id())
	var b := maxi(get_instance_id(), other.get_instance_id())
	var key := "%d:%d" % [a, b]
	var frame := Engine.get_physics_frames()
	if int(_pair_tick.get(key, -100)) >= frame - 6:   # resolved this tick or just now
		return
	_pair_tick[key] = frame
	if _pair_tick.size() > 64:
		_pair_tick.clear()
		_pair_tick[key] = frame
	var v_self := move_dir() * speed
	var v_other := other.move_dir() * other.speed
	var closing := maxf(0.0, (v_self - v_other).dot(-hn))
	var imp := clampf(closing * 0.6, 1.2, 6.0)
	external += hn * imp * 0.5
	other.external -= hn * imp * 0.5
	# rear-end: I'm behind and faster -> push them along, lose some myself
	var to_other := other.global_position - global_position
	to_other.y = 0.0
	if to_other.length_squared() > 0.0001 and forward_dir().dot(to_other.normalized()) > 0.6 and speed > other.speed:
		var dv := (speed - other.speed) * 0.3
		other.speed += dv
		speed -= dv
	elif other.forward_dir().dot(-to_other.normalized()) > 0.6 and other.speed > speed:
		var dv2 := (other.speed - speed) * 0.3
		speed += dv2
		other.speed -= dv2
	stat_bumps += 1
	var strength := clampf(closing / 10.0, 0.1, 1.0)
	bumped.emit(self, other, strength, point)


# ---------------------------------------------------------------------------
# effects + items
# ---------------------------------------------------------------------------
func add_boost(kind: String, bonus: float, duration: float, kick: float = 0.35) -> void:
	var fresh := not boosts.has(kind)
	var prev: Vector2 = boosts.get(kind, Vector2.ZERO)
	boosts[kind] = Vector2(maxf(prev.x, bonus), maxf(prev.y, duration))
	if fresh or duration > prev.y:
		boost_full[kind] = maxf(duration, 0.01)   # H5: HUD shows time left / full
	speed = maxf(speed, minf(speed + bonus * kick, base_top_speed() + bonus))
	# only signal a boost that starts or gets stronger (the magnet refreshes its
	# boost every tick; that must not spam sounds / FOV kicks)
	if fresh or bonus > prev.x:
		boosted.emit(self, kind)


## H5: strongest active boost: [kind, fraction of its time left] or ["", 0].
func boost_meter() -> Array:
	var best := ""
	var bonus := 0.0
	for kind in boosts:
		var v: Vector2 = boosts[kind]
		if v.y > 0.0 and v.x > bonus:
			bonus = v.x
			best = kind
	if best == "":
		return ["", 0.0]
	return [best, clampf((boosts[best] as Vector2).y / float(boost_full.get(best, 1.0)), 0.0, 1.0)]


func add_slow(kind: String, amount: float, duration: float) -> void:
	var prev: Vector2 = slows.get(kind, Vector2.ZERO)
	slows[kind] = Vector2(maxf(prev.x, amount), maxf(prev.y, duration))


## Returns false when a shield absorbed the hit.
func hit(kind: String, stun: float, blockable: bool, slow_amt: float = 0.0, slow_dur: float = 0.0) -> bool:
	if invuln_time > 0.0 or (stun_time > 0.0 and stun > 0.0):
		return false    # K12: no chain hits while spinning / just recovered
	if blockable and shield_time > 0.0:
		shield_time = 0.0
		announced.emit(self, "护盾抵挡!", Tone.GOOD)
		shield_blocked.emit(self, kind)
		return false
	if stun > 0.0:
		stun_time = maxf(stun_time, stun)
		stun_total = stun_time
		stun_kind = kind
		stun_floor = maxf(0.0, speed) * float(HIT_RETAIN.get(kind, HIT_RETAIN_DEFAULT))
		boosts.clear()
		mini_window = 0.0
		double_window = 0.0
		if drifting:
			_end_drift(false)
	if slow_amt > 0.0:
		add_slow(kind, slow_amt, slow_dur)
	stat_hits += 1
	hit_taken.emit(self, kind)
	return true


func receive_item_box() -> void:
	if race != null and race.has_method("on_item_box"):
		race.on_item_box(self)


func give_item(item: int) -> bool:
	if items.size() >= MAX_ITEMS or item == ItemDefs.NONE:
		return false
	items.append(item)
	items_changed.emit(self)
	return true


func use_item() -> void:
	if items.is_empty() or race == null:
		return
	var item: int = items.pop_front()
	items_changed.emit(self)
	race.item_system.use_item(self, item)


func respawn_on_track() -> void:
	if track == null:
		return
	var s := maxf(track.start_offset - 12.0, progress - 6.0)
	var at := track.spawn_transform(s, clampf(lateral * 0.3, -2.5, 2.5))
	place(at)
	freeze_time = config.respawn_freeze
	stun_time = 0.0
	boosts.clear()
	slows.clear()
	drifting = false
	drift_dir = 0
	grounded = false
	air_time = 0.0
	air_boost_ready = false
	wrong_way_time = 0.0
	announced.emit(self, "已重置", Tone.INFO)
