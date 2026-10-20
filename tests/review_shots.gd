extends Node
## Before/after screenshots for review fixes (needs a display; use the Compatibility renderer):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method gl_compatibility \
##     --resolution 1280x720 --fixed-fps 60 --audio-driver Dummy res://tests/review_shots.tscn -- \
##     --tag=before --shots=start,pack,town,canyon,dunes,boost
## Files: screenshots/review_fixes/<tag>_<shot>.png

const STAGES := {"town": 230.0, "canyon": 1250.0, "dunes": 2150.0, "finish": 2860.0, "boost": 700.0, "ramp": 470.0}

var tag := "shot"
var shots: PackedStringArray = ["start", "pack", "town", "canyon", "dunes", "boost"]
var out_dir := "res://screenshots/review_fixes/"
var rm: RaceManager


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir + tag + "_" + name + ".png"
	img.save_png(path)
	print("SHOT ", path)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
		elif a.begins_with("--shots="):
			shots = a.get_slice("=", 1).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	GameConfig.autopilot = true
	if GameConfig.rng_seed == 0:
		GameConfig.rng_seed = 5
	var race: Node = load("res://scenes/race/race.tscn").instantiate()
	add_child(race)
	rm = race.get_node("RaceManager")
	while rm.player == null:
		await _frames(1)
	for s in shots:
		if s.begins_with("it_"):
			await _item_shot(s)
			continue
		if s.begins_with("seq_"):
			await _sequence(s)
			continue
		match s:
			"start":
				while rm.race_clock < 1.3:
					await _frames(1)
				await _snap(s)
			"cd_window":      # H2/K13: the countdown in the super-start window
				while rm.state != RaceManager.State.COUNTDOWN or rm.go_clock - rm.race_clock > 0.2:
					await _frames(1)
				await _snap(s)
			"drift_tiers":    # K5: spark colour per mini-boost tier
				while rm.state != RaceManager.State.RACING or rm.race_time < 3.0:
					await _frames(1)
				var dp := rm.player
				dp.controller = null
				_teleport(dp, 1000.0)
				for dt in [0.6, 1.3, 2.0]:
					dp.speed = 24.0
					dp.drifting = true
					dp.drift_dir = 1
					dp.drift_time = dt
					await _frames(6)
					dp.drift_time = dt
					await _snap("%s_%.1f" % [s, dt])
			"pack":
				while rm.state != RaceManager.State.RACING or rm.race_time < 4.0:
					await _frames(1)
				await _snap(s)
			_:
				while rm.state != RaceManager.State.RACING:
					await _frames(1)
				var p := rm.player
				_teleport(p, STAGES.get(s, 1000.0))
				p.speed = 26.0
				await _frames(40 if s != "boost" else 25)
				if s == "boost":
					p.add_boost("nitro", p.config.nitro_bonus, p.config.nitro_time)
					await _frames(12)
				await _snap(s)
	get_tree().quit()


func _teleport(p: Kart, s: float, lat := 0.0) -> void:
	if rm.has_method("teleport"):
		rm.call("teleport", p, s, lat)
	else:   # older builds (before shots)
		p.place(rm.track.spawn_transform(s, lat))
		p.track_index = int(s / rm.track.step)
		rm.trackers[p] = CheckpointTracker.new(rm.track.checkpoints, s)
		var t: CheckpointTracker = rm.trackers[p]
		while t.next_index < rm.track.checkpoints.size() and rm.track.checkpoints[t.next_index] <= s:
			t.next_index += 1
		p.progress = s


## Frame sequences: <tag>_<seq>_NN.png every `every` physics frames.
func _sequence(name: String) -> void:
	while rm.state != RaceManager.State.RACING or rm.race_time < 3.0:
		await _frames(1)
	var p := rm.player
	var n := 24
	var every := 5
	match name:
		"seq_missile":
			await _reset_scene()
			var ai := _setup_pair(900.0, 22.0)
			_use(p, ItemDefs.MISSILE)
			n = 24
			every = 3
		"seq_wall":
			await _reset_scene()
			_teleport(p, 1000.0, 3.5)
			p.speed = 26.0
			p.facing_yaw = wrapf(p.facing_yaw - 0.6, -PI, PI)
			p.move_yaw = p.facing_yaw
			n = 20
			every = 3
		"seq_jump":
			_teleport(p, rm.track.ramps[1] - 10.0)
			p.speed = 30.0
			n = 36
			every = 3
	var cue_done := false
	for i in n:
		for f in every:
			if name == "seq_jump" and not cue_done and p.landing_window > 0.0:
				cue_done = true
				await _snap("landing_cue")
			if name == "seq_jump" and p.controller != null and "_land_go" in p.controller:
				p.controller.set("_land_go", true)
				p.controller.set("_air_go", false)
			await _frames(1)
		await _snap("%s_%02d" % [name, i])
		print("SEQ ", i, " prog ", snappedf(p.progress, 0.1), " air ", snappedf(p.air_time, 0.01), " last ", snappedf(p.last_air_time, 0.01), " g ", p.grounded, " win ", p.landing_window, " boosts ", p.boosts.keys())


