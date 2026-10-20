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
@export var mistake_rate := 0.04   ## 0..0.1 chance every 5 s of a short mistake
@export var lane_offset := 0.0     ## -1.5..1.5 m
@export var is_rival := false
@export var drift_radius := 30.0
@export var manual_items := false  ## autopilot for the player: items come from Input
@export var start_boost_chance := 0.7

var kart: Kart
var _rng := RandomNumberGenerator.new()
var _mistake_timer := 0.0
var _mistake_steer := 0.0
var _mistake_check := 5.0
var _delayed_steer := 0.0
var _tap_in := -1.0           ## seconds until the next throttle tap
var _double_pending := false
var _item_delay := -1.0
var _item_hold := 0.0
var _drift_cooldown := 0.0
var _want_drift := false
var _start_tap_at := -1.0
var _prev_item_input := false
var stat_drifts := 0
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
		_start_tap_at = go_clock - _rng.randf_range(0.05, 0.4)
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
		kart.in_throttle = 1.0 if (_start_tap_at > 0.0 and clock >= _start_tap_at) else 0.0
		kart.in_tap = _start_tap_at > 0.0 and clock >= _start_tap_at and clock - delta < _start_tap_at
		return

	# ---------- steering ----------
	var look := lerpf(8.0, 15.0, clampf(sp / 25.0, 0.0, 1.0))
	var ahead := _min_radius(track, s, look + 10.0)
	var lane := lane_offset
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
	var target := track.position_at(s + look) + track.right_at(s + look) * lane
	var to := target - kart.global_position
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - kart.facing_yaw, -PI, PI)
	var steer := clampf(-diff * 2.4, -1.0, 1.0)
	var half := track.road_width * 0.5
	if absf(kart.lateral) > half - 1.4:
		steer = clampf(steer - signf(kart.lateral) * 0.45, -1.0, 1.0)

	# ---------- mistakes ----------
	_mistake_check -= delta
	if _mistake_check <= 0.0:
		_mistake_check = 5.0
		if _rng.randf() < mistake_rate:
			_mistake_timer = _rng.randf_range(0.2, 0.45)
			_mistake_steer = _rng.randf_range(-0.7, 0.7)
	if _mistake_timer > 0.0:
		_mistake_timer -= delta
		steer = _delayed_steer if _mistake_steer > 0.0 else clampf(steer + _mistake_steer, -1.0, 1.0)
	_delayed_steer = lerpf(_delayed_steer, steer, clampf(delta * 5.0, 0.0, 1.0))
	if kart.cloud_time > 0.0:
		steer = clampf(steer + sin(clock * 5.0) * 0.3, -1.0, 1.0)

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
				_tap_in = 0.1          # mini boost 0.1 s after releasing
				_double_pending = true
				stat_drifts += 1
	# brake a little if a corner is too tight even for a drift
	if probe.x < 16.0 and sp > 24.0 and not kart.is_boosting():
		throttle = 0.6

	# ---------- throttle taps (mini / double / air / landing boosts) ----------
	var tap := false
	if _tap_in >= 0.0:
		_tap_in -= delta
		if _tap_in < 0.0:
			tap = true
			if _double_pending and kart.mini_window <= 0.0:
				pass
	if _double_pending and kart.double_window > 0.0 and kart.double_delay <= 0.0 and _tap_in < 0.0 and not tap:
		tap = true
		_double_pending = false
	if not kart.grounded and kart.air_boost_ready and kart.air_time >= kart.config.air_boost_min_air:
		tap = true
	if kart.landing_window > 0.0 and kart.landing_window < kart.config.tap_window - 0.06:
		tap = true

	kart.in_steer = steer
	kart.in_throttle = throttle
	kart.in_drift = _want_drift and (kart.drifting or probe.x < drift_radius)
	kart.in_tap = tap
	if manual_items:
		var pressed := Input.is_action_pressed("use_item")
		kart.in_item = pressed and not _prev_item_input
		_prev_item_input = pressed
	else:
		kart.in_item = _decide_item(delta, ahead.x)


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
		ItemDefs.BANANA, ItemDefs.CLOUD:
			use = (gap_behind < 30.0 and (r_ahead < 45.0 or _rng.randf() < 0.02 + defense * 0.03))
		ItemDefs.SHIELD:
			var threatened: bool = rm.item_system != null and rm.item_system.is_threatened(kart)
			use = threatened or (leading and gap_behind < 25.0 and _rng.randf() < defense * 0.04)
	# defensive drivers hold attack items longer, aggressive ones fire sooner
	if not use and _item_hold > 9.0 + 8.0 * defense:
		use = true
	if not use and kart.items.size() >= Kart.MAX_ITEMS and _item_hold > 5.0:
		use = true
	if use:
		_item_delay = -1.0
		_item_hold = 0.0
	return use
