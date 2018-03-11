tool
extends Resource

const Grid = preload("grid.gd")
var HTerrain = load("res://addons/zylann.heightmap/hterrain.gd")
const Util = preload("util.gd")

const CHANNEL_HEIGHT = 0
const CHANNEL_NORMAL = 1
const CHANNEL_SPLAT = 2
const CHANNEL_COLOR = 3
const CHANNEL_MASK = 4
const CHANNEL_COUNT = 5

const MAX_RESOLUTION = 4096 + 1
const DEFAULT_RESOLUTION = 256

signal resolution_changed
signal region_changed


class VerticalBounds:
	var minv = 0
	var maxv = 0


export(int) var resolution setget set_resolution, get_resolution


var _resolution = 0
var _textures = []
var _images = []
var _chunked_vertical_bounds = []
var _chunked_vertical_bounds_size = [0, 0]

var _edit_disable_apply_undo = false


func _init():
	_textures.resize(CHANNEL_COUNT)
	_images.resize(CHANNEL_COUNT)


func load_default():
	print("Loading default data")
	set_resolution(DEFAULT_RESOLUTION)
	update_all_normals()


func get_resolution():
	return _resolution


func set_resolution(p_res):
	assert(typeof(p_res) == TYPE_INT)
	
	print("HeightMapData::set_resolution ", p_res)

	if p_res == get_resolution():
		return

	if p_res < HTerrain.CHUNK_SIZE:
		p_res = HTerrain.CHUNK_SIZE

	# Power of two is important for LOD.
	# Also, grid data is off by one,
	# because for an even number of quads you need an odd number of vertices.
	# To prevent size from increasing at every deserialization, remove 1 before applying power of two.
	p_res = Util.next_power_of_two(p_res - 1) + 1

	_resolution = p_res;

	# Resize heights
	if _images[CHANNEL_HEIGHT] == null:
		var im = Image.new()
		im.create(_resolution, _resolution, false, get_channel_format(CHANNEL_HEIGHT))
		_images[CHANNEL_HEIGHT] = im
	else:
		_images[CHANNEL_HEIGHT].resize(_resolution, _resolution)

	# Resize normals
	if _images[CHANNEL_NORMAL] == null:
		var im = Image.new()
		_images[CHANNEL_NORMAL] = im
	
	_images[CHANNEL_NORMAL].create(_resolution, _resolution, false, get_channel_format(CHANNEL_NORMAL))
	update_all_normals()

	# Resize colors
	if _images[CHANNEL_COLOR] == null:
		var im = Image.new()
		im.create(_resolution, _resolution, false, get_channel_format(CHANNEL_COLOR))
		im.fill(Color(1, 1, 1, 1))
		_images[CHANNEL_COLOR] = im
	else:
		_images[CHANNEL_COLOR].resize(_resolution, _resolution)

	# Resize splats
	if _images[CHANNEL_SPLAT] == null:
		var im = Image.new()
		im.create(_resolution, _resolution, false, get_channel_format(CHANNEL_SPLAT))
		# Initialize weights so we can see the default texture
		im.fill(Color8(0, 128, 0, 0))
		_images[CHANNEL_SPLAT] = im
		
	else:
		_images[CHANNEL_SPLAT].resize(_resolution, _resolution)

	# Resize mask
	if _images[CHANNEL_MASK] == null:
		var im = Image.new()
		im.create(_resolution, _resolution, false, get_channel_format(CHANNEL_MASK))
		# Initialize mask so the terrain has no holes by default
		im.fill(Color8(255, 0, 0, 0))
		_images[CHANNEL_MASK] = im
	
	else:
		_images[CHANNEL_SPLAT].resize(_resolution, _resolution)

	var csize_x = p_res / HTerrain.CHUNK_SIZE
	var csize_y = p_res / HTerrain.CHUNK_SIZE
	# TODO Could set `preserve_data` to true, but would require callback to construct new cells
	Grid.resize_grid(_chunked_vertical_bounds, csize_x, csize_y)
	_chunked_vertical_bounds_size = [csize_x, csize_y]
	update_all_vertical_bounds()

	emit_signal("resolution_changed")


static func get_clamped(im, x, y):

	if x < 0:
		x = 0
	elif x >= im.get_width():
		x = im.get_width() - 1

	if y < 0:
		y = 0
	elif y >= im.get_height():
		y = im.get_height() - 1

	return im.get_pixel(x, y)


