extends SceneTree

# 一次性构建工具：把 Arm / Transport 车辆几何合并为多 surface 的 ArrayMesh 资源，
# 每个材质一个 surface（白/深色/橡胶/青色），将每车约 60 个 MeshInstance 降为 1 个。
# 运行：godot --headless --path . --script res://.dsh-visual/build_vehicle_meshes.gd

const OUT_ARM := "res://assets/scene_01/vehicles/arm_vehicle_mesh.res"
const OUT_TRANSPORT := "res://assets/scene_01/vehicles/transport_vehicle_mesh.res"

const MAT_WHITE := "res://scenes/scene_01/materials/painted_white.tres"
const MAT_DARK := "res://scenes/scene_01/materials/dark_mechanical_metal.tres"
const MAT_RUBBER := "res://scenes/scene_01/materials/rubber.tres"
const MAT_CYAN := "res://scenes/scene_01/materials/cyan_emissive.tres"

const SHELL_OBJ := "res://assets/scene_01/meshes/rounded_shell.obj"
const PANEL_OBJ := "res://assets/scene_01/meshes/beveled_panel.obj"

var _materials := {}
var _shell_mesh: Mesh
var _panel_mesh: Mesh
var _groups := {}
var _group_order: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_materials = {
		"white": load(MAT_WHITE),
		"dark": load(MAT_DARK),
		"rubber": load(MAT_RUBBER),
		"cyan": load(MAT_CYAN),
	}
	_shell_mesh = load(SHELL_OBJ)
	_panel_mesh = load(PANEL_OBJ)
	if _shell_mesh == null or _panel_mesh == null:
		print("BUILD FAIL: missing source meshes")
		quit(1)
		return

	var arm := _build_vehicle(true)
	_save(arm, OUT_ARM)
	var transport := _build_vehicle(false)
	_save(transport, OUT_TRANSPORT)
	quit(0)


