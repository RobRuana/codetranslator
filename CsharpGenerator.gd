class_name CsharpGenerator
extends Node

##
## This file contains c# generation functions
## Developed by Johannes Witt and Hugo Locurcio
## Placed into the Public Domain
##

signal warning_generated(line, string)


var parser := Parser.new()


func _ready():
	var err = parser.connect("warning_generated", self, "warn")
	assert(err == OK) # Fix the signal name above


func warn(line: int, string: String) -> void:
	emit_signal("warning_generated", line, string)

### 			Converters 				  ###
# Converters take input and output Strings! #

func convert_while(string: String) -> String:
	var end = string.find(":")
	if end != -1:
		end -= 6
	return string.substr(6, end).strip_edges()


func convert_foreach(string: String) -> String:
	var end = string.find(":")
	if end != -1:
		end -= 4
	return string.substr(4, end).strip_edges()

func convert_for(string: String) -> String:
	var end := string.find(":")
	if end != -1:
		end -= 4
	var details := string.substr(4, end).strip_edges()
	end = details.find(" in ")
	if end == -1:
		return "var %s = 0;;" % details
	var variable = details.substr(0, end)
	end = details.find("(") - details.find(")")
	if end <= 0 || details.find(")") == -1:
		end = -1

	var info := details.substr(details.find("("), end).split(",")
	var start := 0
	var increment := 1
	var comp := 0
	match info.size():
		3:
			start = int(info[0])
			increment = int(info[2])
			comp = int(info[1])
		2:
			start = int(info[0])
			comp = int(info[1])
		1:
			comp = int(info[0])
	if increment == 1:
		return "var %s = %d; %s < %d; %s++" % [variable, start, variable, comp, variable]
	elif increment == -1:
		return "var %s = %d; %s < %d; %s--" % [variable, start, variable, comp, variable]
	return "var %s = %d; %s < %d; %s += %d" % [variable, start, variable, comp, variable, increment]

## Returns C# "if"
func convert_if(string: String) -> String:
	var end = string.find(":")
	if end != -1:
		end -= 3
	return string.substr(3, end).strip_edges()


## Returns C# "else if" from "elif"
func convert_elif(string: String) -> String:
	var end = string.find(":")
	if end != -1:
		end -= 5
	return string.substr(5, end).strip_edges()


## Converts Class.new(...) to new Class(...)
func convert_constructor(string: String) -> String:
	string = string.strip_edges().replace(".new(", "(")
	return "new " + string


## Converts extends and class_name to a proper class header
func convert_file_scope_to_cs(line: int, string: String, external_class_name: String = "") -> String:
	var lines := string.split("\n", false)
	var is_tool := false
	var classname_line := ""
	var extends_line := ""
	for l in lines:
		var st: String = l
		if st.begins_with("tool"):
			is_tool = true
		elif st.begins_with("class_name"):
			classname_line = st
		elif st.begins_with("extends"):
			extends_line = st
		else:
			print("[]",l,"[]")
			assert(false) # Cached garbage. FIX ME
	if extends_line.empty() && classname_line.empty():
		return "" # We don't have a global scope script
	var cname := "?CLASS_NAME?" if external_class_name.empty() else external_class_name
	if classname_line.empty() and external_class_name.empty():
		warn(line, "C# needs a class name.")
	else:
		cname = classname_line.substr(11)
		cname = cname.substr(0, cname.find(",")).strip_edges()
	var extends_class := ""
	if extends_line.empty():
		extends_class = "?BASECLASS?"
		warn(line, "Expected a base class")
	else:
		extends_class = extends_line.substr(8).strip_edges()
	var tool_line = "[Tool]\n" if is_tool else ""
	return tool_line + "public class " + cname + " : " + extends_class + "\n"


