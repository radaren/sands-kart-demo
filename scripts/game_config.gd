extends Node
## Autoload "GameConfig": command-line flags + InputMap safety net.
## User args (after `--`):  --autopilot  --laps=N  --test  --screenshot=path  --seed=N

var autopilot := false
var max_laps := 1
var test_mode := false
var screenshot_path := ""
var rng_seed := 0
var web_input := false

const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP], "throttle": [KEY_W, KEY_UP], "move_forward": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN], "move_backward": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT],
	"drift": [KEY_SHIFT, KEY_X], "use_item": [KEY_SPACE, KEY_E, KEY_J],
	"respawn": [KEY_R], "pause": [KEY_ESCAPE], "look_back": [KEY_B],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a == "--autopilot":
			autopilot = true
		elif a == "--test":
			test_mode = true
		elif a.begins_with("--laps="):
			max_laps = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--screenshot="):
			screenshot_path = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			rng_seed = int(a.get_slice("=", 1))
	# Make sure every action exists even if project.godot was edited.
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
			for k in ACTIONS[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(action, ev)
	apply_platform_input(OS.has_feature("web"))


## Ctrl is never bound in the project (in a browser Ctrl+W closes the tab and
## Chrome won't let the page block it; Ctrl+D/S bookmark/save). Desktop builds
## add Ctrl back as the QQ飞车-style item key; the web build strips it everywhere.
func apply_platform_input(is_web: bool) -> void:
	web_input = is_web
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue   # built-in text editing shortcuts (copy/paste) stay
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and (e.physical_keycode == KEY_CTRL or e.keycode == KEY_CTRL or e.ctrl_pressed):
				InputMap.action_erase_event(action, e)
	if not is_web and InputMap.has_action("use_item"):
		var ctrl := InputEventKey.new()
		ctrl.physical_keycode = KEY_CTRL
		InputMap.action_add_event("use_item", ctrl)


func item_key_hint() -> String:
	return "Space/E 使用" if web_input else "Space/E/Ctrl 使用"
