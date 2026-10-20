extends ItemEffect
## 香蕉皮: tossed behind the user in a short arc; the first kart that touches it
## spins out (I6: recognisable peel - 3 drooping flaps + stem, toss arc + bounce,
## the peel flies off when hit).

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _landed := false
var peel: Node3D


func _ready() -> void:
	life = 45.0
	_to = user.global_position - user.forward_dir() * 3.2
	_to.y = ground_y_at(_to) + 0.02
	_from = user.global_position + Vector3.UP * 1.2
	global_position = _from
	peel = Node3D.new()
	peel.scale = Vector3.ONE * 1.4
	add_child(peel)
	build_peel(peel)


static func build_peel(root: Node3D) -> void:
	var yellow := FxLib.solid("peel", Color(1.0, 0.86, 0.22))
	var brown := FxLib.solid("peel_tip", Color(0.35, 0.22, 0.08))
	var stub := CapsuleMesh.new(); stub.radius = 0.13; stub.height = 0.55
	var m := MeshInstance3D.new(); m.mesh = stub; m.material_override = yellow
	m.position = Vector3(0, 0.3, 0); root.add_child(m)
	var stem := CylinderMesh.new(); stem.top_radius = 0.04; stem.bottom_radius = 0.06; stem.height = 0.14
	var st := MeshInstance3D.new(); st.mesh = stem; st.material_override = brown
	st.position = Vector3(0, 0.62, 0); root.add_child(st)
	var flap := CapsuleMesh.new(); flap.radius = 0.12; flap.height = 0.7
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		var pivot := Node3D.new()
		pivot.rotation = Vector3(0, a, 0)
		root.add_child(pivot)
		var f := MeshInstance3D.new()
		f.mesh = flap
		f.material_override = yellow
		f.scale = Vector3(1.0, 1.0, 0.35)
		f.position = Vector3(0, 0.2, 0.3)
		f.rotation = Vector3(deg_to_rad(68), 0, 0)    # drooping outwards
		pivot.add_child(f)
		var tip := MeshInstance3D.new()
		var ts := SphereMesh.new(); ts.radius = 0.07; ts.height = 0.14
		tip.mesh = ts; tip.material_override = brown
		tip.position = Vector3(0, 0.05, 0.6)
		pivot.add_child(tip)


func tick(d: float) -> void:
	if not _landed:
		var t := clampf(age / 0.35, 0.0, 1.0)
		var p := _from.lerp(_to, t)
		p.y += sin(t * PI) * 1.2
		global_position = p
		peel.rotation.y += d * 14.0
		if t >= 1.0:
			_landed = true
			var tw := create_tween()
			tw.tween_property(peel, "scale", Vector3(1.75, 1.0, 1.75), 0.06)
			tw.tween_property(peel, "scale", Vector3.ONE * 1.4, 0.12)
		return
	peel.rotation.y += d * 0.6
	for k: Kart in system.race.karts:
		if k == user and age < 0.8:
			continue
		if k.global_position.distance_to(global_position) < 1.7:
			k.hit("banana", 0.9, true)
			_fly_off(k)
			finish()
			return


func _fly_off(k: Kart) -> void:
	# the peel pops into the air and spins away
	var fly := Node3D.new()
	system.add_child(fly)
	fly.global_position = global_position
	build_peel(fly)
	var side := k.forward_dir().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	var tw := fly.create_tween().set_parallel(true)
	tw.tween_property(fly, "global_position", global_position + Vector3.UP * 2.5 + side * 2.0 + k.forward_dir() * 3.0, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(fly, "rotation", Vector3(TAU * 1.5, TAU, 0), 0.6)
	tw.tween_property(fly, "scale", Vector3.ONE * 0.01, 0.6).set_delay(0.2)
	tw.chain().tween_callback(fly.queue_free)
	FxLib.burst(system, global_position + Vector3.UP * 0.3, Color(1.0, 0.9, 0.4), 12, 4.0, 0.4, 0.3)
