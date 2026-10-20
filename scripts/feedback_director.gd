class_name FeedbackDirector
extends Node
## One place that turns game events into feedback (W3): sound effects, camera
## shake (trauma) and FOV kicks. Subscribes to kart / item / race signals;
## gameplay code never calls audio or camera directly.

const SFX_DIR := "res://assets/audio/sfx/"
const SFX := ["beep", "go", "boost", "mini", "wall", "pickup", "use", "explode", "hit",
		"zap", "shield", "slip", "warn", "finish", "land", "ding", "launch", "toss", "puff",
		"magnet", "ufo", "roll", "shatter", "scrape", "bump", "thunder"]
## I5-I9: every item has its own use sound
const USE_SOUND := {ItemDefs.MISSILE: "launch", ItemDefs.BANANA: "toss", ItemDefs.CLOUD: "puff",
		ItemDefs.SHIELD: "shield", ItemDefs.LIGHTNING: "thunder", ItemDefs.MAGNET: "magnet",
		ItemDefs.UFO: "launch", ItemDefs.NITRO: "use"}
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
var _items: ItemSystem
var _lock_beep := 0.0
var _scrape: AudioStreamPlayer
var bumps_seen := 0
const SPARK := Color(1.0, 0.92, 0.45)


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
	# V1/K9: looping scrape for the player grinding along a wall
	_scrape = AudioStreamPlayer.new()
	if streams.has("scrape"):
		var w := (streams["scrape"] as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
		_scrape.stream = w
	_scrape.volume_db = -60.0
	add_child(_scrape)
	race.karts_spawned.connect(_on_karts)
	race.countdown_tick.connect(_on_countdown)
	race.kart_finished.connect(func(k: Kart) -> void:
		if k.is_player:
			play("finish"))
	var items := get_node_or_null(items_path) as ItemSystem
	if items:
		_items = items
		items.item_used.connect(_on_item_used)
		items.exploded.connect(_on_exploded)
		items.ufo_arrived.connect(func(t: Kart) -> void: play("ufo", t, -2.0))


func _on_karts(karts: Array) -> void:
	for k: Kart in karts:
		_item_counts[k] = k.items.size()
		k.wall_hit.connect(_on_wall_hit)
		k.bumped.connect(_on_bumped)
		k.boosted.connect(_on_boosted)
		k.hit_taken.connect(_on_hit)
		k.items_changed.connect(_on_items_changed)
		k.landed.connect(_on_landed)
		k.landing_window_opened.connect(func(kk: Kart) -> void:
			if kk.is_player:
				play("ding", kk, 2.0))
		k.shield_blocked.connect(func(kk: Kart, _kind: String) -> void:
			play("shatter", kk)
			if kk.is_player and camera:
				camera.add_trauma(0.25))


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


func _fx_root() -> Node:
	return get_parent()


func _on_wall_hit(k: Kart, impact: float) -> void:
	play("wall", k, linear_to_db(clampf(0.35 + impact, 0.2, 1.0)))
	# sparks fly off the wall, more for harder hits
	FxLib.burst(_fx_root(), k.wall_point + Vector3.UP * 0.3, SPARK, int(12 + 36 * impact), 6.0 + 8.0 * impact, 0.5, 0.42, -14.0)
	if k.is_player and camera:
		camera.add_trauma(0.25 * impact)


## K10: kart-kart bump: thud + sparks at the contact, small shake for the player.
func _on_bumped(k: Kart, other: Kart, strength: float, point: Vector3) -> void:
	bumps_seen += 1
	play("bump", k if not other.is_player else other, linear_to_db(clampf(0.4 + strength, 0.3, 1.0)))
	FxLib.burst(_fx_root(), point + Vector3.UP * 0.2, SPARK, int(10 + 20 * strength), 5.0 + 5.0 * strength, 0.4, 0.38, -14.0)
	if (k.is_player or other.is_player) and camera:
		camera.add_trauma(0.12 + 0.2 * strength)


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
	# lightning is heard by everyone (it strikes the whole field ahead)
	play(USE_SOUND.get(item, "use"), null if item == ItemDefs.LIGHTNING else k, -2.0)


func _on_exploded(pos: Vector3) -> void:
	if camera:
		var d := camera.global_position.distance_to(pos)
		if d < 30.0:
			camera.add_trauma(0.35 * (1.0 - d / 30.0))


## H3: missile lock-on beep for the player, faster as it closes in.
func _process(delta: float) -> void:
	if race.player == null:
		return
	_update_scrape(delta)
	if _items == null:
		return
	var d := _items.incoming_missile(race.player)
	if d == INF:
		_lock_beep = 0.0
		return
	_lock_beep -= delta
	if _lock_beep <= 0.0:
		play("warn", null, -4.0)
		_lock_beep = lerpf(0.08, 0.4, clampf(d / 120.0, 0.0, 1.0))


var _scrape_fx := 0.0


func _update_scrape(delta: float) -> void:
	var p := race.player
	var on := p.scraping and not p.finished
	var target := linear_to_db(clampf(absf(p.speed) / 30.0, 0.15, 0.9)) if on else -60.0
	_scrape.volume_db = move_toward(_scrape.volume_db, target, delta * (200.0 if on else 120.0))
	if on and not _scrape.playing and _scrape.stream:
		_scrape.play()
	elif not on and _scrape.playing and _scrape.volume_db <= -59.0:
		_scrape.stop()
	# grinding sparks for every kart near the camera
	_scrape_fx -= delta
	if _scrape_fx > 0.0:
		return
	_scrape_fx = 0.05
	for k in race.karts:
		if k.scraping and (camera == null or camera.global_position.distance_to(k.global_position) < 40.0):
			FxLib.burst(_fx_root(), k.wall_point + Vector3.UP * 0.25, SPARK, 6, 4.0 + absf(k.speed) * 0.12, 0.35, 0.32, -12.0, 60.0)
