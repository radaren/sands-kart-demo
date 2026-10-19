class_name ItemSystem
extends Node3D
## Item usage: Kart.use_item() -> race.item_system.use_item(kart, item).
## Pickup / rank-weighted rolls live in RaceManager.on_item_box (ItemTable).

const SCENES := {
	ItemDefs.NITRO: preload("res://scenes/items/nitro.tscn"),
	ItemDefs.MISSILE: preload("res://scenes/items/missile.tscn"),
	ItemDefs.MAGNET: preload("res://scenes/items/magnet.tscn"),
	ItemDefs.BANANA: preload("res://scenes/items/banana.tscn"),
	ItemDefs.CLOUD: preload("res://scenes/items/cloud.tscn"),
	ItemDefs.SHIELD: preload("res://scenes/items/shield.tscn"),
	ItemDefs.LIGHTNING: preload("res://scenes/items/lightning.tscn"),
	ItemDefs.UFO: preload("res://scenes/items/ufo.tscn"),
}

signal item_used(kart: Kart, item: int)
signal screen_flash(color: Color)

var race: RaceManager
var used_log: Array = []      ## [{kart, item, time}] for tests / debugging


func use_item(kart: Kart, item: int) -> void:
	if not SCENES.has(item) or race == null:
		return
	var target: Kart = null
	match item:
		ItemDefs.MISSILE, ItemDefs.MAGNET:
			target = race.kart_ahead(kart)
		ItemDefs.UFO:
			target = race.leader()
			if target == kart:
				target = race.kart_behind(kart)
	var fx := SCENES[item].instantiate() as ItemEffect
	fx.setup(self, kart, target)
	add_child(fx)
	used_log.append({"kart": String(kart.name), "item": ItemDefs.KEYS[item], "time": race.race_time})
	item_used.emit(kart, item)
	if kart.is_player:
		kart.announced.emit(kart, "使用 " + ItemDefs.item_name(item), Kart.Tone.INFO)


func is_threatened(kart: Kart) -> bool:
	for c in get_children():
		if c is ItemEffect and (c as ItemEffect).threatens(kart):
			return true
	return false


func spawn_burst(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 1.0; s.height = 2.0
	mi.mesh = s
	mi.material_override = ItemEffect.emissive(color, 4.0, 0.8)
	add_child(mi)
	mi.global_position = pos
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 3.0, 0.35)
	tw.tween_callback(mi.queue_free)


func flash(color: Color) -> void:
	screen_flash.emit(color)
