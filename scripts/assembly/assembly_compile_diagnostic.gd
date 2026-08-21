class_name AssemblyCompileDiagnostic
extends RefCounted

enum Severity {
	WARNING,
	ERROR,
}

var severity: Severity = Severity.ERROR
var code: StringName = &""
var message: String = ""
var component_id: StringName = &""


func _init(
	diagnostic_code: StringName = &"",
	diagnostic_message: String = "",
	diagnostic_severity: Severity = Severity.ERROR,
	diagnostic_component_id: StringName = &""
) -> void:
	code = diagnostic_code
	message = diagnostic_message
	severity = diagnostic_severity
	component_id = diagnostic_component_id


func is_error() -> bool:
	return severity == Severity.ERROR


func duplicate_diagnostic() -> AssemblyCompileDiagnostic:
	return AssemblyCompileDiagnostic.new(code, message, severity, component_id)