func get_height_at(x, y):
	# This function is relatively slow due to locking, so don't use it to fetch large areas

	# Height data must be loaded in RAM
	assert(_images[CHANNEL_HEIGHT] != null)

	var im = _images[CHANNEL_HEIGHT]
	im.lock();
	var h = get_clamped(im, x, y).r;
	im.unlock();
	return h;


func get_interpolated_height_at(pos):
	# This function is relatively slow due to locking, so don't use it to fetch large areas

	# Height data must be loaded in RAM
	assert(_images[CHANNEL_HEIGHT] != null)

	# The function takes a Vector3 for convenience so it's easier to use in 3D scripting
	var x0 = int(pos.x)
	var y0 = int(pos.z)

	var xf = pos.x - x0
	var yf = pos.z - y0

	var im = _images[CHANNEL_HEIGHT]
	im.lock()
	var h00 = get_clamped(im, x0, y0).r
	var h10 = get_clamped(im, x0 + 1, y0).r
	var h01 = get_clamped(im, x0, y0 + 1).r
	var h11 = get_clamped(im, x0 + 1, y0 + 1).r
	im.unlock()

	# Bilinear filter
	var h = lerp(lerp(h00, h10, xf), lerp(h01, h11, xf), yf)

	return h;


func update_all_normals():
	update_normals(0, 0, _resolution, _resolution)


func update_normals(min_x, min_y, size_x, size_y):	
	assert(typeof(min_x) == TYPE_INT)
	assert(typeof(min_y) == TYPE_INT)
	assert(typeof(size_x) == TYPE_INT)
	assert(typeof(size_x) == TYPE_INT)
	
	assert(_images[CHANNEL_HEIGHT] != null)
	assert(_images[CHANNEL_NORMAL] != null)

	var heights = _images[CHANNEL_HEIGHT]
	var normals = _images[CHANNEL_NORMAL]

	var max_x = min_x + size_x
	var max_y = min_y + size_y

	var p_min = [min_x, min_y]
	var p_max = [max_x, max_y]
	Util.clamp_min_max_excluded(p_min, p_max, [0, 0], [heights.get_width(), heights.get_height()])
	min_x = p_min[0]
	min_y = p_min[1]
	max_x = p_max[0]
	max_y = p_max[1]

	heights.lock();
	normals.lock();

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			
			var left = get_clamped(heights, x - 1, y).r
			var right = get_clamped(heights, x + 1, y).r
			var fore = get_clamped(heights, x, y + 1).r
			var back = get_clamped(heights, x, y - 1).r

			var n = Vector3(left - right, 2.0, back - fore).normalized()

			normals.set_pixel(x, y, encode_normal(n))
			
	heights.unlock()
	normals.unlock()


func notify_region_change(p_min, p_max, channel):
	
	# TODO Hmm not sure if that belongs here // <-- why this, Me from the past?
	match channel:
		CHANNEL_HEIGHT:
			# TODO Optimization: when drawing very large patches, this might get called too often and would slow down.
			# for better user experience, we could set chunks AABBs to a very large height just while drawing,
			# and set correct AABBs as a background task once done
			var size = [p_max[0] - p_min[0], p_max[1] - p_min[1]]
			update_vertical_bounds(p_min[0], p_min[1], size[0], size[1])

			upload_region(channel, p_min[0], p_min[1], p_max[0], p_max[1])
			upload_region(CHANNEL_NORMAL, p_min[0], p_min[1], p_max[0], p_max[1])

		CHANNEL_NORMAL, \
		CHANNEL_SPLAT, \
		CHANNEL_COLOR, \
		CHANNEL_MASK:
			upload_region(channel, p_min[0], p_min[1], p_max[0], p_max[1])

		_:
			print("Unrecognized channel\n")

	emit_signal("region_changed", p_min[0], p_min[1], p_max[0], p_max[1], channel)


func _edit_set_disable_apply_undo(e):
	_edit_disable_apply_undo = e


