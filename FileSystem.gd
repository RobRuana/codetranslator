tool
extends Node


var PACKED_SCENE_EXT: String = "tscn"  # if OS.is_debug_build() else "scn"
var PACKED_SCENE_REGEX: RegEx = RegEx.new()

var RESOURCE_EXT: String = "tres"  # if OS.is_debug_build() else "res"
var RESOURCE_REGEX: RegEx = RegEx.new()


func _init():
	var _err: int
	_err = PACKED_SCENE_REGEX.compile(".+\\.t?scn")
	_err = RESOURCE_REGEX.compile(".+\\.t?res")


func exists(path: String) -> bool:
	var dir: Directory = Directory.new()
	return dir.file_exists(path) or dir.dir_exists(path)


func file_exists(path: String) -> bool:
	var dir: Directory = Directory.new()
	return dir.file_exists(path)


func dir_exists(path: String) -> bool:
	var dir: Directory = Directory.new()
	return dir.dir_exists(path)


func make_dir(path: String) -> int:
	var dir: Directory = Directory.new()
	if not dir.dir_exists(path):
		return dir.make_dir_recursive(path)
	return OK


func find_resources(path: String) -> Array:
	return find_files(path, RESOURCE_REGEX)


func find_packed_scenes(path: String) -> Array:
	return find_files(path, PACKED_SCENE_REGEX)


func find_files_with_pattern(path: String, pattern: String) -> Array:
	var regex: RegEx = RegEx.new()
	var _err: int = regex.compile(pattern)
	return find_files(path, regex)


func find_files(path: String, regex: RegEx) -> Array:
	var dir: Directory = Directory.new()
	if not dir.dir_exists(path):
		return []

	var contents: Array = []
	var err: int = dir.open(path)
	if err == OK:
		err = dir.list_dir_begin(true, true)
		var filename: String = dir.get_next()
		while filename:
			var is_dir: bool = dir.current_is_dir()
			if is_dir:
				for file in find_files("%s/%s" % [path, filename], regex):
					contents.append("%s/%s" % [filename, file])
			elif regex.search(filename):
				contents.append(filename)
			filename = dir.get_next()
	else:
		printerr("Error opening path [%s]: %s" % [err, path])
	return contents


func modified_time(path: String) -> int:
	return File.new().get_modified_time(path)


func list_dir(path: String, include_dirs: bool = true, include_files: bool = true) -> Array:
	var contents: Array = []
	var dir: Directory = Directory.new()
	var err: int = dir.open(path)
	if err == OK:
		err = dir.list_dir_begin(true, true)
		var filename: String = dir.get_next()
		while filename:
			var is_dir: bool = dir.current_is_dir()
			if (is_dir and include_dirs) or (not is_dir and include_files):
				contents.append(filename)
			filename = dir.get_next()
	else:
		printerr("Error opening path [%s]: %s" % [err, path])
	return contents


func load_config(path: String, exit_on_failure: bool = false) -> ConfigFile:
	var config_file: = ConfigFile.new()
	var err: int = config_file.load(path)
	if err != OK:
		push_error("Error loading config file [%s]: %s" % [err, path])
		if exit_on_failure:
			OS.exit_code = err
			get_tree().quit()
	return config_file


func load_dict(path: String, exit_on_failure: bool = false) -> Dictionary:
	var file: File = File.new()
	var err: int = file.open(path, File.READ)
	if err == OK:
		var data: Dictionary = file.get_var()
		file.close()
		return data
	else:
		push_error("Error loading dictionary [%s]: %s" % [err, path])
		if exit_on_failure:
			OS.exit_code = err
			get_tree().quit()
	return {}


func load_text(path: String, exit_on_failure: bool = false) -> String:
	var file: File = File.new()
	var err: int = file.open(path, File.READ)
	if err == OK:
		var text: String = file.get_as_text()
		file.close()
		return text
	else:
		push_error("Error loading text [%s]: %s" % [err, path])
		if exit_on_failure:
			OS.exit_code = err
			get_tree().quit()
	return ""


