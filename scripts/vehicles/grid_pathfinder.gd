class_name GridPathfinder
extends RefCounted

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]


func find_path(
	start_anchor: Vector2i,
	target_anchor: Vector2i,
	footprint: Vector2i,
	grid_size: Vector2i,
	is_footprint_walkable: Callable
) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if footprint.x <= 0 or footprint.y <= 0:
		return empty_path
	if grid_size.x <= 0 or grid_size.y <= 0:
		return empty_path
	if footprint.x > grid_size.x or footprint.y > grid_size.y:
		return empty_path
	if not is_footprint_walkable.is_valid():
		return empty_path
	if not _is_anchor_in_bounds(start_anchor, footprint, grid_size):
		return empty_path
	if not _is_anchor_in_bounds(target_anchor, footprint, grid_size):
		return empty_path
	if not bool(is_footprint_walkable.call(start_anchor, footprint)):
		return empty_path
	if not bool(is_footprint_walkable.call(target_anchor, footprint)):
		return empty_path
	if start_anchor == target_anchor:
		return [start_anchor]

	var frontier: Array[Vector2i] = [start_anchor]
	var frontier_index := 0
	var came_from: Dictionary = {start_anchor: start_anchor}

	while frontier_index < frontier.size():
		var current: Vector2i = frontier[frontier_index]
		frontier_index += 1
		for direction in CARDINAL_DIRECTIONS:
			var next_anchor := current + direction
			if came_from.has(next_anchor):
				continue
			if not _is_anchor_in_bounds(next_anchor, footprint, grid_size):
				continue
			if not bool(is_footprint_walkable.call(next_anchor, footprint)):
				continue
			came_from[next_anchor] = current
			if next_anchor == target_anchor:
				return _reconstruct_path(came_from, start_anchor, target_anchor)
			frontier.append(next_anchor)

	return empty_path


func _is_anchor_in_bounds(
	anchor: Vector2i,
	footprint: Vector2i,
	grid_size: Vector2i
) -> bool:
	return (
		anchor.x >= 0
		and anchor.y >= 0
		and anchor.x + footprint.x <= grid_size.x
		and anchor.y + footprint.y <= grid_size.y
	)


func _reconstruct_path(
	came_from: Dictionary,
	start_anchor: Vector2i,
	target_anchor: Vector2i
) -> Array[Vector2i]:
	var reversed_path: Array[Vector2i] = [target_anchor]
	var current := target_anchor
	while current != start_anchor:
		current = came_from[current]
		reversed_path.append(current)
	reversed_path.reverse()
	return reversed_path
