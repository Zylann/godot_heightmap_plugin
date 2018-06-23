tool
extends Resource

const Grid = preload("util/grid.gd")
var HTerrain = load("res://addons/zylann.hterrain/hterrain.gd")
const Util = preload("util/util.gd")

# TODO Rename "CHANNEL" to "MAP", makes more sense and less confusing with RGBA channels
const CHANNEL_HEIGHT = 0
const CHANNEL_NORMAL = 1
const CHANNEL_SPLAT = 2
const CHANNEL_COLOR = 3
const CHANNEL_DETAIL = 4
const CHANNEL_COUNT = 5

const MAX_RESOLUTION = 4096 + 1
const MIN_RESOLUTION = 64 + 1 #HTerrain.CHUNK_SIZE + 1
const DEFAULT_RESOLUTION = 512
# TODO Have vertical bounds chunk size to emphasise the fact it's independent
# TODO Have undo chunk size to emphasise the fact it's independent

const DATA_FOLDER_SUFFIX = ".hterrain_data"


signal resolution_changed
signal region_changed(x, y, w, h, channel)
# TODO Instead of message, send a state enum and a var (for translation and code semantic)
signal progress_notified(info) # { "progress": real, "message": string, "finished": bool }
signal map_added(type, index)
signal map_removed(type, index)
signal map_changed(type, index)

signal _internal_process


class VerticalBounds:
	var minv = 0
	var maxv = 0


# A map is a texture covering the terrain.
# The usage of a map depends on its type (heightmap, normalmap, splatmap...).
class Map:
	var texture
	# Reference used in case we need the data CPU-side
	var image
	# ID used for saving, because when adding/removing maps,
	# we shouldn't rename texture files just because the indexes change
	var id = -1
	# Should be set to true if the map has unsaved modifications.
	var modified = true
	
	func _init(p_id):
		id = p_id


var _resolution = 0

# There can be multiple maps of the same type, though most of them are single
# [map_type][instance_index] => map
var _maps = [[]]

var _chunked_vertical_bounds = []
var _chunked_vertical_bounds_size = [0, 0]
var _locked = false
var _progress_complete = true

var _edit_disable_apply_undo = false


func _init():
	# Initialize default maps
	_set_default_maps()


func _get_property_list():
	var props = [
		{
			# TODO Only allow predefined resolutions, because that's currently the case
			"name": "resolution",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			# I can't use `_maps` because otherwise Godot takes the member variable directly,
			# and ignores whatever I've put in `_get`
			"name": "_maps_data",
			"type": TYPE_ARRAY,
			"usage": PROPERTY_USAGE_STORAGE
		}
	]
	return props


func _get(key):
	match key:
		"resolution":
			return get_resolution()

		"_maps_data":
			var data = []
			data.resize(len(_maps))

			for i in range(len(_maps)):
				var maps = _maps[i]
				var maps_data = []

				for j in range(len(maps)):
					var map = maps[j]
					maps_data.append({ "id": map.id })
				
				data[i] = maps_data
			
			return data


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

		"_maps_data":
			# Parse metadata that we'll then use to load the actual terrain
			# (How many maps, which files to load etc...)
			var data = v
			_maps.resize(len(data))

			for i in range(len(data)):
				var maps = _maps[i]

				if maps == null:
					maps = []
					_maps[i] = maps

				var maps_data = data[i]
				if len(maps) != len(maps_data):
					maps.resize(len(maps_data))

				for j in range(len(maps)):
					var map = maps[j]
					var id = maps_data[j].id
					if map == null:
						map = Map.new(id)
						maps[j] = map
					else:
						map.id = id


func _set_default_maps():
	_maps.resize(CHANNEL_COUNT)
	for c in range(CHANNEL_COUNT):
		var maps = []
		var n = _get_channel_default_count(c)
		for i in range(n):
			maps.append(Map.new(i))
		_maps[c] = maps


