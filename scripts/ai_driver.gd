class_name AIDriver
extends Node
## AI driving component (same Kart physics as the player).
## - Look-ahead on the centre line (8-15 m, grows with speed) + personal lane offset,
##   narrowed / pulled to the inside of corners.
## - Drifts into tight corners: when the radius a short "lead time" ahead drops below
##   drift_radius it starts drifting ~0.2 s early, releases on exit and taps the
##   throttle 0.1 s later for the mini boost (and again for the double boost).
## - Personality: aggression, defense, mistake_rate; one rival per race.
## - Items are used after a 0.3-0.8 s human-like delay with simple targeting rules.
## Spec note: the design doc's 18 m drift radius assumed 12 m/s; the base project
## runs 30 m/s, so the default threshold is scaled to 30 m (exported, tweakable).

@export var aggression := 0.5      ## 0..1 earlier drift, tighter lines
@export var defense := 0.5         ## 0..1 more defensive items when leading
@export var mistake_rate := 0.2    ## 0.15..0.3 chance every 5 s of a short mistake (A3)
@export var lane_offset := 0.0     ## -1.5..1.5 m
@export var is_rival := false
@export var drift_radius := 30.0
@export var manual_items := false  ## autopilot for the player: items come from Input
@export var start_boost_chance := 0.7
@export var skill := 0.75          ## 0.55..0.9 (A1): mini boost success = skill, double = skill^2

var _aim_fwd := false
var kart: Kart
var _rng := RandomNumberGenerator.new()
var _mistake_timer := 0.0
var _mistake_steer := 0.0
var _mistake_check := 5.0
var _delayed_steer := 0.0
var _tap_in := -1.0           ## seconds until the next throttle tap
var _double_pending := false
var _double_at := 0.2
var _item_delay := -1.0
var _item_hold := 0.0
var _drift_cooldown := 0.0
var _want_drift := false
var _start_tap_at := -1.0
var _prev_item_input := false
var stat_drifts := 0
var _air_roll_done := false
var _air_go := false
var _land_go := false
var _shield_wait := -1.0       ## A2: reaction time left before deciding on the shield
var _mistake_kind := 0         ## A3: 0 steer, 1 late turn-in, 2 over-drift, 3 lift-off
var stat_mini_attempts := 0
var stat_mini_planned := 0
var stat_double_planned := 0
var stat_mistakes := 0
var _lane_s := 0.0
var stat_steer_jitter := 0.0     ## sum |d steer| (A5 measure)
var stat_ticks := 0
var _prev_out_steer := 0.0
var _box_row_s := -1.0
var _box_go := false


func _ready() -> void:
	if kart == null:
		kart = get_parent() as Kart


func setup(seed_value: int) -> void:
	_rng.seed = seed_value
	_mistake_check = _rng.randf_range(3.0, 5.0)


## Called by RaceManager during the countdown with the GO clock time.
func plan_start(go_clock: float) -> void:
	if _rng.randf() < start_boost_chance:
		_start_tap_at = go_clock - _rng.randf_range(0.03, 0.32)   # K13 window is 0.35 s
	else:
		_start_tap_at = go_clock + _rng.randf_range(0.5, 0.9)   # late, no super start


func _turn_sign(track: TrackData, s: float) -> float:
	var a := track.tangent_at(s)
	var b := track.tangent_at(s + 6.0)
	var ang := a.signed_angle_to(b, Vector3.UP)   # + = left
	return signf(ang)


func _min_radius(track: TrackData, s0: float, span: float) -> Vector2:
	## x = smallest radius in [s0, s0+span], y = its turn sign (+1 left / -1 right)
	var best := 1e6
	var best_s := s0
	var s := s0
	while s <= s0 + span:
		var r := track.radius_at(s)
		if r < best:
			best = r
			best_s = s
		s += 2.0
	return Vector2(best, _turn_sign(track, best_s - 3.0))


