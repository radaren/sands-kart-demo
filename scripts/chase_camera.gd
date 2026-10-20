class_name ChaseCamera
extends Camera3D
## Third-person chase camera on the player kart (B = look back).
## Runs in _process on the kart's *interpolated* transform (physics
## interpolation is on), with frame-rate independent exponential damping:
##  - heading is smoothed on its own (C2), look-back snaps instead of swinging
##    through the kart,
##  - follow distance is explicit (C3) instead of an emergent lag, with stiffer
##    horizontal than vertical damping.

@export var race_path: NodePath = ^"../RaceManager"
@export var base_distance := 6.2
@export var height := 2.6
@export var look_ahead := 6.0
@export var heading_rate := 6.0      ## 1/s, heading damping
@export var horiz_rate := 12.0
@export var vert_rate := 5.0

var race: RaceManager
var target_origin := Vector3.ZERO    ## last kart position used (interpolated), for tests
var _yaw := 0.0
var _pos := Vector3.ZERO
var _back := false
var _have := false
var _fov := 72.0


static func damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))


func _ready() -> void:
	race = get_node(race_path) as RaceManager
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = _fov
	far = 1500.0


func _kart_yaw(k: Kart) -> float:
	# blend travel direction and nose so drifts read without whipping the view
	return lerp_angle(k.move_yaw, k.facing_yaw, 0.4)


func _process(delta: float) -> void:
	var k: Kart = race.player if race else null
	if k == null:
		return
	var xf := k.get_global_transform_interpolated()
	target_origin = xf.origin
	var want_yaw := _kart_yaw(k)
	var back := k.look_back
	var snap := not _have or back != _back
	if snap:
		_yaw = want_yaw
	else:
		_yaw = lerp_angle(_yaw, want_yaw, 1.0 - exp(-heading_rate * delta))
	_back = back
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	if back:
		fwd = -fwd
	var frac := clampf(absf(k.speed) / k.config.max_speed, 0.0, 1.4)
	var boost := 1.0 if k.is_boosting() else 0.0
	var dist := base_distance + 1.0 * minf(frac, 1.0) + 0.8 * boost
	var want := xf.origin - fwd * dist + Vector3.UP * height
	if snap or _pos.distance_to(want) > 30.0:
		_pos = want
	else:
		_pos.x = damp(_pos.x, want.x, horiz_rate, delta)
		_pos.z = damp(_pos.z, want.z, horiz_rate, delta)
		_pos.y = damp(_pos.y, want.y, vert_rate, delta)
	_have = true
	global_position = _pos
	look_at(xf.origin + fwd * look_ahead + Vector3.UP * 1.0, Vector3.UP)
	var target_fov := 72.0 + clampf(frac, 0.0, 1.4) * 8.0 + 6.0 * boost
	_fov = damp(_fov, target_fov, 3.0, delta)
	fov = _fov
