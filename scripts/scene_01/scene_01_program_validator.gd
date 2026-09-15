class_name Scene01ProgramValidator
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")

const MAX_REPEAT_COUNT := 100


func validate(program: Scene01Program, grid_size: Vector2i = Vector2i.ZERO) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if program == null:
		return [_diagnostic(&"program_required", "Program is required.")]
	if program.nodes.is_empty():
		return [_diagnostic(&"nodes_required", "Program requires a Start node.")]

	var by_id: Dictionary = {}
	var start_count := 0
	for node in program.nodes:
		_validate_node(node, grid_size, by_id, diagnostics)
		if int(node.get("type", -1)) == ProgramScript.NodeType.START:
			start_count += 1
	if start_count != 1:
		diagnostics.append(_diagnostic(&"single_start_required", "Program requires exactly one Start node."))
	var start: Dictionary = by_id.get(program.start_node_id, {})
	if start.is_empty() or int(start.get("type", -1)) != ProgramScript.NodeType.START:
		diagnostics.append(_diagnostic(&"invalid_start", "Program start_node_id must reference the Start node.", program.start_node_id))
		return diagnostics

	for node in program.nodes:
		var next_id := int(node.get("next_id", ProgramScript.NO_NODE_ID))
		if next_id != ProgramScript.NO_NODE_ID and not by_id.has(next_id):
			diagnostics.append(_diagnostic(&"missing_next_node", "Program next link references a missing node.", int(node.get("id", ProgramScript.NO_NODE_ID))))

	var ordered := program.get_execution_order()
	var order_index: Dictionary = {}
	for index in range(ordered.size()):
		order_index[int(ordered[index].get("id", ProgramScript.NO_NODE_ID))] = index
	if not ordered.is_empty():
		var tail: Dictionary = ordered[ordered.size() - 1]
		var tail_next := int(tail.get("next_id", ProgramScript.NO_NODE_ID))
		if tail_next != ProgramScript.NO_NODE_ID and order_index.has(tail_next):
			diagnostics.append(_diagnostic(&"next_cycle", "Program next links must not form a cycle.", tail_next))
	if order_index.size() != by_id.size():
		diagnostics.append(_diagnostic(&"unreachable_node", "Every program node must be reachable from Start."))

	for node in ordered:
		if int(node.get("type", -1)) != ProgramScript.NodeType.REPEAT:
			continue
		_validate_repeat_target(node, by_id, order_index, program.start_node_id, diagnostics)
	return diagnostics


func required_capabilities(program: Scene01Program) -> Array[StringName]:
	var result: Array[StringName] = []
	for capabilities_value in required_capabilities_by_vehicle(program).values():
		for capability_value in capabilities_value:
			var capability := StringName(capability_value)
			if not result.has(capability):
				result.append(capability)
	return result


func required_capabilities_by_vehicle(program: Scene01Program) -> Dictionary:
	var result: Dictionary = {}
	if program == null:
		return result
	for node in program.get_execution_order():
		var vehicle_id := StringName(node.get("vehicle_id", &""))
		match int(node.get("type", -1)):
			ProgramScript.NodeType.MOVE_TO:
				_append_requirement(result, vehicle_id, AssemblyCapabilitiesScript.CAN_MOVE)
			ProgramScript.NodeType.GRAB_DROP:
				_append_requirement(result, vehicle_id, AssemblyCapabilitiesScript.GRAB_DROP)
	return result


func _validate_node(
	node: Dictionary,
	grid_size: Vector2i,
	by_id: Dictionary,
	diagnostics: Array[Dictionary]
) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	var node_type := int(node.get("type", -1))
	if node_id <= 0 or by_id.has(node_id):
		diagnostics.append(_diagnostic(&"invalid_node_id", "Program node ids must be positive and unique.", node_id))
		return
	by_id[node_id] = node
	if not _is_valid_type(node_type):
		diagnostics.append(_diagnostic(&"invalid_node_type", "Program node type is invalid.", node_id))
		return
	if node_type == ProgramScript.NodeType.MOVE_TO or node_type == ProgramScript.NodeType.GRAB_DROP:
		if StringName(node.get("vehicle_id", &"")) == &"":
			diagnostics.append(_diagnostic(&"command_vehicle_required", "Vehicle command requires a vehicle id.", node_id))
	if node_type == ProgramScript.NodeType.MOVE_TO:
		var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
		if target.x < 0 or target.y < 0:
			diagnostics.append(_diagnostic(&"move_target_required", "MoveTo requires a target anchor.", node_id))
		elif grid_size.x > 0 and grid_size.y > 0 and (target.x >= grid_size.x or target.y >= grid_size.y):
			diagnostics.append(_diagnostic(&"move_target_out_of_bounds", "MoveTo target is outside the grid.", node_id))
	elif node_type == ProgramScript.NodeType.REPEAT:
		var repeat_count := int(node.get("repeat_count", 0))
		if repeat_count < 1 or repeat_count > MAX_REPEAT_COUNT:
			diagnostics.append(_diagnostic(&"invalid_repeat_count", "Repeat N must be between 1 and %d." % MAX_REPEAT_COUNT, node_id))


func _validate_repeat_target(
	node: Dictionary,
	by_id: Dictionary,
	order_index: Dictionary,
	start_node_id: int,
	diagnostics: Array[Dictionary]
) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	var target_id := int(node.get("repeat_target_id", ProgramScript.NO_NODE_ID))
	if not order_index.has(target_id):
		diagnostics.append(_diagnostic(&"repeat_target_required", "Repeat N requires a reachable loop target.", node_id))
		return
	var target: Dictionary = by_id.get(target_id, {})
	var target_type := int(target.get("type", -1))
	if target_id == start_node_id or target_type == ProgramScript.NodeType.REPEAT:
		diagnostics.append(_diagnostic(&"invalid_repeat_target", "Repeat N must target an earlier vehicle command.", node_id))
		return
	if int(order_index[target_id]) >= int(order_index[node_id]):
		diagnostics.append(_diagnostic(&"invalid_repeat_target", "Repeat N must target an earlier vehicle command.", node_id))


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


func _is_valid_type(node_type: int) -> bool:
	return node_type in [
		ProgramScript.NodeType.START,
		ProgramScript.NodeType.MOVE_TO,
		ProgramScript.NodeType.GRAB_DROP,
		ProgramScript.NodeType.REPEAT,
	]


func _diagnostic(code: StringName, message: String, node_id: int = ProgramScript.NO_NODE_ID) -> Dictionary:
	return {"code": code, "message": message, "node_id": node_id}
