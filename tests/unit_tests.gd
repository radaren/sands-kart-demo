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
