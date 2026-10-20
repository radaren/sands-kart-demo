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
var _fov := 70.0
var trauma := 0.0            ## 0..1, shake = trauma^2 * noise (C5)
var fov_kick := 0.0          ## extra degrees, decays over ~0.35 s (C4)
var _shake_t := 0.0
var _noise := FastNoiseLite.new()
var _fin_t := -1.0          ## seconds since the player finished (orbit mode)
var _orbit_yaw := 0.0


static func damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))


## Feedback hooks (FeedbackDirector): trauma accumulates, FOV kick takes the max.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func kick_fov(degrees: float) -> void:
	fov_kick = maxf(fov_kick, degrees)


func _ready() -> void:
	_noise.seed = 3
	_noise.frequency = 1.6
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
	if k.finished and _have:
		_finish_orbit(k, xf, delta)
		return
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
	# continuous nitro rumble
	if k.boosts.has("nitro"):
		trauma = maxf(trauma, 0.08 ** 0.5)
	var shake := Vector3.ZERO
	var roll := 0.0
	if trauma > 0.0:
		_shake_t += delta * 60.0
		var amp := trauma * trauma
		shake = Vector3(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t), 0.0) * 0.45 * amp
		roll = _noise.get_noise_2d(_shake_t, _shake_t) * 0.05 * amp
		trauma = maxf(0.0, trauma - 1.4 * delta)
	global_position = _pos
	look_at(xf.origin + fwd * look_ahead + Vector3.UP * 1.0, Vector3.UP)
	if shake != Vector3.ZERO:
		global_position += global_basis * shake
		rotate_object_local(Vector3.FORWARD, roll)
	# C4: base 70, up to +12 with speed, plus a decaying kick on boost start
	var target_fov := 70.0 + 12.0 * minf(frac, 1.0)
	_fov = damp(_fov, target_fov, 4.0, delta)
	fov_kick = move_toward(fov_kick, 0.0, delta * maxf(fov_kick, 1.0) / 0.35)
	fov = _fov + fov_kick


## Post-finish: ease from the chase view into a slow orbit around the kart,
## pulled in front of any wall/building between kart and camera (no clipping),
## no shake.
func _finish_orbit(k: Kart, xf: Transform3D, delta: float) -> void:
	if _fin_t < 0.0:
		_fin_t = 0.0
		_orbit_yaw = _yaw
	_fin_t += delta
	_orbit_yaw += 0.22 * delta * clampf(_fin_t / 2.0, 0.0, 1.0)
	var back := Vector3(sin(_orbit_yaw), 0.0, cos(_orbit_yaw))     # = -forward of the orbit heading
	var pivot := xf.origin + Vector3.UP * 1.0
	var want := xf.origin + back * 8.0 + Vector3.UP * 3.6    # above the other (ghosted) karts
	var space := get_world_3d().direct_space_state if get_world_3d() else null
	if space:
		var q := PhysicsRayQueryParameters3D.create(pivot, want, Kart.LAYER_WORLD | Kart.LAYER_WALL)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			want = (hit["position"] as Vector3) + (pivot - want).normalized() * 0.5
	_pos.x = damp(_pos.x, want.x, 3.0, delta)
	_pos.z = damp(_pos.z, want.z, 3.0, delta)
	_pos.y = damp(_pos.y, want.y, 3.0, delta)
	trauma = 0.0
	fov_kick = 0.0
	_fov = damp(_fov, 64.0, 2.0, delta)
	fov = _fov
	global_position = _pos
	look_at(pivot, Vector3.UP)
