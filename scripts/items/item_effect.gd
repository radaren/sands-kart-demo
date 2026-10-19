class_name ItemEffect
extends Node3D
## Base class for the 8 item scenes in res://scenes/items/.

var system: ItemSystem
var user: Kart
var target: Kart
var life := 5.0
var age := 0.0


func setup(sys: ItemSystem, owner_kart: Kart, target_kart: Kart) -> void:
	system = sys
	user = owner_kart
	target = target_kart


func _physics_process(delta: float) -> void:
	age += delta
	tick(delta)
	if age >= life:
		finish()


func tick(_delta: float) -> void:
	pass


func finish() -> void:
	if is_queued_for_deletion():
		return
	queue_free()


func threatens(_k: Kart) -> bool:
	return false


static func emissive(c: Color, energy := 2.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func add_mesh(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func ground_y_at(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 20.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else p.y
