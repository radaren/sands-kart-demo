@tool
class_name ProceduralProp
extends Node3D
## Stand-in for the Grape-generated architecture (Grape is not available in
## this environment): sandstone mud houses, ruin pillars, broken columns, an
## arch, a pyramid and sand rocks, built from primitives in _ready().
## Scenes in res://scenes/props/ wrap this with a `kind`; data/grape_props.json
## points TrackBuilder at them, so real Grape .scn files can replace them later
## by just editing the manifest path.

@export_enum("mud_house", "ruin_pillar", "column_broken", "arch_ruin", "pyramid", "sand_rock", "obelisk") var kind := "mud_house"
@export var variant := 0
@export var span := 15.0     ## arch inner width

static var _mats := {}


static func mat(c: Color, rough := 0.88) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, pos, c, rot)


func _mi(mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _ready() -> void:
	for c in get_children():
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var stone_choices: Array[Color] = [Color(0.86, 0.68, 0.45), Color(0.8, 0.6, 0.4), Color(0.9, 0.76, 0.55)]
	var stone: Color = stone_choices[variant % 3]
	var trim := Color(0.66, 0.45, 0.28)
	var dark := Color(0.2, 0.13, 0.09)
	match kind:
		"mud_house":
			var w := 7.0 + variant * 2.0
			var d := 6.0 + variant * 1.5
			var h := 4.5 + variant * 1.8
			_box(Vector3(w, h, d), Vector3(0, h * 0.5, 0), stone)
			for z in [-d * 0.5, d * 0.5]:
				_box(Vector3(w + 0.3, 0.55, 0.35), Vector3(0, h + 0.27, z), trim)
			for x in [-w * 0.5, w * 0.5]:
				_box(Vector3(0.35, 0.55, d), Vector3(x, h + 0.27, 0), trim)
			for side in [-1.0, 1.0]:
				_box(Vector3(1.3, 2.2, 0.1), Vector3(0, 1.1, side * (d * 0.5 + 0.04)), dark)
				for k in [-0.32, 0.32]:
					_box(Vector3(0.9, 1.0, 0.1), Vector3(w * k, h * 0.62, side * (d * 0.5 + 0.04)), dark)
				_box(Vector3(2.2, 0.1, 1.1), Vector3(0, 2.55, side * (d * 0.5 + 0.55)), Color(0.82, 0.25, 0.16), Vector3(side * 0.25, 0, 0))
			if variant == 1:
				_box(Vector3(w * 0.45, h * 0.6, d * 0.6), Vector3(w * 0.55, h * 0.3, -d * 0.1), stone)
			if variant == 2:
				var dome := SphereMesh.new(); dome.radius = minf(w, d) * 0.32; dome.height = minf(w, d) * 0.32; dome.is_hemisphere = true
				_mi(dome, Vector3(0, h, 0), Color(0.3, 0.6, 0.65))
			for k in 3:
				_box(Vector3(0.2, 0.2, 0.9), Vector3(-w * 0.3 + k * w * 0.3, h - 0.6, d * 0.5 + 0.4), Color(0.45, 0.3, 0.18))
		"ruin_pillar", "obelisk":
			var h2 := 7.0 + variant * 2.5 + rng.randf() * 2.0
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.75 if kind == "ruin_pillar" else 0.25
			cyl.bottom_radius = 1.0
			cyl.height = h2
			cyl.radial_segments = 8 if kind == "ruin_pillar" else 4
			_mi(cyl, Vector3(0, h2 * 0.5, 0), stone, Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06)))
			_box(Vector3(2.4, 0.6, 2.4), Vector3(0, 0.3, 0), trim)
			if kind == "ruin_pillar":
				_box(Vector3(2.0, 0.5, 2.0), Vector3(0, h2 + 0.2, 0), trim)
			else:
				var tip := CylinderMesh.new(); tip.top_radius = 0.0; tip.bottom_radius = 0.36; tip.height = 1.0; tip.radial_segments = 4
				_mi(tip, Vector3(0, h2 + 0.5, 0), Color(0.95, 0.8, 0.35))
		"column_broken":
			var cyl2 := CylinderMesh.new(); cyl2.top_radius = 0.8; cyl2.bottom_radius = 0.85; cyl2.height = 3.2; cyl2.radial_segments = 10
			_mi(cyl2, Vector3(0, 1.6, 0), stone)
			var drum := CylinderMesh.new(); drum.top_radius = 0.8; drum.bottom_radius = 0.8; drum.height = 1.6; drum.radial_segments = 10
			_mi(drum, Vector3(2.2, 0.8, 0.6), stone, Vector3(0, 0.4, PI / 2))
			_box(Vector3(2.2, 0.5, 2.2), Vector3(0, 0.25, 0), trim)
		"arch_ruin":
			var r := span * 0.5
			for sd in [-1.0, 1.0]:
				_box(Vector3(1.6, 8.0, 1.6), Vector3(sd * (r + 0.8), 4.0, 0), stone)
				_box(Vector3(2.1, 0.6, 2.1), Vector3(sd * (r + 0.8), 8.2, 0), trim)
			var segs := 12
			for k in segs:
				var t0 := PI * float(k) / segs
				var t1 := PI * float(k + 1) / segs
				var tm := (t0 + t1) * 0.5
				var p := Vector3(cos(tm) * (r + 0.8), 8.5 + sin(tm) * r * 0.42, 0)
				var seg_len := (r + 0.8) * (t1 - t0) * 1.2
				var tilt := atan2(cos(tm) * 0.42, sin(tm))
				_box(Vector3(seg_len, 1.0, 1.4), p, stone, Vector3(0, 0, tilt))
			_box(Vector3(span * 0.5, 1.4, 0.25), Vector3(0, 8.6 + r * 0.42, 0.75), Color(0.82, 0.25, 0.16))
		"pyramid":
			var pm := CylinderMesh.new()
			pm.top_radius = 0.0; pm.bottom_radius = 30.0 + variant * 8.0; pm.height = 26.0 + variant * 6.0; pm.radial_segments = 4
			_mi(pm, Vector3(0, pm.height * 0.5 - 1.0, 0), Color(0.88, 0.72, 0.48), Vector3(0, PI / 4, 0))
		"sand_rock":
			var sm := SphereMesh.new(); sm.radius = 1.6; sm.height = 2.4; sm.radial_segments = 7; sm.rings = 4
			for k in 3:
				var s := 1.0 - k * 0.25
				_mi(sm, Vector3(k * 1.2 - 1.0, 0.6 * s, rng.randf_range(-0.8, 0.8)), Color(0.7, 0.52, 0.35), Vector3(0, rng.randf() * 3.0, 0)).scale = Vector3(1.4, 0.9 + variant * 0.3, 1.1) * s
