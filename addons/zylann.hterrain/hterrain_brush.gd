tool

const HTerrain = preload("./hterrain.gd")
const HTerrainData = preload("./hterrain_data.gd")
const Util = preload("./util/util.gd")
const NativeFactory = preload("./native/factory.gd")
const Logger = preload("./util/logger.gd")

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
const MODE_LEVEL = 8
const MODE_COUNT = 9

# Size of chunks used for undo/redo (so we don't backup the entire terrain everytime)
const EDIT_CHUNK_SIZE = 16

signal shape_changed(shape)

var _radius := 0
var _opacity := 1.0
var _shape : Image = null
var _shape_sum := 0.0
var _shape_source : Image = null
var _shape_size := 0
var _mode := MODE_ADD
var _flatten_height := 0.0
var _texture_index := 0
var _detail_index := 0
var _detail_density := 1.0
var _texture_mode := HTerrain.SHADER_SIMPLE4
var _color := Color(1, 1, 1)
var _mask_flag := false
var _undo_cache := {}
var _image_utils = NativeFactory.get_image_utils()
var _logger = Logger.get_for(self)


func get_mode() -> int:
	return _mode


func set_mode(mode: int):
	assert(mode < MODE_COUNT)
	_mode = mode;
	# Different mode might affect other channels,
	# so we need to clear the current data otherwise it wouldn't make sense
	_undo_cache.clear()


func set_radius(p_radius: int):
	assert(typeof(p_radius) == TYPE_INT)
	if p_radius != _radius:
		assert(p_radius > 0)
		_radius = p_radius
		_update_shape()


func get_radius() -> int:
	return _radius


func get_shape() -> Image:
	return _shape


func set_shape(im: Image):
	_shape_source = im
	_update_shape()


func _update_shape():
	if _shape_source != null:
		_generate_from_image(_shape_source, _radius)
	else:
		_generate_procedural(_radius)


func set_opacity(opacity: float):
	_opacity = clamp(opacity, 0, 1)


func get_opacity() -> float:
	return _opacity


func set_flatten_height(flatten_height: float):
	_flatten_height = flatten_height


func get_flatten_height() -> float:
	return _flatten_height


func set_texture_index(tid: int):
	assert(tid >= 0)
	var slot_count = HTerrain.get_ground_texture_slot_count_for_shader(_texture_mode, _logger)
	assert(tid < slot_count)
	_texture_index = tid


func get_texture_index() -> int:
	return _texture_index


func set_detail_index(index: int):
	assert(index >= 0)
	_detail_index = index


# func get_detail_index():
# 	return _detail_index


func get_detail_density() -> float:
	return _detail_density


func set_detail_density(v: float):
	_detail_density = clamp(v, 0, 1)


func set_color(c: Color):
	# Color might be useful for custom shading
	_color = c


func get_color() -> Color:
	return _color


func get_mask_flag() -> bool:
	return _mask_flag


func set_mask_flag(v: bool):
	assert(typeof(v) == TYPE_BOOL)
	_mask_flag = v


func _generate_procedural(radius: int):
	assert(typeof(radius) == TYPE_INT)
	assert(radius > 0)
	var size := 2 * radius
	_shape = Image.new()
	_shape.create(size, size, 0, Image.FORMAT_RF)
	_shape_size = size
	_shape_sum = _image_utils.generate_gaussian_brush(_shape)
	emit_signal("shape_changed", _shape)


func _generate_from_image(im: Image, radius: int):
	assert(typeof(radius) == TYPE_INT)
	assert(radius > 0)
	assert(im.get_width() == im.get_height())
	var size := 2 * radius
	im = im.duplicate()
	im.convert(Image.FORMAT_RF)
	im.resize(size, size)
	_shape = im
	_shape_size = size
	_shape_sum = _image_utils.get_red_sum(im, Rect2(0, 0, im.get_width(), im.get_height()))
	emit_signal("shape_changed", _shape)


