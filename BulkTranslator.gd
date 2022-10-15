class_name BulkTranslator
extends Control

##
## This file contains callbacks for the app
## Developed by Johannes Witt and Hugo Locurcio and Rob Ruana
## Placed into the Public Domain
##


const GITHUB_URL = "https://github.com/HaSa1002/codetranslator/"
const VERSION = "0.8-dev (Last Build 2021-02-16 02:13)"

const DEFAULT_DIR = "/Users/ratface/Godot/unspoiled/unspoiled/src"


export var bug_report_popup : NodePath
export var about_popup : NodePath
export var paste_bug : NodePath


onready var overwrite_button: CheckButton = $Editor/Controls/Overwrite
onready var working_dir_label: LineEdit = $Editor/Controls/WorkingDir
onready var source_files: TextEdit = $Editor/HSplitContainer/SourceFiles/SourceFiles
onready var output_files: TextEdit = $Editor/HSplitContainer/HSplitContainer/OutputFiles/OutputFiles
onready var output_code: TextEdit = $Editor/HSplitContainer/HSplitContainer/VSplitContainer/OutputCode/OutputCode
onready var warnings: TextEdit = $Editor/HSplitContainer/HSplitContainer/VSplitContainer/Warnings/Warnings


var output_files_current_line: int = -1 setget set_output_files_current_line
var working_dir: String = "" setget set_working_dir
var generator_warnings: Dictionary = {}


func set_output_files_current_line(value: int):
	if output_files_current_line != value:
		output_files_current_line = value
		if output_files_current_line < 0:
			output_code.text = ""
			warnings.text = ""
		else:
			var output_path: String = output_files.get_line(output_files_current_line).strip_edges()
			if working_dir:
				output_path = working_dir + "/" + output_path

			if output_path in generator_warnings:
				var warning_list: Array = generator_warnings[output_path]
				warning_list.sort_custom(WarningInfo, "compare")
				var warning_messages: PoolStringArray = PoolStringArray()
				warning_messages.resize(warning_list.size())
				var index: int = 0
				for warning_info in warning_list:
					warning_messages[index] = warning_info.to_line_string()
					index += 1
				warnings.text = "\n".join(warning_messages)
			else:
				warnings.text = ""

			if FileSystem.file_exists(output_path):
				output_code.text = FileSystem.load_text(output_path)
			else:
				output_code.text = ""


func set_working_dir(value: String):
	working_dir = value
	if working_dir_label:
		working_dir_label.text = value if value else "[working dir]"


func clear():
	source_files.text = ""
	output_files.text = ""
	output_code.text = ""
	warnings.text = ""


func bulk_translate_files(input_paths: PoolStringArray) -> void:
	var file_dialog: FileDialog = get_node("FileDialog")
	var current_dir: String = file_dialog.current_dir
	var current_dir_trailing_slash: String = current_dir + "/"
	set_working_dir(current_dir)

	for input_path in input_paths:
		var output_path: String = convert_file(input_path)
		var relative_input_path: String = input_path.trim_prefix(current_dir_trailing_slash)
		var relative_output_path: String = output_path.trim_prefix(current_dir_trailing_slash)
		source_files.text += relative_input_path + "\n"
		source_files.scroll_vertical = INF
		output_files.text += relative_output_path + "\n"
		output_files.scroll_vertical = INF
		yield(get_tree(), "idle_frame")


func convert_file(input_path: String) -> String:
	assert(input_path.ends_with(".gd"))
	var output_path: String = input_path.get_basename() + ".cs"
	if not overwrite_button.pressed and FileSystem.file_exists(output_path):
		_on_CsharpGenerator_warning_generated(
			0,
			'SKIPPED because file already exists, check "Overwrite" to force overwriting.',
			input_path,
			output_path
		)
		return output_path

	var input_text: String = FileSystem.load_text(input_path)
	var generator: CsharpGenerator = CsharpGenerator.new();
	var _err: int = generator.connect("warning_generated", self, "_on_CsharpGenerator_warning_generated", [input_path, output_path])
	var external_class_name: String = input_path.get_basename().get_file()
	var output_text: String = generator.generate_csharp(input_text, external_class_name)
	generator.disconnect("warning_generated", self, "_on_CsharpGenerator_warning_generated")
	generator.free()
	warnings.text = output_text
	_err = FileSystem.save_text(output_path, output_text)
	return output_path


### Callbacks ###


func _on_BulkTranslateDir_pressed() -> void:
	var file_dialog: FileDialog = get_node("FileDialog")
	file_dialog.invalidate()
	file_dialog.current_dir = DEFAULT_DIR
	file_dialog.mode = FileDialog.MODE_OPEN_DIR
	file_dialog.popup_centered_ratio()


func _on_BulkTranslateFiles_pressed() -> void:
	var file_dialog: FileDialog = get_node("FileDialog")
	file_dialog.invalidate()
	file_dialog.current_dir = DEFAULT_DIR
	file_dialog.mode = FileDialog.MODE_OPEN_FILES
	file_dialog.filters = ["*.gd"]
	file_dialog.popup_centered_ratio()


func _on_CsharpGenerator_warning_generated(line_number: int, message: String, input_path: String, output_path: String):
	var warning_info: WarningInfo = WarningInfo.new()
	warning_info.line_number = line_number
	warning_info.message = message
	warning_info.input_path = input_path
	warning_info.output_path = output_path
	if not output_path in generator_warnings:
		generator_warnings[output_path] = []
	generator_warnings[output_path].append(warning_info)


func _on_FileDialog_dir_selected(path: String) -> void:
	var paths: PoolStringArray = PoolStringArray();
	var gdscript_paths: Array = FileSystem.find_files_with_pattern(path, ".*\\.gd")
	for gdscript_path in gdscript_paths:
		paths.append(path + "/" + gdscript_path)
	bulk_translate_files(paths)


func _on_FileDialog_files_selected(paths: PoolStringArray) -> void:
	bulk_translate_files(paths)


func _on_FileDialog_file_selected(path: String) -> void:
	bulk_translate_files([path])


func _on_OutputFiles_cursor_changed() -> void:
	set_output_files_current_line(output_files.cursor_get_line())