func _edit_load_default():
	print("Loading default data")
	_set_default_maps()
	set_resolution(DEFAULT_RESOLUTION)
	_update_all_normals()


# Don't use the data if this getter returns false
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

	p_res = Util.clamp_int(p_res, MIN_RESOLUTION, MAX_RESOLUTION)

	# Power of two is important for LOD.
	# Also, grid data is off by one,
	# because for an even number of quads you need an odd number of vertices.
	# To prevent size from increasing at every deserialization, remove 1 before applying power of two.
	p_res = Util.next_power_of_two(p_res - 1) + 1

	_resolution = p_res;
	
	for channel in range(CHANNEL_COUNT):
		var maps = _maps[channel]
		
		for index in len(maps):
			print("Resizing ", _get_map_debug_name(channel, index), "...")

			var map = maps[index]
			var im = map.image
			
			if im == null:
				im = Image.new()
				im.create(_resolution, _resolution, false, _get_channel_format(channel))
				
				var fill_color = _get_channel_default_fill(channel)
				if fill_color != null:
					im.fill(fill_color)
				
				map.image = im
				
			else:
				if channel == CHANNEL_NORMAL:
					im.create(_resolution, _resolution, false, _get_channel_format(channel))
					if update_normals:
						_update_all_normals()
				else:
					im.resize(_resolution, _resolution)
			
			map.modified = true

	_update_all_vertical_bounds()

	emit_signal("resolution_changed")

	# TODO No upload to GPU? I wonder how this worked so far, maybe I didn't intend this?


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


# Gets the height at the given cell position.
# This height is raw and doesn't account for scaling of the terrain node.
# This function is relatively slow due to locking, so don't use it to fetch large areas.
func get_height_at(x, y):

	# Height data must be loaded in RAM
	var im = get_image(CHANNEL_HEIGHT)
	assert(im != null)

	im.lock();
	var h = _get_clamped(im, x, y).r;
	im.unlock();
	return h;


# Gets the height at the given floating-point cell position.
# This height is raw and doesn't account for scaling of the terrain node.
# This function is relatively slow due to locking, so don't use it to fetch large areas
func get_interpolated_height_at(pos):

	# Height data must be loaded in RAM
	var im = get_image(CHANNEL_HEIGHT)
	assert(im != null)

	# The function takes a Vector3 for convenience so it's easier to use in 3D scripting
	var x0 = int(floor(pos.x))
	var y0 = int(floor(pos.z))

	var xf = pos.x - x0
	var yf = pos.z - y0

	im.lock()
	var h00 = _get_clamped(im, x0, y0).r
	var h10 = _get_clamped(im, x0 + 1, y0).r
	var h01 = _get_clamped(im, x0, y0 + 1).r
	var h11 = _get_clamped(im, x0 + 1, y0 + 1).r
	im.unlock()

	# Bilinear filter
	var h = lerp(lerp(h00, h10, xf), lerp(h01, h11, xf), yf)

	return h;


# Gets all heights within the given rectangle in cells.
# This height is raw and doesn't account for scaling of the terrain node.
# Data is returned as a PoolRealArray.
func get_heights_region(x0, y0, w, h):
	var im = get_image(CHANNEL_HEIGHT)
	assert(im != null)
	
	var min_x = Util.clamp_int(x0, 0, im.get_width())
	var min_y = Util.clamp_int(y0, 0, im.get_height())
	var max_x = Util.clamp_int(x0 + w, 0, im.get_width() + 1)
	var max_y = Util.clamp_int(y0 + h, 0, im.get_height() + 1)
	
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


# Gets all heights.
# This height is raw and doesn't account for scaling of the terrain node.
# Data is returned as a PoolRealArray.
func get_all_heights():
	return get_heights_region(0, 0, _resolution, _resolution)


# TODO Have an async version that uses the GPU
func _update_all_normals():
	update_normals(0, 0, _resolution, _resolution)


