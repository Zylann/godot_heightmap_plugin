tool

const HTerrain = preload("hterrain.gd")
const HTerrainData = preload("hterrain_data.gd")
const Util = preload("util/util.gd")

# TODO Rename MODE_RAISE
const MODE_ADD = 0
# TODO Rename MODE_LOWER
const MODE_SUBTRACT = 1
const MODE_SMOOTH = 2
const MODE_FLATTEN = 3
const MODE_SPLAT = 4
const MODE_COLOR = 5
const MODE_MASK = 6
const MODE_DETAIL = 7
const MODE_COUNT = 8

# Size of chunks used for undo/redo (so we don't backup the entire terrain everytime)
const EDIT_CHUNK_SIZE = 16

signal shape_changed(shape)

var _radius = 0
var _opacity = 1.0
var _shape = null # Image
var _shape_sum = 0.0
var _shape_source = null
var _shape_size = 0
var _mode = MODE_ADD
var _flatten_height = 0.0
var _texture_index = 0
var _detail_index = 0
var _detail_density = 1.0
var _texture_mode = HTerrain.SHADER_SIMPLE4
var _color = Color(1, 1, 1)
var _mask_flag = false
var _undo_cache = {}


func get_mode():
	return _mode


func set_mode(mode):
	assert(mode < MODE_COUNT)
	_mode = mode;
	# Different mode might affect other channels,
	# so we need to clear the current data otherwise it wouldn't make sense
	_undo_cache.clear()


func set_radius(p_radius):
	assert(typeof(p_radius) == TYPE_INT)
	if p_radius != _radius:
		assert(p_radius > 0)
		_radius = p_radius
		_update_shape()


func get_radius():
	return _radius


func get_shape():
	return _shape


func set_shape(im):
	_shape_source = im
	_update_shape()


func _update_shape():
	if _shape_source != null:
		_generate_from_image(_shape_source, _radius)
	else:
		_generate_procedural(_radius)


func set_opacity(opacity):
	_opacity = clamp(opacity, 0, 1)


func get_opacity():
	return _opacity


func set_flatten_height(flatten_height):
	_flatten_height = flatten_height


func get_flatten_height():
	return _flatten_height


func set_texture_index(tid):
	assert(tid >= 0)
	var slot_count = HTerrain.get_ground_texture_slot_count_for_shader(_texture_mode)
	assert(tid < slot_count)
	_texture_index = tid


func get_texture_index():
	return _texture_index


func set_detail_index(index):
	assert(index >= 0)
	_detail_index = index


# func get_detail_index():
# 	return _detail_index


func get_detail_density():
	return _detail_density


func set_detail_density(v):
	_detail_density = clamp(v, 0, 1)


func set_color(c):
	# Color might be useful for custom shading
	_color = c


func get_color():
	return _color


func get_mask_flag():
	return _mask_flag


func set_mask_flag(v):
	assert(typeof(v) == TYPE_BOOL)
	_mask_flag = v


func _generate_procedural(radius):
	assert(typeof(radius) == TYPE_INT)
	assert(radius > 0)

	var size = 2 * radius

	_shape = Image.new()
	_shape.create(size, size, 0, Image.FORMAT_RF)
	_shape_size = size

	_shape_sum = 0.0;

	_shape.lock()

	for y in range(-radius, radius):
		for x in range(-radius, radius):

			var d = Vector2(x, y).distance_to(Vector2(0, 0)) / float(radius)
			var v = 1.0 - d * d * d
			if v > 1.0:
				v = 1.0
			if v < 0.0:
				v = 0.0

			_shape.set_pixel(x + radius, y + radius, Color(v, v, v))
			_shape_sum += v;

	_shape.unlock()

	emit_signal("shape_changed", _shape)


func _generate_from_image(im, radius):
	assert(typeof(radius) == TYPE_INT)
	assert(radius > 0)
	assert(im.get_width() == im.get_height())

	var size = 2 * radius

	im = im.duplicate()
	im.convert(Image.FORMAT_RF)
	im.resize(size, size)
	_shape = im
	_shape_size = size

	_shape.lock()

	var sum = 0.0
	for y in _shape.get_height():
		for x in _shape.get_width():
			sum += _shape.get_pixel(x, y).r

	_shape.unlock()

	_shape_sum = sum
	emit_signal("shape_changed", _shape)


