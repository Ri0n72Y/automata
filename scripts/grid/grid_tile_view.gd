class_name GridTileView
extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

@export var ground_collision_layer: int = 1

var _tiles_root: Node3D
var _surface_visuals: Node3D
var _playable_floor: MeshInstance3D
var _north_boundary: MeshInstance3D
var _south_boundary: MeshInstance3D
var _west_boundary: MeshInstance3D
var _east_boundary: MeshInstance3D
var _ground_body: StaticBody3D
var _ground_shape: CollisionShape3D
var _surface_active: bool = false


func _ready() -> void:
	if not _bind_surface_nodes():
		push_error("GridTileView is missing required authored field nodes.")


func draw(model: GridModelScript) -> bool:
	if model == null:
		return _fail_validation("GridModel is missing.")
	if not _bind_surface_nodes():
		return _fail_validation("required authored field nodes are missing.")

	var mismatch := _serialized_field_mismatch(model)
	if not mismatch.is_empty():
		return _fail_validation(mismatch)

	_set_ground_enabled(true)
	_surface_active = true
	return true


func is_surface_active() -> bool:
	return _surface_active


func get_ground_body() -> StaticBody3D:
	if _ground_body == null:
		_bind_surface_nodes()
	return _ground_body


func _bind_surface_nodes() -> bool:
	if (
		_tiles_root != null
		and _surface_visuals != null
		and _playable_floor != null
		and _north_boundary != null
		and _south_boundary != null
		and _west_boundary != null
		and _east_boundary != null
		and _ground_body != null
		and _ground_shape != null
	):
		return true

	_tiles_root = get_node_or_null("Tiles") as Node3D
	_surface_visuals = get_node_or_null("Tiles/SurfaceVisuals") as Node3D
	_playable_floor = get_node_or_null("Tiles/SurfaceVisuals/PlayableFloor") as MeshInstance3D
	_north_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/NorthBoundaryCells"
	) as MeshInstance3D
	_south_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/SouthBoundaryCells"
	) as MeshInstance3D
	_west_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/WestBoundaryCells"
	) as MeshInstance3D
	_east_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/EastBoundaryCells"
	) as MeshInstance3D
	_ground_body = get_node_or_null("Tiles/GroundBody") as StaticBody3D
	_ground_shape = get_node_or_null("Tiles/GroundBody/GroundShape") as CollisionShape3D
	return (
		_tiles_root != null
		and _surface_visuals != null
		and _playable_floor != null
		and _north_boundary != null
		and _south_boundary != null
		and _west_boundary != null
		and _east_boundary != null
		and _ground_body != null
		and _ground_shape != null
	)


