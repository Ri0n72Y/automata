extends Node

const ScoreTrackerScript := preload("res://scripts/scene_01/scene_01_score_tracker.gd")
var _score_tracker: ScoreTrackerScript
var _score_label: Label

func _ready() -> void:
	_score_tracker = get_node("../../SceneRoot/Scene01ScoreTracker") as ScoreTrackerScript
	_score_label = get_node("../RootControl/CompletionPanel/Margin/VBox/ScorePlaceholder") as Label
	_score_tracker.score_changed.connect(_refresh)
	call_deferred("_refresh")
func _refresh() -> void:
	var component_text := str(_score_tracker.get_component_count()) if _score_tracker.has_component_count() else "—"
	_score_label.text = "时间 %.1fs   组件 %s   自动化率 %.0f%%" % [
		_score_tracker.get_elapsed_time(),
		component_text,
		_score_tracker.get_automation_rate() * 100.0,
	]