static func _get_mode_channel(mode):
	match mode:
		MODE_ADD, \
		MODE_SUBTRACT, \
		MODE_SMOOTH, \
		MODE_FLATTEN:
			return HTerrainData.CHANNEL_HEIGHT
		MODE_COLOR:
			return HTerrainData.CHANNEL_COLOR
		MODE_SPLAT:
			return HTerrainData.CHANNEL_SPLAT
		MODE_MASK:
			return HTerrainData.CHANNEL_COLOR
		MODE_DETAIL:
			return HTerrainData.CHANNEL_DETAIL
		_:
			print("This mode has no channel")

	return HTerrainData.CHANNEL_COUNT # Error


func paint(height_map, cell_pos_x, cell_pos_y, override_mode):
	#var time_before = OS.get_ticks_msec()

	assert(height_map.get_data() != null)
	var data = height_map.get_data()
	assert(not data.is_locked())

	var delta = _opacity * 1.0 / 60.0
	var mode = _mode

	if override_mode != -1:
		assert(override_mode >= 0 or override_mode < MODE_COUNT)
		mode = override_mode

	var origin_x = cell_pos_x - _shape_size / 2
	var origin_y = cell_pos_y - _shape_size / 2

	height_map.set_area_dirty(origin_x, origin_y, _shape_size, _shape_size)
	var map_index = 0

	# When using sculpting tools, make it dependent on brush size
	var raise_strength = 10.0 + 2.0 * float(_shape_size)

	match mode:

		MODE_ADD:
			_paint_height(data, origin_x, origin_y, raise_strength * delta)

		MODE_SUBTRACT:
			_paint_height(data, origin_x, origin_y, -raise_strength * delta)

		MODE_SMOOTH:
			_smooth_height(data, origin_x, origin_y, 10.0 * delta)

		MODE_FLATTEN:
			_flatten(data, origin_x, origin_y)

		MODE_SPLAT:
			_paint_splat(data, origin_x, origin_y)

		MODE_COLOR:
			_paint_color(data, origin_x, origin_y)

		MODE_MASK:
			_paint_mask(data, origin_x, origin_y)

		MODE_DETAIL:
			_paint_detail(data, origin_x, origin_y)
			map_index = _detail_index

	data.notify_region_change( \
		Rect2(origin_x, origin_y, _shape_size, _shape_size), \
		_get_mode_channel(mode), map_index)

	#var time_elapsed = OS.get_ticks_msec() - time_before
	#print("Time elapsed painting: ", time_elapsed, "ms")


# TODO Erk!
static func _foreach_xy(op, data, origin_x, origin_y, speed, opacity, shape):

	var shape_size = shape.get_width()
	assert(shape.get_width() == shape.get_height())

	var s = opacity * speed

	var min_x = origin_x
	var min_y = origin_y
	var max_x = min_x + shape_size
	var max_y = min_y + shape_size
	var min_noclamp_x = min_x
	var min_noclamp_y = min_y

	min_x = Util.clamp_int(min_x, 0, data.get_resolution())
	min_y = Util.clamp_int(min_y, 0, data.get_resolution())
	max_x = Util.clamp_int(max_x, 0, data.get_resolution())
	max_y = Util.clamp_int(max_y, 0, data.get_resolution())

	shape.lock()

	for y in range(min_y, max_y):
		var py = y - min_noclamp_y

		for x in range(min_x, max_x):
			var px = x - min_noclamp_x

			var shape_value = shape.get_pixel(px, py).r
			op.exec(data, x, y, s * shape_value)

	shape.unlock()


class OperatorAdd:
	var _im = null
	func _init(im):
		_im = im
	func exec(data, pos_x, pos_y, v):
		var c = _im.get_pixel(pos_x, pos_y)
		c.r += v
		_im.set_pixel(pos_x, pos_y, c)


class OperatorSum:
	var sum = 0.0
	var _im = null
	func _init(im):
		_im = im
	func exec(data, pos_x, pos_y, v):
		sum += _im.get_pixel(pos_x, pos_y).r * v


class OperatorLerp:

	var target = 0.0
	var _im = null

	func _init(p_target, im):
		target = p_target
		_im = im

	func exec(data, pos_x, pos_y, v):
		var c = _im.get_pixel(pos_x, pos_y)
		c.r = lerp(c.r, target, v)
		_im.set_pixel(pos_x, pos_y, c)


class OperatorLerpColor:

	var target = Color()
	var _im = null

	func _init(p_target, im):
		target = p_target
		_im = im

	func exec(data, pos_x, pos_y, v):
		var c = _im.get_pixel(pos_x, pos_y)
		c = c.linear_interpolate(target, v)
		_im.set_pixel(pos_x, pos_y, c)


