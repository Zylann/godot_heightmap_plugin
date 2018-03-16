tool
extends Control

const HTerrain = preload("../hterrain.gd")

onready var _textures_list = get_node("TexturesContainer")

var _terrain = null
var _brush = null

var _load_dialog = null
# TODO Proper icon
var _empty_icon = load("res://icon.png")


func _ready():
	_load_dialog = EditorFileDialog.new()
	_load_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_load_dialog.connect("file_selected", self, "_load_texture_selected")
	_load_dialog.mode = EditorFileDialog.MODE_OPEN_FILE
	# TODO I actually want a dialog to load a texture, not specifically a PNG...
	_load_dialog.add_filter("*.png ; PNG files")
	_load_dialog.resizable = true
	_load_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	add_child(_load_dialog)
	
	_textures_list.clear()
	for i in range(4):
		_textures_list.add_item(str(i), _empty_icon)


func set_terrain(terrain):
	_terrain = terrain
	
	_textures_list.clear()
	if _terrain != null:
		for i in range(_terrain.get_detail_texture_slot_count()):
			var tex = _terrain.get_detail_texture(i, HTerrain.DETAIL_ALBEDO)
			_textures_list.add_item(str(i), tex if tex != null else _empty_icon)


func set_brush(brush):
	_brush = brush


func _on_LoadButton_pressed():
	if _terrain == null:
		return
	_load_dialog.popup_centered_ratio()


func _load_texture_selected(path):
	var texture = load(path)
	if texture == null:
		return
	# TODO Make it undoable
	var selected_slots = _textures_list.get_selected_items()
	for slot in selected_slots:
		_terrain.set_detail_texture(slot, HTerrain.DETAIL_ALBEDO, texture)
		_textures_list.set_item_icon(slot, texture)


func _on_ClearButton_pressed():
	if _terrain == null:
		return
	# TODO Make it undoable
	var selected_slots = _textures_list.get_selected_items()
	for slot in selected_slots:
		_terrain.set_detail_texture(slot, HTerrain.DETAIL_ALBEDO, null)
		_textures_list.set_item_icon(slot, null)


func _on_TexturesContainer_item_selected(index):
	if _brush != null:
		_brush.set_texture_index(index)
