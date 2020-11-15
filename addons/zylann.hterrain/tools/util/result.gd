# Data structure to hold the result of a function that can be expected to fail.
# The use case is to report errors back to the GUI and act accordingly,
# instead of forgetting them to the console or having the script break on an assertion.
# This is a C-like way of things, where the result can bubble, and does not require globals.

tool

# Replace `success` with `error : int`?
var success := false
var value = null
var message := ""
var inner_result = null


func _init(p_success: bool, p_message := "", p_inner = null):
	success = p_success
	message = p_message
	inner_result = p_inner


# TODO Can't type-hint self return
func with_value(v):
	value = v
	return self


func get_message() -> String:
	var msg := message
	if inner_result != null:
		msg += "\n"
		msg += inner_result.get_message()
	return msg


func is_ok() -> bool:
	return success
