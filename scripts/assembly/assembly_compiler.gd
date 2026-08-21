class_name AssemblyCompiler
extends RefCounted

const DIAGNOSTIC_ASSEMBLY_ID_REQUIRED: StringName = &"assembly_id_required"
const DIAGNOSTIC_REVISION_INVALID: StringName = &"revision_invalid"
const DIAGNOSTIC_ASSEMBLY_EMPTY: StringName = &"assembly_empty"
const DIAGNOSTIC_COMPONENT_ID_REQUIRED: StringName = &"component_id_required"
const DIAGNOSTIC_COMPONENT_TYPE_REQUIRED: StringName = &"component_type_required"
const DIAGNOSTIC_DUPLICATE_COMPONENT_ID: StringName = &"duplicate_component_id"
const DIAGNOSTIC_ORIENTATION_INVALID: StringName = &"orientation_invalid"
const DIAGNOSTIC_OCCUPANCY_EMPTY: StringName = &"occupancy_empty"
const DIAGNOSTIC_OCCUPANCY_DUPLICATE: StringName = &"occupancy_duplicate"
const DIAGNOSTIC_OCCUPANCY_OVERLAP: StringName = &"occupancy_overlap"
const DIAGNOSTIC_COST_INVALID: StringName = &"cost_invalid"
const DIAGNOSTIC_MASS_INVALID: StringName = &"mass_invalid"
const DIAGNOSTIC_INTERFACE_KIND_REQUIRED: StringName = &"interface_kind_required"
const DIAGNOSTIC_INTERFACE_CELLS_EMPTY: StringName = &"interface_cells_empty"

var _cache: Dictionary = {}


func compile(definition: AssemblyDefinition) -> AssemblyCompileResult:
	if definition == null:
		return _failed_result(
			&"",
			-1,
			[AssemblyCompileDiagnostic.new(DIAGNOSTIC_ASSEMBLY_ID_REQUIRED, "Assembly definition is required.")]
		)
	var key := definition.cache_key()
	if _can_cache(definition) and _cache.has(key):
		return _cache[key]
	var result := _compile_uncached(definition)
	if _can_cache(definition):
		_cache[key] = result
	return result


func clear_cache() -> void:
	_cache.clear()


func invalidate(assembly_id: StringName) -> void:
	var prefix := "%s@" % String(assembly_id)
	for key in _cache.keys():
		if String(key).begins_with(prefix):
			_cache.erase(key)


func get_cache_size() -> int:
	return _cache.size()


func _compile_uncached(definition: AssemblyDefinition) -> AssemblyCompileResult:
	var diagnostics: Array[AssemblyCompileDiagnostic] = []
	if definition.assembly_id == &"":
		diagnostics.append(AssemblyCompileDiagnostic.new(DIAGNOSTIC_ASSEMBLY_ID_REQUIRED, "Assembly id is required."))
	if definition.revision < 0:
		diagnostics.append(AssemblyCompileDiagnostic.new(DIAGNOSTIC_REVISION_INVALID, "Assembly revision must be non-negative."))
	var components := definition.get_components()
	if components.is_empty():
		diagnostics.append(AssemblyCompileDiagnostic.new(DIAGNOSTIC_ASSEMBLY_EMPTY, "Assembly must contain at least one component."))

	var component_ids: Dictionary = {}
	var occupied_lookup: Dictionary = {}
	var occupied_cells: Array[Vector2i] = []
	var capability_lookup: Dictionary = {}
	var interfaces: Array[AssemblyInteractionInterface] = []
	var total_cost := 0
	var total_mass := 0.0

	for component in components:
		_validate_component_basics(component, component_ids, diagnostics)
		var local_occupied_lookup: Dictionary = {}
		for local_cell in component.occupied_cells:
			if local_occupied_lookup.has(local_cell):
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_OCCUPANCY_DUPLICATE,
					"Component contains duplicate occupied cells.",
					AssemblyCompileDiagnostic.Severity.ERROR,
					component.component_id
				))
				continue
			local_occupied_lookup[local_cell] = true
			var assembly_cell := component.origin + _rotate_cell(local_cell, component.orientation_quarters)
			if occupied_lookup.has(assembly_cell):
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_OCCUPANCY_OVERLAP,
					"Multiple components occupy cell %s." % assembly_cell,
					AssemblyCompileDiagnostic.Severity.ERROR,
					component.component_id
				))
				continue
			occupied_lookup[assembly_cell] = component.component_id
			occupied_cells.append(assembly_cell)

		for capability in component.capabilities:
			if capability != &"":
				capability_lookup[capability] = true

		for interface_value in component.interaction_interfaces:
			if interface_value.kind == &"":
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_INTERFACE_KIND_REQUIRED,
					"Interaction interface kind is required.",
					AssemblyCompileDiagnostic.Severity.ERROR,
					component.component_id
				))
				continue
			if interface_value.cells.is_empty():
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_INTERFACE_CELLS_EMPTY,
					"Interaction interface must publish at least one cell.",
					AssemblyCompileDiagnostic.Severity.ERROR,
					component.component_id
				))
				continue
			var compiled_cells: Array[Vector2i] = []
			for local_interface_cell in interface_value.cells:
				compiled_cells.append(component.origin + _rotate_cell(local_interface_cell, component.orientation_quarters))
			interfaces.append(AssemblyInteractionInterface.new(
				interface_value.kind,
				compiled_cells,
				interface_value.metadata,
				component.component_id
			))

		total_cost += component.cost
		total_mass += component.mass

	if _has_errors(diagnostics):
		return _failed_result(definition.assembly_id, definition.revision, diagnostics)

	var capability_names: Array[StringName] = []
	for capability in capability_lookup.keys():
		capability_names.append(capability)
	return AssemblyCompileResult.new(
		definition.assembly_id,
		definition.revision,
		true,
		AssemblyCapabilitySet.new(capability_names),
		interfaces,
		AssemblySimulationEnvelope.new(occupied_cells),
		AssemblyMetrics.new(total_cost, total_mass),
		diagnostics
	)