func compute(delta: float) -> void:
	if kart == null or kart.track == null:
		return
	var track := kart.track
	var s := kart.progress
	var sp := absf(kart.speed)
	var clock: float = kart.race.race_clock if kart.race != null else 0.0

	# ---------- countdown: hold throttle, tap for the super start ----------
	if kart.controls_locked:
		kart.in_steer = 0.0
		kart.in_drift = false
		kart.in_item = false
		kart.in_item_forward = false
		kart.in_throttle = 1.0 if (_start_tap_at > 0.0 and clock >= _start_tap_at) else 0.0
		kart.in_tap = _start_tap_at > 0.0 and clock >= _start_tap_at and clock - delta < _start_tap_at
		return

	# ---------- steering ----------
	var look := clampf(0.8 * sp, 12.0, 28.0)    # A5: 0.8 s of travel (was 8-15 m)
	if kart.cloud_time > 0.0:
		look *= 0.5        # I8: blinded by ink - shorter look-ahead
	var ahead := _min_radius(track, s, look + 10.0)
	var lane := lane_offset
	var lane_rate := 3.0
	if ahead.x < 45.0:
		var inside := ahead.y * -(1.2 + 2.2 * aggression)   # right turn (-1) -> +lateral (right)
		lane = lerpf(lane * 0.4, inside, clampf((45.0 - ahead.x) / 25.0, 0.0, 1.0))
	elif kart.items.size() < Kart.MAX_ITEMS and kart.race != null and kart.race.get("track_builder") != null:
		# I1 follow-up: boxes no longer cover the road, so aim for one (most of the time)
		var bl: float = kart.race.track_builder.box_lateral_ahead(s + 6.0, s + 55.0, kart.lateral)
		if not is_nan(bl):
			if absf(_box_row_s - s) > 60.0:
				_box_row_s = s
				_box_go = _rng.randf() < 0.7 + 0.25 * aggression
			if _box_go:
				lane = bl
				lane_rate = 7.0       # committing to a box needs a quicker line change
				look = minf(look, 13.0)   # and tighter tracking to hit a 1.35 m reach
	_lane_s = move_toward(_lane_s, lane, lane_rate * delta)    # A4/A5: lane changes at <= 3 m/s
	lane = _lane_s
	var target := track.position_at(s + look) + track.right_at(s + look) * lane
	var to := target - kart.global_position
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - kart.facing_yaw, -PI, PI)
	# A5: pure pursuit - the yaw rate that arcs onto the look-ahead point,
	# divided by the kart's max yaw rate at this speed - plus a damping term on
	# a wall push that grows with distance. (A lateral-rate damping term was
	# tried and tripled the steering jitter - kart.lateral is too noisy.)
	var dist := maxf(to.length(), 4.0)
	var yaw_rate_need := 2.0 * maxf(sp, 4.0) * sin(diff) / dist
	var frac := clampf(sp / kart.config.max_speed, 0.0, 1.0)
	var max_rate := lerpf(kart.config.turn_rate_low, kart.config.turn_rate_high, frac) * clampf(sp / 4.0, 0.25, 1.0)
	var steer := clampf(-yaw_rate_need / maxf(max_rate, 0.3), -1.0, 1.0)
	var half := track.road_width * 0.5
	var wall_k := smoothstep(half - 2.4, half - 0.6, absf(kart.lateral))
	steer = clampf(steer - signf(kart.lateral) * 0.5 * wall_k, -1.0, 1.0)

	# ---------- mistakes (A3) ----------
	_mistake_check -= delta
	if _mistake_check <= 0.0:
		_mistake_check = 5.0
		roll_mistake()
	var mistake_throttle := 1.0
	if _mistake_timer > 0.0:
		_mistake_timer -= delta
		match _mistake_kind:
			0:   # wobble: both directions now (old code only ever pulled left)
				steer = clampf(steer + _mistake_steer, -1.0, 1.0)
			1:   # late turn-in: keeps the lagging steer
				steer = _delayed_steer
			2:   # over-drift: steers too hard, may scrape the wall
				steer = clampf(steer * 1.6 + signf(steer) * 0.25, -1.0, 1.0)
			3:   # lifts off the throttle
				mistake_throttle = 0.35
	_delayed_steer = lerpf(_delayed_steer, steer, 1.0 - exp(-4.0 * delta))
	if kart.cloud_time > 0.0:
		steer = clampf(steer + sin(clock * 5.0) * 0.5, -1.0, 1.0)   # I8: was 0.3

	# ---------- drift into tight corners ----------
	_drift_cooldown = maxf(0.0, _drift_cooldown - delta)
	var lead := sp * (0.2 + 0.15 * aggression) + 4.0
	var probe := _min_radius(track, s + lead, 8.0)
	var here := _min_radius(track, s, 6.0)
	var throttle := 1.0
	if not kart.drifting:
		if probe.x < drift_radius and sp > kart.config.drift_min_speed + 1.0 and _drift_cooldown <= 0.0 and kart.grounded:
			_want_drift = true
			steer = -probe.y * maxf(absf(steer), 0.7)
		elif here.x >= drift_radius:
			_want_drift = false
	else:
		if here.x >= drift_radius and probe.x >= drift_radius:
			_want_drift = false
			_drift_cooldown = 0.6
			if kart.drift_charged():
				stat_drifts += 1
				var plan := plan_exit_taps()
				_tap_in = plan.x           # < 0: missed the mini boost
				_double_pending = plan.y > 0.5
				# K4: skilled drivers land the perfect 0.15-0.30 s double more often
				_double_at = _rng.randf_range(0.16, 0.28) if _rng.randf() < skill else _rng.randf_range(0.31, 0.5)
	# brake a little if a corner is too tight even for a drift
	if probe.x < 16.0 and sp > 24.0 and not kart.is_boosting():
		throttle = 0.6
	throttle *= mistake_throttle

	# ---------- throttle taps (mini / double / air / landing boosts) ----------
	var tap := false
	if _tap_in >= 0.0:
		_tap_in -= delta
		if _tap_in < 0.0:
			tap = true
	if _double_pending and kart.double_window > 0.0 and kart.double_elapsed >= _double_at and _tap_in < 0.0 and not tap:
		tap = true
		_double_pending = false
	# air / landing boosts: success = skill * 0.8, decided once per jump (A1)
	if not kart.grounded:
		if not _air_roll_done:
			_air_roll_done = true
			_air_go = _rng.randf() < skill * 0.8
			_land_go = _rng.randf() < skill * 0.8
		if _air_go and kart.air_boost_ready and kart.air_time >= kart.config.air_boost_min_air:
			tap = true
	elif kart.landing_window <= 0.0:
		_air_roll_done = false
	if _land_go and kart.landing_window > 0.0 and kart.landing_window < kart.config.landing_window_time - 0.06:
		tap = true

	kart.in_steer = steer
	stat_steer_jitter += absf(steer - _prev_out_steer)
	_prev_out_steer = steer
	stat_ticks += 1
	kart.in_throttle = throttle
	kart.in_drift = _want_drift and (kart.drifting or probe.x < drift_radius)
	kart.in_tap = tap
	if manual_items:
		var pressed := Input.is_action_pressed("use_item")
		kart.in_item = pressed and not _prev_item_input
		_prev_item_input = pressed
	else:
		_aim_fwd = false
		kart.in_item = _decide_item(delta, ahead.x)
		kart.in_item_forward = kart.in_item and _aim_fwd
		if kart.in_item_forward:
			kart.in_item = false


