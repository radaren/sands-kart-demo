extends Node
## Headless functional test of the core loop.
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test
## Writes tests/test_results.json (also printed). Exit code 0 = all pass.

const RACE := "res://scenes/race/race.tscn"

var race: Node
var rm: RaceManager
var player: Kart
var results := []
var boost_kinds := {}


func _ready() -> void:
	race = load(RACE).instantiate()
	add_child(race)
	rm = race.get_node("RaceManager")
	_run()


func _check(name: String, ok: bool, detail: Dictionary) -> void:
	results.append({"test": name, "pass": ok, "detail": detail})
	print(("PASS " if ok else "FAIL ") + name + "  " + JSON.stringify(detail))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await _frames(int(seconds * 60.0))


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var n := int(timeout_s * 60.0)
	for i in n:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _press(action: String) -> void:
	Input.action_press(action)


func _release(action: String) -> void:
	Input.action_release(action)


func _run() -> void:
	await _wait_until(func(): return rm.player != null, 5.0)
	player = rm.player
	player.boosted.connect(func(_k, kind): boost_kinds[kind] = boost_kinds.get(kind, 0) + 1)
	var hud: HudController = race.get_node("HUD")

	# 1. countdown + super start ------------------------------------------
	await _wait_until(func(): return rm.countdown_value == 3 and rm.race_clock >= RaceManager.SETTLE + 0.1, 5.0)
	var shown := hud.center_label.text
	_check("countdown_shows_3", rm.state == RaceManager.State.COUNTDOWN and shown == "3",
			{"state": rm.state, "hud_center": shown, "rank_text": hud.rank_label.text, "speed_text": hud.speed_label.text})
	await _wait_until(func(): return rm.race_clock >= rm.go_clock - 0.25, 5.0)
	_press("throttle")
	await _wait_until(func(): return rm.state == RaceManager.State.RACING, 2.0)
	await _wait(0.5)
	var v := player.velocity.length()
	_check("super_start_speed_gt_15", v > 15.0 and boost_kinds.has("start"),
			{"velocity_mps": snappedf(v, 0.01), "speed_kmh": snappedf(player.kmh(), 0.1), "start_boost": boost_kinds.has("start"), "max_speed_cfg": player.config.max_speed})

	# 2. drift + mini boost + double boost into turn 1 (right hander) ------------
	await _wait_until(func(): return player.progress >= 118.0, 10.0)
	_press("steer_right")
	await _frames(2)
	_press("drift")
	await _wait(0.8)
	var drift_was := player.drifting
	var dtime := player.drift_time
	_release("drift")
	_release("steer_right")
	_release("throttle")
	await _frames(1)
	var window := player.mini_window
	var before := player.speed
	await _wait(0.1)
	_press("throttle")
	await _frames(3)
	var minis := player.stat_mini_boosts
	await _wait(0.2)
	_release("throttle")
	await _frames(2)
	_press("throttle")
	await _wait(0.3)
	var after := player.speed
	_check("drift_mini_boost", drift_was and minis >= 1 and boost_kinds.has("mini"),
			{"was_drifting": drift_was, "drift_time": snappedf(dtime, 0.01), "mini_window_after_release": snappedf(window, 0.01),
			"mini_boosts": minis, "speed_before": snappedf(before, 0.01), "speed_after": snappedf(after, 0.01), "boost_kinds": boost_kinds.duplicate()})

	# switch the player to the AI driver (items still read from Input)
	var ai := AIDriver.new()
	ai.kart = player
	ai.manual_items = true
	ai.aggression = 1.0      # the check needs a pickup: always go for boxes
	ai.name = "AutoPilot"
	player.add_child(ai)
	var human: Node = player.controller
	player.controller = ai

	# 3. item pickup + use -------------------------------------------------
	var got: bool = await _wait_until(func(): return player.item_slots[0] != null, 75.0)   # rows are ~400 m apart; 75 s covers 6 rows
	var item: Variant = player.item_slots[0]
	var item_key: String = ItemDefs.KEYS.get(item, "none") if got else "none"
	var used_before: int = rm.item_system.used_log.size()
	_press("use_item")
	await _frames(6)
	_release("use_item")
	await _frames(2)
	var used: bool = rm.item_system.used_log.size() > used_before
	_check("item_pickup_and_use", got and used,
			{"picked": item_key, "progress_at_pickup": snappedf(player.progress, 0.1), "used_log": rm.item_system.used_log.slice(used_before),
			"nitro_active": player.boosts.has("nitro"), "shield": player.shield_time > 0.0})

	# 4. rankings update ---------------------------------------------------
	var r1: Array = rm.rankings.duplicate()
	var p1 := {}
	for k in rm.karts:
		p1[k.name] = k.progress
	await _wait(3.0)
	var r2: Array = rm.rankings.duplicate()
	var moved := 0
	for k in rm.karts:
		if not k.is_player and k.progress > p1[k.name] + 5.0:
			moved += 1
	var rubber := {}
	for k in rm.karts:
		rubber[k.name] = snappedf(k.rubber, 0.001)
	_check("rankings_update", r2.size() == 6 and r2.has("Player") and player.rank >= 1 and player.rank <= 6 and moved == 5,
			{"before": r1, "after": r2, "player_rank": player.rank, "ai_moving": moved, "rubber": rubber})

	# 5. wrong way warning + respawn penalty -------------------------------
	player.controller = human
	_release("throttle")
	player.facing_yaw = wrapf(player.facing_yaw + PI, -PI, PI)
	player.move_yaw = player.facing_yaw
	player.speed = 6.0
	_press("throttle")
	var ww: bool = await _wait_until(func(): return player.wrong_way_time > 0.8, 4.0)
	await _frames(2)
	var banner: bool = player.wrong_way_time > 0.8
	var ww_time: float = player.wrong_way_time
	_press("respawn")
	await _frames(2)
	_release("respawn")
	var frozen := player.freeze_time
	_check("wrong_way_and_respawn", ww and banner and frozen > 2.5,
			{"wrong_way_time_before_R": snappedf(ww_time, 0.01), "wrong_way_time_after_R": snappedf(player.wrong_way_time, 0.01), "freeze_after_R": snappedf(frozen, 0.01)})
	player.controller = ai

	# 6. finish + results ----------------------------------------------------
	var done: bool = await _wait_until(func(): return rm.race_finished, 420.0)
	var res_screen: ResultsScreen = race.get_node("Results")
	var times := []
	for r in rm.results:
		times.append("%d %s %s" % [r.rank, r.name, r.time_text])
	var ok_rows: bool = rm.results.size() == 6 and rm.results.all(func(r): return str(r.time_text) != "")
	_check("race_finished_and_results", done and ok_rows and res_screen.is_showing(),
			{"race_finished": rm.race_finished, "player_finish": RaceManager.format_time(player.finish_time), "results": times,
			"boost_kinds": boost_kinds, "player_hits": player.stat_hits,
			"landing_boosts_by_kart": rm.karts.map(func(k): return "%d/%d" % [k.stat_landing_boosts, k.stat_launches]), "items_used_total": rm.item_system.used_log.size(),
			"ai_wall_hits": rm.karts.filter(func(k): return not k.is_player).map(func(k): return k.stat_wall_hits),
			"ai_steer_jitter_per_s": rm.karts.filter(func(k): return not k.is_player).map(func(k): var a = k.get_node("AIDriver"); return snappedf(a.stat_steer_jitter / maxf(a.stat_ticks, 1) * 60.0, 0.01)),
			"ai_attack_hold_s": _attack_holds(),
			"charge_fills_by_kart": rm.karts.map(func(k): return k.stat_charge_fills),
			"sim_seconds": snappedf(rm.race_time, 0.1)})

	# 7. post-finish: 10 s after the results appear, finished karts must coast
	# and park cleanly - no walls, no kart-kart contacts, no jitter
	var fin: Array = rm.karts.filter(func(k): return k.finished)
	var wall0: Array = fin.map(func(k): return k.stat_wall_hits)
	var bump0: Array = fin.map(func(k): return k.stat_bumps)
	var prev: Array = fin.map(func(k): return k.global_position)
	var prev2: Array = prev.duplicate()
	var max_jerk := 0.0
	var min_pair := 99.0
	var max_lat := 0.0
	var cam: Camera3D = race.get_node("Camera") if race.has_node("Camera") else get_viewport().get_camera_3d()
	var min_cam := 99.0
	for f_i in 600:
		await get_tree().physics_frame
		for i in fin.size():
			var k: Kart = fin[i]
			var pnow: Vector3 = k.global_position
			if f_i >= 2:
				max_jerk = maxf(max_jerk, (pnow - 2.0 * prev[i] + prev2[i]).length())
			prev2[i] = prev[i]
			prev[i] = pnow
			max_lat = maxf(max_lat, absf(k.lateral))
			for j in range(i + 1, fin.size()) if f_i > 480 else []:
				min_pair = minf(min_pair, pnow.distance_to(fin[j].global_position))
		if cam and player.finished:
			min_cam = minf(min_cam, cam.global_position.distance_to(player.global_position))
	if OS.get_cmdline_user_args().has("--coast-debug"):
		for k in fin:
			print("END %s parked=%s s=%.1f sp=%.2f lat=%.2f" % [k.name, k.parked, k.progress, k.speed, k.lateral])
	var walls_after: int = 0
	var bumps_after: int = 0
	for i in fin.size():
		walls_after += fin[i].stat_wall_hits - int(wall0[i])
		bumps_after += fin[i].stat_bumps - int(bump0[i])
	var parked: int = fin.filter(func(k): return k.parked).size()
	# late finishers may still be cruising down the run-off - smoothly, at <= cruise speed
	var settled: int = fin.filter(func(k): return k.parked or absf(k.speed) <= AIDriver.COAST_CRUISE + 0.5).size()
	_check("post_finish_settles", fin.size() >= 2 and walls_after == 0 and bumps_after == 0 and max_jerk < 0.02 \
			and min_pair > 1.5 and max_lat < rm.track.road_width * 0.5 - 1.0 and settled == fin.size() and parked >= 1 and min_cam > 2.0,
			{"finished_karts": fin.size(), "parked": parked, "settled": settled, "wall_hits_after": walls_after, "bumps_after": bumps_after,
			"max_jerk_m_per_frame2": snappedf(max_jerk, 0.0001), "min_pair_dist_m": snappedf(min_pair, 0.01),
			"max_abs_lateral_m": snappedf(max_lat, 0.01), "min_camera_dist_m": snappedf(min_cam, 0.01)})

	var all_ok: bool = results.all(func(r): return r.pass)
	var f := FileAccess.open("res://tests/test_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"godot": Engine.get_version_info().string, "all_pass": all_ok, "results": results}, "  "))
	f.close()
	print("ALL PASS" if all_ok else "SOME FAILED")
	get_tree().quit(0 if all_ok else 1)


## A8: min / mean seconds the AI held attack items before using them
func _attack_holds() -> Array:
	var hs := []
	for k in rm.karts:
		var a := k.get_node_or_null("AIDriver") as AIDriver
		if a == null or k.is_player:
			continue
		for h in a.stat_item_holds:
			if h[0] in [ItemDefs.MISSILE, ItemDefs.UFO, ItemDefs.LIGHTNING]:
				hs.append(float(h[1]))
	if hs.is_empty():
		return []
	var tot := 0.0
	for h in hs:
		tot += h
	return [hs.size(), snappedf(hs.min(), 0.01), snappedf(tot / hs.size(), 0.01)]
