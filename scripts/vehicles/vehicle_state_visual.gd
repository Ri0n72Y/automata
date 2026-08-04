extends Node3D
class_name VehicleStateVisual

var _actor: VehicleActor
var _carry_warning: Label3D
var _tray_slots_root: Node3D
var _tray_count_label: Label3D
var _last_arm_has_item: bool = false
var _last_tray_count: int = -1
var _initialized: bool = false


func _ready() -> void:
	_actor = get_parent() as VehicleActor
	_carry_warning = get_node_or_null("CarryWarning") as Label3D
	_tray_slots_root = get_node_or_null("TraySlots") as Node3D
	_tray_count_label = get_node_or_null("TrayCountLabel") as Label3D
	refresh_visual(true)


func _process(_delta: float) -> void:
	refresh_visual()


func refresh_visual(force: bool = false) -> void:
	if _actor == null:
		_actor = get_parent() as VehicleActor
	if _actor == null or _actor.runtime_state == null:
		return

	var arm_has_item: bool = _actor.runtime_state.arm_has_item
	var tray_count: int = _actor.runtime_state.tray_count
	if force or not _initialized or arm_has_item != _last_arm_has_item:
		if _carry_warning != null:
			_carry_warning.visible = arm_has_item
		_last_arm_has_item = arm_has_item
	if force or not _initialized or tray_count != _last_tray_count:
		_refresh_tray_visual(tray_count)
		_last_tray_count = tray_count
	_initialized = true


func is_carry_warning_visible() -> bool:
	return _carry_warning != null and _carry_warning.visible


func get_visible_tray_slot_count() -> int:
	if _tray_slots_root == null:
		return 0
	var visible_count: int = 0
	for child in _tray_slots_root.get_children():
		var slot := child as Node3D
		if slot != null and slot.visible:
			visible_count += 1
	return visible_count


func get_tray_count_label_text() -> String:
	return _tray_count_label.text if _tray_count_label != null else ""


func _refresh_tray_visual(tray_count: int) -> void:
	var slot_count: int = _tray_slots_root.get_child_count() if _tray_slots_root != null else 0
	var visible_count: int = clampi(tray_count, 0, slot_count)
	if _tray_slots_root != null:
		for index in range(slot_count):
			var slot := _tray_slots_root.get_child(index) as Node3D
			if slot != null:
				slot.visible = index < visible_count
	if _tray_count_label != null:
		var capacity: int = slot_count
		if _actor.definition != null and _actor.definition.tray_capacity > 0:
			capacity = _actor.definition.tray_capacity
		_tray_count_label.text = "%d/%d" % [tray_count, capacity]
