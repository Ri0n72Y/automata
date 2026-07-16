extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")
const GridDebugViewScript := preload("res://scripts/grid/grid_debug_view.gd")
const GridTileViewScript := preload("res://scripts/grid/grid_tile_view.gd")
const SceneCameraRigScript := preload("res://scripts/camera/scene_01_camera_rig.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")

@export_group("Grid")
@export_range(1, 256, 1) var grid_width: int = 12
@export_range(1, 256, 1) var grid_height: int = 8
@export_range(0.1, 10.0, 0.1) var grid_cell_size: float = 1.0
@export var grid_local_origin: Vector3 = Vector3.ZERO

@onready var scene_root: Node3D = %SceneRoot
var grid_root: Node3D
@onready var grid_tile_view: GridTileViewScript = %GridTileView
@onready var grid_debug_view: GridDebugViewScript = %GridDebugView
@onready var grid_selection_controller: GridSelectionControllerScript = %GridSelectionController
@onready var robot_root: Node3D = %RobotRoot
@onready var object_root: Node3D = %ObjectRoot
@onready var camera_root: Node3D = %CameraRoot
@onready var scene_camera_rig: SceneCameraRigScript = %Scene01CameraRig
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
		_configure_grid_dependents()
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
	if is_node_ready():
		_configure_grid_dependents()
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


func get_grid_cell_type(cell: Vector2i) -> int:
	if grid_model == null:
		return GridModelScript.CellType.BOUNDARY
	return grid_model.get_cell_type(cell)


func is_grid_cell_walkable(cell: Vector2i) -> bool:
	if grid_model == null:
		return false
	return grid_model.is_cell_walkable(cell)


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
	if grid_selection_controller != null:
		grid_selection_controller.clear_hover()
		grid_selection_controller.cancel_selection()


func _configure_grid_dependents() -> void:
	if grid_model == null or grid_root == null:
		return

	if grid_tile_view != null:
		grid_tile_view.draw(grid_model)
	if grid_debug_view != null:
		grid_debug_view.draw(grid_model)

	var local_center := grid_model.local_origin + Vector3(
		float(grid_model.width) * grid_model.cell_size * 0.5,
		0.0,
		float(grid_model.height) * grid_model.cell_size * 0.5
	)
	var world_center := grid_root.to_global(local_center)
	var world_scale := grid_root.global_basis.get_scale().abs()
	var world_width := float(grid_model.width) * grid_model.cell_size * world_scale.x
	var world_height := float(grid_model.height) * grid_model.cell_size * world_scale.z

	if scene_camera_rig != null:
		scene_camera_rig.configure_for_grid(world_center, world_width, world_height)
	if grid_selection_controller != null:
		var active_camera: Camera3D
		if scene_camera_rig != null:
			active_camera = scene_camera_rig.get_camera()
		grid_selection_controller.configure(self, active_camera, grid_model.cell_size)