static func _is_valid_pos(pos_x, pos_y, im):
	return not (pos_x < 0 or pos_y < 0 or pos_x >= im.get_width() or pos_y >= im.get_height())


func _backup_for_undo(im, undo_cache, rect_origin_x, rect_origin_y, rect_size_x, rect_size_y):

	# Backup cells before they get changed,
	# using chunks so that we don't save the entire grid everytime.
	# This function won't do anything if all concerned chunks got backupped already.

	var cmin_x = rect_origin_x / EDIT_CHUNK_SIZE
	var cmin_y = rect_origin_y / EDIT_CHUNK_SIZE
	var cmax_x = (rect_origin_x + rect_size_x - 1) / EDIT_CHUNK_SIZE + 1
	var cmax_y = (rect_origin_y + rect_size_y - 1) / EDIT_CHUNK_SIZE + 1

	for cpos_y in range(cmin_y, cmax_y):
		var min_y = cpos_y * EDIT_CHUNK_SIZE
		var max_y = min_y + EDIT_CHUNK_SIZE

		for cpos_x in range(cmin_x, cmax_x):

			var k = Util.encode_v2i(cpos_x, cpos_y)
			if undo_cache.has(k):
				# Already backupped
				continue

			var min_x = cpos_x * EDIT_CHUNK_SIZE
			var max_x = min_x + EDIT_CHUNK_SIZE

			var invalid_min = not _is_valid_pos(min_x, min_y, im)
			var invalid_max = not _is_valid_pos(max_x - 1, max_y - 1, im) # Note: max is excluded

			if invalid_min or invalid_max:
				# Out of bounds

				# Note: this error check isn't working because data grids are intentionally off-by-one
				#if(invalid_min ^ invalid_max)
				#	print_line("Wut? Grid might not be multiple of chunk size!");

				continue

			var sub_image = im.get_rect(Rect2(min_x, min_y, max_x - min_x, max_y - min_y))
			undo_cache[k] = sub_image



func _paint_height(data, origin_x, origin_y, speed):
	#var time_before = OS.get_ticks_msec()

	var im = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	assert(im != null)

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)
	#print("Backup time: ", (OS.get_ticks_msec() - time_before))
	#time_before = OS.get_ticks_msec()

	im.lock()
	var op = OperatorAdd.new(im)
	_foreach_xy(op, data, origin_x, origin_y, speed, _opacity, _shape)
	im.unlock()
	#print("Raster time: ", (OS.get_ticks_msec() - time_before))
	#time_before = OS.get_ticks_msec()


func _smooth_height(data, origin_x, origin_y, speed):

	var im = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	assert(im != null)

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)

	im.lock()

	var sum_op = OperatorSum.new(im)
	# Perform sum at full opacity, we'll use it for the next operation
	_foreach_xy(sum_op, data, origin_x, origin_y, 1.0, 1.0, _shape)
	var target_value = sum_op.sum / float(_shape_sum)

	var lerp_op = OperatorLerp.new(target_value, im)
	_foreach_xy(lerp_op, data, origin_x, origin_y, speed, _opacity, _shape)

	im.unlock()


func _flatten(data, origin_x, origin_y):

	var im = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	assert(im != null)

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)

	im.lock()
	var op = OperatorLerp.new(_flatten_height, im)
	_foreach_xy(op, data, origin_x, origin_y, 1, 1, _shape)
	im.unlock()


func _paint_splat(data, origin_x, origin_y):

	var im = data.get_image(HTerrainData.CHANNEL_SPLAT)
	assert(im != null)

	var shape_size = _shape_size

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, shape_size, shape_size)

	var min_x = origin_x
	var min_y = origin_y
	var max_x = min_x + shape_size
	var max_y = min_y + shape_size
	var min_noclamp_x = min_x
	var min_noclamp_y = min_y

	min_x = Util.clamp_int(min_x, 0, data.get_resolution())
	min_y = Util.clamp_int(min_y, 0, data.get_resolution())
	max_x = Util.clamp_int(max_x, 0, data.get_resolution())
	max_y = Util.clamp_int(max_y, 0, data.get_resolution())

	im.lock()

	if _texture_mode == HTerrain.SHADER_SIMPLE4:

		var target_color = Color(0, 0, 0, 0)
		target_color[_texture_index] = 1.0

		_shape.lock()

		for y in range(min_y, max_y):
			var py = y - min_noclamp_y

			for x in range(min_x, max_x):
				var px = x - min_noclamp_x

				var shape_value = _shape.get_pixel(px, py).r

				var c = im.get_pixel(x, y)
				c = c.linear_interpolate(target_color, shape_value * _opacity)
				im.set_pixel(x, y, c)

		_shape.unlock()

