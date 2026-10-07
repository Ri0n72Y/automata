class_name GridTileView
extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")
const PLAYABLE_GRID_SIZE_PARAMETER := &"tile_repeat"

@export var ground_collision_layer: int = 1

var _tiles_root: Node3D
var _playable_floor: MeshInstance3D
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

	var mismatch := _model_compatibility_mismatch(model)
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
		and _playable_floor != null
		and _ground_body != null
		and _ground_shape != null
	):
		return true

	_tiles_root = get_node_or_null("Tiles") as Node3D
	_playable_floor = get_node_or_null("Tiles/SurfaceVisuals/PlayableFloor") as MeshInstance3D
	_ground_body = get_node_or_null("Tiles/GroundBody") as StaticBody3D
	_ground_shape = get_node_or_null("Tiles/GroundBody/GroundShape") as CollisionShape3D
	return (
		_tiles_root != null
		and _playable_floor != null
		and _ground_body != null
		and _ground_shape != null
	)


func _model_compatibility_mismatch(model: GridModelScript) -> String:
	var plane := _playable_floor.mesh as PlaneMesh
	if plane == null:
		return "PlayableFloor must provide an authored PlaneMesh compatibility surface."

	var authored_grid_size_variant := _playable_floor.get_instance_shader_parameter(
		PLAYABLE_GRID_SIZE_PARAMETER
	)
	if not (authored_grid_size_variant is Vector2):
		return "PlayableFloor is missing its authored logical grid size."
	var authored_grid_size: Vector2 = authored_grid_size_variant
	var model_grid_size := Vector2(float(model.width), float(model.height))
	if not authored_grid_size.is_equal_approx(model_grid_size):
		return "GridModel dimensions do not match the authored PlayableFloor grid."

	var model_physical_size := Vector2(
		float(model.width) * model.cell_size,
		float(model.height) * model.cell_size
	)
	if not plane.size.is_equal_approx(model_physical_size):
		return "GridModel physical size does not match the authored PlayableFloor bounds."

	var authored_origin := _tiles_root.position + Vector3(
		_playable_floor.position.x - plane.size.x * 0.5,
		0.0,
		_playable_floor.position.z - plane.size.y * 0.5
	)
	if not authored_origin.is_equal_approx(model.local_origin):
		return "GridModel origin does not match the authored PlayableFloor bounds."

	if not (_ground_shape.shape is BoxShape3D):
		return "GroundShape must provide an authored BoxShape3D interaction surface."

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
