tool
extends Control

const HTerrain = preload("../../hterrain.gd")

signal texture_selected(index)

onready var _textures_list = $TexturesContainer
onready var _edit_dialog = $EditDialog

var _terrain : HTerrain = null

var _load_dialog = null

var _empty_icon = load("res://addons/zylann.hterrain/tools/icons/empty.png")


func _ready():
	_edit_dialog.set_load_texture_dialog(_load_dialog)
	
	# Default amount, will be updated when a terrain is assigned
	_textures_list.clear()
	for i in range(4):
		_textures_list.add_item(str(i), _empty_icon)


func set_terrain(terrain: HTerrain):
	_terrain = terrain
	_textures_list.clear()
	_edit_dialog.set_terrain(terrain)


func _process(delta: float):
	if _terrain != null:
		var slot_count = _terrain.get_cached_ground_texture_slot_count()
		if slot_count != _textures_list.get_item_count():
			_update_texture_list()


func _update_texture_list():
	_textures_list.clear()
	if _terrain != null:
		var slot_count = _terrain.get_cached_ground_texture_slot_count()
		for i in range(slot_count):
			var tex = _terrain.get_ground_texture(i, HTerrain.GROUND_ALBEDO_BUMP)
			var hint = _get_slot_hint_name(i, _terrain.get_shader_type())
			_textures_list.add_item(hint, tex if tex != null else _empty_icon)


static func _get_slot_hint_name(i: int, stype: String):
	if i == 3 and (stype == HTerrain.SHADER_CLASSIC4 or stype == HTerrain.SHADER_CLASSIC4_LITE):
		return "cliff"
	return str("ground", i)


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
		_terrain.set_ground_texture(slot, HTerrain.GROUND_ALBEDO_BUMP, texture)
		_textures_list.set_item_icon(slot, texture)


func _on_ClearButton_pressed():
	if _terrain == null:
		return
	# TODO Make it undoable
	var selected_slots = _textures_list.get_selected_items()
	for slot in selected_slots:
		_terrain.set_ground_texture(slot, HTerrain.GROUND_ALBEDO_BUMP, null)
		_textures_list.set_item_icon(slot, null)


func _on_TexturesContainer_item_selected(index):
	emit_signal("texture_selected", index)


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
