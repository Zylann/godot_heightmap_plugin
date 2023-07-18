@tool
extends EditorFileDialog


func _init():
	#access = EditorFileDialog.ACCESS_RESOURCES
	file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	# TODO I actually want a dialog to load a texture, not specifically a PNG...
	add_filter("*.png ; PNG files")
	add_filter("*.jpg ; JPG files")
	unresizable = false
	access = EditorFileDialog.ACCESS_RESOURCES
	close_requested.connect(call_deferred.bind("_on_close"))


func _on_close():
	# Disconnect listeners automatically,
	# so we can re-use the same dialog with different listeners
	var cons = get_signal_connection_list("file_selected")
	for con in cons:
		file_selected.disconnect(con.callable)

