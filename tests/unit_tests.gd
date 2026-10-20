extends Node
## Targeted checks for the review fixes (opus_review.md issue IDs).
##   godot --headless --path . --fixed-fps 60 res://tests/unit_tests.tscn -- --test
## Each t_* method returns {"pass": bool, ...details}. Runs inside a live race.

const RACE := "res://scenes/race/race.tscn"

var race: Node
var rm: RaceManager
var results := []


func _ready() -> void:
	race = load(RACE).instantiate()
	add_child(race)
	rm = race.get_node("RaceManager")
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await _frames(int(seconds * 60.0))


func _run() -> void:
	while rm.player == null:
		await _frames(1)
	var names: Array[String] = []
	for m in get_method_list():
		if str(m.name).begins_with("t_"):
			names.append(str(m.name))
	names.sort()
	for n in names:
		var r: Dictionary = await call(n)
		var ok: bool = r.get("pass", false)
		r.erase("pass")
		results.append({"test": n, "pass": ok, "detail": r})
		print(("PASS " if ok else "FAIL ") + n + "  " + JSON.stringify(r))
	var all_ok: bool = results.all(func(x): return x.pass)
	var f := FileAccess.open("res://tests/unit_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"all_pass": all_ok, "results": results}, "  "))
	f.close()
	print("UNIT ALL PASS" if all_ok else "UNIT SOME FAILED")
	get_tree().quit(0 if all_ok else 1)


## helpers ------------------------------------------------------------------
func _until_racing() -> void:
	while rm.state != RaceManager.State.RACING:
		await _frames(1)


func _ai(i: int) -> Kart:
	return rm.karts[i]


## Put a kart on the centre line at offset s, moving at `spd`, with its AI parked.
func _stage(k: Kart, s: float, spd: float, lat := 0.0) -> void:
	rm.teleport(k, s, lat)
	k.speed = spd
	k.velocity = k.move_dir() * spd


# ---------------------------------------------------------------------------
# tests (alphabetical order = run order)
# ---------------------------------------------------------------------------
func _keycodes(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append((ev as InputEventKey).physical_keycode)
	return out


## Web bug: Ctrl+W closes the tab. The project map must have no Ctrl at all,
## and the web platform setup must not add it back.
func t_a_input_map_has_no_ctrl() -> Dictionary:
	var proj_ctrl := []
	for prop in ProjectSettings.get_property_list():
		var pname := str(prop.name)
		if not pname.begins_with("input/") or pname.begins_with("input/ui_"):
			continue
		var v: Dictionary = ProjectSettings.get_setting(pname)
		for ev in v.get("events", []):
			if ev is InputEventKey and (ev.physical_keycode == KEY_CTRL or ev.keycode == KEY_CTRL or ev.ctrl_pressed):
				proj_ctrl.append(pname)
	GameConfig.apply_platform_input(true)
	var web_ctrl := []
	for a in InputMap.get_actions():
		if not str(a).begins_with("ui_") and KEY_CTRL in _keycodes(a):
			web_ctrl.append(a)
	var item_keys := _keycodes("use_item")
	var drift_keys := _keycodes("drift")
	GameConfig.apply_platform_input(OS.has_feature("web"))
	return {"pass": proj_ctrl.is_empty() and web_ctrl.is_empty() and KEY_SPACE in item_keys and KEY_E in item_keys
			and drift_keys.size() >= 2,
			"project_ctrl_actions": proj_ctrl, "web_ctrl_actions": web_ctrl,
			"web_item_keys": item_keys.map(func(k): return OS.get_keycode_string(k)),
			"drift_keys": drift_keys.map(func(k): return OS.get_keycode_string(k))}


## C1/C2: physics interpolation on, camera reads the kart's interpolated transform
## in _process and damps heading (a 1.2 rad instant kart yaw change must not
## jump the view; it converges within ~1 s).
func t_b_camera_interpolated_and_heading_damped() -> Dictionary:
	var cam: ChaseCamera = race.get_node("ChaseCamera")
	var p := rm.player
	await _wait(1.0)   # kart settled on the grid
	var interp_ok := cam.target_origin.distance_to(p.get_global_transform_interpolated().origin) < 0.02
	var cam_yaw := func() -> float:
		var f := -cam.global_basis.z
		return atan2(-f.x, -f.z)
	var y0: float = cam_yaw.call()
	var saved := [p.facing_yaw, p.move_yaw]
	p.facing_yaw = wrapf(p.facing_yaw + 1.2, -PI, PI)
	p.move_yaw = p.facing_yaw
	await get_tree().process_frame
	await get_tree().process_frame
	var step1 := absf(wrapf(cam_yaw.call() - y0, -PI, PI))
	await _wait(1.0)
	var after1s := absf(wrapf(cam_yaw.call() - y0, -PI, PI))
	p.facing_yaw = saved[0]
	p.move_yaw = saved[1]
	await _wait(1.0)
	return {"pass": ProjectSettings.get_setting("physics/common/physics_interpolation") and interp_ok
			and cam.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and step1 < 0.3 and absf(after1s - 1.2) < 0.08,
			"interpolation_setting": ProjectSettings.get_setting("physics/common/physics_interpolation"),
			"camera_uses_interpolated_origin": interp_ok, "yaw_change_first_frames_rad": snappedf(step1, 0.001),
			"yaw_change_after_1s_rad": snappedf(after1s, 0.001), "kart_yaw_step_rad": 1.2}


## T8 / W1: fog does not paint the sky; one renderer everywhere.
func t_c_environment_fog_and_renderer() -> Dictionary:
	var we: WorldEnvironment = race.find_child("WorldEnvironment*", true, false)
	if we == null:
		for n in race.find_children("*", "WorldEnvironment", true, false):
			we = n
	var env := we.environment
	var sun: DirectionalLight3D = race.find_child("Sun", true, false)
	return {"pass": env.fog_sky_affect <= 0.2 and env.fog_density <= 0.0008 and sun.rotation_degrees.x > -40.0
			and str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "gl_compatibility",
			"fog_sky_affect": env.fog_sky_affect, "fog_density": env.fog_density, "sun_pitch_deg": snappedf(sun.rotation_degrees.x, 0.1),
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method")}


## W3/C4/C5: kart signals are wired to sound + camera; magnet refresh doesn't spam.
func t_d_feedback_wired() -> Dictionary:
	var fb: FeedbackDirector = race.get_node("Feedback")
	var cam: ChaseCamera = race.get_node("ChaseCamera")
	var p := rm.player
	var conns := {}
	for sig in ["wall_hit", "boosted", "hit_taken", "items_changed", "landed", "shield_blocked"]:
		conns[sig] = p.get_signal_connection_list(sig).size()
	var it: ItemSystem = race.get_node("ItemSystem")
	conns["item_used"] = it.get_signal_connection_list("item_used").size()
	cam.trauma = 0.0
	p.wall_hit.emit(p, 0.8)
	var trauma := cam.trauma
	var wall_sfx: bool = fb.played.back() == "wall"
	cam.fov_kick = 0.0
	p.add_boost("mini", 7.5, 0.5)
	var kick := cam.fov_kick
	var mini_sfx: bool = fb.played.back() == "mini"
	var count := [0]
	var cb := func(_k, kind): if kind == "magnet": count[0] += 1
	p.boosted.connect(cb)
	for i in 30:
		p.add_boost("magnet", 8.0, 0.15, 0.0)
		await _frames(1)
	p.boosted.disconnect(cb)
	p.boosts.clear()
	var sounds := fb.streams.size()
	var all_wired: bool = conns.values().all(func(v): return v > 0)
	return {"pass": all_wired and trauma >= 0.19 and wall_sfx and kick >= 3.9 and mini_sfx and count[0] == 1 and sounds >= 10,
			"connections": conns, "trauma_after_wall_hit_0.8": snappedf(trauma, 0.01), "fov_kick_after_mini": snappedf(kick, 0.01),
			"magnet_boosted_signals_over_30_ticks": count[0], "sfx_loaded": sounds}


## K12: a banana hit leaves ~45% of the entry speed (not a dead stop), and the
## kart is invulnerable for 1.2 s after recovering.
func t_e_hit_retains_speed_and_invuln() -> Dictionary:
	await _until_racing()
	var k := _ai(3)
	while k.speed < 24.0:
		await _frames(1)
	k.shield_time = 0.0
	k.invuln_time = 0.0
	var entry := k.speed
	var ok_hit := k.hit("banana", 0.9, true)
	var low := entry
	while k.stun_time > 0.0:
		low = minf(low, k.speed)
		await _frames(1)
	var retained := low / entry
	var second := k.hit("missile", 1.4, true)      # right after recovery: blocked
	var inv := k.invuln_time
	await _wait(1.3)
	k.shield_time = 0.0
	var third := k.hit("banana", 0.01, true)        # after invuln: lands again
	return {"pass": ok_hit and absf(retained - 0.45) < 0.06 and not second and inv > 1.0 and third,
			"entry_speed": snappedf(entry, 0.1), "lowest_speed_in_stun": snappedf(low, 0.1), "retained_ratio": snappedf(retained, 0.01),
			"hit_during_invuln_landed": second, "invuln_left": snappedf(inv, 0.01), "hit_after_invuln_landed": third}


## I4: slowdowns take the max instead of adding up.
func t_f_slows_use_max() -> Dictionary:
	var k := _ai(4)
	k.slows.clear()
	k.add_slow("lightning", 8.0, 3.0)
	k.add_slow("ufo", 9.0, 4.0)
	k.add_slow("magnet", 3.0, 1.0)
	var amt := k.slow_amount()
	k.slows.clear()
	return {"pass": is_equal_approx(amt, 9.0), "slow_amount_with_8_9_3": amt}


## I1: item box rows no longer cover the whole road. A kart triggers a box when
## its centre is within trigger radius + kart half-width; every row must leave a
## lane (>= 0.5 m of centre positions) that misses, and boxes must be avoidable.
func t_g_item_boxes_not_guaranteed() -> Dictionary:
	var tb: TrackBuilder = race.get_node("SandsTrack")
	var reach := TrackBuilder.ITEM_TRIGGER_RADIUS + _kart_half_width()
	var rows := {}
	for laterals in [TrackBuilder.ITEM_ROW_A, TrackBuilder.ITEM_ROW_B]:
		var covered := 0
		var n := 0
		var gap := 0.0
		var best_gap := 0.0
		var x := -5.4
		while x <= 5.4:
			n += 1
			var hit := false
			for b in laterals:
				if absf(x - b) <= reach:
					hit = true
			if hit:
				covered += 1
				gap = 0.0
			else:
				gap += 0.05
				best_gap = maxf(best_gap, gap)
			x += 0.05
		rows[str(laterals)] = {"coverage": snappedf(float(covered) / n, 0.01), "widest_miss_lane_m": snappedf(best_gap, 0.01)}
	var ok := TrackBuilder.ITEM_TRIGGER_RADIUS <= 0.8
	for r in rows.values():
		ok = ok and r.widest_miss_lane_m >= 0.5 and r.coverage < 0.95
	return {"pass": ok, "rows": rows, "reach_m": snappedf(reach, 0.01), "boxes": tb.item_box_nodes.size(),
			"old_layout": "5 boxes, r=1.25 -> 100% coverage"}


func _kart_half_width() -> float:
	var side := rm.player.get_node_or_null("SideShape") as CollisionShape3D
	if side and side.shape is CapsuleShape3D:
		return (side.shape as CapsuleShape3D).height * 0.5
	var cs: CollisionShape3D = rm.player.get_node("CollisionShape3D")
	if cs.shape is BoxShape3D:
		return (cs.shape as BoxShape3D).size.x * 0.5
	if cs.shape is CapsuleShape3D:
		return (cs.shape as CapsuleShape3D).radius
	return 0.8


## I2: a kart with full slots passes through a box without consuming it.
func t_h_full_slots_keep_box() -> Dictionary:
	var tb: TrackBuilder = race.get_node("SandsTrack")
	var k := _ai(5)
	var holder: Node3D = null
	for h in tb.item_box_nodes:
		if h.get_meta("active", false):
			holder = h
			break
	var saved := k.items.duplicate()
	k.items.assign([ItemDefs.NITRO, ItemDefs.BANANA])
	tb._on_item_box_body(k, holder)
	var still_active: bool = holder.get_meta("active", false)
	k.items.clear()
	tb._on_item_box_body(k, holder)
	var consumed_when_room: bool = not holder.get_meta("active", true)
	k.items.assign(saved)
	return {"pass": still_active and consumed_when_room, "full_slots_box_still_active": still_active,
			"consumed_with_free_slot": consumed_when_room}


## I3: the leader never rolls a missile / magnet (nobody ahead to hit).
func t_i_rank1_no_missile_magnet() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var table: ItemTable = RaceManager.ITEM_TABLE
	var bad := 0
	var rank2_attack := 0
	for i in 5000:
		var it := table.roll(1, 6, 0.0, rng)
		if it == ItemDefs.MISSILE or it == ItemDefs.MAGNET:
			bad += 1
		var it2 := table.roll(2, 6, 10.0, rng)
		if it2 == ItemDefs.MISSILE or it2 == ItemDefs.MAGNET:
			rank2_attack += 1
	return {"pass": bad == 0 and rank2_attack > 0, "rank1_missile_or_magnet_of_5000": bad, "rank2_missile_or_magnet_of_5000": rank2_attack}


## K6: leaving a drift the slip angle decays smoothly (grip ramps up over 0.3 s)
## and the nose swings back ~40% of the way instead of the path snapping to it.
func t_j_drift_exit_grip_ramp() -> Dictionary:
	await _until_racing()
	var p := rm.player
	var ctrl := p.controller
	p.controller = null
	_stage(p, 60.0, 24.0)
	await _frames(2)
	p.in_drift = true
	p.in_steer = 0.0
	p.drifting = true
	p.drift_dir = 1
	p.move_yaw = wrapf(p.facing_yaw + 0.5, -PI, PI)   # 0.5 rad slip
	var face0 := p.facing_yaw
	p.in_drift = false                                # release -> drift ends this tick
	await _frames(1)
	var s0 := absf(wrapf(p.facing_yaw - p.move_yaw, -PI, PI))
	await _frames(3)   # 0.05 s
	var s_005 := absf(wrapf(p.facing_yaw - p.move_yaw, -PI, PI))
	await _wait(0.5)
	var s_05 := absf(wrapf(p.facing_yaw - p.move_yaw, -PI, PI))
	var face_swing := absf(wrapf(p.facing_yaw - face0, -PI, PI))
	p.controller = ctrl
	var old_model := 0.5 * exp(-10.0 * (4.0 / 60.0))   # old: grip 10 right away
	return {"pass": not p.drifting and s_005 > 0.85 * s0 and s_005 > old_model + 0.05 and s_05 < 0.06 and face_swing > 0.12,
			"slip_after_release": snappedf(s0, 0.001), "slip_after_0.05s": snappedf(s_005, 0.001),
			"old_model_slip_after_0.05s": snappedf(old_model, 0.001), "slip_after_0.55s": snappedf(s_05, 0.001),
			"nose_swing_back_rad": snappedf(face_swing, 0.001)}


## K9: one wall contact = one resolution: loss 0.12+0.43*impact^2, a single
## wall_hit event per 0.15 s, nose turned only 25% towards the wall.
func t_k_wall_hit_single_resolution() -> Dictionary:
	await _until_racing()
	var p := rm.player
	var ctrl := p.controller
	p.controller = null
	var out := {}
	for angle in [0.35, 1.2]:
		_stage(p, 50.0, 25.0, 3.0)
		var yaw: float = p.facing_yaw - angle            # turn right, into the right wall
		p.facing_yaw = yaw
		p.move_yaw = yaw
		var hits: Array = []
		var cb := func(_k, imp): hits.append([rm.race_clock, imp])
		p.wall_hit.connect(cb)
		var prev_speed := p.speed
		var before := 0.0
		var after := 0.0
		for i in 120:
			prev_speed = p.speed
			await _frames(1)
			if hits.size() == 1 and before == 0.0:
				before = prev_speed
				after = p.speed
			if hits.size() > 0 and rm.race_clock - hits[0][0] > 0.15:
				break
		p.wall_hit.disconnect(cb)
		var imp: float = hits[0][1] if hits.size() > 0 else 0.0
		var expected: float = 0.12 + 0.43 * imp * imp
		var loss: float = 1.0 - after / maxf(before, 0.01)
		out["angle_%.2f" % angle] = {"impact": snappedf(imp, 0.01), "speed_before": snappedf(before, 0.1), "speed_after": snappedf(after, 0.1),
				"loss": snappedf(loss, 0.01), "expected_loss": snappedf(expected, 0.01), "wall_hit_events_in_0.15s": hits.size()}
	p.controller = ctrl
	var ok := true
	for k in out:
		var r: Dictionary = out[k]
		ok = ok and int(r["wall_hit_events_in_0.15s"]) == 1 and absf(float(r.loss) - float(r.expected_loss)) < 0.04
	out["pass"] = ok
	return out


## A1: mini boost success ~ skill, double ~ skill^2, tap delay ~ N(0.12, 0.05);
## A2: shield reaction 0.25-0.6 s, chance 0.4+0.5*defense;
## A3: mistakes ~ mistake_rate per 5 s check, both steering directions.
func t_l_ai_skill_model() -> Dictionary:
	var ai := AIDriver.new()
	ai.setup(1234)
	ai.skill = 0.7
	ai.defense = 0.5
	ai.mistake_rate = 0.25
	var n := 4000
	var mini := 0
	var dbl := 0
	var delays := []
	for i in n:
		var p := ai.plan_exit_taps()
		if p.x >= 0.0:
			mini += 1
			delays.append(p.x)
		if p.y > 0.5:
			dbl += 1
	var mean := 0.0
	for d in delays:
		mean += d
	mean /= maxf(1.0, delays.size())
	var late := delays.filter(func(d): return d > 0.35).size()
	var rmin := 9.0
	var rmax := 0.0
	for i in 500:
		var r := ai.shield_reaction_delay()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	var mistakes := 0
	var left := 0
	var right := 0
	for i in n:
		if ai.roll_mistake():
			mistakes += 1
			if ai._mistake_kind == 0:
				if ai._mistake_steer < 0.0: left += 1
				else: right += 1
	var chance := ai.shield_chance()
	ai.free()
	var roster_skills := []
	for k in rm.karts:
		var d := k.get_node_or_null("AIDriver") as AIDriver
		if d and not k.is_player:
			roster_skills.append(d.skill)
	var mini_rate := float(mini) / n
	var dbl_rate := float(dbl) / n
	var m_rate := float(mistakes) / n
	return {"pass": absf(mini_rate - 0.7) < 0.03 and absf(dbl_rate - 0.49) < 0.03 and absf(mean - 0.12) < 0.01
			and rmin >= 0.25 and rmax <= 0.6 and absf(chance - 0.65) < 0.001 and absf(m_rate - 0.25) < 0.03
			and left > 50 and right > 50 and roster_skills.size() == 5 and roster_skills.min() >= 0.55 and roster_skills.max() <= 0.9,
			"skill": 0.7, "mini_success_rate": snappedf(mini_rate, 0.001), "double_rate": snappedf(dbl_rate, 0.001),
			"tap_delay_mean_s": snappedf(mean, 0.001), "taps_too_late_pct": snappedf(100.0 * late / maxf(1, delays.size()), 0.1),
			"shield_delay_range_s": [snappedf(rmin, 0.01), snappedf(rmax, 0.01)], "shield_chance_def0.5": 0.65,
			"mistake_rate_per_check": snappedf(m_rate, 0.001), "steer_mistakes_left_right": [left, right], "roster_skills": roster_skills}


## Landing boost (落地喷): every kicker gives 0.6-1.0 s of air at race speeds;
## touchdown opens a 0.3 s window (+ding); a W tap in it gives +3 m/s for 1.5 s;
## not tapping gives nothing.
func t_m_landing_boost() -> Dictionary:
	await _until_racing()
	var p := rm.player
	var fb: FeedbackDirector = race.get_node("Feedback")
	var ctrl := p.controller
	var pin := PlayerInput.new()
	pin.kart = p
	p.controller = pin
	Input.action_press("accelerate")
	var airs := []
	var windows := []
	var fired := []
	var bonus := 0.0
	var dur := 0.0
	var ding := false
	var no_tap_boost := false
	var idx := 0
	for r in rm.track.ramps:
		for tap in [true, false]:
			_stage(p, r - 40.0, 26.0)
			p.boosts.clear()
			await _frames(2)
			var base := p.stat_landing_boosts
			var t_air := 0.0
			var t_win := 0
			var tapped := false
			for i in 240:
				await _frames(1)
				if not p.grounded:
					t_air = maxf(t_air, p.air_time)
				if p.landing_window > 0.0:
					t_win += 1
					if not ding:
						ding = fb.played.has("ding")
					if tap and not tapped and t_win == 3:   # 0.05 s after touchdown
						Input.action_release("accelerate")
						await _frames(1)
						Input.action_press("accelerate")
						tapped = true
				if tapped and p.boosts.has("landing") and bonus == 0.0:
					bonus = p.boosts["landing"].x
					dur = p.boosts["landing"].y
				if t_air > 0.0 and p.grounded and p.landing_window <= 0.0 and (tapped or t_win > 0) and i > 120:
					break
			if tap:
				airs.append(snappedf(t_air, 0.01))
				fired.append(p.stat_landing_boosts > base)
			else:
				windows.append(t_win)
				no_tap_boost = no_tap_boost or p.stat_landing_boosts > base
			idx += 1
	Input.action_release("accelerate")
	p.controller = ctrl
	pin.free()
	var air_ok: bool = airs.all(func(a): return a >= 0.6 and a <= 1.0)
	var win_ok: bool = windows.all(func(w): return w >= 16 and w <= 20)
	return {"pass": air_ok and win_ok and fired.all(func(f): return f) and not no_tap_boost and is_equal_approx(bonus, 3.0) and dur >= 1.4 and ding,
			"air_time_per_ramp_s": airs, "window_frames_no_tap": windows, "boost_fired_per_ramp": fired,
			"boost_bonus_mps": bonus, "boost_time_s": snappedf(dur, 0.01), "ding_played": ding, "boost_without_tap": no_tap_boost}


func _effects(cls_name: String) -> Array:
	var out := []
	for c in rm.item_system.get_children():
		if c is ItemEffect and c.get_script().resource_path.get_file().begins_with(cls_name):
			out.append(c)
	return out


func _clear_items() -> void:
	for c in rm.item_system.get_children():
		c.queue_free()
	for k in rm.karts:
		k.stun_time = 0.0; k.invuln_time = 0.0; k.shield_time = 0.0; k.cloud_time = 0.0
		k.slows.clear(); k.boosts.clear(); k.items.clear()
	await _frames(2)


## I5-I9 / H3 / H1: every item has a use sound and readable effects; hits play
## a kind-specific reaction; materials are cached (no new shader per use).
func t_n_item_presentation() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var fb: FeedbackDirector = race.get_node("Feedback")
	var hud: HudController = race.get_node("HUD")
	var p := rm.player
	var ai := _ai(1)
	var out := {}
	# --- missile: player -> AI ahead
	_stage(p, 900.0, 20.0)
	_stage(ai, 925.0, 18.0)
	await _frames(20)
	var exploded := [0]
	var cb := func(_pos): exploded[0] += 1
	rm.item_system.exploded.connect(cb)
	rm.item_system.use_item(p, ItemDefs.MISSILE)
	await _frames(3)
	var ms := _effects("missile")
	out["missile_trail"] = not ms.is_empty() and ms[0].trail_puffs > 0
	out["missile_lock_distance_m"] = snappedf(rm.item_system.incoming_missile(ai), 0.1)
	out["missile_use_sound"] = fb.played.has("launch")
	var tumble := 0.0
	for i in 120:
		await _frames(1)
		var kv := ai.get_node("Visual") as KartVisual
		if kv and kv.react_kind == "missile":
			tumble = maxf(tumble, absf(kv.model.rotation.x))
	out["missile_exploded"] = exploded[0]
	out["missile_tumble_max_rad"] = snappedf(tumble, 0.01)
	rm.item_system.exploded.disconnect(cb)
	await _clear_items()
	var mats_after_first := FxLib._mats.size()
	rm.item_system.use_item(p, ItemDefs.MISSILE)
	await _frames(30)
	out["new_materials_on_2nd_missile"] = FxLib._mats.size() - mats_after_first
	await _clear_items()
	# --- banana: AI drops, player drives into it
	_stage(p, 1650.0, 18.0)
	_stage(ai, 1662.0, 16.0)
	var ai_ctrl := ai.controller
	ai.controller = null
	ai.in_throttle = 0.6
	await _frames(10)
	rm.item_system.use_item(ai, ItemDefs.BANANA)
	await _frames(1)
	var bn := _effects("banana")
	out["banana_peel_parts"] = bn[0].peel.find_children("*", "MeshInstance3D", true, false).size() if not bn.is_empty() else 0
	out["banana_use_sound"] = fb.played.has("toss")
	var spin := 0.0
	for i in 150:
		await _frames(1)
		var kv := p.get_node("Visual") as KartVisual
		if kv and kv.react_kind == "banana":
			spin = maxf(spin, absf(kv.model.rotation.y))
	out["banana_spin_max_rad"] = snappedf(spin, 0.01)
	await _clear_items()
	# --- lightning: flash only when the player is struck
	var flashes := [0]
	var fcb := func(_c): flashes[0] += 1
	rm.item_system.screen_flash.connect(fcb)
	_stage(p, 2250.0, 20.0)
	_stage(ai, 2230.0, 20.0)
	await _frames(15)
	rm.item_system.use_item(p, ItemDefs.LIGHTNING)     # player strikes others
	await _frames(2)
	var lt := _effects("lightning")
	var boxes := 0
	out["flash_when_player_casts"] = flashes[0]
	await _clear_items()
	await _frames(20)
	rm.item_system.use_item(ai, ItemDefs.LIGHTNING)    # AI behind strikes the player
	await _frames(2)
	out["flash_when_player_struck"] = flashes[0]
	lt = _effects("lightning")
	if not lt.is_empty():
		for b in lt[0].bolts:
			if b.mesh is BoxMesh: boxes += 1
	out["lightning_bolts"] = lt[0].bolts.size() if not lt.is_empty() else 0
	out["lightning_box_meshes"] = boxes
	out["lightning_squash"] = (p.get_node("Visual") as KartVisual).react_kind == "lightning"
	rm.item_system.screen_flash.disconnect(fcb)
	await _clear_items()
	# --- shield: fresnel bubble, block shatters
	rm.item_system.use_item(p, ItemDefs.SHIELD)
	await _frames(15)
	var kvp := p.get_node("Visual") as KartVisual
	out["shield_shader"] = kvp.shield_bubble.material_override is ShaderMaterial and kvp.shield_bubble.visible
	p.hit("missile", 1.4, true)
	await _frames(2)
	out["shield_break_sound"] = fb.played.back() == "shatter" or fb.played.has("shatter")
	await _clear_items()
	# --- HUD icons + roulette
	p.items.clear()
	p.items_changed.emit(p)
	await _frames(2)
	p.give_item(ItemDefs.BANANA)
	await _frames(3)
	out["hud_icons_loaded"] = hud._icons.size()
	out["hud_roulette_running"] = hud.is_rolling()
	await _wait(0.8)
	out["hud_icon_after_roll"] = not p.items.is_empty() and not hud.is_rolling() and hud.slot_icons[0].texture == hud._icons.get(p.items[0])
	p.items.clear()
	ai.controller = ai_ctrl
	var ok: bool = out["missile_trail"] and out["missile_lock_distance_m"] < 60.0 and out["missile_use_sound"] \
			and out["missile_exploded"] >= 1 and out["missile_tumble_max_rad"] > 3.0 and out["new_materials_on_2nd_missile"] == 0 \
			and out["banana_peel_parts"] >= 10 and out["banana_use_sound"] and out["banana_spin_max_rad"] > 6.0 \
			and out["lightning_bolts"] >= 2 and out["lightning_box_meshes"] == 0 and out["flash_when_player_casts"] == 0 \
			and out["flash_when_player_struck"] == 1 and out["lightning_squash"] and out["shield_shader"] and out["shield_break_sound"] \
			and out["hud_icons_loaded"] == 8 and out["hud_roulette_running"] and out["hud_icon_after_roll"]
	out["pass"] = ok
	return out


func _count_sparks() -> int:
	var n := 0
	for c in race.get_children():
		if c is CPUParticles3D:
			n += 1
	return n


## K10 K11 C6 V1: wide collider; one bump resolution per pair with closing-speed
## impulse and 30% speed hand-off on rear-ends; sparks + sounds for wall hits,
## wall scraping and bumps; karts at the lens fade out.
func t_o_collision_presentation() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var fb: FeedbackDirector = race.get_node("Feedback")
	var p := rm.player
	var ai := _ai(1)
	var out := {}
	out["kart_half_width_m"] = _kart_half_width()
	# --- rear-end bump
	var ctrl := p.controller
	var ai_ctrl := ai.controller
	p.controller = null
	ai.controller = null
	p.in_throttle = 0.0
	ai.in_throttle = 0.0
	_stage(p, 60.0, 24.0, 0.0)
	_stage(ai, 63.2, 14.0, 0.0)
	var events := []
	var cb := func(k, o, st, _pt): events.append([Engine.get_physics_frames(), st])
	p.bumped.connect(cb)
	ai.bumped.connect(cb)
	var bumps0 := fb.bumps_seen
	var sp0 := _count_sparks()
	var before_p := 0.0
	var before_ai := 0.0
	var after_p := 0.0
	var after_ai := 0.0
	for i in 60:
		before_p = p.speed
		before_ai = ai.speed
		await _frames(1)
		if not events.is_empty():
			after_p = p.speed
			after_ai = ai.speed
			break
	await _frames(3)
	p.bumped.disconnect(cb)
	ai.bumped.disconnect(cb)
	out["bump_events_in_3_ticks"] = events.size()
	out["rear_end_speeds_before"] = [snappedf(before_p, 0.1), snappedf(before_ai, 0.1)]
	out["rear_end_speeds_after"] = [snappedf(after_p, 0.1), snappedf(after_ai, 0.1)]
	var expected_dv := (before_p - before_ai) * 0.3
	out["front_kart_gain"] = snappedf(after_ai - before_ai, 0.1)
	out["expected_gain_approx"] = snappedf(expected_dv, 0.1)
	out["bump_sound"] = fb.played.has("bump") and fb.bumps_seen > bumps0
	out["bump_sparks"] = _count_sparks() > sp0
	# --- wall hit + scrape
	_stage(ai, 300.0, 0.0, 0.0)
	_stage(p, 50.0, 25.0, 3.0)
	p.facing_yaw -= 0.5
	p.move_yaw = p.facing_yaw
	p.in_steer = 0.4     # keep pushing into the wall -> grind along it
	p.in_throttle = 1.0
	var sp1 := _count_sparks()
	var scraped := 0
	var wall_snd := false
	for i in 50:
		await _frames(1)
		if p.scraping:
			scraped += 1
		wall_snd = wall_snd or fb.played.has("wall")
	out["wall_sound"] = wall_snd
	out["wall_sparks"] = _count_sparks() > sp1
	out["scraping_ticks_of_50"] = scraped
	out["scrape_loop_playing"] = fb._scrape.playing
	p.in_steer = 0.0
	# --- C6: kart at the lens fades
	var cam: ChaseCamera = race.get_node("ChaseCamera")
	await _frames(5)
	ai.place(Transform3D(cam.global_basis, cam.global_position + -cam.global_basis.z * 1.8 + Vector3.DOWN * 0.6))
	await _frames(3)
	var kv := ai.get_node("Visual") as KartVisual
	out["near_camera_fade"] = snappedf(kv._cam_fade, 0.01)
	p.controller = ctrl
	ai.controller = ai_ctrl
	var ok: bool = out["kart_half_width_m"] >= 0.8 and out["bump_events_in_3_ticks"] == 1 \
			and absf(out["front_kart_gain"] - out["expected_gain_approx"]) < 1.2 and out["front_kart_gain"] > 1.0 \
			and out["bump_sound"] and out["bump_sparks"] and out["wall_sound"] and out["wall_sparks"] \
			and out["scraping_ticks_of_50"] >= 10 and out["near_camera_fade"] > 0.5
	out["pass"] = ok
	return out


## K4 K5 K13: mini-boost tiers, double-boost rating, tight start window; the
## font covers every CJK string the scripts use.
func t_p_boost_skill_timing() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var p := rm.player
	var ctrl := p.controller
	p.controller = null
	var out := {}
	# K5 tiers
	var tiers := []
	for dt in [0.5, 1.2, 2.0]:
		_stage(p, 60.0, 24.0)
		p.boosts.clear()
		p.drifting = true
		p.drift_dir = 1
		p.drift_time = dt
		p._end_drift(true)
		p.in_tap = true
		p._update_taps(0.016)
		tiers.append(snappedf(p.boosts.get("mini", Vector2.ZERO).x, 0.1))
	out["mini_bonus_by_drift_0.5_1.2_2.0s"] = tiers
	# K4 double rating
	var results := {}
	for when in [0.05, 0.2, 0.45]:
		p.boosts.clear()
		p.drifting = true; p.drift_dir = 1; p.drift_time = 0.5
		p._end_drift(true)
		p.in_tap = true
		p._update_taps(0.0)
		p.in_tap = false
		var t := 0.0
		while t < when:
			p._update_taps(1.0 / 60.0)
			t += 1.0 / 60.0
		var perfect0 := p.stat_perfect_doubles
		var doubles0 := p.stat_doubles
		p.in_tap = true
		p._update_taps(1.0 / 60.0)
		p.in_tap = false
		results["%.2f" % when] = "perfect" if p.stat_perfect_doubles > perfect0 else ("normal" if p.stat_doubles > doubles0 else "fail")
	out["double_at_s"] = results
	p.boosts.clear()
	p.controller = ctrl
	# K13 window (pure logic on a fresh kart state)
	var cfg := p.config
	var starts := {}
	for off in [-0.6, -0.3, 0.05, 0.2]:
		p.boosts.clear()
		p.start_jumped = false
		p.start_window = 0.0
		var go := 100.0
		p.last_tap_clock = -10.0
		if off < 0.0:
			p.last_tap_clock = go + off
			p.countdown_tap(go + off, go)
		p.in_throttle = 1.0
		p.on_race_go(go)
		if off > 0.0:
			# tap after GO
			p.start_window -= off
			if p.start_window > 0.0:
				p.in_tap = true
				p._update_taps(0.0)
				p.in_tap = false
		starts["%.2f" % off] = p.boosts.has("start")
	p.boosts.clear()
	p.start_jumped = false
	out["super_start_by_tap_offset_s"] = starts
	out["start_kick"] = cfg.super_start_kick
	# font coverage
	var font: FontFile = load("res://assets/fonts/NotoSansSC-Bold-subset.otf")
	var missing := ""
	for f in ["res://scripts/hud_controller.gd", "res://scripts/kart.gd", "res://scripts/items/ufo_item.gd", "res://scripts/title_screen.gd", "res://scripts/game_config.gd"]:
		for c in FileAccess.get_file_as_string(f):
			if c.unicode_at(0) > 0x2E80 and not font.has_char(c.unicode_at(0)) and not missing.contains(c):
				missing += c
	out["glyphs_missing"] = missing
	out["pass"] = tiers == [7.5, 9.0, 10.5] and results == {"0.05": "fail", "0.20": "perfect", "0.45": "normal"} \
			and starts == {"-0.60": false, "-0.30": true, "0.05": true, "0.20": false} and missing == ""
	return out


## I5 I6 I7: lightning 4 m/s x 2 s, UFO 5 m/s x 3 s and can be shaken off by
## boosting, missile turn rate capped at 2.2 rad/s.
func t_q_item_balance() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var p := rm.player
	var ai := _ai(1)
	var out := {}
	_stage(p, 900.0, 22.0)
	_stage(ai, 940.0, 20.0)
	await _frames(20)
	rm.item_system.use_item(p, ItemDefs.MISSILE)
	await _frames(1)
	var ms := _effects("missile")
	var max_turn := 0.0
	var prev: Vector3 = ms[0].dir
	for i in 90:
		await _frames(1)
		if not is_instance_valid(ms[0]) or ms[0].is_queued_for_deletion():
			break
		if ms[0].age > 0.25:
			max_turn = maxf(max_turn, prev.angle_to(ms[0].dir) * 60.0)
		prev = ms[0].dir
	out["missile_max_turn_rad_s"] = snappedf(max_turn, 0.01)
	out["missile_still_hits_straight"] = ai.stun_kind == "missile" and ai.stat_hits > 0
	await _clear_items()
	await _wait(1.3)
	# lightning slow
	_stage(ai, 980.0, 20.0)
	await _frames(10)
	ai.hit("lightning", 0.5, true, 4.0, 2.0)
	out["lightning_slow"] = ai.slows.get("lightning", Vector2.ZERO)
	await _clear_items()
	await _wait(1.3)
	# UFO: shake off by boosting
	_stage(p, 1100.0, 22.0)
	_stage(ai, 1120.0, 22.0)
	await _frames(20)
	var t0 := rm.race_clock
	rm.item_system.use_item(p, ItemDefs.UFO)
	var arrived_at := -1.0
	var gone_at := -1.0
	for i in 400:
		await _frames(1)
		var u := _effects("ufo")
		if u.is_empty():
			gone_at = rm.race_clock
			break
		if u[0].arrived and arrived_at < 0.0:
			arrived_at = rm.race_clock
			out["ufo_slow"] = 0.0
		if arrived_at > 0.0:
			var tk: Kart = u[0].target
			out["ufo_slow"] = maxf(float(out.get("ufo_slow", 0.0)), tk.slows.get("ufo", Vector2.ZERO).x)
			tk.add_boost("nitro", 6.0, 0.2, 0.0)       # the target boosts to shake it off
	out["ufo_hover_before_shake_off_s"] = snappedf(gone_at - arrived_at, 0.01)
	await _clear_items()
	out["pass"] = max_turn <= 2.3 and out["missile_still_hits_straight"] and out["lightning_slow"].x == 4.0 \
			and out.get("ufo_slow", 0.0) == 5.0 and out["ufo_hover_before_shake_off_s"] > 0.0 and out["ufo_hover_before_shake_off_s"] < 1.2
	return out


## I8: banana thrown forward (Q) lands ahead and hits the kart in front, never
## the thrower; a clouded AI drifts off its line more.
func t_r_banana_forward() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var p := rm.player
	var ai := _ai(2)
	var out := {}
	_stage(p, 1300.0, 22.0)
	_stage(ai, 1345.0, 3.0)
	var actrl := ai.controller
	ai.controller = null
	ai.in_throttle = 0.0
	for k in rm.karts:      # nobody else may drive over the peel
		if k != p and k != ai:
			_stage(k, 300.0 + rm.karts.find(k) * 8.0, 0.0)
	await _frames(10)
	var ctrl := p.controller
	p.controller = null
	p.in_throttle = 1.0
	var x0 := p.global_position
	p.items.clear()
	p.items.append(ItemDefs.BANANA)
	p.in_item_forward = true
	await _frames(1)
	p.in_item_forward = false
	await _frames(45)
	var b := _effects("banana")
	if not b.is_empty():
		out["landed_ahead_m"] = snappedf((b[0].global_position - x0).dot(p.forward_dir()), 0.1)
		out["ai_to_peel_m"] = snappedf(ai.global_position.distance_to(b[0].global_position), 0.1)
		out["ai_ahead_m"] = snappedf((ai.global_position - x0).dot(p.forward_dir()), 0.1)
		# drive the AI kart over the peel from just behind it
		var bs: float = float(rm.track.project(b[0].global_position, p.track_index, 60)["distance"])
		_stage(ai, bs - 6.0, 10.0)
	for i in 120:
		await _frames(1)
		ai.in_throttle = 1.0; ai.in_steer = 0.0
		p.in_throttle = -1.0
		if ai.stun_kind == "banana" or p.stun_kind == "banana":
			break
	out["ai_hit"] = ai.stun_kind == "banana"
	out["thrower_hit"] = p.stun_kind == "banana"
	ai.controller = actrl
	p.controller = ctrl
	await _clear_items()
	out["pass"] = out.get("landed_ahead_m", 0.0) > 15.0 and out["ai_hit"] and not out["thrower_hit"]
	return out


## K1: visual posture - roll into turns, brake dive, air pitch, landing spring,
## front-wheel steer.
func t_s_body_posture() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var p := rm.player
	var v := p.get_node("Visual") as KartVisual
	var ctrl := p.controller
	p.controller = null
	var out := {}
	_stage(p, 1000.0, 24.0)
	for i in 30:
		p.in_throttle = 1.0; p.in_steer = 1.0
		await _frames(1)
	out["roll_deg_right_turn"] = snappedf(rad_to_deg(v.body_roll), 0.1)
	out["front_wheel_yaw_deg"] = snappedf(rad_to_deg(v.wheels[0].rotation.y), 0.1)
	for i in 20:
		p.in_throttle = -1.0; p.in_steer = 0.0
		await _frames(1)
	out["brake_pitch_deg"] = snappedf(rad_to_deg(v.body_pitch), 0.1)
	# air: launch it upward
	_stage(p, 1100.0, 24.0)
	await _frames(5)
	p.in_throttle = 1.0
	p.velocity.y = 7.0
	p.grounded = false
	var max_up := 0.0
	var min_pitch := 0.0
	var min_spring := 0.0
	for i in 150:
		await _frames(1)
		max_up = maxf(max_up, v.body_pitch)
		min_pitch = minf(min_pitch, v.body_pitch)
		min_spring = minf(min_spring, v.spring_y)
	out["air_pitch_up_down_deg"] = [snappedf(rad_to_deg(max_up), 0.1), snappedf(rad_to_deg(min_pitch), 0.1)]
	out["landing_spring_min_m"] = snappedf(min_spring, 0.01)
	out["spring_settled_m"] = snappedf(v.spring_y, 0.01)
	p.controller = ctrl
	out["pass"] = out["roll_deg_right_turn"] > 2.0 and out["front_wheel_yaw_deg"] < -10.0 and out["brake_pitch_deg"] < -1.5 \
			and max_up > 0.04 and min_pitch < -0.05 and min_spring < -0.03 and absf(v.spring_y) < 0.02
	return out


## V1: dust, tiered drift sparks, boost flame trail, landing dust, skid marks.
func t_t_trail_fx() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var fx: KartTrailFx = rm.trail_fx
	var p := rm.player
	var ctrl := p.controller
	p.controller = null
	for key in fx.stats:
		fx.stats[key] = 0
	_stage(p, 1000.0, 24.0)
	for i in 60:
		p.in_throttle = 1.0; p.in_steer = 0.0
		await _frames(1)
	var dust_straight: int = fx.stats["dust"]
	p.drifting = true; p.drift_dir = 1
	for i in 80:
		p.in_throttle = 1.0; p.in_steer = 1.0; p.in_drift = true
		p.drifting = true; p.drift_time = 1.2
		await _frames(1)
	p.in_drift = false
	var skids := fx.skid_count()
	p.add_boost("nitro", 6.0, 0.6)
	await _frames(30)
	p.landed.emit(p, 0.8)
	await _frames(2)
	var out := fx.stats.duplicate()
	out["dust_in_1s_straight"] = dust_straight
	out["skid_quads"] = skids
	p.controller = ctrl
	out["pass"] = dust_straight >= 5 and fx.stats["sparks"] >= 5 and fx.stats["flames"] >= 5 and fx.stats["landing_dust"] >= 1 and skids >= 5
	return out


## H1 H4 H5: tips queue by priority, timing cues have their own label, rank
## change animates + "超越 X", lap label, boost meter = boost time left.
func t_u_hud_flow() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var hud := get_tree().root.find_children("*", "HudController", true, false)
	var h: HudController = hud[0] if not hud.is_empty() else null
	var out := {}
	if h == null:
		return {"pass": false, "error": "no hud"}
	var p := rm.player
	h.push_tip("A low", Color.WHITE, 0, 1.0)
	h.push_tip("B low", Color.WHITE, 0, 1.0)
	h.push_tip("C bad", Color.RED, 2, 1.0)
	out["shown_after_3_pushes"] = h.tip_label.text
	out["queued"] = h.tip_queue_size()
	await _wait(1.1)
	out["next_shown"] = h.tip_label.text
	# timing cue does not clobber the tip
	p.mini_window = 0.2
	await _frames(2)
	out["cue"] = h.cue_label.text
	out["tip_kept"] = h.tip_label.text
	p.mini_window = 0.0
	# boost meter (staged away from boost pads)
	_stage(p, 1530.0, 6.0)
	p.boosts.clear()
	p.add_boost("nitro", 6.0, 2.0)
	await _wait(1.0)
	out["meter_after_1_of_2s"] = snappedf(h.boost_bar.value, 0.05)
	out["meter_kind"] = p.boost_meter()[0]
	p.boosts.clear()
	await _frames(2)
	out["meter_idle"] = h.boost_bar.value
	# rank change: put the player just behind a kart, then just ahead of it
	var ai := _ai(3)
	var rc0 := h.rank_changes
	_stage(ai, 1500.0, 20.0)
	_stage(p, 1490.0, 20.0)
	await _frames(10)
	_stage(p, 1510.0, 20.0)
	await _frames(10)
	out["rank_changes"] = h.rank_changes - rc0
	out["overtake_tip"] = h.tip_label.text if h.tip_label.text.begins_with("超越") else ""
	for t in h._tips:
		if str(t["text"]).begins_with("超越"):
			out["overtake_tip"] = t["text"]
	out["lap_label"] = h.lap_label.text
	out["pass"] = out["shown_after_3_pushes"] == "C bad" and out["queued"] == 2 and out["next_shown"] == "A low" \
			and out["cue"].begins_with("小喷") and out["tip_kept"] == "A low" and absf(out["meter_after_1_of_2s"] - 0.5) <= 0.1 \
			and out["meter_kind"] == "nitro" and out["meter_idle"] == 0.0 and out["rank_changes"] >= 1 and out["overtake_tip"] != "" \
			and out["lap_label"] == "圈数 1/1"
	return out


## A6: rubber band aims at a per-AI target gap, has a ±25 m dead zone, ±8 %
## cap, and fades out over the last 15 % of the race.
func t_v_rubber_band() -> Dictionary:
	await _until_racing()
	await _wait(maxf(0.0, 10.5 - rm.race_time))
	var ai := _ai(2)
	var rb := ai.get_node("RubberBand") as AIRubberBand
	var p := rm.player
	var out := {"target_gap": rb.target_gap}
	var cases := {}
	for off in [0.0, -300.0, 300.0]:
		_stage(p, 1500.0, 20.0)
		_stage(ai, 1500.0 + rb.target_gap + off, 20.0)
		await _frames(2)
		cases["%d" % int(off)] = snappedf(rb.compute_target(), 0.001)
	out["target_by_error_m"] = cases
	_stage(p, rm.track.length - 60.0, 20.0)
	_stage(ai, rm.track.length - 60.0 - 300.0, 20.0)
	await _frames(2)
	out["near_finish_far_behind"] = snappedf(rb.compute_target(), 0.001)
	var gaps := []
	for k in rm.karts:
		var r := k.get_node_or_null("RubberBand") as AIRubberBand
		if r:
			gaps.append(r.target_gap)
	out["all_target_gaps"] = gaps
	out["pass"] = cases["0"] == 1.0 and cases["-300"] == 1.08 and cases["300"] == 0.92 and out["near_finish_far_behind"] < 1.02
	return out


## A8: the AI holds a missile on a straight instead of firing at once, and does
## not cast lightning from 2nd place.
func t_w_ai_item_timing() -> Dictionary:
	await _until_racing()
	await _clear_items()
	var ai := _ai(2)
	var drv := ai.get_node("AIDriver") as AIDriver
	var out := {}
	# lightning from a high rank: put the AI first-ish
	_stage(ai, 1800.0, 22.0)
	ai.items.clear()
	await _frames(30)        # let the ranking catch up with the teleport
	out["rank_at_give"] = ai.rank
	ai.items.append(ItemDefs.LIGHTNING)
	var used_light := false
	var slots_filled := false     # a full inventory is dumped after 5 s - legit
	for i in 8 * 60:
		await _frames(1)
		if ai.items.size() >= Kart.MAX_ITEMS:
			slots_filled = true
		if ai.items.is_empty() or ai.items[0] != ItemDefs.LIGHTNING:
			used_light = not slots_filled
			break
	out["ai_rank"] = ai.rank
	out["lightning_used_in_8s_from_rank"] = used_light
	out["slots_filled_first"] = slots_filled
	ai.items.clear()
	await _frames(2)
	# missile: earliest use time
	ai.items.clear()
	ai.items.append(ItemDefs.MISSILE)
	var t0 := rm.race_clock
	var fired_after := -1.0
	for i in 12 * 60:
		await _frames(1)
		if ai.items.is_empty():
			fired_after = rm.race_clock - t0
			break
	out["missile_fired_after_s"] = snappedf(fired_after, 0.01)
	out["attack_hold_s"] = snappedf(drv._attack_hold, 0.01)
	await _clear_items()
	out["pass"] = (not used_light or ai.rank >= 4) and (fired_after < 0.0 or fired_after >= 1.5)
	return out


## T1 T3 T4: longer technical layout, canyon walls only inside the canyon zone.
func t_x_track_layout() -> Dictionary:
	await _frames(1)
	var tb: TrackBuilder = rm.track_builder
	var tr := rm.track
	var out := {"race_m": snappedf(tr.finish_offset - tr.start_offset, 1.0)}
	var walls := []
	for s in [700.0, 900.0, 1100.0]:
		var c := tr.position_at(s) + tr.right_at(s) * 22.0
		walls.append(snappedf(tb.terrain_height(c.x, c.z) - tr.position_at(s).y, 0.1))
	out["canyon_wall_above_road_m"] = walls
	var c2 := tr.position_at(2000.0) + tr.right_at(2000.0) * 22.0
	out["dunes_at_22m_above_road_m"] = snappedf(tb.terrain_height(c2.x, c2.z) - tr.position_at(2000.0).y, 0.1)
	out["terrain_cell_m"] = TrackBuilder.TERRAIN_CELL
	var wmin: float = walls.min()
	out["pass"] = float(out["race_m"]) > 3200.0 and wmin >= 10.0 and float(out["dunes_at_22m_above_road_m"]) < 8.0
	return out