# ---------- skill model (A1-A3), public for tests ----------
## Plan the taps after a charged drift. x = seconds until the mini-boost tap
## (-1 = fumbled), y = 1 when a double boost will be attempted. Reaction delay
## ~ N(0.12, 0.05); a tap later than the 0.35 s window simply misses.
func plan_exit_taps() -> Vector2:
	stat_mini_attempts += 1
	if _rng.randf() >= skill:
		return Vector2(-1.0, 0.0)
	stat_mini_planned += 1
	var delay := clampf(_rng.randfn(0.12, 0.05), 0.02, 0.6)
	var dbl := _rng.randf() < skill   # overall double rate = skill^2
	if dbl:
		stat_double_planned += 1
	return Vector2(delay, 1.0 if dbl else 0.0)


func shield_reaction_delay() -> float:
	return _rng.randf_range(0.25, 0.6)


func shield_chance() -> float:
	return 0.4 + 0.5 * defense


## Every 5 s: chance of a short mistake (0.15-0.3, weaker drivers more often).
func roll_mistake() -> bool:
	if _rng.randf() >= mistake_rate:
		return false
	stat_mistakes += 1
	_mistake_kind = _rng.randi_range(0, 3)
	_mistake_timer = _rng.randf_range(0.25, 0.6)
	_mistake_steer = _rng.randf_range(0.3, 0.7) * (1.0 if _rng.randf() < 0.5 else -1.0)
	return true


