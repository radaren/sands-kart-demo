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
signal shield_blocked(kart: Kart, kind: String)

enum Tone { GOOD, BAD, INFO }

const LAYER_WORLD := 1
const LAYER_KART := 2
const LAYER_WALL := 8
const MAX_ITEMS := 2
## K12: share of the entry speed a hit leaves you with (instead of stopping dead).
const HIT_RETAIN := {"banana": 0.45, "lightning": 0.55, "missile": 0.15}
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

# --- drift / boost ----------------------------------------------------------------
var drifting := false
var drift_dir := 0
var drift_time := 0.0
var mini_window := 0.0
var double_window := 0.0
var double_delay := 0.0
var landing_window := 0.0
var air_boost_ready := false
var start_window := 0.0
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
	_tick_effects(delta)
	var can_drive := not controls_locked and freeze_time <= 0.0 and stun_time <= 0.0
	var steer := clampf(in_steer, -1.0, 1.0) if can_drive else 0.0
	steer_state = move_toward(steer_state, steer, config.steer_response * delta)
	if can_drive:
		_update_drift(delta)
		_update_taps(delta)
		if in_item:
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
			add_boost("mini", config.mini_boost_bonus, config.mini_boost_time)
			double_window = 0.6
			double_delay = 0.12
			stat_mini_boosts += 1
			announced.emit(self, "小喷!", Tone.GOOD)
			return
	elif double_window > 0.0:
		double_window -= delta
		double_delay -= delta
		if in_tap and double_delay <= 0.0:
			double_window = 0.0
			var remaining: Vector2 = boosts.get("mini", Vector2.ZERO)
			add_boost("mini", config.double_boost_bonus, remaining.y + config.double_boost_time)
			announced.emit(self, "双喷!", Tone.GOOD)
			return
	if landing_window > 0.0:
		landing_window -= delta
		if in_tap:
			landing_window = 0.0
			add_boost("landing", config.landing_boost_bonus, config.landing_boost_time)
			announced.emit(self, "落地喷!", Tone.GOOD)
			return
	if not grounded and air_boost_ready and air_time >= config.air_boost_min_air and in_tap:
		air_boost_ready = false
		add_boost("air", config.air_boost_bonus, config.air_boost_time)
		announced.emit(self, "空喷!", Tone.GOOD)


## Called by the race manager the moment the light turns green.
func on_race_go(clock: float) -> void:
	controls_locked = false
	var pressed_recently := last_tap_clock >= clock - config.super_start_early and last_tap_clock <= clock + 0.05
	if in_throttle > 0.5 and pressed_recently:
		_super_start()
	else:
		start_window = config.super_start_late


func _super_start() -> void:
	start_window = 0.0
	add_boost("start", config.super_start_bonus, config.super_start_time, 0.6)
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
		rate = maxf(rate, 0.35)
		facing_yaw -= float(drift_dir) * rate * delta
		move_yaw = lerp_angle(move_yaw, facing_yaw, 1.0 - exp(-config.drift_grip * delta))
	else:
		var rate := lerpf(config.turn_rate_low, config.turn_rate_high, frac) * clampf(spd / 4.0, 0.0, 1.0)
		if not grounded:
			rate *= config.air_control
		var dir_sign := 1.0 if speed >= 0.0 else -1.0
		facing_yaw -= steer_state * rate * dir_sign * delta
		move_yaw = lerp_angle(move_yaw, facing_yaw, 1.0 - exp(-config.grip * delta))
	facing_yaw = wrapf(facing_yaw, -PI, PI)
	move_yaw = wrapf(move_yaw, -PI, PI)
	slip = wrapf(facing_yaw - move_yaw, -PI, PI)


func _move(delta: float) -> void:
	var dir := move_dir()
	var h := dir * speed + external
	external = external.move_toward(Vector3.ZERO, 9.0 * delta)
	var vy := velocity.y
	if grounded:
		vy = maxf(vy, -3.0)
	else:
		vy -= config.gravity * delta
	velocity = Vector3(h.x, vy, h.z)
	var was_grounded := grounded
	var air_before := air_time
	move_and_slide()
	_handle_collisions()
	grounded = is_on_floor()
	if grounded:
		ground_normal = get_floor_normal()
		if not was_grounded:
			_on_landed(air_before)
		air_time = 0.0
	else:
		if was_grounded:
			air_boost_ready = true
		air_time += delta
	rotation = Vector3(0.0, facing_yaw, 0.0)


func _on_landed(air: float) -> void:
	last_air_time = air
	if air > 0.2:
		landed.emit(self, air)
	air_boost_ready = false
	if air >= config.landing_min_air:
		landing_window = config.tap_window


func _handle_collisions() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		var other := col.get_collider()
		if other is Kart:
			_bump(other as Kart, n)
			continue
		if absf(n.y) > 0.6:
			continue
		var hn := Vector3(n.x, 0.0, n.z)
		if hn.length_squared() < 0.0001:
			continue
		hn = hn.normalized()
		var dir := move_dir()
		var impact := -dir.dot(hn)
		if impact <= 0.05:
			continue
		speed *= 1.0 - config.wall_speed_loss * clampf(impact * 1.3, 0.0, 1.0)
		var tangent := dir - hn * dir.dot(hn)
		if tangent.length_squared() > 0.0001:
			tangent = tangent.normalized()
			move_yaw = atan2(-tangent.x, -tangent.z)
			facing_yaw = lerp_angle(facing_yaw, move_yaw, 0.5)
		external += hn * (1.5 + 3.0 * impact)
		if drifting:
			_end_drift(false)
		if impact > 0.35:
			wall_hit.emit(self, impact)


func _bump(other: Kart, n: Vector3) -> void:
	var hn := Vector3(n.x, 0.0, n.z)
	if hn.length_squared() < 0.0001:
		return
	hn = hn.normalized()
	external += hn * 3.5
	other.external -= hn * 3.5
	speed *= 0.985


# ---------------------------------------------------------------------------
# effects + items
# ---------------------------------------------------------------------------
func add_boost(kind: String, bonus: float, duration: float, kick: float = 0.35) -> void:
	var fresh := not boosts.has(kind)
	var prev: Vector2 = boosts.get(kind, Vector2.ZERO)
	boosts[kind] = Vector2(maxf(prev.x, bonus), maxf(prev.y, duration))
	speed = maxf(speed, minf(speed + bonus * kick, base_top_speed() + bonus))
	# only signal a boost that starts or gets stronger (the magnet refreshes its
	# boost every tick; that must not spam sounds / FOV kicks)
	if fresh or bonus > prev.x:
		boosted.emit(self, kind)


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
