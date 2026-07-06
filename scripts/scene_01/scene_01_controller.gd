extends Node3D

@onready var scene_root: Node3D = %SceneRoot
@onready var grid_root: Node3D = %GridRoot
@onready var robot_root: Node3D = %RobotRoot
@onready var object_root: Node3D = %ObjectRoot
@onready var camera_root: Node3D = %CameraRoot
@onready var ui_root: CanvasLayer = %UIRoot

var box_count: int = 3
var target_box_count: int = 8
var timer: float = 0.0
var automation_rate: float = 0.0
var is_running: bool = false

func _ready() -> void:
	reset_scene_state()

func _process(delta: float) -> void:
	if is_running:
		timer += delta

func run_scene() -> void:
	is_running = true

func pause_scene() -> void:
	is_running = false

func reset_scene() -> void:
	reset_scene_state()

func reset_scene_state() -> void:
	is_running = false
	timer = 0.0
	box_count = 3
	target_box_count = 8
	automation_rate = 0.0
