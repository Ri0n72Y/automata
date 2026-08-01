class_name VehicleMoveController
extends Node3D

signal move_requested(vehicle_id: StringName, target_anchor: Vector2i)
signal move_accepted(vehicle_id: StringName, target_anchor: Vector2i)
signal move_rejected(vehicle_id: StringName, target_anchor: Vector2i, reason: StringName)
signal move_stopped(vehicle_id: StringName)

const GridPathfinderScript := preload("res://scripts/vehicles/grid_pathfinder.gd")
const MoveCommandScript := preload("res://scripts/vehicles/move_command.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const Scene01VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

const STOP_TASK_ACTION := &"vehicle_stop_task"
const REJECTION_NO_VEHICLE := &"no_vehicle_selected"
const REJECTION_BUSY := &"vehicle_busy"
const REJECTION_NO_PATH := &"no_path"
const REJECTION_START_FAILED := &"start_failed"
const MOTION_EPSILON := 0.000001

@export var valid_target_color: Color = Color(0.2, 0.9, 0.35, 0.20)
@export var invalid_target_color: Color = Color(1.0, 0.2, 0.18, 0.23)
@export var valid_path_color: Color = Color(0.2, 0.95, 0.42, 0.88)
@export var invalid_path_color: Color = Color(1.0, 0.28, 0.22, 0.82)
@export_range(0.01, 0.2, 0.01) var preview_height: float = 0.05
@export_range(0.8, 1.0, 0.01) var preview_scale: float = 0.94
@export_range(0.02, 0.2, 0.01) var path_line_width: float = 0.07
@export_range(0.01, 0.2, 0.01) var path_line_height: float = 0.075

var controller: Node
var vehicle_selection_controller: VehicleSelectionControllerScript
var grid_selection_controller: GridSelectionControllerScript
var vehicle_manager: Scene01VehicleManagerScript
var _pathfinder := GridPathfinderScript.new()
var _target_preview: MeshInstance3D
var _path_preview_root: Node3D
var _path_segments: Array[MeshInstance3D] = []
var _preview_path: Array[Vector2i] = []
var _preview_is_valid: bool = false
var _last_rejection_reason: StringName = &""
var _vehicle_ui_open: bool = false
var _observed_vehicle: VehicleActorScript
var _managed_vehicles: Array[VehicleActorScript] = []
var _valid_path_material: StandardMaterial3D
var _invalid_path_material: StandardMaterial3D


func _ready() -> void:
	_target_preview = _create_target_preview()
	add_child(_target_preview)
	_path_preview_root = Node3D.new()
	_path_preview_root.name = "VehiclePathPreview"
	add_child(_path_preview_root)
	_valid_path_material = _create_path_material(valid_path_color)
	_invalid_path_material = _create_path_material(invalid_path_color)


func _physics_process(delta: float) -> void:
	_advance_managed_vehicles(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _vehicle_ui_open:
		return
	if event is InputEventKey:
		if event.echo or _has_command_modifier(event):
			return
	if not event.is_action_pressed(STOP_TASK_ACTION):
		return
	if request_selected_vehicle_stop():
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_replace_observed_vehicle(null)
	_disconnect_managed_vehicle_signals()


func configure(
	p_controller: Node,
	p_vehicle_selection_controller: VehicleSelectionControllerScript,
	p_grid_selection_controller: GridSelectionControllerScript,
	p_vehicle_manager: Scene01VehicleManagerScript
) -> void:
	controller = p_controller
	vehicle_selection_controller = p_vehicle_selection_controller
	grid_selection_controller = p_grid_selection_controller
	vehicle_manager = p_vehicle_manager
	_connect_input_signals()
	_connect_managed_vehicle_signals()
	_sync_live_target_mode()


func set_vehicle_ui_open(is_open: bool) -> void:
	if _vehicle_ui_open == is_open:
		return
	_vehicle_ui_open = is_open
	_sync_live_target_mode()


func is_vehicle_ui_open() -> bool:
	return _vehicle_ui_open


func request_selected_vehicle_move(target_anchor: Vector2i) -> bool:
	var vehicle := _get_selected_vehicle()
	var vehicle_id: StringName = &""
	if vehicle != null:
		vehicle_id = vehicle.get_vehicle_id()
	move_requested.emit(vehicle_id, target_anchor)
	if vehicle == null:
		_reject(vehicle_id, target_anchor, REJECTION_NO_VEHICLE)
		return false
	if vehicle.runtime_state == null or not vehicle.runtime_state.begin_move_planning():
		_reject(vehicle_id, target_anchor, REJECTION_BUSY)
		refresh_target_preview()
		return false

	var path := _find_path(vehicle, target_anchor)
	if path.is_empty():
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_NO_PATH)
		refresh_target_preview()
		return false

	var command := MoveCommandScript.new()
	if not command.configure(target_anchor, path):
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_NO_PATH)
		refresh_target_preview()
		return false

	if command.state == MoveCommandScript.State.WAITING:
		vehicle.runtime_state.clear_move_command()
		_clear_grid_target()
		_last_rejection_reason = &""
		move_accepted.emit(vehicle_id, target_anchor)
		_sync_live_target_mode()
		return true

	if not vehicle.start_move(command):
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_START_FAILED)
		refresh_target_preview()
		return false

	vehicle.set_physics_process(false)
	_clear_grid_target()
	_last_rejection_reason = &""
	move_accepted.emit(vehicle_id, target_anchor)
	return true


