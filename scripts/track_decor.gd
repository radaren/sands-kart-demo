class_name TrackDecor
extends RefCounted
## Procedural replacements for the Grape buildings / pillars / arches and the
## cloud vegetation assets (cacti, palms, rocks). Everything is merged per material.

static func _m(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(sx, sy, sz); return b


static func _xf(pos: Vector3, yaw := 0.0, scl := Vector3.ONE, extra := Basis.IDENTITY) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * extra * Basis.from_scale(scl), pos)


static func build(root: Node3D, decor: Dictionary, terrain_h: Callable) -> void:
	var mb := MeshBatcher.new()
	var sand_stone := [_m(Color(0.86, 0.68, 0.45)), _m(Color(0.8, 0.6, 0.4)), _m(Color(0.9, 0.76, 0.55))]
	var trim := _m(Color(0.66, 0.45, 0.28))
	var dark := _m(Color(0.18, 0.12, 0.09))
	var dome_m := _m(Color(0.3, 0.6, 0.65), 0.5)
	var cactus_m := _m(Color(0.28, 0.55, 0.22))
	var cactus_d := _m(Color(0.22, 0.45, 0.18))
	var trunk_m := _m(Color(0.55, 0.38, 0.22))
	var leaf_m := _m(Color(0.25, 0.6, 0.2))
	var rock_m := _m(Color(0.62, 0.45, 0.32), 0.95)
	var pillar_m := _m(Color(0.76, 0.56, 0.36))
	var cloth := _m(Color(0.85, 0.25, 0.18))

	# ---- buildings (rect / L footprint, flat roof with parapet, windows, optional dome)
	var i := 0
	for b in decor.get("buildings", []):
		i += 1
		var key := "stone%d" % (i % 3)
		var m: Material = sand_stone[i % 3]
		var base := Vector3(b.x, b.y - 0.5, b.z)
		var yaw: float = b.rot
		var w: float = b.w; var d: float = b.d; var h: float = b.h
		mb.add(key, m, _box(w, h, d), _xf(base + Vector3(0, h * 0.5, 0), yaw))
		if b.lshape:
			var off := Basis(Vector3.UP, yaw) * Vector3(w * 0.35, 0, d * 0.6)
			mb.add(key, m, _box(w * 0.4, h * 0.7, d * 0.6), _xf(base + off + Vector3(0, h * 0.35, 0), yaw))
		# parapet
		for side in [Vector3(0, 0, d * 0.5), Vector3(0, 0, -d * 0.5)]:
			mb.add("trim", trim, _box(w, 0.6, 0.3), _xf(base + Basis(Vector3.UP, yaw) * side + Vector3(0, h + 0.3, 0), yaw))
		for side in [Vector3(w * 0.5, 0, 0), Vector3(-w * 0.5, 0, 0)]:
			mb.add("trim", trim, _box(0.3, 0.6, d), _xf(base + Basis(Vector3.UP, yaw) * side + Vector3(0, h + 0.3, 0), yaw))
		# windows + door on both long faces
		var floors := int(h / 3.2)
		for f in floors:
			for k in [-0.3, 0.0, 0.3]:
				for face in [-1, 1]:
					var p := Vector3(w * k, 1.8 + f * 3.0, face * (d * 0.5 + 0.02))
					mb.add("dark", dark, _box(0.9, 1.2, 0.08), _xf(base + Basis(Vector3.UP, yaw) * p, yaw))
		for face in [-1, 1]:
			mb.add("dark", dark, _box(1.4, 2.2, 0.1), _xf(base + Basis(Vector3.UP, yaw) * Vector3(0, 1.1, face * (d * 0.5 + 0.03)), yaw))
			mb.add("cloth", cloth, _box(2.2, 0.12, 1.2), _xf(base + Basis(Vector3.UP, yaw) * Vector3(0, 2.6, face * (d * 0.5 + 0.6)), yaw, Vector3.ONE, Basis(Vector3.RIGHT, face * 0.25)))
		if b.dome:
			var dm := SphereMesh.new(); dm.radius = minf(w, d) * 0.3; dm.height = minf(w, d) * 0.3; dm.is_hemisphere = true
			mb.add("dome", dome_m, dm, _xf(base + Vector3(0, h, 0), yaw))

	# ---- arches (two pillars + segmented semicircle) spanning the road
	for a in decor.get("arches", []):
		var span: float = a.span
		var yaw: float = a.rot
		var c := Vector3(a.x, a.y, a.z)
		var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		for sd in [-1, 1]:
			mb.add("pillar", pillar_m, _box(1.6, 9.0, 1.6), _xf(c + right * sd * span * 0.5 + Vector3(0, 4.0, 0), yaw))
			mb.add("trim", trim, _box(2.0, 0.6, 2.0), _xf(c + right * sd * span * 0.5 + Vector3(0, 8.6, 0), yaw))
		var segs := 14
		var r := span * 0.5
		for k in segs:
			var t0 := PI * float(k) / segs
			var t1 := PI * float(k + 1) / segs
			var tm := (t0 + t1) * 0.5
			var p := c + right * cos(tm) * r + Vector3(0, 8.9 + sin(tm) * r * 0.45, 0)
			var seg_len := r * (t1 - t0) * 1.15
			var tilt := atan2(cos(tm) * 0.45, -sin(tm))
			mb.add("pillar", pillar_m, _box(seg_len, 1.1, 1.4), _xf(p, yaw, Vector3.ONE, Basis(Vector3.BACK, -tilt)))
		var banner := _box(span * 0.55, 1.6, 0.3)
		mb.add("cloth", cloth, banner, _xf(c + Vector3(0, 9.3 + r * 0.45, 0), yaw))

	# ---- stone pillars (散落石柱)
	for p in decor.get("pillars", []):
		var cyl := CylinderMesh.new()
		cyl.top_radius = p.r * 0.75; cyl.bottom_radius = p.r; cyl.height = p.h; cyl.radial_segments = 8
		var tilt := Basis(Vector3.RIGHT, p.tilt) * Basis(Vector3.FORWARD, p.tilt * 0.5)
		var pos := Vector3(p.x, p.y + p.h * 0.5, p.z)
		mb.add("pillar", pillar_m, cyl, _xf(pos, p.tilt * 10.0, Vector3.ONE, tilt))
		mb.add("trim", trim, _box(p.r * 2.0, 0.6, p.r * 2.0), _xf(pos + tilt * Vector3(0, p.h * 0.5, 0), p.tilt * 10.0, Vector3.ONE, tilt))

	# ---- cacti
	var cap := CapsuleMesh.new(); cap.radius = 0.35; cap.height = 3.0; cap.radial_segments = 8; cap.rings = 2
	var arm := CapsuleMesh.new(); arm.radius = 0.25; arm.height = 1.6; arm.radial_segments = 6; arm.rings = 2
	var barrel := SphereMesh.new(); barrel.radius = 0.7; barrel.height = 1.2; barrel.radial_segments = 8; barrel.rings = 4
	for c in decor.get("cacti", []):
		var y: float = terrain_h.call(c.x, c.z)
		var s: float = c.scale
		var pos := Vector3(c.x, y, c.z)
		var key := "cactus" if int(c.variant) % 2 == 0 else "cactus_d"
		var mm: Material = cactus_m if key == "cactus" else cactus_d
		if int(c.variant) == 5:
			mb.add(key, mm, barrel, _xf(pos + Vector3(0, 0.5 * s, 0), c.rot, Vector3.ONE * s))
			continue
		mb.add(key, mm, cap, _xf(pos + Vector3(0, 1.4 * s, 0), c.rot, Vector3.ONE * s))
		var arms := int(c.variant) % 3
		for k in arms + 1:
			var sd := 1.0 if k % 2 == 0 else -1.0
			var hgt := (1.2 + 0.5 * k) * s
			var dirv := Basis(Vector3.UP, c.rot) * Vector3(sd, 0, 0)
			mb.add(key, mm, _box(0.7 * s, 0.35 * s, 0.35 * s), _xf(pos + dirv * 0.45 * s + Vector3(0, hgt, 0), c.rot))
			mb.add(key, mm, arm, _xf(pos + dirv * 0.8 * s + Vector3(0, hgt + 0.6 * s, 0), c.rot, Vector3.ONE * s))

	# ---- palms
	var seg := CylinderMesh.new(); seg.top_radius = 0.22; seg.bottom_radius = 0.3; seg.height = 1.6; seg.radial_segments = 6
	var leaf := _box(0.9, 0.08, 3.6)
	var nut := SphereMesh.new(); nut.radius = 0.22; nut.height = 0.44; nut.radial_segments = 6; nut.rings = 3
	for pl in decor.get("palms", []):
		var y: float = terrain_h.call(pl.x, pl.z)
		var s: float = pl.scale
		var lean := 0.12 + 0.05 * int(pl.variant)
		var dirv := Basis(Vector3.UP, pl.rot) * Vector3(1, 0, 0)
		var p := Vector3(pl.x, y, pl.z)
		var top := p
		for k in 5:
			var q := p + dirv * (lean * k * k * 0.35 * s) + Vector3(0, (0.8 + 1.5 * k) * s, 0)
			mb.add("trunk", trunk_m, seg, _xf(q, pl.rot, Vector3.ONE * s, Basis(Vector3.BACK, -lean * k * 0.3)))
			top = q + Vector3(0, 0.8 * s, 0)
		for k in 7:
			var a: float = TAU * k / 7.0 + pl.rot
			var ld := Vector3(sin(a), 0, cos(a))
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.45)
			mb.add("leaf", leaf_m, leaf, Transform3D(b * Basis.from_scale(Vector3.ONE * s), top + ld * 1.5 * s - Vector3(0, 0.5 * s, 0)))
		for k in 3:
			var a2 := TAU * k / 3.0
			mb.add("trunk", trunk_m, nut, _xf(top + Vector3(sin(a2) * 0.3, -0.3, cos(a2) * 0.3) * s, 0.0))

	# ---- rocks
	var rk := SphereMesh.new(); rk.radius = 1.0; rk.height = 1.4; rk.radial_segments = 7; rk.rings = 4
	for r in decor.get("rocks", []):
		var y: float = terrain_h.call(r.x, r.z)
		var s: float = r.scale * (1.0 + int(r.variant) * 0.6)
		mb.add("rock", rock_m, rk, _xf(Vector3(r.x, y + 0.2 * s, r.z), r.rot, Vector3(1.4, 0.8 + 0.2 * int(r.variant), 1.1) * s))

	mb.build(root, "Decor")
