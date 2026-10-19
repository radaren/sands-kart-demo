class_name MeshBatcher
extends RefCounted
## Merges many primitive meshes into one ArrayMesh per material (few draw calls).

var _tools := {}
var _mats := {}


func add(key: String, material: Material, mesh: Mesh, xf: Transform3D) -> void:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
		_mats[key] = material
	(_tools[key] as SurfaceTool).append_from(mesh, 0, xf)


func build(parent: Node3D, name_prefix: String, shadows := true) -> void:
	for key in _tools:
		var st: SurfaceTool = _tools[key]
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [name_prefix, key]
		mi.mesh = st.commit()
		mi.material_override = _mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