func request_selected_vehicle_stop() -> bool:
	var vehicle := _get_selected_vehicle()
	if not _is_vehicle_moving(vehicle):
		return false
	var vehicle_id := vehicle.get_vehicle_id()
	vehicle.cancel_move()
	move_stopped.emit(vehicle_id)
	return true


func reset_controller_state() -> void:
	_last_rejection_reason = &""
	_vehicle_ui_open = false
	_hide_prediction()


func refresh_target_preview() -> void:
	if _target_preview == null or grid_selection_controller == null:
		_hide_prediction()
		return
	var vehicle := _get_selected_vehicle()
	if not _can_show_prediction(vehicle):
		_hide_prediction()
		return
	if not grid_selection_controller.has_selected_cell():
		_hide_prediction()
		return

	var target_anchor := grid_selection_controller.selected_cell
	var footprint: Vector2i = vehicle.definition.footprint
	var cell_size := vehicle.cell_size
	var path := _find_path(vehicle, target_anchor)
	_preview_path = path.duplicate()
	_preview_is_valid = not path.is_empty()

	var mesh := _target_preview.mesh as BoxMesh
	mesh.size = Vector3(
		float(footprint.x) * cell_size * preview_scale,
		0.02,
		float(footprint.y) * cell_size * preview_scale
	)
	var world_center: Vector3 = controller.call(
		"grid_footprint_center_to_world",
		target_anchor,
		footprint
	)
	_target_preview.position = to_local(world_center) + Vector3.UP * preview_height
	var target_material := _target_preview.material_override as StandardMaterial3D
	target_material.albedo_color = valid_target_color if _preview_is_valid else invalid_target_color
	_target_preview.visible = true
	_update_path_preview(path, footprint, _preview_is_valid)


func sync_visuals() -> void:
	refresh_target_preview()


func is_target_preview_visible() -> bool:
	return _target_preview != null and _target_preview.visible


func is_target_preview_valid() -> bool:
	return is_target_preview_visible() and _preview_is_valid


func is_path_preview_visible() -> bool:
	for segment in _path_segments:
		if segment != null and segment.visible:
			return true
	return false


func get_preview_path() -> Array[Vector2i]:
	return _preview_path.duplicate()


func get_last_rejection_reason() -> StringName:
	return _last_rejection_reason


