@tool
extends AcceptDialog

const HTerrainTextureSet = preload("../../../hterrain_texture_set.gd")
const HT_Logger = preload("../../../util/logger.gd")
const HT_EditorUtil = preload("../../util/editor_util.gd")
const HT_Errors = preload("../../../util/errors.gd")
const HT_TextureSetEditor = preload("./texture_set_editor.gd")
const HT_Result = preload("../../util/result.gd")
const HT_Util = preload("../../../util/util.gd")
const HT_PackedTextureUtil = preload("../../packed_textures/packed_texture_util.gd")
const ResourceImporterTexture_Unexposed = preload("../../util/resource_importer_texture.gd")
const ResourceImporterTextureLayered_Unexposed = preload(
	"../../util/resource_importer_texture_layered.gd")

const HT_NormalMapPreviewShader = preload("../display_normal.gdshader")

const COMPRESS_RAW = 0
const COMPRESS_LOSSLESS = 1
const COMPRESS_LOSSY = 1
const COMPRESS_VRAM = 2
const COMPRESS_COUNT = 3

const _compress_names = ["Raw", "Lossless", "Lossy", "VRAM"]

# Indexed by HTerrainTextureSet.SRC_TYPE_* constants
const _smart_pick_file_keywords = [
	["albedo", "color", "col", "diffuse"],
	["bump", "height", "depth", "displacement", "disp"],
	["normal", "norm", "nrm"],
	["roughness", "rough", "rgh"]
]

signal import_finished

@onready var _texture_editors = [
	$Import/HS/VB2/HB/Albedo,
	$Import/HS/VB2/HB/Bump,
	$Import/HS/VB2/HB/Normal,
	$Import/HS/VB2/HB/Roughness
]

@onready var _slots_list : ItemList = $Import/HS/VB/SlotsList

# TODO Some shortcuts to import options were disabled in the GUI because of Godot issues.
# If users want to customize that, they need to do it on the files directly.
#
# There is no script API in Godot to choose the import settings of a generated file.
# They always start with the defaults, and the only implemented case is for the import dock.
# It appeared possible to reverse-engineer and write a .import file as done in HTerrainData,
# however when I tried this with custom importers, Godot stopped importing after scan(),
# and the resources could not load. However, selecting them each and clicking "Reimport"
# did import them fine. Unfortunately, this short-circuits the workflow.
# Since I have no idea what's going on with this reverse-engineering, I had to drop those options.
# Godot needs an API to import specific files and choose settings before the first import.
#
# Godot 4: now we'll really need it, let's enable and we'll see if it works
# when we can test the workflow...
const _WRITE_IMPORT_FILES = true

@onready var _import_mode_selector : OptionButton = $Import/GC/ImportModeSelector
@onready var _compression_selector : OptionButton = $Import/GC/CompressionSelector
@onready var _resolution_spinbox : SpinBox = $Import/GC/ResolutionSpinBox
@onready var _mipmaps_checkbox : CheckBox = $Import/GC/MipmapsCheckbox
@onready var _add_slot_button : Button = $Import/HS/VB/HB/AddSlotButton
@onready var _remove_slot_button : Button = $Import/HS/VB/HB/RemoveSlotButton
@onready var _import_directory_line_edit : LineEdit = $Import/HB2/ImportDirectoryLineEdit
@onready var _normalmap_flip_checkbox : CheckBox = $Import/HS/VB2/HB/Normal/NormalMapFlipY

var _texture_set : HTerrainTextureSet
var _undo_redo_manager : EditorUndoRedoManager
var _logger = HT_Logger.get_for(self)

# This is normally an `EditorFileDialog`. I can't type-hint this one properly,
# because when I test this UI in isolation, I can't use `EditorFileDialog`.
var _load_texture_dialog : ConfirmationDialog
var _load_texture_type : int = -1
var _error_popup : AcceptDialog
var _info_popup : AcceptDialog
var _delete_confirmation_popup : ConfirmationDialog
var _open_dir_dialog : ConfirmationDialog
var _editor_file_system : EditorFileSystem
var _normalmap_material : ShaderMaterial