func _validate_component_basics(
	component: AssemblyComponentDefinition,
	component_ids: Dictionary,
	diagnostics: Array[AssemblyCompileDiagnostic]
) -> void:
	if component.component_id == &"":
		diagnostics.append(AssemblyCompileDiagnostic.new(DIAGNOSTIC_COMPONENT_ID_REQUIRED, "Component id is required."))
	elif component_ids.has(component.component_id):
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_DUPLICATE_COMPONENT_ID,
			"Component ids must be unique.",
			AssemblyCompileDiagnostic.Severity.ERROR,
			component.component_id
		))
	else:
		component_ids[component.component_id] = true
	if component.component_type == &"":
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_COMPONENT_TYPE_REQUIRED,
			"Component type is required.",
			AssemblyCompileDiagnostic.Severity.ERROR,
			component.component_id
		))
	if component.orientation_quarters < 0 or component.orientation_quarters > 3:
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_ORIENTATION_INVALID,
			"Component orientation must be in the range 0...3.",
			AssemblyCompileDiagnostic.Severity.ERROR,
			component.component_id
		))
	if component.occupied_cells.is_empty():
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_OCCUPANCY_EMPTY,
			"Component must occupy at least one local cell.",
			AssemblyCompileDiagnostic.Severity.ERROR,
			component.component_id
		))
	if component.cost < 0:
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_COST_INVALID,
			"Component cost must be non-negative.",
			AssemblyCompileDiagnostic.Severity.ERROR,
			component.component_id
		))
	if component.mass < 0.0:
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_MASS_INVALID,
			"Component mass must be non-negative.",
			AssemblyCompileDiagnostic.Severity.ERROR,
			component.component_id
		))


func _failed_result(
	assembly_id: StringName,
	revision: int,
	diagnostics: Array
) -> AssemblyCompileResult:
	return AssemblyCompileResult.new(
		assembly_id,
		revision,
		false,
		AssemblyCapabilitySet.new(),
		[],
		AssemblySimulationEnvelope.new(),
		AssemblyMetrics.new(),
		diagnostics
	)


func _can_cache(definition: AssemblyDefinition) -> bool:
	return definition.assembly_id != &"" and definition.revision >= 0


func _has_errors(diagnostics: Array[AssemblyCompileDiagnostic]) -> bool:
	for diagnostic in diagnostics:
		if diagnostic.is_error():
			return true
	return false


func _rotate_cell(cell: Vector2i, orientation_quarters: int) -> Vector2i:
	match orientation_quarters:
		0:
			return cell
		1:
			return Vector2i(-cell.y, cell.x)
		2:
			return Vector2i(-cell.x, -cell.y)
		3:
			return Vector2i(cell.y, -cell.x)
		_:
			return cell
