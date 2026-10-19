class_name ChaseCamera
extends Camera3D
## Smooth third-person chase camera on the player kart (B = look back).

@export var race_path: NodePath = ^"../RaceManager"
@export var distance := 6.8
@export var height := 2.7
@export var look_ahead := 6.0

var race: RaceManager
var _fov := 72.0


func _ready() -> void:
	race = get_node(race_path) as RaceManager
	fov = _fov
	far = 1500.0


func _physics_process(delta: float) -> void:
	var k: Kart = race.player if race else null
	if k == null:
		return
	var fwd := k.move_dir().lerp(k.forward_dir(), 0.4).normalized()
	if k.look_back:
		fwd = -fwd
	var want := k.global_position - fwd * distance + Vector3.UP * height
	var t := clampf(delta * 8.0, 0.0, 1.0)
	if global_position.distance_to(want) > 30.0:
		global_position = want
	else:
		global_position = global_position.lerp(want, t)
	look_at(k.global_position + fwd * look_ahead + Vector3.UP * 1.0, Vector3.UP)
	var target_fov := 72.0 + clampf(absf(k.speed) / 30.0, 0.0, 1.4) * 8.0 + (6.0 if k.is_boosting() else 0.0)
	_fov = lerpf(_fov, target_fov, clampf(delta * 3.0, 0.0, 1.0))
	fov = _fov
