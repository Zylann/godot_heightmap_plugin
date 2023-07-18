
# Slider with two handles representing an interval.

@tool
extends Control

const VALUE_LOW = 0
const VALUE_HIGH = 1
const VALUE_COUNT = 2

const FG_MARGIN = 1

signal changed

var _min_value := 0.0
var _max_value := 1.0
var _values = [0.2, 0.6]
var _grabbing := false


func _get_property_list():
	return [
		{
			"name": "min_value",
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "max_value",
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "range",
			"type": TYPE_VECTOR2,
			"usage": PROPERTY_USAGE_STORAGE
		}
	]


func _get(key: StringName):
	match key:
		&"min_value":
			return _min_value
		&"max_value":
			return _max_value
		&"range":
			return Vector2(_min_value, _max_value)


func _set(key: StringName, value):
	match key:
		&"min_value":
			_min_value = min(value, _max_value)
			queue_redraw()
		&"max_value":
			_max_value = max(value, _min_value)
			queue_redraw()
		&"range":
			_min_value = value.x
			_max_value = value.y


func set_values(low: float, high: float):
	if low > high:
		low = high
	if high < low:
		high = low
	_values[VALUE_LOW] = low
	_values[VALUE_HIGH] = high
	queue_redraw()


func set_value(i: int, v: float, notify_change: bool):
	var min_value = _min_value
	var max_value = _max_value
	
	match i:
		VALUE_LOW:
			max_value = _values[VALUE_HIGH]
		VALUE_HIGH:
			min_value = _values[VALUE_LOW]
		_:
			assert(false)
	
	v = clampf(v, min_value, max_value)
	if v != _values[i]:
		_values[i] = v
		queue_redraw()
		if notify_change:
			changed.emit()


func get_value(i: int) -> float:
	return _values[i]


func get_low_value() -> float:
	return _values[VALUE_LOW]


func get_high_value() -> float:
	return _values[VALUE_HIGH]


func get_ratio(i: int) -> float:
	return _value_to_ratio(_values[i])


func get_low_ratio() -> float:
	return get_ratio(VALUE_LOW)


func get_high_ratio() -> float:
	return get_ratio(VALUE_HIGH)


func _ratio_to_value(r: float) -> float:
	return r * (_max_value - _min_value) + _min_value


func _value_to_ratio(v: float) -> float:
	if absf(_max_value - _min_value) < 0.001:
		return 0.0
	return (v - _min_value) / (_max_value - _min_value)


func _get_closest_index(ratio: float) -> int:
	var distance_low := absf(ratio - get_low_ratio())
	var distance_high := absf(ratio - get_high_ratio())
	if distance_low < distance_high:
		return VALUE_LOW
	return VALUE_HIGH


func _set_from_pixel(px: float):
	var r := (px - FG_MARGIN) / (size.x - FG_MARGIN * 2.0)
	var i := _get_closest_index(r)
	var v := _ratio_to_value(r)
	set_value(i, v, true)


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_grabbing = true
				_set_from_pixel(event.position.x)
		else:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_grabbing = false
				
	elif event is InputEventMouseMotion:
		if _grabbing:
			_set_from_pixel(event.position.x)			


func _draw():
	var grabber_width := 3
	var background_v_margin := 0
	var foreground_margin := FG_MARGIN
	var grabber_color := Color(0.8, 0.8, 0.8)
	var interval_color := Color(0.4,0.4,0.4)
	var background_color := Color(0.1, 0.1, 0.1)
	
	var control_rect := Rect2(Vector2(), size)
	
	var bg_rect := Rect2(
		control_rect.position.x, 
		control_rect.position.y + background_v_margin, 
		control_rect.size.x, 
		control_rect.size.y - 2 * background_v_margin)
	draw_rect(bg_rect, background_color)
	
	var fg_rect := control_rect.grow(-foreground_margin)
	
	var low_ratio := get_low_ratio()
	var high_ratio := get_high_ratio()
	
	var low_x := fg_rect.position.x + low_ratio * fg_rect.size.x
	var high_x := fg_rect.position.x + high_ratio * fg_rect.size.x

	var interval_rect := Rect2(
		low_x, fg_rect.position.y, high_x - low_x, fg_rect.size.y)
	draw_rect(interval_rect, interval_color)

	low_x = fg_rect.position.x + low_ratio * (fg_rect.size.x - grabber_width)
	high_x = fg_rect.position.x + high_ratio * (fg_rect.size.x - grabber_width)
	
	for x in [low_x, high_x]:
		var grabber_rect := Rect2(
			x,
			fg_rect.position.y,
			grabber_width,
			fg_rect.size.y)
		draw_rect(grabber_rect, grabber_color)
	