## Converts the output of _parse_statement into C# Code
func convert_statement(line: int, statement: Array, gsv, lsv, usings, place_semicolon := true) -> String:
	var place_dot := [
		"var",
		"method",
		"string",
		"get_node",
	]
	var result := ""
	var previous = ""
	var _i := 0
	for s in statement:
		match s[0]:
			"pass":
				place_semicolon = false
				pass
			"var":
				if previous in place_dot:
					result += "."
				if s[1] in gsv:
					result += gsv[s[1]][0]
				elif Detector.var_in_local_vars(s[1], lsv):
					result += Utility.get_var_in_local_vars(s[1], lsv)[0]
				elif s[1] in Utility.REMAP_VARIABLES:
					result += Utility.REMAP_VARIABLES[s[1]]
				else:
					# We have to assume, that the variable is declared in a parent class
					var is_private := Detector.is_private(s[1])
					if is_private:
						warn(line, "Variable %s looks private, but is not declared in this file" % s[1])
					result += Utility.pascal(s[1], is_private)
				previous = "var"
				pass
			"constructor":
				if previous in place_dot:
					result += "."
				result += "new %s(" % s[1]
				var j = 0
				for args in s[2][0][2]:
					j += 1
					result += convert_statement(line, args, gsv, lsv, usings, false)
					if j < s[2][0][2].size():
						result += ", "
				result += ")"
			"method":
				if previous in place_dot:
					result += "."
				var method = ""
				if Utility.is_remapped_method(s[1]):
					method = Utility.get_remapped_method(s[1]) + "(%s)"
				elif Detector.is_builtin(s[1]):
					# We have a constructor
					method = convert_builtin(s[1], !s[2].empty())
				else:
					method = Utility.pascal(s[1], Detector.is_private(s[1])) + "(%s)"
				Parser.parse_using(s[1], usings)
				var is_connect = s[1] == "connect"
				var connect_same_method = false
				var j = 0
				var arg_str = ""
				for args in s[2]:
					j += 1
					var part = convert_statement(line, args, gsv, lsv, usings, false)
					if is_connect:
						if j == 2:
							connect_same_method = part.begins_with("this");
						elif j == 3 && connect_same_method:
							part = "nameof(%s)" % Utility.pascal(part.substr(1, part.length() - 2))
					arg_str += part
					if j < s[2].size():
						arg_str += ", "
				if method.find("%s") == -1:
					result += method
				else:
					result += method % arg_str

				previous = "method"
				pass
			"assignment", "comparison", "math", "bitwise":
				result += convert_statement(line, s[1], gsv, lsv, usings, false) + " %s " % s[2] + \
					convert_statement(line, s[3], gsv, lsv, usings, false)
				previous = "assignment/comparison"
			"get_node":
				result += "GetNode(\"%s\")" % s[1]
				previous = "get_node"
			"string":
				result += s[1]
				previous = "string"
				pass
			"int", "float", "bool":
				result += s[1]
				previous = "int/float/bool"
			"const":
				if previous in place_dot:
					result += "."
				result += s[1]
				warn(line, "If constant is enum refer to documentation for correct syntax.")
				previous = "const"
			"return":
				result += "return " + convert_statement(line, s[1], gsv, lsv, usings, false)
				previous = "return"
			"array":
				var elements := ""
				for e in s[1]:
					elements += convert_statement(line, e, gsv, lsv, usings, false) + ", "
				elements.erase(elements.length() - 2, 2)
				result += Utility.BUILTIN_CLASSES["Array"][1] % elements
			"property":
				result += "[%s]" % s[1]
				previous = "property"
			"subscription":
				var type = s[1][0][0] if !s[1].empty() else ""
				match type:
					"int":
						if int(s[1][0][1]) < 0:
							result += "[%s.Count %s]" % [result, s[1][0][1]]
						else:
							result += "[%s]" % s[1][0][1]
					_:
						result += "[%s]" % convert_statement(line, s[1], gsv, lsv, usings, false)
				previous = "subscription"
			"is":
				result += " is %s" % s[1]
				previous = "is"
			"as":
				result += " as %s" % s[1]
				previous = "as"
			"in":
				result += convert_statement(line, s[1], gsv, lsv, usings, false) + " in " + convert_statement(line, s[2], gsv, lsv, usings, false)
				previous = "in"
			"group":
				result += "(%s)" % convert_statement(line, s[1], gsv, lsv, usings, false)
				previous = "group"
			"nodepath":
				result += "new NodePath(\"%s\")" % s[1]
				previous = "nodepath"
			"negation":
				result += "!"
				previous = "negation"
			"?":
				warn(line, "Expression %s is unrecognized!" % s[1])
				pass
			var other:
				print("type '%s' is unrecognized! Content:" % other, s)
				warn(line, "type '%s' is unrecognized! This is a Bug and should be reported" % other)
		_i += 1
	if place_semicolon:
		result += ";"
	return result



func convert_builtin(type: String, has_args := false, as_type := false) -> String:
	type = type.substr(0, type.find("(")).strip_edges()
	if Utility.BUILTIN_CLASSES[type] == null:
		return type if as_type else "new "+type+"(%s)"
	elif Utility.BUILTIN_CLASSES[type] is Array:
		if as_type:
			return Utility.BUILTIN_CLASSES[type][0]
		elif has_args:
			return "new " + Utility.BUILTIN_CLASSES[type][1]
		else:
			return "new " + Utility.BUILTIN_CLASSES[type][1] % ""
	else:
		if has_args:
			return type if as_type else "new "+type+"(%s)"
		else:
			return Utility.BUILTIN_CLASSES[type]


