class_name HudController
extends CanvasLayer
## HUD: rank, lap, timer, speed (km/h), 2 item slots, minimap, countdown and
## centre tips, wrong-way warning, cloud fog overlay, pause menu (Esc).

@export var race_path: NodePath = ^"../RaceManager"

var race: RaceManager
var player: Kart
var rank_label: Label
var lap_label: Label
var time_label: Label
var speed_label: Label
var boost_bar: ProgressBar
var center_label: Label
var tip_label: Label
var wrong_label: Label
var slot_panels: Array[PanelContainer] = []
var slot_labels: Array[Label] = []
var slot_icons: Array[TextureRect] = []
var lock_warn: Control
var _icons := {}
var _shown: Array = []          ## item shown per slot (roulette state)
var _roll_t: Array = [0.0, 0.0]  ## remaining roulette time per slot
var _roll_tick := 0.0
var _rng := RandomNumberGenerator.new()
var _ink: ShaderMaterial
var _ink_amount := 0.0
const ROLL_TIME := 0.55
var fog: ColorRect
var flash_rect: ColorRect
var minimap: Minimap
var pause_menu: Control
var _tips: Array = []
var _tip_time := 0.0
var _center_time := 0.0


func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 7))
	return l


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	race = get_node(race_path) as RaceManager
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	fog = ColorRect.new()
	fog.color = Color(1, 1, 1, 1)
	_ink = ShaderMaterial.new()
	_ink.shader = load("res://assets/shaders/ink_overlay.gdshader")
	fog.material = _ink
	fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fog)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	# top-left: rank / lap / time
	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 16)
	root.add_child(tl)
	rank_label = _label("6/6", 64, Color(1.0, 0.85, 0.3))
	tl.add_child(rank_label)
	lap_label = _label("圈数 1/1", 24)
	tl.add_child(lap_label)
	time_label = _label("0:00.00", 30)
	tl.add_child(time_label)
	# top-right: item slots
	var tr := HBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-270, 18)
	tr.add_theme_constant_override("separation", 12)
	root.add_child(tr)
	for i in 2:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(118 if i == 0 else 92, 92 if i == 0 else 72)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45)
		sb.border_color = Color(1, 0.9, 0.6)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		pc.add_theme_stylebox_override("panel", sb)
		var box := Control.new()
		pc.add_child(box)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6; icon.offset_top = 2; icon.offset_right = -6; icon.offset_bottom = -14
		icon.pivot_offset = pc.custom_minimum_size * 0.5
		box.add_child(icon)
		var l := _label("", 15 if i == 0 else 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.offset_bottom = 4
		box.add_child(l)
		tr.add_child(pc)
		slot_panels.append(pc)
		slot_labels.append(l)
		slot_icons.append(icon)
		_shown.append(ItemDefs.NONE)
	for it: int in ItemDefs.KEYS.keys():
		var path := ItemDefs.icon_path(it)
		if ResourceLoader.exists(path):
			_icons[it] = load(path)
	var hint := _label(GameConfig.item_key_hint(), 14, Color(1, 1, 1, 0.8))
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.position = Vector2(-270, 116)
	root.add_child(hint)
	# bottom-right: speed
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-250, -120)
	root.add_child(br)
	speed_label = _label("0 km/h", 46)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_label.custom_minimum_size = Vector2(220, 0)
	br.add_child(speed_label)
	boost_bar = ProgressBar.new()
	boost_bar.custom_minimum_size = Vector2(220, 14)
	boost_bar.show_percentage = false
	boost_bar.max_value = 1.0
	br.add_child(boost_bar)
	# bottom-left: minimap
	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.size = Vector2(230, 230)
	minimap.position = Vector2(18, -248)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	# centre
	center_label = _label("", 140, Color(1.0, 0.9, 0.3))
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.custom_minimum_size = Vector2(800, 180)
	center_label.position = Vector2(-400, -220)
	root.add_child(center_label)
	tip_label = _label("", 34, Color(1, 1, 1))
	tip_label.set_anchors_preset(Control.PRESET_CENTER)
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_label.custom_minimum_size = Vector2(800, 50)
	tip_label.position = Vector2(-400, -40)
	root.add_child(tip_label)
	wrong_label = _label("逆行!  ←  WRONG WAY", 52, Color(1.0, 0.25, 0.2))
	wrong_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wrong_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrong_label.custom_minimum_size = Vector2(800, 60)
	wrong_label.position = Vector2(-400, 140)
	wrong_label.visible = false
	root.add_child(wrong_label)
	_build_lock_warning(root)
	_build_pause_menu(root)
	race.countdown_tick.connect(_on_countdown)
	if race.item_system:
		race.item_system.screen_flash.connect(_on_flash)
	_bind_player.call_deferred()


