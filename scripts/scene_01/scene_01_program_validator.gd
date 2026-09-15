class_name Scene01ProgramValidator
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")

const MAX_REPEAT_COUNT := 100


func validate(program: Scene01Program, grid_size: Vector2i = Vector2i.ZERO) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if program == null:
		return [_diagnostic(&"program_required", "Program is required.")]
	if program.vehicle_id == &"":
		diagnostics.append(_diagnostic(&"vehicle_required", "Program default vehicle is required."))
	if program.nodes.is_empty():
		diagnostics.append(_diagnostic(&"nodes_required", "Program requires a Start node."))
		return diagnostics

	var by_id: Dictionary = {}
	var start_count := 0
	for node in program.nodes:
		var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
		var node_type := int(node.get("type", -1))
		if node_id <= 0 or by_id.has(node_id):
			diagnostics.append(_diagnostic(&"invalid_node_id", "Program node ids must be positive and unique.", node_id))
			continue
		by_id[node_id] = node
		if node_type < ProgramScript.NodeType.START or node_type > ProgramScript.NodeType.REPEAT:
			diagnostics.append(_diagnostic(&"invalid_node_type", "Program node type is invalid.", node_id))
			continue
		match node_type:
			ProgramScript.NodeType.START:
				start_count += 1
			ProgramScript.NodeType.SELECT_VEHICLE:
				if StringName(node.get("vehicle_id", &"")) == &"":
					diagnostics.append(_diagnostic(&"select_vehicle_required", "SelectVehicle requires a vehicle id.", node_id))
			ProgramScript.NodeType.MOVE_TO:
				var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
				if target.x < 0 or target.y < 0:
					diagnostics.append(_diagnostic(&"move_target_required", "MoveTo requires a target anchor.", node_id))
				elif grid_size.x > 0 and grid_size.y > 0 and (target.x >= grid_size.x or target.y >= grid_size.y):
					diagnostics.append(_diagnostic(&"move_target_out_of_bounds", "MoveTo target is outside the grid.", node_id))
			ProgramScript.NodeType.REPEAT:
				var repeat_count := int(node.get("repeat_count", 0))
				if repeat_count < 1 or repeat_count > MAX_REPEAT_COUNT:
					diagnostics.append(_diagnostic(&"invalid_repeat_count", "Repeat N must be between 1 and %d." % MAX_REPEAT_COUNT, node_id))

	if start_count != 1:
		diagnostics.append(_diagnostic(&"single_start_required", "Program requires exactly one Start node."))
	var start: Dictionary = by_id.get(program.start_node_id, {})
	if start.is_empty() or int(start.get("type", -1)) != ProgramScript.NodeType.START:
		diagnostics.append(_diagnostic(&"invalid_start", "Program start_node_id must reference the Start node.", program.start_node_id))
		return diagnostics

	var order: Array[int] = []
	var visited: Dictionary = {}
	var current_id := program.start_node_id
	while current_id != ProgramScript.NO_NODE_ID:
		if visited.has(current_id):
			diagnostics.append(_diagnostic(&"next_cycle", "Program next links must not form a cycle.", current_id))
			break
		var node: Dictionary = by_id.get(current_id, {})
		if node.is_empty():
			diagnostics.append(_diagnostic(&"missing_next_node", "Program next link references a missing node.", current_id))
			break
		visited[current_id] = true
		order.append(current_id)
		var next_id := int(node.get("next_id", ProgramScript.NO_NODE_ID))
		if next_id != ProgramScript.NO_NODE_ID and not by_id.has(next_id):
			diagnostics.append(_diagnostic(&"missing_next_node", "Program next link references a missing node.", current_id))
			break
		current_id = next_id

	if visited.size() != by_id.size():
		diagnostics.append(_diagnostic(&"unreachable_node", "Every program node must be reachable from Start."))

	var order_index: Dictionary = {}
	for index in range(order.size()):
		order_index[order[index]] = index
	for node_id_value in order:
		var node_id := int(node_id_value)
		var node: Dictionary = by_id[node_id]
		if int(node.get("type", -1)) != ProgramScript.NodeType.REPEAT:
			continue
		var target_id := int(node.get("repeat_target_id", ProgramScript.NO_NODE_ID))
		if not order_index.has(target_id):
			diagnostics.append(_diagnostic(&"repeat_target_required", "Repeat N requires a reachable loop target.", node_id))
			continue
		if target_id == program.start_node_id or int(order_index[target_id]) >= int(order_index[node_id]):
			diagnostics.append(_diagnostic(&"invalid_repeat_target", "Repeat N must target an earlier executable node after Start.", node_id))

	return diagnostics


func required_capabilities(program: Scene01Program) -> Array[StringName]:
	var result: Array[StringName] = []
	var by_vehicle := required_capabilities_by_vehicle(program)
	for capabilities_value in by_vehicle.values():
		for capability_value in capabilities_value:
			var capability := StringName(capability_value)
			if not result.has(capability):
				result.append(capability)
	return result


func required_capabilities_by_vehicle(program: Scene01Program) -> Dictionary:
	var result: Dictionary = {}
	if program == null:
		return result
	var current_vehicle_id := program.vehicle_id
	for node in _ordered_nodes(program):
		match int(node.get("type", -1)):
			ProgramScript.NodeType.SELECT_VEHICLE:
				current_vehicle_id = StringName(node.get("vehicle_id", &""))
			ProgramScript.NodeType.MOVE_TO:
				_append_requirement(result, current_vehicle_id, AssemblyCapabilitiesScript.CAN_MOVE)
			ProgramScript.NodeType.GRAB_DROP:
				_append_requirement(result, current_vehicle_id, AssemblyCapabilitiesScript.GRAB_DROP)
	return result


func _ordered_nodes(program: Scene01Program) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_id := program.start_node_id
	var visited: Dictionary = {}
	while current_id != ProgramScript.NO_NODE_ID and not visited.has(current_id):
		visited[current_id] = true
		var node := program.get_node_data(current_id)
		if node.is_empty():
			break
		result.append(node)
		current_id = int(node.get("next_id", ProgramScript.NO_NODE_ID))
	return result


func _append_requirement(result: Dictionary, vehicle_id: StringName, capability: StringName) -> void:
	if vehicle_id == &"":
		return
	var capabilities: Array[StringName] = []
	if result.has(vehicle_id):
		for value in result[vehicle_id]:
			capabilities.append(StringName(value))
	if not capabilities.has(capability):
		capabilities.append(capability)
	result[vehicle_id] = capabilities


func _diagnostic(code: StringName, message: String, node_id: int = ProgramScript.NO_NODE_ID) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"node_id": node_id,
	}
