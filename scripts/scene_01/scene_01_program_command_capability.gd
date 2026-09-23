class_name Scene01ProgramCommandCapability
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")


static func required_capability(statement_type: int) -> StringName:
	match statement_type:
		ProgramScript.StatementType.MOVE_TO:
			return AssemblyCapabilitiesScript.CAN_MOVE
		ProgramScript.StatementType.ROTATE:
			return AssemblyCapabilitiesScript.CAN_ROTATE
		ProgramScript.StatementType.GRAB_DROP:
			return AssemblyCapabilitiesScript.GRAB_DROP
	return &""


static func supports(capabilities: Array[StringName], statement_type: int) -> bool:
	var required := required_capability(statement_type)
	return required != &"" and capabilities.has(required)
