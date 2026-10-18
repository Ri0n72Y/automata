extends Node

## Level entry helper: consumes GameFlow.start_in_workshop and opens the
## in-level blueprint workbench shortly after the scene is initialized.

func _ready() -> void:
	if GameFlow.start_in_workshop:
		call_deferred("_open_workshop")


func _open_workshop() -> void:
	GameFlow.start_in_workshop = false
	await get_tree().process_frame
	await get_tree().process_frame
	var blueprint_ui := get_parent().get_node_or_null("BlueprintUIRoot")
	if blueprint_ui != null and blueprint_ui.has_method("_open"):
		blueprint_ui.call("_open")
