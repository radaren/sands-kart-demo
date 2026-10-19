class_name ResultsScreen
extends CanvasLayer
## Results: 1-6 with names and finish times (1:23.45), restart / title buttons.

@export var race_path: NodePath = ^"../RaceManager"

var race: RaceManager
var panel: PanelContainer
var list: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	race = get_node(race_path) as RaceManager
	race.race_completed.connect(show_results)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 470)
	panel.position = Vector2(-280, -235)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.1, 0.05, 0.88)
	sb.border_color = Color(1.0, 0.8, 0.4)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "比赛结果 RESULTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	v.add_child(title)
	list = VBoxContainer.new()
	v.add_child(list)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	v.add_child(buttons)
	var again := Button.new()
	again.name = "Restart"
	again.text = "再来一局"
	again.custom_minimum_size = Vector2(200, 52)
	again.add_theme_font_size_override("font_size", 24)
	again.pressed.connect(func(): race.request_restart())
	buttons.add_child(again)
	var back := Button.new()
	back.text = "返回标题"
	back.custom_minimum_size = Vector2(200, 52)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func(): race.request_title())
	buttons.add_child(back)
	panel.visible = false


func show_results(results: Array) -> void:
	for c in list.get_children():
		c.queue_free()
	for r: Dictionary in results:
		var row := HBoxContainer.new()
		for txt_w in [["%d" % r.rank, 50], [r.name, 220], [r.time_text, 180]]:
			var l := Label.new()
			l.text = txt_w[0]
			l.custom_minimum_size = Vector2(txt_w[1], 0)
			l.add_theme_font_size_override("font_size", 28)
			l.add_theme_color_override("font_color", Color(1, 0.95, 0.5) if r.player else (r.color as Color).lightened(0.35))
			row.add_child(l)
		list.add_child(row)
	panel.visible = true
	(panel.find_child("Restart", true, false) as Button).grab_focus()


func is_showing() -> bool:
	return panel.visible
