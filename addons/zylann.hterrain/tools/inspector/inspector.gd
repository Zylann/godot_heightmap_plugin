
# GDScript implementation of an inspector.
# It generates controls for a provided list of properties,
# which is easier to maintain than placing them by hand and connecting things in the editor.

@tool
extends Control

const USAGE_FILE = "file"
const USAGE_ENUM = "enum"

signal property_changed(key, value)

# Used for most simple types
class HT_InspectorEditor:
	var control = null
	var getter := Callable()
	var setter := Callable()
	var item_disabler_setter := Callable()
	var key_label : Label


# Used when the control cannot hold the actual value
class HT_InspectorResourceEditor extends HT_InspectorEditor:
	var value = null
	var label = null
	
	func get_value():
		return value
	
	func set_value(v):
		value = v
		label.text = "null" if v == null else v.resource_path


class HT_InspectorVectorEditor extends HT_InspectorEditor:
	signal value_changed(v)
	
	var value := Vector2()
	var xed = null
	var yed = null
	
	func get_value():
		return value
	
	func set_value(v):
		xed.value = v.x
		yed.value = v.y
		value = v
	
	func _component_changed(v, i):
		value[i] = v
		value_changed.emit(value)		


# TODO Rename _schema
var _prototype = null
var _edit_signal := true
# name => editor
var _editors := {}

# Had to separate the container because otherwise I can't open dialogs properly...
@onready var _grid_container = get_node("GridContainer")
@onready var _file_dialog = get_node("OpenFileDialog")


# Test
#func _ready():
#	set_prototype({
#		"seed": {
#			"type": TYPE_INT,
#			"randomizable": true
#		},
#		"base_height": {
#			"type": TYPE_REAL,
#			"range": {"min": -1000.0, "max": 1000.0, "step": 0.1}
#		},
#		"height_range": {
#			"type": TYPE_REAL,
#			"range": {"min": -1000.0, "max": 1000.0, "step": 0.1 },
#			"default_value": 500.0
#		},
#		"streamed": {
#			"type": TYPE_BOOL
#		},
#		"texture": {
#			"type": TYPE_OBJECT,
#			"object_type": Resource
#		}
#	})


# TODO Rename clear_schema
func clear_prototype():
	_editors.clear()
	var i = _grid_container.get_child_count() - 1
	while i >= 0:
		var child = _grid_container.get_child(i)
		_grid_container.remove_child(child)
		child.call_deferred("free")
		i -= 1
	_prototype = null


func get_value(key: String):
	var editor = _editors[key]
	return editor.getter.call()


func get_values():
	var values = {}
	for key in _editors:
		var editor = _editors[key]
		values[key] = editor.getter.call()
	return values


func set_value(key: String, value):
	var editor = _editors[key]
	editor.setter.call(value)


func set_values(values: Dictionary):
	for key in values:
		if _editors.has(key):
			var editor = _editors[key]
			var v = values[key]
			editor.setter.call(v)


func set_item_disabled(key: String, id:int, disabled:bool):
	var editor = _editors[key]
	if editor.item_disabler_setter != null:
		editor.item_disabler_setter.call(id, disabled)


# TODO Rename set_schema
func set_prototype(proto: Dictionary):
	clear_prototype()
	
	for key in proto:
		var prop = proto[key]
		
		var label := Label.new()
		label.text = str(key).capitalize()
		_grid_container.add_child(label)
		
		var editor := _make_editor(key, prop)
		editor.key_label = label
		
		if prop.has("default_value"):
			editor.setter.call(prop.default_value)

		_editors[key] = editor
		
		if prop.has("enabled"):
			set_property_enabled(key, prop.enabled)
		
		_grid_container.add_child(editor.control)
	
	_prototype = proto


func trigger_all_modified():
	for key in _prototype:
		var value = _editors[key].getter.call_func()
		property_changed.emit(key, value)


func set_property_enabled(prop_name: String, enabled: bool):
	var ed = _editors[prop_name]
	
	if ed.control is BaseButton:
		ed.control.disabled = not enabled
		
	elif ed.control is SpinBox:
		ed.control.editable = enabled

	elif ed.control is LineEdit:
		ed.control.editable = enabled
	
	# TODO Support more editors

	var col = ed.key_label.modulate
	if enabled:
		col.a = 1.0
	else:
		col.a = 0.5
	ed.key_label.modulate = col


