class_name WarningInfo
extends Object


var input_path: String
var output_path: String
var line_number: int
var message: String


static func compare(v1: WarningInfo, v2: WarningInfo) -> bool:
	return (
		v1.line_number < v2.line_number or (
			v1.line_number == v2.line_number and (
				v1.message < v2.message
			)
		)
	)


func to_line_string() -> String:
	return "Line %d: %s" % [line_number, message]