func _connect_input_signals() -> void:
	if grid_selection_controller != null:
		var confirmed_callable := Callable(self, "_on_grid_selection_confirmed")
		if not grid_selection_controller.selection_confirmed.is_connected(confirmed_callable):
			grid_selection_controller.selection_confirmed.connect(confirmed_callable)
		var grid_changed_callable := Callable(self, "_on_grid_selection_changed")
		if not grid_selection_controller.selection_changed.is_connected(grid_changed_callable):
			grid_selection_controller.selection_changed.connect(grid_changed_callable)
	if vehicle_selection_controller != null:
		var vehicle_changed_callable := Callable(self, "_on_vehicle_selection_changed")
		if not vehicle_selection_controller.selection_changed.is_connected(vehicle_changed_callable):
			vehicle_selection_controller.selection_changed.connect(vehicle_changed_callable)


func _connect_managed_vehicle_signals() -> void:
	_disconnect_managed_vehicle_signals()
	if vehicle_manager == null:
		return
	for vehicle_node in vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		_managed_vehicles.append(vehicle)
		var started_callable := Callable(self, "_on_managed_vehicle_move_started").bind(vehicle)
		if not vehicle.move_started.is_connected(started_callable):
			vehicle.move_started.connect(started_callable)
		if _is_vehicle_moving(vehicle):
			vehicle.set_physics_process(false)


func _disconnect_managed_vehicle_signals() -> void:
	for vehicle in _managed_vehicles:
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		var started_callable := Callable(self, "_on_managed_vehicle_move_started").bind(vehicle)
		if vehicle.move_started.is_connected(started_callable):
			vehicle.move_started.disconnect(started_callable)
	_managed_vehicles.clear()


func _on_managed_vehicle_move_started(_target_anchor: Vector2i, vehicle: VehicleActorScript) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	vehicle.set_physics_process(false)
	if vehicle == _get_selected_vehicle():
		_sync_live_target_mode()


func _on_grid_selection_confirmed(target_anchor: Vector2i) -> void:
	if grid_selection_controller == null or not grid_selection_controller.is_live_target_mode():
		return
	request_selected_vehicle_move(target_anchor)


func _on_grid_selection_changed(_cell: Vector2i, _has_selection: bool) -> void:
	refresh_target_preview()


func _on_vehicle_selection_changed(_vehicle_id: StringName, _has_selection: bool) -> void:
	_sync_live_target_mode()


func _on_observed_vehicle_move_started(_target_anchor: Vector2i) -> void:
	_hide_prediction()


func _on_observed_vehicle_move_completed(_target_anchor: Vector2i) -> void:
	_sync_live_target_mode()


func _on_observed_vehicle_move_blocked() -> void:
	_sync_live_target_mode()


func _sync_live_target_mode() -> void:
	if grid_selection_controller == null:
		return
	var vehicle := _get_selected_vehicle()
	_replace_observed_vehicle(vehicle)
	var interaction_enabled := (
		vehicle != null
		and not _vehicle_ui_open
		and vehicle.runtime_state != null
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.PLANNING
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING
	)
	var footprint := Vector2i.ONE
	if vehicle != null and vehicle.definition != null:
		footprint = vehicle.definition.footprint
	grid_selection_controller.set_live_target_mode(interaction_enabled, footprint)
	if _can_show_prediction(vehicle):
		refresh_target_preview()
	else:
		_hide_prediction()


func _can_show_prediction(vehicle: VehicleActorScript) -> bool:
	if vehicle == null or _vehicle_ui_open:
		return false
	if vehicle.definition == null or vehicle.runtime_state == null:
		return false
	return (
		vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.PLANNING
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING
	)


