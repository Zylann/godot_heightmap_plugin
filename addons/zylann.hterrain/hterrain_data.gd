tool
extends Resource

const Grid = preload("grid.gd")
var HTerrain = load("res://addons/zylann.hterrain/hterrain.gd")
const Util = preload("util.gd")

# TODO Rename "CHANNEL" to "MAP", makes more sense and less confusing with RGBA channels
const CHANNEL_HEIGHT = 0
const CHANNEL_NORMAL = 1
const CHANNEL_SPLAT = 2
const CHANNEL_COLOR = 3
const CHANNEL_COUNT = 4

const MAX_RESOLUTION = 4096 + 1
const DEFAULT_RESOLUTION = 256
# TODO Have vertical bounds chunk size
# TODO Have undo chunk size

const DATA_FOLDER_SUFFIX = ".hterrain_data"


signal resolution_changed
signal region_changed(x, y, w, h, channel)
# TODO Instead of message, send a state enum and a var (for translation and code semantic)
signal progress_notified(info) # { "progress": real, "message": string, "finished": bool }

signal _internal_process


class VerticalBounds:
	var minv = 0
	var maxv = 0


var _resolution = 0
var _textures = []
var _images = []
var _chunked_vertical_bounds = []
var _chunked_vertical_bounds_size = [0, 0]
var _locked = false
var _progress_complete = true

var _edit_disable_apply_undo = false


func _init():
	_textures.resize(CHANNEL_COUNT)
	_images.resize(CHANNEL_COUNT)


func _get_property_list():
	var props = [
		{
			# TODO Only allow predefined resolutions, because that's currently the case
			"name": "resolution",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_EDITOR
		}
	]
	return props


func _get(key):
	match key:
		"resolution":
			return get_resolution()


func _set(key, v):
	match key:
		# TODO Should we even allow this to be set if there is existing data which isn't loaded yet?
		"resolution":
			# Setting resolution has only effect when set from editor or a script.
			# It's not part of the saved resource variables because it is
			# deduced from the height texture,
			# and resizing on load wouldn't make sense.
			assert(typeof(v) == TYPE_INT)
			set_resolution(v)


func _edit_load_default():
	print("Loading default data")
	set_resolution(DEFAULT_RESOLUTION)
	_update_all_normals()


func is_locked():
	return _locked


func get_resolution():
	return _resolution


func set_resolution(p_res):
	set_resolution2(p_res, true)


func set_resolution2(p_res, update_normals):
	assert(typeof(p_res) == TYPE_INT)
	assert(typeof(update_normals) == TYPE_BOOL)
	
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
	print("Resizing heights...")
	if _images[CHANNEL_HEIGHT] == null:
		var im = Image.new()
		im.create(_resolution, _resolution, false, _get_channel_format(CHANNEL_HEIGHT))
		_images[CHANNEL_HEIGHT] = im
	else:
		_images[CHANNEL_HEIGHT].resize(_resolution, _resolution)

	# Resize normals
	print("Resizing normals...")
	if _images[CHANNEL_NORMAL] == null:
		var im = Image.new()
		_images[CHANNEL_NORMAL] = im
	
	_images[CHANNEL_NORMAL].create(_resolution, _resolution, false, _get_channel_format(CHANNEL_NORMAL))
	if update_normals:
		_update_all_normals()

	# Resize colors
	print("Resizing colors...")
	if _images[CHANNEL_COLOR] == null:
		var im = Image.new()
		im.create(_resolution, _resolution, false, _get_channel_format(CHANNEL_COLOR))
		im.fill(Color(1, 1, 1, 1))
		_images[CHANNEL_COLOR] = im
	else:
		_images[CHANNEL_COLOR].resize(_resolution, _resolution)

	# Resize splats
	print("Resizing splats...")
	if _images[CHANNEL_SPLAT] == null:
		var im = Image.new()
		im.create(_resolution, _resolution, false, _get_channel_format(CHANNEL_SPLAT))
		im.fill(Color(1, 0, 0, 0))
		_images[CHANNEL_SPLAT] = im
		
	else:
		_images[CHANNEL_SPLAT].resize(_resolution, _resolution)

	_update_all_vertical_bounds()

	emit_signal("resolution_changed")


