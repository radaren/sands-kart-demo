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
signal exploded(pos: Vector3)
signal ufo_arrived(target: Kart)

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
	fx.reset_physics_interpolation()   # spawned at the kart, not lerped in from the origin
	used_log.append({"kart": String(kart.name), "item": ItemDefs.KEYS[item], "time": race.race_time})
	item_used.emit(kart, item)
	if kart.is_player:
		kart.announced.emit(kart, "使用 " + ItemDefs.item_name(item), Kart.Tone.INFO)


func is_threatened(kart: Kart) -> bool:
	for c in get_children():
		if c is ItemEffect and (c as ItemEffect).threatens(kart):
			return true
	return false


## Nearest homing missile locked on `kart` (metres), INF if none (H3 lock-on warning).
func incoming_missile(kart: Kart) -> float:
	var best := INF
	for c in get_children():
		if c is ItemEffect and c.has_method("distance_to_target") and (c as ItemEffect).target == kart:
			best = minf(best, c.distance_to_target())
	return best


func spawn_burst(pos: Vector3, color: Color) -> void:
	FxLib.flash_sphere(self, pos, color, 1.0, 0.35, 3.0)
	FxLib.burst(self, pos, color, 20, 8.0, 0.5, 0.4)


## Compile item shaders while the countdown runs (no hitch on the first use).
func prewarm(at: Vector3) -> void:
	FxLib.prewarm(self, at)


func flash(color: Color) -> void:
	screen_flash.emit(color)