func _replace_observed_vehicle(vehicle: VehicleActorScript) -> void:
	if _observed_vehicle == vehicle:
		return
	_disconnect_observed_vehicle()
	_observed_vehicle = vehicle
	if _observed_vehicle == null or not is_instance_valid(_observed_vehicle):
		return
	var started_callable := Callable(self, "_on_observed_vehicle_move_started")
	if not _observed_vehicle.move_started.is_connected(started_callable):
		_observed_vehicle.move_started.connect(started_callable)
	var completed_callable := Callable(self, "_on_observed_vehicle_move_completed")
	if not _observed_vehicle.move_completed.is_connected(completed_callable):
		_observed_vehicle.move_completed.connect(completed_callable)
	var blocked_callable := Callable(self, "_on_observed_vehicle_move_blocked")
	if not _observed_vehicle.move_blocked.is_connected(blocked_callable):
		_observed_vehicle.move_blocked.connect(blocked_callable)


func _disconnect_observed_vehicle() -> void:
	if _observed_vehicle == null or not is_instance_valid(_observed_vehicle):
		_observed_vehicle = null
		return
	var started_callable := Callable(self, "_on_observed_vehicle_move_started")
	if _observed_vehicle.move_started.is_connected(started_callable):
		_observed_vehicle.move_started.disconnect(started_callable)
	var completed_callable := Callable(self, "_on_observed_vehicle_move_completed")
	if _observed_vehicle.move_completed.is_connected(completed_callable):
		_observed_vehicle.move_completed.disconnect(completed_callable)
	var blocked_callable := Callable(self, "_on_observed_vehicle_move_blocked")
	if _observed_vehicle.move_blocked.is_connected(blocked_callable):
		_observed_vehicle.move_blocked.disconnect(blocked_callable)
	_observed_vehicle = null


func _get_selected_vehicle() -> VehicleActorScript:
	if vehicle_selection_controller == null:
		return null
	return vehicle_selection_controller.get_selected_vehicle()


func _advance_managed_vehicles(delta: float) -> void:
	if vehicle_manager == null:
		return
	var duration := maxf(delta, 0.0)
	if duration <= MOTION_EPSILON:
		return

	var vehicles: Array[VehicleActorScript] = []
	for vehicle_node in vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		vehicles.append(vehicle)

	for vehicle in vehicles:
		if not _is_vehicle_moving(vehicle):
			continue
		if vehicle.runtime_state.get_effective_speed() > 0.0:
			continue
		vehicle.cancel_move()

	var plans: Array[Dictionary] = []
	for vehicle in vehicles:
		plans.append(_build_motion_plan(vehicle, duration))

	var collision := _find_earliest_collision_event(vehicles, plans)
	if collision.is_empty():
		_advance_all_moving(vehicles, duration)
		return

	var event_time := clampf(float(collision.get("time", 0.0)), 0.0, duration)
	var moving_ids: Dictionary = collision.get("moving_ids", {})
	for index in range(vehicles.size()):
		var vehicle := vehicles[index]
		if moving_ids.has(vehicle.get_instance_id()):
			var safe_time := _last_safe_completed_time(index, plans, event_time)
			if safe_time > MOTION_EPSILON and _is_vehicle_moving(vehicle):
				vehicle.advance_move(safe_time)
			if _is_vehicle_moving(vehicle):
				vehicle.cancel_move()
			continue
		if event_time > MOTION_EPSILON and _is_vehicle_moving(vehicle):
			vehicle.advance_move(event_time)


func _last_safe_completed_time(
	plan_index: int,
	plans: Array[Dictionary],
	collision_time: float
) -> float:
	if plan_index < 0 or plan_index >= plans.size():
		return 0.0
	var plan := plans[plan_index]
	var footprint: Vector2 = plan.get("footprint", Vector2.ZERO)
	var last_safe_time := 0.0
	var segments: Array = plan.get("segments", [])
	for segment_variant in segments:
		var segment: Dictionary = segment_variant
		if not bool(segment.get("moving", false)):
			continue
		var end_time := float(segment.get("end_time", 0.0))
		if end_time > collision_time + MOTION_EPSILON:
			continue
		var end_position: Vector2 = segment.get("end", Vector2.ZERO)
		var candidate := Rect2(end_position, footprint)
		var overlaps := false
		for other_index in range(plans.size()):
			if other_index == plan_index:
				continue
			var other_plan := plans[other_index]
			var other_size: Vector2 = other_plan.get("footprint", Vector2.ZERO)
			var other_position := _plan_position_at(other_plan, end_time)
			if _rects_overlap(candidate, Rect2(other_position, other_size)):
				overlaps = true
				break
		if not overlaps:
			last_safe_time = maxf(last_safe_time, end_time)
	return last_safe_time


