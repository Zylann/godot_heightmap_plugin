tool
extends Control


onready var _size_slider = get_node("GridContainer/BrushSizeControl/Slider")
onready var _size_label = get_node("GridContainer/BrushSizeControl/Label")

onready var _opacity_slider = get_node("GridContainer/BrushOpacityControl/Slider")
onready var _opacity_label = get_node("GridContainer/BrushOpacityControl/Label")

onready var _flatten_height_box = get_node("GridContainer/FlattenHeightControl")

onready var _color_picker = get_node("GridContainer/ColorPickerButton")

var _brush = null


func _ready():
	_size_slider.connect("value_changed", self, "_on_size_slider_value_changed")
	_opacity_slider.connect("value_changed", self, "_on_opacity_slider_value_changed")
	_flatten_height_box.connect("value_changed", self, "_on_flatten_height_box_value_changed")
	_color_picker.connect("color_changed", self, "_on_color_picker_color_changed")


func set_brush(brush):
	if brush != null:
		# Initial params
		_size_slider.value = brush.get_radius()
		_opacity_slider.ratio = brush.get_opacity()
		_flatten_height_box.value = brush.get_flatten_height()
		_color_picker.get_picker().color = brush.get_color()
	_brush = brush


func _on_size_slider_value_changed(v):
	if _brush != null:
		_brush.set_radius(int(v))
	_size_label.text = str(v)


func _on_opacity_slider_value_changed(v):
	if _brush != null:
		_brush.set_opacity(_opacity_slider.ratio)
	_opacity_label.text = str(v)


func _on_flatten_height_box_value_changed(v):
	if _brush != null:
		_brush.set_flatten_height(v)


func _on_color_picker_color_changed(v):
	if _brush != null:
		_brush.set_color(v)


