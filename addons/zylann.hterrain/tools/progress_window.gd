@tool
extends AcceptDialog


#onready var _label = get_node("VBoxContainer/Label")
@onready var _progress_bar : ProgressBar = $VBoxContainer/ProgressBar


func _init():
	get_ok_button().hide()


func show_progress(message, progress):
	self.title = message
	_progress_bar.ratio = progress