func _edit_apply_undo(undo_data):

	if _edit_disable_apply_undo:
		return

	var chunk_positions = undo_data["chunk_positions"]
	var chunk_datas = undo_data["data"]
	var channel = undo_data["channel"]

	# Validate input

	assert(channel >= 0 and channel < CHANNEL_COUNT)
	assert(chunk_positions.size() / 2 == chunk_datas.size())

	assert(chunk_positions.size() % 2 == 0)
	for i in range(len(chunk_positions)):
		var p = chunk_positions[i]
		assert(typeof(p) == TYPE_INT)

	for i in range(len(chunk_datas)):
		var d = chunk_datas[i]
		assert(typeof(d) == TYPE_OBJECT)
		assert(d is Image)

	var regions_changed = []

	# Apply

	for i in range(len(chunk_datas)):
		var cpos_x = chunk_positions[2 * i]
		var cpos_y = chunk_positions[2 * i + 1]

		var min_x = cpos_x * HTerrain.CHUNK_SIZE
		var min_y = cpos_y * HTerrain.CHUNK_SIZE
		var max_x = min_x + 1 * HTerrain.CHUNK_SIZE
		var max_y = min_y + 1 * HTerrain.CHUNK_SIZE

		var data = chunk_datas[i]
		assert(data != null)

		var data_rect = Rect2(0, 0, data.get_width(), data.get_height())

		match channel:

			CHANNEL_HEIGHT:
				assert(_images[channel] != null)
				_images[channel].blit_rect(data, data_rect, Vector2(min_x, min_y))
				# Padding is needed because normals are calculated using neighboring,
				# so a change in height X also requires normals in X-1 and X+1 to be updated
				# TODO HEY, second parameter is a size! FIXIT
				update_normals(min_x - 1, min_y - 1, max_x - min_x + 2, max_y - min_y + 2)

			CHANNEL_SPLAT, \
			CHANNEL_COLOR, \
			CHANNEL_MASK:
				assert(_images[channel] != null)
				_images[channel].blit_rect(data, data_rect, Vector2(min_x, min_y))

			CHANNEL_NORMAL:
				print("This is a calculated channel!, no undo on this one\n")
			_:
				print("Wut? Unsupported undo channel\n");
		
		# Defer this to a second pass, otherwise it causes order-dependent artifacts on the normal map
		regions_changed.append([[min_x, min_y], [max_x, max_y], channel])

	for args in regions_changed:
		# TODO This one is VERY slow because partial texture updates is not supported...
		# so the entire texture gets reuploaded for each chunk being undone
		notify_region_change(args[0], args[1], args[2])


func upload_channel(channel):
	upload_region(channel, 0, 0, _resolution, _resolution)


func upload_region(channel, min_x, min_y, max_x, max_y):

	assert(_images[channel] != null)

	if _textures[channel] == null:
		_textures[channel] = ImageTexture.new()

	var flags = 0;

	if channel == CHANNEL_NORMAL or channel == CHANNEL_COLOR:
		# To allow smooth shading in fragment shader
		flags |= Texture.FLAG_FILTER


	#               ..ooo@@@XXX%%%xx..
	#            .oo@@XXX%x%xxx..     ` .
	#          .o@XX%%xx..               ` .
	#        o@X%..                  ..ooooooo
	#      .@X%x.                 ..o@@^^   ^^@@o
	#    .ooo@@@@@@ooo..      ..o@@^          @X%
	#    o@@^^^     ^^^@@@ooo.oo@@^             %
	#   xzI    -*--      ^^^o^^        --*-     %
	#   @@@o     ooooooo^@@^o^@X^@oooooo     .X%x
	#  I@@@@@@@@@XX%%xx  ( o@o )X%x@ROMBASED@@@X%x
	#  I@@@@XX%%xx  oo@@@@X% @@X%x   ^^^@@@@@@@X%x
	#   @X%xx     o@@@@@@@X% @@XX%%x  )    ^^@X%x
	#    ^   xx o@@@@@@@@Xx  ^ @XX%%x    xxx
	#          o@@^^^ooo I^^ I^o ooo   .  x
	#          oo @^ IX      I   ^X  @^ oo
	#          IX     U  .        V     IX
	#           V     .           .     V
	#
	# TODO Partial update pleaaase! SLOOOOOOOOOOWNESS AHEAD !!
	_textures[channel].create_from_image(_images[channel], flags)
	#print("Channel updated ", channel)


func get_image(channel):
	return _images[channel]


func get_texture(channel):
	if _textures[channel] == null and _images[channel] != null:
		upload_channel(channel)
	return _textures[channel]