func update_normals(min_x, min_y, size_x, size_y):	
	#var time_before = OS.get_ticks_msec()

	assert(typeof(min_x) == TYPE_INT)
	assert(typeof(min_y) == TYPE_INT)
	assert(typeof(size_x) == TYPE_INT)
	assert(typeof(size_x) == TYPE_INT)
	
	var heights = get_image(CHANNEL_HEIGHT)
	var normals = get_image(CHANNEL_NORMAL)
	
	assert(heights != null)
	assert(normals != null)

	var max_x = min_x + size_x
	var max_y = min_y + size_y

	var p_min = [min_x, min_y]
	var p_max = [max_x, max_y]
	Util.clamp_min_max_excluded(p_min, p_max, [0, 0], [heights.get_width(), heights.get_height()])
	min_x = p_min[0]
	min_y = p_min[1]
	max_x = p_max[0]
	max_y = p_max[1]

	if normals.has_method("bumpmap_to_normalmap"):

		# Calculating normals using this function will make border pixels invalid,
		# so we must pick a region 1 pixel larger in all directions to be sure we have neighboring information.
		# Then, we'll blit the result by cropping away this margin.
		var min_pad_x = 0 if min_x == 0 else 1
		var min_pad_y = 0 if min_y == 0 else 1
		var max_pad_x = 0 if max_x == normals.get_width() else 1
		var max_pad_y = 0 if max_y == normals.get_height() else 1

		var src_extract_rect = Rect2( \
			min_x - min_pad_x, \
			min_y - min_pad_y, \
			max_x - min_x + min_pad_x + max_pad_x, \
			max_y - min_y + min_pad_x + max_pad_x)

		var sub = heights.get_rect(src_extract_rect)
		# TODO Need a parameter for this function to NOT wrap pixels, it can cause lighting artifacts on map borders
		sub.bumpmap_to_normalmap()
		sub.convert(normals.get_format())

		var src_blit_rect = Rect2( \
			min_pad_x, \
			min_pad_x, \
			sub.get_width() - min_pad_x - max_pad_x, \
			sub.get_height() - min_pad_x - max_pad_y)

		normals.blit_rect(sub, src_blit_rect, Vector2(min_x, min_y))

	else:
		# Godot 3.0.3 or earlier...
		# It is slow.

		#                             __________
		#                          .~#########%%;~.
		#                         /############%%;`\
		#                        /######/~\/~\%%;,;,\
		#                       |#######\    /;;;;.,.|
		#                       |#########\/%;;;;;.,.|
		#              XX       |##/~~\####%;;;/~~\;,|       XX
		#            XX..X      |#|  o  \##%;/  o  |.|      X..XX
		#          XX.....X     |##\____/##%;\____/.,|     X.....XX
		#     XXXXX.....XX      \#########/\;;;;;;,, /      XX.....XXXXX
		#    X |......XX%,.@      \######/%;\;;;;, /      @#%,XX......| X
		#    X |.....X  @#%,.@     |######%%;;;;,.|     @#%,.@  X.....| X
		#    X  \...X     @#%,.@   |# # # % ; ; ;,|   @#%,.@     X.../  X
		#     X# \.X        @#%,.@                  @#%,.@        X./  #
		#      ##  X          @#%,.@              @#%,.@          X   #
		#    , "# #X            @#%,.@          @#%,.@            X ##
		#       `###X             @#%,.@      @#%,.@             ####'
		#      . ' ###              @#%.,@  @#%,.@              ###`"
		#        . ";"                @#%.@#%,.@                ;"` ' .
		#          '                    @#%,.@                   ,.
		#          ` ,                @#%,.@  @@                `
		#                              @@@  @@@  

		heights.lock();
		normals.lock();

		for y in range(min_y, max_y):
			for x in range(min_x, max_x):
				
				var left = _get_clamped(heights, x - 1, y).r
				var right = _get_clamped(heights, x + 1, y).r
				var fore = _get_clamped(heights, x, y + 1).r
				var back = _get_clamped(heights, x, y - 1).r

				var n = Vector3(left - right, 2.0, fore - back).normalized()

				normals.set_pixel(x, y, _encode_normal(n))
				
		heights.unlock()
		normals.unlock()

	#var time_elapsed = OS.get_ticks_msec() - time_before
	#print("Elapsed updating normals: ", time_elapsed, "ms")
	#print("Was from ", min_x, ", ", min_y, " to ", max_x, ", ", max_y)


