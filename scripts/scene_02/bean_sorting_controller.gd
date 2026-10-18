class_name BeanSortingController
extends Scene01LifecycleController

## First Bean Sorting puzzle: fixed layout, shuffled box numbers 1-5, manual
## submit settlement. Reuses Scene 01 grid / vehicles / assembly / Program stack.

signal settlement_ready(snapshot: Dictionary)
signal bean_state_changed(state: int)

enum BeanState { READY, RUNNING, PAUSED, COMPLETED }

const TOTAL_INITIAL_GRAMS := 3000
const BEAN_TO_NUMBER := {
	BeanBatch.TYPE_SOYBEAN: 1,
	BeanBatch.TYPE_MUNG_BEAN: 2,
	BeanBatch.TYPE_WHITE_BEAN: 3,
}
const ALL_BEAN_TYPES := [
	BeanBatch.TYPE_SOYBEAN,
	BeanBatch.TYPE_MUNG_BEAN,
	BeanBatch.TYPE_WHITE_BEAN,
]

@onready var bean_object_manager: BeanObjectManager = %Scene01ObjectManager

var _box_numbers: Array[int] = [1, 2, 3, 4, 5]
var _settlement: Dictionary = {}
var _completed := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	_rng.randomize()
	if _has_bean_scene():
		_setup_round()


func _has_bean_scene() -> bool:
	return bean_object_manager != null and bean_object_manager.is_initialized()


func get_bean_state() -> int:
	if _completed:
		return BeanState.COMPLETED
	if is_scene_paused():
		return BeanState.PAUSED
	if is_gameplay_running():
		return BeanState.RUNNING
	return BeanState.READY


func get_bean_object_manager() -> BeanObjectManager:
	return bean_object_manager


func get_batch_limit_grams() -> int:
	return BeanSourceInventory.GRAB_LIMIT_GRAMS


func get_total_initial_grams() -> int:
	return TOTAL_INITIAL_GRAMS


func get_box_number_for_slot(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= _box_numbers.size():
		return 0
	return _box_numbers[slot_index]


func get_required_number_for_bean(bean_type: StringName) -> int:
	return int(BEAN_TO_NUMBER.get(bean_type, 0))


func get_settlement() -> Dictionary:
	return _settlement.duplicate(true)


func is_settled() -> bool:
	return _completed


func submit_beans() -> bool:
	if _completed or not is_gameplay_running():
		return false
	var runner := get_node_or_null("SceneRoot/Scene01ProgramRunner")
	if runner != null and int(runner.call("get_state")) != 0:
		return false
	_settlement = _build_settlement()
	_completed = true
	settlement_ready.emit(get_settlement())
	bean_state_changed.emit(BeanState.COMPLETED)
	return true


func reroll_round() -> bool:
	if is_gameplay_running() or is_scene_paused():
		return false
	if not reset_scene_state():
		return false
	_setup_round()
	return true


func reset_scene_state() -> bool:
	var restored := super.reset_scene_state()
	if restored:
		_completed = false
		_settlement.clear()
		_apply_box_numbers()
		bean_state_changed.emit(get_bean_state())
	return restored


func _setup_round() -> void:
	var numbers: Array[int] = [1, 2, 3, 4, 5]
	for index in range(numbers.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temp := numbers[index]
		numbers[index] = numbers[swap_index]
		numbers[swap_index] = temp
	_box_numbers = numbers
	_completed = false
	_settlement.clear()
	_apply_box_numbers()
	bean_state_changed.emit(get_bean_state())


func _apply_box_numbers() -> void:
	if not _has_bean_scene():
		return
	var targets := bean_object_manager.get_targets()
	for index in range(targets.size()):
		targets[index].set_box_number(get_box_number_for_slot(index))


func _build_settlement() -> Dictionary:
	var correct_grams := 0
	var placed_grams := 0
	var per_target: Array[Dictionary] = []
	var per_bean_correct := {}
	for bean_type in ALL_BEAN_TYPES:
		per_bean_correct[bean_type] = 0

	var targets := bean_object_manager.get_targets()
	for index in range(targets.size()):
		var target := targets[index]
		var number := get_box_number_for_slot(index)
		var per_type := target.inventory.get_grams_by_type()
		var target_grams := target.inventory.get_total_grams()
		placed_grams += target_grams
		var target_correct := 0
		for bean_type in ALL_BEAN_TYPES:
			var grams := int(per_type.get(bean_type, 0))
			if grams <= 0:
				continue
			if get_required_number_for_bean(bean_type) == number:
				target_correct += grams
				per_bean_correct[bean_type] = int(per_bean_correct.get(bean_type, 0)) + grams
		correct_grams += target_correct
		per_target.append({
			"slot_index": index,
			"box_number": number,
			"total_grams": target_grams,
			"correct_grams": target_correct,
			"per_bean": per_type,
		})

	var source_remaining := 0
	for source in bean_object_manager.get_sources():
		source_remaining += source.inventory.remaining_grams

	var carried_grams := 0
	for vehicle_node in scene_vehicle_manager.get_vehicles():
		var vehicle = vehicle_node
		if vehicle == null or vehicle.runtime_state == null:
			continue
		var carried_item = vehicle.runtime_state.carried_item
		if carried_item is BeanBatch:
			carried_grams += (carried_item as BeanBatch).grams

	var lost := clampi(TOTAL_INITIAL_GRAMS - placed_grams - source_remaining - carried_grams, 0, TOTAL_INITIAL_GRAMS)
	var wrong := maxi(placed_grams - correct_grams, 0)
	return {
		"score": correct_grams,
		"max_score": TOTAL_INITIAL_GRAMS,
		"correct_grams": correct_grams,
		"wrong_box_grams": wrong,
		"lost_or_unsubmitted_grams": lost,
		"placed_grams": placed_grams,
		"source_remaining_grams": source_remaining,
		"carried_grams": carried_grams,
		"total_initial_grams": TOTAL_INITIAL_GRAMS,
		"per_bean_correct": per_bean_correct,
		"per_target": per_target,
		"elapsed_time": timer,
	}