func _plan_position_at(plan: Dictionary, time: float) -> Vector2:
	var segments: Array = plan.get("segments", [])
	if segments.is_empty():
		return Vector2.ZERO
	for segment_variant in segments:
		var segment: Dictionary = segment_variant
		var start_time := float(segment.get("start_time", 0.0))
		var end_time := float(segment.get("end_time", start_time))
		if time < start_time - MOTION_EPSILON or time > end_time + MOTION_EPSILON:
			continue
		return _segment_position_at(segment, time)
	var first_segment: Dictionary = segments.front()
	if time <= float(first_segment.get("start_time", 0.0)):
		return first_segment.get("start", Vector2.ZERO)
	var last_segment: Dictionary = segments.back()
	return last_segment.get("end", Vector2.ZERO)


func _advance_all_moving(vehicles: Array[VehicleActorScript], delta: float) -> void:
	for vehicle in vehicles:
		if _is_vehicle_moving(vehicle):
			vehicle.advance_move(delta)


func _build_motion_plan(vehicle: VehicleActorScript, delta: float) -> Dictionary:
	var duration := maxf(delta, 0.0)
	var footprint := Vector2.ZERO
	if vehicle != null and vehicle.definition != null:
		footprint = Vector2(
			float(vehicle.definition.footprint.x),
			float(vehicle.definition.footprint.y)
		)
	var stationary_anchor := _get_vehicle_motion_anchor(vehicle)
	var stationary_segments: Array[Dictionary] = [
		_motion_segment(0.0, duration, stationary_anchor, stationary_anchor, false)
	]
	if not _is_vehicle_moving(vehicle):
		return {
			"moving": false,
			"must_block": false,
			"footprint": footprint,
			"segments": stationary_segments,
		}

	var command: MoveCommandScript = vehicle.runtime_state.active_move_command
	var speed := vehicle.runtime_state.get_effective_speed()
	if speed <= 0.0:
		return {
			"moving": true,
			"must_block": true,
			"footprint": footprint,
			"segments": stationary_segments,
		}

	var segments: Array[Dictionary] = []
	var path_index := command.path_index
	var progress := clampf(vehicle.get_segment_progress(), 0.0, 1.0)
	var elapsed := 0.0
	var current_position := _path_position(command, path_index, progress)
	while elapsed < duration - MOTION_EPSILON and path_index < command.path.size() - 1:
		var remaining_fraction := 1.0 - progress
		var remaining_time := remaining_fraction / speed
		var step_time := minf(duration - elapsed, remaining_time)
		var next_progress := minf(progress + step_time * speed, 1.0)
		var next_position := _path_position(command, path_index, next_progress)
		segments.append(_motion_segment(
			elapsed,
			elapsed + step_time,
			current_position,
			next_position,
			true
		))
		elapsed += step_time
		current_position = next_position
		progress = next_progress
		if progress >= 1.0 - MOTION_EPSILON:
			path_index += 1
			progress = 0.0
			current_position = Vector2(
				float(command.path[path_index].x),
				float(command.path[path_index].y)
			)

	if elapsed < duration - MOTION_EPSILON:
		segments.append(_motion_segment(
			elapsed,
			duration,
			current_position,
			current_position,
			false
		))
	if segments.is_empty():
		segments.append(_motion_segment(
			0.0,
			duration,
			current_position,
			current_position,
			false
		))
	return {
		"moving": true,
		"must_block": false,
		"footprint": footprint,
		"segments": segments,
	}