func _bind_player() -> void:
	if race.player == null:
		await get_tree().physics_frame
		_bind_player()
		return
	player = race.player
	player.announced.connect(_on_announce)
	player.hit_taken.connect(_on_hit)
	minimap.setup(race.track, race)


## H3 lock-on warning: red chevrons at the bottom centre + label, blinking
## faster as the missile closes in (the beep is in FeedbackDirector).
func _build_lock_warning(root: Control) -> void:
	lock_warn = Control.new()
	lock_warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lock_warn.position = Vector2(0, -150)
	lock_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for j in 2:
		var tri := Polygon2D.new()
		tri.polygon = PackedVector2Array([Vector2(-46, 0), Vector2(0, -34), Vector2(46, 0), Vector2(30, 0), Vector2(0, -22), Vector2(-30, 0)])
		tri.color = Color(1.0, 0.18, 0.12)
		tri.position = Vector2(0, -j * 26)
		lock_warn.add_child(tri)
	var l := _label("▲ 导弹! ▲", 30, Color(1.0, 0.3, 0.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(300, 40)
	l.position = Vector2(-150, 6)
	lock_warn.add_child(l)
	lock_warn.visible = false
	root.add_child(lock_warn)


func _update_slots(delta: float) -> void:
	var fb := get_node_or_null("../Feedback")
	for i in 2:
		var it: int = player.items[i] if i < player.items.size() else ItemDefs.NONE
		if it != ItemDefs.NONE and _shown[i] == ItemDefs.NONE and i == player.items.size() - 1 \
				and not (i == 0 and _shown[1] == it):
			_roll_t[i] = ROLL_TIME        # new pickup: spin the roulette
		_shown[i] = it
		var show := it
		if _roll_t[i] > 0.0:
			_roll_t[i] -= delta
			show = ItemDefs.KEYS.keys()[int(_roll_t[i] * 18.0) % ItemDefs.KEYS.size()]
			if _roll_t[i] <= 0.0:
				show = it
				var tw := slot_icons[i].create_tween()
				slot_icons[i].scale = Vector2(1.35, 1.35)
				tw.tween_property(slot_icons[i], "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
		var sb := slot_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		if show == ItemDefs.NONE:
			slot_icons[i].texture = null
			slot_labels[i].text = ""
			sb.bg_color = Color(0, 0, 0, 0.45)
		else:
			slot_icons[i].texture = _icons.get(show)
			slot_labels[i].text = "" if _roll_t[i] > 0.0 else ItemDefs.item_name(show)
			sb.bg_color = Color(ItemDefs.COLORS[show].darkened(0.35), 0.7)
	if (_roll_t[0] > 0.0 or _roll_t[1] > 0.0) and fb:
		_roll_tick -= delta
		if _roll_tick <= 0.0:
			_roll_tick = 0.07
			fb.play("roll", null, -8.0)


func is_rolling() -> bool:
	return _roll_t[0] > 0.0 or _roll_t[1] > 0.0


func _build_pause_menu(root: Control) -> void:
	pause_menu = PanelContainer.new()
	pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu.position = Vector2(-160, -130)
	pause_menu.custom_minimum_size = Vector2(320, 260)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_menu.add_child(v)
	v.add_child(_label("暂停", 40))
	for pair in [["继续 (Esc)", _toggle_pause], ["重新开始", func(): race.request_restart()], ["返回标题", func(): race.request_title()]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(240, 48)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(pair[1])
		v.add_child(b)
	pause_menu.visible = false
	root.add_child(pause_menu)


func _toggle_pause() -> void:
	if race.race_finished:
		return
	get_tree().paused = not get_tree().paused
	pause_menu.visible = get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()


func _on_countdown(v: int) -> void:
	center_label.text = "GO!" if v == 0 else str(v)
	center_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4) if v == 0 else Color(1.0, 0.9, 0.3))
	_center_time = 0.9
	# H2: 0.25 s pop for each number
	center_label.pivot_offset = center_label.custom_minimum_size * 0.5
	center_label.scale = Vector2.ONE * 1.6
	var tw := center_label.create_tween()
	tw.tween_property(center_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_announce(_k: Kart, text: String, tone: int) -> void:
	var c := Color(0.5, 1.0, 0.6) if tone == Kart.Tone.GOOD else (Color(1.0, 0.45, 0.35) if tone == Kart.Tone.BAD else Color.WHITE)
	tip_label.text = text
	tip_label.add_theme_color_override("font_color", c)
	_tip_time = 1.4


func _on_hit(_k: Kart, kind: String) -> void:
	var names := {"missile": "被导弹击中!", "banana": "踩到香蕉皮!", "lightning": "被闪电劈中!", "ufo": "飞碟减速!", "magnet": "被磁铁吸住!"}
	_on_announce(_k, names.get(kind, "受到攻击!"), Kart.Tone.BAD)


func _on_flash(c: Color) -> void:
	flash_rect.color = Color(c, 0.55)


func _process(delta: float) -> void:
	if race == null:
		return
	if player != null:
		rank_label.text = "%d/%d" % [player.rank, race.karts.size()]
		lap_label.text = "圈数 %d/%d" % [1, race.max_laps]
		time_label.text = RaceManager.format_time(race.race_time if race.state != RaceManager.State.COUNTDOWN else 0.0)
		if player.finished:
			time_label.text = RaceManager.format_time(player.finish_time)
		speed_label.text = "%d km/h" % int(round(player.kmh()))
		var top := player.config.max_speed + player.config.nitro_bonus
		boost_bar.value = clampf(absf(player.speed) / top, 0.0, 1.0)
		boost_bar.modulate = Color(0.4, 0.8, 1.0) if player.is_boosting() else Color(1, 1, 1)
		_update_slots(delta)
		var incoming := race.item_system.incoming_missile(player) if race.item_system else INF
		if incoming < 120.0:
			var rate := lerpf(16.0, 4.0, clampf(incoming / 87.0, 0.0, 1.0))
			lock_warn.visible = true
			lock_warn.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.001 * rate * PI * 0.5))
			lock_warn.scale = Vector2.ONE * lerpf(1.3, 0.9, clampf(incoming / 120.0, 0.0, 1.0))
		else:
			lock_warn.visible = false
		wrong_label.visible = player.wrong_way_time > 0.8 and int(Time.get_ticks_msec() / 300) % 2 == 0
		var was := _ink_amount
		_ink_amount = move_toward(_ink_amount, 1.0 if player.cloud_time > 0.0 else 0.0, delta * (4.0 if player.cloud_time > 0.0 else 1.2))
		if was <= 0.0 and _ink_amount > 0.0:
			_ink.set_shader_parameter("seed", _rng.randf() * 10.0)
		_ink.set_shader_parameter("amount", _ink_amount)
		var vs := get_viewport().get_visible_rect().size
		_ink.set_shader_parameter("aspect", Vector2(vs.x / maxf(vs.y, 1.0), 1.0))
		fog.visible = _ink_amount > 0.0
		if player.mini_window > 0.0 and _tip_time <= 0.0:
			tip_label.text = "小喷就绪! 按 ↑/W"
			tip_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
			_tip_time = 0.3
		if player.landing_window > 0.0:
			# the window is only 0.3 s: this hint wins over any other tip
			tip_label.text = "落地喷! 点按 ↑/W"
			tip_label.add_theme_color_override("font_color", Color(0.55, 1.0, 1.0))
			_tip_time = 0.3
	if race.state == RaceManager.State.COUNTDOWN and race.race_clock < RaceManager.SETTLE:
		center_label.text = ""
	elif race.state == RaceManager.State.COUNTDOWN and player != null:
		# H2/K13: the number turns green inside the super-start window
		var left := race.go_clock - race.race_clock
		var in_window := left <= player.config.super_start_early
		center_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.35) if in_window else Color(1.0, 0.9, 0.3))
		if in_window and _tip_time <= 0.0:
			tip_label.text = "现在按 ↑/W!"
			tip_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			_tip_time = 0.1
	_center_time -= delta
	if _center_time <= 0.0 and race.state != RaceManager.State.COUNTDOWN:
		center_label.text = ""
	_tip_time -= delta
	if _tip_time <= 0.0:
		tip_label.text = ""
	flash_rect.color.a = move_toward(flash_rect.color.a, 0.0, delta * 2.0)
