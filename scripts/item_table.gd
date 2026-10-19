class_name ItemTable
extends Resource
## Rank based item weights. Keys are ItemDefs ids, values are relative weights.

@export var front_weights := {1: 20, 2: 5, 3: 5, 4: 30, 5: 20, 6: 20, 7: 0, 8: 0}
@export var middle_weights := {1: 25, 2: 15, 3: 15, 4: 15, 5: 10, 6: 10, 7: 5, 8: 5}
@export var back_weights := {1: 30, 2: 10, 3: 15, 4: 5, 5: 0, 6: 5, 7: 20, 8: 15}
## When the last place kart trails the leader by more than this many metres it
## gets an extra nitro weight.
@export var far_behind_gap := 150.0
@export var far_behind_nitro_bonus := 10


func weights_for(rank: int, total: int) -> Dictionary:
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
