extends Object
class_name Utils
# shuffle copied verbatim from res://systems/Utils.gd
static func shuffle(arr: Array, rand: RandomNumberGenerator) -> void :
	if arr.size() < 2:
		return

	for i in range(arr.size() - 1, 0, -1):
		var j = rand.randi() % (i + 1)
		var tmp = arr[j]
		arr[j] = arr[i]
		arr[i] = tmp
