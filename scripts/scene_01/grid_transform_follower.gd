extends Node3D
class_name GridTransformFollower

@export var target_path: NodePath = ^"../GridRoot"

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_sync_transform()


func _process(_delta: float) -> void:
	_sync_transform()


func _sync_transform() -> void:
	if _target == null:
		_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		global_transform = _target.global_transform
