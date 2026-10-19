extends SceneTree
## godot --headless --path . --script res://tests/smoke_track.gd
func _initialize() -> void:
	var t: SandsTrack = load("res://scenes/track/sands_track.tscn").instantiate()
	root.add_child(t)
	await process_frame
	print("length=", t.length, " samples=", t.samples_p.size(), " curve_len=", t.curve.get_baked_length())
	print("checkpoints=", t.checkpoints.size(), " pads=", t.boost_pads.size(), " item_sites=", t.item_sites.size())
	for k in t.segments:
		print(k, " ", t.segments[k])
	var minr := 1e9
	for r in t.samples_r: minr = minf(minr, r)
	print("min radius=", minr, " heading@0=", t.heading_at(0), " p@100=", t.point_at(100), " closest=", t.closest_offset(t.point_at(1234.5) + t.right_at(1234.5) * 3.0, 1230.0))
	print("children=", t.get_child_count())
	quit()
