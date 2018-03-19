tool
extends Control

const HTerrain = preload("../hterrain.gd")

onready var _textures_list = get_node("TexturesContainer")
onready var _edit_dialog = get_node("EditDialog")

var _terrain = null
var _brush = null

var _load_dialog = null

var _empty_icon = preload("icons/empty.png")


func _ready():
	_edit_dialog.set_load_texture_dialog(_load_dialog)
	
	_textures_list.clear()
	for i in range(4):
		_textures_list.add_item(str(i), _empty_icon)


func set_terrain(terrain):
	_terrain = terrain
	
	_edit_dialog.set_terrain(terrain)
	
	_textures_list.clear()
	if _terrain != null:
		for i in range(_terrain.get_detail_texture_slot_count()):
			var tex = _terrain.get_detail_texture(i, HTerrain.DETAIL_ALBEDO)
			_textures_list.add_item(str(i), tex if tex != null else _empty_icon)


func set_brush(brush):
	_brush = brush


func set_load_texture_dialog(dialog):
	_load_dialog = dialog
	_edit_dialog.set_load_texture_dialog(_load_dialog)


func _on_LoadButton_pressed():
	if _terrain == null:
		return
	_load_dialog.connect("file_selected", self, "_load_texture_selected")
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


func _on_EditButton_pressed():
	var selected_slots = _textures_list.get_selected_items()
	if selected_slots.size() != 0:
		_edit_dialog.set_slot(selected_slots[0])
		_edit_dialog.popup_centered()


func _on_EditDialog_albedo_changed(slot, texture):
	_textures_list.set_item_icon(slot, texture)


func _on_TexturesContainer_item_activated(index):
	_edit_dialog.set_slot(index)
	_edit_dialog.popup_centered()
