@tool
extends Control

const MIN_UI_CIRCLE_SIZE = 40
const MAX_UI_CIRCLE_SIZE = 500

@onready var _brush_size_background: TextureRect = %BrushSizeBackground
@onready var _brush_size_preview: TextureRect = %BrushSizePreview
@onready var _value_label: Label = %ValueLabel
@onready var _overlay_name_label: Label = %OverlayNameLabel
@onready var _exponential_slider: HSlider = %ExponentialSlider

@export var brush_size_factor: float = 2.5
@export var min_value: float = -1
@export var max_value: float = -1
var _brush_preview_color: Color = Color.LIGHT_GREEN
var _dpi_scale: float = 1.0
var _value: float = 0.0

signal on_value_selected(new_value: int)
signal on_cancel

var background_margin: int = 10


func _physics_process(delta: float) -> void:
	_update_size(_get_mouse_distance())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			on_value_selected.emit(_value)
		else:
			on_cancel.emit()
	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			on_cancel.emit()


func set_brush_preview_color(brush_color: Color) -> void:
	_brush_preview_color = brush_color
	_update_brush_preview_color()


func _update_brush_preview_color() -> void:
	_brush_size_preview.modulate = _brush_preview_color


func set_overlay_name(overlay_label_name: String) -> void:
	_overlay_name_label.text = overlay_label_name


func _update_size(value: float) -> void:
	var dist := clampi(value * brush_size_factor, MIN_UI_CIRCLE_SIZE*_dpi_scale, MAX_UI_CIRCLE_SIZE*_dpi_scale )
	var ui_size := clampi(dist, MIN_UI_CIRCLE_SIZE*_dpi_scale, MAX_UI_CIRCLE_SIZE*_dpi_scale)
	_brush_size_background.size = Vector2(ui_size + background_margin, ui_size + background_margin)
	_brush_size_background.position = Vector2(-( (ui_size/2) + (background_margin/2)) , -( (ui_size/2) + (background_margin/2)))
	_brush_size_preview.size = Vector2(ui_size, ui_size)
	_brush_size_preview.position = Vector2(-(ui_size/2) , -(ui_size/2))

	_exponential_slider.min_value = MIN_UI_CIRCLE_SIZE*_dpi_scale
	_exponential_slider.max_value = MAX_UI_CIRCLE_SIZE*_dpi_scale
	_exponential_slider.value = (_exponential_slider.min_value+_exponential_slider.max_value)-ui_size

	var re_value: float = absf(1.0-_exponential_slider.get_as_ratio()) * (max_value-min_value)
	re_value += min_value

	_value = roundi(re_value)
	_value_label.text = str(_value)


func apply_dpi_scale(dpi_scale: float) -> void:
	_dpi_scale = dpi_scale


func setup_start_position(start_pos: Vector2, initial_value: float) -> void:
	position = start_pos

	_exponential_slider.min_value = MIN_UI_CIRCLE_SIZE*_dpi_scale
	_exponential_slider.max_value = MAX_UI_CIRCLE_SIZE*_dpi_scale

	var reverse: float = (initial_value - min_value) / (max_value-min_value)
	reverse = absf(1-reverse)
	_exponential_slider.set_as_ratio(reverse)

	var ui_size: float = (_exponential_slider.min_value+_exponential_slider.max_value) - _exponential_slider.value

	position.x -= (ui_size/brush_size_factor)


func _get_mouse_distance() -> float:
	var global_mouse_pos: Vector2 = get_global_mouse_position()
	
	var distance: float = position.distance_to(global_mouse_pos)
	if position.x > global_mouse_pos.x:
		distance = 0

	return distance;
