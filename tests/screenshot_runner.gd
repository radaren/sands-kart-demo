extends Node
## Captures screenshots (needs a display, e.g. xvfb-run):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-method gl_compatibility \
##       --resolution 1280x720 --fixed-fps 60 res://tests/screenshot_runner.tscn -- --autopilot
## Shots go to res://screenshots/.

const SHOTS := [
	[0.0, "01_title.png"],
	[1.2, "02_countdown.png"],
	[9.0, "03_town.png"],
	[30.0, "04_canyon.png"],
	[55.0, "05_dunes.png"],
	[80.0, "06_late_race.png"],
]

func _snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://screenshots/" + file)
	print("SHOT ", file)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	GameConfig.autopilot = true
	var title: Node = load("res://scenes/ui/title.tscn").instantiate()
	add_child(title)
	await _frames(20)
	await _snap(SHOTS[0][1])
	title.queue_free()
	var race: Node = load("res://scenes/race/race.tscn").instantiate()
	add_child(race)
	var rm: RaceManager = race.get_node("RaceManager")
	var t0 := Time.get_ticks_msec()
	var frame := 0
	for i in range(1, SHOTS.size()):
		var target := int(SHOTS[i][0] * 60.0)
		await _frames(target - frame)
		frame = target
		await _snap(SHOTS[i][1])
	# results
	var results: Node = race.get_node("Results")
	var n := 0
	while not results.is_showing() and n < 60 * 120:
		await get_tree().process_frame
		n += 1
	await _frames(30)
	await _snap("07_results.png")
	print("done in ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	get_tree().quit()
