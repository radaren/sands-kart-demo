extends ItemEffect
## 导弹: homing missile at the kart directly ahead; tumbles it (1.4 s) unless shielded.
## I5: pops up off the kart's back, then accelerates (0 -> 58 m/s in 0.45 s) with a
## smoke trail and a flickering exhaust; explodes on impact; the target's HUD
## shows a red lock-on arrow and beeps faster as it closes in.

const TOP_SPEED := 58.0
var speed := 18.0
var dir := Vector3.FORWARD
var trail_puffs := 0
var _puff_t := 0.0
var flame: MeshInstance3D
var _launch := Vector3.ZERO


func _ready() -> void:
	life = 7.0
	dir = user.forward_dir()
	global_position = user.global_position + Vector3.UP * 1.1 - dir * 0.4
	_launch = Vector3.UP * 7.0 + dir * 4.0       # pop up, then tip over towards the target
	var body := CylinderMesh.new(); body.top_radius = 0.17; body.bottom_radius = 0.17; body.height = 1.2
	add_mesh(body, FxLib.solid("missile_body", Color(0.92, 0.92, 0.95), 0.3), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	var band := CylinderMesh.new(); band.top_radius = 0.18; band.bottom_radius = 0.18; band.height = 0.25
	add_mesh(band, FxLib.solid("missile_red", Color(0.9, 0.15, 0.12), 0.6), Vector3(0, 0, 0.2), Vector3(PI / 2, 0, 0))
	var tip := CylinderMesh.new(); tip.top_radius = 0.0; tip.bottom_radius = 0.17; tip.height = 0.45
	add_mesh(tip, FxLib.solid("missile_red", Color(0.9, 0.15, 0.12), 0.6), Vector3(0, 0, -0.82), Vector3(-PI / 2, 0, 0))
	var fin := BoxMesh.new(); fin.size = Vector3(0.7, 0.04, 0.3)
	add_mesh(fin, FxLib.solid("missile_red", Color(0.9, 0.15, 0.12), 0.6), Vector3(0, 0, 0.5))
	add_mesh(fin, FxLib.solid("missile_red", Color(0.9, 0.15, 0.12), 0.6), Vector3(0, 0, 0.5), Vector3(0, 0, PI / 2))
	var fl := CylinderMesh.new(); fl.top_radius = 0.16; fl.bottom_radius = 0.0; fl.height = 0.9
	flame = add_mesh(fl, FxLib.mat("missile_flame", Color(1.0, 0.65, 0.2)), Vector3(0, 0, 1.05), Vector3(PI / 2, 0, 0))
	FxLib.burst(system, global_position, Color(1.0, 0.8, 0.5), 14, 5.0, 0.35, 0.5, -2.0)



func threatens(k: Kart) -> bool:
	return k == target


## Distance to the target (for the lock-on warning); INF when not homing.
func distance_to_target() -> float:
	if not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)


func tick(delta: float) -> void:
	var goal := global_position + dir * 10.0
	if is_instance_valid(target):
		goal = target.global_position + Vector3.UP * 0.8
	if age < 0.2:
		# launch pop: up off the user's back, arcing over towards the target
		_launch.y -= 35.0 * delta
		global_position += _launch * delta
		dir = _launch.normalized()
	else:
		speed = move_toward(speed, TOP_SPEED, 90.0 * delta)
		var turn := clampf(delta * (6.0 if age > 0.35 else 3.0), 0.0, 1.0)
		dir = dir.slerp((goal - global_position).normalized(), turn).normalized()
		global_position += dir * speed * delta
	if dir.length_squared() > 0.01 and absf(dir.dot(Vector3.UP)) < 0.99:
		look_at(global_position + dir, Vector3.UP)
	flame.scale = Vector3.ONE * (0.8 + 0.4 * sin(age * 70.0))
	_puff_t -= delta
	if _puff_t <= 0.0:
		_puff_t = 0.025
		trail_puffs += 1
		FxLib.puff(system, global_position - dir * 1.0, FxLib.SMOKE, 0.9, 0.8)
	if is_instance_valid(target) and global_position.distance_to(goal) < 1.8:
		target.hit("missile", 1.4, true)
		explode()
		return
	if not is_instance_valid(target) and age > 2.5:
		explode()


func explode() -> void:
	FxLib.explosion(system, global_position, 1.0)
	system.exploded.emit(global_position)
	finish()