func load_json(path: String, exit_on_failure: bool = false):
	var result: JSONParseResult = JSON.parse(load_text(path, exit_on_failure))
	if result.error == OK:
		return result.result
	else:
		push_error("Error loading json [%s] %s, Line %s: %s" % [result.error, result.error_string, result.error_line, path])
		if exit_on_failure:
			OS.exit_code = result.error
			get_tree().quit()
	return null


func save_dict(path: String, data: Dictionary, exit_on_failure: bool = false) -> int:
	var err: int = make_dir(path.get_base_dir())
	if err == OK:
		var file: File = File.new()
		err = file.open(path, File.WRITE)
		if err == OK:
			file.store_var(data)
			file.close()
	if  err != OK:
		push_error("Error saving dictionary [%s]: %s" % [err, path])
		if exit_on_failure:
			OS.exit_code = err
			get_tree().quit()
	return err


func save_text(path: String, text: String, exit_on_failure: bool = false) -> int:
	var err: int = make_dir(path.get_base_dir())
	if err == OK:
		var file: File = File.new()
		err = file.open(path, File.WRITE)
		if err == OK:
			file.store_string(text)
			file.close()
	if err != OK:
		push_error("Error saving text [%s]: %s" % [err, path])
		if exit_on_failure:
			OS.exit_code = err
			get_tree().quit()
	return err


func save_json(path: String, data, indent: String = "", sort_keys: bool = false, exit_on_failure: bool = false) -> int:
	return save_text(path, JSON.print(data, indent, sort_keys), exit_on_failure)


func save_packed_scene(path: String, node: Node, save_flags: int = 0, exit_on_failure: bool = false) -> int:
	var packed_scene: PackedScene = PackedScene.new()
	var err: int = packed_scene.pack(node)
	if err == OK:
		return save_resource(path, packed_scene, save_flags, exit_on_failure)
	return err


func save_resource(path: String, data: Resource, save_flags: int = 0, exit_on_failure: bool = false) -> int:
	var err: int = make_dir(path.get_base_dir())
	if err == OK:
		err = ResourceSaver.save(path, data as Resource, save_flags)
		if err != OK:
			push_error("Error saving resource [%s]: %s" % [err, path])
			if exit_on_failure:
				OS.exit_code = err
				get_tree().quit()
	return err


func is_empty_dir(path: String) -> bool:
	var dir = Directory.new()
	if dir.dir_exists(path) and dir.open(path) == OK:
		dir.list_dir_begin(true)
		var filename: String = dir.get_next()
		var is_empty: bool = filename == ""
		dir.list_dir_end()
		return is_empty
	return false


func remove_recursive(path: String, prune_empty: bool = false) -> int:
	var dir = Directory.new()
	var err: int = OK
	if dir.dir_exists(path):
		err = dir.open(path)
		if err == OK:
			# List directory content
			dir.list_dir_begin(true)
			var filename: String = dir.get_next()
			while filename != "":
				if dir.current_is_dir():
					err = remove_recursive("%s/%s" % [path, filename])
				else:
					err = dir.remove(filename)
					if err != OK:
						push_error("Error deleting file [%s]: %s/%s" % [err, path, filename])

				if err != OK:
					break

				filename = dir.get_next()

			dir.list_dir_end()

			if err == OK:
				# Remove current path
				err = dir.remove(path)
				if err != OK:
					push_error("Error deleting dir [%s]: %s" % [err, path])

	elif dir.file_exists(path):
		err = dir.remove(path)
		if err != OK:
			push_error("Error deleting file [%s]: %s" % [err, path])

	if err == OK and prune_empty:
		path = path.get_base_dir()
		while err == OK and path and is_empty_dir(path):
			err = dir.remove(path)
			if err != OK:
				push_error("Error pruning empty dir [%s]: %s" % [err, path])
				break
			path = path.get_base_dir()

	return err