func _make_editor(key: String, prop: Dictionary) -> HT_InspectorEditor:
	var ed : HT_InspectorEditor = null
	
	var editor : Control = null
	var getter : Callable
	var setter : Callable
	var item_disabler_setter : Callable
	var extra = null
	
	match prop.type:
		TYPE_INT, \
		TYPE_FLOAT:
			var pre = null
			if prop.has("randomizable") and prop.randomizable:
				editor = HBoxContainer.new()
				pre = Button.new()
				pre.pressed.connect(_randomize_property_pressed.bind(key))
				pre.text = "Randomize"
				editor.add_child(pre)
			
			if prop.type == TYPE_INT and prop.has("usage") and prop.usage == USAGE_ENUM:
				# Enumerated value
				assert(prop.has("enum_items"))
				var option_button := OptionButton.new()
				
				for i in len(prop.enum_items):
					var item:Array = prop.enum_items[i]
					var value:int = item[0]
					var text:String = item[1]
					option_button.add_item(text, value)

				getter = option_button.get_selected_id
				setter = func select_id(id: int):
					var index:int = option_button.get_item_index(id)
					assert(index >= 0)
					option_button.select(index)
				item_disabler_setter = func set_item_disabled(id: int, disabled:bool):
					var index:int = option_button.get_item_index(id)
					assert(index >= 0)
					option_button.set_item_disabled(index, disabled)

				option_button.item_selected.connect(_property_edited.bind(key))
				
				editor = option_button

			else:
				# Numeric value
				var spinbox := SpinBox.new()
				# Spinboxes have shit UX when not expanded...
				spinbox.custom_minimum_size = Vector2(120, 16) 
				_setup_range_control(spinbox, prop)
				spinbox.value_changed.connect(_property_edited.bind(key))
				
				# TODO In case the type is INT, the getter should return an integer!
				getter = spinbox.get_value
				setter = spinbox.set_value
				
				var show_slider = prop.has("range") \
					and not (prop.has("slidable") \
					and prop.slidable == false)
					
				if show_slider:
					if editor == null:
						editor = HBoxContainer.new()
					var slider := HSlider.new()
					# Need to give some size because otherwise the slider is hard to click...
					slider.custom_minimum_size = Vector2(32, 16)
					_setup_range_control(slider, prop)
					slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					spinbox.share(slider)
					editor.add_child(slider)
					editor.add_child(spinbox)
				else:
					spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					if editor == null:
						editor = spinbox
					else:
						editor.add_child(spinbox)
			
		TYPE_STRING:
			if prop.has("usage") and prop.usage == USAGE_FILE:
				editor = HBoxContainer.new()
				
				var line_edit := LineEdit.new()
				line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				editor.add_child(line_edit)
				
				var exts = []
				if prop.has("exts"):
					exts = prop.exts
				
				var load_button := Button.new()
				load_button.text = "..."
				load_button.pressed.connect(_on_ask_load_file.bind(key, exts))
				editor.add_child(load_button)
				
				line_edit.text_submitted.connect(_property_edited.bind(key))
				getter = line_edit.get_text
				setter = line_edit.set_text
				
			else:
				editor = LineEdit.new()
				editor.text_submitted.connect(_property_edited.bind(key))
				getter = editor.get_text
				setter = editor.set_text
		
		TYPE_COLOR:
			editor = ColorPickerButton.new()
			editor.color_changed.connect(_property_edited.bind(key))
			getter = editor.get_pick_color
			setter = editor.set_pick_color
			
		TYPE_BOOL:
			editor = CheckBox.new()
			editor.toggled.connect(_property_edited.bind(key))
			getter = editor.is_pressed
			setter = editor.set_pressed
		
		TYPE_OBJECT:
			# TODO How do I even check inheritance if I work on the class themselves, not instances?
			if prop.object_type == Resource:
				editor = HBoxContainer.new()
				
				var label := Label.new()
				label.text = "null"
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label.clip_text = true
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				editor.add_child(label)
				
				var load_button := Button.new()
				load_button.text = "Load..."
				load_button.pressed.connect(_on_ask_load_texture.bind(key))
				editor.add_child(load_button)

				var clear_button := Button.new()
				clear_button.text = "Clear"
				clear_button.pressed.connect(_on_ask_clear_texture.bind(key))
				editor.add_child(clear_button)
				
				ed = HT_InspectorResourceEditor.new()
				ed.label = label
				getter = ed.get_value
				setter = ed.set_value
		
		TYPE_VECTOR2:
			editor = HBoxContainer.new()

			ed = HT_InspectorVectorEditor.new()

			var xlabel := Label.new()
			xlabel.text = "x"
			editor.add_child(xlabel)
			var xed := SpinBox.new()
			xed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			xed.step = 0.01
			xed.min_value = -10000
			xed.max_value = 10000
			# TODO This will fire twice (for each coordinate), hmmm...
			xed.value_changed.connect(ed._component_changed.bind(0))
			editor.add_child(xed)
			
			var ylabel := Label.new()
			ylabel.text = "y"
			editor.add_child(ylabel)
			var yed = SpinBox.new()
			yed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			yed.step = 0.01
			yed.min_value = -10000
			yed.max_value = 10000
			yed.value_changed.connect(ed._component_changed.bind(1))
			editor.add_child(yed)
			
			ed.xed = xed
			ed.yed = yed
			ed.value_changed.connect(_property_edited.bind(key))
			getter = ed.get_value
			setter = ed.set_value
		
		_:
			editor = Label.new()
			editor.text = "<not editable>"
			getter = _dummy_getter
			setter = _dummy_setter
	
	if not(editor is CheckButton):
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if ed == null:
		# Default
		ed = HT_InspectorEditor.new()
	ed.control = editor
	ed.getter = getter
	ed.setter = setter
	ed.item_disabler_setter = item_disabler_setter
	
	return ed


