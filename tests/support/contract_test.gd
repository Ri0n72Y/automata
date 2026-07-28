extends RefCounted

var failures: int = 0


func expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)


func expect_false(value: bool, message: String) -> void:
	expect_true(not value, message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func expect_vector3_approx(actual: Vector3, expected: Vector3, message: String) -> void:
	if actual.is_equal_approx(expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func finish(tree: SceneTree, suite_name: String) -> void:
	if failures == 0:
		print("%s passed." % suite_name)
		tree.quit(0)
		return
	push_error("%s failed: %d failure(s)." % [suite_name, failures])
	tree.quit(1)