var _import_mode := HTerrainTextureSet.MODE_TEXTURES

class HT_TextureSetImportEditorSlot:
	# Array of strings.
	# Can be either path to images, hexadecimal colors starting with #, or empty string for "null".
	var texture_paths := []
	var flip_normalmap_y := false
	
	func _init():
		for i in HTerrainTextureSet.SRC_TYPE_COUNT:
			texture_paths.append("")

# Array of HT_TextureSetImportEditorSlot
var _slots_data := []

var _import_settings := {
	"mipmaps": true,
	"compression": COMPRESS_VRAM,
	"resolution": 512
}


func _init():
	get_ok_button().hide()
	
	# Default data
	_slots_data.clear()
	for i in 4:
		_slots_data.append(HT_TextureSetImportEditorSlot.new())


func _ready():
	if HT_Util.is_in_edited_scene(self):
		return

	for src_type in len(_texture_editors):
		var ed = _texture_editors[src_type]
		var typename = HTerrainTextureSet.get_source_texture_type_name(src_type)
		ed.set_label(typename.capitalize())
		ed.load_pressed.connect(_on_texture_load_pressed.bind(src_type))
		ed.clear_pressed.connect(_on_texture_clear_pressed.bind(src_type))
	
	for import_mode in HTerrainTextureSet.MODE_COUNT:
		var n = HTerrainTextureSet.get_import_mode_name(import_mode)
		_import_mode_selector.add_item(n, import_mode)

	for compress_mode in COMPRESS_COUNT:
		var n = _compress_names[compress_mode]
		_compression_selector.add_item(n, compress_mode)
	
	_normalmap_material = ShaderMaterial.new()
	_normalmap_material.shader = HT_NormalMapPreviewShader
	_texture_editors[HTerrainTextureSet.SRC_TYPE_NORMAL].set_material(_normalmap_material)


func setup_dialogs(parent: Node):
	var d = HT_EditorUtil.create_open_image_dialog()
	d.file_selected.connect(_on_LoadTextureDialog_file_selected)
	_load_texture_dialog = d
	add_child(d)
	
	d = AcceptDialog.new()
	d.title = "Import error"
	_error_popup = d
	add_child(_error_popup)

	d = AcceptDialog.new()
	d.title = "Info"
	_info_popup = d
	add_child(_info_popup)
	
	d = ConfirmationDialog.new()
	d.confirmed.connect(_on_delete_confirmation_popup_confirmed)
	_delete_confirmation_popup = d
	add_child(_delete_confirmation_popup)
	
	d = HT_EditorUtil.create_open_dir_dialog()
	d.title = "Choose import directory"
	d.dir_selected.connect(_on_OpenDirDialog_dir_selected)
	_open_dir_dialog = d
	add_child(_open_dir_dialog)
	
	_update_ui_from_data()


func _notification(what: int):
	if what == NOTIFICATION_EXIT_TREE:
		# Have to check for null in all of them,
		# because otherwise it breaks in the scene editor...
		if _load_texture_dialog != null:
			_load_texture_dialog.queue_free()
		if _error_popup != null:
			_error_popup.queue_free()
		if _delete_confirmation_popup != null:
			_delete_confirmation_popup.queue_free()
		if _open_dir_dialog != null:
			_open_dir_dialog.queue_free()
		if _info_popup != null:
			_info_popup.queue_free()


# TODO Is it still necessary for an import tab?
func set_undo_redo(ur: EditorUndoRedoManager):
	_undo_redo_manager = ur


func set_editor_file_system(efs: EditorFileSystem):
	_editor_file_system = efs


