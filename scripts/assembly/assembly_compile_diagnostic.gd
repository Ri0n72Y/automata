class_name AssemblyCompileDiagnostic
extends RefCounted

var code: StringName = &""
var message: String = ""
var component_id: StringName = &""


func _init(
	diagnostic_code: StringName = &"",
	diagnostic_message: String = "",
	diagnostic_component_id: StringName = &""
) -> void:
	code = diagnostic_code
	message = diagnostic_message
	component_id = diagnostic_component_id


func duplicate_diagnostic() -> AssemblyCompileDiagnostic:
	return AssemblyCompileDiagnostic.new(code, message, component_id)
