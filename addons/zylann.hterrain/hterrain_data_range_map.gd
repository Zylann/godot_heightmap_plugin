# Low-resolution representation of a heightmap, 
# used to tell minimum and maximum heights within chunks.
class_name HTerrainDataRangeMap

const CHUNK_SIZE = 16

# RGF image where R is min height and G is max height
var _data := Image.new()
var _logger := HT_Logger.get_for(self)


func get_size() -> Vector2i:
	return _data.get_size()


# Return value: (X: min, Y: max)
func get_chunk_range(cpos: Vector2i) -> Vector2:
	var c := _data.get_pixelv(cpos)
	return Vector2(c.r, c.g)


# Not so useful in itself, but GDScript is slow,
# so I needed it to speed up the LOD hack I had to do to take height into account.
# x is min height, y is max height
func get_point_aabb(cell_x: int, cell_y: int) -> Vector2:
	var cx := cell_x / CHUNK_SIZE
	var cy := cell_y / CHUNK_SIZE

	if cx < 0:
		cx = 0
	if cy < 0:
		cy = 0
	if cx >= _data.get_width():
		cx = _data.get_width() - 1
	if cy >= _data.get_height():
		cy = _data.get_height() - 1

	var b := _data.get_pixel(cx, cy)
	return Vector2(b.r, b.g)


func get_aabb() -> AABB:
	# TODO Why subtract 1? I forgot. 
	#      Could it be the off-by-one from power of two used in HTerrainData?
	# TODO Optimize for full region, this is actually quite costy
	return get_region_aabb(Rect2i(Vector2i(), _data.get_size() - Vector2i(1, 1)))


func get_region_aabb(rect_pixels: Rect2i) -> AABB:
	# Get info from cached vertical bounds,
	# which is a lot faster than directly fetching heights from the map.
	# It's not 100% accurate, but enough for culling use case if chunk size is decently chosen.

	var cmin := rect_pixels.position / CHUNK_SIZE
	var cmax := (rect_pixels.end - Vector2i(1,1)) / CHUNK_SIZE + Vector2i(1,1)

	cmin = cmin.clamp(Vector2i(), _data.get_size() - Vector2i(1,1))
	cmax = cmax.clamp(Vector2i(), _data.get_size())

	var min_height := _data.get_pixelv(cmin).r
	var max_height := min_height

	for y in range(cmin.y, cmax.y):
		for x in range(cmin.x, cmax.x):
			var b := _data.get_pixel(x, y)
			min_height = minf(b.r, min_height)
			max_height = maxf(b.g, max_height)

	var aabb := AABB()
	aabb.position = Vector3(rect_pixels.position.x, min_height, rect_pixels.position.y)
	aabb.size = Vector3(rect_pixels.size.x, max_height - min_height, rect_pixels.size.y)

	return aabb


func update(heights: Image) -> void:
	var heights_res := heights.get_size()
	var csize := heights_res / CHUNK_SIZE
	_logger.debug(str("Updating all vertical bounds... (", csize.x, "x", csize.y, " chunks)"))
	_data = Image.create(csize.x, csize.y, false, Image.FORMAT_RGF)
	update_area(heights, Rect2i(0, 0, heights_res.x - 1, heights_res.y - 1))


func update_area(heights: Image, rect_pixels: Rect2i) -> void:
	var cmin := HT_Util.floordiv_vec2i_int(rect_pixels.position, CHUNK_SIZE)
	var cmax := HT_Util.ceildiv_vec2i_int(rect_pixels.end, CHUNK_SIZE)
	
	cmin.x = clampi(cmin.x, 0, _data.get_width() - 1)
	cmin.y = clampi(cmin.y, 0, _data.get_height() - 1)
	cmax.x = clampi(cmax.x, 0, _data.get_width())
	cmax.y = clampi(cmax.y, 0, _data.get_height())

	# Note: chunks in _chunked_vertical_bounds share their edge cells and
	# have an actual size of chunk size + 1.
	var chunk_size_x := CHUNK_SIZE + 1
	var chunk_size_y := CHUNK_SIZE + 1
	
	for y in range(cmin.y, cmax.y):
		var pmin_y := y * CHUNK_SIZE

		for x in range(cmin.x, cmax.x):
			var pmin_x := x * CHUNK_SIZE
			var b := _compute_vertical_bounds_at(
				heights, 
				Rect2i(pmin_x, pmin_y, chunk_size_x, chunk_size_y)
			)
			_data.set_pixel(x, y, Color(b.x, b.y, 0))


func _compute_vertical_bounds_at(heights: Image, rect_pixels: Rect2i) -> Vector2:
	match heights.get_format():
		Image.FORMAT_RF, \
		Image.FORMAT_RH:
			return _get_heights_range_f(heights, rect_pixels)
		Image.FORMAT_RGB8:
			return _get_heights_range_rgb8(heights, rect_pixels)
		_:
			_logger.error(str("Unknown heightmap format ", heights.get_format()))
			return Vector2()


static func _get_heights_range_rgb8(im: Image, rect: Rect2i) -> Vector2:
	assert(im.get_format() == Image.FORMAT_RGB8)
	
	rect = rect.intersection(Rect2i(0, 0, im.get_width(), im.get_height()))
	var min_x := rect.position.x
	var min_y := rect.position.y
	var max_x := min_x + rect.size.x
	var max_y := min_y + rect.size.y
	
	var min_height := HTerrainData.decode_height_from_rgb8_unorm(im.get_pixel(min_x, min_y))
	var max_height := min_height

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			var h := HTerrainData.decode_height_from_rgb8_unorm(im.get_pixel(x, y))
			min_height = minf(h, min_height)
			max_height = maxf(h, max_height)

	return Vector2(min_height, max_height)


static func _get_heights_range_f(im: Image, rect: Rect2i) -> Vector2:
	assert(im.get_format() == Image.FORMAT_RF or im.get_format() == Image.FORMAT_RH)
	
	rect = rect.intersection(Rect2i(0, 0, im.get_width(), im.get_height()))
	var min_x := rect.position.x
	var min_y := rect.position.y
	var max_x := min_x + rect.size.x
	var max_y := min_y + rect.size.y
	
	var min_height := im.get_pixel(min_x, min_y).r
	var max_height := min_height

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			var h := im.get_pixel(x, y).r
			min_height = minf(h, min_height)
			max_height = maxf(h, max_height)

	return Vector2(min_height, max_height)