## Parses a variable declaration and output converted code
func parse_declaration(line: int, global_scope: bool, string: String, gsv, lsvi, lsv, usings) -> String:
	var is_const = Detector.is_const_declaration(string)
	var result := ""
	if global_scope: # Include access modifier in global scope
		result += "private " if Detector.is_private_var(string) else "public "
	var info := Parser.parse_variable_d(string, gsv, lsv, is_const)
	if is_const:
		result += "const "
	if info[1] == null:
		info[1] = "?VAR?"
		warn(line, "Type of declaration is unknown")
	if info[3]:
		if info[3] == 1:
			warn(line, "Type is inferred from a number. This is error-prone. Set the type explicit!")
		elif info[3] == 2:
			warn(line, "Type is dependent on a variable. This is can lead to unexpected changes.")
	if info[0] == null:
		warn(line, "Expected variable name")
		info[0] = "?NAME?"
	else:
		if global_scope:
			var vname = info[0] if is_const else Utility.pascal(info[0], Detector.is_private(info[0]))
			gsv[info[0]] = [vname, info[1]]
			info[0] = vname
		elif info[0] in Utility.REMAP_VARIABLES:
			var vname = Utility.REMAP_VARIABLES[info[0]]
			lsvi[info[0]] = [vname, info[1]]
			info[0] = vname
		else:
			var vname = info[0] if is_const else Utility.camelCase(info[0], false)
			lsvi[info[0]] = [vname, info[1]]
			info[0] = vname
	if Detector.is_builtin(info[1]):
		info[1] = convert_builtin(info[1], false, true)
	result += info[1] + " " + info[0]
	if info[2] != null:
		result += " = "
		if info[2].empty():
			warn(line, "Expected assignment")
			result += "?ASSIGNMENT?"
		else:
			if Detector.is_constructor(info[2]):
				result += convert_constructor(info[2])
			else:
				print(line)
				result += convert_statement(line, parser.parse_statement(line, info[2]), gsv, lsv, usings, false)
	result += ";"
	return result


