extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const OUTPUT_DIR := "res://p2_capture_output"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_output)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("Unable to create P2 capture directory: %s" % mkdir_error)
		quit(1)
		return

	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Unable to load Scene 01 for P2 capture.")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _settle()
	if not _save_capture("p2_overall.png"):
		quit(1)
		return

	_hide_ui(scene)
	var rig := scene.get_node_or_null("SceneRoot/CameraRoot/Scene01CameraRig") as Node3D
	var camera := rig.get_node_or_null("SceneCamera") as Camera3D if rig != null else null
	if camera == null:
		push_error("Scene 01 capture camera is missing.")
		quit(1)
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true

	var receiver := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager/StandardBox") as Node3D
	if receiver == null:
		push_error("StandardBox is missing from Scene 01.")
		quit(1)
		return
	_frame_object(camera, receiver.global_position, 2.5)
	await _settle()
	if not _save_capture("p2_standard_box.png"):
		quit(1)
		return

	var source := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager/InfiniteBlockPile") as Node3D
	if source == null:
		push_error("InfiniteBlockPile is missing from Scene 01.")
		quit(1)
		return
	_frame_object(camera, source.global_position, 2.5)
	await _settle()
	if not _save_capture("p2_infinite_block_pile.png"):
		quit(1)
		return

	quit(0)


func _settle() -> void:
	for _index in range(8):
		await process_frame


func _hide_ui(scene: Node) -> void:
	for path in ["HUDRoot", "OperationsUIRoot", "UIRoot", "LifecycleUIRoot", "DebugUIRoot"]:
		var layer := scene.get_node_or_null(path)
		if layer != null:
			layer.set("visible", false)


func _frame_object(camera: Camera3D, target: Vector3, size: float) -> void:
	camera.size = size
	camera.global_position = target + Vector3(2.35, 1.9, 2.35)
	camera.look_at(target + Vector3(0, 0.35, 0), Vector3.UP)


func _save_capture(file_name: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Viewport capture was empty: %s" % file_name)
		return false
	var path := "%s/%s" % [OUTPUT_DIR, file_name]
	var result := image.save_png(path)
	if result != OK:
		push_error("Unable to save capture %s: %s" % [path, result])
		return false
	print("Saved capture: %s" % path)
	return true
