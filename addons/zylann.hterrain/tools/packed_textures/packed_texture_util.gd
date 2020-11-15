tool

const Logger = preload("../../util/logger.gd")
const Errors = preload("../../util/errors.gd")
const Result = preload("../util/result.gd")


static func generate_image(sources: Dictionary, resolution: int, logger) -> Result:
	var image := Image.new()
	image.create(resolution, resolution, true, Image.FORMAT_RGBA8)
	
	image.lock()
	
	# TODO Accelerate with GDNative
	for key in sources:
		var src_path : String = sources[key]
		
		logger.debug(str("Processing source ", src_path))
		
		var src_image := Image.new()
		if src_path.begins_with("#"):
			# Plain color
			var col = Color(src_path)
			src_image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
			src_image.fill(col)
			
		else:
			# File
			var err := src_image.load(src_path)
			if err != OK:
				return Result.new(false, "Could not open file {0}: {1}" \
					.format([src_path, Errors.get_message(err)])) \
					.with_value(err)
			src_image.decompress()
		
		src_image.resize(image.get_width(), image.get_height())
		src_image.lock()
		
		# TODO Support more channel configurations
		# TODO Support normalmap strength +/-
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
				Rect2(0, 0, image.get_width(), image.get_height()), Vector2())

		src_image.unlock()
	
	image.unlock()
	return Result.new(true).with_value(image)

