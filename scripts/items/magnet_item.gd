extends ItemEffect
## 磁铁: locks onto the kart ahead and pulls the user towards it for 2.5 s.

var beam: MeshInstance3D


func _ready() -> void:
	life = 2.5
	if target == null or not is_instance_valid(target):
		life = 0.1
		return
	if target.shield_time > 0.0:
		target.hit("magnet", 0.0, true)   # consumes the shield
		life = 0.1
		return
	var c := CylinderMesh.new(); c.top_radius = 0.12; c.bottom_radius = 0.12; c.height = 1.0
	beam = add_mesh(c, emissive(Color(0.9, 0.3, 0.45), 3.0, 0.6))


func tick(_d: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(user) or beam == null:
		return
	user.add_boost("magnet", 8.0, 0.15, 0.0)
	target.add_slow("magnet", 3.0, 0.15)
	var a := user.global_position + Vector3.UP * 1.0
	var b := target.global_position + Vector3.UP * 1.0
	var mid := (a + b) * 0.5
	var dist := a.distance_to(b)
	global_position = mid
	if dist > 0.1:
		look_at(b, Vector3.UP)
		beam.rotation = Vector3(PI / 2, 0, 0)
		beam.scale = Vector3(1, dist, 1)
