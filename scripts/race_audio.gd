class_name RaceAudio
extends Node
## Engine loop on every kart (3D, pitch by speed), drift friction for the
## player, BGM loop. Uses the delivered clips in assets/props_raw/audio_src
## (bgm_a/b there are 0.05 s stubs, so a procedural loop in assets/audio is used).

const ENGINE := "res://assets/props_raw/audio_src/engine_accel/main.wav"
const TIRE := "res://assets/props_raw/audio_src/tire_friction/main.wav"
const BGM := "res://assets/audio/bgm_desert_loop.wav"

@export var race_path: NodePath = ^"../RaceManager"
var race: RaceManager
var _engines := {}
var engine_pitch_mul := {}    ## W5: per-kart pitch spread (player 1.0, AIs 0.95-1.05)
var _arng := RandomNumberGenerator.new()   # cosmetic only, kept off the gameplay RNG
var _tire: AudioStreamPlayer
var _bgm: AudioStreamPlayer


static func looped(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		return w
	return s


func _ready() -> void:
	race = get_node(race_path) as RaceManager
	_bgm = AudioStreamPlayer.new()
	_bgm.stream = looped(BGM)
	_bgm.volume_db = -12.0
	add_child(_bgm)
	if _bgm.stream:
		_bgm.play()
	_tire = AudioStreamPlayer.new()
	_tire.stream = looped(TIRE)
	_tire.volume_db = -10.0
	add_child(_tire)


func _process(_d: float) -> void:
	if race == null:
		return
	var eng := looped(ENGINE) if _engines.is_empty() else null
	for k: Kart in race.karts:
		if not _engines.has(k):
			var p := AudioStreamPlayer3D.new()
			p.stream = eng if eng else looped(ENGINE)
			p.unit_size = 6.0
			p.max_distance = 80.0
			p.volume_db = -6.0 if k.is_player else -10.0
			k.add_child(p)
			# W5: start each loop at a random point and spread the pitch, so six
			# identical engines don't phase into one buzzing tone
			var length: float = p.stream.get_length() if p.stream else 0.0
			p.play(_arng.randf_range(0.0, maxf(length - 0.05, 0.0)))
			_engines[k] = p
			engine_pitch_mul[k] = 1.0 if k.is_player else _arng.randf_range(0.95, 1.05)
		var pl: AudioStreamPlayer3D = _engines[k]
		pl.pitch_scale = clampf((0.55 + absf(k.speed) / 28.0) * float(engine_pitch_mul[k]), 0.5, 2.1)
	if race.player and _tire.stream:
		var want := race.player.drifting
		if want and not _tire.playing:
			_tire.play()
		elif not want and _tire.playing:
			_tire.stop()