func _get_vehicle_motion_anchor(vehicle: VehicleActorScript) -> Vector2:
	if vehicle == null or vehicle.runtime_state == null:
		return Vector2.ZERO
	if _is_vehicle_moving(vehicle):
		var command: MoveCommandScript = vehicle.runtime_state.active_move_command
		return _path_position(
			command,
			command.path_index,
			clampf(vehicle.get_segment_progress(), 0.0, 1.0)
		)
	return Vector2(
		float(vehicle.runtime_state.anchor_cell.x),
		float(vehicle.runtime_state.anchor_cell.y)
	)


func _path_position(command: MoveCommandScript, path_index: int, progress: float) -> Vector2:
	if command == null or command.path.is_empty():
		return Vector2.ZERO
	var safe_index := clampi(path_index, 0, command.path.size() - 1)
	var current_anchor := command.path[safe_index]
	if safe_index >= command.path.size() - 1:
		return Vector2(float(current_anchor.x), float(current_anchor.y))
	var next_anchor := command.path[safe_index + 1]
	return Vector2(float(current_anchor.x), float(current_anchor.y)).lerp(
		Vector2(float(next_anchor.x), float(next_anchor.y)),
		clampf(progress, 0.0, 1.0)
	)


func _motion_segment(
	start_time: float,
	end_time: float,
	start_position: Vector2,
	end_position: Vector2,
	is_moving: bool
) -> Dictionary:
	return {
		"start_time": start_time,
		"end_time": end_time,
		"start": start_position,
		"end": end_position,
		"moving": is_moving,
	}


func _find_earliest_collision_event(
	vehicles: Array[VehicleActorScript],
	plans: Array[Dictionary]
) -> Dictionary:
	var earliest_time := INF
	var moving_ids: Dictionary = {}
	for first_index in range(vehicles.size()):
		for second_index in range(first_index + 1, vehicles.size()):
			var first_plan: Dictionary = plans[first_index]
			var second_plan: Dictionary = plans[second_index]
			if not bool(first_plan.get("moving", false)) and not bool(second_plan.get("moving", false)):
				continue
			var collision_time := _motion_plan_collision_time(first_plan, second_plan)
			if is_inf(collision_time):
				continue
			if collision_time < earliest_time - MOTION_EPSILON:
				earliest_time = collision_time
				moving_ids.clear()
			if absf(collision_time - earliest_time) > MOTION_EPSILON:
				continue
			if _plan_was_moving_into_time(first_plan, collision_time):
				moving_ids[vehicles[first_index].get_instance_id()] = true
			if _plan_was_moving_into_time(second_plan, collision_time):
				moving_ids[vehicles[second_index].get_instance_id()] = true

	if is_inf(earliest_time) or moving_ids.is_empty():
		return {}
	return {
		"time": earliest_time,
		"moving_ids": moving_ids,
	}


func _motion_plan_collision_time(first_plan: Dictionary, second_plan: Dictionary) -> float:
	var earliest_time := INF
	var first_segments: Array = first_plan.get("segments", [])
	var second_segments: Array = second_plan.get("segments", [])
	var first_size: Vector2 = first_plan.get("footprint", Vector2.ZERO)
	var second_size: Vector2 = second_plan.get("footprint", Vector2.ZERO)
	for first_variant in first_segments:
		var first_segment: Dictionary = first_variant
		for second_variant in second_segments:
			var second_segment: Dictionary = second_variant
			var overlap_start := maxf(
				float(first_segment.get("start_time", 0.0)),
				float(second_segment.get("start_time", 0.0))
			)
			var overlap_end := minf(
				float(first_segment.get("end_time", 0.0)),
				float(second_segment.get("end_time", 0.0))
			)
			if overlap_start > overlap_end + MOTION_EPSILON:
				continue
			var collision_time := _segments_collision_time(
				first_segment,
				second_segment,
				first_size,
				second_size,
				overlap_start,
				overlap_end
			)
			earliest_time = minf(earliest_time, collision_time)
	return earliest_time


