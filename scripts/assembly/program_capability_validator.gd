class_name ProgramCapabilityValidator
extends RefCounted

const DIAGNOSTIC_COMPILE_RESULT_REQUIRED: StringName = &"compile_result_required"
const DIAGNOSTIC_MISSING_CAPABILITY: StringName = &"missing_capability"


func validate(
	compile_result: AssemblyCompileResult,
	required_capabilities: Array[StringName]
) -> Array[AssemblyCompileDiagnostic]:
	var diagnostics: Array[AssemblyCompileDiagnostic] = []
	if compile_result == null or not compile_result.is_success():
		diagnostics.append(AssemblyCompileDiagnostic.new(
			DIAGNOSTIC_COMPILE_RESULT_REQUIRED,
			"A successful assembly compile result is required."
		))
		return diagnostics
	var checked: Dictionary = {}
	for capability in required_capabilities:
		if capability == &"" or checked.has(capability):
			continue
		checked[capability] = true
		if not compile_result.has_capability(capability):
			diagnostics.append(AssemblyCompileDiagnostic.new(
				DIAGNOSTIC_MISSING_CAPABILITY,
				"Assembly is missing required capability '%s'." % String(capability)
			))
	return diagnostics
