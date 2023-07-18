@tool

const HT_Logger = preload("../../util/logger.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Result = preload("../util/result.gd")

const _transform_params = [
	"normalmap_flip_y"
]


# sources: {
#     "a": "path_to_image_where_red_channel_will_be_stored_in_alpha.png",
#     "rgb": "path_to_image_where_rgb_channels_will_be_stored.png"
#     "rgba": "path_to_image.png",
#     "rgb": "#hexcolor"
# }
static func generate_image(sources: Dictionary, resolution: int, logger) -> HT_Result:
	var image := Image.create(resolution, resolution, true, Image.FORMAT_RGBA8)
	
	var flip_normalmap_y := false
	
	# TODO Accelerate with GDNative
	for key in sources:
		if key in _transform_params:
			continue
		
		var src_path : String = sources[key]
		
		logger.debug(str("Processing source \"", src_path, "\""))
		
		var src_image : Image
		if src_path.begins_with("#"):
			# Plain color
			var col = Color(src_path)
			src_image = Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
			src_image.fill(col)
			
		else:
			# File
			src_image = Image.new()
			var err := src_image.load(src_path)
			if err != OK:
				return HT_Result.new(false, "Could not open file \"{0}\": {1}" \
					.format([src_path, HT_Errors.get_message(err)])) \
					.with_value(err)
			src_image.decompress()
		
		src_image.resize(image.get_width(), image.get_height())
		
		# TODO Support more channel configurations
		if key == "rgb":
			for y in image.get_height():
				for x in image.get_width():
					var dst_col := image.get_pixel(x, y)
					var a := dst_col.a
					dst_col = src_image.get_pixel(x, y)
					dst_col.a = a
					image.set_pixel(x, y, dst_col)
					
		elif key == "a":
			for y in image.get_height():
				for x in image.get_width():
					var dst_col := image.get_pixel(x, y)
					dst_col.a = src_image.get_pixel(x, y).r
					image.set_pixel(x, y, dst_col)
		
		elif key == "rgba":
			# Meh
			image.blit_rect(src_image, 
				Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i())

	if sources.has("normalmap_flip_y") and sources.normalmap_flip_y:
		_flip_normalmap_y(image)
	
	return HT_Result.new(true).with_value(image)


static func _flip_normalmap_y(image: Image):
	for y in image.get_height():
		for x in image.get_width():
			var col := image.get_pixel(x, y)
			col.g = 1.0 - col.g
			image.set_pixel(x, y, col)


