tool
extends EditorFileDialog


func _init():
	#access = EditorFileDialog.ACCESS_RESOURCES
	mode = EditorFileDialog.MODE_OPEN_FILE
	# TODO I actually want a dialog to load a texture, not specifically a PNG...
	add_filter("*.png ; PNG files")
	add_filter("*.jpg ; JPG files")
	resizable = true
	access = EditorFileDialog.ACCESS_RESOURCES
	connect("popup_hide", self, "call_deferred", ["_on_close"])


func _on_close():
	# Disconnect listeners automatically,
	# so we can re-use the same dialog with different listeners
	var cons = get_signal_connection_list("file_selected")
	for con in cons:
		disconnect("file_selected", con.target, con.method)

