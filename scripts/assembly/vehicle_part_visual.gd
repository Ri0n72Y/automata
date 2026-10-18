class_name VehiclePartVisual
extends RefCounted

## 3D workbench preview for the blueprint editor. Geometry is built from
## primitives so each part reads as a distinct silhouette without new assets.

const SHELL := Color(0.878, 0.898, 0.89, 1)
const SHELL_EDGE := Color(0.545, 0.58, 0.59, 1)
const DARK := Color(0.13, 0.15, 0.16, 1)
const TIRE := Color(0.075, 0.085, 0.095, 1)
const CYAN := Color(0.17, 0.78, 0.82, 1)
const CYAN_DIM := Color(0.17, 0.78, 0.82, 0.55)
const AMBER := Color(0.88, 0.58, 0.2, 1)
const AMBER_DIM := Color(0.88, 0.58, 0.2, 0.55)
const SLOT_CHASSIS := 0
const SLOT_WHEEL := 1
const SLOT_MODULE := 2


static func build_vehicle(chassis_id: StringName, wheel_id: StringName, module_id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "PreviewVehicle"
	var chassis_slot := _slot_node(root, "ChassisSlot", SLOT_CHASSIS)
	var wheel_slot := _slot_node(root, "WheelSlot", SLOT_WHEEL)
	var module_slot := _slot_node(root, "ModuleSlot", SLOT_MODULE)
	_build_chassis(chassis_slot, chassis_id)
	_build_wheels(wheel_slot, wheel_id)
	_build_module(module_slot, module_id)
	return root


static func build_part_model(slot: int, part_id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "PartPreview"
	match slot:
		SLOT_CHASSIS:
			_build_chassis(root, part_id)
		SLOT_WHEEL:
			_build_wheels(root, part_id)
		_:
			_build_module(root, part_id)
	return root


static func node_aabb(node: Node3D) -> AABB:
	if node == null:
		return AABB()
	return _subtree_aabb(node, Transform3D.IDENTITY)


static func slot_node(root: Node3D, slot: int) -> Node3D:
	match slot:
		SLOT_CHASSIS:
			return root.get_node_or_null("ChassisSlot") as Node3D
		SLOT_WHEEL:
			return root.get_node_or_null("WheelSlot") as Node3D
		SLOT_MODULE:
			return root.get_node_or_null("ModuleSlot") as Node3D
	return null


static func slot_aabb(node: Node3D) -> AABB:
	if node == null:
		return AABB()
	return _subtree_aabb(node, node.transform)


static func make_selection_box(aabb: AABB) -> Node3D:
	var root := Node3D.new()
	root.name = "SelectionCage"
	var expanded := aabb.grow(0.035)
	_add_dashed_box(root, expanded, CYAN, 0.02, 3)
	return root


static func _slot_node(parent: Node3D, node_name: String, slot: int) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.set_meta("blueprint_slot", slot)
	parent.add_child(node)
	return node


static func _subtree_aabb(node: Node3D, accumulated: Transform3D) -> AABB:
	var result := AABB()
	var has_value := false
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var transformed := _transform_aabb(
				mesh_instance.get_aabb(),
				accumulated * mesh_instance.transform
			)
			result = transformed if not has_value else result.merge(transformed)
			has_value = true
		elif child is Node3D:
			var nested := _subtree_aabb(child as Node3D, accumulated * child.transform)
			if nested.size != Vector3.ZERO:
				result = nested if not has_value else result.merge(nested)
				has_value = true
	return result


static func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var center := aabb.get_center()
	var half := aabb.size * 0.5
	var transformed := AABB(transform * (center + half * Vector3(-1, -1, -1)), Vector3.ZERO)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				transformed = transformed.expand(transform * (center + half * Vector3(x, y, z)))
	return transformed


# -------------------------------------------------------------------- chassis

static func _build_chassis(parent: Node3D, chassis_id: StringName) -> void:
	match chassis_id:
		&"skid_steer":
			_add_box(parent, Vector3(1.36, 0.3, 0.98), Vector3(0, 0.37, 0), SHELL)
			_add_box(parent, Vector3(1.42, 0.16, 1.06), Vector3(0, 0.2, 0), DARK)
			_add_box(parent, Vector3(1.12, 0.05, 0.74), Vector3(0, 0.53, 0), SHELL_EDGE)
			_add_box(parent, Vector3(0.5, 0.025, 0.02), Vector3(0, 0.41, -0.5), CYAN, true)
		&"omni":
			_add_cylinder(parent, 0.62, 0.3, Vector3(0, 0.38, 0), SHELL)
			_add_cylinder(parent, 0.46, 0.06, Vector3(0, 0.55, 0), SHELL_EDGE)
			for index in range(3):
				var angle := TAU * float(index) / 3.0 + 0.4
				var position := Vector3(cos(angle) * 0.5, 0.24, sin(angle) * 0.5)
				_add_cylinder(parent, 0.16, 0.14, position, TIRE)
			_add_cylinder(parent, 0.2, 0.03, Vector3(0, 0.59, 0), CYAN, true)
		_:
			_add_box(parent, Vector3(1.16, 0.26, 0.84), Vector3(0, 0.37, 0), SHELL)
			_add_box(parent, Vector3(0.98, 0.06, 0.68), Vector3(0, 0.52, 0), SHELL_EDGE)
			_add_box(parent, Vector3(0.44, 0.025, 0.02), Vector3(0, 0.41, -0.43), CYAN, true)
			_add_box(parent, Vector3(0.08, 0.12, 0.84), Vector3(0.46, 0.3, 0), DARK)
			_add_box(parent, Vector3(0.08, 0.12, 0.84), Vector3(-0.46, 0.3, 0), DARK)


static func _build_wheels(parent: Node3D, wheel_id: StringName) -> void:
	var radius := 0.26
	var width := 0.18
	var hub := SHELL
	if wheel_id == &"fast":
		radius = 0.22
		width = 0.15
		hub = CYAN
	elif wheel_id == &"heavy":
		radius = 0.31
		width = 0.24
		hub = AMBER
	for x in [-0.56, 0.56]:
		for z in [-0.36, 0.36]:
			_add_wheel(parent, Vector3(x, radius, z), radius, width, hub)


static func _add_wheel(parent: Node3D, position: Vector3, radius: float, width: float, hub_color: Color) -> void:
	var tire := _add_cylinder(parent, radius, width, position, TIRE)
	tire.rotation.z = PI * 0.5
	var hub := _add_cylinder(parent, radius * 0.46, width * 1.06, position, hub_color, true)
	hub.rotation.z = PI * 0.5


# --------------------------------------------------------------------- module

static func _build_module(parent: Node3D, module_id: StringName) -> void:
	match module_id:
		&"gripper_arm":
			# Industrial 2-link arm + parallel gripper, every joint visibly connected.
			_add_cylinder(parent, 0.15, 0.1, Vector3(0, 0.56, 0.26), DARK)
			_add_cylinder(parent, 0.12, 0.18, Vector3(0, 0.68, 0.26), SHELL)
			_add_sphere(parent, 0.11, Vector3(0, 0.79, 0.26), CYAN)
			var elbow := Vector3(0.04, 1.12, 0.08)
			_add_rod(parent, Vector3(0, 0.79, 0.26), elbow, 0.11, SHELL)
			_add_sphere(parent, 0.1, elbow, CYAN)
			var wrist := Vector3(0.02, 1.3, -0.16)
			_add_rod(parent, elbow, wrist, 0.09, SHELL)
			_add_sphere(parent, 0.08, wrist, CYAN)
			_add_rod(parent, wrist, Vector3(0.02, 1.28, -0.27), 0.055, SHELL_EDGE)
			_add_box(parent, Vector3(0.3, 0.07, 0.1), Vector3(0.02, 1.25, -0.32), SHELL_EDGE)
			_add_box(parent, Vector3(0.05, 0.2, 0.07), Vector3(-0.11, 1.14, -0.34), SHELL)
			_add_box(parent, Vector3(0.05, 0.2, 0.07), Vector3(0.15, 1.14, -0.34), SHELL)
			_add_box(parent, Vector3(0.05, 0.05, 0.07), Vector3(-0.11, 1.03, -0.34), DARK)
			_add_box(parent, Vector3(0.05, 0.05, 0.07), Vector3(0.15, 1.03, -0.34), DARK)
		&"cargo_tray":
			_add_box(parent, Vector3(0.82, 0.06, 0.62), Vector3(0, 0.62, 0), SHELL)
			_add_box(parent, Vector3(0.82, 0.2, 0.04), Vector3(0, 0.72, 0.3), SHELL)
			_add_box(parent, Vector3(0.82, 0.2, 0.04), Vector3(0, 0.72, -0.3), SHELL)
			_add_box(parent, Vector3(0.04, 0.2, 0.62), Vector3(0.4, 0.72, 0), SHELL)
			_add_box(parent, Vector3(0.04, 0.2, 0.62), Vector3(-0.4, 0.72, 0), SHELL)
			_add_box(parent, Vector3(0.62, 0.02, 0.02), Vector3(0, 0.79, 0.28), CYAN, true)
			_add_box(parent, Vector3(0.62, 0.02, 0.02), Vector3(0, 0.79, -0.28), CYAN, true)
		_:
			_add_dashed_box(parent, AABB(Vector3(-0.36, 0.58, -0.32), Vector3(0.72, 0.5, 0.64)), AMBER_DIM, 0.014, 4)
			for corner in [
				Vector3(-0.36, 0.58, -0.32), Vector3(0.36, 0.58, -0.32),
				Vector3(-0.36, 0.58, 0.32), Vector3(0.36, 0.58, 0.32),
				Vector3(-0.36, 1.08, -0.32), Vector3(0.36, 1.08, -0.32),
				Vector3(-0.36, 1.08, 0.32), Vector3(0.36, 1.08, 0.32),
			]:
				_add_sphere(parent, 0.028, corner, AMBER_DIM)


# ------------------------------------------------------------------- helpers

static func _material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	material.metallic = 0.0
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.9
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


static func _add_box(
	parent: Node3D,
	size: Vector3,
	position: Vector3,
	color: Color,
	emission: bool = false
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = _material(color, emission)
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_cylinder(
	parent: Node3D,
	radius: float,
	height: float,
	position: Vector3,
	color: Color,
	emission: bool = false
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = _material(color, emission)
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_sphere(parent: Node3D, radius: float, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = _material(color, true)
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_rod(
	parent: Node3D,
	from: Vector3,
	to: Vector3,
	thickness: float,
	color: Color
) -> MeshInstance3D:
	var direction := to - from
	var length := direction.length()
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, maxf(length, 0.01))
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	var midpoint := from + direction * 0.5
	var up := Vector3.UP
	if absf(direction.normalized().dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	mesh_instance.transform = Transform3D(Basis.IDENTITY, midpoint).looking_at(to, up)
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_dashed_box(parent: Node3D, aabb: AABB, color: Color, thickness: float, segments: int) -> void:
	var min_corner := aabb.position
	var max_corner := aabb.position + aabb.size
	var corners := [
		Vector3(min_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, max_corner.z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for edge in edges:
		_add_dashed_segment(parent, corners[edge[0]], corners[edge[1]], color, thickness, segments)


static func _add_dashed_segment(
	parent: Node3D,
	from: Vector3,
	to: Vector3,
	color: Color,
	thickness: float,
	segments: int
) -> void:
	var direction := to - from
	var length := direction.length()
	if length <= 0.001:
		return
	var segment_length := length / float(segments)
	for index in range(segments):
		if index % 2 == 1:
			continue
		var start := from + direction.normalized() * (segment_length * float(index))
		var midpoint := start + direction.normalized() * (segment_length * 0.5)
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(thickness, thickness, segment_length)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _material(color, true)
		var transform := Transform3D(Basis.IDENTITY, midpoint)
		var up := Vector3.UP
		if absf(direction.normalized().dot(Vector3.UP)) > 0.99:
			up = Vector3.RIGHT
		mesh_instance.transform = transform.looking_at(midpoint + direction, up)
		parent.add_child(mesh_instance)