func set_texture_set(texture_set: HTerrainTextureSet):
	if _texture_set == texture_set:
		# TODO What if the set was actually modified since?
		return
	_texture_set = texture_set

	_slots_data.clear()
	
	if _texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES:
		var slots_count = _texture_set.get_slots_count()
		
		for slot_index in slots_count:
			var slot := HT_TextureSetImportEditorSlot.new()
			
			for type in HTerrainTextureSet.TYPE_COUNT:
				var texture = _texture_set.get_texture(slot_index, type)
				
				if texture == null or texture.resource_path == "":
					continue
				
				if not texture.resource_path.ends_with(".packed_tex"):
					continue
				
				var import_data := _parse_json_file(texture.resource_path)
				if import_data.is_empty() or not import_data.has("src"):
					continue
				
				var src_types = HTerrainTextureSet.get_src_types_from_type(type)
				
				var src_data = import_data["src"]
				if src_data.has("rgb"):
					slot.texture_paths[src_types[0]] = src_data["rgb"]
				if src_data.has("a"):
					slot.texture_paths[src_types[1]] = src_data["a"]
			
			_slots_data.append(slot)
	
	else:
		var slots_count := _texture_set.get_slots_count()
		
		for type in HTerrainTextureSet.TYPE_COUNT:
			var texture_array := _texture_set.get_texture_array(type)
			
			if texture_array == null or texture_array.resource_path == "":
				continue
			
			if not texture_array.resource_path.ends_with(".packed_texarr"):
				continue
			
			var import_data := _parse_json_file(texture_array.resource_path)
			if import_data.is_empty() or not import_data.has("layers"):
				continue
			
			var layers_data = import_data["layers"]
			
			for slot_index in len(layers_data):
				var src_data = layers_data[slot_index]
				
				var src_types = HTerrainTextureSet.get_src_types_from_type(type)
				
				while slot_index >= len(_slots_data):
					var slot = HT_TextureSetImportEditorSlot.new()
					_slots_data.append(slot)
				
				var slot : HT_TextureSetImportEditorSlot = _slots_data[slot_index]
				
				if src_data.has("rgb"):
					slot.texture_paths[src_types[0]] = src_data["rgb"]
				if src_data.has("a"):
					slot.texture_paths[src_types[1]] = src_data["a"]

	# TODO If the set doesn't have a file, use terrain path by default?
	if texture_set.resource_path != "":
		var dir = texture_set.resource_path.get_base_dir()
		_import_directory_line_edit.text = dir

	_update_ui_from_data()


func _parse_json_file(fpath: String) -> Dictionary:
	var f := FileAccess.open(fpath, FileAccess.READ)
	if f == null:
		var err := FileAccess.get_open_error()
		_logger.error("Could not load {0}: {1}".format([fpath, HT_Errors.get_message(err)]))
		return {}
	
	var json_text := f.get_as_text()
	var json := JSON.new()
	var json_err := json.parse(json_text)
	if json_err != OK:
		_logger.error("Failed to parse {0}: {1}".format([fpath, json.get_error_message()]))
		return {}
	
	return json.data


func _update_ui_from_data():
	var prev_selected_items := _slots_list.get_selected_items()
	
	_slots_list.clear()
	
	for slot_index in len(_slots_data):
		_slots_list.add_item("Texture {0}".format([slot_index]))
	
	_resolution_spinbox.value = _import_settings.resolution
	_mipmaps_checkbox.button_pressed = _import_settings.mipmaps
	_set_selected_id(_compression_selector, _import_settings.compression)
	_set_selected_id(_import_mode_selector, _import_mode)
	
	var has_slots : bool = _slots_list.get_item_count() > 0
	
	for ed in _texture_editors:
		ed.set_enabled(has_slots)
	_normalmap_flip_checkbox.disabled = not has_slots
	
	if has_slots:
		if len(prev_selected_items) > 0:
			var i : int = prev_selected_items[0]
			if i >= _slots_list.get_item_count():
				i = _slots_list.get_item_count() - 1
			_select_slot(i)
		else:
			_select_slot(0)
	else:
		for type in HTerrainTextureSet.SRC_TYPE_COUNT:
			_set_ui_slot_texture_from_path("", type)
	
	var max_slots := HTerrainTextureSet.get_max_slots_for_mode(_import_mode)
	_add_slot_button.disabled = (len(_slots_data) >= max_slots)
	_remove_slot_button.disabled = (len(_slots_data) == 0)


