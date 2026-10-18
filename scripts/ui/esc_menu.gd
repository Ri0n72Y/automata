extends CanvasLayer

## In-level Esc menu: continue, open the assembly workshop without leaving the
## level, restart the level, return to the main menu, or quit.

@onready var panel: PanelContainer = %MenuPanel
@onready var continue_button: Button = %ContinueButton
@onready var workshop_button: Button = %WorkshopButton
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel

var _blueprint_ui: Node


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_blueprint_ui = get_parent().get_node_or_null("BlueprintUIRoot")
	continue_button.pressed.connect(_close_menu)
	workshop_button.pressed.connect(_open_workshop)
	restart_button.pressed.connect(_restart_level)
	menu_button.pressed.connect(_return_to_main_menu)
	quit_button.pressed.connect(_quit_game)
	workshop_button.disabled = _blueprint_ui == null
	status_label.text = "ESC 关闭菜单 · 关卡将继续运行"
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _is_text_input_focused():
		return
	if _blueprint_visible():
		return
	if visible:
		_close_menu()
	else:
		_open_menu()
	get_viewport().set_input_as_handled()


func _open_menu() -> void:
	visible = true
	get_tree().paused = true
	continue_button.grab_focus()


func _close_menu() -> void:
	visible = false
	get_tree().paused = false


func _blueprint_visible() -> bool:
	return _blueprint_ui != null and _blueprint_ui.visible


func _open_workshop() -> void:
	if _blueprint_ui == null:
		return
	_close_menu()
	_blueprint_ui.call("_open")


func _restart_level() -> void:
	_close_menu()
	var tree := get_tree()
	tree.reload_current_scene()


func _return_to_main_menu() -> void:
	_close_menu()
	get_tree().change_scene_to_file(GameFlow.MAIN_MENU_PATH)


func _quit_game() -> void:
	get_tree().quit()


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
