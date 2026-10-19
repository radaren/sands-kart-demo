extends Node
## Autoload "GameConfig": command-line flags + InputMap safety net.
## User args (after `--`):  --autopilot  --laps=N  --test  --screenshot=path  --seed=N

var autopilot := false
var max_laps := 1
var test_mode := false
var screenshot_path := ""
var rng_seed := 0

const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP], "throttle": [KEY_W, KEY_UP], "move_forward": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN], "move_backward": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT], "steer_right": [KEY_D, KEY_RIGHT],
	"drift": [KEY_SHIFT], "use_item": [KEY_CTRL, KEY_SPACE],
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
