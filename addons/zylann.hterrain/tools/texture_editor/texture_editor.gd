tool
extends Control

const HTerrain = preload("../../hterrain.gd")
const HTerrainTextureSet = preload("../../hterrain_texture_set.gd")
const HT_TextureList = preload("./texture_list.gd")
const HT_Logger = preload("../../util/logger.gd")
# TODO Can't preload because it causes the plugin to fail loading if assets aren't imported
const EMPTY_ICON_TEXTURE_PATH = "res://addons/zylann.hterrain/tools/icons/empty.png"

signal texture_selected(index)
signal edit_pressed(index)
signal import_pressed

onready var _textures_list: HT_TextureList = $TextureList
onready var _buttons_container = $HBoxContainer

var _terrain : HTerrain = null
var _texture_set : HTerrainTextureSet = null

var _texture_list_need_update := false
var _empty_icon : Texture

var _logger = HT_Logger.get_for(self)


func _ready():
	_empty_icon = load(EMPTY_ICON_TEXTURE_PATH)
	if _empty_icon == null:
		_logger.error(str("Failed to load empty icon ", EMPTY_ICON_TEXTURE_PATH))
	
	# Default amount, will be updated when a terrain is assigned
	_textures_list.clear()
	for i in range(4):
		_textures_list.add_item(str(i), _empty_icon)


func set_terrain(terrain: HTerrain):
	_terrain = terrain
	_textures_list.clear()


static func _get_slot_count(terrain: HTerrain) -> int:
	var texture_set = terrain.get_texture_set()
	if texture_set == null:
		return 0
	return texture_set.get_slots_count()


func _process(delta: float):
	var texture_set = null
	if _terrain != null:
		texture_set = _terrain.get_texture_set()

	if _texture_set != texture_set:
		if _texture_set != null:
			_texture_set.disconnect("changed", self, "_on_texture_set_changed")

		_texture_set = texture_set

		if _texture_set != null:
			_texture_set.connect("changed", self, "_on_texture_set_changed")

		_update_texture_list()

	if _texture_list_need_update:
		_update_texture_list()
		_texture_list_need_update = false


func _on_texture_set_changed():
	_texture_list_need_update = true


func _update_texture_list():
	_textures_list.clear()

	if _terrain == null:
		_set_buttons_active(false)
		return
	var texture_set := _terrain.get_texture_set()
	if texture_set == null:
		_set_buttons_active(false)
		return
	_set_buttons_active(true)

	var slots_count := texture_set.get_slots_count()

	match texture_set.get_mode():
		HTerrainTextureSet.MODE_TEXTURES:
			for slot_index in slots_count:
				var texture := texture_set.get_texture(
					slot_index, HTerrainTextureSet.TYPE_ALBEDO_BUMP)
				var hint = _get_slot_hint_name(slot_index, _terrain.get_shader_type())
				if texture == null:
					texture = _empty_icon
				_textures_list.add_item(hint, texture)

		HTerrainTextureSet.MODE_TEXTURE_ARRAYS:
			var texture_array = texture_set.get_texture_array(HTerrainTextureSet.TYPE_ALBEDO_BUMP)
			for slot_index in slots_count:
				var hint = _get_slot_hint_name(slot_index, _terrain.get_shader_type())
				_textures_list.add_item(hint, texture_array, slot_index)


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
