class_name AssemblyCompiler
extends RefCounted

const DIAGNOSTIC_COMPILE_REQUEST_REQUIRED: StringName = &"compile_request_required"
const DIAGNOSTIC_REVISION_CONTENT_MISMATCH: StringName = &"revision_content_mismatch"
const DIAGNOSTIC_ASSEMBLY_ID_REQUIRED: StringName = &"assembly_id_required"
const DIAGNOSTIC_REVISION_INVALID: StringName = &"revision_invalid"
const DIAGNOSTIC_ASSEMBLY_EMPTY: StringName = &"assembly_empty"
const DIAGNOSTIC_COMPONENT_ENTRY_INVALID: StringName = &"component_entry_invalid"
const DIAGNOSTIC_COMPONENT_ID_REQUIRED: StringName = &"component_id_required"
const DIAGNOSTIC_COMPONENT_TYPE_REQUIRED: StringName = &"component_type_required"
const DIAGNOSTIC_DUPLICATE_COMPONENT_ID: StringName = &"duplicate_component_id"
const DIAGNOSTIC_ORIENTATION_INVALID: StringName = &"orientation_invalid"
const DIAGNOSTIC_OCCUPANCY_EMPTY: StringName = &"occupancy_empty"
const DIAGNOSTIC_OCCUPANCY_DUPLICATE: StringName = &"occupancy_duplicate"
const DIAGNOSTIC_OCCUPANCY_OVERLAP: StringName = &"occupancy_overlap"
const DIAGNOSTIC_COORDINATE_OVERFLOW: StringName = &"coordinate_overflow"
const DIAGNOSTIC_COST_INVALID: StringName = &"cost_invalid"
const DIAGNOSTIC_MASS_INVALID: StringName = &"mass_invalid"
const DIAGNOSTIC_INTERFACE_ENTRY_INVALID: StringName = &"interface_entry_invalid"
const DIAGNOSTIC_INTERFACE_KIND_REQUIRED: StringName = &"interface_kind_required"
const DIAGNOSTIC_INTERFACE_CELLS_EMPTY: StringName = &"interface_cells_empty"
const DIAGNOSTIC_INTERFACE_COORDINATE_SPACE_INVALID: StringName = &"interface_coordinate_space_invalid"
const DIAGNOSTIC_INTERFACE_METADATA_INVALID: StringName = &"interface_metadata_invalid"
const MIN_INT32: int = -2147483648
const MAX_INT32: int = 2147483647
const MAX_INT64: int = 9223372036854775807

# assembly_id -> revision -> { structure_signature, result }
var _cache: Dictionary = {}


func compile(request: AssemblyCompileRequest) -> AssemblyCompileResult:
	if request == null or not request.has_definition():
		return _failed_result(
			AssemblyRevision.new(),
			[AssemblyCompileDiagnostic.new(DIAGNOSTIC_COMPILE_REQUEST_REQUIRED, "Assembly compile request is required.")]
		)
	var revision := request.get_revision()
	var definition := request.get_definition()
	var pre_cache_diagnostics := _validate_pre_cache_input(definition)
	if not pre_cache_diagnostics.is_empty():
		return _failed_result(revision, pre_cache_diagnostics)
	if request.is_cacheable():
		var assembly_id := revision.get_assembly_id()
		var revision_value := revision.get_value()
		var revisions: Dictionary = _cache.get(assembly_id, {})
		if revisions.has(revision_value):
			var cached_entry: Dictionary = revisions[revision_value]
			if cached_entry.get("structure_signature", []) != request.get_structure_signature():
				return _failed_result(
					revision,
					[AssemblyCompileDiagnostic.new(
						DIAGNOSTIC_REVISION_CONTENT_MISMATCH,
						"Assembly structure changed without advancing its revision."
					)]
				)
			return cached_entry["result"]
		var result := _compile_uncached(definition, revision)
		revisions[revision_value] = {
			"structure_signature": request.get_structure_signature(),
			"result": result,
		}
		_cache[assembly_id] = revisions
		return result
	return _compile_uncached(definition, revision)


func invalidate(assembly_id: StringName) -> void:
	_cache.erase(assembly_id)


func get_cache_size() -> int:
	var total := 0
	for revisions_value in _cache.values():
		if revisions_value is Dictionary:
			var revisions: Dictionary = revisions_value
			total += revisions.size()
	return total


func _validate_pre_cache_input(definition: AssemblyDefinition) -> Array[AssemblyCompileDiagnostic]:
	var diagnostics: Array[AssemblyCompileDiagnostic] = []
	if definition.get_invalid_component_entry_count() > 0:
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_COMPONENT_ENTRY_INVALID,
			"Assembly contains an invalid component entry."
		))
	for component in definition.get_components():
		if component.get_invalid_interface_entry_count() > 0:
			diagnostics.append(AssemblyCompileDiagnostic.new(
				DIAGNOSTIC_INTERFACE_ENTRY_INVALID,
				"Component contains an invalid interaction interface entry.",
				component.component_id
			))
		if not is_finite(component.mass):
			diagnostics.append(AssemblyCompileDiagnostic.new(
				DIAGNOSTIC_MASS_INVALID,
				"Component mass must be finite and non-negative.",
				component.component_id
			))
		for interface_value in component.interaction_interfaces:
			if not interface_value.is_metadata_valid():
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_INTERFACE_METADATA_INVALID,
					"Interaction interface metadata must be a flat map of stable primitive values.",
					component.component_id
				))
	return diagnostics