## Parses the source code and outputs the resulting C# Code
func generate_csharp(source: String, external_class_name: String = "") -> String:
	var output: String = ""
	var line_number: int = 0
	var comment: String = ""

	var is_file_scope: bool = true
	var collected_scope: String = ""
	var is_global_scope: bool = false
	var global_scope_vars := {}
	var local_vars := {0: {}} #contains dict for each indent level, index by indent
	var usings := [
		"Godot",
		"System",
	]
	var is_multiline: bool = false
	var braces: int = 0
	var csharp_indent_current: int = 0
	var csharp_indent_previous: int = 0
	var gdscript_indent_current: int = 0
	var gdscript_indent_previous: int = 0  # warning-ignore: unused_variable
	source = source.replace("    ", "\t")

	for line in source.split("\n"):
		var l: String = line.strip_edges()
		line_number += 1
		var gdscript_indent = line.length() - line.strip_edges(true, false).length()
		var line_is_blank: bool = Detector.is_comment(l) or l.empty()
		if not line_is_blank and not is_multiline:
			gdscript_indent_previous = gdscript_indent_current
			gdscript_indent_current = gdscript_indent

		if is_file_scope:
			if gdscript_indent != 0:
				is_file_scope = false
			else:
				if Detector.is_file_scope(l):
					collected_scope += l + "\n"
					continue
				elif not line_is_blank:
					is_file_scope = false
			if !is_file_scope:
				var file_scope = convert_file_scope_to_cs(line_number, collected_scope, external_class_name)
				is_global_scope = !file_scope.empty()
				output += file_scope

		csharp_indent_previous = csharp_indent_current
		csharp_indent_current = gdscript_indent_current + (1 if is_global_scope else 0)
		if !is_multiline:
			if csharp_indent_current < csharp_indent_previous:
				var dedent: int = csharp_indent_previous - csharp_indent_current
				while dedent > 0:
					var _result: bool = local_vars.erase(braces)
					braces -= 1
					var index: int = output.strip_edges(false, true).length() + 1
					output = output.left(index) + "\t".repeat(braces) + "}\n" + output.right(index)
					dedent -= 1
			elif csharp_indent_current > csharp_indent_previous:
				var indent: int = csharp_indent_current - csharp_indent_previous
				while indent > 0:
					output += "\t".repeat(braces) + "{\n"
					braces += 1
					local_vars[braces] = {}
					indent -= 1
			output += "\t".repeat(braces)

		is_multiline = false
		if l.ends_with(";"):
			l.erase(l.length() - 1, 1)
		if l.empty() || Detector.is_pass(l):
			output += "\n"
			continue
		if Detector.is_comment(l):
			# directly convert line into comment and continue
			output += "//" + l.substr(1)
			l = ""
		if Detector.has_comment(l):
			# split comment out of case conversion
			comment = l.split("#")[1]
			l = l.split("#")[0]
		if Detector.is_declaration(l) || Detector.is_const_declaration(l):
			var is_global_var = braces == 1 && is_global_scope
			output += parse_declaration(
				line_number,
				is_global_var,
				l,
				global_scope_vars,
				local_vars[braces],
				local_vars,
				usings
			)
			l = ""

		if Detector.is_function_declaration(l):
			if Detector.is_overriding_virtual_function(l):
				output += "public override "
			elif Detector.is_private_function(l):
				output += "private "
			else:
				output += "public "
			if Detector.is_static_function(l):
				output += "static "
			var retval := Parser.get_function_retval(l)
			if retval.empty():
				warn(line_number, "No return value provided. Assuming void. Use -> RETVAL to specify")
				retval = "void"
			output += retval + " "
			var func_name := Parser.get_function_name_from_d(l)
			if func_name.empty():
				warn(line_number, "Expected function name")
				output += "?NAME?("
			else:
				output += Utility.pascal(func_name, Detector.is_virtual(func_name)) + "("
			for arg in Parser.get_function_arguments(l):
				if arg[1] == null:
					warn(line_number, "No type provided. Consider type hinting with NAME:TYPE")
					output += "?TYPE? "
				elif arg[1].empty():
					warn(line_number, "Expected type")
					output += "?TYPE? "
				else:
					output += arg[1] + " "

				if arg[0].empty():
					warn(line_number, "Expected argument name")
					output += "?NAME?"
				else:
					if arg[0] in Utility.REMAP_VARIABLES:
						output += Utility.REMAP_VARIABLES[arg[0]]
						local_vars[braces][arg[0]] = [Utility.REMAP_VARIABLES[arg[0]], arg[1]]
					else:
						output += arg[0]
						local_vars[braces][arg[0]] = [arg[0], arg[1]]

				if arg[2] == null:
					pass # We ensure below is a String... Hacky tho
				elif arg[2].empty():
					warn(line_number, "Expected default value")
					output += " ?VALUE?"
				else:
					output += " = " + arg[2]
				output += ", "
			if output.ends_with(", "):
				output = output.left(output.find_last(", "))
			output += ")"
			l = ""
		if Detector.is_while(l):
			output += "while (%s)" % convert_statement(line_number, parser.parse_statement(line_number, convert_while(l)), \
				global_scope_vars, local_vars, usings, false)
			l = ""
		if Detector.is_for(l):
			if Detector.is_foreach(l):
				output += "foreach (var %s)" % convert_statement(line_number, parser.parse_statement(line_number, convert_foreach(l)), \
					global_scope_vars, local_vars, usings, false)
			else:
				output += "for (%s)" % convert_for(l)
			l = ""
		if Detector.is_if(l):
			output += "if (%s)" % convert_statement(line_number, parser.parse_statement(line_number, convert_if(l)), \
				global_scope_vars, local_vars, usings, false)
			l = ""
		if Detector.is_elif(l):
			output += "else if (%s)" % convert_statement(line_number, \
				parser.parse_statement(line_number, convert_elif(l)), \
				global_scope_vars, local_vars, usings, false)
			l = ""
		if Detector.is_else(l):
			output += "else"
			l = ""
		if l.ends_with("\\"):
			is_multiline = true
			l = l.left(l.length() - 2).strip_edges()
		if !l.empty():
			var debug_parse_result = parser.parse_statement(line_number, l)
			print(debug_parse_result)
			output += convert_statement(line_number, parser.parse_statement(line_number, l), \
				global_scope_vars, local_vars, usings, !is_multiline)
		if !comment.empty():
			output += " //" + comment
			comment = ""
		if !is_multiline:
			output += "\n"
		#print("[%d] " % line_number, l)

	while braces > 0:
		braces -= 1
		output += "\t".repeat(braces) + "}\n"

	var usings_str := ""
	if is_global_scope:
		for using in usings:
			usings_str += "using %s;\n" % using
		usings_str += "\n"
	output = usings_str + output.rstrip("\n").replace("\t", "    ")
	#print(output)
	return output
