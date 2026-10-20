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
	k.place(rm.track.spawn_transform(s, lat))
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
