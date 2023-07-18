@tool
extends Control

const FG_MARGIN = 2
const MAX_DECIMALS_VISUAL = 3

signal value_changed(value)


var _value := 0.0
@export var value: float:
	get:
		return _value
	set(v):
		set_value_no_notify(v)


var _min_value := 0.0
@export var min_value: float:
	get:
		return _min_value
	set(v):
		set_min_value(v)


var _max_value := 100.0
@export var max_value: float:
	get:
		return _max_value
	set(v):
		set_max_value(v)


var _prefix := ""
@export var prefix: String:
	get:
		return _prefix
	set(v):
		set_prefix(v)


var _suffix := ""
@export var suffix: String:
	get:
		return _suffix
	set(v):
		set_suffix(v)


var _rounded := false
@export var rounded: bool:
	get:
		return _rounded
	set(v):
		set_rounded(v)


var _centered := true
@export var centered: bool:
	get:
		return _centered
	set(v):
		set_centered(v)


var _allow_greater := false
@export var allow_greater: bool:
	get:
		return _allow_greater
	set(v):
		set_allow_greater(v)


# There is still a limit when typing a larger value, but this one is to prevent software
# crashes or freezes. The regular min and max values are for slider UX. Exceeding it should be 
# a corner case.
var _greater_max_value := 10000.0
@export var greater_max_value: float:
	get:
		return _greater_max_value
	set(v):
		set_greater_max_value(v)


var _label : Label
var _label2 : Label
var _line_edit : LineEdit
var _ignore_line_edit := false
var _pressing := false
var _grabbing := false
var _press_pos := Vector2()


func _init():
	custom_minimum_size = Vector2(32, 28)
	
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	#_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.anchor_top = 0
	_label.anchor_left = 0
	_label.anchor_right = 1
	_label.anchor_bottom = 1
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color_shadow", Color(0,0,0,0.5))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

	_label2 = Label.new()
	_label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label2.clip_text = true
	#_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label2.anchor_top = 0
	_label2.anchor_left = 0
	_label2.anchor_right = 1
	_label2.anchor_bottom = 1
	_label2.offset_left = 8
	_label2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label2.add_theme_color_override("font_color_shadow", Color(0,0,0,0.5))
	_label2.add_theme_constant_override("shadow_offset_x", 1)
	_label2.add_theme_constant_override("shadow_offset_y", 1)
	_label2.hide()
	add_child(_label2)
	
	_line_edit = LineEdit.new()
	_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line_edit.anchor_top = 0
	_line_edit.anchor_left = 0
	_line_edit.anchor_right = 1
	_line_edit.anchor_bottom = 1
	_line_edit.gui_input.connect(_on_LineEdit_gui_input)
	_line_edit.focus_exited.connect(_on_LineEdit_focus_exited)
	_line_edit.text_submitted.connect(_on_LineEdit_text_submitted)
	_line_edit.hide()
	add_child(_line_edit)
	
	mouse_default_cursor_shape = Control.CURSOR_HSIZE


func _ready():
	pass # Replace with function body.


func set_centered(p_centered: bool):
	_centered = p_centered
	if _centered:
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.offset_right = 0
		_label2.hide()
	else:
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label.offset_right = -8
		_label2.show()
	queue_redraw()


func is_centered() -> bool:
	return _centered


func set_value_no_notify(v: float):
	set_value(v, false, false)


func set_value(v: float, notify_change: bool, use_slider_maximum: bool = false):
	if _allow_greater and not use_slider_maximum:
		v = clampf(v, _min_value, _greater_max_value)
	else:
		v = clampf(v, _min_value, _max_value)

	if v != _value:
		_value = v

		queue_redraw()
		
		if notify_change:
			value_changed.emit(get_value())


func get_value():
	if _rounded:
		return int(roundf(_value))
	return _value


func set_min_value(minv: float):
	_min_value = minv
	#queue_redraw()


func get_min_value() -> float:
	return _min_value