func _compile_uncached(
	definition: AssemblyDefinition,
	revision: AssemblyRevision
) -> AssemblyCompileResult:
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
					component.component_id
				))
				continue
			local_occupied_lookup[local_cell] = true
			var transformed_cell: Variant = _transform_cell_checked(
				component.origin,
				local_cell,
				component.orientation_quarters
			)
			if transformed_cell == null:
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_COORDINATE_OVERFLOW,
					"Transformed assembly geometry exceeds the Vector2i coordinate range.",
					component.component_id
				))
				continue
			var assembly_cell: Vector2i = transformed_cell
			if occupied_lookup.has(assembly_cell):
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_OCCUPANCY_OVERLAP,
					"Multiple components occupy cell %s." % assembly_cell,
					component.component_id
				))
				continue
			occupied_lookup[assembly_cell] = component.component_id
			occupied_cells.append(assembly_cell)

		for capability in component.capabilities:
			if capability != &"":
				capability_lookup[capability] = true

		for interface_value in component.interaction_interfaces:
			if not interface_value.is_component_local():
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_INTERFACE_COORDINATE_SPACE_INVALID,
					"Compile input interaction cells must use component-local coordinates.",
					component.component_id
				))
				continue
			if interface_value.kind == &"":
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_INTERFACE_KIND_REQUIRED,
					"Interaction interface kind is required.",
					component.component_id
				))
				continue
			if interface_value.cells.is_empty():
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_INTERFACE_CELLS_EMPTY,
					"Interaction interface must publish at least one cell.",
					component.component_id
				))
				continue
			var compiled_cells: Array[Vector2i] = []
			var interface_transform_failed := false
			for local_interface_cell in interface_value.cells:
				var transformed_interface_cell: Variant = _transform_cell_checked(
					component.origin,
					local_interface_cell,
					component.orientation_quarters
				)
				if transformed_interface_cell == null:
					diagnostics.append(AssemblyCompileDiagnostic.new(
						DIAGNOSTIC_COORDINATE_OVERFLOW,
						"Transformed interaction geometry exceeds the Vector2i coordinate range.",
						component.component_id
					))
					interface_transform_failed = true
					continue
				var compiled_cell: Vector2i = transformed_interface_cell
				compiled_cells.append(compiled_cell)
			if interface_transform_failed:
				continue
			interfaces.append(AssemblyInteractionInterface.new(
				interface_value.kind,
				compiled_cells,
				interface_value.metadata,
				component.component_id,
				AssemblyInteractionInterface.CoordinateSpace.ASSEMBLY_LOCAL
			))

		if component.cost >= 0:
			if component.cost > 0 and total_cost > MAX_INT64 - component.cost:
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_COST_INVALID,
					"Assembly total cost exceeds the supported integer range.",
					component.component_id
				))
			else:
				total_cost += component.cost

		if component.mass >= 0.0:
			var next_total_mass := total_mass + component.mass
			if not is_finite(next_total_mass):
				diagnostics.append(AssemblyCompileDiagnostic.new(
					DIAGNOSTIC_MASS_INVALID,
					"Assembly total mass must remain finite.",
					component.component_id
				))
			else:
				total_mass = next_total_mass

	if not diagnostics.is_empty():
		return _failed_result(revision, diagnostics)

	var capability_names: Array[StringName] = []
	for capability in capability_lookup.keys():
		capability_names.append(capability)
	return AssemblyCompileResult.new(
		revision,
		true,
		capability_names,
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
			component.component_id
		))
	else:
		component_ids[component.component_id] = true
	if component.component_type == &"":
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_COMPONENT_TYPE_REQUIRED,
			"Component type is required.",
			component.component_id
		))
	if component.orientation_quarters < 0 or component.orientation_quarters > 3:
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_ORIENTATION_INVALID,
			"Component orientation must be in the range 0...3.",
			component.component_id
		))
	if component.occupied_cells.is_empty():
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_OCCUPANCY_EMPTY,
			"Component must occupy at least one local cell.",
			component.component_id
		))
	if component.cost < 0:
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_COST_INVALID,
			"Component cost must be non-negative.",
			component.component_id
		))
	if not is_finite(component.mass) or component.mass < 0.0:
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_MASS_INVALID,
			"Component mass must be finite and non-negative.",
			component.component_id
		))


func _failed_result(
	revision: AssemblyRevision,
	diagnostics: Array[AssemblyCompileDiagnostic]
) -> AssemblyCompileResult:
	return AssemblyCompileResult.new(
		revision,
		false,
		[],
		[],
		AssemblySimulationEnvelope.new(),
		AssemblyMetrics.new(),
		diagnostics
	)


func _transform_cell_checked(
	origin: Vector2i,
	cell: Vector2i,
	orientation_quarters: int
) -> Variant:
	var source_x := int(cell.x)
	var source_y := int(cell.y)
	var rotated_x: int
	var rotated_y: int
	match orientation_quarters:
		0:
			rotated_x = source_x
			rotated_y = source_y
		1:
			rotated_x = -source_y
			rotated_y = source_x
		2:
			rotated_x = -source_x
			rotated_y = -source_y
		3:
			rotated_x = source_y
			rotated_y = -source_x
		_:
			rotated_x = source_x
			rotated_y = source_y

	var assembly_x := int(origin.x) + rotated_x
	var assembly_y := int(origin.y) + rotated_y
	if (
		assembly_x < MIN_INT32
		or assembly_x > MAX_INT32
		or assembly_y < MIN_INT32
		or assembly_y > MAX_INT32
	):
		return null
	return Vector2i(assembly_x, assembly_y)
