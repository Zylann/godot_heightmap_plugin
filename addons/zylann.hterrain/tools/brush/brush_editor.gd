tool
extends Control

const Brush = preload("../../hterrain_brush.gd")
const Errors = preload("../../util/errors.gd")
const NativeFactory = preload("../../native/factory.gd")
const Logger = preload("../../util/logger.gd")

const SHAPES_DIR = "addons/zylann.hterrain/tools/brush/shapes"
const DEFAULT_BRUSH = "round2.exr"

onready var _size_slider := $GridContainer/BrushSizeControl/Slider as Slider
onready var _size_value_label := $GridContainer/BrushSizeControl/Label as Label
#onready var _size_label = _params_container.get_node("BrushSizeLabel")

onready var _opacity_slider = $GridContainer/BrushOpacityControl/Slider
onready var _opacity_value_label = $GridContainer/BrushOpacityControl/Label
onready var _opacity_control = $GridContainer/BrushOpacityControl
onready var _opacity_label = $GridContainer/BrushOpacityLabel

onready var _flatten_height_box = $GridContainer/FlattenHeightControl
onready var _flatten_height_label = $GridContainer/FlattenHeightLabel

onready var _color_picker = $GridContainer/ColorPickerButton
onready var _color_label = $GridContainer/ColorLabel

onready var _density_slider = $GridContainer/DensitySlider
onready var _density_label = $GridContainer/DensityLabel

onready var _holes_label = $GridContainer/HoleLabel
onready var _holes_checkbox = $GridContainer/HoleCheckbox

onready var _shape_texture_rect = get_node("BrushShapeButton/TextureRect")

var _brush : Brush
var _load_image_dialog = null
var _logger = Logger.get_for(self)

# TODO This is an ugly workaround for https://github.com/godotengine/godot/issues/19479
onready var _temp_node = get_node("Temp")
onready var _grid_container = get_node("GridContainer")
func _set_visibility_of(node, v):
	node.get_parent().remove_child(node)
	if v:
		_grid_container.add_child(node)
	else:
		_temp_node.add_child(node)
	node.visible = v


func _ready():
	_size_slider.connect("value_changed", self, "_on_size_slider_value_changed")
	_opacity_slider.connect("value_changed", self, "_on_opacity_slider_value_changed")
	_flatten_height_box.connect("value_changed", self, "_on_flatten_height_box_value_changed")
	_color_picker.connect("color_changed", self, "_on_color_picker_color_changed")
	_density_slider.connect("value_changed", self, "_on_density_slider_changed")
	_holes_checkbox.connect("toggled", self, "_on_holes_checkbox_toggled")
	
	if NativeFactory.is_native_available():
		_size_slider.max_value = 200
	else:
		_size_slider.max_value = 50


func setup_dialogs(base_control: Control):
	assert(_load_image_dialog == null)
	_load_image_dialog = EditorFileDialog.new()
	_load_image_dialog.mode = EditorFileDialog.MODE_OPEN_FILE
	_load_image_dialog.add_filter("*.exr ; EXR files")
	_load_image_dialog.resizable = true
	_load_image_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_load_image_dialog.current_dir = SHAPES_DIR
	_load_image_dialog.connect("file_selected", self, "_on_LoadImageDialog_file_selected")
	base_control.add_child(_load_image_dialog)


func _exit_tree():
	if _load_image_dialog != null:
		_load_image_dialog.queue_free()
		_load_image_dialog = null

# Testing display modes
#var mode = 0
#func _input(event):
#	if event is InputEventKey:
#		if event.pressed:
#			set_display_mode(mode)
#			mode += 1
#			if mode >= Brush.MODE_COUNT:
#				mode = 0

func set_brush(brush: Brush):
	if brush != null:
		# Initial params
		_size_slider.value = brush.get_radius()
		_opacity_slider.ratio = brush.get_opacity()
		_flatten_height_box.value = brush.get_flatten_height()
		_color_picker.get_picker().color = brush.get_color()
		_density_slider.value = brush.get_detail_density()
		_holes_checkbox.pressed = not brush.get_mask_flag()

		set_display_mode(brush.get_mode())
		set_brush_shape_from_file(SHAPES_DIR.plus_file(DEFAULT_BRUSH))

	_brush = brush


func set_display_mode(mode: int):
	var show_flatten = mode == Brush.MODE_FLATTEN
	var show_color = mode == Brush.MODE_COLOR
	var show_density = mode == Brush.MODE_DETAIL
	var show_opacity = mode != Brush.MODE_MASK
	var show_holes = mode == Brush.MODE_MASK

	_set_visibility_of(_opacity_label, show_opacity)
	_set_visibility_of(_opacity_control, show_opacity)

	_set_visibility_of(_color_label, show_color)
	_set_visibility_of(_color_picker, show_color)

	_set_visibility_of(_flatten_height_label, show_flatten)
	_set_visibility_of(_flatten_height_box, show_flatten)

	_set_visibility_of(_density_label, show_density)
	_set_visibility_of(_density_slider, show_density)

	_set_visibility_of(_holes_label, show_holes)
	_set_visibility_of(_holes_checkbox, show_holes)

#	_opacity_label.visible = show_opacity
#	_opacity_control.visible = show_opacity
#
#	_color_picker.visible = show_color
#	_color_label.visible = show_color
#
#	_flatten_height_box.visible = show_flatten
#	_flatten_height_label.visible = show_flatten
#
#	_density_label.visible = show_density
#	_density_slider.visible = show_density
#
#	_holes_label.visible = show_holes
#	_holes_checkbox.visible = show_holes


func _on_size_slider_value_changed(v: float):
	if _brush != null:
		_brush.set_radius(int(v))
	_size_value_label.text = str(v)


func _on_opacity_slider_value_changed(v: float):
	if _brush != null:
		_brush.set_opacity(_opacity_slider.ratio)
	_opacity_value_label.text = str(v)


func _on_flatten_height_box_value_changed(v: float):
	if _brush != null:
		_brush.set_flatten_height(v)


func _on_color_picker_color_changed(v: Color):
	if _brush != null:
		_brush.set_color(v)


func _on_density_slider_changed(v: float):
	if _brush != null:
		_brush.set_detail_density(v)


func _on_holes_checkbox_toggled(v: bool):
	if _brush != null:
		# When checked, we draw holes. When unchecked, we clear holes
		_brush.set_mask_flag(not v)


func _on_BrushShapeButton_pressed():
	_load_image_dialog.popup_centered_ratio(0.7)


func _on_LoadImageDialog_file_selected(path: String):
	set_brush_shape_from_file(path)


func set_brush_shape_from_file(path: String):
	var im := Image.new()
	var err := im.load(path)
	if err != OK:
		_logger.error("Could not load image at '{0}', error {1}" \
			.format([path, Errors.get_message(err)]))
		return

	if _brush != null:
		var im2 := im
		var v := Engine.get_version_info()
		if v.major == 3 and v.minor < 1:
			# Forcing image brushes would ruin resized ones,
			# due to https://github.com/godotengine/godot/issues/24244
			if path.find(SHAPES_DIR.plus_file(DEFAULT_BRUSH)) != -1:
				im2 = null

		_brush.set_shape(im2)

	var tex := ImageTexture.new()
	tex.create_from_image(im, Texture.FLAG_FILTER)
	_shape_texture_rect.texture = tex
