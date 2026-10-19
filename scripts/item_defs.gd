class_name ItemDefs
extends RefCounted
## Item ids, names and colours shared by gameplay, AI and HUD.

const NONE := 0
const NITRO := 1
const MISSILE := 2
const MAGNET := 3
const BANANA := 4
const CLOUD := 5
const SHIELD := 6
const LIGHTNING := 7
const UFO := 8

const ALL := [NITRO, MISSILE, MAGNET, BANANA, CLOUD, SHIELD, LIGHTNING, UFO]

const NAMES := {
	NITRO: "氮气",
	MISSILE: "导弹",
	MAGNET: "磁铁",
	BANANA: "香蕉皮",
	CLOUD: "云雾",
	SHIELD: "护盾",
	LIGHTNING: "闪电",
	UFO: "飞碟",
}

const KEYS := {
	NITRO: "nitro",
	MISSILE: "missile",
	MAGNET: "magnet",
	BANANA: "banana",
	CLOUD: "cloud",
	SHIELD: "shield",
	LIGHTNING: "lightning",
	UFO: "ufo",
}

const COLORS := {
	NITRO: Color(0.25, 0.65, 1.0),
	MISSILE: Color(0.95, 0.25, 0.2),
	MAGNET: Color(0.9, 0.3, 0.45),
	BANANA: Color(1.0, 0.85, 0.2),
	CLOUD: Color(0.8, 0.82, 0.88),
	SHIELD: Color(0.25, 0.9, 0.9),
	LIGHTNING: Color(0.7, 0.45, 1.0),
	UFO: Color(0.4, 0.95, 0.45),
}


static func item_name(item: int) -> String:
	return NAMES.get(item, "")


static func icon_path(item: int) -> String:
	return "res://assets/ui/items/%s.png" % KEYS.get(item, "none")