static func _setup_range_control(range_control: Range, prop):
	if prop.type == TYPE_INT:
		range_control.step = 1
		range_control.rounded = true
	else:
		range_control.step = 0.1
	if prop.has("range"):
		range_control.min_value = prop.range.min
		range_control.max_value = prop.range.max
		if prop.range.has("step"):
			range_control.step = prop.range.step
	else:
		# Where is INT_MAX??
		range_control.min_value = -0x7fffffff
		range_control.max_value = 0x7fffffff


func _property_edited(value, key):
	if _edit_signal:
		property_changed.emit(key, value)


func _randomize_property_pressed(key):
	var prop = _prototype[key]
	var v = 0
	
	# TODO Support range step
	match prop.type:
		TYPE_INT:
			if prop.has("range"):
				v = randi() % (prop.range.max - prop.range.min) + prop.range.min
			else:
				v = randi() - 0x7fffffff
		TYPE_FLOAT:
			if prop.has("range"):
				v = randf_range(prop.range.min, prop.range.max)
			else:
				v = randf()
	
	_editors[key].setter.call(v)


func _dummy_getter():
	pass


func _dummy_setter(v):
	# TODO Could use extra data to store the value anyways?
	pass


func _on_ask_load_texture(key):
	_open_file_dialog(["*.png ; PNG files"], _on_texture_selected.bind(key), 
		FileDialog.ACCESS_RESOURCES)


func _open_file_dialog(filters: Array, callback: Callable, access: int):
	_file_dialog.access = access
	_file_dialog.clear_filters()
	for filter in filters:
		_file_dialog.add_filter(filter)

	# Can't just use one-shot signals because the dialog could be closed without choosing a file...
#	if not _file_dialog.file_selected.is_connected(callback):
#		_file_dialog.file_selected.connect(callback, Object.CONNECT_ONE_SHOT)
	_file_dialog.visibility_changed.connect(
		call_deferred.bind("_on_file_dialog_visibility_changed"), CONNECT_ONE_SHOT)
	_file_dialog.file_selected.connect(callback)
	
	_file_dialog.popup_centered_ratio(0.7)


func _on_file_dialog_visibility_changed():
	if _file_dialog.visible == false:
		# Disconnect listeners automatically,
		# so we can re-use the same dialog with different listeners
		var cons = _file_dialog.get_signal_connection_list("file_selected")
		for con in cons:
			_file_dialog.file_selected.disconnect(con.callable)


func _on_texture_selected(path: String, key):
	var tex = load(path)
	if tex == null:
		return
	var ed = _editors[key]
	ed.setter.call(tex)
	_property_edited(tex, key)


func _on_ask_clear_texture(key):
	var ed = _editors[key]
	ed.setter.call(null)
	_property_edited(null, key)


func _on_ask_load_file(key, exts):
	var filters := []
	for ext in exts:
		filters.append(str("*.", ext, " ; ", ext.to_upper(), " files"))
	_open_file_dialog(filters, _on_file_selected.bind(key), FileDialog.ACCESS_FILESYSTEM)


func _on_file_selected(path, key):
	var ed = _editors[key]
	ed.setter.call(path)
	_property_edited(path, key)
