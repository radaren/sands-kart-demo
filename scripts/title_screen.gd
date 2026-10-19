extends Control
## Title screen (built in code so it needs no art assets).

signal start_requested

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.72, 0.42)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var sun := ColorRect.new()
	sun.color = Color(1.0, 0.86, 0.55)
	sun.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sun.offset_top = -220
	add_child(sun)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(640, 0)
	box.position = Vector2(-320, -200)
	add_child(box)
	var title := Label.new()
	title.text = "时之沙 · 沙漠卡丁车道具赛"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.45, 0.18, 0.05))
	title.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Sands Kart Demo · 6 人道具赛 · 单程约 2.9 km"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.35, 0.2, 0.1))
	box.add_child(sub)
	var btn := Button.new()
	btn.text = "开始比赛 (Enter)"
	btn.custom_minimum_size = Vector2(320, 64)
	btn.add_theme_font_size_override("font_size", 28)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func(): start_requested.emit())
	box.add_child(btn)
	btn.grab_focus()
	var help := Label.new()
	help.text = "W/↑ 加速(小喷)  S/↓ 刹车  A D/← → 转向  Shift 漂移\nCtrl/Space 道具  R 重生  Esc 暂停"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 18)
	help.add_theme_color_override("font_color", Color(0.3, 0.18, 0.08))
	box.add_child(help)
	var q := Button.new()
	q.text = "退出"
	q.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	q.pressed.connect(func(): get_tree().quit())
	box.add_child(q)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		start_requested.emit()
