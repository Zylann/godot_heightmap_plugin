tool
extends WindowDialog


const PRESET_CUSTOM = 0
const PRESET_RGB_ALPHA = 1
const PRESET_ONE_PER_CHANNEL = 2

const _channel_to_index = {"r": 0, "g": 1, "b": 2, "a": 3}


onready var _preset_selector = get_node("VBoxContainer/HBoxContainer/Middle/PresetSelector")
onready var _output_node = get_node("VBoxContainer/HBoxContainer/Output/CenterContainer/Output")
onready var _save_file_dialog = get_node("SaveFileDialog")

var _config = {
	"input":[
		null, # path/to/texture.png
		null,
		null,
		null
	],
	"mappings":[
		{"r": "r", "g": "g", "b": "b", "a": "a"},
		null,
		null,
		null
	],
	"output": null # path/to/texture.png
}


func _ready():
	_preset_selector.clear()
	_preset_selector.add_item("Custom", PRESET_CUSTOM)
	_preset_selector.add_item("RGB + Alpha", PRESET_RGB_ALPHA)
	_preset_selector.add_item("One per channel", PRESET_ONE_PER_CHANNEL)
	
	_reset_mappings()
	_reset_textures()
	
	for i in range(4):
		var node = _get_input_node(i)
		node.connect("texture_path_changed", self, "_on_input_texture_changed", [i])
	

func set_load_texture_dialog(dialog):
	for i in range(4):
		var node = _get_input_node(i)
		node.set_load_texture_dialog(dialog)


func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible == false:
			#_reset_mappings()
			_reset_textures()


func _on_input_texture_changed(file_path, i):
	_config.input[i] = file_path


func _get_input_node(i):
	var inputs = get_node("VBoxContainer/HBoxContainer/Inputs")
	return inputs.get_node("InputTexture" + str(i))


func _reset_textures():
	for i in range(len(_config.input)):
		_config.input[i] = null
		var node = _get_input_node(i)
		node.reset()
	_config.output = null


func _reset_mappings():
	for i in range(len(_config.mappings)):
		_config.mappings[i] = null
	update()


func _on_PresetSelector_item_selected(id):
	match id:
		
		PRESET_CUSTOM:
			pass
		
		PRESET_RGB_ALPHA:
			_reset_mappings()
			_config.mappings[0] = {
				"r": "r",
				"g": "g",
				"b": "b"
			}
			_config.mappings[1] = {
				"r": "a"
			}
		
		PRESET_ONE_PER_CHANNEL:
			_reset_mappings()
			_config.mappings[0] = {"r": "r"}
			_config.mappings[1] = {"r": "g"}
			_config.mappings[2] = {"r": "b"}
			_config.mappings[3] = {"r": "a"}
		
		_:
			print("Preset not implemented")
	
	update()


func _get_input_position(i, c):
	var node = _get_input_node(i)
	var slot = node.get_slot(c)
	var local_pos = slot.rect_size / 2.0
	return get_position_relative_to(slot, local_pos, self)


func _get_output_position(c):
	var slot = _output_node.get_slot(c)
	var local_pos = slot.rect_size / 2.0
	return get_position_relative_to(slot, local_pos, self)


static func get_position_relative_to(control, pos, relative_to):
	var from_transform = control.get_global_transform()
	var to_transform = relative_to.get_global_transform().inverse()
	pos = from_transform.xform(pos)
	pos = to_transform.xform(pos)
	return pos


func _get_channel_color(c):
	var slot = _output_node.get_slot(c)
	return slot.self_modulate


func _draw():
	_draw_connections()


func _draw_connections():
	for j in range(len(_config.mappings)):
		var mapping = _config.mappings[j]
		
		if mapping == null:
			continue
		
		for k in mapping:
			var v = mapping[k]
			
			var from_index = _channel_to_index[k]
			var to_index = _channel_to_index[v]
			
			var from_pos = _get_input_position(j, from_index)
			var to_pos = _get_output_position(to_index)
			
			_draw_connection(from_pos, to_pos, \
				_get_channel_color(from_index), \
				_get_channel_color(to_index))


func _draw_connection(pos0, pos1, color0, color1):
	var pts = 10
	
	var positions = PoolVector2Array()
	positions.resize(pts + 1)
	
	var colors = PoolColorArray()
	colors.resize(pts + 1)
	
	for i in range(pts):
		var t = i / float(pts)
		
		var color = color0.linear_interpolate(color1, t)
		
		var pos = Vector2( \
			lerp(pos0.x, pos1.x, t), \
			lerp(pos0.y, pos1.y, smoothstep(0.0, 1.0, t)))
		
		positions[i] = pos
		colors[i] = color

	positions[len(positions) - 1] = pos1
	colors[len(colors) - 1] = color1
	
	draw_polyline_colors(positions, colors, 2.0, true)


static func smoothstep(edge0, edge1, x):
	x = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func maxi(a, b):
	return a if a > b else b


static func generate_image(config):
	var inputs = []
	inputs.resize(len(config.input))

	var width = 0
	var height = 0
	
	for i in range(len(config.input)):
		var path = config.input[i]
		if path == null or path == "":
			print("No path in input ", i)
			continue
		var im = Image.new()
		var err = im.load(path)
		if err != OK:
			print("ERROR: can't load image at ", path, ", error ", err)
			return null
		inputs[i] = im

		#print("Image size: ", im.get_width(), "x", im.get_height())
		width = maxi(im.get_width(), width)
		height = maxi(im.get_height(), height)

	if width == 0 or height == 0:
		print("No input image")
		return null
	
	for i in range(len(inputs)):
		var input_image = inputs[i]
		if input_image == null:
			continue
		if input_image.get_width() != width or input_image.get_height() != height:
			print("Input image ", i, " has different size, resizing to ", width, "x", height)
			input_image.resize(width, height, Image.INTERPOLATE_CUBIC)
	
	var output_image = Image.new()
	output_image.create(width, height, false, Image.FORMAT_RGBA8)
	output_image.fill(Color(0, 0, 0, 1))
	
	var mapping_indexes = []
	for mapping in config.mappings:
		
		var indexes = []
		mapping_indexes.append(indexes)
		
		if mapping == null:
			continue
		
		for k in mapping:
			var v = mapping[k]
			indexes.push_back([
				_channel_to_index[k],
				_channel_to_index[v]
			])

	print(mapping_indexes)
	output_image.lock()
	
	for i in range(len(mapping_indexes)):
		var mappings = mapping_indexes[i]
		var input_image = inputs[i]

		if input_image == null:
			continue
		
		input_image.lock()
		
		for mapping in mappings:
			var src = mapping[0]
			var dst = mapping[1]
			
			for y in range(output_image.get_height()):
				for x in range(output_image.get_width()):
					
					var ic = input_image.get_pixel(x, y)
					var oc = output_image.get_pixel(x, y)
					
					oc[dst] = ic[src]
					
					output_image.set_pixel(x, y, oc)
		
		input_image.unlock()
	
	output_image.unlock()
	
	return output_image


func _on_SaveButton_pressed():
	_save_file_dialog.popup_centered_ratio()


func _on_SaveFileDialog_file_selected(path):
	_config.output = path
	var im = generate_image(_config)
	if im == null:
		return
	im.save_png(path)
	#var cfg_path = path + ".pack_config"
	print("Image saved at ", path)
	#hide()


func _on_CancelButton_pressed():
	hide()

