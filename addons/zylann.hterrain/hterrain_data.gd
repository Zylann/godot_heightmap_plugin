
# Holds data of the terrain.
# This is mostly a set of textures using specific formats, some precalculated, and metadata.

@tool
extends Resource

const HT_Grid = preload("./util/grid.gd")
const HT_Util = preload("./util/util.gd")
const HT_Errors = preload("./util/errors.gd")
const HT_Logger = preload("./util/logger.gd")
const HT_ImageFileCache = preload("./util/image_file_cache.gd")
const HT_XYZFormat = preload("./util/xyz_format.gd")

enum {
	BIT_DEPTH_UNDEFINED = 0,
	BIT_DEPTH_16 = 16,
	BIT_DEPTH_32 = 32
}

# Note: indexes matters for saving, don't re-order
# TODO Rename "CHANNEL" to "MAP", makes more sense and less confusing with RGBA channels
const CHANNEL_HEIGHT = 0
const CHANNEL_NORMAL = 1
const CHANNEL_SPLAT = 2
const CHANNEL_COLOR = 3
const CHANNEL_DETAIL = 4
const CHANNEL_GLOBAL_ALBEDO = 5
const CHANNEL_SPLAT_INDEX = 6
const CHANNEL_SPLAT_WEIGHT = 7
const CHANNEL_COUNT = 8

const _map_types = {
	CHANNEL_HEIGHT: {
		name = "height",
		shader_param_name = "u_terrain_heightmap",
		filter = true,
		mipmaps = false,
		texture_format = Image.FORMAT_RF,
		default_fill = Color(0, 0, 0, 1),
		default_count = 1,
		can_be_saved_as_png = false,
		authored = true,
		srgb = false
	},
	CHANNEL_NORMAL: {
		name = "normal",
		shader_param_name = "u_terrain_normalmap",
		filter = true,
		mipmaps = false,
		# TODO RGB8 is a lie, we should use RGBA8 and pack something in A I guess
		texture_format = Image.FORMAT_RGB8,
		default_fill = Color(0.5, 0.5, 1.0),
		default_count = 1,
		can_be_saved_as_png = true,
		authored = false,
		srgb = false
	},
	CHANNEL_SPLAT: {
		name = "splat",
		shader_param_name = [
			"u_terrain_splatmap", # not _0 for compatibility
			"u_terrain_splatmap_1",
			"u_terrain_splatmap_2",
			"u_terrain_splatmap_3"
		],
		filter = true,
		mipmaps = false,
		texture_format = Image.FORMAT_RGBA8,
		default_fill = [Color(1, 0, 0, 0), Color(0, 0, 0, 0)],
		default_count = 1,
		can_be_saved_as_png = true,
		authored = true,
		srgb = false
	},
	CHANNEL_COLOR: {
		name = "color",
		shader_param_name = "u_terrain_colormap",
		filter = true,
		mipmaps = false,
		texture_format = Image.FORMAT_RGBA8,
		default_fill = Color(1, 1, 1, 1),
		default_count = 1,
		can_be_saved_as_png = true,
		authored = true,
		srgb = true
	},
	CHANNEL_DETAIL: {
		name = "detail",
		shader_param_name = "u_terrain_detailmap",
		filter = true,
		mipmaps = false,
		texture_format = Image.FORMAT_R8,
		default_fill = Color(0, 0, 0),
		default_count = 0,
		can_be_saved_as_png = true,
		authored = true,
		srgb = false
	},
	CHANNEL_GLOBAL_ALBEDO: {
		name = "global_albedo",
		shader_param_name = "u_terrain_globalmap",
		filter = true,
		mipmaps = true,
		texture_format = Image.FORMAT_RGB8,
		default_fill = null,
		default_count = 0,
		can_be_saved_as_png = true,
		authored = false,
		srgb = true
	},
	CHANNEL_SPLAT_INDEX: {
		name = "splat_index",
		shader_param_name = "u_terrain_splat_index_map",
		filter = false,
		mipmaps = false,
		texture_format = Image.FORMAT_RGB8,
		default_fill = Color(0, 0, 0),
		default_count = 0,
		can_be_saved_as_png = true,
		authored = true,
		srgb = false
	},
	CHANNEL_SPLAT_WEIGHT: {
		name = "splat_weight",
		shader_param_name = "u_terrain_splat_weight_map",
		filter = true,
		mipmaps = false,
		texture_format = Image.FORMAT_RG8,
		default_fill = Color(1, 0, 0),
		default_count = 0,
		can_be_saved_as_png = true,
		authored = true,
		srgb = false
	}
}

# Resolution is a power of two + 1
const MAX_RESOLUTION = 4097
const MIN_RESOLUTION = 65 # must be higher than largest chunk size
const DEFAULT_RESOLUTION = 513
const SUPPORTED_RESOLUTIONS = [65, 129, 257, 513, 1025, 2049, 4097]

const VERTICAL_BOUNDS_CHUNK_SIZE = 16
# TODO Have undo chunk size to emphasise the fact it's independent

const META_EXTENSION = "hterrain"
const META_FILENAME = "data.hterrain"
const META_VERSION = "0.11"

signal resolution_changed
signal region_changed(x, y, w, h, channel)
signal map_added(type, index)
signal map_removed(type, index)
signal map_changed(type, index)


# A map is a texture covering the terrain.
# The usage of a map depends on its type (heightmap, normalmap, splatmap...).
class HT_Map:
	var texture: Texture2D
	# Reference used in case we need the data CPU-side
	var image: Image
	# ID used for saving, because when adding/removing maps,
	# we shouldn't rename texture files just because the indexes change.
	# This is mostly for internal keeping.
	# The API still uses indexes that may shift if your remove a map.
	var id := -1
	# Should be set to true if the map has unsaved modifications.
	var modified := true

	func _init(p_id: int):
		id = p_id


var _resolution := 0

# There can be multiple maps of the same type, though most of them are single
# [map_type][instance_index] => map
var _maps := [[]]

# RGF image where R is min height and G is max height
var _chunked_vertical_bounds := Image.new()

var _locked := false

var _edit_disable_apply_undo := false
var _logger := HT_Logger.get_for(self)


func _init():
	# Initialize default maps
	_set_default_maps()


func _set_default_maps():
	_maps.resize(CHANNEL_COUNT)
	for c in CHANNEL_COUNT:
		var maps := []
		var n : int = _map_types[c].default_count
		for i in n:
			maps.append(HT_Map.new(i))
		_maps[c] = maps


func _edit_load_default():
	_logger.debug("Loading default data")
	_set_default_maps()
	resize(DEFAULT_RESOLUTION)


# Don't use the data if this getter returns false
func is_locked() -> bool:
	return _locked


func get_resolution() -> int:
	return _resolution


# @obsolete
func set_resolution(p_res):
	_logger.error("`HTerrainData.set_resolution()` is obsolete, use `resize()` instead")
	resize(p_res)


# @obsolete
func set_resolution2(p_res, update_normals):
	_logger.error("`HTerrainData.set_resolution2()` is obsolete, use `resize()` instead")
	resize(p_res, true, Vector2(-1, -1))


