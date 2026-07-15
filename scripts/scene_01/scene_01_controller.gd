extends Node3D

@export_group("Grid")
@export_range(1, 256, 1) var grid_width: int = 12
@export_range(1, 256, 1) var grid_height: int = 8
@export_range(0.1, 10.0, 0.1) var grid_cell_size: float = 1.0
@export var grid_local_origin: Vector3 = Vector3.ZERO

@onready var scene_root: Node3D = %SceneRoot
@onready var grid_root: Node3D = %GridRoot
@onready var grid_debug_view: GridDebugView = %GridDebugView
@onready var robot_root: Node3D = %RobotRoot
@onready var object_root: Node3D = %ObjectRoot
@onready var camera_root: Node3D = %CameraRoot
@onready var ui_root: CanvasLayer = %UIRoot

var grid_model: GridModel
var box_count: int = 3
var target_box_count: int = 8
var timer: float = 0.0
var automation_rate: float = 0.0
var is_running: bool = false


func _ready() -> void:
	initialize_grid()
	reset_scene_state()


func _process(delta: float) -> void:
	if is_running:
		timer += delta


func initialize_grid() -> void:
	grid_model = GridModel.new()
	if not grid_model.configure(
		grid_width,
		grid_height,
		grid_cell_size,
		grid_local_origin
	):
		push_error("Scene 01 grid configuration is invalid.")
		return
	grid_debug_view.configure(grid_model)


func world_to_grid_cell(world_position: Vector3) -> Vector2i:
	var local_position := grid_root.to_local(world_position)
	return grid_model.local_to_cell(local_position)


func grid_cell_to_world(cell: Vector2i) -> Vector3:
	return grid_root.to_global(grid_model.cell_to_local(cell))


func is_grid_cell_valid(cell: Vector2i) -> bool:
	return grid_model.is_cell_valid(cell)


func run_scene() -> void:
	is_running = true


func pause_scene() -> void:
	is_running = false


func reset_scene() -> void:
	reset_scene_state()


func reset_scene_state() -> void:
	is_running = false
	timer = 0.0
	box_count = 3
	target_box_count = 8
	automation_rate = 0.0
