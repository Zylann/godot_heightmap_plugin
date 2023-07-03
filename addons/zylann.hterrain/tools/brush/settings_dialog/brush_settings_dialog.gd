@tool
extends AcceptDialog

const HT_Util = preload("../../../util/util.gd")
const HT_Brush = preload("../brush.gd")
const HT_Logger = preload("../../../util/logger.gd")
const HT_EditorUtil = preload("../../util/editor_util.gd")
const HT_SpinSlider = preload("../../util/spin_slider.gd")
const HT_Scratchpad = preload("./preview_scratchpad.gd")

@onready var _scratchpad : HT_Scratchpad = $VB/HB/VB3/PreviewScratchpad

@onready var _shape_list : ItemList = $VB/HB/VB/ShapeList
@onready var _remove_shape_button : Button = $VB/HB/VB/HBoxContainer/RemoveShape
@onready var _change_shape_button : Button = $VB/HB/VB/ChangeShape

@onready var _size_slider : HT_SpinSlider = $VB/HB/VB2/Settings/Size
@onready var _opacity_slider : HT_SpinSlider = $VB/HB/VB2/Settings/Opacity
@onready var _pressure_enabled_checkbox : CheckBox = $VB/HB/VB2/Settings/PressureEnabled
@onready var _pressure_over_size_slider : HT_SpinSlider = $VB/HB/VB2/Settings/PressureOverSize
@onready var _pressure_over_opacity_slider : HT_SpinSlider = $VB/HB/VB2/Settings/PressureOverOpacity
@onready var _frequency_distance_slider : HT_SpinSlider = $VB/HB/VB2/Settings/FrequencyDistance
@onready var _frequency_time_slider : HT_SpinSlider = $VB/HB/VB2/Settings/FrequencyTime
@onready var _random_rotation_checkbox : CheckBox = $VB/HB/VB2/Settings/RandomRotation
@onready var _shape_cycling_checkbox : CheckBox = $VB/HB/VB2/Settings/ShapeCycling

var _brush : HT_Brush
# This is a `EditorFileDialog`,
# but cannot type it because I want to be able to test it by running the scene.
# And when I run it, Godot does not allow to use `EditorFileDialog`.
var _load_image_dialog
# -1 means add, otherwise replace
var _load_image_index := -1
var _logger = HT_Logger.get_for(self)


func _ready():
	if HT_Util.is_in_edited_scene(self):
		return
	
	_size_slider.set_max_value(HT_Brush.MAX_SIZE_FOR_SLIDERS)
	_size_slider.set_greater_max_value(HT_Brush.MAX_SIZE)
	
	# TESTING
	if not Engine.is_editor_hint():
		setup_dialogs(self)
		call_deferred("popup")


func set_brush(brush : HT_Brush):
	assert(brush != null)
	_brush = brush
	_update_controls_from_brush()


# `base_control` can no longer be hinted as a `Control` because in Godot 4 it could be a
# window or dialog, which are no longer controls...
func setup_dialogs(base_control: Node):
	assert(_load_image_dialog == null)
	_load_image_dialog = HT_EditorUtil.create_open_file_dialog()
	_load_image_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_load_image_dialog.add_filter("*.exr ; EXR files")
	_load_image_dialog.unresizable = false
	_load_image_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_load_image_dialog.current_dir = HT_Brush.SHAPES_DIR
	_load_image_dialog.file_selected.connect(_on_LoadImageDialog_file_selected)
	_load_image_dialog.files_selected.connect(_on_LoadImageDialog_files_selected)
	#base_control.add_child(_load_image_dialog)
	# When a dialog opens another dialog, we get this error:
	# "Transient parent has another exclusive child."
	# Which is worked around by making the other dialog a child of the first one (I don't know why)
	add_child(_load_image_dialog)


func _exit_tree():
	if _load_image_dialog != null:
		_load_image_dialog.queue_free()
		_load_image_dialog = null


func _get_shapes_from_gui() -> Array[Texture2D]:
	var shapes : Array[Texture2D] = []
	for i in _shape_list.get_item_count():
		var icon : Texture2D = _shape_list.get_item_icon(i)
		assert(icon != null)
		shapes.append(icon)
	return shapes


func _update_shapes_gui(shapes: Array[Texture2D]):
	_shape_list.clear()
	for shape in shapes:
		assert(shape != null)
		assert(shape is Texture2D)
		_shape_list.add_icon_item(shape)
	_update_shape_list_buttons()


func _on_AddShape_pressed():
	_load_image_index = -1
	_load_image_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
	_load_image_dialog.popup_centered_ratio(0.7)


func _on_RemoveShape_pressed():
	var selected_indices := _shape_list.get_selected_items()
	if len(selected_indices) == 0:
		return

	var index : int = selected_indices[0]
	_shape_list.remove_item(index)

	var shapes := _get_shapes_from_gui()
	for brush in _get_brushes():
		brush.set_shapes(shapes)

	_update_shape_list_buttons()


