extends Node3D
class_name Scene01ItemReceiverNode

@export var receiver_resource: ItemReceiverInterface

var _capacity_slots_root: Node3D
var _capacity_label: Label3D
var _capacity_slots: Array[Node3D] = []


func _ready() -> void:
	_bind_capacity_visual()
	_connect_count_signal()
	refresh_visual()


func _exit_tree() -> void:
	_disconnect_count_signal()


func is_configured() -> bool:
	return receiver_resource != null


func get_receiver_interface() -> ItemReceiverInterface:
	return receiver_resource


func get_accepted_item_types() -> PackedStringArray:
	return receiver_resource.get_accepted_item_types() if receiver_resource != null else PackedStringArray()


func accepts_item_type(item_type: StringName) -> bool:
	return receiver_resource != null and receiver_resource.accepts_item_type(item_type)


func get_interaction_cells() -> Array[Vector2i]:
	if receiver_resource != null:
		return receiver_resource.get_interaction_cells()
	var empty: Array[Vector2i] = []
	return empty


func get_current_count() -> int:
	return receiver_resource.get_current_count() if receiver_resource != null else 0


func get_capacity() -> int:
	return receiver_resource.get_capacity() if receiver_resource != null else 0


func put_item(item: Variant) -> ItemTransferResult:
	if receiver_resource == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return receiver_resource.put_item(item)


func take_item() -> ItemTransferResult:
	if receiver_resource == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return receiver_resource.take_item()


func refresh_visual() -> void:
	var visible_count := clampi(get_current_count(), 0, _capacity_slots.size())
	for index in range(_capacity_slots.size()):
		_capacity_slots[index].visible = index < visible_count
	if _capacity_label != null:
		_capacity_label.text = "%d/%d  IN" % [get_current_count(), get_capacity()]


func get_visible_slot_count() -> int:
	var visible_count: int = 0
	for slot in _capacity_slots:
		if slot.visible:
			visible_count += 1
	return visible_count


func get_capacity_label_text() -> String:
	return _capacity_label.text if _capacity_label != null else ""


func _bind_capacity_visual() -> void:
	_capacity_slots.clear()
	_capacity_slots_root = get_node_or_null("VisualRoot/CapacitySlots") as Node3D
	_capacity_label = get_node_or_null("VisualRoot/CapacityLabel") as Label3D
	if _capacity_slots_root == null:
		return
	for child in _capacity_slots_root.get_children():
		var slot := child as Node3D
		if slot != null:
			_capacity_slots.append(slot)


func _connect_count_signal() -> void:
	if receiver_resource == null or not receiver_resource.has_signal(&"count_changed"):
		return
	var callback := Callable(self, "_on_count_changed")
	if not receiver_resource.is_connected(&"count_changed", callback):
		receiver_resource.connect(&"count_changed", callback)


func _disconnect_count_signal() -> void:
	if receiver_resource == null or not receiver_resource.has_signal(&"count_changed"):
		return
	var callback := Callable(self, "_on_count_changed")
	if receiver_resource.is_connected(&"count_changed", callback):
		receiver_resource.disconnect(&"count_changed", callback)


func _on_count_changed(_previous_count: int, _current_count: int) -> void:
	refresh_visual()