# Resizes all maps of the terrain. This may take some time to complete.
# Note that no upload to GPU is done, you have to do it once you're done with all changes,
# by calling `notify_region_change` or `notify_full_change`.
# p_res: new resolution. Must be a power of two + 1.
# stretch: if true, the terrain will be stretched in X and Z axes.
#          If false, it will be cropped or expanded.
# anchor: if stretch is false, decides which side or corner to crop/expand the terrain from.
#
# There is an off-by-one in the data,
# so for example a map of 512x512 will actually have 513x513 cells.
# Here is why:
# If we had an even amount of cells, it would produce this situation when making LOD chunks:
#
#   x---x---x---x      x---x---x---x
#   |   |   |   |      |       |
#   x---x---x---x      x   x   x   x
#   |   |   |   |      |       |
#   x---x---x---x      x---x---x---x
#   |   |   |   |      |       |
#   x---x---x---x      x   x   x   x
#
#       LOD 0              LOD 1
#
# We would be forced to ignore the last cells because they would produce an irregular chunk.
# We need an off-by-one because quads making up chunks SHARE their consecutive vertices.
# One quad needs at least 2x2 cells to exist.
# Two quads of the heightmap share an edge, which needs a total of 3x3 cells, not 4x4.
# One chunk has 16x16 quads, so it needs 17x17 cells,
# not 16, where the last cell is shared with the next chunk.
# As a result, a map of 4x4 chunks needs 65x65 cells, not 64x64.
func resize(p_res: int, stretch := true, anchor := Vector2(-1, -1)):
	assert(typeof(p_res) == TYPE_INT)
	assert(typeof(stretch) == TYPE_BOOL)
	assert(typeof(anchor) == TYPE_VECTOR2)

	_logger.debug(str("set_resolution ", p_res))

	if p_res == get_resolution():
		return

	p_res = clampi(p_res, MIN_RESOLUTION, MAX_RESOLUTION)

	# Power of two is important for LOD.
	# Also, grid data is off by one,
	# because for an even number of quads you need an odd number of vertices.
	# To prevent size from increasing at every deserialization,
	# remove 1 before applying power of two.
	p_res = HT_Util.next_power_of_two(p_res - 1) + 1

	_resolution = p_res;

	for channel in CHANNEL_COUNT:
		var maps : Array = _maps[channel]

		for index in len(maps):
			_logger.debug(str("Resizing ", get_map_debug_name(channel, index), "..."))

			var map : HT_Map = maps[index]
			var im := map.image

			if im == null:
				_logger.debug("Image not in memory, creating it")
				im = Image.create(_resolution, _resolution, false, get_channel_format(channel))

				var fill_color = _get_map_default_fill_color(channel, index)
				if fill_color != null:
					_logger.debug(str("Fill with ", fill_color))
					im.fill(fill_color)

			else:
				if stretch and not _map_types[channel].authored:
					# Create a blank new image, it will be automatically computed later
					im = Image.create(_resolution, _resolution, false, get_channel_format(channel))
				else:
					if stretch:
						if im.get_format() == Image.FORMAT_RGB8:
							# Can't directly resize this format
							var float_heightmap := convert_heightmap_to_float(im, _logger)
							float_heightmap.resize(_resolution, _resolution)
							im = Image.create(
								float_heightmap.get_width(),
								float_heightmap.get_height(), im.has_mipmaps(), im.get_format())
							convert_float_heightmap_to_rgb8(float_heightmap, im)
						else:
							# Assuming float or single-component fixed-point
							im.resize(_resolution, _resolution)
					else:
						var fill_color = _get_map_default_fill_color(channel, index)
						im = HT_Util.get_cropped_image(im, _resolution, _resolution, \
							fill_color, anchor)

			map.image = im
			map.modified = true

	_update_all_vertical_bounds()

	resolution_changed.emit()


# TODO Can't hint it, the return is a nullable Color
static func _get_map_default_fill_color(map_type: int, map_index: int):
	var config = _map_types[map_type].default_fill
	if config == null:
		# No fill required
		return null
	if typeof(config) == TYPE_COLOR:
		# Standard color fill
		return config
	assert(typeof(config) == TYPE_ARRAY)
	assert(len(config) == 2)
	if map_index == 0:
		# First map has this config
		return config[0]
	# Others have this
	return config[1]


# Gets the height at the given cell position.
# This height is raw and doesn't account for scaling of the terrain node.
# This function is relatively slow due to locking, so don't use it to fetch large areas.
func get_height_at(x: int, y: int) -> float:
	# Height data must be loaded in RAM
	var im := get_image(CHANNEL_HEIGHT)
	assert(im != null)
	match im.get_format():
		Image.FORMAT_RF:
			return HT_Util.get_pixel_clamped(im, x, y).r
		Image.FORMAT_RGB8:
			return decode_height_from_rgb8_unorm(HT_Util.get_pixel_clamped(im, x, y))
		_:
			_logger.error(str("Invalid heigthmap format ", im.get_format()))
			return 0.0


# Gets the height at the given floating-point cell position.
# This height is raw and doesn't account for scaling of the terrain node.
# This function is relatively slow due to locking, so don't use it to fetch large areas
func get_interpolated_height_at(pos: Vector3) -> float:
	# Height data must be loaded in RAM
	var im := get_image(CHANNEL_HEIGHT)
	assert(im != null)
	var map_type = _map_types[CHANNEL_HEIGHT]
	assert(im.get_format() == map_type.texture_format)

	# The function takes a Vector3 for convenience so it's easier to use in 3D scripting
	var x0 := int(floorf(pos.x))
	var y0 := int(floorf(pos.z))

	var xf := pos.x - x0
	var yf := pos.z - y0
	
	var h00 : float
	var h10 : float
	var h01 : float
	var h11 : float
	
	match im.get_format():
		Image.FORMAT_RF:
			h00 = HT_Util.get_pixel_clamped(im, x0, y0).r
			h10 = HT_Util.get_pixel_clamped(im, x0 + 1, y0).r
			h01 = HT_Util.get_pixel_clamped(im, x0, y0 + 1).r
			h11 = HT_Util.get_pixel_clamped(im, x0 + 1, y0 + 1).r
		
		Image.FORMAT_RGB8:
			var c00 := HT_Util.get_pixel_clamped(im, x0, y0)
			var c10 := HT_Util.get_pixel_clamped(im, x0 + 1, y0)
			var c01 := HT_Util.get_pixel_clamped(im, x0, y0 + 1)
			var c11 := HT_Util.get_pixel_clamped(im, x0 + 1, y0 + 1)

			h00 = decode_height_from_rgb8_unorm(c00)
			h10 = decode_height_from_rgb8_unorm(c10)
			h01 = decode_height_from_rgb8_unorm(c01)
			h11 = decode_height_from_rgb8_unorm(c11)
		
		_:
			_logger.error(str("Invalid heightmap format ", im.get_format()))
			return 0.0

	# Bilinear filter
	var h := lerpf(lerpf(h00, h10, xf), lerpf(h01, h11, xf), yf)
	return h

# Gets all heights within the given rectangle in cells.
# This height is raw and doesn't account for scaling of the terrain node.
# Data is returned as a PackedFloat32Array.
func get_heights_region(x0: int, y0: int, w: int, h: int) -> PackedFloat32Array:
	var im = get_image(CHANNEL_HEIGHT)
	assert(im != null)
	
	var min_x := clampi(x0, 0, im.get_width())
	var min_y := clampi(y0, 0, im.get_height())
	var max_x := clampi(x0 + w, 0, im.get_width() + 1)
	var max_y := clampi(y0 + h, 0, im.get_height() + 1)

	var heights := PackedFloat32Array()

	var area := (max_x - min_x) * (max_y - min_y)
	if area == 0:
		_logger.debug("Empty heights region!")
		return heights

	heights.resize(area)

	var i := 0
	
	if im.get_format() == Image.FORMAT_RF or im.get_format() == Image.FORMAT_RH:
		for y in range(min_y, max_y):
			for x in range(min_x, max_x):
				heights[i] = im.get_pixel(x, y).r
				i += 1
				
	elif im.get_format() == Image.FORMAT_RGB8:
		for y in range(min_y, max_y):
			for x in range(min_x, max_x):
				var c := im.get_pixel(x, y)
				heights[i] = decode_height_from_rgb8_unorm(c)
				i += 1
	
	else:
		_logger.error(str("Unknown heightmap format! ", im.get_format()))

	return heights


# Checks that all images stored in maps have the correct format.
# May be called in case someone uses `copy_from()` to update images and uses wrong formats.
func check_images():
	var errors := PackedStringArray()
	
	for map_type in _maps.size():
		var map_list : Array = _maps[map_type]

		for map_index in map_list.size():
			var map : HT_Map = map_list[map_index]
			var im := map.image

			if im == null:
				continue
			
			if im.get_width() != im.get_height():
				errors.append(
					str("Terrain image ", get_map_debug_name(map_type, map_index), 
					" is not square (", im.get_width(), "x", im.get_height(), "). ",
					"Did you modify it directly?"))

			elif im.get_width() != get_resolution():
				errors.append(
					str("Terrain image ", get_map_debug_name(map_type, map_index), 
					" resolution (", im.get_width(), ") does not match the expected ",
					"resolution (", get_resolution(), "). Did you modify it directly?"))

			var expected_format : int = _map_types[map_type].texture_format
			if im.get_format() != expected_format:
				errors.append(
					str("Terrain image ", get_map_debug_name(map_type, map_index), 
					" has an unexpected format (expected ", expected_format, ", found ", 
					im.get_format(), "). Did you modify it directly?"))
	
	assert(errors.size() == 0, " ".join(errors))