static func _get_clamped(im, x, y):

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
	var h = _get_clamped(im, x, y).r;
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
	var h00 = _get_clamped(im, x0, y0).r
	var h10 = _get_clamped(im, x0 + 1, y0).r
	var h01 = _get_clamped(im, x0, y0 + 1).r
	var h11 = _get_clamped(im, x0 + 1, y0 + 1).r
	im.unlock()

	# Bilinear filter
	var h = lerp(lerp(h00, h10, xf), lerp(h01, h11, xf), yf)

	return h;


func get_heights_region(x0, y0, w, h):
	assert(_images[CHANNEL_HEIGHT] != null)
	
	var im = _images[CHANNEL_HEIGHT]
	
	var min_x = Util.clampi(x0, 0, im.get_width())
	var min_y = Util.clampi(y0, 0, im.get_height())
	var max_x = Util.clampi(x0 + w, 0, im.get_width() + 1)
	var max_y = Util.clampi(y0 + h, 0, im.get_height() + 1)
	
	var heights = PoolRealArray()
	
	var area = (max_x - min_x) * (max_y - min_y)
	if area == 0:
		print("Empty heights region!")
		return heights
	
	heights.resize(area)
	
	im.lock()
	
	var i = 0
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			heights[i] = im.get_pixel(x, y).r
			i += 1
	
	im.unlock()
	
	return heights


func get_all_heights():
	return get_heights_region(0, 0, _resolution, _resolution)



# TODO Have an async version that uses the GPU
func _update_all_normals():
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
			
			var left = _get_clamped(heights, x - 1, y).r
			var right = _get_clamped(heights, x + 1, y).r
			var fore = _get_clamped(heights, x, y + 1).r
			var back = _get_clamped(heights, x, y - 1).r

			var n = Vector3(left - right, 2.0, back - fore).normalized()

			normals.set_pixel(x, y, _encode_normal(n))
			
	heights.unlock()
	normals.unlock()


func notify_region_change(p_min, p_max, channel):
	
	# TODO Hmm not sure if that belongs here // <-- why this, Me from the past?
	match channel:
		CHANNEL_HEIGHT:
			# TODO when drawing very large patches, this might get called too often and would slow down.
			# for better user experience, we could set chunks AABBs to a very large height just while drawing,
			# and set correct AABBs as a background task once done
			var size = [p_max[0] - p_min[0], p_max[1] - p_min[1]]
			_update_vertical_bounds(p_min[0], p_min[1], size[0], size[1])

			_upload_region(channel, p_min[0], p_min[1], p_max[0], p_max[1])
			_upload_region(CHANNEL_NORMAL, p_min[0], p_min[1], p_max[0], p_max[1])

		CHANNEL_NORMAL, \
		CHANNEL_SPLAT, \
		CHANNEL_COLOR:
			_upload_region(channel, p_min[0], p_min[1], p_max[0], p_max[1])

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
				update_normals(min_x - 1, min_y - 1, max_x - min_x + 2, max_y - min_y + 2)

			CHANNEL_SPLAT, \
			CHANNEL_COLOR:
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


func _upload_channel(channel):
	_upload_region(channel, 0, 0, _resolution, _resolution)


func _upload_region(channel, min_x, min_y, max_x, max_y):

	assert(_images[channel] != null)

	if _textures[channel] == null or not (_textures[channel] is ImageTexture):
		_textures[channel] = ImageTexture.new()

	var flags = 0;

	if channel == CHANNEL_NORMAL or channel == CHANNEL_COLOR or channel == CHANNEL_SPLAT:
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
		_upload_channel(channel)
	return _textures[channel]


