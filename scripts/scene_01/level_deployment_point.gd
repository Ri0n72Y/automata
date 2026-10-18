class_name LevelDeploymentPoint
extends Node3D

## Per-level deployment origin. Adjustable from the scene inspector; the
## blueprint workbench always deploys here and reports when the cell is busy.

@export var cell: Vector2i = Vector2i(1, 1)
@export var facing: int = 0
@export var show_marker: bool = true


func _ready() -> void:
	position = Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
	if show_marker:
		_build_marker()


func get_deploy_cell() -> Vector2i:
	return cell


func get_facing() -> int:
	return facing


func set_deploy_cell(value: Vector2i) -> void:
	cell = value
	position = Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func _build_marker() -> void:
	var pad := MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.48
	pad_mesh.bottom_radius = 0.48
	pad_mesh.height = 0.05
	pad_mesh.radial_segments = 40
	pad.mesh = pad_mesh
	pad.position = Vector3(0, 0.025, 0)
	var pad_material := StandardMaterial3D.new()
	pad_material.albedo_color = Color(0.62, 0.88, 0.92, 0.32)
	pad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad.material_override = pad_material
	add_child(pad)

	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.5
	ring_mesh.bottom_radius = 0.5
	ring_mesh.height = 0.015
	ring_mesh.radial_segments = 40
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0.055, 0)
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.070588, 0.627451, 0.686275, 0.9)
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_material
	add_child(ring)

	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.070588, 0.627451, 0.686275, 1)
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in range(4):
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.26, 0.02, 0.05)
		marker.mesh = mesh
		marker.material_override = line_material
		var angle := PI * 0.5 * float(index) + PI * 0.25
		marker.position = Vector3(cos(angle) * 0.46, 0.07, sin(angle) * 0.46)
		marker.rotation.y = -angle
		add_child(marker)

	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.035
	beam_mesh.bottom_radius = 0.035
	beam_mesh.height = 1.4
	beam_mesh.radial_segments = 12
	beam.mesh = beam_mesh
	beam.position = Vector3(0, 0.72, 0)
	var beam_material := StandardMaterial3D.new()
	beam_material.albedo_color = Color(0.070588, 0.627451, 0.686275, 0.28)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = beam_material
	add_child(beam)

	var label := Label3D.new()
	label.text = "部署点 · DEPLOY"
	label.font_size = 30
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 1.55, 0)
	label.modulate = Color(0.66, 0.94, 0.98, 0.95)
	add_child(label)