func _segments_collision_time(
	first_segment: Dictionary,
	second_segment: Dictionary,
	first_size: Vector2,
	second_size: Vector2,
	overlap_start: float,
	overlap_end: float
) -> float:
	var first_start := _segment_position_at(first_segment, overlap_start)
	var second_start := _segment_position_at(second_segment, overlap_start)
	var duration := maxf(overlap_end - overlap_start, 0.0)
	if duration <= MOTION_EPSILON:
		if _rects_overlap(Rect2(first_start, first_size), Rect2(second_start, second_size)):
			return overlap_start
		return INF

	var first_end := _segment_position_at(first_segment, overlap_end)
	var second_end := _segment_position_at(second_segment, overlap_end)
	var relative_start := first_start - second_start
	var relative_velocity := ((first_end - first_start) - (second_end - second_start)) / duration
	var x_interval := _axis_overlap_interval(
		relative_start.x,
		relative_velocity.x,
		first_size.x,
		second_size.x,
		duration
	)
	if x_interval.x > x_interval.y:
		return INF
	var y_interval := _axis_overlap_interval(
		relative_start.y,
		relative_velocity.y,
		first_size.y,
		second_size.y,
		duration
	)
	if y_interval.x > y_interval.y:
		return INF
	var entry_time := maxf(x_interval.x, y_interval.x)
	var exit_time := minf(x_interval.y, y_interval.y)
	if entry_time > exit_time:
		return INF
	return overlap_start + maxf(entry_time, 0.0)


func _plan_was_moving_into_time(plan: Dictionary, time: float) -> bool:
	if not bool(plan.get("moving", false)):
		return false
	if time <= MOTION_EPSILON:
		return true
	var segments: Array = plan.get("segments", [])
	for segment_variant in segments:
		var segment: Dictionary = segment_variant
		if not bool(segment.get("moving", false)):
			continue
		var start_time := float(segment.get("start_time", 0.0))
		var end_time := float(segment.get("end_time", start_time))
		if time > start_time + MOTION_EPSILON and time <= end_time + MOTION_EPSILON:
			return true
	return false


func _segment_position_at(segment: Dictionary, time: float) -> Vector2:
	var start_time := float(segment.get("start_time", 0.0))
	var end_time := float(segment.get("end_time", start_time))
	var start_position: Vector2 = segment.get("start", Vector2.ZERO)
	var end_position: Vector2 = segment.get("end", start_position)
	var duration := end_time - start_time
	if duration <= MOTION_EPSILON:
		return start_position
	return start_position.lerp(
		end_position,
		clampf((time - start_time) / duration, 0.0, 1.0)
	)


func _axis_overlap_interval(
	relative_start: float,
	relative_velocity: float,
	first_size: float,
	second_size: float,
	duration: float
) -> Vector2:
	var lower_bound := -first_size + MOTION_EPSILON
	var upper_bound := second_size - MOTION_EPSILON
	if absf(relative_velocity) <= MOTION_EPSILON:
		if relative_start > lower_bound and relative_start < upper_bound:
			return Vector2(0.0, duration)
		return Vector2(1.0, 0.0)
	var lower_time := (lower_bound - relative_start) / relative_velocity
	var upper_time := (upper_bound - relative_start) / relative_velocity
	var entry_time := maxf(0.0, minf(lower_time, upper_time))
	var exit_time := minf(duration, maxf(lower_time, upper_time))
	return Vector2(entry_time, exit_time)


func _rects_overlap(first: Rect2, second: Rect2) -> bool:
	return (
		first.position.x < second.end.x - MOTION_EPSILON
		and first.end.x > second.position.x + MOTION_EPSILON
		and first.position.y < second.end.y - MOTION_EPSILON
		and first.end.y > second.position.y + MOTION_EPSILON
	)


func _is_vehicle_moving(vehicle: VehicleActorScript) -> bool:
	return (
		vehicle != null
		and vehicle.runtime_state != null
		and vehicle.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.MOVING
		and vehicle.runtime_state.active_move_command != null
	)


