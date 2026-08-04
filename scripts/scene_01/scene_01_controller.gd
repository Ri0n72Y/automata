extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")
const GridDebugViewScript := preload("res://scripts/grid/grid_debug_view.gd")
const GridTileViewScript := preload("res://scripts/grid/grid_tile_view.gd")
const SceneCameraRigScript := preload("res://scripts/camera/scene_01_camera_rig.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const VehicleMoveControllerScript := preload("res://scripts/input/vehicle_move_controller.gd")
const Scene01VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const Scene01ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")

@export_group("Grid")
@export_range(1, 256, 1) var grid_width: int = 12
@export_range(1, 256, 1) var grid_height: int = 8
@export_range(0.1, 10.0, 0.1) var grid_cell_size: float = 1.0
@export var grid_local_origin: Vector3 = Vector3.ZERO

@onready var scene_root: Node3D = %SceneRoot
var grid_root: Node3D
@onready var grid_tile_view: GridTileViewScript = %GridTileView
@onready var grid_debug_view: GridDebugViewScript = %GridDebugView
@onready var vehicle_selection_controller: VehicleSelectionControllerScript = %VehicleSelectionController
@onready var vehicle_move_controller: VehicleMoveControllerScript = %VehicleMoveController
@onready var grid_selection_controller: GridSelectionControllerScript = %GridSelectionController
@onready var robot_root: Node3D = %RobotRoot
@onready var scene_vehicle_manager: Scene01VehicleManagerScript = %Scene01VehicleManager
@onready var object_root: Node3D = %ObjectRoot
@onready var scene_object_manager: Scene01ObjectManagerScript = %Scene01ObjectManager
@onready var camera_root: Node3D = %CameraRoot
@onready var scene_camera_rig: SceneCameraRigScript = %Scene01CameraRig
@onready var ui_root: CanvasLayer = %UIRoot

var grid_model: GridModelScript
var box_count: int = 3
var target_box_count: int = 8
var timer: float = 0.0
var automation_rate: float = 0.0
var is_running: bool = false

var _initial_grid_root_transform: Transform3D = Transform3D.IDENTITY
var _preview_scale_enabled: bool = false
var _preview_offset_enabled: bool = false


func _enter_tree() -> void:
	grid_root = get_node_or_null("SceneRoot/GridRoot") as Node3D
	if grid_root == null:
		push_error("Scene 01 is missing GridRoot.")
	initialize_grid()


func _ready() -> void:
	if grid_root != null:
		_initial_grid_root_transform = grid_root.transform
	if grid_model != null and not _configure_initial_grid_dependents():
		push_error("Scene 01 grid dependents failed to initialize.")
	if scene_object_manager != null:
		scene_object_manager.box_count_changed.connect(_on_object_box_count_changed)
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

	if not is_node_ready():
		grid_model = model
		return true

	var previous_model := grid_model
	grid_model = model
	var preparation: Scene01VehicleManagerScript.VehicleBatchPreparation
	if scene_vehicle_manager != null:
		preparation = scene_vehicle_manager.prepare_vehicle_batch(
			self,
			model.cell_size
		)
		if preparation == null:
			grid_model = previous_model
			push_error(
				"Scene 01 grid initialization failed because vehicles rejected the candidate grid."
			)
			return false

	if scene_vehicle_manager != null and not scene_vehicle_manager.commit_vehicle_batch(
		self,
		preparation
	):
		grid_model = previous_model
		push_error("Scene 01 grid initialization failed because vehicle commit was rejected.")
		return false

	if vehicle_move_controller != null:
		vehicle_move_controller.reset_controller_state()
	if vehicle_selection_controller != null:
		vehicle_selection_controller.cancel_selection()
	if grid_selection_controller != null:
		grid_selection_controller.clear_hover()
		grid_selection_controller.cancel_selection()
	_configure_grid_presentation()
	return true


func world_to_grid_cell(world_position: Vector3) -> Vector2i:
	if grid_root == null or grid_model == null:
		push_error("Scene 01 grid is not initialized.")
		return Vector2i(-1, -1)
	var position := grid_root.to_local(world_position)
	return grid_model.position_to_cell(position)


func world_to_nearest_grid_anchor(
	world_position: Vector3,
	footprint: Vector2i = Vector2i.ONE
) -> Vector2i:
	if grid_root == null or grid_model == null:
		push_error("Scene 01 grid is not initialized.")
		return Vector2i(-1, -1)
	var local_position := grid_root.to_local(world_position)
	var anchor := grid_model.position_to_nearest_anchor(local_position, footprint)
	return Vector2i(
		clampi(anchor.x, 0, grid_model.width - 1),
		clampi(anchor.y, 0, grid_model.height - 1)
	)


func grid_cell_to_world(cell: Vector2i) -> Vector3:
	if grid_root == null or grid_model == null:
		push_error("Scene 01 grid is not initialized.")
		return Vector3.ZERO
	return grid_root.to_global(grid_model.cell_to_position(cell))


func grid_footprint_center_to_world(
	anchor_cell: Vector2i,
	footprint: Vector2i
) -> Vector3:
	if grid_root == null or grid_model == null:
		push_error("Scene 01 grid is not initialized.")
		return Vector3.ZERO
	var local_center := grid_model.cell_to_position(anchor_cell) + Vector3(
		float(footprint.x - 1) * grid_model.cell_size * 0.5,
		0.0,
		float(footprint.y - 1) * grid_model.cell_size * 0.5
	)
	return grid_root.to_global(local_center)


func get_grid_world_basis() -> Basis:
	if grid_root == null:
		return Basis.IDENTITY
	return grid_root.global_basis


func get_grid_size() -> Vector2i:
	if grid_model == null:
		return Vector2i.ZERO
	return Vector2i(grid_model.width, grid_model.height)


func is_grid_cell_valid(cell: Vector2i) -> bool:
	if grid_model == null:
		return false
	return grid_model.is_cell_valid(cell)


func get_grid_cell_type(cell: Vector2i) -> int:
	if grid_model == null:
		return GridModelScript.CellType.BOUNDARY
	return grid_model.get_cell_type(cell)


func set_grid_cell_type(cell: Vector2i, cell_type: int) -> bool:
	if grid_model == null:
		return false
	if not grid_model._set_cell_type(cell, cell_type):
		return false
	if is_node_ready() and grid_tile_view != null:
		grid_tile_view.draw(grid_model)
	return true


func is_grid_cell_walkable(cell: Vector2i) -> bool:
	if grid_model == null:
		return false
	return grid_model.is_cell_walkable(cell)


func is_grid_footprint_walkable(
	anchor_cell: Vector2i,
	footprint: Vector2i
) -> bool:
	if grid_model == null or footprint.x <= 0 or footprint.y <= 0:
		return false
	for offset_y in range(footprint.y):
		for offset_x in range(footprint.x):
			var cell := anchor_cell + Vector2i(offset_x, offset_y)
			if not grid_model.is_cell_walkable(cell):
				return false
	return true


func run_scene() -> void:
	is_running = true


func pause_scene() -> void:
	is_running = false


func reset_scene() -> void:
	reset_scene_state()


func reset_scene_state() -> void:
	is_running = false
	timer = 0.0
	target_box_count = 8
	automation_rate = 0.0
	_preview_scale_enabled = false
	_preview_offset_enabled = false
	if grid_root != null:
		grid_root.transform = _initial_grid_root_transform
	if vehicle_move_controller != null:
		vehicle_move_controller.reset_controller_state()
	if vehicle_selection_controller != null:
		vehicle_selection_controller.cancel_selection()
	if grid_selection_controller != null:
		grid_selection_controller.clear_hover()
		grid_selection_controller.cancel_selection()
	if scene_vehicle_manager != null:
		scene_vehicle_manager.reset_vehicles()
		scene_vehicle_manager.sync_vehicles_from_state()
	if scene_object_manager != null:
		scene_object_manager.reset_objects()
		var standard_box := scene_object_manager.get_standard_box()
		box_count = standard_box.get_current_count() if standard_box != null else 3
	else:
		box_count = 3
	_refresh_camera_for_grid()


func preview_rotate_grid(direction: int) -> void:
	if grid_root == null:
		return
	var step := clampi(direction, -1, 1)
	grid_root.rotate_y(float(step) * PI * 0.5)
	_sync_grid_transform_dependents()


func preview_toggle_grid_scale() -> void:
	if grid_root == null:
		return
	_preview_scale_enabled = not _preview_scale_enabled
	grid_root.scale = Vector3(1.35, 1.0, 0.78) if _preview_scale_enabled else Vector3.ONE
	_sync_grid_transform_dependents()


func preview_toggle_grid_offset() -> void:
	if grid_root == null:
		return
	_preview_offset_enabled = not _preview_offset_enabled
	grid_root.position = (
		_initial_grid_root_transform.origin + Vector3(1.5, 0.0, -0.75)
		if _preview_offset_enabled
		else _initial_grid_root_transform.origin
	)
	_sync_grid_transform_dependents()


func preview_restore_grid_transform() -> void:
	if grid_root == null:
		return
	_preview_scale_enabled = false
	_preview_offset_enabled = false
	grid_root.transform = _initial_grid_root_transform
	_sync_grid_transform_dependents()


func _sync_grid_transform_dependents() -> void:
	if scene_vehicle_manager != null:
		scene_vehicle_manager.sync_vehicles_from_state()
	if vehicle_selection_controller != null:
		vehicle_selection_controller.refresh_highlight()
	if grid_selection_controller != null:
		grid_selection_controller.refresh_visuals()
	if vehicle_move_controller != null:
		vehicle_move_controller.sync_visuals()
	_refresh_camera_for_grid()


func _configure_initial_grid_dependents() -> bool:
	if grid_model == null or grid_root == null:
		return false
	if scene_vehicle_manager != null and not scene_vehicle_manager.configure(
		self,
		grid_model.cell_size
	):
		return false
	_configure_grid_presentation()
	return true


func _configure_grid_presentation() -> void:
	if grid_model == null or grid_root == null:
		return

	if grid_tile_view != null:
		grid_tile_view.draw(grid_model)
	if grid_debug_view != null:
		grid_debug_view.draw(grid_model)

	_refresh_camera_for_grid()
	var active_camera: Camera3D
	if scene_camera_rig != null:
		active_camera = scene_camera_rig.get_camera()
	if vehicle_selection_controller != null:
		vehicle_selection_controller.configure(active_camera, scene_vehicle_manager)
	if grid_selection_controller != null:
		grid_selection_controller.configure(self, active_camera, grid_model.cell_size)
	if vehicle_move_controller != null:
		vehicle_move_controller.configure(
			self,
			vehicle_selection_controller,
			grid_selection_controller,
			scene_vehicle_manager
		)


func _refresh_camera_for_grid() -> void:
	if grid_model == null or grid_root == null or scene_camera_rig == null:
		return
	var local_min: Vector3 = grid_model.local_origin
	var local_max: Vector3 = grid_model.local_origin + Vector3(
		float(grid_model.width) * grid_model.cell_size,
		0.0,
		float(grid_model.height) * grid_model.cell_size
	)
	var world_corners: Array[Vector3] = [
		grid_root.to_global(Vector3(local_min.x, local_min.y, local_min.z)),
		grid_root.to_global(Vector3(local_max.x, local_min.y, local_min.z)),
		grid_root.to_global(Vector3(local_min.x, local_min.y, local_max.z)),
		grid_root.to_global(Vector3(local_max.x, local_min.y, local_max.z)),
	]
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for corner in world_corners:
		min_x = minf(min_x, corner.x)
		max_x = maxf(max_x, corner.x)
		min_z = minf(min_z, corner.z)
		max_z = maxf(max_z, corner.z)
	var local_center: Vector3 = (local_min + local_max) * 0.5
	var world_center: Vector3 = grid_root.to_global(local_center)
	var world_width: float = maxf(max_x - min_x, 0.01)
	var world_height: float = maxf(max_z - min_z, 0.01)
	scene_camera_rig.configure_for_grid(world_center, world_width, world_height)


func _on_object_box_count_changed(_previous_count: int, current_count: int) -> void:
	box_count = current_count
