
# Note: the inspector destroys this node when another object is edited.

tool
extends Control

const Util = preload("../../util/util.gd")
const TextureImportConfig = preload("./texture_import_config.gd")

onready var _texture_list = $VB/SC/TextureList
onready var _config_nodes = {
	"albedo": $VB/SC/SlotConfig/Albedo,
	"bump": $VB/SC/SlotConfig/Bump,
	"normal": $VB/SC/SlotConfig/Normal,
	"roughness": $VB/SC/SlotConfig/Roughness
}

var _config : TextureImportConfig = null
var _file_dialog : EditorFileDialog
var _file_dialog_key : String


func _ready():
	if Util.is_in_edited_scene(self):
		return
	
	_file_dialog = EditorFileDialog.new()
	_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_file_dialog.mode = EditorFileDialog.MODE_OPEN_FILE
	_file_dialog.add_filter("*.png ; PNG files")
	_file_dialog.add_filter("*.jpg ; JPG files")
	_file_dialog.connect("file_selected", self, "_on_file_dialog_file_selected")
	add_child(_file_dialog)

	for k in _config_nodes:
		var n = _config_nodes[k]
		n.connect("browse_clicked", self, "_on_path_editor_browse_clicked", [k])
		n.connect("value_changed", self, "_on_path_changed", [k])


func set_config(config: TextureImportConfig):
	if _config != null:
		_config.disconnect("slot_count_changed", self, "_on_config_slot_count_changed")
	
	_config = config

	if _config != null:
		_config.connect("slot_count_changed", self, "_on_config_slot_count_changed")
	
	_update_list()


func _update_list():
	_texture_list.clear()
	
	_clear_config_nodes()

	if _config == null:
		return

	for i in _config.get_slot_count():
		var tc = _config.get_texture_config(i)
		if tc == null:
			_texture_list.add_item(str("Slot ", i, " (empty)"))
		else:
			_texture_list.add_item(str("Slot ", i))


func _on_path_changed(fpath: String, key: String):
	var i = _get_selected_config_index()
	var tc := _config.get_texture_config(i)
	if tc == null:
		if fpath == "":
			# LineEdit still emits change signals everytime we call `clear()`,
			# so have to ignore that...
			return
		tc = TextureImportConfig.SlotConfig.new()
		_config.set_texture_config(i, tc)
	tc.set(str(key, "_path"), fpath)


func _on_config_slot_count_changed():
	_update_list()


func _on_ReimportButton_pressed():
	_config.generate_textures()


func _on_TextureList_item_selected(index: int):
	_update_config_nodes()


func _get_selected_config_index():
	var selected_indexes = _texture_list.get_selected_items()
	if len(selected_indexes) == 0:
		return -1
	return selected_indexes[0]


func _get_selected_config():
	var selected_indexes = _texture_list.get_selected_items()
	if len(selected_indexes) == 0:
		return null
	var selected_index = selected_indexes[0]
	return _config.get_texture_config(selected_index)


func _update_config_nodes():
	var tc = _get_selected_config()
	if tc == null:
		_clear_config_nodes()
		return
	for k in _config_nodes:
		var n = _config_nodes[k]
		var path = tc.get(str(k, "_path"))
		n.set_value(path)


func _clear_config_nodes():
	for k in _config_nodes:
		var n = _config_nodes[k]
		n.clear()


func _on_EraseButton_pressed():
	var selected_indexes = _texture_list.get_selected_items()
	if len(selected_indexes) == 0:
		return
	var selected_index = selected_indexes[0]
	_config.set_texture_config(selected_index, null)


func _on_path_editor_browse_clicked(key: String):
	var n = _config_nodes[key]
	
	var current_path = n.get_value()
	if current_path != "":
		_file_dialog.current_file = current_path
	
	_file_dialog_key = key
	_file_dialog.popup_centered()


func _on_file_dialog_file_selected(fpath: String):
	var n = _config_nodes[_file_dialog_key]
	n.set_value(fpath)
