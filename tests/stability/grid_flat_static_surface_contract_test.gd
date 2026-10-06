extends SceneTree

const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const FIELD_SCENE := preload("res://scenes/scene_01/components/scene_01_field_16x10.tscn")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var view = FIELD_SCENE.instantiate()
	root.add_child(view)

	var model = GRID_MODEL_SCRIPT.new()
	_expect_true(model.configure(16, 10, 1.0), "Flat grid fixture should configure.")
	view.rebuild(model)

	_expect_true(
		view.is_using_flat_static_surface(),
		"Default 16x10 boundary-ring model should use the flat static surface."
	)
	_expect_true(view.is_using_static_scene(), "Flat surface should satisfy scene-owned rendering semantics.")
	_expect_false(view.is_using_dynamic_scene(), "Grid view must not generate per-cell runtime meshes.")
	_expect_equal(view.get_tile_count(), 160, "Flat renderer should report all represented model cells.")
	_expect_true(view.get_tile_node(Vector2i(1, 1)) == null, "Flat renderer must not own per-cell MeshInstance nodes.")
	_expect_true(view.get_ground_body() != null, "Flat renderer must preserve the authoritative ground collider.")

	_expect_true(
		model._set_cell_type(Vector2i(1, 1), GRID_MODEL_SCRIPT.CellType.NORMAL_TILE),
		"Fixture should be able to introduce a cell type the fixed surface cannot represent."
	)
	view.rebuild(model)
	_expect_false(
		view.is_using_flat_static_surface(),
		"Fixed surface must fail closed when model cell types diverge from its visual contract."
	)
	_expect_false(view.is_using_dynamic_scene(), "Unsupported models must not resurrect per-cell mesh generation.")
	_expect_equal(view.get_tile_count(), 0, "Unsupported model should expose no active rendered cells.")
	_expect_true(view.get_ground_body() == null, "Unsupported model should disable the scene-owned ground collider.")

	view.free()
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Grid flat static surface contract tests passed.")
		quit(0)
		return
	push_error("Grid flat static surface contract tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)


func _expect_false(value: bool, message: String) -> void:
	if not value:
		return
	failures += 1
	push_error(message)
