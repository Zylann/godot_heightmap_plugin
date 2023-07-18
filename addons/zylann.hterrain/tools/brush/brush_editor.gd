@tool
extends Control

const HT_TerrainPainter = preload("./terrain_painter.gd")
const HT_Brush = preload("./brush.gd")
const HT_Errors = preload("../../util/errors.gd")
#const NativeFactory = preload("../../native/factory.gd")
const HT_Logger = preload("../../util/logger.gd")
const HT_IntervalSlider = preload("../util/interval_slider.gd")

const HT_BrushSettingsDialogScene = preload("./settings_dialog/brush_settings_dialog.tscn")
const HT_BrushSettingsDialog = preload("./settings_dialog/brush_settings_dialog.gd")


@onready var _size_slider : Slider = $GridContainer/BrushSizeControl/Slider
@onready var _size_value_label : Label = $GridContainer/BrushSizeControl/Label
#onready var _size_label = _params_container.get_node("BrushSizeLabel")

@onready var _opacity_slider : Slider = $GridContainer/BrushOpacityControl/Slider
@onready var _opacity_value_label : Label = $GridContainer/BrushOpacityControl/Label
@onready var _opacity_control : Control = $GridContainer/BrushOpacityControl
@onready var _opacity_label : Label = $GridContainer/BrushOpacityLabel

@onready var _flatten_height_container : Control = $GridContainer/HB
@onready var _flatten_height_box : SpinBox = $GridContainer/HB/FlattenHeightControl
@onready var _flatten_height_label : Label = $GridContainer/FlattenHeightLabel
@onready var _flatten_height_pick_button : Button = $GridContainer/HB/FlattenHeightPickButton

@onready var _color_picker : ColorPickerButton = $GridContainer/ColorPickerButton
@onready var _color_label : Label = $GridContainer/ColorLabel

@onready var _density_slider : Slider = $GridContainer/DensitySlider
@onready var _density_label : Label = $GridContainer/DensityLabel

@onready var _holes_label : Label = $GridContainer/HoleLabel
@onready var _holes_checkbox : CheckBox = $GridContainer/HoleCheckbox

@onready var _slope_limit_label : Label = $GridContainer/SlopeLimitLabel
@onready var _slope_limit_control : HT_IntervalSlider = $GridContainer/SlopeLimit

@onready var _shape_texture_rect : TextureRect = get_node("BrushShapeButton/TextureRect")

var _terrain_painter : HT_TerrainPainter
var _brush_settings_dialog : HT_BrushSettingsDialog = null
var _logger = HT_Logger.get_for(self)

# TODO This is an ugly workaround for https://github.com/godotengine/godot/issues/19479
@onready var _temp_node = get_node("Temp")
@onready var _grid_container = get_node("GridContainer")
func _set_visibility_of(node: Control, v: bool):
	node.get_parent().remove_child(node)
	if v:
		_grid_container.add_child(node)
	else:
		_temp_node.add_child(node)
	node.visible = v


func _ready():
	_size_slider.value_changed.connect(_on_size_slider_value_changed)
	_opacity_slider.value_changed.connect(_on_opacity_slider_value_changed)
	_flatten_height_box.value_changed.connect(_on_flatten_height_box_value_changed)
	_color_picker.color_changed.connect(_on_color_picker_color_changed)
	_density_slider.value_changed.connect(_on_density_slider_changed)
	_holes_checkbox.toggled.connect(_on_holes_checkbox_toggled)
	_slope_limit_control.changed.connect(_on_slope_limit_changed)
	
	_size_slider.max_value = HT_Brush.MAX_SIZE_FOR_SLIDERS
	#if NativeFactory.is_native_available():
	#	_size_slider.max_value = 200
	#else:
	#	_size_slider.max_value = 50


func setup_dialogs(base_control: Node):
	assert(_brush_settings_dialog == null)
	_brush_settings_dialog = HT_BrushSettingsDialogScene.instantiate()
	base_control.add_child(_brush_settings_dialog)
	
	# That dialog has sub-dialogs
	_brush_settings_dialog.setup_dialogs(base_control)
	_brush_settings_dialog.set_brush(_terrain_painter.get_brush())


func _exit_tree():
	if _brush_settings_dialog != null:
		_brush_settings_dialog.queue_free()
		_brush_settings_dialog = null

# Testing display modes
#var mode = 0
#func _input(event):
#	if event is InputEventKey:
#		if event.pressed:
#			set_display_mode(mode)
#			mode += 1
#			if mode >= Brush.MODE_COUNT:
#				mode = 0