# Call this function after you end modifying a map.
# It will commit the change to the GPU so the change will take effect.
# In the editor, it will also mark the map as modified so it will be saved when needed.
# Finally, it will emit `region_changed`, which allows other systems to catch up (like physics or grass)
# p_min: origin point in cells of the rectangular area, as an array of 2 integers. 
# p_size: size of the rectangular area, as an array of 2 integers.
# channel: which kind of map changed
# index: index of the map that changed
func notify_region_change(p_min, p_size, channel, index = 0):

	# TODO Hmm not sure if that belongs here // <-- why this, Me from the past?
	match channel:
		CHANNEL_HEIGHT:
			# TODO when drawing very large patches, this might get called too often and would slow down.
			# for better user experience, we could set chunks AABBs to a very large height just while drawing,
			# and set correct AABBs as a background task once done
			_update_vertical_bounds(p_min[0], p_min[1], p_size[0], p_size[1])

			_upload_region(channel, 0, p_min[0], p_min[1], p_size[0], p_size[1])
			_upload_region(CHANNEL_NORMAL, 0, p_min[0], p_min[1], p_size[0], p_size[1])

			_maps[CHANNEL_NORMAL][index].modified = true
			_maps[channel][index].modified = true

		CHANNEL_NORMAL, \
		CHANNEL_SPLAT, \
		CHANNEL_COLOR, \
		CHANNEL_DETAIL:
			_upload_region(channel, index, p_min[0], p_min[1], p_size[0], p_size[1])
			_maps[channel][index].modified = true

		_:
			print("Unrecognized channel\n")

	emit_signal("region_changed", p_min[0], p_min[1], p_size[0], p_size[1], channel)


func _edit_set_disable_apply_undo(e):
	_edit_disable_apply_undo = e


func _edit_apply_undo(undo_data):

	if _edit_disable_apply_undo:
		return

	var chunk_positions = undo_data["chunk_positions"]
	var chunk_datas = undo_data["data"]
	var channel = undo_data["channel"]
	var index = undo_data["index"]

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
		
		var dst_image = get_image(channel, index)
		assert(dst_image != null)

		match channel:

			CHANNEL_HEIGHT:
				dst_image.blit_rect(data, data_rect, Vector2(min_x, min_y))
				# Padding is needed because normals are calculated using neighboring,
				# so a change in height X also requires normals in X-1 and X+1 to be updated
				update_normals(min_x - 1, min_y - 1, max_x - min_x + 2, max_y - min_y + 2)

			CHANNEL_SPLAT, \
			CHANNEL_COLOR, \
			CHANNEL_DETAIL:
				dst_image.blit_rect(data, data_rect, Vector2(min_x, min_y))

			CHANNEL_NORMAL:
				print("This is a calculated channel!, no undo on this one\n")
			_:
				print("Wut? Unsupported undo channel\n");
		
		# Defer this to a second pass, otherwise it causes order-dependent artifacts on the normal map
		regions_changed.append([[min_x, min_y], [max_x - min_x, max_y - min_y], channel, index])

	for args in regions_changed:
		# TODO This one is VERY slow because partial texture updates is not supported...
		# so the entire texture gets reuploaded for each chunk being undone
		notify_region_change(args[0], args[1], args[2], args[3])