static func _set_selected_id(ob: OptionButton, id: int):
	for i in ob.get_item_count():
		if ob.get_item_id(i) == id:
			ob.selected = i
			break


func _select_slot(slot_index: int):
	assert(slot_index >= 0)
	assert(slot_index < len(_slots_data))
	var slot = _slots_data[slot_index]
	
	for type in HTerrainTextureSet.SRC_TYPE_COUNT:
		var im_path : String = slot.texture_paths[type]
		_set_ui_slot_texture_from_path(im_path, type)

	_slots_list.select(slot_index)
	
	_normalmap_flip_checkbox.button_pressed = slot.flip_normalmap_y
	_normalmap_material.set_shader_parameter("u_flip_y", slot.flip_normalmap_y)


func _set_ui_slot_texture_from_path(im_path: String, type: int):
	var ed = _texture_editors[type]

	if im_path == "":
		ed.set_texture(null)
		ed.set_texture_tooltip("<empty>")
		return
	
	var im : Image
	
	if im_path.begins_with("#") and im_path.find(".") == -1:
		# The path is actually a preset for a uniform color.
		# This is a feature of packed texture descriptor files.
		# Make a small placeholder image.
		var color := Color(im_path)
		im = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		im.fill(color)
		
	else:
		# Regular path
		im = Image.new()
		var err := im.load(im_path)
		if err != OK:
			_logger.error(str("Unable to load image from ", im_path))
			# TODO Different icon for images that can't load?
			ed.set_texture(null)
			ed.set_texture_tooltip("<empty>")
			return

	var tex := ImageTexture.create_from_image(im)
	ed.set_texture(tex)
	ed.set_texture_tooltip(im_path)


func _set_source_image(fpath: String, type: int):
	_set_ui_slot_texture_from_path(fpath, type)

	var slot_index : int = _slots_list.get_selected_items()[0]
	#var prev_path = _texture_set.get_source_image_path(slot_index, type)
	
	var slot : HT_TextureSetImportEditorSlot = _slots_data[slot_index]
	slot.texture_paths[type] = fpath


func _set_import_property(key: String, value):
	var prev_value = _import_settings[key]
	# This is needed, notably because CheckBox emits a signal too when we set it from code...
	if prev_value == value:
		return
		
	_import_settings[key] = value


func _on_texture_load_pressed(type: int):
	_load_texture_type = type
	_load_texture_dialog.popup_centered_ratio()


func _on_LoadTextureDialog_file_selected(fpath: String):
	_set_source_image(fpath, _load_texture_type)
	
	if _load_texture_type == HTerrainTextureSet.SRC_TYPE_ALBEDO:
		_smart_pick_files(fpath)


# Attempts to load source images of other types by looking at how the albedo file was named
func _smart_pick_files(albedo_fpath: String):
	var albedo_words = _smart_pick_file_keywords[HTerrainTextureSet.SRC_TYPE_ALBEDO]
	
	var albedo_fname := albedo_fpath.get_file()
	var albedo_fname_lower = albedo_fname.to_lower()
	var fname_pattern = ""
	
	for albedo_word in albedo_words:
		var i = albedo_fname_lower.find(albedo_word, 0)
		if i != -1:
			fname_pattern = \
				albedo_fname.substr(0, i) + "{0}" + albedo_fname.substr(i + len(albedo_word))
			break
	
	if fname_pattern == "":
		return
	
	var dirpath := albedo_fpath.get_base_dir()
	var fnames := _get_files_in_directory(dirpath, _logger)
	
	var types := [
		HTerrainTextureSet.SRC_TYPE_BUMP,
		HTerrainTextureSet.SRC_TYPE_NORMAL,
		HTerrainTextureSet.SRC_TYPE_ROUGHNESS
	]
	
	var slot_index : int = _slots_list.get_selected_items()[0]
	
	for type in types:
		var slot = _slots_data[slot_index]
		if slot.texture_paths[type] != "":
			# Already set, don't overwrite unwantedly
			continue
		
		var keywords = _smart_pick_file_keywords[type]
		
		for key in keywords:
			var expected_fname = fname_pattern.format([key])
			
			var found := false
			
			for i in len(fnames):
				var fname : String = fnames[i]
				
				# TODO We should probably ignore extensions?
				if fname.to_lower() == expected_fname.to_lower():
					var fpath = dirpath.path_join(fname)
					_set_source_image(fpath, type)
					found = true
					break
			
			if found:
				break


