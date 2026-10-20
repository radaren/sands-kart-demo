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
