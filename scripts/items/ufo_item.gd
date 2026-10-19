extends ItemEffect
## 飞碟: flies to the race leader and hovers over it for 4 s, slowing it down.

var arrived := false
var hover := 0.0


func _ready() -> void:
	life = 9.0
	global_position = user.global_position + Vector3.UP * 4.0
	var disc := CylinderMesh.new(); disc.top_radius = 1.0; disc.bottom_radius = 1.8; disc.height = 0.45
	add_mesh(disc, emissive(Color(0.4, 0.95, 0.45), 1.5))
	var dome := SphereMesh.new(); dome.radius = 0.75; dome.height = 0.9; dome.is_hemisphere = true
	add_mesh(dome, emissive(Color(0.8, 1.0, 0.9), 1.0, 0.7), Vector3(0, 0.2, 0))
	var beam := CylinderMesh.new(); beam.top_radius = 0.5; beam.bottom_radius = 1.6; beam.height = 3.0
	var bm := add_mesh(beam, emissive(Color(0.5, 1.0, 0.5), 1.5, 0.25), Vector3(0, -1.7, 0))
	bm.name = "Beam"
	bm.visible = false


func threatens(k: Kart) -> bool:
	return k == target and not arrived


func tick(delta: float) -> void:
	if not is_instance_valid(target):
		finish()
		return
	var goal := target.global_position + Vector3.UP * 3.6
	if not arrived:
		global_position = global_position.move_toward(goal, 80.0 * delta)
		if global_position.distance_to(goal) < 1.0:
			arrived = true
			if not target.hit("ufo", 0.0, true):
				finish()
				return
			get_node("Beam").visible = true
	else:
		global_position = goal
		hover += delta
		target.add_slow("ufo", 9.0, 0.15)
		if hover >= 4.0:
			finish()
	rotation.y += delta * 4.0
