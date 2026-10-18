class_name GameFlow
extends RefCounted

## Cross-scene entry intent (no autoload): static flags survive scene changes
## for the duration of the process and are consumed by the destination scene.

const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
const LEVEL_SCENE_01 := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LEVEL_SCENE_02 := "res://scenes/scene_02/scene_02_bean_sorting.tscn"

static var start_in_workshop := false