# ---------- item AI ----------
func _decide_item(delta: float, r_ahead: float) -> bool:
	if kart.items.is_empty():
		_item_delay = -1.0
		_item_hold = 0.0
		return false
	if _item_delay < 0.0:
		_item_delay = _rng.randf_range(0.3, 0.8)   # reaction delay
		return false
	if _item_delay > 0.0:
		_item_delay = maxf(0.0, _item_delay - delta)
		return false
	_item_hold += delta
	var rm = kart.race
	if rm == null or not rm.has_method("kart_ahead"):
		return false
	var item: int = kart.items[0]
	var ahead: Kart = rm.kart_ahead(kart)
	var behind: Kart = rm.kart_behind(kart)
	var gap_ahead: float = INF if ahead == null else ahead.progress - kart.progress
	var gap_behind: float = INF if behind == null else kart.progress - behind.progress
	var leading := kart.rank == 1
	var straight_ahead := _min_radius(kart.track, kart.progress, 45.0).x > 80.0
	var use := false
	match item:
		ItemDefs.NITRO:
			use = straight_ahead and kart.grounded
		ItemDefs.MISSILE:
			use = gap_ahead < 110.0
		ItemDefs.MAGNET:
			use = gap_ahead < 70.0 and gap_ahead > 5.0
		ItemDefs.UFO:
			use = not leading
		ItemDefs.LIGHTNING:
			use = kart.rank >= 3 or (not leading and _rng.randf() < 0.02)
		ItemDefs.BANANA when gap_ahead > 12.0 and gap_ahead < 30.0 and aggression > 0.5:
			use = true
			_aim_fwd = true        # I8: aggressive drivers lob it at the kart ahead
		ItemDefs.BANANA, ItemDefs.CLOUD:
			use = (gap_behind < 30.0 and (r_ahead < 45.0 or _rng.randf() < 0.02 + defense * 0.03))
		ItemDefs.SHIELD:
			# A2: human-like reaction — notice the threat, wait 0.25-0.6 s, then
			# raise the shield with probability 0.4 + 0.5 * defense
			var threatened: bool = rm.item_system != null and rm.item_system.is_threatened(kart)
			if threatened:
				if _shield_wait < 0.0:
					_shield_wait = shield_reaction_delay()
				else:
					_shield_wait -= delta
					if _shield_wait <= 0.0:
						use = _rng.randf() < shield_chance()
						_shield_wait = 99.0      # decided for this threat
			else:
				_shield_wait = -1.0
				use = leading and gap_behind < 25.0 and _rng.randf() < defense * 0.04
	# defensive drivers hold attack items longer, aggressive ones fire sooner
	if not use and _item_hold > 9.0 + 8.0 * defense:
		use = true
	if not use and kart.items.size() >= Kart.MAX_ITEMS and _item_hold > 5.0:
		use = true
	if use:
		_item_delay = -1.0
		_item_hold = 0.0
	return use
