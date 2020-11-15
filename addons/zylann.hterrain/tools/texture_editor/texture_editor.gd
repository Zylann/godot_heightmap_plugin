tool
extends Control

const HTerrain = preload("../../hterrain.gd")
const TextureList = preload("./texture_list.gd")

signal texture_selected(index)
signal edit_pressed(index)
signal import_pressed

onready var _textures_list: TextureList = $TextureList
onready var _buttons_container = $HBoxContainer

var _terrain : HTerrain = null
var _empty_icon = load("res://addons/zylann.hterrain/tools/icons/empty.png")


func _ready():
	# Default amount, will be updated when a terrain is assigned
	_textures_list.clear()
	for i in range(4):
		_textures_list.add_item(str(i), _empty_icon)


func set_terrain(terrain: HTerrain):
	_terrain = terrain
	_textures_list.clear()


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


func _on_TextureList_item_selected(index: int):
	emit_signal("texture_selected", index)


func _on_TextureList_item_activated(index: int):
	emit_signal("edit_pressed", index)


func _on_EditButton_pressed():
	var selected_slot := _textures_list.get_selected_item()
	if selected_slot == -1:
		selected_slot = 0
	emit_signal("edit_pressed", selected_slot)


func _on_ImportButton_pressed():
	emit_signal("import_pressed")
