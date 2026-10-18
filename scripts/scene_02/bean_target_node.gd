class_name BeanTargetNode
extends Node3D

## Scene-side target bin: receiver-only inventory plus number/gram presentation.

@export var capacity_grams: int = 1000
@export var interaction_cell: Vector2i = Vector2i.ZERO

var inventory: BeanTargetInventory
var box_number: int = 0
var _number_label: Label3D
var _grams_label: Label3D


func _ready() -> void:
	position = Vector3(interaction_cell.x + 0.5, 0.0, interaction_cell.y + 0.5)
	inventory = BeanTargetInventory.new()
	inventory.configure(capacity_grams, interaction_cell)
	inventory.grams_changed.connect(_on_grams_changed)
	_build_visual()


func get_receiver_interface() -> ItemReceiverInterface:
	return inventory


func get_occupied_cell() -> Vector2i:
	return interaction_cell


func set_box_number(value: int) -> void:
	box_number = value
	if _number_label != null:
		_number_label.text = "#%d" % box_number


func is_target_number() -> bool:
	return box_number >= 1 and box_number <= 3


func _build_visual() -> void:
	var shell_material := StandardMaterial3D.new()
	shell_material.albedo_color = Color(0.807, 0.807, 0.776, 1)
	shell_material.roughness = 0.5
	shell_material.metallic = 0.0
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.055, 0.065, 0.075, 1)
	rim_material.roughness = 0.55
	rim_material.metallic = 0.3
	var bean_material := StandardMaterial3D.new()
	bean_material.albedo_color = Color(0.85, 0.78, 0.6, 1)
	bean_material.roughness = 0.8

	var shell := MeshInstance3D.new()
	var shell_mesh := BoxMesh.new()
	shell_mesh.size = Vector3(0.88, 0.5, 0.88)
	shell.mesh = shell_mesh
	shell.position = Vector3(0, 0.25, 0)
	shell.material_override = shell_material
	add_child(shell)

	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(0.92, 0.06, 0.92)
	rim.mesh = rim_mesh
	rim.position = Vector3(0, 0.52, 0)
	rim.material_override = rim_material
	add_child(rim)

	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.7, 0.06, 0.7)
	fill.mesh = fill_mesh
	fill.position = Vector3(0, 0.44, 0)
	fill.material_override = bean_material
	add_child(fill)

	_number_label = Label3D.new()
	_number_label.text = "#?"
	_number_label.font_size = 96
	_number_label.outline_size = 0
	_number_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_number_label.no_depth_test = true
	_number_label.position = Vector3(0, 1.0, 0)
	_number_label.modulate = Color(0.08, 0.09, 0.1, 1)
	add_child(_number_label)

	_grams_label = Label3D.new()
	_grams_label.text = "0 / %d g" % capacity_grams
	_grams_label.font_size = 22
	_grams_label.outline_size = 6
	_grams_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_grams_label.no_depth_test = true
	_grams_label.position = Vector3(0, 1.42, 0)
	_grams_label.modulate = Color(0.85, 0.95, 1.0, 1)
	add_child(_grams_label)


func _on_grams_changed(total_grams: int) -> void:
	if _grams_label != null:
		_grams_label.text = "%d / %d g" % [total_grams, capacity_grams]