static func _get_files_in_directory(dirpath: String, logger) -> Array:
	var dir := DirAccess.open(dirpath)
	var err := DirAccess.get_open_error()
	if err != OK:
		logger.error("Could not open directory {0}: {1}" \
			.format([dirpath, HT_Errors.get_message(err)]))
		return []
	
	dir.include_hidden = false
	dir.include_navigational = false

	err = dir.list_dir_begin()
	if err != OK:
		logger.error("Could not probe directory {0}: {1}" \
			.format([dirpath, HT_Errors.get_message(err)]))
		return []
	
	var files := []
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			files.append(fname)
		fname = dir.get_next()
	
	return files


func _on_texture_clear_pressed(type: int):
	_set_source_image("", type)


func _on_SlotsList_item_selected(index: int):
	_select_slot(index)


func _on_ImportModeSelector_item_selected(index: int):
	var mode : int = _import_mode_selector.get_item_id(index)
	if mode != _import_mode:
		#_set_import_property("mode", mode)
		_import_mode = mode
		_update_ui_from_data()


func _on_CompressionSelector_item_selected(index: int):
	var compression : int = _compression_selector.get_item_id(index)
	_set_import_property("compression", compression)


func _on_MipmapsCheckbox_toggled(button_pressed: bool):
	_set_import_property("mipmaps", button_pressed)


func _on_ResolutionSpinBox_value_changed(value):
	_set_import_property("resolution", int(value))


func _on_TextureArrayPrefixLineEdit_text_changed(new_text: String):
	_set_import_property("output_prefix", new_text)


func _on_AddSlotButton_pressed():
	var i := len(_slots_data)
	_slots_data.append(HT_TextureSetImportEditorSlot.new())
	_update_ui_from_data()
	_select_slot(i)


func _on_RemoveSlotButton_pressed():
	if _slots_list.get_item_count() == 0:
		return
	var selected_item = _slots_list.get_selected_items()[0]
	_delete_confirmation_popup.title = "Delete slot {0}".format([selected_item])
	_delete_confirmation_popup.dialog_text = "Delete import slot {0}?".format([selected_item])
	_delete_confirmation_popup.popup_centered()


func _on_delete_confirmation_popup_confirmed():
	var selected_item : int = _slots_list.get_selected_items()[0]
	_slots_data.remove_at(selected_item)
	_update_ui_from_data()


func _on_CancelButton_pressed():
	hide()


func _on_BrowseImportDirectory_pressed():
	_open_dir_dialog.popup_centered_ratio()


func _on_ImportDirectoryLineEdit_text_changed(new_text: String):
	pass


func _on_OpenDirDialog_dir_selected(dir_path: String):
	_import_directory_line_edit.text = dir_path


func _show_error(message: String):
	_error_popup.dialog_text = message
	_error_popup.popup_centered()


func _on_NormalMapFlipY_toggled(button_pressed: bool):
	var slot_index : int = _slots_list.get_selected_items()[0]
	var slot : HT_TextureSetImportEditorSlot = _slots_data[slot_index]
	slot.flip_normalmap_y = button_pressed
	_normalmap_material.set_shader_parameter("u_flip_y", slot.flip_normalmap_y)


# class ButtonDisabler:
# 	var _button : Button