func _serialized_field_mismatch(model: GridModelScript) -> String:
	var width := float(model.width) * model.cell_size
	var height := float(model.height) * model.cell_size
	var boundary_width := model.cell_size
	var side_height := height - boundary_width * 2.0

	if not _tiles_root.position.is_equal_approx(model.local_origin):
		return "Tiles origin does not match GridModel.local_origin."
	if not _tiles_root.scale.is_equal_approx(Vector3.ONE):
		return "Tiles scale must stay at Vector3.ONE."
	if not _surface_visuals.visible:
		return "SurfaceVisuals must be authored visible."
	if side_height <= 0.0:
		return "GridModel is too small for the authored four-edge warning boundary."

	var mismatch := _plane_mismatch(_playable_floor, Vector2(width, height), "PlayableFloor")
	if not mismatch.is_empty():
		return mismatch
	mismatch = _plane_mismatch(
		_north_boundary,
		Vector2(width, boundary_width),
		"NorthBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _plane_mismatch(
		_south_boundary,
		Vector2(width, boundary_width),
		"SouthBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _plane_mismatch(
		_west_boundary,
		Vector2(boundary_width, side_height),
		"WestBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _plane_mismatch(
		_east_boundary,
		Vector2(boundary_width, side_height),
		"EastBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch

	if not _playable_floor.position.is_equal_approx(Vector3(width * 0.5, 0.002, height * 0.5)):
		return "PlayableFloor position does not match serialized GridModel geometry."
	if not _north_boundary.position.is_equal_approx(
		Vector3(width * 0.5, 0.01, boundary_width * 0.5)
	):
		return "North warning position does not match serialized GridModel geometry."
	if not _south_boundary.position.is_equal_approx(
		Vector3(width * 0.5, 0.01, height - boundary_width * 0.5)
	):
		return "South warning position does not match serialized GridModel geometry."
	if not _west_boundary.position.is_equal_approx(
		Vector3(boundary_width * 0.5, 0.01, height * 0.5)
	):
		return "West warning position does not match serialized GridModel geometry."
	if not _east_boundary.position.is_equal_approx(
		Vector3(width - boundary_width * 0.5, 0.01, height * 0.5)
	):
		return "East warning position does not match serialized GridModel geometry."

	mismatch = _shader_vector2_mismatch(
		_playable_floor,
		&"tile_repeat",
		Vector2(float(model.width), float(model.height)),
		"PlayableFloor"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _shader_vector2_mismatch(
		_north_boundary,
		&"tile_repeat",
		Vector2(float(model.width), 1.0),
		"NorthBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _shader_vector2_mismatch(
		_south_boundary,
		&"tile_repeat",
		Vector2(float(model.width), 1.0),
		"SouthBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	var side_repeat := float(model.height - 2)
	mismatch = _shader_vector2_mismatch(
		_west_boundary,
		&"tile_repeat",
		Vector2(1.0, side_repeat),
		"WestBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _shader_vector2_mismatch(
		_east_boundary,
		&"tile_repeat",
		Vector2(1.0, side_repeat),
		"EastBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch

	mismatch = _shader_vector2_mismatch(
		_north_boundary,
		&"tile_origin",
		Vector2.ZERO,
		"NorthBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _shader_vector2_mismatch(
		_south_boundary,
		&"tile_origin",
		Vector2(0.0, float(model.height - 1)),
		"SouthBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _shader_vector2_mismatch(
		_west_boundary,
		&"tile_origin",
		Vector2(0.0, 1.0),
		"WestBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch
	mismatch = _shader_vector2_mismatch(
		_east_boundary,
		&"tile_origin",
		Vector2(float(model.width - 1), 1.0),
		"EastBoundaryCells"
	)
	if not mismatch.is_empty():
		return mismatch

	var box_shape := _ground_shape.shape as BoxShape3D
	if box_shape == null:
		return "GroundShape must use an authored BoxShape3D."
	if not box_shape.size.is_equal_approx(Vector3(width, 0.08, height)):
		return "GroundShape size does not match serialized GridModel geometry."
	if not _ground_shape.position.is_equal_approx(Vector3(width * 0.5, -0.04, height * 0.5)):
		return "GroundShape position does not match serialized GridModel geometry."
	if _ground_body.collision_mask != 0:
		return "GroundBody collision_mask must stay zero."

	return ""


func _plane_mismatch(node: MeshInstance3D, expected_size: Vector2, label: String) -> String:
	var plane := node.mesh as PlaneMesh
	if plane == null:
		return "%s must use an authored PlaneMesh." % label
	if not plane.size.is_equal_approx(expected_size):
		return "%s PlaneMesh size does not match GridModel." % label
	return ""


func _shader_vector2_mismatch(
	node: MeshInstance3D,
	parameter: StringName,
	expected: Vector2,
	label: String
) -> String:
	var actual := Vector2(node.get_instance_shader_parameter(parameter))
	if not actual.is_equal_approx(expected):
		return "%s %s does not match GridModel." % [label, parameter]
	return ""


func _fail_validation(message: String) -> bool:
	_surface_active = false
	_set_ground_enabled(false)
	push_error("GridTileView serialized field validation failed: %s" % message)
	return false


func _set_ground_enabled(enabled: bool) -> void:
	if _ground_body == null or _ground_shape == null:
		return
	_ground_body.collision_layer = ground_collision_layer if enabled else 0
	_ground_body.collision_mask = 0
	_ground_shape.disabled = not enabled