func _on_ShapeList_item_activated(index: int):
	_request_modify_shape(index)


func _on_ChangeShape_pressed():
	var selected = _shape_list.get_selected_items()
	if len(selected) == 0:
		return
	_request_modify_shape(selected[0])


func _request_modify_shape(index: int):
	_load_image_index = index
	_load_image_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_load_image_dialog.popup_centered_ratio(0.7)


func _on_LoadImageDialog_files_selected(fpaths: PackedStringArray):
	var shapes := _get_shapes_from_gui()
	
	for fpath in fpaths:
		var tex := HT_Brush.load_shape_from_image_file(fpath, _logger)
		if tex == null:
			# Failed
			continue
		shapes.append(tex)
	
	for brush in _get_brushes():
		brush.set_shapes(shapes)
	
	_update_shapes_gui(shapes)


func _on_LoadImageDialog_file_selected(fpath: String):
	var tex := HT_Brush.load_shape_from_image_file(fpath, _logger)
	if tex == null:
		# Failed
		return
	
	var shapes := _get_shapes_from_gui()
	if _load_image_index == -1 or _load_image_index >= len(shapes):
		# Add
		shapes.append(tex)
	else:
		# Replace
		assert(_load_image_index >= 0)
		shapes[_load_image_index] = tex

	for brush in _get_brushes():
		brush.set_shapes(shapes)
	
	_update_shapes_gui(shapes)


func _notification(what: int):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		# Testing the scratchpad because visibility can not only change before entering the tree
		# since Godot 4 port, it can also change between entering the tree and being _ready...
		if visible and _scratchpad != null:
			_update_controls_from_brush()


func _update_controls_from_brush():
	var brush := _brush
	
	if brush == null:
		# To allow testing
		brush = _scratchpad.get_painter().get_brush()

	_update_shapes_gui(brush.get_shapes())

	_size_slider.set_value(brush.get_size(), false)
	_opacity_slider.set_value(brush.get_opacity() * 100.0, false)
	_pressure_enabled_checkbox.button_pressed = brush.is_pressure_enabled()
	_pressure_over_size_slider.set_value(brush.get_pressure_over_scale() * 100.0, false)
	_pressure_over_opacity_slider.set_value(brush.get_pressure_over_opacity() * 100.0, false)
	_frequency_distance_slider.set_value(brush.get_frequency_distance(), false)
	_frequency_time_slider.set_value(
		1000.0 / maxf(0.1, float(brush.get_frequency_time_ms())), false)
	_random_rotation_checkbox.button_pressed = brush.is_random_rotation_enabled()
	_shape_cycling_checkbox.button_pressed = brush.is_shape_cycling_enabled()


func _on_ClearScratchpad_pressed():
	_scratchpad.reset_image()


func _on_Size_value_changed(value: float):
	for brush in _get_brushes():
		brush.set_size(value)


func _on_Opacity_value_changed(value):
	for brush in _get_brushes():
		brush.set_opacity(value / 100.0)


func _on_PressureEnabled_toggled(button_pressed):
	for brush in _get_brushes():
		brush.set_pressure_enabled(button_pressed)


func _on_PressureOverSize_value_changed(value):
	for brush in _get_brushes():
		brush.set_pressure_over_scale(value / 100.0)


func _on_PressureOverOpacity_value_changed(value):
	for brush in _get_brushes():
		brush.set_pressure_over_opacity(value / 100.0)


func _on_FrequencyDistance_value_changed(value):
	for brush in _get_brushes():
		brush.set_frequency_distance(value)


func _on_FrequencyTime_value_changed(fps):
	fps = max(1.0, fps)
	var ms = 1000.0 / fps
	if is_equal_approx(fps, 60.0):
		ms = 0
	for brush in _get_brushes():
		brush.set_frequency_time_ms(ms)


func _on_RandomRotation_toggled(button_pressed: bool):
	for brush in _get_brushes():
		brush.set_random_rotation_enabled(button_pressed)


func _on_shape_cycling_toggled(button_pressed: bool):
	for brush in _get_brushes():
		brush.set_shape_cycling_enabled(button_pressed)


func _get_brushes() -> Array[HT_Brush]:
	if _brush != null:
		# We edit both the preview brush and the terrain brush
		# TODO Could we simply share the brush?
		return [_brush, _scratchpad.get_painter().get_brush()]
	# When testing the dialog in isolation, the edited brush might be null
	return [_scratchpad.get_painter().get_brush()]


func _on_ShapeList_item_selected(index):
	_update_shape_list_buttons()
	for brush in _get_brushes():
		brush.set_shape_index(index)


func _update_shape_list_buttons():
	var selected_count := len(_shape_list.get_selected_items())
	# There must be at least one shape
	_remove_shape_button.disabled = _shape_list.get_item_count() == 1 or selected_count == 0
	_change_shape_button.disabled = selected_count == 0


func _on_shape_list_empty_clicked(at_position, mouse_button_index):
	_update_shape_list_buttons()