# Gets all heights as an array indexed as [x + y * width].
# This height is raw and doesn't account for scaling of the terrain node.
func get_all_heights() -> PackedFloat32Array:
	var im = get_image(CHANNEL_HEIGHT)
	assert(im != null)
	if im.get_format() == Image.FORMAT_RF:
		return im.get_data().to_float32_array()
	else:
		return get_heights_region(0, 0, _resolution, _resolution)


# Call this function after you end modifying a map.
# It will commit the change to the GPU so the change will take effect.
# In the editor, it will also mark the map as modified so it will be saved when needed.
# Finally, it will emit `region_changed`, 
# which allows other systems to catch up (like physics or grass)
#
# p_rect:
#     modified area.
#
# map_type:
#    which kind of map changed, see CHANNEL_* constants
#
# index:
#    index of the map that changed
#
# p_upload_to_texture:
#     the modified region will be copied from the map image to the texture.
#     If the change already occurred on GPU, you may set this to false.
#
# p_update_vertical_bounds:
#     if the modified map is the heightmap, vertical bounds will be updated.
#
func notify_region_change(
	p_rect: Rect2,
	p_map_type: int,
	p_index := 0,
	p_upload_to_texture := true,
	p_update_vertical_bounds := true):
	
	assert(p_map_type >= 0 and p_map_type < CHANNEL_COUNT)
	
	var min_x := int(p_rect.position.x)
	var min_y := int(p_rect.position.y)
	var size_x := int(p_rect.size.x)
	var size_y := int(p_rect.size.y)
	
	if p_map_type == CHANNEL_HEIGHT and p_update_vertical_bounds:
		assert(p_index == 0)
		_update_vertical_bounds(min_x, min_y, size_x, size_y)
	
	if p_upload_to_texture:
		_upload_region(p_map_type, p_index, min_x, min_y, size_x, size_y)
	
	_maps[p_map_type][p_index].modified = true

	region_changed.emit(min_x, min_y, size_x, size_y, p_map_type)
	changed.emit()


func notify_full_change():
	for maptype in range(CHANNEL_COUNT):
		# Ignore normals because they get updated along with heights
		if maptype == CHANNEL_NORMAL:
			continue
		var maps = _maps[maptype]
		for index in len(maps):
			notify_region_change(Rect2(0, 0, _resolution, _resolution), maptype, index)


func _edit_set_disable_apply_undo(e: bool):
	_edit_disable_apply_undo = e


func _edit_apply_undo(undo_data: Dictionary, image_cache: HT_ImageFileCache):
	if _edit_disable_apply_undo:
		return

	var chunk_positions: Array = undo_data["chunk_positions"]
	var map_infos: Array = undo_data["maps"]
	var chunk_size: int = undo_data["chunk_size"]

	_logger.debug(str("Applying ", len(chunk_positions), " undo/redo chunks"))

	# Validate input

	for map_info in map_infos:
		assert(map_info.map_type >= 0 and map_info.map_type < CHANNEL_COUNT)
		assert(len(map_info.chunks) == len(chunk_positions))
		for im_cache_id in map_info.chunks:
			assert(typeof(im_cache_id) == TYPE_INT)

	# Apply for each map
	for map_info in map_infos:
		var map_type := map_info.map_type as int
		var map_index := map_info.map_index as int
		
		var regions_changed := []
		
		for chunk_index in len(map_info.chunks):
			var cpos : Vector2 = chunk_positions[chunk_index]
			var cpos_x := int(cpos.x)
			var cpos_y := int(cpos.y)
	
			var min_x := cpos_x * chunk_size
			var min_y := cpos_y * chunk_size
			var max_x := min_x + chunk_size
			var max_y := min_y + chunk_size
	
			var data_id = map_info.chunks[chunk_index]
			var data := image_cache.load_image(data_id)
			assert(data != null)
	
			var dst_image := get_image(map_type, map_index)
			assert(dst_image != null)
	
			if _map_types[map_type].authored:
				#_logger.debug(str("Apply undo chunk ", cpos, " to ", Vector2(min_x, min_y)))
				var src_rect := Rect2i(0, 0, data.get_width(), data.get_height())
				dst_image.blit_rect(data, src_rect, Vector2i(min_x, min_y))
			else:
				_logger.error(
					str("Channel ", map_type, " is a calculated channel!, no undo on this one"))
	
			# Defer this to a second pass,
			# otherwise it causes order-dependent artifacts on the normal map
			regions_changed.append([
				Rect2(min_x, min_y, max_x - min_x, max_y - min_y), map_type, map_index])

		for args in regions_changed:
			notify_region_change(args[0], args[1], args[2])


#static func _debug_dump_heightmap(src: Image, fpath: String):
#	var im = Image.new()
#	im.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGB8)
#	im.lock()
#	src.lock()
#	for y in im.get_height():
#		for x in im.get_width():
#			var col = src.get_pixel(x, y)
#			var c = col.r - floor(col.r)
#			im.set_pixel(x, y, Color(c, 0.0, 0.0, 1.0))
#	im.unlock()
#	src.unlock()
#	im.save_png(fpath)


# TODO Support map indexes
# Used for undoing full-terrain changes
func _edit_apply_maps_from_file_cache(image_file_cache: HT_ImageFileCache, map_ids: Dictionary):
	if _edit_disable_apply_undo:
		return
	for map_type in map_ids:
		var id = map_ids[map_type]
		var src_im := image_file_cache.load_image(id)
		if src_im == null:
			continue
		var index := 0
		var dst_im := get_image(map_type, index)
		var rect := Rect2i(0, 0, src_im.get_height(), src_im.get_height())
		dst_im.blit_rect(src_im, rect, Vector2i())
		notify_region_change(rect, map_type, index)


func _upload_channel(channel: int, index: int):
	_upload_region(channel, index, 0, 0, _resolution, _resolution)


func _upload_region(channel: int, index: int, min_x: int, min_y: int, size_x: int, size_y: int):
	#_logger.debug("Upload ", min_x, ", ", min_y, ", ", size_x, "x", size_y)
	#var time_before = OS.get_ticks_msec()

	var map : HT_Map = _maps[channel][index]

	var image := map.image
	assert(image != null)
	assert(size_x > 0 and size_y > 0)

	# TODO Actually, I think the input params should be valid in the first place...
	if min_x < 0:
		min_x = 0
	if min_y < 0:
		min_y = 0
	if min_x + size_x > image.get_width():
		size_x = image.get_width() - min_x
	if min_y + size_y > image.get_height():
		size_y = image.get_height() - min_y
	if size_x <= 0 or size_y <= 0:
		return

	var texture := map.texture

	if texture == null or not (texture is ImageTexture):
		# The texture doesn't exist yet in an editable format
		if texture != null and not (texture is ImageTexture):
			_logger.debug(str(
				"_upload_region was used but the texture isn't an ImageTexture. ",\
				"The map ", channel, "[", index, "] will be reuploaded entirely."))
		else:
			_logger.debug(str(
				"_upload_region was used but the texture is not created yet. ",\
				"The map ", channel, "[", index, "] will be uploaded entirely."))

		map.texture = ImageTexture.create_from_image(image)

		# Need to notify because other systems may want to grab the new texture object
		map_changed.emit(channel, index)

	# TODO Unfortunately Texture2D.get_size() wasn't updated to use Vector2i in Godot 4
	elif Vector2i(texture.get_size()) != image.get_size():
		_logger.debug(str(
			"_upload_region was used but the image size is different. ",\
			"The map ", channel, "[", index, "] will be reuploaded entirely."))

		map.texture = ImageTexture.create_from_image(image)

		# Since Godot 4, need to notify because other systems may want to grab the new texture
		# object. In Godot 3 it wasn't necessary because we were able to resize a texture without
		# having to recreate it from scratch...
		map_changed.emit(channel, index)

	else:
		HT_Util.update_texture_partial(texture, image, 
			Rect2i(min_x, min_y, size_x, size_y), Vector2i(min_x, min_y))

	#_logger.debug(str("Channel updated ", channel))

	#var time_elapsed = OS.get_ticks_msec() - time_before
	#_logger.debug(str("Texture upload time: ", time_elapsed, "ms"))