func _upload_channel(channel, index):
	_upload_region(channel, index, 0, 0, _resolution, _resolution)


func _upload_region(channel, index, min_x, min_y, size_x, size_y):

	#print("Upload ", min_x, ", ", min_y, ", ", size_x, "x", size_y)
	#var time_before = OS.get_ticks_msec()

	var map = _maps[channel][index]

	var image = map.image
	assert(image != null)
	assert(size_x > 0 and size_y > 0)

	var flags = 0;
	if channel == CHANNEL_NORMAL or channel == CHANNEL_COLOR or channel == CHANNEL_SPLAT or channel == CHANNEL_HEIGHT:
		flags |= Texture.FLAG_FILTER

	var texture = map.texture

	if texture == null or not (texture is ImageTexture):
		
		# The texture doesn't exist yet in an editable format
		if texture != null and not (texture is ImageTexture):
			print("_upload_region was used but the texture isn't an ImageTexture. ",\
				"The map ", channel, "[", index, "] will be reuploaded entirely.")
		else:
			print("_upload_region was used but the texture is not created yet. ",\
				"The map ", channel, "[", index, "] will be uploaded entirely.")

		texture = ImageTexture.new()
		texture.create_from_image(image, flags)
		
		map.texture = texture

		# Need to notify because other systems may want to grab the new texture object
		emit_signal("map_changed", channel, index)

	elif texture.get_size() != image.get_size():

		print("_upload_region was used but the image size is different. ",\
			"The map ", channel, "[", index, "] will be reuploaded entirely.")
		
		texture.create_from_image(image, flags)

	else:
		if VisualServer.has_method("texture_set_data_partial"):

			# TODO Actually, I think the input params should be valid in the first place...
			if min_x < 0:
				min_x = 0
			if min_y < 0:
				min_y = 0
			if min_x + size_x > image.get_width():
				size_x = image.get_width() - min_x
			if min_y + size_y > image.get_height():
				size_y = image.get_height() - min_y
			#if size_x <= 0 or size_y <= 0:
			#	return

			VisualServer.texture_set_data_partial( \
				texture.get_rid(), image, \
				min_x, min_y, \
				size_x, size_y, \
				min_x, min_y, \
				0, 0)

		else:
			# Godot 3.0.3 and earlier...
			# It is slow.

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
			texture.create_from_image(image, flags)

	#print("Channel updated ", channel)

	#var time_elapsed = OS.get_ticks_msec() - time_before
	#print("Texture upload time: ", time_elapsed, "ms")


func get_map_count(map_type):
	return len(_maps[map_type])


func _edit_add_detail_map():
	print("Adding detail map")
	var map_type = CHANNEL_DETAIL
	var detail_maps = _maps[map_type]
	var map = Map.new(_get_free_id(map_type))
	map.image = Image.new()
	map.image.create(_resolution, _resolution, false, _get_channel_format(map_type))
	var index = len(detail_maps)
	detail_maps.append(map)
	emit_signal("map_added", map_type, index)
	return index


func _edit_remove_detail_map(index):
	print("Removing detail map ", index)
	var map_type = CHANNEL_DETAIL
	var detail_maps = _maps[map_type]
	detail_maps.remove(index)
	emit_signal("map_removed", map_type, index)


func _get_free_id(map_type):
	var maps = _maps[map_type]
	var id = 0
	while _get_map_by_id(map_type, id) != null:
		id += 1
	return id


func _get_map_by_id(map_type, id):
	var maps = _maps[map_type]
	for map in maps:
		if map.id == id:
			return map
	return null


func get_image(channel, index = 0):
	var maps = _maps[channel]
	return maps[index].image


func _get_texture(channel, index):
	var maps = _maps[channel]
	return maps[index].texture


func get_texture(channel, index = 0):
	# TODO Perhaps it's not a good idea to auto-upload like that
	if _get_texture(channel, index) == null and get_image(channel) != null:
		_upload_channel(channel, index)
	return _get_texture(channel, index)