func _has_command_modifier(event: InputEventKey) -> bool:
	return event.alt_pressed or event.shift_pressed or event.ctrl_pressed or event.meta_pressed


func _find_path(vehicle: VehicleActorScript, target_anchor: Vector2i) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if controller == null or vehicle_manager == null:
		return empty_path
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return empty_path
	var grid_size: Vector2i = controller.call("get_grid_size")
	var walkable := Callable(self, "_is_footprint_walkable_for_vehicle").bind(vehicle)
	return _pathfinder.find_path(
		vehicle.runtime_state.anchor_cell,
		target_anchor,
		vehicle.definition.footprint,
		grid_size,
		walkable
	)


func _is_footprint_walkable_for_vehicle(
	anchor: Vector2i,
	footprint: Vector2i,
	moving_vehicle: VehicleActorScript
) -> bool:
	if not bool(controller.call("is_grid_footprint_walkable", anchor, footprint)):
		return false
	var candidate_cells: Dictionary = {}
	for offset_y in range(footprint.y):
		for offset_x in range(footprint.x):
			candidate_cells[anchor + Vector2i(offset_x, offset_y)] = true
	for vehicle_node in vehicle_manager.get_vehicles():
		var other := vehicle_node as VehicleActorScript
		if other == null or other == moving_vehicle or other.runtime_state == null:
			continue
		for occupied_cell in other.get_occupied_cells():
			if candidate_cells.has(occupied_cell):
				return false
	return true


func _update_path_preview(
	path: Array[Vector2i],
	footprint: Vector2i,
	is_valid: bool
) -> void:
	_hide_path_segments()
	if controller == null or path.size() < 2:
		return
	for index in range(path.size() - 1):
		var segment := _ensure_path_segment(index)
		var start_world: Vector3 = controller.call(
			"grid_footprint_center_to_world",
			path[index],
			footprint
		)
		var end_world: Vector3 = controller.call(
			"grid_footprint_center_to_world",
			path[index + 1],
			footprint
		)
		var start_local := to_local(start_world)
		var end_local := to_local(end_world)
		var delta := end_local - start_local
		var length := Vector2(delta.x, delta.z).length()
		if length <= 0.001:
			continue
		var box_mesh := segment.mesh as BoxMesh
		box_mesh.size = Vector3(length, 0.025, path_line_width)
		segment.position = (start_local + end_local) * 0.5 + Vector3.UP * path_line_height
		segment.rotation = Vector3(0.0, -atan2(delta.z, delta.x), 0.0)
		segment.material_override = _valid_path_material if is_valid else _invalid_path_material
		segment.visible = true


func _ensure_path_segment(index: int) -> MeshInstance3D:
	while _path_segments.size() <= index:
		var segment := MeshInstance3D.new()
		segment.name = "PathSegment_%d" % _path_segments.size()
		segment.visible = false
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment.mesh = BoxMesh.new()
		_path_preview_root.add_child(segment)
		_path_segments.append(segment)
	return _path_segments[index]


func _clear_grid_target() -> void:
	if grid_selection_controller != null:
		grid_selection_controller.cancel_selection()
	_hide_prediction()


func _reject(vehicle_id: StringName, target_anchor: Vector2i, reason: StringName) -> void:
	_last_rejection_reason = reason
	move_rejected.emit(vehicle_id, target_anchor, reason)


func _hide_prediction() -> void:
	_preview_is_valid = false
	_preview_path.clear()
	if _target_preview != null:
		_target_preview.visible = false
	_hide_path_segments()


func _hide_path_segments() -> void:
	for segment in _path_segments:
		if segment != null:
			segment.visible = false


func _create_target_preview() -> MeshInstance3D:
	var preview := MeshInstance3D.new()
	preview.name = "VehicleTargetFootprintPreview"
	preview.visible = false
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	material.albedo_color = valid_target_color
	preview.material_override = material
	return preview


func _create_path_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	material.albedo_color = color
	return material
