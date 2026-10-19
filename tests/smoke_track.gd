extends SceneTree
## godot --headless --path . --script res://tests/smoke_track.gd
func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var tb: TrackBuilder = load("res://scenes/track/sands_track.tscn").instantiate()
	root.add_child(tb)
	await process_frame
	var tr := tb.track
	print("built in ", Time.get_ticks_msec() - t0, " ms; length=", tr.length, " finish=", tr.finish_offset, " points=", tr.points.size())
	print("ramps=", tr.ramps, " boosts=", tr.boosts, " item_rows=", tr.item_rows)
	print("item boxes=", tb.item_box_nodes.size(), " children=", tb.get_child_count(), " town_end=", tb.town_end())
	var minr := 1e9
	for r in tr.curvature: minr = minf(minr, r)
	print("min radius=", minr)
	var kinds := {}
	for c in tb.get_children():
		var k: String = c.scene_file_path.get_file() if c.scene_file_path != "" else c.get_class()
		kinds[k] = kinds.get(k, 0) + 1
	print(kinds)
	quit()