func _setup_pair(s: float, gap: float, lat := 0.0) -> Kart:
	var p := rm.player
	var ai: Kart = rm.karts[1]
	_teleport(p, s, lat)
	_teleport(ai, s + gap, lat)
	p.speed = 24.0
	ai.speed = 22.0
	for k in rm.karts:
		if k != p and k != ai:
			_teleport(k, 200.0 + rm.karts.find(k) * 6.0, 0.0)
	return ai


func _use(k: Kart, item: int) -> void:
	k.items.clear()
	rm.item_system.use_item(k, item)


## Item presentation stills: it_<item>[_<phase>]
const ITEM_S := {"it_missile": 900.0, "it_warning": 1100.0, "it_banana": 1650.0, "it_cloud": 1900.0,
		"it_shield": 2050.0, "it_lightning": 2250.0, "it_magnet": 700.0, "it_ufo": 2650.0, "it_hud": 1250.0,
		"it_wall": 1000.0, "it_bump": 1100.0}


func _reset_scene() -> void:
	for c in rm.item_system.get_children():
		c.queue_free()
	for k in rm.karts:
		k.stun_time = 0.0
		k.cloud_time = 0.0
		k.shield_time = 0.0
		k.invuln_time = 0.0
		k.slows.clear()
		k.boosts.clear()
		k.items.clear()
	await _frames(2)


func _item_shot(name: String) -> void:
	while rm.state != RaceManager.State.RACING or rm.race_time < 3.0:
		await _frames(1)
	await _reset_scene()
	var p := rm.player
	var base: float = ITEM_S.get(name, 900.0)
	match name:
		"it_missile":       # player fires at the kart ahead
			var ai := _setup_pair(base, 30.0)
			await _frames(30)
			_use(p, ItemDefs.MISSILE)
			await _frames(9)
			await _snap(name + "_flight")
			for i in 60:
				await _frames(1)
				if ai.stun_time > 0.0:
					break
			await _frames(6)
			await _snap(name + "_hit")
		"it_warning":       # kart behind fires at the player
			var ai := _setup_pair(base, -25.0)
			ai.speed = 24.0
			await _frames(30)
			_use(ai, ItemDefs.MISSILE)
			await _frames(14)
			await _snap(name)
		"it_banana":
			var ai := _setup_pair(base, 16.0)
			await _frames(20)
			_use(ai, ItemDefs.BANANA)
			await _frames(30)
			await _snap(name + "_peel")
			for i in 90:
				await _frames(1)
				if p.stun_time > 0.0:
					break
			await _frames(18)
			await _snap(name + "_spin")
		"it_cloud":
			var ai := _setup_pair(base, 14.0)
			await _frames(20)
			_use(ai, ItemDefs.CLOUD)
			for i in 120:
				await _frames(1)
				if p.cloud_time > 0.0:
					break
			await _frames(30)
			await _snap(name)
		"it_shield":
			var ai := _setup_pair(base, -22.0)
			ai.speed = 24.0
			await _frames(20)
			_use(p, ItemDefs.SHIELD)
			await _frames(30)
			await _snap(name + "_on")
			_use(ai, ItemDefs.MISSILE)
			for i in 90:
				await _frames(1)
				if p.shield_time <= 0.0:
					break
			await _frames(4)
			await _snap(name + "_break")
		"it_lightning":
			var ai := _setup_pair(base, -20.0)
			await _frames(30)
			_use(ai, ItemDefs.LIGHTNING)
			await _frames(4)
			await _snap(name)
		"it_magnet":
			var ai := _setup_pair(base, 12.0)
			await _frames(20)
			_use(p, ItemDefs.MAGNET)
			await _frames(30)
			await _snap(name)
		"it_ufo":
			var ai := _setup_pair(base, 13.0)
			await _frames(20)
			_use(p, ItemDefs.UFO)
			for i in 120:
				await _frames(1)
			await _snap(name)
		"it_wall":          # grind along the right wall (no driver)
			_setup_pair(base, 300.0)
			var ctrl := p.controller
			p.controller = null
			_teleport(p, base, 3.0)
			p.speed = 26.0
			p.facing_yaw -= 0.45
			p.move_yaw = p.facing_yaw
			p.in_throttle = 1.0
			p.in_steer = 0.35
			for i in 40:
				await _frames(1)
				if p.scraping and i > 8:
					break
			await _frames(4)
			await _snap(name + "_hit")
			await _frames(12)
			await _snap(name + "_scrape")
			p.in_steer = 0.0
			p.controller = ctrl
		"it_bump":
			var ai := _setup_pair(base, 4.0)
			var ctrl := p.controller
			var actrl := ai.controller
			p.controller = null
			ai.controller = null
			p.speed = 26.0
			ai.speed = 14.0
			p.in_throttle = 1.0
			ai.in_throttle = 0.5
			for i in 60:
				await _frames(1)
				if p.stat_bumps + ai.stat_bumps > 0:
					break
			await _frames(3)
			await _snap(name)
			p.controller = ctrl
			ai.controller = actrl
		"it_hud":
			var ai := _setup_pair(base, 26.0)
			p.items.clear()
			p.items_changed.emit(p)
			p.receive_item_box()
			await _frames(8)
			await _snap(name + "_roll")
			await _frames(70)
			await _snap(name + "_slots")