func _new_groups() -> void:
	_groups.clear()
	_group_order.clear()
	for group_name in ["white", "dark", "rubber", "cyan"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_groups[group_name] = st
		_group_order.append(group_name)


func _add(group_name: String, mesh: Mesh, pos: Vector3, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> void:
	var st: SurfaceTool = _groups[group_name]
	var basis := Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(scale)
	st.append_from(mesh, 0, Transform3D(basis, pos))


func _box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cylinder(radius: float, height: float, segments := 24) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	return m


func _sphere(radius: float, segments := 20) -> Mesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 6)
	return m


func _capsule(radius: float, height: float, segments := 20) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 4
	return m


func _wheel(pos: Vector3) -> void:
	_add("rubber", _cylinder(0.155, 0.115), pos, Vector3(0, 0, 90))
	_add("dark", _cylinder(0.095, 0.122), pos, Vector3(0, 0, 90))
	_add("white", _cylinder(0.055, 0.128), pos, Vector3(0, 0, 90))


func _common_chassis() -> void:
	# wheels + axles
	for z in [-0.255, 0.255]:
		_add("dark", _cylinder(0.03, 0.64, 12), Vector3(0, 0.155, z), Vector3(0, 0, 90))
		_wheel(Vector3(-0.325, 0.155, z))
		_wheel(Vector3(0.325, 0.155, z))
	_add("dark", _panel_mesh, Vector3(0, 0.20, 0), Vector3.ZERO, Vector3(0.62, 0.15, 0.54))


func _build_vehicle(is_arm: bool) -> ArrayMesh:
	_new_groups()

	if is_arm:
		_build_arm()
	else:
		_build_transport()

	var result := ArrayMesh.new()
	var surface_index := 0
	for group_name in _group_order:
		var st: SurfaceTool = _groups[group_name]
		st.commit(result)
		result.surface_set_material(surface_index, _materials[group_name])
		surface_index += 1
	return result


func _build_arm() -> void:
	_common_chassis()

	# white shell + pale top deck with a dark inset service plate
	_add("white", _shell_mesh, Vector3(0, 0.36, 0), Vector3.ZERO, Vector3(0.60, 0.245, 0.56))
	_add("white", _panel_mesh, Vector3(0, 0.515, 0.01), Vector3.ZERO, Vector3(0.42, 0.045, 0.38))
	_add("dark", _panel_mesh, Vector3(0, 0.545, 0.03), Vector3.ZERO, Vector3(0.28, 0.018, 0.22))
	_add("white", _panel_mesh, Vector3(0, 0.545, 0.20), Vector3.ZERO, Vector3(0.30, 0.025, 0.10))
	_add("dark", _box(Vector3(0.26, 0.12, 0.10)), Vector3(0, 0.43, 0.30))

	# bumpers / skirts / eye bezel
	_add("dark", _box(Vector3(0.56, 0.075, 0.075)), Vector3(0, 0.235, -0.335))
	_add("dark", _box(Vector3(0.56, 0.075, 0.075)), Vector3(0, 0.235, 0.335))
	_add("dark", _box(Vector3(0.035, 0.10, 0.40)), Vector3(-0.315, 0.33, 0))
	_add("dark", _box(Vector3(0.035, 0.10, 0.40)), Vector3(0.315, 0.33, 0))
	_add("dark", _box(Vector3(0.18, 0.09, 0.03)), Vector3(0, 0.36, -0.285))
	_add("cyan", _cylinder(0.045, 0.02), Vector3(0, 0.36, -0.30), Vector3(90, 0, 0))
	_add("cyan", _box(Vector3(0.30, 0.028, 0.02)), Vector3(0, 0.47, -0.30))
	_add("cyan", _box(Vector3(0.26, 0.028, 0.02)), Vector3(0, 0.555, 0.30))

	# arm base / shoulder: white turret shell with dark articulation rings
	_add("white", _cylinder(0.145, 0.10), Vector3(0, 0.585, 0.06))
	_add("dark", _cylinder(0.152, 0.022, 24), Vector3(0, 0.528, 0.06))
	_add("cyan", _cylinder(0.148, 0.012, 24), Vector3(0, 0.634, 0.06))
	_add("white", _sphere(0.105), Vector3(0, 0.70, 0.05))
	_add("dark", _sphere(0.075), Vector3(0, 0.70, -0.02))
	# upper arm: shoulder -> elbow
	_add("white", _capsule(0.080, 0.44), Vector3(0, 0.89, -0.01), Vector3(-26, 0, 0))
	_add("dark", _sphere(0.082), Vector3(0, 1.06, -0.09))
	# lower arm: elbow -> wrist
	_add("white", _capsule(0.064, 0.34), Vector3(0, 1.17, -0.20), Vector3(-41, 0, 0))
	_add("dark", _sphere(0.075), Vector3(0, 1.28, -0.30))
	_add("cyan", _cylinder(0.08, 0.016, 20), Vector3(0, 1.30, -0.32), Vector3(-41, 0, 0))
	# work head + grippers
	_add("white", _box(Vector3(0.24, 0.09, 0.10)), Vector3(0, 1.33, -0.40))
	_add("white", _box(Vector3(0.065, 0.11, 0.22)), Vector3(-0.115, 1.33, -0.51), Vector3(0, 8, 0))
	_add("white", _box(Vector3(0.065, 0.11, 0.22)), Vector3(0.115, 1.33, -0.51), Vector3(0, -8, 0))
	_add("dark", _box(Vector3(0.05, 0.055, 0.10)), Vector3(-0.115, 1.29, -0.61))
	_add("dark", _box(Vector3(0.05, 0.055, 0.10)), Vector3(0.115, 1.29, -0.61))
	_add("cyan", _box(Vector3(0.02, 0.03, 0.18)), Vector3(-0.145, 1.33, -0.51))
	_add("cyan", _box(Vector3(0.02, 0.03, 0.18)), Vector3(0.145, 1.33, -0.51))

	# side markers
	_add("cyan", _box(Vector3(0.02, 0.03, 0.28)), Vector3(-0.304, 0.405, 0))
	_add("cyan", _box(Vector3(0.02, 0.03, 0.28)), Vector3(0.304, 0.405, 0))

	# side panel seams + sensor pods + antenna
	for x in [-0.301, 0.301]:
		_add("dark", _box(Vector3(0.006, 0.14, 0.42)), Vector3(x, 0.355, 0))
	_add("dark", _box(Vector3(0.07, 0.05, 0.07)), Vector3(-0.20, 0.505, -0.22))
	_add("dark", _box(Vector3(0.07, 0.05, 0.07)), Vector3(0.20, 0.505, -0.22))
	_add("cyan", _box(Vector3(0.035, 0.018, 0.035)), Vector3(-0.20, 0.535, -0.22))
	_add("cyan", _box(Vector3(0.035, 0.018, 0.035)), Vector3(0.20, 0.535, -0.22))
	_add("dark", _cylinder(0.008, 0.30, 8), Vector3(0.235, 0.66, 0.235))
	_add("cyan", _sphere(0.02, 12), Vector3(0.235, 0.815, 0.235))


func _build_transport() -> void:
	_common_chassis()

	# white body + tray shell
	_add("white", _shell_mesh, Vector3(0, 0.355, 0), Vector3.ZERO, Vector3(0.64, 0.23, 0.54))
	_add("white", _shell_mesh, Vector3(0, 0.635, 0), Vector3.ZERO, Vector3(0.66, 0.07, 0.58))
	_add("white", _box(Vector3(0.04, 0.14, 0.56)), Vector3(-0.33, 0.72, 0))
	_add("white", _box(Vector3(0.04, 0.14, 0.56)), Vector3(0.33, 0.72, 0))
	_add("white", _box(Vector3(0.70, 0.035, 0.04)), Vector3(0, 0.79, -0.285))
	_add("white", _box(Vector3(0.70, 0.035, 0.04)), Vector3(0, 0.79, 0.285))

	# dark tray frame / bed / posts / bumpers
	_add("dark", _shell_mesh, Vector3(0, 0.565, 0), Vector3.ZERO, Vector3(0.70, 0.055, 0.62))
	_add("dark", _box(Vector3(0.56, 0.02, 0.48)), Vector3(0, 0.666, 0))
	for x in [-0.315, 0.315]:
		for z in [-0.275, 0.275]:
			_add("dark", _cylinder(0.032, 0.17, 16), Vector3(x, 0.72, z))
	_add("dark", _box(Vector3(0.56, 0.075, 0.075)), Vector3(0, 0.245, -0.335))
	_add("dark", _box(Vector3(0.56, 0.075, 0.075)), Vector3(0, 0.245, 0.335))
	_add("dark", _box(Vector3(0.36, 0.085, 0.03)), Vector3(0, 0.45, -0.275))
	_add("dark", _box(Vector3(0.20, 0.10, 0.03)), Vector3(0, 0.36, -0.29))
	_add("dark", _box(Vector3(0.16, 0.06, 0.08)), Vector3(0, 0.25, 0.345))

	# eye + status + tray light (all four tray edges so any facing reads)
	_add("cyan", _cylinder(0.048, 0.02), Vector3(0, 0.36, -0.305), Vector3(90, 0, 0))
	_add("cyan", _box(Vector3(0.04, 0.028, 0.02)), Vector3(-0.24, 0.44, -0.288))
	_add("cyan", _box(Vector3(0.04, 0.028, 0.02)), Vector3(0.24, 0.44, -0.288))
	_add("cyan", _box(Vector3(0.52, 0.02, 0.02)), Vector3(0, 0.575, -0.315))
	_add("cyan", _box(Vector3(0.52, 0.02, 0.02)), Vector3(0, 0.575, 0.315))
	_add("cyan", _box(Vector3(0.02, 0.02, 0.50)), Vector3(-0.352, 0.595, 0))
	_add("cyan", _box(Vector3(0.02, 0.02, 0.50)), Vector3(0.352, 0.595, 0))
	_add("cyan", _box(Vector3(0.04, 0.028, 0.02)), Vector3(0, 0.585, 0.315))

	# side panel seams + sensor pods + antenna
	for x in [-0.321, 0.321]:
		_add("dark", _box(Vector3(0.005, 0.14, 0.44)), Vector3(x, 0.35, 0))
	_add("dark", _box(Vector3(0.07, 0.05, 0.07)), Vector3(-0.22, 0.50, -0.245))
	_add("dark", _box(Vector3(0.07, 0.05, 0.07)), Vector3(0.22, 0.50, -0.245))
	_add("cyan", _box(Vector3(0.035, 0.018, 0.035)), Vector3(-0.22, 0.53, -0.245))
	_add("cyan", _box(Vector3(0.035, 0.018, 0.035)), Vector3(0.22, 0.53, -0.245))
	_add("dark", _cylinder(0.008, 0.26, 8), Vector3(0.245, 0.65, 0.245))
	_add("cyan", _sphere(0.02, 12), Vector3(0.245, 0.78, 0.245))


func _save(mesh: ArrayMesh, path: String) -> void:
	var err := ResourceSaver.save(mesh, path)
	print("SAVED ", path, " surfaces=", mesh.get_surface_count(), " err=", err)
