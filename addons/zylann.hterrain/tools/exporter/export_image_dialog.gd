@tool
extends AcceptDialog

const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Util = preload("../../util/util.gd")
const HT_Logger = preload("../../util/logger.gd")

const FORMAT_RH = 0
const FORMAT_RF = 1
const FORMAT_R16 = 2
const FORMAT_PNG8 = 3
const FORMAT_EXRH = 4
const FORMAT_EXRF = 5
const FORMAT_COUNT = 6

@onready var _output_path_line_edit := $VB/Grid/OutputPath/HeightmapPathLineEdit as LineEdit
@onready var _format_selector := $VB/Grid/FormatSelector as OptionButton
@onready var _height_range_min_spinbox := $VB/Grid/HeightRange/HeightRangeMin as SpinBox
@onready var _height_range_max_spinbox := $VB/Grid/HeightRange/HeightRangeMax as SpinBox
@onready var _export_button := $VB/Buttons/ExportButton as Button
@onready var _show_in_explorer_checkbox := $VB/ShowInExplorerCheckbox as CheckBox

var _terrain : HTerrain = null
var _file_dialog : EditorFileDialog = null
var _format_names := []
var _format_extensions := []
var _logger = HT_Logger.get_for(self)


func _init():
	# Godot 4 decided to not have a plain WindowDialog class...
	# there is Window but it's way too unfriendly...
	get_ok_button().hide()


func _ready():
	_format_names.resize(FORMAT_COUNT)
	_format_extensions.resize(FORMAT_COUNT)
	
	_format_names[FORMAT_RH] = "16-bit RAW float"
	_format_names[FORMAT_RF] = "32-bit RAW float"
	_format_names[FORMAT_R16] = "16-bit RAW unsigned"
	_format_names[FORMAT_PNG8] = "8-bit PNG greyscale"
	_format_names[FORMAT_EXRH] = "16-bit float greyscale EXR"
	_format_names[FORMAT_EXRF] = "32-bit float greyscale EXR"
	
	_format_extensions[FORMAT_RH] = "raw"
	_format_extensions[FORMAT_RF] = "raw"
	_format_extensions[FORMAT_R16] = "raw"
	_format_extensions[FORMAT_PNG8] = "png"
	_format_extensions[FORMAT_EXRH] = "exr"
	_format_extensions[FORMAT_EXRF] = "exr"
	
	if not HT_Util.is_in_edited_scene(self):
		for i in len(_format_names):
			_format_selector.get_popup().add_item(_format_names[i], i)


func setup_dialogs(base_control: Control):
	assert(_file_dialog == null)
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	fd.unresizable = false
	fd.access = EditorFileDialog.ACCESS_FILESYSTEM
	fd.file_selected.connect(_on_FileDialog_file_selected)
	add_child(fd)
	_file_dialog = fd
	
	_update_file_extension()


func set_terrain(terrain: HTerrain):
	_terrain = terrain


func _exit_tree():
	if _file_dialog != null:
		_file_dialog.queue_free()
		_file_dialog = null


func _on_FileDialog_file_selected(fpath: String):
	_output_path_line_edit.text = fpath


func _auto_adjust_height_range():
	assert(_terrain != null)
	assert(_terrain.get_data() != null)
	var aabb := _terrain.get_data().get_aabb()
	_height_range_min_spinbox.value = aabb.position.y
	_height_range_max_spinbox.value = aabb.position.y + aabb.size.y


func _export() -> bool:
	assert(_terrain != null)
	assert(_terrain.get_data() != null)
	var src_heightmap: Image = _terrain.get_data().get_image(HTerrainData.CHANNEL_HEIGHT)
	var fpath := _output_path_line_edit.text.strip_edges()
	
	# TODO Is `selected` an ID or an index? I need an ID, it works by chance for now.
	var format := _format_selector.selected
	
	var height_min := _height_range_min_spinbox.value
	var height_max := _height_range_max_spinbox.value
	
	if height_min == height_max:
		_logger.error("Cannot export, height range is zero")
		return false
	
	if height_min > height_max:
		_logger.error("Cannot export, height min is greater than max")
		return false
	
	var save_error := OK
	
	var float_heightmap := HTerrainData.convert_heightmap_to_float(src_heightmap, _logger)
	
	if format == FORMAT_PNG8:
		var hscale := 1.0 / (height_max - height_min)
		var im := Image.create(
			src_heightmap.get_width(), src_heightmap.get_height(), false, Image.FORMAT_R8)
		
		for y in src_heightmap.get_height():
			for x in src_heightmap.get_width():
				var h := clampf((float_heightmap.get_pixel(x, y).r - height_min) * hscale, 0.0, 1.0)
				im.set_pixel(x, y, Color(h, h, h))
		
		save_error = im.save_png(fpath)
	
	elif format == FORMAT_EXRH:
		float_heightmap.convert(Image.FORMAT_RH)
		save_error = float_heightmap.save_exr(fpath, true)

	elif format == FORMAT_EXRF:
		save_error = float_heightmap.save_exr(fpath, true)
	
	else: # RAW
		var f := FileAccess.open(fpath, FileAccess.WRITE)
		if f == null:
			var err := FileAccess.get_open_error()
			_print_file_error(fpath, err)
			return false
		
		if format == FORMAT_RH:
			float_heightmap.convert(Image.FORMAT_RH)
			f.store_buffer(float_heightmap.get_data())
		
		elif format == FORMAT_RF:
			f.store_buffer(float_heightmap.get_data())
		
		elif format == FORMAT_R16:
			var hscale := 65535.0 / (height_max - height_min)
			for y in float_heightmap.get_height():
				for x in float_heightmap.get_width():
					var h := int((float_heightmap.get_pixel(x, y).r - height_min) * hscale)
					if h < 0:
						h = 0
					elif h > 65535:
						h = 65535
					if x % 50 == 0:
						_logger.debug(str(h))
					f.store_16(h)
	
	if save_error == OK:
		_logger.debug("Exported heightmap as \"{0}\"".format([fpath]))
		return true
	else:
		_print_file_error(fpath, save_error)
		return false


func _update_file_extension():
	if _format_selector.selected == -1:
		_format_selector.selected = 0
		# This recursively calls the current function
		return
	
	# TODO Is `selected` an ID or an index? I need an ID, it works by chance for now.
	var format = _format_selector.selected

	var ext : String = _format_extensions[format]
	_file_dialog.clear_filters()
	_file_dialog.add_filter(str("*.", ext, " ; ", ext.to_upper(), " files"))
	
	var fpath := _output_path_line_edit.text.strip_edges()
	if fpath != "":
		_output_path_line_edit.text = str(fpath.get_basename(), ".", ext)


func _print_file_error(fpath: String, err: int):
	_logger.error("Could not save path {0}, error: {1}" \
		.format([fpath, HT_Errors.get_message(err)]))


func _on_CancelButton_pressed():
	hide()


func _on_ExportButton_pressed():
	if _export():
		hide()
	if _show_in_explorer_checkbox.button_pressed:
		OS.shell_open(_output_path_line_edit.text.strip_edges().get_base_dir())


func _on_HeightmapPathLineEdit_text_changed(new_text: String):
	_export_button.disabled = (new_text.strip_edges() == "")


func _on_HeightmapPathBrowseButton_pressed():
	_file_dialog.popup_centered_ratio()


func _on_FormatSelector_item_selected(id):
	_update_file_extension()


func _on_HeightRangeAutoButton_pressed():
	_auto_adjust_height_range()