static func _get_mode_channel(mode: int) -> int:
	assert(mode >= 0 and mode < MODE_COUNT)
	match mode:
		MODE_ADD, \
		MODE_SUBTRACT, \
		MODE_SMOOTH, \
		MODE_LEVEL, \
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

	return HTerrainData.CHANNEL_COUNT # Error


func paint(terrain: HTerrain, cell_pos_x: int, cell_pos_y: int, override_mode: int):
	#var time_before = OS.get_ticks_msec()

	assert(terrain.get_data() != null)
	var data = terrain.get_data()
	assert(not data.is_locked())

	var delta := _opacity * 1.0 / 60.0
	var mode := _mode

	if override_mode != -1:
		assert(override_mode >= 0 or override_mode < MODE_COUNT)
		mode = override_mode

	var origin_x := cell_pos_x - _shape_size / 2
	var origin_y := cell_pos_y - _shape_size / 2

	terrain.set_area_dirty(origin_x, origin_y, _shape_size, _shape_size)
	var map_index := 0

	# When using sculpting tools, make it dependent on brush size
	var raise_strength := 10.0 + 2.0 * float(_shape_size)

	match mode:
		MODE_ADD:
			_paint_height(data, origin_x, origin_y, raise_strength * delta)

		MODE_SUBTRACT:
			_paint_height(data, origin_x, origin_y, -raise_strength * delta)

		MODE_SMOOTH:
			_smooth_height(data, origin_x, origin_y, 60.0 * delta)

		MODE_LEVEL:
			_level_height(data, origin_x, origin_y, 10.0 * delta)

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
	#_logger.debug("Time elapsed painting: ", time_elapsed, "ms")


static func _is_valid_pos(pos_x: int, pos_y: int, im: Image) -> bool:
	return not (pos_x < 0 or pos_y < 0 or pos_x >= im.get_width() or pos_y >= im.get_height())


func _backup_for_undo(im: Image, undo_cache: Dictionary, 
	rect_origin_x: int, rect_origin_y: int, rect_size_x: int, rect_size_y: int):

	# Backup cells before they get changed,
	# using chunks so that we don't save the entire grid everytime.
	# This function won't do anything if all concerned chunks got backupped already.

	var cmin_x := rect_origin_x / EDIT_CHUNK_SIZE
	var cmin_y := rect_origin_y / EDIT_CHUNK_SIZE
	var cmax_x := (rect_origin_x + rect_size_x - 1) / EDIT_CHUNK_SIZE + 1
	var cmax_y := (rect_origin_y + rect_size_y - 1) / EDIT_CHUNK_SIZE + 1

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

				# Note: this error check isn't working because data grids are 
				# intentionally off-by-one
				#if(invalid_min ^ invalid_max)
				#	_logger.error("Wut? Grid might not be multiple of chunk size!");

				continue

			var sub_image = im.get_rect(Rect2(min_x, min_y, max_x - min_x, max_y - min_y))
			undo_cache[k] = sub_image


func _paint_height(data: HTerrainData, origin_x: int, origin_y: int, speed: float):
	var im := data.get_image(HTerrainData.CHANNEL_HEIGHT)
	assert(im != null)
	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)
	_image_utils.add_red_brush(im, _shape, Vector2(origin_x, origin_y), speed * _opacity)


func _smooth_height(data: HTerrainData, origin_x: int, origin_y: int, speed: float):
	var im := data.get_image(HTerrainData.CHANNEL_HEIGHT)
	assert(im != null)
	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)
	_image_utils.blur_red_brush(
		im, _shape, Vector2(origin_x, origin_y), speed * _opacity)


