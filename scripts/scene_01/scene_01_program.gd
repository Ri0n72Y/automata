class_name Scene01Program
extends Resource

const NO_NODE_ID := -1

enum NodeType {
	START = 0,
	MOVE_TO = 1,
	GRAB_DROP = 2,
	REPEAT = 3,
}

@export var start_node_id: int = NO_NODE_ID
@export var nodes: Array[Dictionary] = []


func reset() -> void:
	nodes.clear()
	start_node_id = _append_raw_node(NodeType.START)


func append_node(node_type: int) -> int:
	if nodes.is_empty():
		reset()
	if not _is_appendable_type(node_type):
		return NO_NODE_ID
	var tail_id := get_tail_node_id()
	var node_id := _append_raw_node(node_type)
	if tail_id != NO_NODE_ID:
		connect_nodes(tail_id, node_id)
	return node_id


func connect_nodes(from_node_id: int, to_node_id: int) -> bool:
	if from_node_id == to_node_id:
		return false
	var from_index := _find_node_index(from_node_id)
	if from_index < 0:
		return false
	if to_node_id != NO_NODE_ID and _find_node_index(to_node_id) < 0:
		return false
	var node := nodes[from_index].duplicate(true)
	node["next_id"] = to_node_id
	nodes[from_index] = node
	return true


func remove_node(node_id: int) -> bool:
	if node_id == start_node_id:
		return false
	var index := _find_node_index(node_id)
	if index < 0:
		return false
	var removed: Dictionary = nodes[index]
	var replacement_next := int(removed.get("next_id", NO_NODE_ID))
	nodes.remove_at(index)
	for current_index in range(nodes.size()):
		var node := nodes[current_index].duplicate(true)
		if int(node.get("next_id", NO_NODE_ID)) == node_id:
			node["next_id"] = replacement_next
		if int(node.get("repeat_target_id", NO_NODE_ID)) == node_id:
			node["repeat_target_id"] = NO_NODE_ID
		nodes[current_index] = node
	return true


func set_command_vehicle(node_id: int, vehicle_id: StringName) -> bool:
	var index := _find_node_index(node_id)
	if index < 0:
		return false
	var node_type := int(nodes[index].get("type", -1))
	if node_type != NodeType.MOVE_TO and node_type != NodeType.GRAB_DROP:
		return false
	var node := nodes[index].duplicate(true)
	node["vehicle_id"] = vehicle_id
	nodes[index] = node
	return true


func set_move_target(node_id: int, target_anchor: Vector2i) -> bool:
	var index := _find_node_index(node_id)
	if index < 0 or int(nodes[index].get("type", -1)) != NodeType.MOVE_TO:
		return false
	var node := nodes[index].duplicate(true)
	node["target_anchor"] = target_anchor
	nodes[index] = node
	return true


func set_repeat(node_id: int, repeat_count: int, repeat_target_id: int) -> bool:
	var index := _find_node_index(node_id)
	if index < 0 or int(nodes[index].get("type", -1)) != NodeType.REPEAT:
		return false
	var node := nodes[index].duplicate(true)
	node["repeat_count"] = repeat_count
	node["repeat_target_id"] = repeat_target_id
	nodes[index] = node
	return true


func get_node_data(node_id: int) -> Dictionary:
	var index := _find_node_index(node_id)
	return nodes[index].duplicate(true) if index >= 0 else {}


func get_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in nodes:
		result.append(node.duplicate(true))
	return result


func get_execution_order() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_id := start_node_id
	var visited: Dictionary = {}
	while current_id != NO_NODE_ID and not visited.has(current_id):
		visited[current_id] = true
		var node := get_node_data(current_id)
		if node.is_empty():
			break
		result.append(node)
		current_id = int(node.get("next_id", NO_NODE_ID))
	return result


func get_tail_node_id() -> int:
	var ordered := get_execution_order()
	if ordered.is_empty():
		return NO_NODE_ID
	var tail: Dictionary = ordered[ordered.size() - 1]
	return int(tail.get("id", NO_NODE_ID)) if int(tail.get("next_id", NO_NODE_ID)) == NO_NODE_ID else NO_NODE_ID


func duplicate_program() -> Scene01Program:
	var copy := Scene01Program.new()
	copy.start_node_id = start_node_id
	copy.nodes = get_nodes()
	return copy


func _append_raw_node(node_type: int) -> int:
	var node_id := _next_node_id()
	nodes.append({
		"id": node_id,
		"type": node_type,
		"next_id": NO_NODE_ID,
		"vehicle_id": &"",
		"target_anchor": Vector2i(-1, -1),
		"repeat_count": 1,
		"repeat_target_id": NO_NODE_ID,
	})
	return node_id


func _is_appendable_type(node_type: int) -> bool:
	return node_type in [NodeType.MOVE_TO, NodeType.GRAB_DROP, NodeType.REPEAT]


func _next_node_id() -> int:
	var maximum := 0
	for node in nodes:
		maximum = maxi(maximum, int(node.get("id", 0)))
	return maximum + 1


func _find_node_index(node_id: int) -> int:
	for index in range(nodes.size()):
		if int(nodes[index].get("id", NO_NODE_ID)) == node_id:
			return index
	return -1
