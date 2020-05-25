tool
extends HBoxContainer

signal value_changed

# I was unable to properly integrate shared file browsing in this...
# Otherwise I'd have to create as many FileDialogs as there are paths...
signal browse_clicked


onready var _line_edit = $LineEdit
onready var _button = $Button


func set_value(text: String):
	_line_edit.text = text


func get_value() -> String:
	return _line_edit.text


func clear():
	_line_edit.clear()


func _on_LineEdit_text_changed(new_text: String):
	emit_signal("value_changed", new_text)


func _on_Button_pressed():
	emit_signal("browse_clicked")
