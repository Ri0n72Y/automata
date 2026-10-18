extends Node

## Minimal level switcher for local playtesting: presses a single digit to
## change scenes. No gameplay ownership; purely a developer/QA convenience.

@export_file("*.tscn") var target_scene: String = ""
@export var keycode: int = KEY_2


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or target_scene.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode:
		get_tree().change_scene_to_file(target_scene)
		get_viewport().set_input_as_handled()
