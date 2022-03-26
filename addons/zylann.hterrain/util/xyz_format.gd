tool

# XYZ files are text files containing a list of 3D points.
# They can be found in GIS software as an export format for heightmaps.
# In order to turn it into a heightmap we may calculate bounds first
# to find the origin and then set points in an image.


class HT_XYZBounds:
	# Note: it is important for these to be double-precision floats,
	# GIS data can have large coordinates
	var min_x := 0.0
	var min_y := 0.0

	var max_x := 0.0
	var max_y := 0.0

	var line_count := 0

	var image_width := 0
	var image_height := 0


# TODO `split_float` returns 32-bit floats, despite internally parsing doubles... 
# Despite that, I still use it here because it doesn't seem to cause issues and is faster.
# If it becomes an issue, we'll have to switch to `split` and casting to `float`.

static func load_bounds(f: File) -> HT_XYZBounds:
	# It is faster to get line and split floats than using CSV functions
	var line := f.get_line()
	var floats = line.split_floats(" ")
	
	# We only care about X and Y, it makes less operations to do in the loop.
	# Z is the height and will remain as-is at the end.
	var min_pos_x : float = floats[0]
	var min_pos_y : float = floats[1]

	var max_pos_x := min_pos_x
	var max_pos_y := min_pos_y

	# Start at 1 because we just read the first line
	var line_count := 1
	
	# We know the file is a series of float triplets
	while not f.eof_reached():
		line = f.get_line()

		# The last line can be empty
		if len(line) < 2:
			break

		floats = line.split_floats(" ")

		var pos_x = floats[0]
		var pos_y = floats[1]
		
		min_pos_x = min(min_pos_x, pos_x)
		min_pos_y = min(min_pos_y, pos_y)

		max_pos_x = max(max_pos_x, pos_x)
		max_pos_y = max(max_pos_y, pos_y)

		line_count += 1

	var bounds := HT_XYZBounds.new()
	bounds.min_x = min_pos_x
	bounds.min_y = min_pos_y
	bounds.max_x = max_pos_x
	bounds.max_y = max_pos_y
	bounds.line_count = line_count
	bounds.image_width = int(max_pos_x - min_pos_x) + 1
	bounds.image_height = int(max_pos_y - min_pos_y) + 1
	return bounds


# Loads points into an image with existing dimensions and format.
# `f` must be positionned at the beginning of the series of points.
# If `bounds` is `null`, it will be computed.
static func load_heightmap(f: File, dst_image: Image, bounds: HT_XYZBounds):
	# We are not going to read the entire file directly in memory, because it can be really big.
	# Instead we'll parse it directly and the only thing we retain in memory is the heightmap.
	# This can be really slow on big files. If we can assume the file is square and points
	# separated by 1 unit each in a grid pattern, it could be a bit faster, but
	# parsing points from text really is the main bottleneck (40 seconds to load a 2000x2000 file!).
	
	# Bounds can be precalculated
	if bounds == null:
		var file_begin := f.get_position()
		bounds = load_bounds(f)
		f.seek(file_begin)
	
	# Put min coordinates on the GDScript stack so they are faster to access
	var min_pos_x := bounds.min_x
	var min_pos_y := bounds.min_y
	var line_count := bounds.line_count

	dst_image.lock()
	
	for i in line_count:
		var line := f.get_line()
		var floats := line.split_floats(" ")
		var x := int(floats[0] - min_pos_x)
		var y := int(floats[1] - min_pos_y)
		
		# Make sure the coordinate is inside the image,
		# due to float imprecision or potentially non-grid-aligned points.
		# Could use `Rect2` to check faster but it uses floats.
		# `Rect2i` would be better but is only available in Godot 4.
		if x >= 0 and y >= 0 and x < dst_image.get_width() and y < dst_image.get_height():
			dst_image.set_pixel(x, y, Color(floats[2], 0, 0))
	
	dst_image.unlock()

