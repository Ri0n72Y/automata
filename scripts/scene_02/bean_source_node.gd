class_name BeanSourceNode
extends Node3D

## Scene-side bean source: owns the finite inventory and its presentation.
## Placement cell is exported and converted to world position on ready.

@export var bean_type: StringName = BeanBatch.TYPE_SOYBEAN
@export var capacity_grams: int = 1000
@export var interaction_cell: Vector2i = Vector2i.ZERO

var inventory: BeanSourceInventory
var _label: Label3D


func _ready() -> void:
	position = Vector3(interaction_cell.x + 0.5, 0.0, interaction_cell.y + 0.5)
	inventory = BeanSourceInventory.new()
	inventory.configure(bean_type, capacity_grams, interaction_cell)
	inventory.grams_changed.connect(_on_grams_changed)
	_build_visual()
	_update_label()


func get_source_interface() -> ItemSourceInterface:
	return inventory


func get_occupied_cell() -> Vector2i:
	return interaction_cell


func _build_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = BeanBatch.color_for(bean_type)
	material.roughness = 0.72
	material.metallic = 0.0
	var base_color := BeanBatch.color_for(bean_type).darkened(0.45)
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = base_color
	base_material.roughness = 0.6

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.86, 0.12, 0.86)
	base.mesh = base_mesh
	base.position = Vector3(0, 0.06, 0)
	base.material_override = base_material
	add_child(base)

	for index in range(4):
		var cube := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.34, 0.26, 0.34)
		cube.mesh = mesh
		cube.material_override = material
		var angle := float(index) * 1.7
		cube.position = Vector3(cos(angle) * 0.18, 0.3 + float(index) * 0.06, sin(angle) * 0.18)
		cube.rotation.y = angle
		add_child(cube)

	_label = Label3D.new()
	_label.text = ""
	_label.font_size = 30
	_label.outline_size = 7
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0, 1.15, 0)
	_label.modulate = Color(0.9, 0.95, 1.0, 1)
	add_child(_label)


func _on_grams_changed(_remaining: int) -> void:
	_update_label()


func _update_label() -> void:
	if _label == null or inventory == null:
		return
	_label.text = "%s\n%d g" % [BeanBatch.display_name_for(bean_type), inventory.remaining_grams]