func get_aabb():
	# TODO Why subtract 1? I forgot
	return get_region_aabb(0, 0, _resolution - 1, _resolution - 1)


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
	
	for y in range(cmin_y, cmax_y):
		for x in range(cmin_x, cmax_x):
			
			var b = _chunked_vertical_bounds[y][x]

			if b.minv < min_height:
				min_height = b.minv

			if b.maxv > max_height:
				max_height = b.maxv	

	var aabb = AABB()
	aabb.position = Vector3(origin_in_cells_x, min_height, origin_in_cells_y)
	aabb.size = Vector3(size_in_cells_x, max_height - min_height, size_in_cells_y)
	
	return aabb


func _update_all_vertical_bounds():
	var csize_x = _resolution / HTerrain.CHUNK_SIZE
	var csize_y = _resolution / HTerrain.CHUNK_SIZE
	print("Updating all vertical bounds... (", csize_x , "x", csize_y, " chunks)")
	# TODO Could set `preserve_data` to true, but would require callback to construct new cells
	Grid.resize_grid(_chunked_vertical_bounds, csize_x, csize_y)
	_chunked_vertical_bounds_size = [csize_x, csize_y]

	_update_vertical_bounds(0, 0, _resolution - 1, _resolution - 1)


func _update_vertical_bounds(origin_in_cells_x, origin_in_cells_y, size_in_cells_x, size_in_cells_y):

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

	for y in range(cmin_y, cmax_y):
		var pmin_y = y * HTerrain.CHUNK_SIZE
		
		for x in range(cmin_x, cmax_y):
			
			var b = _chunked_vertical_bounds[y][x]
			if b == null:
				b = VerticalBounds.new()
				_chunked_vertical_bounds[y][x] = b

			var pmin_x = x * HTerrain.CHUNK_SIZE
			_compute_vertical_bounds_at(pmin_x, pmin_y, chunk_size_x, chunk_size_y, b);


func _compute_vertical_bounds_at(origin_x, origin_y, size_x, size_y, out_b):

	var heights = _images[CHANNEL_HEIGHT]
	assert(heights != null)

	var min_x = origin_x
	var min_y = origin_y
	var max_x = origin_x + size_x
	var max_y = origin_y + size_y

	heights.lock();

	var min_height = heights.get_pixel(min_x, min_y).r
	var max_height = min_height

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			
			var h = heights.get_pixel(x, y).r
			
			if h < min_height:
				min_height = h
			elif h > max_height:
				max_height = h
	
	heights.unlock()

	out_b.minv = min_height
	out_b.maxv = max_height


func _notify_progress(message, progress, finished = false):
	_progress_complete = finished
	print("[", int(100.0 * progress), "%] ", message)
	emit_signal("progress_notified", {
		"message": message, 
		"progress": progress,
		"finished": finished
	})


func _notify_progress_complete():
	_notify_progress("Done", 1.0, true)


func save_data_async():
	_locked = true
	_notify_progress("Saving terrain data...", 0.0)
	yield(self, "_internal_process")
	
	for channel in range(CHANNEL_COUNT):
		var p = 0.1 + 0.9 * float(channel) / float(CHANNEL_COUNT)
		_notify_progress("Saving map " + _get_channel_name(channel) + "...", p)
		yield(self, "_internal_process")
		_save_channel(channel)
	# TODO Trigger reimport on generated assets

	_locked = false
	_notify_progress_complete()


func load_data():
	load_data_async()
	while not _progress_complete:
		emit_signal("_internal_process")


func load_data_async():
	_locked = true
	_notify_progress("Loading terrain data...", 0.0)
	yield(self, "_internal_process")
	
	# Note: if we loaded all maps at once before uploading them to VRAM,
	# it would take a lot more RAM than if we load them one by one
	for channel in range(CHANNEL_COUNT):
		var p = 0.1 + 0.6 * float(channel) / float(CHANNEL_COUNT)
		_notify_progress("Loading map " + _get_channel_name(channel) + "...", p)
		yield(self, "_internal_process")
		_load_channel(channel, float(channel) / float(CHANNEL_COUNT))
	
	_notify_progress("Calculating vertical bounds...", 0.8)
	yield(self, "_internal_process")
	_update_all_vertical_bounds()
		
	_notify_progress("Notify resolution change...", 0.9)
	yield(self, "_internal_process")
	
	_locked = false
	emit_signal("resolution_changed")
	
	_notify_progress_complete()