func set_terrain_painter(terrain_painter: HT_TerrainPainter):
	if _terrain_painter != null:
		_terrain_painter.flatten_height_changed.disconnect(_on_flatten_height_changed)
		_terrain_painter.get_brush().shapes_changed.disconnect(_on_brush_shapes_changed)
		_terrain_painter.get_brush().shape_index_changed.disconnect(_on_brush_shape_index_changed)
	
	_terrain_painter = terrain_painter

	if _terrain_painter != null:
		# TODO Had an issue in Godot 3.2.3 where mismatching type would silently cast to null...
		# It happens if the argument went through a Variant (for example if call_deferred is used)
		assert(_terrain_painter != null)
	
	if _terrain_painter != null:
		# Initial brush params
		_size_slider.value = _terrain_painter.get_brush().get_size()
		_opacity_slider.ratio = _terrain_painter.get_brush().get_opacity()
		# Initial specific params
		_flatten_height_box.value = _terrain_painter.get_flatten_height()
		_color_picker.get_picker().color = _terrain_painter.get_color()
		_density_slider.value = _terrain_painter.get_detail_density()
		_holes_checkbox.button_pressed = not _terrain_painter.get_mask_flag()
		
		var low := rad_to_deg(_terrain_painter.get_slope_limit_low_angle())
		var high := rad_to_deg(_terrain_painter.get_slope_limit_high_angle())
		_slope_limit_control.set_values(low, high)

		set_display_mode(_terrain_painter.get_mode())
		
		# Load default brush
		var brush := _terrain_painter.get_brush()
		var default_shape_fpath := HT_Brush.DEFAULT_BRUSH_TEXTURE_PATH
		var default_shape := HT_Brush.load_shape_from_image_file(default_shape_fpath, _logger)
		brush.set_shapes([default_shape])
		_update_shape_preview()
		
		_terrain_painter.flatten_height_changed.connect(_on_flatten_height_changed)
		brush.shapes_changed.connect(_on_brush_shapes_changed)
		brush.shape_index_changed.connect(_on_brush_shape_index_changed)


func _on_flatten_height_changed():
	_flatten_height_box.value = _terrain_painter.get_flatten_height()
	_flatten_height_pick_button.button_pressed = false


func _on_brush_shapes_changed():
	_update_shape_preview()


func _on_brush_shape_index_changed():
	_update_shape_preview()


func _update_shape_preview():
	var brush := _terrain_painter.get_brush()
	var i := brush.get_shape_index()
	_shape_texture_rect.texture = brush.get_shape(i)


func set_display_mode(mode: int):
	var show_flatten := mode == HT_TerrainPainter.MODE_FLATTEN
	var show_color := mode == HT_TerrainPainter.MODE_COLOR
	var show_density := mode == HT_TerrainPainter.MODE_DETAIL
	var show_opacity := mode != HT_TerrainPainter.MODE_MASK
	var show_holes := mode == HT_TerrainPainter.MODE_MASK
	var show_slope_limit := \
		mode == HT_TerrainPainter.MODE_SPLAT or mode == HT_TerrainPainter.MODE_DETAIL

	_set_visibility_of(_opacity_label, show_opacity)
	_set_visibility_of(_opacity_control, show_opacity)

	_set_visibility_of(_color_label, show_color)
	_set_visibility_of(_color_picker, show_color)

	_set_visibility_of(_flatten_height_label, show_flatten)
	_set_visibility_of(_flatten_height_container, show_flatten)

	_set_visibility_of(_density_label, show_density)
	_set_visibility_of(_density_slider, show_density)

	_set_visibility_of(_holes_label, show_holes)
	_set_visibility_of(_holes_checkbox, show_holes)

	_set_visibility_of(_slope_limit_label, show_slope_limit)
	_set_visibility_of(_slope_limit_control, show_slope_limit)

	_flatten_height_pick_button.button_pressed = false


func _on_size_slider_value_changed(v: float):
	if _terrain_painter != null:
		_terrain_painter.set_brush_size(int(v))
	_size_value_label.text = str(v)


func _on_opacity_slider_value_changed(v: float):
	if _terrain_painter != null:
		_terrain_painter.set_opacity(_opacity_slider.ratio)
	_opacity_value_label.text = str(v)


func _on_flatten_height_box_value_changed(v: float):
	if _terrain_painter != null:
		_terrain_painter.set_flatten_height(v)


func _on_color_picker_color_changed(v: Color):
	if _terrain_painter != null:
		_terrain_painter.set_color(v)


func _on_density_slider_changed(v: float):
	if _terrain_painter != null:
		_terrain_painter.set_detail_density(v)


func _on_holes_checkbox_toggled(v: bool):
	if _terrain_painter != null:
		# When checked, we draw holes. When unchecked, we clear holes
		_terrain_painter.set_mask_flag(not v)


func _on_BrushShapeButton_pressed():
	_brush_settings_dialog.popup_centered()


func _on_FlattenHeightPickButton_pressed():
	_terrain_painter.set_meta("pick_height", true)


func _on_slope_limit_changed():
	var low = deg_to_rad(_slope_limit_control.get_low_value())
	var high = deg_to_rad(_slope_limit_control.get_high_value())
	_terrain_painter.set_slope_limit_angles(low, high)