# Gets how many instances of a given map are present in the terrain data.
# A return value of 0 means there is no such map, and querying for it might cause errors.
func get_map_count(map_type: int) -> int:
	if map_type < len(_maps):
		return len(_maps[map_type])
	return 0


# TODO Deprecated
func _edit_add_detail_map():
	return _edit_add_map(CHANNEL_DETAIL)


# TODO Deprecated
func _edit_remove_detail_map(index):
	_edit_remove_map(CHANNEL_DETAIL, index)


func _edit_add_map(map_type: int) -> int:
	# TODO Check minimum and maximum instances of a given map
	_logger.debug(str("Adding map of type ", get_channel_name(map_type)))
	while map_type >= len(_maps):
		_maps.append([])
	var maps = _maps[map_type]
	var map = HT_Map.new(_get_free_id(map_type))
	map.image = Image.create(_resolution, _resolution, false, get_channel_format(map_type))
	var index = len(maps)
	var default_color = _get_map_default_fill_color(map_type, index)
	if default_color != null:
		map.image.fill(default_color)
	maps.append(map)
	map_added.emit(map_type, index)
	return index


func _edit_insert_map_from_image_cache(map_type: int, index: int, image_cache, image_id: int):
	if _edit_disable_apply_undo:
		return
	_logger.debug(str("Adding map of type ", get_channel_name(map_type), 
		" from an image at index ", index))
	while map_type >= len(_maps):
		_maps.append([])
	var maps = _maps[map_type]
	var map := HT_Map.new(_get_free_id(map_type))
	map.image = image_cache.load_image(image_id)
	maps.insert(index, map)
	map_added.emit(map_type, index)


func _edit_remove_map(map_type: int, index: int):
	# TODO Check minimum and maximum instances of a given map
	_logger.debug(str("Removing map ", get_channel_name(map_type), " at index ", index))
	var maps : Array = _maps[map_type]
	maps.remove_at(index)
	map_removed.emit(map_type, index)


func _get_free_id(map_type: int) -> int:
	var maps = _maps[map_type]
	var id = 0
	while _get_map_by_id(map_type, id) != null:
		id += 1
	return id


func _get_map_by_id(map_type: int, id: int) -> HT_Map:
	var maps = _maps[map_type]
	for map in maps:
		if map.id == id:
			return map
	return null


func get_image(map_type: int, index := 0) -> Image:
	var maps = _maps[map_type]
	return maps[index].image


func get_texture(map_type: int, index := 0, writable := false) -> Texture:
	# TODO Split into `get_texture` and `get_writable_texture`?
	
	var maps : Array = _maps[map_type]
	var map : HT_Map = maps[index]

	if map.image != null:
		if map.texture == null:
			_upload_channel(map_type, index)
		elif writable and not (map.texture is ImageTexture):
			_upload_channel(map_type, index)
	else:
		if writable:
			_logger.warn(str("Requested writable terrain texture ",
				get_map_debug_name(map_type, index), ", but it's not available in this context"))

	return map.texture


func has_texture(map_type: int, index: int) -> bool:
	var maps = _maps[map_type]
	return index < len(maps)


func get_aabb() -> AABB:
	# TODO Why subtract 1? I forgot
	# TODO Optimize for full region, this is actually quite costy
	return get_region_aabb(0, 0, _resolution - 1, _resolution - 1)


# Not so useful in itself, but GDScript is slow,
# so I needed it to speed up the LOD hack I had to do to take height into account
func get_point_aabb(cell_x: int, cell_y: int) -> Vector2:
	assert(typeof(cell_x) == TYPE_INT)
	assert(typeof(cell_y) == TYPE_INT)

	var cx = cell_x / VERTICAL_BOUNDS_CHUNK_SIZE
	var cy = cell_y / VERTICAL_BOUNDS_CHUNK_SIZE

	if cx < 0:
		cx = 0
	if cy < 0:
		cy = 0
	if cx >= _chunked_vertical_bounds.get_width():
		cx = _chunked_vertical_bounds.get_width() - 1
	if cy >= _chunked_vertical_bounds.get_height():
		cy = _chunked_vertical_bounds.get_height() - 1

	var b := _chunked_vertical_bounds.get_pixel(cx, cy)
	return Vector2(b.r, b.g)


func get_region_aabb(origin_in_cells_x: int, origin_in_cells_y: int,
	size_in_cells_x: int, size_in_cells_y: int) -> AABB:

	assert(typeof(origin_in_cells_x) == TYPE_INT)
	assert(typeof(origin_in_cells_y) == TYPE_INT)
	assert(typeof(size_in_cells_x) == TYPE_INT)
	assert(typeof(size_in_cells_y) == TYPE_INT)

	# Get info from cached vertical bounds,
	# which is a lot faster than directly fetching heights from the map.
	# It's not 100% accurate, but enough for culling use case if chunk size is decently chosen.

	var cmin_x := origin_in_cells_x / VERTICAL_BOUNDS_CHUNK_SIZE
	var cmin_y := origin_in_cells_y / VERTICAL_BOUNDS_CHUNK_SIZE

	var cmax_x := (origin_in_cells_x + size_in_cells_x - 1) / VERTICAL_BOUNDS_CHUNK_SIZE + 1
	var cmax_y := (origin_in_cells_y + size_in_cells_y - 1) / VERTICAL_BOUNDS_CHUNK_SIZE + 1

	cmin_x = clampi(cmin_x, 0, _chunked_vertical_bounds.get_width() - 1)
	cmin_y = clampi(cmin_y, 0, _chunked_vertical_bounds.get_height() - 1)
	cmax_x = clampi(cmax_x, 0, _chunked_vertical_bounds.get_width())
	cmax_y = clampi(cmax_y, 0, _chunked_vertical_bounds.get_height())

	var min_height := _chunked_vertical_bounds.get_pixel(cmin_x, cmin_y).r
	var max_height = min_height

	for y in range(cmin_y, cmax_y):
		for x in range(cmin_x, cmax_x):
			var b = _chunked_vertical_bounds.get_pixel(x, y)
			min_height = minf(b.r, min_height)
			max_height = maxf(b.g, max_height)

	var aabb = AABB()
	aabb.position = Vector3(origin_in_cells_x, min_height, origin_in_cells_y)
	aabb.size = Vector3(size_in_cells_x, max_height - min_height, size_in_cells_y)

	return aabb


func _update_all_vertical_bounds():
	var csize_x := _resolution / VERTICAL_BOUNDS_CHUNK_SIZE
	var csize_y := _resolution / VERTICAL_BOUNDS_CHUNK_SIZE
	_logger.debug(str("Updating all vertical bounds... (", csize_x , "x", csize_y, " chunks)"))
	_chunked_vertical_bounds = Image.create(csize_x, csize_y, false, Image.FORMAT_RGF)
	_update_vertical_bounds(0, 0, _resolution - 1, _resolution - 1)


func update_vertical_bounds(p_rect: Rect2):
	var min_x := int(p_rect.position.x)
	var min_y := int(p_rect.position.y)
	var size_x := int(p_rect.size.x)
	var size_y := int(p_rect.size.y)

	_update_vertical_bounds(min_x, min_y, size_x, size_y)


func _update_vertical_bounds(origin_in_cells_x: int, origin_in_cells_y: int, \
							size_in_cells_x: int, size_in_cells_y: int):

	var cmin_x := origin_in_cells_x / VERTICAL_BOUNDS_CHUNK_SIZE
	var cmin_y := origin_in_cells_y / VERTICAL_BOUNDS_CHUNK_SIZE

	var cmax_x := (origin_in_cells_x + size_in_cells_x - 1) / VERTICAL_BOUNDS_CHUNK_SIZE + 1
	var cmax_y := (origin_in_cells_y + size_in_cells_y - 1) / VERTICAL_BOUNDS_CHUNK_SIZE + 1

	cmin_x = clampi(cmin_x, 0, _chunked_vertical_bounds.get_width() - 1)
	cmin_y = clampi(cmin_y, 0, _chunked_vertical_bounds.get_height() - 1)
	cmax_x = clampi(cmax_x, 0, _chunked_vertical_bounds.get_width())
	cmax_y = clampi(cmax_y, 0, _chunked_vertical_bounds.get_height())

	# Note: chunks in _chunked_vertical_bounds share their edge cells and
	# have an actual size of chunk size + 1.
	var chunk_size_x := VERTICAL_BOUNDS_CHUNK_SIZE + 1
	var chunk_size_y := VERTICAL_BOUNDS_CHUNK_SIZE + 1
	
	for y in range(cmin_y, cmax_y):
		var pmin_y := y * VERTICAL_BOUNDS_CHUNK_SIZE

		for x in range(cmin_x, cmax_x):
			var pmin_x := x * VERTICAL_BOUNDS_CHUNK_SIZE
			var b = _compute_vertical_bounds_at(pmin_x, pmin_y, chunk_size_x, chunk_size_y)
			_chunked_vertical_bounds.set_pixel(x, y, Color(b.x, b.y, 0))