func get_data_dir():
	# TODO Eventually have that one configurable?
	return resource_path.get_basename() + DATA_FOLDER_SUFFIX


func _save_channel(channel):
	var im = _images[channel]
	if im == null:
		var tex = _textures[channel]
		if tex != null:
			print("Image not found for channel ", channel, ", downloading from VRAM")
			im = tex.get_data()
		else:
			print("No data in channel ", channel)
			# This data doesn't have such channel
			return true
	
	var dir_path = get_data_dir()
	var dir = Directory.new()
	if not dir.dir_exists(dir_path):
		dir.make_dir(dir_path)
	
	var fpath = dir_path.plus_file(_get_channel_name(channel))
	
	if _channel_can_be_saved_as_png(channel):
		fpath += ".png"
		im.save_png(fpath)

	else:
		fpath += ".bin"
		var f = File.new()
		var err = f.open(fpath, File.WRITE)
		if err != OK:
			print("Could not open ", fpath, " for writing")
			return false
		
		# TODO Too lazy to save mipmaps in that format...
		# only heights are using it for now anyways
		assert(not im.has_mipmaps())

		var data = im.get_data()
		f.store_32(im.get_width())
		f.store_32(im.get_height())
		var pixel_size = data.size() / (im.get_width() * im.get_height())
		f.store_32(pixel_size)
		f.store_buffer(im.get_data())
		f.close()
	
	return true


func _load_channel(channel, progress = 0.0):
	var dir = get_data_dir()
	var fpath = dir.plus_file(_get_channel_name(channel))
	
	if _channel_can_be_saved_as_png(channel):
		fpath += ".png"
		# In this particular case, we can use Godot ResourceLoader directly, if the texture got imported.

		if Engine.editor_hint:
			# But in the editor we want textures to be editable,
			# so we have to automatically load the data also in RAM
			var im = _images[channel]
			if im == null:
				im = Image.new()
				_images[channel] = im
			im.load(fpath)

		var tex = load(fpath)
		_textures[channel] = tex

	else:
		fpath += ".bin"
		var f = File.new()
		var err = f.open(fpath, File.READ)
		if err != OK:
			print("Could not open ", fpath, " for reading")
			return false
		
		var width = f.get_32()
		var height = f.get_32()
		var pixel_size = f.get_32()
		var data_size = width * height * pixel_size
		var data = f.get_buffer(data_size)
		if data.size() != data_size:
			print("Unexpected end of buffer, expected size ", data_size, ", got ", data.size())
			return false

		_resolution = width

		var im = _images[channel]
		if im == null:
			im = Image.new()
			_images[channel] = im
		im.create_from_data(_resolution, _resolution, false, _get_channel_format(channel), data)
		_upload_channel(channel)

	return true


func _edit_import_heightmap_8bit_async(src_image, min_y, max_y):
	# TODO Support clamping
	if _edit_check_valid_map_size(src_image.get_width(), src_image.get_height()):
		return false
	var res = src_image.get_width()
	
	_locked = true
	
	_notify_progress("Resizing terrain to " + str(res) + "x" + str(res) + "...", 0.1)
	yield(self, "_internal_process")
	set_resolution2(src_image.get_width(), false)
	
	var im = get_image(CHANNEL_HEIGHT)
	assert(im != null)
	
	var hrange = max_y - min_y
	
	var width = Util.min_int(im.get_width(), src_image.get_width())
	var height = Util.min_int(im.get_height(), src_image.get_height())
	
	_notify_progress("Converting to internal format...", 0.2)
	yield(self, "_internal_process")
	
	im.lock()
	src_image.lock()
	
	# Convert to internal format (from RGBA8 to RH16)
	for y in range(0, width):
		for x in range(0, height):
			var gs = src_image.get_pixel(x, y).r
			var h = min_y + hrange * gs
			im.set_pixel(x, y, Color(h, 0, 0))
	
	src_image.unlock()
	im.unlock()
	
	_notify_progress("Updating normals...", 0.3)
	yield(self, "_internal_process")
	_update_all_normals()
	
	_locked = false
	
	_notify_progress("Notify region change...", 0.9)
	yield(self, "_internal_process")
	notify_region_change([0, 0], [im.get_width(), im.get_height()], CHANNEL_HEIGHT)
	
	_notify_progress_complete()


