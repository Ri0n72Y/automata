extends Control

## Main menu / landing screen: pick a level or jump straight into the assembly
## workshop. The right side renders a slowly rotating showcase vehicle.

const LEVEL_SCENE_01 := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LEVEL_SCENE_02 := "res://scenes/scene_02/scene_02_bean_sorting.tscn"
const VisualScript := preload("res://scripts/assembly/vehicle_part_visual.gd")

@onready var showcase_root: Node3D = %ShowcaseModelRoot
@onready var showcase_pivot: Node3D = %ShowcasePivot
@onready var showcase_camera: Camera3D = %ShowcaseCamera
@onready var scene_one_button: Button = %SceneOneButton
@onready var scene_two_button: Button = %SceneTwoButton
@onready var workshop_button: Button = %WorkshopButton
@onready var quit_button: Button = %QuitButton

var _vehicle: Node3D


func _ready() -> void:
	scene_one_button.pressed.connect(_open_level.bind(LEVEL_SCENE_01))
	scene_two_button.pressed.connect(_open_level.bind(LEVEL_SCENE_02))
	workshop_button.pressed.connect(_open_workshop)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	_build_showcase()
	_build_showcase_stage()
	showcase_camera.look_at(Vector3(0.0, 0.72, 0.0), Vector3.UP)


func _process(delta: float) -> void:
	if showcase_pivot != null:
		showcase_pivot.rotation.y += delta * 0.22


func _build_showcase() -> void:
	_vehicle = VisualScript.build_vehicle(&"differential", &"standard", &"gripper_arm")
	showcase_root.add_child(_vehicle)


func _build_showcase_stage() -> void:
	var viewport := showcase_camera.get_parent() as SubViewport
	if viewport == null:
		return
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(9.0, 0.04, 9.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.03, 0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.055, 0.098, 0.125, 1)
	floor_material.roughness = 0.9
	floor.material_override = floor_material
	viewport.add_child(floor)
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.11, 0.2, 0.235, 1)
	line_material.roughness = 0.8
	for index in range(-6, 7):
		var offset := float(index) * 0.5
		for axis in [0, 1]:
			var line := MeshInstance3D.new()
			var line_mesh := BoxMesh.new()
			line_mesh.size = Vector3(9.0, 0.012, 0.018) if axis == 0 else Vector3(0.018, 0.012, 9.0)
			line.mesh = line_mesh
			line.position = Vector3(0, -0.005, offset) if axis == 0 else Vector3(offset, -0.005, 0)
			line.material_override = line_material
			viewport.add_child(line)


func _open_level(path: String) -> void:
	GameFlow.start_in_workshop = false
	get_tree().change_scene_to_file(path)


func _open_workshop() -> void:
	GameFlow.start_in_workshop = true
	get_tree().change_scene_to_file(LEVEL_SCENE_01)