func get_aabb():
	# TODO Why subtract 1? I forgot
	return get_region_aabb(0, 0, _resolution - 1, _resolution - 1)


func get_region_aabb(origin_in_cells_x, origin_in_cells_y, size_in_cells_x, size_in_cells_y):

	assert(typeof(origin_in_cells_x) == TYPE_INT)
	assert(typeof(origin_in_cells_y) == TYPE_INT)
	assert(typeof(size_in_cells_x) == TYPE_INT)
	assert(typeof(size_in_cells_y) == TYPE_INT)

	# Get info from cached vertical bounds,
	# which is a lot faster than directly fetching heights from the map.
	# It's not 100% accurate, but enough for culling use case if chunk size is decently chosen.

	var cmin_x = origin_in_cells_x / HTerrain.CHUNK_SIZE
	var cmin_y = origin_in_cells_y / HTerrain.CHUNK_SIZE
	
	var cmax_x = (origin_in_cells_x + size_in_cells_x - 1) / HTerrain.CHUNK_SIZE + 1
	var cmax_y = (origin_in_cells_y + size_in_cells_y - 1) / HTerrain.CHUNK_SIZE + 1

	if cmin_x < 0:
		cmin_x = 0
	if cmin_y < 0:
		cmin_y = 0
	if cmax_x >= _chunked_vertical_bounds_size[0]:
		cmax_x = _chunked_vertical_bounds_size[0]
	if cmax_y >= _chunked_vertical_bounds_size[1]:
		cmax_y = _chunked_vertical_bounds_size[1]

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

	var heights = get_image(CHANNEL_HEIGHT)
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
	if not _is_any_map_modified():
		print("Terrain data has no modifications to save")
		return

	_locked = true
	_notify_progress("Saving terrain data...", 0.0)
	yield(self, "_internal_process")
	
	var map_count = _get_total_map_count()
	
	var pi = 0
	for channel in range(CHANNEL_COUNT):
		var maps = _maps[channel]
		
		for index in range(len(maps)):
			
			var map = _maps[channel][index]
			if not map.modified:
				print("Skipping non-modified ", _get_map_debug_name(channel, index))
				continue

			var p = 0.1 + 0.9 * float(pi) / float(map_count)
			_notify_progress(str("Saving map ", _get_map_debug_name(channel, index), \
				" as ", _get_map_filename(channel, index), "..."), p)

			yield(self, "_internal_process")
			_save_channel(channel, index)

			map.modified = false
			pi += 1
			
	# TODO In editor, trigger reimport on generated assets

	_locked = false
	_notify_progress_complete()


func _is_any_map_modified():
	for maplist in _maps:
		for map in maplist:
			if map.modified:
				return true
	return false


func _get_total_map_count():
	var s = 0
	for maps in _maps:
		s += len(maps)
	return s


func load_data():
	load_data_async()
	while not _progress_complete:
		emit_signal("_internal_process")


func load_data_async():
	_locked = true
	_notify_progress("Loading terrain data...", 0.0)
	yield(self, "_internal_process")
	
	var channel_instance_sum = _get_total_map_count()
	var pi = 0

	# Note: if we loaded all maps at once before uploading them to VRAM,
	# it would take a lot more RAM than if we load them one by one
	for map_type in range(len(_maps)):
		var maps = _maps[map_type]

		for index in range(len(maps)):

			var p = 0.1 + 0.6 * float(pi) / float(channel_instance_sum)
			_notify_progress(str("Loading map ", _get_map_debug_name(map_type, index), \
				" from ", _get_map_filename(map_type, index), "..."), p)
			yield(self, "_internal_process")

			_load_channel(map_type, index)

			# A map that was just loaded is considered not modified yet
			_maps[map_type][index].modified = false

			pi += 1
	
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