func _compute_vertical_bounds_at(
	origin_x: int, origin_y: int, size_x: int, size_y: int) -> Vector2:
	
	var heights := get_image(CHANNEL_HEIGHT)
	assert(heights != null)
	match heights.get_format():
		Image.FORMAT_RF:
			return _get_heights_range_f(heights, Rect2i(origin_x, origin_y, size_x, size_y))
		Image.FORMAT_RGB8:
			return _get_heights_range_rgb8(heights, Rect2i(origin_x, origin_y, size_x, size_y))
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
	
	var min_height := decode_height_from_rgb8_unorm(im.get_pixel(min_x, min_y))
	var max_height := min_height

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			var h := decode_height_from_rgb8_unorm(im.get_pixel(x, y))
			min_height = minf(h, min_height)
			max_height = maxf(h, max_height)

	return Vector2(min_height, max_height)


static func _get_heights_range_f(im: Image, rect: Rect2i) -> Vector2:
	assert(im.get_format() == Image.FORMAT_RF)
	
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


func save_data(data_dir: String) -> bool:
	_logger.debug("Saving terrain data...")
	
	_locked = true

	_save_metadata(data_dir.path_join(META_FILENAME))

	var map_count = _get_total_map_count()

	var all_succeeded = true

	var pi = 0
	for map_type in CHANNEL_COUNT:
		var maps : Array = _maps[map_type]

		for index in len(maps):
			var map : HT_Map = maps[index]
			if not map.modified:
				_logger.debug(str(
					"Skipping non-modified ", get_map_debug_name(map_type, index)))
				continue

			_logger.debug(str("Saving map ", get_map_debug_name(map_type, index),
				" as ", _get_map_filename(map_type, index), "..."))

			all_succeeded = all_succeeded and _save_map(data_dir, map_type, index)

			map.modified = false
			pi += 1
	
	# TODO Cleanup unused map files?

	# TODO In editor, trigger reimport on generated assets
	_locked = false

	return all_succeeded


func _is_any_map_modified() -> bool:
	for maplist in _maps:
		for map in maplist:
			if map.modified:
				return true
	return false


func _get_total_map_count() -> int:
	var s = 0
	for maps in _maps:
		s += len(maps)
	return s


func _load_metadata(path: String):
	var f = FileAccess.open(path, FileAccess.READ)
	assert(f != null)
	var text = f.get_as_text()
	f = null # close file
	var json = JSON.new()
	var json_err := json.parse(text)
	# Careful, `assert` is stripped in release exports, including its argument expression...
	# See https://github.com/godotengine/godot-proposals/issues/502
	assert(json_err == OK)
	_deserialize_metadata(json.data)


func _save_metadata(path: String):
	var d = _serialize_metadata()
	var text = JSON.stringify(d, "\t", true)
	var f = FileAccess.open(path, FileAccess.WRITE)
	var err = f.get_error()
	assert(err == OK)
	f.store_string(text)


func _serialize_metadata() -> Dictionary:
	var data := []
	data.resize(len(_maps))

	for i in range(len(_maps)):
		var maps = _maps[i]
		var maps_data := []

		for j in range(len(maps)):
			var map : HT_Map = maps[j]
			maps_data.append({ "id": map.id })

		data[i] = maps_data

	return {
		"version": META_VERSION,
		"maps": data
	}


# Parse metadata that we'll then use to load the actual terrain
# (How many maps, which files to load etc...)
func _deserialize_metadata(dict: Dictionary) -> bool:
	if not dict.has("version"):
		_logger.error("Terrain metadata has no version")
		return false

	if dict.version != META_VERSION:
		_logger.error("Terrain metadata version mismatch. Got {0}, expected {1}" \
			.format([dict.version, META_VERSION]))
		return false

	var data = dict["maps"]
	assert(len(data) <= len(_maps))

	for i in len(data):
		var maps = _maps[i]

		var maps_data = data[i]
		if len(maps) != len(maps_data):
			maps.resize(len(maps_data))

		for j in len(maps):
			var map = maps[j]
			# Cast because the data comes from json, where every number is double
			var id := int(maps_data[j].id)
			if map == null:
				map = HT_Map.new(id)
				maps[j] = map
			else:
				map.id = id

	return true


func load_data(dir_path: String, 
	# Same as default in ResourceLoader.load()
	resource_loader_cache_mode := ResourceLoader.CACHE_MODE_REUSE):
	
	_locked = true

	_load_metadata(dir_path.path_join(META_FILENAME))

	_logger.debug("Loading terrain data...")

	var channel_instance_sum = _get_total_map_count()
	var pi = 0
	
	# Note: if we loaded all maps at once before uploading them to VRAM,
	# it would take a lot more RAM than if we load them one by one
	for map_type in len(_maps):
		var maps = _maps[map_type]

		for index in len(maps):
			_logger.debug(str("Loading map ", get_map_debug_name(map_type, index),
				" from ", _get_map_filename(map_type, index), "..."))

			_load_map(dir_path, map_type, index, resource_loader_cache_mode)

			# A map that was just loaded is considered not modified yet
			maps[index].modified = false

			pi += 1

	_logger.debug("Calculating vertical bounds...")
	_update_all_vertical_bounds()

	_logger.debug("Notify resolution change...")

	_locked = false
	resolution_changed.emit()


# Reloads the entire terrain from files, disregarding cached resources.
# This could be useful to reload a terrain while playing the game. You can do some edits in the
# editor, save the terrain and then reload in-game.
func reload():
	_logger.debug("Reloading terrain data...")
	var dir_path := resource_path.get_base_dir()
	load_data(dir_path, ResourceLoader.CACHE_MODE_IGNORE)
	_logger.debug("Reloading terrain data done")
	
	# Debug
#	var heightmap := get_image(CHANNEL_HEIGHT, 0)
#	var im = Image.create(heightmap.get_width(), heightmap.get_height(), false, Image.FORMAT_RGB8)
#	for y in heightmap.get_height():
#		for x in heightmap.get_width():
#			var h := heightmap.get_pixel(x, y).r * 0.1
#			var g := h - floorf(h)
#			im.set_pixel(x, y, Color(g, g, g, 1.0))
#	im.save_png("local_tests/debug_data/reloaded_heightmap.png")


func get_data_dir() -> String:
	# The HTerrainData resource represents the metadata and entry point for Godot.
	# It should be placed within a folder dedicated for terrain storage.
	# Other heavy data such as maps are stored next to that file.
	return resource_path.get_base_dir()


func _save_map(dir_path: String, map_type: int, index: int) -> bool:
	var map : HT_Map = _maps[map_type][index]
	var im := map.image
	if im == null:
		var tex := map.texture
		if tex != null:
			_logger.debug(str("Image not found for map ", map_type, ", downloading from VRAM"))
			im = tex.get_image()
		else:
			_logger.debug(str("No data in map ", map_type, "[", index, "]"))
			# This data doesn't have such map
			return true

	# The function says "absolute" but in reality it accepts paths like `res://x`,
	# which from a user standpoint are not absolute. Also, `FileAccess.file_exists` exists but
	# isn't named "absolute" :shrug:
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_absolute(dir_path)
		if err != OK:
			_logger.error("Could not create directory '{0}', error {1}" \
				.format([dir_path, HT_Errors.get_message(err)]))
		return false

	var fpath := dir_path.path_join(_get_map_filename(map_type, index))

	return _save_map_image(fpath, map_type, im)


func _save_map_image(fpath: String, map_type: int, im: Image) -> bool:
	if _channel_can_be_saved_as_png(map_type):
		fpath += ".png"
		var err := im.save_png(fpath)
		if err != OK:
			_logger.error("Could not save '{0}', error {1}" \
				.format([fpath, HT_Errors.get_message(err)]))
			return false
		_try_write_default_import_options(fpath, map_type, _logger)

	else:
		fpath += ".res"
		var err := ResourceSaver.save(im, fpath)
		if err != OK:
			_logger.error("Could not save '{0}', error {1}" \
				.format([fpath, HT_Errors.get_message(err)]))
			return false

	return true


