class_name Scene01ProgramSourceEditor
extends CodeEdit

signal program_text_changed()

const HEADER := "automata_scene01_program 2"
var _restoring := false


func _ready() -> void:
	text_changed.connect(_on_text_changed)
	caret_changed.connect(_refresh_line_marker)
	_refresh_line_marker()


func set_program_text(source: String) -> void:
	_restoring = true
	text = _normalize_header(source)
	_restoring = false
	var line := maxi(0, get_line_count() - 1)
	set_caret_line(line)
	set_caret_column(get_line(line).length())
	_refresh_line_marker()


func insert_statement_line(statement: String) -> void:
	if statement.strip_edges().is_empty():
		return
	var target_line := maxi(1, get_caret_line())
	if target_line >= get_line_count():
		target_line = maxi(1, get_line_count() - 1)
	var current_line := get_line(target_line)
	var insert_after := get_caret_column() > 0 and not current_line.strip_edges().is_empty()
	if insert_after:
		set_caret_line(target_line)
		set_caret_column(current_line.length())
		var suffix := "\n" if target_line >= get_line_count() - 1 or not get_line(target_line + 1).strip_edges().is_empty() else ""
		insert_text_at_caret("\n" + statement + suffix)
	else:
		set_caret_line(target_line)
		set_caret_column(0)
		insert_text_at_caret(statement + "\n")
	_refresh_line_marker()


func _on_text_changed() -> void:
	if _restoring:
		return
	var normalized := _normalize_header(text)
	if normalized != text:
		_restoring = true
		text = normalized
		_restoring = false
	_refresh_line_marker()
	program_text_changed.emit()


func _normalize_header(source: String) -> String:
	var header_line := HEADER + "\n"
	if source.begins_with(header_line):
		return source
	if source == HEADER:
		return header_line
	var lines := source.split("\n", true)
	if not lines.is_empty() and String(lines[0]).begins_with("automata_scene01_program"):
		lines[0] = HEADER
		return "\n".join(lines)
	return header_line + source


func _refresh_line_marker() -> void:
	clear_executing_lines()
	var line := get_caret_line()
	if line > 0 and line < get_line_count():
		set_line_as_executing(line, true)
