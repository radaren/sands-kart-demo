class_name RaceManager
extends Node
## Race controller: spawns the 6 karts, countdown 3-2-1-GO, per-tick track
## projection (progress / lateral), checkpoints + wrong-way + auto respawn,
## live ranking, item boxes / boost pads, finish detection and results.
## Kart.race points here (race_clock, item_system, on_item_box()).

signal countdown_tick(value: int)        ## 3, 2, 1, 0 = GO
signal race_started
signal kart_finished(kart: Kart)
signal race_completed(results: Array)
signal restart_requested
signal title_requested
signal karts_spawned(karts: Array)

enum State { COUNTDOWN, RACING, FINISHED }

const KART_SCENE := preload("res://scenes/kart/kart.tscn")
const ITEM_TABLE := preload("res://data/item_table.tres")
const COUNTDOWN := 3.0
const SETTLE := 0.6            ## karts drop onto the grid before "3"
const RESULTS_WAIT := 12.0     ## after the player finishes, wait this long for the AI

const ROSTER := [
	# name, colour, aggression, defense, mistake_rate (per 5 s), lane, rival, skill
	["你", Color(0.92, 0.16, 0.12), 0.0, 0.0, 0.0, 0.0, false, 0.95],
	["阿蓝", Color(0.15, 0.4, 0.95), 0.45, 0.6, 0.18, -1.2, false, 0.8],
	["小黄", Color(1.0, 0.82, 0.1), 0.35, 0.3, 0.3, 1.4, false, 0.55],
	["绿洲", Color(0.2, 0.75, 0.3), 0.55, 0.7, 0.2, 0.6, false, 0.72],
	["橘子", Color(1.0, 0.5, 0.08), 0.6, 0.4, 0.25, -0.5, false, 0.62],
	["紫电", Color(0.6, 0.25, 0.9), 0.8, 0.5, 0.15, 0.2, true, 0.9],   # 宿敌 rival
]

@export var max_laps := 1
@export var track_builder_path: NodePath = ^"../SandsTrack"
@export var item_system_path: NodePath = ^"../ItemSystem"

var state := State.COUNTDOWN
var race_clock := 0.0           ## seconds since the scene started (used by Kart taps)
var go_clock := SETTLE + COUNTDOWN
var race_time := 0.0            ## seconds since GO
var countdown_value := 3
var karts: Array[Kart] = []
var player: Kart
var rankings: Array[String] = []
var ordered: Array = []
var finish_order: Array = []
var race_finished := false
var results: Array = []
var track: TrackData
var track_builder: TrackBuilder
var item_system: ItemSystem
var trackers := {}             ## Kart -> CheckpointTracker
var _stuck := {}
var _player_finish_clock := -1.0
var _rng := RandomNumberGenerator.new()
var _last_count := 4


func _ready() -> void:
	_rng.seed = GameConfig.rng_seed if GameConfig.rng_seed != 0 else int(Time.get_unix_time_from_system())
	max_laps = GameConfig.max_laps if GameConfig.max_laps > 0 else max_laps
	track_builder = get_node(track_builder_path) as TrackBuilder
	item_system = get_node_or_null(item_system_path) as ItemSystem
	track = track_builder.track if track_builder.track != null else TrackData.load_default()
	track_builder.item_box_collected.connect(_on_item_box_body)
	track_builder.boost_pad_entered.connect(_on_boost_pad_body)
	if item_system:
		item_system.race = self
	_spawn_karts.call_deferred()


func _spawn_karts() -> void:
	var root := get_parent()
	for i in ROSTER.size():
		var r: Array = ROSTER[i]
		var kart := KART_SCENE.instantiate() as Kart
		kart.name = "Player" if i == 0 else "AI_%d" % i
		kart.display_name = r[0]
		kart.body_color = r[1]
		kart.is_player = i == 0
		kart.race = self
		kart.track = track
		root.add_child(kart)
		var visual := KartVisual.new()
		visual.name = "Visual"
		kart.add_child(visual)
		visual.build(r[1], r[0])
		var slot := track.grid_slot(i)
		kart.place(track.spawn_transform(slot["s"], slot["offset"]))
		kart.progress = slot["s"]
		kart.track_index = track.index_at(slot["s"])
		if kart.is_player and not GameConfig.autopilot:
			var pi := PlayerInput.new()
			pi.name = "PlayerInput"
			pi.kart = kart
			kart.add_child(pi)
			kart.controller = pi
		else:
			var ai := AIDriver.new()
			ai.name = "AIDriver"
			ai.kart = kart
			ai.setup(_rng.randi() + i)
			if kart.is_player:
				ai.manual_items = true      # autopilot (tests): items still from Input
				ai.start_boost_chance = 1.0
				ai.skill = r[7]
				ai.mistake_rate = 0.0
			else:
				ai.aggression = r[2]
				ai.defense = r[3]
				ai.mistake_rate = r[4]
				ai.lane_offset = r[5]
				ai.is_rival = r[6]
				ai.skill = r[7]
				var rb := AIRubberBand.new()
				rb.name = "RubberBand"
				rb.kart = kart
				rb.race_manager = self
				kart.add_child(rb)
				if ai.is_rival:
					kart.base_speed_bias = 1.03
				kart.speed_scale = kart.base_speed_bias
			kart.add_child(ai)
			kart.controller = ai
			ai.plan_start(go_clock)
		trackers[kart] = CheckpointTracker.new(track.checkpoints, slot["s"])
		_stuck[kart] = 0.0
		karts.append(kart)
		if kart.is_player:
			player = kart
	for k in karts:
		var rb := k.get_node_or_null("RubberBand") as AIRubberBand
		if rb:
			rb.player = player
	_update_ranking()
	karts_spawned.emit(karts)