static func _try_write_default_import_options(
	fpath: String, channel: int, logger: HT_Logger.HT_LoggerBase):
	
	var imp_fpath := fpath + ".import"
	if FileAccess.file_exists(imp_fpath):
		# Already exists
		return
	
	var map_info = _map_types[channel]
	var srgb: bool = map_info.srgb
	
	var defaults : Dictionary
	
	if channel == CHANNEL_HEIGHT:
		defaults = {
			"remap": {
				# Have the heightmap editable as an image by default
				"importer": "image",
				"type": "Image"
			},
			"deps": {
				"source_file": fpath
			}
		}
	
	else:
		defaults = {
			"remap": {
				"importer": "texture",
				"type": "CompressedTexture2D"
			},
			"deps": {
				"source_file": fpath
			},
			"params": {
				# Use lossless compression.
				# Lossy ruins quality and makes the editor choke on big textures.
				# TODO I would have used ImageTexture.COMPRESS_LOSSLESS,
				# but apparently what is saved in the .import file does not match,
				# and rather corresponds TO THE UI IN THE IMPORT DOCK :facepalm:
				"compress/mode": 0,
				
				"compress/hdr_compression": 0,
				"compress/normal_map": 0,
				# No mipmaps
				"mipmaps/limit": 0,
				
				# Most textures aren't color.
				# Same here, this is mapping something from the import dock UI,
				# and doesn't have any enum associated, just raw numbers in C++ code...
				# 0 = "disabled", 1 = "enabled", 2 = "detect"
				"flags/srgb": 2 if srgb else 0,
				
				# No need for this, the meaning of alpha is never transparency
				"process/fix_alpha_border": false,
				
				# Don't try to be smart.
				# This can actually overwrite the settings with defaults...
				# https://github.com/godotengine/godot/issues/24220
				"detect_3d/compress_to": 0,
			}
		}

	HT_Util.write_import_file(defaults, imp_fpath, logger)


func _load_map(dir: String, map_type: int, index: int, resource_loader_cache_mode : int) -> bool:
	var fpath := dir.path_join(_get_map_filename(map_type, index))

	# Maps must be configured before being loaded
	var map : HT_Map = _maps[map_type][index]
	# while len(_maps) <= map_type:
	# 	_maps.append([])
	# while len(_maps[map_type]) <= index:
	# 	_maps[map_type].append(null)
	# var map = _maps[map_type][index]
	# if map == null:
	# 	map = Map.new()
	# 	_maps[map_type][index] = map

	if _channel_can_be_saved_as_png(map_type):
		fpath += ".png"
	else:
		fpath += ".res"
	
	var tex = ResourceLoader.load(fpath, "", resource_loader_cache_mode)
	
	var must_load_image_in_editor := true
	
	# Short-term compatibility with RGB8 encoding from the godot4 branch
	if Engine.is_editor_hint() and tex == null and map_type == CHANNEL_HEIGHT:
		var legacy_fpath := fpath.get_basename() + ".png"
		var temp = ResourceLoader.load(legacy_fpath, "", resource_loader_cache_mode)
		if temp != null:
			if temp is Texture2D:
				temp = temp.get_image()
			if temp is Image:
				if temp.get_format() == Image.FORMAT_RGB8:
					_logger.warn(str(
						"Found a heightmap using legacy RGB8 format. It will be converted to RF. ",
						"You may want to remove the old file: {0}").format([fpath]))
					tex = convert_heightmap_to_float(temp, _logger)
					_save_map_image(fpath.get_basename(), map_type, tex)

	if tex != null and tex is Image:
		# The texture is imported as Image,
		# perhaps the user wants it to be accessible from RAM in game.
		_logger.debug("Map {0} is imported as Image. An ImageTexture will be generated." \
				.format([get_map_debug_name(map_type, index)]))
		map.image = tex
		tex = ImageTexture.create_from_image(map.image)
		must_load_image_in_editor = false
	
	var texture_changed : bool = (tex != map.texture)
	map.texture = tex

	if Engine.is_editor_hint():
		if must_load_image_in_editor:
			# But in the editor we want textures to be editable,
			# so we have to automatically load the data also in RAM
			if map.image == null:
				map.image = Image.load_from_file(fpath)
			else:
				map.image.load(fpath)
		_ensure_map_format(map.image, map_type, index)
	
	if map_type == CHANNEL_HEIGHT:
		_resolution = map.image.get_width()

	# Initially added to support reloading of an existing terrain (otherwise it's pointless to emit
	# during scene loading when the resource isn't assigned yet)
	if texture_changed:
		map_changed.emit(map_type, index)

	return true


func _ensure_map_format(im: Image, map_type: int, index: int):
	var format := im.get_format()
	var expected_format : int = _map_types[map_type].texture_format
	if format != expected_format:
		_logger.warn("Map {0} loaded as format {1}, expected {2}. Will be converted." \
			.format([get_map_debug_name(map_type, index), format, expected_format]))
		im.convert(expected_format)


# Imports images into the terrain data by converting them to the internal format.
# It is possible to omit some of them, in which case those already setup will be used.
# This function is quite permissive, and will only fail if there is really no way to import.
# It may involve cropping, so preliminary checks should be done to inform the user.
#
# TODO Plan is to make this function threaded, in case import takes too long.
# So anything that could mess with the main thread should be avoided.
# Eventually, it would be temporarily removed from the terrain node to work 
# in isolation during import.
func _edit_import_maps(input: Dictionary) -> bool:
	assert(typeof(input) == TYPE_DICTIONARY)

	if input.has(CHANNEL_HEIGHT):
		var params = input[CHANNEL_HEIGHT]
		if not _import_heightmap(
			params.path, params.min_height, params.max_height, params.big_endian, params.bit_depth):
			return false

	# TODO Import indexed maps?
	var maptypes := [CHANNEL_COLOR, CHANNEL_SPLAT]

	for map_type in maptypes:
		if input.has(map_type):
			var params = input[map_type]
			if not _import_map(map_type, params.path):
				return false

	return true


# Provided an arbitrary width and height,
# returns the closest size the terrain actuallysupports
static func get_adjusted_map_size(width: int, height: int) -> int:
	var width_po2 = HT_Util.next_power_of_two(width - 1) + 1
	var height_po2 = HT_Util.next_power_of_two(height - 1) + 1
	var size_po2 = mini(width_po2, height_po2)
	size_po2 = clampi(size_po2, MIN_RESOLUTION, MAX_RESOLUTION)
	return size_po2


