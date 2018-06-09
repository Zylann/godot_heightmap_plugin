tool
extends Control

const Brush = preload("../../hterrain_brush.gd")

onready var _size_slider = get_node("GridContainer/BrushSizeControl/Slider")
onready var _size_value_label = get_node("GridContainer/BrushSizeControl/Label")
onready var _size_label = get_node("GridContainer/BrushSizeLabel")

onready var _opacity_slider = get_node("GridContainer/BrushOpacityControl/Slider")
onready var _opacity_value_label = get_node("GridContainer/BrushOpacityControl/Label")
onready var _opacity_control = get_node("GridContainer/BrushOpacityControl")
onready var _opacity_label = get_node("GridContainer/BrushOpacityLabel")

onready var _flatten_height_box = get_node("GridContainer/FlattenHeightControl")
onready var _flatten_height_label = get_node("GridContainer/FlattenHeightLabel")

onready var _color_picker = get_node("GridContainer/ColorPickerButton")
onready var _color_label = get_node("GridContainer/ColorLabel")

onready var _density_slider = get_node("GridContainer/DensitySlider")
onready var _density_label = get_node("GridContainer/DensityLabel")

onready var _holes_label = get_node("GridContainer/HoleLabel")
onready var _holes_checkbox = get_node("GridContainer/HoleCheckbox")

var _brush = null


func _ready():
	_size_slider.connect("value_changed", self, "_on_size_slider_value_changed")
	_opacity_slider.connect("value_changed", self, "_on_opacity_slider_value_changed")
	_flatten_height_box.connect("value_changed", self, "_on_flatten_height_box_value_changed")
	_color_picker.connect("color_changed", self, "_on_color_picker_color_changed")
	_density_slider.connect("value_changed", self, "_on_density_slider_changed")
	_holes_checkbox.connect("toggled", self, "_on_holes_checkbox_toggled")

# Testing display modes
#var mode = 0
#func _input(event):
#	if event is InputEventKey:
#		if event.pressed:
#			set_display_mode(mode)
#			mode += 1
#			if mode >= Brush.MODE_COUNT:
#				mode = 0

func set_brush(brush):
	if brush != null:
		# Initial params
		_size_slider.value = brush.get_radius()
		_opacity_slider.ratio = brush.get_opacity()
		_flatten_height_box.value = brush.get_flatten_height()
		_color_picker.get_picker().color = brush.get_color()
		_density_slider.value = brush.get_detail_density()
		_holes_checkbox.pressed = not brush.get_mask_flag()
		
		set_display_mode(brush.get_mode())
		
	_brush = brush


func set_display_mode(mode):
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


func _on_size_slider_value_changed(v):
	if _brush != null:
		_brush.set_radius(int(v))
	_size_value_label.text = str(v)


func _on_opacity_slider_value_changed(v):
	if _brush != null:
		_brush.set_opacity(_opacity_slider.ratio)
	_opacity_value_label.text = str(v)


func _on_flatten_height_box_value_changed(v):
	if _brush != null:
		_brush.set_flatten_height(v)


func _on_color_picker_color_changed(v):
	if _brush != null:
		_brush.set_color(v)


func _on_density_slider_changed(v):
	if _brush != null:
		_brush.set_detail_density(v)


func _on_holes_checkbox_toggled(v):
	if _brush != null:
		# When checked, we draw holes. When unchecked, we clear holes
		_brush.set_mask_flag(not v)