# 	func _init(b: Button):
# 		_button = b
# 		_button.disabled = true

# 	func _notification(what: int):
# 		if what == NOTIFICATION_PREDELETE:
# 			_button.disabled = false


func _get_undo_redo_for_texture_set() -> UndoRedo:
	return _undo_redo_manager.get_history_undo_redo(
		_undo_redo_manager.get_object_history_id(_texture_set))


func _on_ImportButton_pressed():
	if _texture_set == null:
		_show_error("No HTerrainTextureSet selected.")
		return
	
	var import_dir := _import_directory_line_edit.text.strip_edges()

	var prefix := ""
	if _texture_set.resource_path != "":
		prefix = _texture_set.resource_path.get_file().get_basename() + "_"
	
	var files_data_result : HT_Result
	if _import_mode == HTerrainTextureSet.MODE_TEXTURES:
		files_data_result = _generate_packed_images(import_dir, prefix)
	else:
		files_data_result = _generate_packed_texarray_images(import_dir, prefix)

	if not files_data_result.success:
		_show_error(files_data_result.get_message())
		return

	var files_data : Array = files_data_result.value
	
	if len(files_data) == 0:
		_show_error("There are no files to save.\nYou must setup at least one slot of textures.")
		return

	for fd in files_data:
		var dir_path : String = fd.path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			_show_error("The directory {0} could not be found.".format([dir_path]))
			return

	if _WRITE_IMPORT_FILES:
		for fd in files_data:
			var import_fpath = fd.path + ".import"
			if not HT_Util.write_import_file(fd.import_file_data, import_fpath, _logger):
				_show_error("Failed to write file {0}: {1}".format([import_fpath]))
				return

	if _editor_file_system == null:
		_show_error("EditorFileSystem is not setup, can't trigger import system.")
		return

	#                   ______
	#                .-"      "-.
	#               /            \
	#   _          |              |          _
	#  ( \         |,  .-.  .-.  ,|         / )
	#   > "=._     | )(__/  \__)( |     _.=" <
	#  (_/"=._"=._ |/     /\     \| _.="_.="\_)
	#         "=._ (_     ^^     _)"_.="
	#             "=\__|IIIIII|__/="
	#            _.="| \IIIIII/ |"=._
	#  _     _.="_.="\          /"=._"=._     _
	# ( \_.="_.="     `--------`     "=._"=._/ )
	#  > _.="                            "=._ <
	# (_/                                    \_)
	#
	# TODO What I need here is a way to trigger the import of specific files!
	# It exists, but is not exposed, so I have to rely on a VERY fragile and hacky use of scan()...
	# I'm not even sure it works tbh. It's terrible.
	# See https://github.com/godotengine/godot-proposals/issues/1615
	_editor_file_system.scan()
	while _editor_file_system.is_scanning():
		_logger.debug("Waiting for scan to complete...")
		await get_tree().process_frame
		if not is_inside_tree():
			# oops?
			return
	_logger.debug("Scanning complete")
	# Looks like import takes place AFTER scanning, so let's yield some more...
	for fd in len(files_data) * 2:
		_logger.debug("Yielding some more")
		await get_tree().process_frame

	var failed_resource_paths := []

	# Using UndoRedo is mandatory for Godot to consider the resource as modified...
	# ...yet if files get deleted, that won't be undoable anyways, but whatever :shrug:
	var ur := _get_undo_redo_for_texture_set()

	# Check imported textures
	if _import_mode == HTerrainTextureSet.MODE_TEXTURES:
		for fd in files_data:
			var texture : Texture2D = load(fd.path)
			if texture == null:
				failed_resource_paths.append(fd.path)
				continue
			fd.texture = texture

	else:
		for fd in files_data:
			var texture_array : TextureLayered = load(fd.path)
			if texture_array == null:
				failed_resource_paths.append(fd.path)
				continue
			fd.texture_array = texture_array

	if len(failed_resource_paths) > 0:
		var failed_list := "\n".join(PackedStringArray(failed_resource_paths))
		_show_error("Some resources failed to load:\n" + failed_list)
		return

	# All is OK, commit action to modify the texture set with imported textures

	if _import_mode == HTerrainTextureSet.MODE_TEXTURES:
		ur.create_action("HTerrainTextureSet: import textures")

		HT_TextureSetEditor.backup_for_undo(_texture_set, ur)

		ur.add_do_method(_texture_set.clear)
		ur.add_do_method(_texture_set.set_mode.bind(_import_mode))

		for i in len(_slots_data):
			ur.add_do_method(_texture_set.insert_slot.bind(-1))
		for fd in files_data:
			ur.add_do_method(_texture_set.set_texture.bind(fd.slot_index, fd.type, fd.texture))

	else:
		ur.create_action("HTerrainTextureSet: import texture arrays")

		HT_TextureSetEditor.backup_for_undo(_texture_set, ur)

		ur.add_do_method(_texture_set.clear)
		ur.add_do_method(_texture_set.set_mode.bind(_import_mode))

		for fd in files_data:
			ur.add_do_method(_texture_set.set_texture_array.bind(fd.type, fd.texture_array))

	ur.commit_action()
	
	_logger.debug("Done importing")

	_info_popup.dialog_text = "Importing complete!"
	_info_popup.popup_centered()

	import_finished.emit()


