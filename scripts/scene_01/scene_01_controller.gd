extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")
const GridDebugViewScript := preload("res://scripts/grid/grid_debug_view.gd")

@export_group("Grid")
@export_range(1, 256, 1) var grid_width: int = 12
@export_range(1, 256, 1) var grid_height: int = 8
@export_range(0.1, 10.0, 0.1) var grid_cell_size: float = 1.0
@export var grid_local_origin: Vector3 = Vector3.ZERO

@onready var scene_root: Node3D = %SceneRoot
var grid_root: Node3D
@onready var grid_debug_view: GridDebugViewScript = %GridDebugView
@onready var robot_root: Node3D = %RobotRoot
@onready var object_root: Node3D = %ObjectRoot
@onready var camera_root: Node3D = %CameraRoot
@onready var ui_root: CanvasLayer = %UIRoot

var grid_model: GridModelScript
var box_count: int = 3
var target_box_count: int = 8
var timer: float = 0.0
var automation_rate: float = 0.0
var is_running: bool = false


func _enter_tree() -> void:
	grid_root = get_node_or_null("SceneRoot/GridRoot") as Node3D
	if grid_root == null:
		push_error("Scene 01 is missing GridRoot.")
	initialize_grid()


func _ready() -> void:
	if grid_model != null:
		grid_debug_view.draw(grid_model)
	reset_scene_state()


func _process(delta: float) -> void:
	if is_running:
		timer += delta


func initialize_grid() -> bool:
	var model := GridModelScript.new()
	if not model.configure(
		grid_width,
		grid_height,
		grid_cell_size,
		grid_local_origin
	):
		push_error("Scene 01 grid configuration is invalid.")
		return false

	grid_model = model
	if is_node_ready() and grid_debug_view != null:
		grid_debug_view.draw(grid_model)
	return true


func world_to_grid_cell(world_position: Vector3) -> Vector2i:
	if grid_root == null or grid_model == null:
		push_error("Scene 01 grid is not initialized.")
		return Vector2i(-1, -1)
	var position := grid_root.to_local(world_position)
	return grid_model.position_to_cell(position)


func grid_cell_to_world(cell: Vector2i) -> Vector3:
	if grid_root == null or grid_model == null:
		push_error("Scene 01 grid is not initialized.")
		return Vector3.ZERO
	return grid_root.to_global(grid_model.cell_to_position(cell))


func is_grid_cell_valid(cell: Vector2i) -> bool:
	if grid_model == null:
		return false
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