func _save_channel(channel, index):
	var map = _maps[channel][index]
	var im = map.image
	if im == null:
		var tex = map.texture
		if tex != null:
			print("Image not found for channel ", channel, ", downloading from VRAM")
			im = tex.get_data()
		else:
			print("No data in channel ", channel, "[", index, "]")
			# This data doesn't have such channel
			return true
	
	var dir_path = get_data_dir()
	var dir = Directory.new()
	if not dir.dir_exists(dir_path):
		dir.make_dir(dir_path)
	
	var fpath = dir_path.plus_file(_get_map_filename(channel, index))
	
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


func _load_channel(channel, index):
	var dir = get_data_dir()
	var fpath = dir.plus_file(_get_map_filename(channel, index))

	# Maps must be configured before being loaded
	var map = _maps[channel][index]
	# while len(_maps) <= channel:
	# 	_maps.append([])
	# while len(_maps[channel]) <= index:
	# 	_maps[channel].append(null)
	# var map = _maps[channel][index]
	# if map == null:
	# 	map = Map.new()
	# 	_maps[channel][index] = map
	
	if _channel_can_be_saved_as_png(channel):
		fpath += ".png"
		# In this particular case, we can use Godot ResourceLoader directly, if the texture got imported.

		if Engine.editor_hint:
			# But in the editor we want textures to be editable,
			# so we have to automatically load the data also in RAM
			if map.image == null:
				map.image = Image.new()
			map.image.load(fpath)

		var tex = load(fpath)
		map.texture = tex

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
		
		if map.image == null:
			map.image = Image.new()
		map.image.create_from_data(_resolution, _resolution, false, _get_channel_format(channel), data)
		_upload_channel(channel, index)

	return true


# Imports images into the terrain data by converting them to the internal format.
# It is possible to omit some of them, in which case those already setup will be used.
# This function is quite permissive, and will only fail if there is really no way to import.
# It may involve cropping, so preliminary checks should be done to inform the user.
#
# TODO Plan is to make this function threaded, in case import takes too long.
# So anything that could mess with the main thread should be avoided.
# Eventually, it would be temporarily removed from the terrain node to work in isolation during import.
func _edit_import_maps(input):
	assert(typeof(input) == TYPE_DICTIONARY)

	if input.has(CHANNEL_HEIGHT):
		var params = input[CHANNEL_HEIGHT]
		if not _import_heightmap(params.path, params.min_height, params.max_height):
			return false

	var maptypes = [CHANNEL_COLOR, CHANNEL_SPLAT]

	for map_type in maptypes:
		if input.has(map_type):
			var params = input[map_type]
			if not _import_map(map_type, params.path):
				return false

	return true


static func get_adjusted_map_size(width, height):
	var width_po2 = Util.next_power_of_two(width - 1) + 1
	var height_po2 = Util.next_power_of_two(height - 1) + 1
	var size_po2 = Util.min_int(width_po2, height_po2)
	size_po2 = Util.clamp_int(size_po2, MIN_RESOLUTION, MAX_RESOLUTION)
	return size_po2