class HT_PackedImageInfo:
	var path := "" # Where the packed image is saved
	var slot_index : int # Slot in texture set, when using individual textures
	var type : int # 0:Albedo+Bump, 1:Normal+Roughness
	var import_file_data := {} # Data to write into the .import file (when enabled...)
	var image : Image
	var is_default := false
	var texture : Texture2D
	var texture_array : TextureLayered


# Shared code between the two import modes
func _generate_packed_images2() -> HT_Result:
	var resolution : int = _import_settings.resolution
	var images_infos := []
	
	for type in HTerrainTextureSet.TYPE_COUNT:
		var src_types := HTerrainTextureSet.get_src_types_from_type(type)
		
		for slot_index in len(_slots_data):
			var slot : HT_TextureSetImportEditorSlot = _slots_data[slot_index]
			
			# Albedo or Normal
			var src0 : String = slot.texture_paths[src_types[0]]
			# Bump or Roughness
			var src1 : String = slot.texture_paths[src_types[1]]
			
			if src0 == "":
				if src_types[0] == HTerrainTextureSet.SRC_TYPE_ALBEDO:
					return HT_Result.new(false, 
						"Albedo texture is missing in slot {0}".format([slot_index]))
			
			var is_default := (src0 == "" and src1 == "")
			
			if src0 == "":
				src0 = HTerrainTextureSet.get_source_texture_default_color_code(src_types[0])
			if src1 == "":
				src1 = HTerrainTextureSet.get_source_texture_default_color_code(src_types[1])
				
			var pack_sources := {
				"rgb": src0,
				"a": src1
			}

			if HTerrainTextureSet.SRC_TYPE_NORMAL in src_types and slot.flip_normalmap_y:
				pack_sources["normalmap_flip_y"] = true
			
			var packed_image_result := HT_PackedTextureUtil.generate_image(
				pack_sources, resolution, _logger)
			if not packed_image_result.success:
				return packed_image_result
			var packed_image : Image = packed_image_result.value
			
			var fd := HT_PackedImageInfo.new()
			fd.slot_index = slot_index
			fd.type = type
			fd.image = packed_image
			fd.is_default = is_default
			
			images_infos.append(fd)
	
	return HT_Result.new(true).with_value(images_infos)