func set_max_value(maxv: float):
	_max_value = maxv
	#queue_redraw()


func get_max_value() -> float:
	return _max_value


func set_greater_max_value(gmax: float):
	_greater_max_value = gmax


func get_greater_max_value() -> float:
	return _greater_max_value


func set_rounded(b: bool):
	_rounded = b
	queue_redraw()


func is_rounded() -> bool:
	return _rounded


func set_prefix(p_prefix: String):
	_prefix = p_prefix
	queue_redraw()


func get_prefix() -> String:
	return _prefix


func set_suffix(p_suffix: String):
	_suffix = p_suffix
	queue_redraw()


func get_suffix() -> String:
	return _suffix


func set_allow_greater(allow: bool):
	_allow_greater = allow


func is_allowing_greater() -> bool:
	return _allow_greater


func _set_from_pixel(px: float):
	var r := (px - FG_MARGIN) / (size.x - FG_MARGIN * 2.0)
	var v := _ratio_to_value(r)
	set_value(v, true, true)


func get_ratio() -> float:
	return _value_to_ratio(get_value())


func _ratio_to_value(r: float) -> float:
	return r * (_max_value - _min_value) + _min_value


func _value_to_ratio(v: float) -> float:
	if absf(_max_value - _min_value) < 0.001:
		return 0.0
	return (v - _min_value) / (_max_value - _min_value)


func _on_LineEdit_gui_input(event: InputEvent):
	if event is InputEventKey:
		if event.pressed:
			if event.keycode == KEY_ESCAPE:
				_ignore_line_edit = true
				_hide_line_edit()
				grab_focus()
				_ignore_line_edit = false


func _on_LineEdit_focus_exited():
	if _ignore_line_edit:
		return
	_enter_text()


func _on_LineEdit_text_submitted(text: String):
	_enter_text()


func _enter_text():
	var s = _line_edit.text.strip_edges()
	if s.is_valid_float():
		var v := s.to_float()
		if not _allow_greater:
			v = minf(v, _max_value)
		set_value(v, true, false)
	_hide_line_edit()


func _hide_line_edit():
	_line_edit.hide()
	_label.show()
	queue_redraw()


func _show_line_edit():
	_line_edit.show()
	_line_edit.text = str(get_value())
	_line_edit.select_all()
	_line_edit.grab_focus()
	_label.hide()
	queue_redraw()


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_press_pos = event.position
				_pressing = true
		else:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_pressing = false
				if _grabbing:
					_grabbing = false
					_set_from_pixel(event.position.x)
				else:
					_show_line_edit()
	
	elif event is InputEventMouseMotion:
		if _pressing and _press_pos.distance_to(event.position) > 2.0:
			_grabbing = true
		if _grabbing:
			_set_from_pixel(event.position.x)			


func _draw():
	if _line_edit.visible:
		return
	
	#var grabber_width := 3
	var background_v_margin := 0
	var foreground_margin := FG_MARGIN
	#var grabber_color := Color(0.8, 0.8, 0.8)
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
	# Clamping the ratio because the value can be allowed to exceed the slider's boundaries
	var ratio := clampf(get_ratio(), 0.0, 1.0)
	fg_rect.size.x *= ratio
	draw_rect(fg_rect, interval_color)
	
	var value_text := str(get_value())

	var dot_pos := value_text.find(".")
	if dot_pos != -1:
		var decimal_count := len(value_text) - dot_pos
		if decimal_count > MAX_DECIMALS_VISUAL:
			value_text = value_text.substr(0, dot_pos + MAX_DECIMALS_VISUAL + 1)
	
	if _centered:
		var text := value_text
		if _prefix != "":
			text = str(_prefix, " ", text)
		if _suffix != "":
			text = str(text, " ", _suffix)
		_label.text = text
	
	else:
		_label2.text = _prefix
		var text := value_text
		if _suffix != "":
			text = str(text, " ", _suffix)
		_label.text = text
