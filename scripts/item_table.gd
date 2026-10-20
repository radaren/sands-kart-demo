class_name ItemTable
extends Resource
## Rank based item weights. Keys are ItemDefs ids, values are relative weights.

@export var front_weights := {1: 20, 2: 5, 3: 5, 4: 30, 5: 20, 6: 20, 7: 0, 8: 0}
@export var middle_weights := {1: 25, 2: 15, 3: 15, 4: 15, 5: 10, 6: 10, 7: 5, 8: 5}
@export var back_weights := {1: 35, 2: 12, 3: 15, 4: 8, 5: 0, 6: 5, 7: 10, 8: 15}   # I5: lightning 20 -> 10
## When the last place kart trails the leader by more than this many metres it
## gets an extra nitro weight.
@export var far_behind_gap := 150.0
@export var far_behind_nitro_bonus := 10


func weights_for(rank: int, total: int) -> Dictionary:
	if rank == 1:
		# I3: the leader has nobody ahead to hit
		var w := front_weights.duplicate()
		for useless in [ItemDefs.MISSILE, ItemDefs.MAGNET, ItemDefs.UFO, ItemDefs.LIGHTNING]:
			w[useless] = 0
		return w
	if rank <= 2:
		return front_weights.duplicate()
	if rank <= 4 and total > 4:
		return middle_weights.duplicate()
	return back_weights.duplicate()


func roll(rank: int, total: int, leader_gap: float, rng: RandomNumberGenerator) -> int:
	var weights := weights_for(rank, total)
	if rank == total and leader_gap > far_behind_gap:
		weights[ItemDefs.NITRO] = int(weights.get(ItemDefs.NITRO, 0)) + far_behind_nitro_bonus
	var sum := 0
	for key: int in weights:
		sum += int(weights[key])
	if sum <= 0:
		return ItemDefs.NITRO
	var pick := rng.randi_range(1, sum)
	for key: int in weights:
		pick -= int(weights[key])
		if pick <= 0:
			return key
	return ItemDefs.NITRO