func _generate_packed_images(import_dir: String, prefix: String) -> HT_Result:
	var images_infos_result := _generate_packed_images2()
	if not images_infos_result.success:
		return images_infos_result
	var images_infos : Array = images_infos_result.value
	
	for info_index in len(images_infos):
		var info : HT_PackedImageInfo = images_infos[info_index]
		
		var type_name := HTerrainTextureSet.get_texture_type_name(info.type)
		var fpath := import_dir.path_join(
			str(prefix, "slot", info.slot_index, "_", type_name, ".png"))
		
		var err := info.image.save_png(fpath)
		if err != OK:
			return HT_Result.new(false, 
				"Could not save image {0}, {1}".format([fpath, HT_Errors.get_message(err)]))
		
		info.path = fpath
		info.import_file_data = {
			"remap": {
				"importer": "texture",
				"type": "CompressedTexture2D"
			},
			"deps": {
				"source_file": fpath
			},
			"params": {
				"compress/mode": ResourceImporterTexture_Unexposed.COMPRESS_VRAM_COMPRESSED,
				"compress/high_quality": false,
				"compress/lossy_quality": 0.7,
				"mipmaps/generate": true,
				"mipmaps/limit": -1,
				"roughness/mode": ResourceImporterTexture_Unexposed.ROUGHNESS_DISABLED,
				"process/fix_alpha_border": false
			}
		}
	
	return HT_Result.new(true).with_value(images_infos)


static func _assemble_texarray_images(images: Array[Image], resolution: Vector2i) -> Image:
	# Godot expects some kind of grid. Let's be lazy and do a grid with only one row.
	var atlas := Image.create(resolution.x * len(images), resolution.y, false, Image.FORMAT_RGBA8)
	for index in len(images):
		var image : Image = images[index]
		if image.get_size() != resolution:
			image.resize(resolution.x, resolution.y, Image.INTERPOLATE_BILINEAR)
		atlas.blit_rect(image, 
			Rect2i(0, 0, image.get_width(), image.get_height()),
			Vector2i(index * resolution.x, 0))
	return atlas
	

func _generate_packed_texarray_images(import_dir: String, prefix: String) -> HT_Result:
	var images_infos_result := _generate_packed_images2()
	if not images_infos_result.success:
		return images_infos_result
	var individual_images_infos : Array = images_infos_result.value

	var resolution : int = _import_settings.resolution
	
	var texarray_images_infos := []
	var slot_count := len(_slots_data)
	
	for type in HTerrainTextureSet.TYPE_COUNT:
		var texarray_images : Array[Image] = []
		texarray_images.resize(slot_count)
		
		var fully_defaulted_slots := 0
		
		for i in slot_count:
			var info : HT_PackedImageInfo = individual_images_infos[type * slot_count + i]
			if info.type == type:
				texarray_images[i] = info.image
			if info.is_default:
				fully_defaulted_slots += 1
		
		if fully_defaulted_slots == len(texarray_images):
			# No need to generate this file at all
			continue
			
		var texarray_image := _assemble_texarray_images(texarray_images, 
			Vector2i(resolution, resolution))
		
		var type_name := HTerrainTextureSet.get_texture_type_name(type)
		var fpath := import_dir.path_join(str(prefix, type_name, "_array.png"))
		
		var err := texarray_image.save_png(fpath)
		if err != OK:
			return HT_Result.new(false, 
				"Could not save image {0}, {1}".format([fpath, HT_Errors.get_message(err)]))
		
		var texarray_image_info := HT_PackedImageInfo.new()
		texarray_image_info.type = type
		texarray_image_info.path = fpath
		texarray_image_info.import_file_data = {
			"remap": {
				"importer": "2d_array_texture",
				"type": "CompressedTexture2DArray"
			},
			"deps": {
				"source_file": fpath
			},
			"params": {
				"compress/mode": ResourceImporterTextureLayered_Unexposed.COMPRESS_VRAM_COMPRESSED,
				"compress/high_quality": false,
				"compress/lossy_quality": 0.7,
				"mipmaps/generate": true,
				"mipmaps/limit": -1,
				"process/fix_alpha_border": false,
				"slices/horizontal": len(texarray_images),
				"slices/vertical": 1
			}
		}
		
		texarray_images_infos.append(texarray_image_info)

	return HT_Result.new(true).with_value(texarray_images_infos)