func _edit_import_heightmap_16bit_file_async(f, min_y, max_y):	
	var file_len = f.get_len()
	var file_res = int(round(sqrt(file_len / 2)))
	var res = Util.next_power_of_two(file_res - 1) + 1
	print("file_len: ", file_len, ", file_res: ", file_res, ", res: ", res)
	var width = res
	var height = res

	_locked = true

	_notify_progress("Resizing terrain to " + str(width) + "x" + str(height) + "...", 0.1)
	yield(self, "_internal_process")
	set_resolution2(res, false)
	
	var im = get_image(CHANNEL_HEIGHT)
	assert(im != null)
	
	var hrange = max_y - min_y
	
	_notify_progress("Converting to internal format...", 0.2)
	yield(self, "_internal_process")
	
	im.lock()
	
	var rw = Util.min_int(res, file_res)
	var rh = Util.min_int(res, file_res)
	
	# Convert to internal format (from bytes to RH16)
	var h = 0.0
	for y in range(0, rh):
		for x in range(0, rw):
			var gs = float(f.get_16()) / 65536.0
			h = min_y + hrange * float(gs)
			im.set_pixel(x, y, Color(h, 0, 0))
		# Skip next pixels if the file is bigger than the accepted resolution
		for x in range(rw, file_res):
			f.get_16()
	
	im.unlock()

	_notify_progress("Updating normals...", 0.3)
	yield(self, "_internal_process")
	_update_all_normals()
	
	_locked = false
	_notify_progress("Notifying region change...", 0.9)
	yield(self, "_internal_process")
	
	notify_region_change([0, 0], [im.get_width(), im.get_height()], CHANNEL_HEIGHT)
	
	_notify_progress_complete()


static func _edit_check_valid_map_size(width, height):
	if width != height:
		print("Map is not square.")
		return false
	if Util.next_power_of_two(width) + 1 != width:
		print("Map is not power of two + 1")
		return false
	return true


static func _encode_normal(n):
	return Color(0.5 * (n.x + 1.0), 0.5 * (n.y + 1.0), 0.5 * (n.z + 1.0), 1.0)


#static func _decode_normal(c):
#	return Vector3(2.0 * c.r - 1.0, 2.0 * c.g - 1.0, 2.0 * c.b - 1.0)


static func _get_channel_format(channel):
	match channel:
		CHANNEL_HEIGHT:
			return Image.FORMAT_RH
		CHANNEL_NORMAL:
			return Image.FORMAT_RGB8
		CHANNEL_SPLAT:
			return Image.FORMAT_RGBA8
		CHANNEL_COLOR:
			return Image.FORMAT_RGBA8
	
	print("Unrecognized channel\n")
	return Image.FORMAT_MAX


# Note: PNG supports 16-bit channels, unfortunately Godot doesn't
static func _channel_can_be_saved_as_png(channel):
	if channel == CHANNEL_HEIGHT:
		return false
	return true


static func _get_channel_name(c):
	match c:
		CHANNEL_COLOR:
			return "color"
		CHANNEL_SPLAT:
			return "splat"
		CHANNEL_NORMAL:
			return "normal"
		CHANNEL_HEIGHT:
			return "height"
	return null