func _import_heightmap(fpath: String, min_y: float, max_y: float, big_endian: bool, bit_depth: int) -> bool:
	var ext := fpath.get_extension().to_lower()

	if ext == "png":
		# Godot can only load 8-bit PNG,
		# so we have to bring it back to float in the wanted range

		var src_image := Image.load_from_file(fpath)
		# TODO No way to access the error code?
		if src_image == null:
			return false

		var res := get_adjusted_map_size(src_image.get_width(), src_image.get_height())
		if res != src_image.get_width():
			src_image.crop(res, res)

		_locked = true

		_logger.debug(str("Resizing terrain to ", res, "x", res, "..."))
		resize(src_image.get_width(), false, Vector2())

		var im := get_image(CHANNEL_HEIGHT)
		assert(im != null)

		var hrange := max_y - min_y

		var width := mini(im.get_width(), src_image.get_width())
		var height := mini(im.get_height(), src_image.get_height())

		_logger.debug("Converting to internal format...")

		# Convert to internal format with range scaling
		match im.get_format():
			Image.FORMAT_RF:
				for y in width:
					for x in height:
						var gs := src_image.get_pixel(x, y).r
						var h := min_y + hrange * gs
						im.set_pixel(x, y, Color(h, h, h))
			Image.FORMAT_RGB8:
				for y in width:
					for x in height:
						var gs := src_image.get_pixel(x, y).r
						var h := min_y + hrange * gs
						im.set_pixel(x, y, encode_height_to_rgb8_unorm(h))
			_:
				_logger.error(str("Invalid heightmap format ", im.get_format()))
	
	elif ext == "exr":
		var src_image := Image.load_from_file(fpath)
		# TODO No way to access the error code?
		if src_image == null:
			return false

		var res := get_adjusted_map_size(src_image.get_width(), src_image.get_height())
		if res != src_image.get_width():
			src_image.crop(res, res)

		_locked = true

		_logger.debug(str("Resizing terrain to ", res, "x", res, "..."))
		resize(src_image.get_width(), false, Vector2())

		var im := get_image(CHANNEL_HEIGHT)
		assert(im != null)

		_logger.debug("Converting to internal format...")
		
		match im.get_format():
			Image.FORMAT_RF:
				# See https://github.com/Zylann/godot_heightmap_plugin/issues/34
				# Godot can load EXR but it always makes them have at least 3-channels.
				# Heightmaps need only one, so we have to get rid of 2.
				var height_format = _map_types[CHANNEL_HEIGHT].texture_format
				src_image.convert(height_format)
				im.blit_rect(src_image, Rect2i(0, 0, res, res), Vector2i())
			
			Image.FORMAT_RGB8:
				convert_float_heightmap_to_rgb8(src_image, im)
				
			_:
				_logger.error(str("Invalid heightmap format ", im.get_format()))

	elif ext == "raw":
		# RAW files don't contain size, so we take the user's bit depth import choice.
		# We also need to bring it back to float in the wanted range.

		var f := FileAccess.open(fpath, FileAccess.READ)
		if f == null:
			return false

		var file_len := f.get_length()
		var file_res := HT_Util.integer_square_root(file_len / (bit_depth/8))
		if file_res == -1:
			# Can't deduce size
			return false

		# TODO Need a way to know which endianess our system has!
		# For now we have to make an assumption...
		# This function is most supposed to execute in the editor.
		# The editor officially runs on desktop architectures, which are
		# generally little-endian.
		if big_endian:
			f.big_endian = true

		var res := get_adjusted_map_size(file_res, file_res)

		var width := res
		var height := res

		_locked = true

		_logger.debug(str("Resizing terrain to ", width, "x", height, "..."))
		resize(res, false, Vector2())

		var im := get_image(CHANNEL_HEIGHT)
		assert(im != null)

		var hrange := max_y - min_y

		_logger.debug("Converting to internal format...")

		var rw := mini(res, file_res)
		var rh := mini(res, file_res)

		# Convert to internal format
		var h := 0.0
		if bit_depth == BIT_DEPTH_32:
			for y in rh:
				for x in rw:
					var gs := float(f.get_32()) / 4294967295.0
					h = min_y + hrange * float(gs)
					match im.get_format():
						Image.FORMAT_RF:
							im.set_pixel(x, y, Color(h, 0, 0))
						Image.FORMAT_RGB8:
							im.set_pixel(x, y, encode_height_to_rgb8_unorm(h))
						_:
							_logger.error(str("Invalid heightmap format ", im.get_format()))
							return false

				# Skip next pixels if the file is bigger than the accepted resolution
				for x in range(rw, file_res):
					f.get_32()
		else:
			for y in rh:
				for x in rw:
					var gs := float(f.get_16()) / 65535.0
					h = min_y + hrange * float(gs)
					match im.get_format():
						Image.FORMAT_RF:
							im.set_pixel(x, y, Color(h, 0, 0))
						Image.FORMAT_RGB8:
							im.set_pixel(x, y, encode_height_to_rgb8_unorm(h))
						_:
							_logger.error(str("Invalid heightmap format ", im.get_format()))
							return false

				# Skip next pixels if the file is bigger than the accepted resolution
				for x in range(rw, file_res):
					f.get_16()

	elif ext == "xyz":
		var f := FileAccess.open(fpath, FileAccess.READ)
		if f == null:
			return false

		var bounds := HT_XYZFormat.load_bounds(f)
		var res := get_adjusted_map_size(bounds.image_width, bounds.image_height)

		var width := res
		var height := res

		_locked = true

		_logger.debug(str("Resizing terrain to ", width, "x", height, "..."))
		resize(res, false, Vector2())

		var im := get_image(CHANNEL_HEIGHT)
		assert(im != null)

		im.fill(Color(0,0,0))

		_logger.debug(str("Parsing XYZ file (this can take a while)..."))
		f.seek(0)
		var float_heightmap := Image.create(im.get_width(), im.get_height(), false, Image.FORMAT_RF)
		HT_XYZFormat.load_heightmap(f, float_heightmap, bounds)

		# Flipping because in Godot, for X to mean "east"/"right", Z must be backward,
		# and we are using Z to map the Y axis of the heightmap image.
		float_heightmap.flip_y()
		
		match im.get_format():
			Image.FORMAT_RF:
				im.blit_rect(float_heightmap, Rect2i(0, 0, res, res), Vector2i())
			Image.FORMAT_RGB8:
				convert_float_heightmap_to_rgb8(float_heightmap, im)
			_:
				_logger.error(str("Invalid heightmap format ", im.get_format()))

		# Note: when importing maps with non-compliant sizes and flipping,
		# the result might not be aligned to global coordinates.
		# If this is a problem, we could just offset the terrain to compensate?

	else:
		# File extension not recognized
		return false

	_locked = false

	_logger.debug("Notify region change...")
	notify_region_change(Rect2(0, 0, get_resolution(), get_resolution()), CHANNEL_HEIGHT)

	return true


func _import_map(map_type: int, path: String) -> bool:
	# Heightmap requires special treatment
	assert(map_type != CHANNEL_HEIGHT)

	var im := Image.load_from_file(path)
	# TODO No way to get the error code?
	if im == null:
		return false

	var res := get_resolution()
	if im.get_width() != res or im.get_height() != res:
		im.crop(res, res)

	if im.get_format() != get_channel_format(map_type):
		im.convert(get_channel_format(map_type))

	var map : HT_Map = _maps[map_type][0]
	map.image = im

	notify_region_change(Rect2(0, 0, im.get_width(), im.get_height()), map_type)
	return true


# TODO Workaround for https://github.com/Zylann/godot_heightmap_plugin/issues/101
func _dummy_function():
	pass


static func _get_xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


class HT_CellRaycastContext:
	var begin_pos := Vector3()
	var _cell_begin_pos_y := 0.0
	var _cell_begin_pos_2d := Vector2()
	var dir := Vector3()
	var dir_2d := Vector2()
	var vertical_bounds : Image
	var hit = null # Vector3
	var heightmap : Image
	var broad_param_2d_to_3d := 1.0
	var cell_param_2d_to_3d := 1.0
	# TODO Can't call static functions of the enclosing class.....................
	var decode_height_func : Callable
	#var dbg
	
	func broad_cb(cx: int, cz: int, enter_param: float, exit_param: float) -> bool:
		if cx < 0 or cz < 0 or cz >= vertical_bounds.get_height() \
		or cx >= vertical_bounds.get_width():
			# The function may occasionally be called at boundary values
			return false
		var vb := vertical_bounds.get_pixel(cx, cz)
		var begin := begin_pos + dir * (enter_param * broad_param_2d_to_3d)
		var exit_y := begin_pos.y + dir.y * exit_param * broad_param_2d_to_3d
		#_spawn_box(Vector3(cx * VERTICAL_BOUNDS_CHUNK_SIZE, \
		#	begin.y, cz * VERTICAL_BOUNDS_CHUNK_SIZE), 2.0)
		if begin.y < vb.r or exit_y > vb.g:
			# Not hitting this chunk
			return false
		# We may be hitting something in this chunk, perform a narrow phase
		# through terrain cells
		var distance_in_chunk_2d := (exit_param - enter_param) * VERTICAL_BOUNDS_CHUNK_SIZE
		var cell_ray_origin_2d := Vector2(begin.x, begin.z)
		_cell_begin_pos_y = begin.y
		_cell_begin_pos_2d = cell_ray_origin_2d
		var rhit = HT_Util.grid_raytrace_2d(
			cell_ray_origin_2d, dir_2d, cell_cb, distance_in_chunk_2d)
		return rhit != null
	
	func cell_cb(cx: int, cz: int, enter_param: float, exit_param: float) -> bool:
		var enter_pos := _cell_begin_pos_2d + dir_2d * enter_param
		#var exit_pos := _cell_begin_pos_2d + dir_2d * exit_param

		var enter_y := _cell_begin_pos_y + dir.y * enter_param * cell_param_2d_to_3d
		var exit_y := _cell_begin_pos_y + dir.y * exit_param * cell_param_2d_to_3d

		hit = _intersect_cell(heightmap, cx, cz, Vector3(enter_pos.x, enter_y, enter_pos.y), dir,
			decode_height_func)

		return hit != null

	static func _intersect_cell(heightmap: Image, cx: int, cz: int,
		begin_pos: Vector3, dir: Vector3, decode_func : Callable):
		
		var c00 := HT_Util.get_pixel_clamped(heightmap, cx,     cz)
		var c10 := HT_Util.get_pixel_clamped(heightmap, cx + 1, cz)
		var c01 := HT_Util.get_pixel_clamped(heightmap, cx,     cz + 1)
		var c11 := HT_Util.get_pixel_clamped(heightmap, cx + 1, cz + 1)
		
		var h00 : float = decode_func.call(c00)
		var h10 : float = decode_func.call(c10)
		var h01 : float = decode_func.call(c01)
		var h11 : float = decode_func.call(c11)

		var p00 := Vector3(cx,     h00, cz)
		var p10 := Vector3(cx + 1, h10, cz)
		var p01 := Vector3(cx,     h01, cz + 1)
		var p11 := Vector3(cx + 1, h11, cz + 1)

		var th0 = Geometry3D.ray_intersects_triangle(begin_pos, dir, p00, p10, p11)
		var th1 = Geometry3D.ray_intersects_triangle(begin_pos, dir, p00, p11, p01)

		if th0 != null:
			return th0
		return th1

