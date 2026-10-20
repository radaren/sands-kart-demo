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
	sun.anchor_left = 0.0
	sun.anchor_right = 1.0
	sun.anchor_top = 0.66
	sun.anchor_bottom = 1.0
	add_child(sun)
	# the user's kart concept art (assets/karts/reference) as title art
	var ref := "res://assets/karts/reference/kart_candidate_1.png"
	if ResourceLoader.exists(ref):
		var tex := TextureRect.new()
		tex.texture = load(ref)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# right column, framed
		var frame := PanelContainer.new()
		frame.anchor_left = 0.56
		frame.anchor_right = 0.96
		frame.anchor_top = 0.5
		frame.anchor_bottom = 0.5
		frame.offset_top = -190
		frame.offset_bottom = 190
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.85, 0.83, 0.8)
		sb.border_color = Color(0.45, 0.18, 0.05)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(6)
		frame.add_theme_stylebox_override("panel", sb)
		add_child(frame)
		frame.add_child(tex)
	var box := VBoxContainer.new()
	# left column
	box.anchor_left = 0.02
	box.anchor_right = 0.55
	box.anchor_top = 0.0
	box.anchor_bottom = 1.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)
	var title := Label.new()
	title.text = "时之沙 · 沙漠卡丁车\n道具赛"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.45, 0.18, 0.05))
	title.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Sands of Time Kart · 6 人道具赛 · 单程约 2.9 km"
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
	help.text = "W/↑ 加速(小喷)  S/↓ 刹车  A D/← → 转向  Shift/X 漂移\n%s 道具  R 重生  B 回看  Esc 暂停" % ("Space/E" if GameConfig.web_input else "Space/E/Ctrl")
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 18)
	help.add_theme_color_override("font_color", Color(0.3, 0.18, 0.08))
	box.add_child(help)
	var q := Button.new()
	q.text = "退出"
	q.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	q.pressed.connect(func(): get_tree().quit())
	if not OS.has_feature("web"):
		box.add_child(q)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		start_requested.emit()