func _import_heightmap(fpath, min_y, max_y):
	var ext = fpath.get_extension().to_lower()

	if ext == "png":
		# Godot can only load 8-bit PNG,
		# so we have to bring it back to float in the wanted range

		var src_image = Image.new()
		var err = src_image.load(fpath)
		if err != OK:
			return false

		var res = get_adjusted_map_size(src_image.get_width(), src_image.get_height())
		if res != src_image.get_width():
			src_image.crop(res, res)
		
		_locked = true
		
		print("Resizing terrain to ", res, "x", res, "...")
		set_resolution2(src_image.get_width(), false)
		
		var im = get_image(CHANNEL_HEIGHT)
		assert(im != null)
		
		var hrange = max_y - min_y
		
		var width = Util.min_int(im.get_width(), src_image.get_width())
		var height = Util.min_int(im.get_height(), src_image.get_height())
		
		print("Converting to internal format...", 0.2)
		
		im.lock()
		src_image.lock()
		
		# Convert to internal format (from RGBA8 to RH16) with range scaling
		for y in range(0, width):
			for x in range(0, height):
				var gs = src_image.get_pixel(x, y).r
				var h = min_y + hrange * gs
				im.set_pixel(x, y, Color(h, 0, 0))
		
		src_image.unlock()
		im.unlock()

	elif ext == "raw":
		# RAW files don't contain size, so we have to deduce it from 16-bit size.
		# We also need to bring it back to float in the wanted range.

		var f = File.new()
		var err = f.open(fpath, File.READ)
		if err != OK:
			return false

		var file_len = f.get_len()
		var file_res = Util.integer_square_root(file_len / 2)
		if file_res == -1:
			# Can't deduce size
			return false

		var res = get_adjusted_map_size(file_res, file_res)

		var width = res
		var height = res

		_locked = true

		print("Resizing terrain to ", width, "x", height, "...")
		set_resolution2(res, false)
		
		var im = get_image(CHANNEL_HEIGHT)
		assert(im != null)
		
		var hrange = max_y - min_y
		
		print("Converting to internal format...")
		
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
	
	else:
		# File extension not recognized
		return false
	
	print("Updating normals...")
	_update_all_normals()
	
	_locked = false
	
	print("Notify region change...")
	notify_region_change([0, 0], [get_resolution(), get_resolution()], CHANNEL_HEIGHT)

	return true


func _import_map(map_type, path):
	# Heightmap requires special treatment
	assert(map_type != CHANNEL_HEIGHT)

	var im = Image.new()
	var err = im.load(path)
	if err != OK:
		return false

	var res = get_resolution()
	if im.get_width() != res or im.get_height() != res:
		im.crop(res, res)

	if im.get_format() != _get_channel_format(map_type):
		im.convert(_get_channel_format(map_type))

	var map = _maps[map_type][0]
	map.image = im

	notify_region_change([0, 0], [im.get_width(), im.get_height()], map_type)
	return true


static func _encode_normal(n):
	return Color(0.5 * (n.x + 1.0), 0.5 * (n.z + 1.0), 0.5 * (n.y + 1.0), 1.0)


#static func _decode_normal(c):
#	return Vector3(2.0 * c.r - 1.0, 2.0 * c.b - 1.0, 2.0 * c.g - 1.0)


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
		CHANNEL_DETAIL:
			return Image.FORMAT_L8
	
	print("Unrecognized channel\n")
	return Image.FORMAT_MAX


# Note: PNG supports 16-bit channels, unfortunately Godot doesn't
static func _channel_can_be_saved_as_png(channel):
	if channel == CHANNEL_HEIGHT:
		return false
	return true


static func _get_channel_name(c):
	var name = null
	match c:
		CHANNEL_COLOR:
			name = "color"
		CHANNEL_SPLAT:
			name = "splat"
		CHANNEL_NORMAL:
			name = "normal"
		CHANNEL_HEIGHT:
			name = "height"
		CHANNEL_DETAIL:
			name = "detail"
	assert(name != null)
	return name


static func _get_map_debug_name(map_type, index):
	return str(_get_channel_name(map_type), "[", index, "]")


func _get_map_filename(c, index):
	var name = _get_channel_name(c)
	var id = _maps[c][index].id
	if id > 0:
		name += str(id + 1)
	return name


static func _get_channel_default_fill(c):
	match c:
		CHANNEL_COLOR:
			return Color(1, 1, 1, 1)
		CHANNEL_SPLAT:
			return Color(1, 0, 0, 0)
		CHANNEL_DETAIL:
			return Color(0, 0, 0, 0)
		_:
			# No need to fill
			return null


static func _get_channel_default_count(c):
	if c == CHANNEL_DETAIL:
		return 0
	return 1
