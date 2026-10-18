extends SceneTree

# 构建工具：把 Scene 01 实验室环境的静态 MeshInstance 按材质合并成 1 个多 surface 的 ArrayMesh。
# 注意：这是一次性 bake。当前仓库中的环境场景已经是合并后的产物（StaticShell）；
# 再次运行本脚本会因找不到 authored material_override 而中止。若要继续改环境几何，
# 请以 git 历史中的 authored 场景为起点，或改用程序化构建脚本。
# 运行：godot --headless --path . --script res://tools/build_environment_meshes.gd
# 输入：res://scenes/scene_01/components/scene_01_lab_platform_environment.tscn（authored 版本）

const SOURCE_SCENE := "res://scenes/scene_01/components/scene_01_lab_platform_environment.tscn"
const OUT_MESH := "res://assets/scene_01/environment/aperture_environment_mesh.res"
const OUT_DIR := "res://assets/scene_01/environment"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed := load(SOURCE_SCENE) as PackedScene
	if packed == null:
		print("BUILD FAIL: cannot load source scene")
		quit(1)
		return
	var instance := packed.instantiate()
	get_root().add_child(instance)
	await process_frame

	var groups := {}
	for group_name in [
		"res://scenes/scene_01/materials/lab_structural_white.tres",
		"res://scenes/scene_01/materials/painted_white.tres",
		"res://scenes/scene_01/materials/dark_mechanical_metal.tres",
		"res://scenes/scene_01/materials/lab_platform_coating.tres",
		"res://scenes/scene_01/materials/lab_glass.tres",
		"res://scenes/scene_01/materials/cyan_emissive.tres",
		"res://scenes/scene_01/materials/aperture_panel_wall.tres",
		"res://scenes/scene_01/materials/aperture_accent_orange.tres",
		"res://scenes/scene_01/materials/aperture_light_cove.tres",
		"res://scenes/scene_01/materials/aperture_led_dots.tres",
	]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[group_name] = st

	var root_inverse: Transform3D = instance.global_transform.affine_inverse()
	var counts := {}
	var skipped_hidden := 0
	var authored_mesh_nodes := 0
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not _is_effectively_visible(mesh_instance):
			skipped_hidden += 1
			continue
		var material := mesh_instance.material_override
		if material == null:
			continue
		authored_mesh_nodes += 1
		var material_path := material.resource_path
		if not groups.has(material_path):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[material_path] = st
		var st: SurfaceTool = groups[material_path]
		var xform := root_inverse * mesh_instance.global_transform
		var mesh := mesh_instance.mesh
		for surface_index in range(mesh.get_surface_count()):
			st.append_from(mesh, surface_index, xform)
		counts[material_path] = int(counts.get(material_path, 0)) + 1

	var result := ArrayMesh.new()
	var surface_index := 0
	for material_path in groups:
		var st: SurfaceTool = groups[material_path]
		if int(counts.get(material_path, 0)) == 0:
			continue
		st.commit(result)
		result.surface_set_material(surface_index, load(material_path))
		print("SURFACE ", material_path, " nodes=", counts[material_path])
		surface_index += 1

	if authored_mesh_nodes == 0 or result.get_surface_count() == 0:
		print("BUILD ABORT: source scene has no authored MeshInstance materials (already merged?).")
		print("Restore the pre-merge authored scene before re-running this bake.")
		instance.queue_free()
		quit(1)
		return

	var err := ResourceSaver.save(result, OUT_MESH)
	print("SAVED ", OUT_MESH, " surfaces=", result.get_surface_count(), " skipped_hidden=", skipped_hidden, " err=", err)
	instance.queue_free()
	quit(0 if err == OK else 1)


func _is_effectively_visible(node: Node) -> bool:
	var current: Node = node
	while current != null:
		var node_3d := current as Node3D
		if node_3d != null and not node_3d.visible:
			return false
		current = current.get_parent()
	return true
