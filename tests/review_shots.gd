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
		if s.begins_with("seq_"):
			await _sequence(s)
			continue
		match s:
			"start":
				while rm.race_clock < 1.3:
					await _frames(1)
				await _snap(s)
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
