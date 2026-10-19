extends ItemEffect
## 导弹: homing missile at the kart directly ahead; stuns 1.4 s unless shielded.

var speed := 58.0
var dir := Vector3.FORWARD


func _ready() -> void:
	life = 7.0
	dir = user.forward_dir()
	global_position = user.global_position + Vector3.UP * 1.4 + dir * 2.0
	var body := CylinderMesh.new(); body.top_radius = 0.18; body.bottom_radius = 0.18; body.height = 1.3
	add_mesh(body, emissive(Color(0.95, 0.25, 0.2), 1.5), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	var tip := CylinderMesh.new(); tip.top_radius = 0.0; tip.bottom_radius = 0.18; tip.height = 0.4
	add_mesh(tip, emissive(Color(1, 1, 1), 1.0), Vector3(0, 0, -0.85), Vector3(-PI / 2, 0, 0))
	var flame := SphereMesh.new(); flame.radius = 0.25; flame.height = 0.5
	add_mesh(flame, emissive(Color(1.0, 0.6, 0.1), 5.0), Vector3(0, 0, 0.8))


func threatens(k: Kart) -> bool:
	return k == target


func tick(delta: float) -> void:
	var goal: Vector3
	if is_instance_valid(target):
		goal = target.global_position + Vector3.UP * 0.8
		dir = dir.slerp((goal - global_position).normalized(), clampf(delta * 6.0, 0.0, 1.0)).normalized()
	global_position += dir * speed * delta
	if dir.length_squared() > 0.01:
		look_at(global_position + dir, Vector3.UP)
	if is_instance_valid(target) and global_position.distance_to(goal) < 1.8:
		target.hit("missile", 1.4, true)
		system.spawn_burst(global_position, Color(1.0, 0.5, 0.15))
		finish()
