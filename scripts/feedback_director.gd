class_name FeedbackDirector
extends Node
## One place that turns game events into feedback (W3): sound effects, camera
## shake (trauma) and FOV kicks. Subscribes to kart / item / race signals;
## gameplay code never calls audio or camera directly.

const SFX_DIR := "res://assets/audio/sfx/"
const SFX := ["beep", "go", "boost", "mini", "wall", "pickup", "use", "explode", "hit",
		"zap", "shield", "slip", "warn", "finish", "land", "ding"]
const HIT_SOUND := {"missile": "explode", "lightning": "zap", "banana": "slip", "ufo": "zap"}
const FOV_KICK := {"mini": 4.0, "nitro": 10.0, "start": 8.0, "pad": 8.0, "landing": 6.0, "air": 5.0}

@export var race_path: NodePath = ^"../RaceManager"
@export var camera_path: NodePath = ^"../ChaseCamera"
@export var items_path: NodePath = ^"../ItemSystem"

var race: RaceManager
var camera: ChaseCamera
var streams := {}
var played: Array[String] = []        ## log of played effects (tests / debugging)
var _item_counts := {}
var _pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	race = get_node(race_path) as RaceManager
	camera = get_node_or_null(camera_path) as ChaseCamera
	for n in SFX:
		var path: String = SFX_DIR + n + ".wav"
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_pool.append(p)
	race.karts_spawned.connect(_on_karts)
	race.countdown_tick.connect(_on_countdown)
	race.kart_finished.connect(func(k: Kart) -> void:
		if k.is_player:
			play("finish"))
	var items := get_node_or_null(items_path) as ItemSystem
	if items:
		items.item_used.connect(_on_item_used)


func _on_karts(karts: Array) -> void:
	for k: Kart in karts:
		_item_counts[k] = k.items.size()
		k.wall_hit.connect(_on_wall_hit)
		k.boosted.connect(_on_boosted)
		k.hit_taken.connect(_on_hit)
		k.items_changed.connect(_on_items_changed)
		k.landed.connect(_on_landed)
		k.landing_window_opened.connect(func(kk: Kart) -> void:
			if kk.is_player:
				play("ding", kk, 2.0))
		k.shield_blocked.connect(func(kk: Kart, _kind: String) -> void: play("shield", kk))


## Play a one-shot. Player events are 2D; other karts are 3D at their position
## (and skipped when far from the camera).
func play(name: String, at: Kart = null, volume_db := 0.0) -> void:
	if not streams.has(name):
		return
	if at != null and not at.is_player:
		if camera and camera.global_position.distance_to(at.global_position) > 45.0:
			return
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = streams[name]
		p3.volume_db = volume_db - 4.0
		p3.unit_size = 8.0
		p3.max_distance = 60.0
		at.add_child(p3)
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		var p := _free_player()
		p.stream = streams[name]
		p.volume_db = volume_db
		p.play()
	played.append(name)
	if played.size() > 200:
		played.remove_at(0)


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]


func _on_countdown(v: int) -> void:
	play("go" if v == 0 else "beep")


func _on_wall_hit(k: Kart, impact: float) -> void:
	play("wall", k, linear_to_db(clampf(0.35 + impact, 0.2, 1.0)))
	if k.is_player and camera:
		camera.add_trauma(0.25 * impact)


func _on_boosted(k: Kart, kind: String) -> void:
	if kind == "magnet":
		return
	play("mini" if kind == "mini" else "boost", k, -3.0)
	if k.is_player and camera:
		camera.kick_fov(FOV_KICK.get(kind, 4.0))


func _on_hit(k: Kart, kind: String) -> void:
	play(HIT_SOUND.get(kind, "hit"), k)
	if k.is_player and camera:
		camera.add_trauma(0.5)


func _on_landed(k: Kart, air: float) -> void:
	if k.is_player:
		play("land", k, -4.0)
		if camera:
			camera.add_trauma(0.15 * air)


func _on_items_changed(k: Kart) -> void:
	var n := k.items.size()
	if n > int(_item_counts.get(k, 0)) and k.is_player:
		play("pickup", k)
	_item_counts[k] = n


func _on_item_used(k: Kart, item: int) -> void:
	play("zap" if item == ItemDefs.LIGHTNING else "use", k, -2.0)
