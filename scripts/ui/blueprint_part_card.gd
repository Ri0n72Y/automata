class_name BlueprintPartCard
extends Button

## Bottom-shelf part card: 3D part preview at a 45° angle that auto-rotates on
## hover, plus full name / subtitle / cost text.

const VisualScript := preload("res://scripts/assembly/vehicle_part_visual.gd")

const BG := Color(0.968, 0.976, 0.984, 1)
const BG_HOVER := Color(0.916, 0.958, 0.972, 1)
const BG_SELECTED := Color(0.878, 0.956, 0.976, 1)
const BORDER := Color(0.812, 0.871, 0.898, 1)
const BORDER_SELECTED := Color(0.070588, 0.627451, 0.686275, 1)
const INK := Color(0.062745, 0.109804, 0.137255, 1)
const MUTED := Color(0.376, 0.463, 0.514, 1)
const CYAN := Color(0.070588, 0.627451, 0.686275, 1)
const VIEW_SIZE := Vector2i(132, 58)

var slot: int = 0
var part_id: StringName = &""
var display_name: String = ""
var subtitle: String = ""
var cost_label: String = ""
var selected := false

var _hover := false
var _viewport: SubViewport
var _pivot: Node3D


func configure(p_slot: int, p_part_id: StringName, p_name: String, p_subtitle: String, p_cost: int) -> void:
	slot = p_slot
	part_id = p_part_id
	display_name = p_name
	subtitle = p_subtitle
	cost_label = "" if p_part_id == &"" else "成本 %d" % p_cost
	custom_minimum_size = Vector2(150, 118)
	focus_mode = 0
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_hover_changed.bind(true))
	mouse_exited.connect(_on_hover_changed.bind(false))
	_build_preview()
	queue_redraw()


func _process(delta: float) -> void:
	if not _hover or _pivot == null or _viewport == null:
		return
	_pivot.rotation.y += delta * 1.5
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _on_hover_changed(hover: bool) -> void:
	_hover = hover
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _build_preview() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.position = Vector2(9, 6)
	container.size = Vector2(VIEW_SIZE)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(_viewport)

	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.current = true
	_viewport.add_child(camera)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.9, -0.6, 0)
	key.light_energy = 1.7
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, 2.4, 0)
	fill.light_energy = 0.6
	_viewport.add_child(fill)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.73, 0.81, 0.85, 1)
	environment.ambient_light_energy = 1.0
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_pivot.rotation.y = 0.55
	var model := VisualScript.build_part_model(slot, part_id)
	_pivot.add_child(model)
	var bounds := VisualScript.node_aabb(model)
	if bounds.size != Vector3.ZERO:
		var center := bounds.get_center()
		model.position = -center
		var radius := maxf(bounds.size.length() * 0.5, 0.25)
		var direction := Vector3(1.0, 0.85, 1.0).normalized()
		camera.position = direction * radius * 2.1
		camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var background := BG
	if selected:
		background = BG_SELECTED
	elif _hover:
		background = BG_HOVER
	draw_style_box(_rounded_box(background, BORDER_SELECTED if selected else BORDER, 8), rect)
	var font := get_theme_font("font")
	draw_string(
		font,
		Vector2(6, 78),
		display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x - 12,
		12,
		INK
	)
	if subtitle != "":
		draw_string(
			font,
			Vector2(6, 94),
			subtitle,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x - 12,
			10,
			MUTED
		)
	if cost_label != "":
		draw_string(
			font,
			Vector2(6, 109),
			cost_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x - 12,
			10,
			CYAN
		)


func _rounded_box(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	return box
