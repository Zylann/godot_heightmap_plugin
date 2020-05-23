tool
extends Control

const HTerrain = preload("../../hterrain.gd")
const TextureList = preload("./texture_list.gd")

signal texture_selected(index)

onready var _textures_list: TextureList = $TextureList
onready var _edit_dialog = $EditDialog
onready var _buttons_container = $HBoxContainer

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


static func _get_slot_count(terrain: HTerrain) -> int:
	if terrain.is_using_texture_array():
		var texture_array = terrain.get_ground_texture_array(HTerrain.GROUND_ALBEDO_BUMP)
		if texture_array == null:
			return 0
		return texture_array.get_depth()
	return terrain.get_cached_ground_texture_slot_count()


func _process(delta: float):
	if _terrain != null:
		var slot_count := _get_slot_count(_terrain)
		if slot_count != _textures_list.get_item_count():
			_update_texture_list()


func _update_texture_list():
	_textures_list.clear()
	if _terrain != null:
		var slot_count = _get_slot_count(_terrain)
		if _terrain.is_using_texture_array():
			# Texture array workflow doesn't support changing layers from here
			_set_buttons_active(false)
			var texture_array = _terrain.get_ground_texture_array(HTerrain.GROUND_ALBEDO_BUMP)
			for i in slot_count:
				var hint = _get_slot_hint_name(i, _terrain.get_shader_type())
				_textures_list.add_item(hint, texture_array, i)
		else:
			_set_buttons_active(true)
			for i in range(slot_count):
				var tex = _terrain.get_ground_texture(i, HTerrain.GROUND_ALBEDO_BUMP)
				var hint = _get_slot_hint_name(i, _terrain.get_shader_type())
				_textures_list.add_item(hint, tex if tex != null else _empty_icon)


func _set_buttons_active(active: bool):
	for i in _buttons_container.get_child_count():
		var child = _buttons_container.get_child(i)
		if child is Button:
			child.disabled = not active


static func _get_slot_hint_name(i: int, stype: String) -> String:
	if i == 3 and (stype == HTerrain.SHADER_CLASSIC4 or stype == HTerrain.SHADER_CLASSIC4_LITE):
		return "cliff"
	return str(i)


func set_load_texture_dialog(dialog):
	_load_dialog = dialog
	_edit_dialog.set_load_texture_dialog(_load_dialog)


func _on_LoadButton_pressed():
	if _terrain == null:
		return
	_load_dialog.connect("file_selected", self, "_load_texture_selected")
	_load_dialog.popup_centered_ratio()


# TODO Get rid of the custom UI to set the textures with CLASSIC4.
# The shader API should be enough to list them, and users could use the inspector.
# The texture array shader is already in that workflow.

func _load_texture_selected(path):
	var texture = load(path)
	if texture == null:
		return
	# TODO Make it undoable
	var selected_slot = _textures_list.get_selected_item()
	_terrain.set_ground_texture(selected_slot, HTerrain.GROUND_ALBEDO_BUMP, texture)
	_textures_list.set_item_texture(selected_slot, texture)


func _on_ClearButton_pressed():
	if _terrain == null:
		return
	# TODO Make it undoable
	var selected_slot = _textures_list.get_selected_item()
	_terrain.set_ground_texture(selected_slot, HTerrain.GROUND_ALBEDO_BUMP, null)
	_textures_list.set_item_texture(selected_slot, _empty_icon)


func _on_TextureList_item_selected(index: int):
	emit_signal("texture_selected", index)


func _on_EditButton_pressed():
	var selected_slots = _textures_list.get_selected_items()
	if selected_slots.size() != 0:
		_edit_dialog.set_slot(selected_slots[0])
		_edit_dialog.popup_centered()


func _on_EditDialog_albedo_changed(slot: int, texture):
	_textures_list.set_item_texture(slot, texture)


func _on_TextureList_item_activated(index):
	if _terrain.is_using_texture_array():
		# Can't really edit those the same way
		return
	_edit_dialog.set_slot(index)
	_edit_dialog.popup_centered()