#	elif _texture_mode == HTerrain.SHADER_ARRAY:
#		var shape_threshold = 0.1
#
#		for y in range(min_y, max_y):
#			var py = y - min_noclamp_y
#
#			for x in range(min_x, max_x):
#				var px = x - min_noclamp_x
#
#				var shape_value = _shape[py][px]
#
#				if shape_value > shape_threshold:
#					# TODO Improve weight blending, it looks meh
#					var c = Color()
#					c.r = float(_texture_index) / 256.0
#					c.g = clamp(_opacity, 0.0, 1.0)
#					im.set_pixel(x, y, c)
	else:
		printerr("Unknown texture mode ", _texture_mode)

	im.unlock()


func _paint_color(data, origin_x, origin_y):

	var im = data.get_image(HTerrainData.CHANNEL_COLOR)
	assert(im != null)

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)

	im.lock()
	var op = OperatorLerpColor.new(_color, im)
	_foreach_xy(op, data, origin_x, origin_y, 1, _opacity, _shape)
	im.unlock()


func _paint_detail(data, origin_x, origin_y):

	var im = data.get_image(HTerrainData.CHANNEL_DETAIL, _detail_index)
	assert(im != null)

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)

	im.lock()
	var op = OperatorLerpColor.new(Color(_detail_density, _detail_density, _detail_density, 1.0), im)
	_foreach_xy(op, data, origin_x, origin_y, 1, _opacity, _shape)
	im.unlock()


func _paint_mask(data, origin_x, origin_y):

	var im = data.get_image(HTerrainData.CHANNEL_COLOR)
	assert(im != null)

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size);

	var shape_size = _shape_size

	var min_x = origin_x
	var min_y = origin_y
	var max_x = min_x + shape_size
	var max_y = min_y + shape_size
	var min_noclamp_x = min_x
	var min_noclamp_y = min_y

	min_x = Util.clamp_int(min_x, 0, data.get_resolution())
	min_y = Util.clamp_int(min_y, 0, data.get_resolution())
	max_x = Util.clamp_int(max_x, 0, data.get_resolution())
	max_y = Util.clamp_int(max_y, 0, data.get_resolution())

	var mask_value = 1.0 if _mask_flag else 0.0

	im.lock()
	_shape.lock()

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):

			var px = x - min_noclamp_x
			var py = y - min_noclamp_y

			var shape_value = _shape.get_pixel(px, py).r

			var c = im.get_pixel(x, y)
			c.a = lerp(c.a, mask_value, shape_value)
			im.set_pixel(x, y, c)

	_shape.unlock()
	im.unlock()


static func _fetch_redo_chunks(im, keys):
	var output = []
	for key in keys:
		var cpos = Util.decode_v2i(key)
		var min_x = cpos[0] * EDIT_CHUNK_SIZE
		var min_y = cpos[1] * EDIT_CHUNK_SIZE
		var max_x = min_x + 1 * EDIT_CHUNK_SIZE
		var max_y = min_y + 1 * EDIT_CHUNK_SIZE
		var sub_image = im.get_rect(Rect2(min_x, min_y, max_x - min_x, max_y - min_y))
		output.append(sub_image)
	return output


func _edit_pop_undo_redo_data(heightmap_data):

	# TODO If possible, use a custom Reference class to store this data into the UndoRedo API,
	# but WITHOUT exposing it to scripts (so we won't need the following conversions!)

	var chunk_positions_keys = _undo_cache.keys()

	var channel = _get_mode_channel(_mode)
	assert(channel != HTerrainData.CHANNEL_COUNT)

	var im = heightmap_data.get_image(channel)
	assert(im != null)

	var redo_data = _fetch_redo_chunks(im, chunk_positions_keys)

	# Convert chunk positions to flat int array
	var undo_data = []
	var chunk_positions = PoolIntArray()
	chunk_positions.resize(chunk_positions_keys.size() * 2)

	var i = 0
	for key in chunk_positions_keys:
		var cpos = Util.decode_v2i(key)
		chunk_positions[i] = cpos[0]
		chunk_positions[i + 1] = cpos[1]
		i += 2
		# Also gather pre-cached data for undo, in the same order
		undo_data.append(_undo_cache[key])

	var data = {
		"undo": undo_data,
		"redo": redo_data,
		"chunk_positions": chunk_positions,
		"channel": channel,
		"index": 0,
		"chunk_size": EDIT_CHUNK_SIZE
	}

	_undo_cache.clear()

	return data