func get_region_aabb(origin_in_cells_x, origin_in_cells_y, size_in_cells_x, size_in_cells_y):

	# Get info from cached vertical bounds,
	# which is a lot faster than directly fetching heights from the map.
	# It's not 100% accurate, but enough for culling use case if chunk size is decently chosen.

	var cmin_x = origin_in_cells_x / HTerrain.CHUNK_SIZE
	var cmin_y = origin_in_cells_y / HTerrain.CHUNK_SIZE
	
	var cmax_x = (origin_in_cells_x + size_in_cells_x - 1) / HTerrain.CHUNK_SIZE + 1
	var cmax_y = (origin_in_cells_y + size_in_cells_y - 1) / HTerrain.CHUNK_SIZE + 1

	var min_height = _chunked_vertical_bounds[0][0].minv
	var max_height = min_height
	
	var y = cmin_y
	while y < cmax_y:
		var x = cmin_x
		while x < cmax_x:
			
			var b = _chunked_vertical_bounds[y][x]

			if b.minv < min_height:
				min_height = b.minv

			if b.maxv > max_height:
				max_height = b.maxv
			
			x += 1
		y += 1
	

	var aabb = AABB()
	aabb.position = Vector3(origin_in_cells_x, min_height, origin_in_cells_y)
	aabb.size = Vector3(size_in_cells_x, max_height - min_height, size_in_cells_y)
	
	return aabb


func update_all_vertical_bounds():
	update_vertical_bounds(0, 0, _resolution - 1, _resolution - 1)


func update_vertical_bounds(origin_in_cells_x, origin_in_cells_y, size_in_cells_x, size_in_cells_y):

	var cmin_x = origin_in_cells_x / HTerrain.CHUNK_SIZE
	var cmin_y = origin_in_cells_y / HTerrain.CHUNK_SIZE
	
	var cmax_x = (origin_in_cells_x + size_in_cells_x - 1) / HTerrain.CHUNK_SIZE + 1
	var cmax_y = (origin_in_cells_y + size_in_cells_y - 1) / HTerrain.CHUNK_SIZE + 1

	var cmin = [cmin_x, cmin_y]
	var cmax = [cmax_x, cmax_y]
	Grid.clamp_min_max_excluded(cmin, cmax, _chunked_vertical_bounds_size)
	cmin_x = cmin[0]
	cmin_y = cmin[1]
	cmax_x = cmax[0]
	cmax_y = cmax[1]

	# Note: chunks in _chunked_vertical_bounds share their edge cells and have an actual size of CHUNK_SIZE+1.
	var chunk_size_x = HTerrain.CHUNK_SIZE + 1
	var chunk_size_y = HTerrain.CHUNK_SIZE + 1

	var y = cmin_y
	while y < cmax_y:
		var x = cmin_x
		while x < cmax_x:
			
			var b = _chunked_vertical_bounds[y][x]
			if b == null:
				b = VerticalBounds.new()
				_chunked_vertical_bounds[y][x] = b

			var pmin_x = x * HTerrain.CHUNK_SIZE
			var pmin_y = y * HTerrain.CHUNK_SIZE
			compute_vertical_bounds_at(pmin_x, pmin_y, chunk_size_x, chunk_size_y, b);
			
			x += 1
		y += 1


func compute_vertical_bounds_at(origin_x, origin_y, size_x, size_y, out_b):

	var heights = _images[CHANNEL_HEIGHT]
	assert(heights != null)

	var min_x = origin_x
	var min_y = origin_y
	var max_x = origin_x + size_x
	var max_y = origin_y + size_y

	heights.lock();

	var min_height = heights.get_pixel(min_x, min_y).r
	var max_height = min_height

	var y = min_y
	while y < max_y:
		var x = min_x
		while x < max_x:
			
			var h = heights.get_pixel(x, y).r

			if h < min_height:
				min_height = h
			elif h > max_height:
				max_height = h
			
			x += 1
		y += 1

	heights.unlock()

	out_b.minv = min_height
	out_b.maxv = max_height


static func encode_normal(n):
	return Color(0.5 * (n.x + 1.0), 0.5 * (n.y + 1.0), 0.5 * (n.z + 1.0), 1.0)


static func decode_normal(c):
	return Vector3(2.0 * c.r - 1.0, 2.0 * c.g - 1.0, 2.0 * c.b - 1.0)


static func get_channel_format(channel):
	match channel:
		CHANNEL_HEIGHT:
			return Image.FORMAT_RH
		CHANNEL_NORMAL:
			return Image.FORMAT_RGB8
		CHANNEL_SPLAT:
			return Image.FORMAT_RG8
		CHANNEL_COLOR:
			return Image.FORMAT_RGBA8
		CHANNEL_MASK:
			# TODO A bitmap would be 8 times lighter...
			return Image.FORMAT_R8
	
	print("Unrecognized channel\n")
	return Image.FORMAT_MAX


