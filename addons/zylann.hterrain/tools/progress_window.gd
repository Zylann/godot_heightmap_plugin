tool
extends Control


#onready var _label = get_node("VBoxContainer/Label")
onready var _progress_bar = $VBoxContainer/ProgressBar


func show_progress(message, progress):
	self.window_title = message
	_progress_bar.ratio = progress

