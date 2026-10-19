extends Node
## Main: title screen -> race scene -> results -> restart / back to title.

const TITLE_SCENE := preload("res://scenes/ui/title.tscn")
const RACE_SCENE_PATH := "res://scenes/race/race.tscn"

var _current: Node


func _ready() -> void:
	show_title()


func _swap(node: Node) -> void:
	if _current:
		_current.queue_free()
	_current = node
	add_child(node)


func show_title() -> void:
	get_tree().paused = false
	var t := TITLE_SCENE.instantiate()
	t.start_requested.connect(start_race)
	_swap(t)


func start_race() -> void:
	get_tree().paused = false
	var race: Node = load(RACE_SCENE_PATH).instantiate()
	_swap(race)
	var rm := race.get_node("RaceManager")
	rm.restart_requested.connect(start_race, CONNECT_DEFERRED)
	rm.title_requested.connect(show_title, CONNECT_DEFERRED)