func is_racing() -> bool:
	return state == State.RACING


func _physics_process(delta: float) -> void:
	race_clock += delta
	if karts.is_empty():
		return
	match state:
		State.COUNTDOWN:
			var remaining := go_clock - race_clock
			var c := int(ceil(remaining))
			if race_clock >= SETTLE and c != _last_count and c >= 1 and c <= 3:
				_last_count = c
				countdown_value = c
				countdown_tick.emit(c)
			if race_clock >= go_clock:
				_go()
		State.RACING, State.FINISHED:
			race_time = race_clock - go_clock
	_track_karts(delta)
	_update_ranking()
	if state == State.RACING and _player_finish_clock >= 0.0:
		var all_done := finish_order.size() == karts.size()
		if all_done or race_clock - _player_finish_clock >= RESULTS_WAIT:
			_complete_race()


func _go() -> void:
	state = State.RACING
	countdown_value = 0
	race_time = 0.0
	countdown_tick.emit(0)
	for k in karts:
		k.on_race_go(race_clock)
	race_started.emit()


func _track_karts(delta: float) -> void:
	for k in karts:
		var proj := track.project(k.global_position, k.track_index, 14)
		k.track_index = proj["index"]
		k.lateral = proj["signed"]
		var tracker: CheckpointTracker = trackers[k]
		k.progress = tracker.update(float(proj["distance"]))
		# wrong way
		var tan := track.tangent_at(k.progress)
		if state == State.RACING and k.forward_dir().dot(tan) < -0.35 and absf(k.speed) > 3.0 and not k.finished:
			k.wrong_way_time += delta
		else:
			k.wrong_way_time = maxf(0.0, k.wrong_way_time - delta * 2.0)
		# fell off / stuck / wrong way (AI) -> respawn
		var ground_y := track.position_at(k.progress).y
		if k.global_position.y < ground_y - 12.0:
			k.respawn_on_track()
			continue
		if state == State.RACING and not k.finished and k.freeze_time <= 0.0 and k.stun_time <= 0.0:
			# stuck = barely moving in the world (also catches "speed > 0 but blocked")
			var moving := Vector2(k.get_real_velocity().x, k.get_real_velocity().z).length()
			_stuck[k] = (_stuck[k] + delta) if moving < 2.0 else 0.0
			if not (k.controller is PlayerInput):
				if _stuck[k] > 3.0 or k.wrong_way_time > 2.5:
					_stuck[k] = 0.0
					k.respawn_on_track()
		# finish line
		if state != State.COUNTDOWN and not k.finished and k.progress >= track.finish_offset and tracker.all_passed():
			_on_kart_finished(k)


func _on_kart_finished(k: Kart) -> void:
	k.finished = true
	k.finish_time = race_time
	finish_order.append(k)
	kart_finished.emit(k)
	if k == player:
		_player_finish_clock = race_clock
		k.announced.emit(k, "完赛! 第 %d 名" % (finish_order.size()), Kart.Tone.GOOD)
		if k.controller is PlayerInput:
			# hand the kart to an AI so it coasts down the run-out
			var ai := AIDriver.new()
			ai.kart = k
			ai.name = "AutoPilot"
			k.add_child(ai)
			k.controller = ai


func _update_ranking() -> void:
	ordered = RankingSystem.sort_karts(karts, finish_order)
	var names: Array[String] = []
	for k: Kart in ordered:
		names.append(String(k.name))
	rankings = names


func kart_ahead(k: Kart) -> Kart:
	if k.rank <= 1 or ordered.size() < k.rank:
		return null
	return ordered[k.rank - 2]


func kart_behind(k: Kart) -> Kart:
	if k.rank >= ordered.size():
		return null
	return ordered[k.rank]


func leader() -> Kart:
	return ordered[0] if not ordered.is_empty() else null


# ---------------------------------------------------------------- items / pads
func _on_item_box_body(body: Node3D) -> void:
	if body is Kart:
		(body as Kart).receive_item_box()


func on_item_box(k: Kart) -> void:
	if k.items.size() >= Kart.MAX_ITEMS:
		return
	var lead := leader()
	var gap := 0.0 if lead == null else lead.progress - k.progress
	var item := ITEM_TABLE.roll(k.rank, karts.size(), gap, _rng)
	if k.give_item(item) and k.is_player:
		k.announced.emit(k, "获得 " + ItemDefs.item_name(item), Kart.Tone.INFO)


func _on_boost_pad_body(body: Node3D) -> void:
	if body is Kart:
		var k := body as Kart
		k.add_boost("pad", k.config.pad_bonus, k.config.pad_time)
		if k.is_player:
			k.announced.emit(k, "加速带!", Kart.Tone.GOOD)


# ---------------------------------------------------------------- results
static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]


func _complete_race() -> void:
	state = State.FINISHED
	race_finished = true
	results.clear()
	for k: Kart in ordered:
		var t := k.finish_time
		var estimated := false
		if not k.finished:
			estimated = true
			t = race_time + maxf(0.0, track.finish_offset - k.progress) / maxf(absf(k.speed), 20.0)
		results.append({"rank": k.rank, "name": k.display_name, "node": String(k.name), "time": t,
				"time_text": ("≈" if estimated else "") + format_time(t), "player": k.is_player,
				"color": k.body_color, "finished": k.finished})
	race_completed.emit(results)


func request_restart() -> void:
	get_tree().paused = false
	if restart_requested.get_connections().is_empty():
		get_tree().reload_current_scene()
	else:
		restart_requested.emit()


func request_title() -> void:
	get_tree().paused = false
	if title_requested.get_connections().is_empty():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		title_requested.emit()