func _level_height(data: HTerrainData, origin_x: int, origin_y: int, speed: float):
	var im := data.get_image(HTerrainData.CHANNEL_HEIGHT)
	assert(im != null)
	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)
	# Perform sum at full opacity, we'll use it for the next operation
	var sum = _image_utils.get_red_sum_weighted(im, _shape, Vector2(origin_x, origin_y), 1.0)
	var target_value = sum / _shape_sum
	_image_utils.lerp_channel_brush(
		im, _shape, Vector2(origin_x, origin_y), speed * _opacity, target_value, 0)


func _flatten(data: HTerrainData, origin_x: int, origin_y: int):
	var im = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	assert(im != null)
	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)
	_image_utils.lerp_channel_brush(
		im, _shape, Vector2(origin_x, origin_y), 1.0, _flatten_height, 0)


func _paint_splat(data: HTerrainData, origin_x: int, origin_y: int):
	var im := data.get_image(HTerrainData.CHANNEL_SPLAT)
	assert(im != null)

	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)

	if _texture_mode == HTerrain.SHADER_SIMPLE4:
		var target_color = Color(0, 0, 0, 0)
		target_color[_texture_index] = 1.0
		_image_utils.lerp_color_brush(
			im, _shape, Vector2(origin_x, origin_y), _opacity, target_color)

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
		_logger.error("Unknown texture mode {0}".format([_texture_mode]))


func _paint_color(data: HTerrainData, origin_x: int, origin_y: int):
	var im := data.get_image(HTerrainData.CHANNEL_COLOR)
	assert(im != null)
	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)
	_image_utils.lerp_color_brush(
		im, _shape, Vector2(origin_x, origin_y), _opacity, _color)


func _paint_detail(data: HTerrainData, origin_x: int, origin_y: int):
	var im := data.get_image(HTerrainData.CHANNEL_DETAIL, _detail_index)
	assert(im != null)
	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size)
	var col := Color(_detail_density, _detail_density, _detail_density)
	# Need to use RGB because detail layers use the L8 format.
	# If we used only R, get_pixel() still converts RGB into V (which is max(R, G, B))
	_image_utils.lerp_color_brush(
		im, _shape, Vector2(origin_x, origin_y), _opacity, col)


func _paint_mask(data: HTerrainData, origin_x: int, origin_y: int):
	var im := data.get_image(HTerrainData.CHANNEL_COLOR)
	assert(im != null)
	_backup_for_undo(im, _undo_cache, origin_x, origin_y, _shape_size, _shape_size);
	var mask_value := 1.0 if _mask_flag else 0.0
	_image_utils.lerp_channel_brush(
		im, _shape, Vector2(origin_x, origin_y), 1.0, mask_value, 3)


static func _fetch_redo_chunks(im: Image, keys: Array) -> Array:
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


func _edit_pop_undo_redo_data(heightmap_data: HTerrainData) -> Dictionary:
	# TODO If possible, use a custom Reference class to store this data into the UndoRedo API,
	# but WITHOUT exposing it to scripts (so we won't need the following conversions!)

	var chunk_positions_keys := _undo_cache.keys()

	var channel := _get_mode_channel(_mode)
	assert(channel != HTerrainData.CHANNEL_COUNT)

	var im := heightmap_data.get_image(channel)
	assert(im != null)

	var redo_data := _fetch_redo_chunks(im, chunk_positions_keys)

	# Convert chunk positions to flat int array
	var undo_data := []
	var chunk_positions := PoolIntArray()
	chunk_positions.resize(chunk_positions_keys.size() * 2)

	var i := 0
	for key in chunk_positions_keys:
		var cpos = Util.decode_v2i(key)
		chunk_positions[i] = cpos[0]
		chunk_positions[i + 1] = cpos[1]
		i += 2
		# Also gather pre-cached data for undo, in the same order
		undo_data.append(_undo_cache[key])

	var data := {
		"undo": undo_data,
		"redo": redo_data,
		"chunk_positions": chunk_positions,
		"channel": channel,
		"index": 0,
		"chunk_size": EDIT_CHUNK_SIZE
	}

	_undo_cache.clear()
	return data
