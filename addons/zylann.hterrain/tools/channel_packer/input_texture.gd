tool
extends Control


const _index_to_channel = ["r", "g", "b", "a"]

signal texture_path_changed(file_path)

onready var _texture_preview = get_node("TextureRect")
onready var _load_button = get_node("TextureRect/LoadButton")
onready var _clear_button = get_node("TextureRect/ClearButton")

var _load_texture_dialog = null
var _empty_texture = preload("../icons/empty.png")


func set_load_texture_dialog(dialog):
	_load_texture_dialog = dialog


func get_slot(channel_index):
	var c = _index_to_channel[channel_index]
	return get_node("Channels/" + c.capitalize())


func reset():
	_set_texture(null, null, false)


func _on_LoadButton_pressed():
	_load_texture_dialog.connect("file_selected", self, "_on_LoadTextureDialog_file_selected")
	_load_texture_dialog.popup_centered_ratio()


func _on_ClearButton_pressed():
	_set_texture(null, null)


func _on_LoadTextureDialog_file_selected(fpath):
	# Using raw image loading so we can load images from outside the project
	var im = Image.new()
	var err = im.load(fpath)
	if err != OK:
		print("ERROR: couldn't load image '", fpath, "', error ", err)
		return
	var tex = ImageTexture.new()
	tex.create_from_image(im, 0)
	_set_texture(tex, fpath)


func _set_texture(tex, fpath, emit=true):
	if tex == null:
		_texture_preview.texture = _empty_texture
		_load_button.show()
		_clear_button.hide()
	else:
		_texture_preview.texture = tex
		_load_button.hide()
		_clear_button.show()
	if emit:
		emit_signal("texture_path_changed", fpath)
