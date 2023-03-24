@tool
extends AcceptDialog


#onready var _label = get_node("VBoxContainer/Label")
@onready var _progress_bar : ProgressBar = $VBoxContainer/ProgressBar


func _init():
	get_ok_button().hide()


func _show_progress(message, progress):
	self.title = message
	_progress_bar.ratio = progress


func handle_progress(info: Dictionary):
	if info.has("finished") and info.finished:
		hide()
	
	else:
		if not visible:
			popup_centered()
		
		var message = ""
		if info.has("message"):
			message = info.message
		
		_show_progress(info.message, info.progress)
		# TODO Have builtin modal progress bar
		# https://github.com/godotengine/godot/issues/17763