#	func _spawn_box(pos: Vector3, r: float):
#		if not Input.is_key_pressed(KEY_CONTROL):
#			return
#		var mi = MeshInstance.new()
#		mi.mesh = CubeMesh.new()
#		mi.translation = pos * dbg.map_scale
#		mi.scale = Vector3(r, r, r)
#		dbg.add_child(mi)
#		mi.owner = dbg.get_tree().edited_scene_root


# Raycasts heightmap image directly without using a collider.
# The coordinate system is such that Y is up, terrain minimum corner is at (0, 0),
# and one heightmap pixel is one space unit.
# TODO Cannot hint as `-> Vector2` because it can be null if there is no hit
func cell_raycast(ray_origin: Vector3, ray_direction: Vector3, max_distance: float):
	var heightmap := get_image(CHANNEL_HEIGHT)
	if heightmap == null:
		return null

	var terrain_rect := Rect2(Vector2(), Vector2(_resolution, _resolution))

	# Project and clip into 2D
	var ray_origin_2d := _get_xz(ray_origin)
	var ray_end_2d := _get_xz(ray_origin + ray_direction * max_distance)
	var clipped_segment_2d := HT_Util.get_segment_clipped_by_rect(terrain_rect,
		ray_origin_2d, ray_end_2d)
	# TODO We could clip along Y too if we had total AABB cached somewhere

	if len(clipped_segment_2d) == 0:
		# Not hitting the terrain area
		return null

	var max_distance_2d := ray_origin_2d.distance_to(ray_end_2d)
	if max_distance_2d < 0.001:
		# TODO Direct vertical hit?
		return null
	
	# Get ratio along the segment where the first point was clipped
	var begin_clip_param := ray_origin_2d.distance_to(clipped_segment_2d[0]) / max_distance_2d
	
	var ray_direction_2d := _get_xz(ray_direction).normalized()
	
	var ctx := HT_CellRaycastContext.new()
	ctx.begin_pos = ray_origin + ray_direction * (begin_clip_param * max_distance)
	ctx.dir = ray_direction
	ctx.dir_2d = ray_direction_2d
	ctx.vertical_bounds = _chunked_vertical_bounds
	ctx.heightmap = heightmap
	ctx.cell_param_2d_to_3d = max_distance / max_distance_2d
	ctx.broad_param_2d_to_3d = ctx.cell_param_2d_to_3d * VERTICAL_BOUNDS_CHUNK_SIZE
	
	match heightmap.get_format():
		Image.FORMAT_RF:
			ctx.decode_height_func = decode_height_from_f
		Image.FORMAT_RGB8:
			ctx.decode_height_func = decode_height_from_rgb8_unorm
		_:
			_logger.error(str("Invalid heightmap format ", heightmap.get_format()))
			return null

	#ctx.dbg = dbg

	# Broad phase through cached vertical bound chunks
	var broad_ray_origin = clipped_segment_2d[0] / VERTICAL_BOUNDS_CHUNK_SIZE
	var broad_max_distance = \
		clipped_segment_2d[0].distance_to(clipped_segment_2d[1]) / VERTICAL_BOUNDS_CHUNK_SIZE
	var hit_bp = HT_Util.grid_raytrace_2d(broad_ray_origin, ray_direction_2d, ctx.broad_cb, 
		broad_max_distance)

	if hit_bp == null:
		# No hit
		return null

	return Vector2(ctx.hit.x, ctx.hit.z)


static func encode_normal(n: Vector3) -> Color:
	n = 0.5 * (n + Vector3.ONE)
	return Color(n.x, n.z, n.y)


static func get_channel_format(channel: int) -> int:
	return _map_types[channel].texture_format as int


# Note: PNG supports 16-bit channels, unfortunately Godot doesn't
static func _channel_can_be_saved_as_png(channel: int) -> bool:
	return _map_types[channel].can_be_saved_as_png


static func get_channel_name(c: int) -> String:
	return _map_types[c].name as String


static func get_map_debug_name(map_type: int, index: int) -> String:
	return str(get_channel_name(map_type), "[", index, "]")


func _get_map_filename(map_type: int, index: int) -> String:
	var name = get_channel_name(map_type)
	var id = _maps[map_type][index].id
	if id > 0:
		name += str(id + 1)
	return name


static func get_map_shader_param_name(map_type: int, index: int) -> String:
	var param_name = _map_types[map_type].shader_param_name
	if typeof(param_name) == TYPE_STRING:
		return param_name
	return param_name[index]


# TODO Can't type hint because it returns a nullable array
#static func get_map_type_and_index_from_shader_param_name(p_name: String):
#	for map_type in _map_types:
#		var pn = _map_types[map_type].shader_param_name
#		if typeof(pn) == TYPE_STRING:
#			if pn == p_name:
#				return [map_type, 0]
#		else:
#			for i in len(pn):
#				if pn[i] == p_name:
#					return [map_type, i]
#	return null


static func decode_height_from_f(c: Color) -> float:
	return c.r


const _V2_UNIT_STEPS = 1024.0
const _V2_MIN = -8192.0
const _V2_MAX = 8191.0
const _V2_DF = 255.0 / _V2_UNIT_STEPS

# This RGB8 encoding implementation is specific to this plugin.
# It was used in the port to Godot 4.0 for a time, until it was found float
# textures could be used.

static func decode_height_from_rgb8_unorm(c: Color) -> float:
	return (c.r * 0.25 + c.g * 64.0 + c.b * 16384.0) * (4.0 * _V2_DF) + _V2_MIN


static func encode_height_to_rgb8_unorm(h: float) -> Color:
	h -= _V2_MIN
	var i := int(h * _V2_UNIT_STEPS)
	var r := i % 256
	var g := (i / 256) % 256
	var b := i / 65536
	return Color(r, g, b, 255.0) / 255.0


static func convert_heightmap_to_float(src: Image, logger: HT_Logger.HT_LoggerBase) -> Image:
	var src_format := src.get_format()
	
	if src_format == Image.FORMAT_RH:
		var im : Image = src.duplicate()
		im.convert(Image.FORMAT_RF)
		return im

	if src_format == Image.FORMAT_RF:
		return src.duplicate() as Image
	
	if src_format == Image.FORMAT_RGB8:
		var im := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RF)
		for y in src.get_height():
			for x in src.get_width():
				var c := src.get_pixel(x, y)
				var h := decode_height_from_rgb8_unorm(c)
				im.set_pixel(x, y, Color(h, h, h, 1.0))
		return im
	
	logger.error("Unknown source heightmap format!")
	return null


static func convert_float_heightmap_to_rgb8(src: Image, dst: Image):
	assert(dst.get_format() == Image.FORMAT_RGB8)
	assert(dst.get_size() == src.get_size())
	
	for y in src.get_height():
		for x in src.get_width():
			var h = src.get_pixel(x, y).r
			dst.set_pixel(x, y, encode_height_to_rgb8_unorm(h))

