@tool

# These functions are the same as the ones found in the GDNative library.
# They are used if the user's platform is not supported.

const HT_Util = preload("../util/util.gd")

var _blur_buffer : Image


func get_red_range(im: Image, rect: Rect2) -> Vector2:
	rect = rect.intersection(Rect2(0, 0, im.get_width(), im.get_height()))
	var min_x := int(rect.position.x)
	var min_y := int(rect.position.y)
	var max_x := min_x + int(rect.size.x)
	var max_y := min_y + int(rect.size.y)

	var min_height := im.get_pixel(min_x, min_y).r
	var max_height := min_height

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			var h = im.get_pixel(x, y).r
			if h < min_height:
				min_height = h
			elif h > max_height:
				max_height = h

	return Vector2(min_height, max_height)


func get_red_sum(im: Image, rect: Rect2) -> float:
	rect = rect.intersection(Rect2(0, 0, im.get_width(), im.get_height()))
	var min_x := int(rect.position.x)
	var min_y := int(rect.position.y)
	var max_x := min_x + int(rect.size.x)
	var max_y := min_y + int(rect.size.y)

	var sum := 0.0
	
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			sum += im.get_pixel(x, y).r

	return sum


func get_red_sum_weighted(im: Image, brush: Image, pos: Vector2, factor: float) -> float:
	var min_x = int(pos.x)
	var min_y = int(pos.y)
	var max_x = min_x + brush.get_width()
	var max_y = min_y + brush.get_height()
	var min_noclamp_x = min_x
	var min_noclamp_y = min_y

	min_x = clampi(min_x, 0, im.get_width())
	min_y = clampi(min_y, 0, im.get_height())
	max_x = clampi(max_x, 0, im.get_width())
	max_y = clampi(max_y, 0, im.get_height())

	var sum = 0.0

	for y in range(min_y, max_y):
		var by = y - min_noclamp_y

		for x in range(min_x, max_x):
			var bx = x - min_noclamp_x
			
			var shape_value = brush.get_pixel(bx, by).r
			sum += im.get_pixel(x, y).r * shape_value * factor

	return sum


func add_red_brush(im: Image, brush: Image, pos: Vector2, factor: float):
	var min_x = int(pos.x)
	var min_y = int(pos.y)
	var max_x = min_x + brush.get_width()
	var max_y = min_y + brush.get_height()
	var min_noclamp_x = min_x
	var min_noclamp_y = min_y

	min_x = clampi(min_x, 0, im.get_width())
	min_y = clampi(min_y, 0, im.get_height())
	max_x = clampi(max_x, 0, im.get_width())
	max_y = clampi(max_y, 0, im.get_height())

	for y in range(min_y, max_y):
		var by = y - min_noclamp_y

		for x in range(min_x, max_x):
			var bx = x - min_noclamp_x

			var shape_value = brush.get_pixel(bx, by).r
			var r = im.get_pixel(x, y).r + shape_value * factor
			im.set_pixel(x, y, Color(r, r, r))


func lerp_channel_brush(im: Image, brush: Image, pos: Vector2, 
	factor: float, target_value: float, channel: int):
		
	var min_x = int(pos.x)
	var min_y = int(pos.y)
	var max_x = min_x + brush.get_width()
	var max_y = min_y + brush.get_height()
	var min_noclamp_x = min_x
	var min_noclamp_y = min_y

	min_x = clampi(min_x, 0, im.get_width())
	min_y = clampi(min_y, 0, im.get_height())
	max_x = clampi(max_x, 0, im.get_width())
	max_y = clampi(max_y, 0, im.get_height())

	for y in range(min_y, max_y):
		var by = y - min_noclamp_y

		for x in range(min_x, max_x):
			var bx = x - min_noclamp_x

			var shape_value = brush.get_pixel(bx, by).r
			var c = im.get_pixel(x, y)
			c[channel] = lerp(c[channel], target_value, shape_value * factor)
			im.set_pixel(x, y, c)


func lerp_color_brush(im: Image, brush: Image, pos: Vector2, 
	factor: float, target_value: Color):
		
	var min_x = int(pos.x)
	var min_y = int(pos.y)
	var max_x = min_x + brush.get_width()
	var max_y = min_y + brush.get_height()
	var min_noclamp_x = min_x
	var min_noclamp_y = min_y

	min_x = clampi(min_x, 0, im.get_width())
	min_y = clampi(min_y, 0, im.get_height())
	max_x = clampi(max_x, 0, im.get_width())
	max_y = clampi(max_y, 0, im.get_height())

	for y in range(min_y, max_y):
		var by = y - min_noclamp_y

		for x in range(min_x, max_x):
			var bx = x - min_noclamp_x

			var shape_value = brush.get_pixel(bx, by).r
			var c = im.get_pixel(x, y).lerp(target_value, factor * shape_value)
			im.set_pixel(x, y, c)


func generate_gaussian_brush(im: Image) -> float:
	var sum := 0.0
	var center := Vector2(im.get_width() / 2, im.get_height() / 2)
	var radius := minf(im.get_width(), im.get_height()) / 2.0

	for y in im.get_height():
		for x in im.get_width():
			var d := Vector2(x, y).distance_to(center) / radius
			var v := clampf(1.0 - d * d * d, 0.0, 1.0)
			im.set_pixel(x, y, Color(v, v, v))
			sum += v;

	return sum


func blur_red_brush(im: Image, brush: Image, pos: Vector2, factor: float):
	factor = clampf(factor, 0.0, 1.0)
	
	if _blur_buffer == null:
		_blur_buffer = Image.new()
	var buffer := _blur_buffer
	
	var buffer_width := brush.get_width() + 2
	var buffer_height := brush.get_height() + 2
	
	if buffer_width != buffer.get_width() or buffer_height != buffer.get_height():
		buffer.create(buffer_width, buffer_height, false, Image.FORMAT_RF)
	
	var min_x := int(pos.x) - 1
	var min_y := int(pos.y) - 1
	var max_x := min_x + buffer.get_width()
	var max_y := min_y + buffer.get_height()
	
	var im_clamp_w = im.get_width() - 1
	var im_clamp_h = im.get_height() - 1
	
	# Copy pixels to temporary buffer
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			var ix := clampi(x, 0, im_clamp_w)
			var iy := clampi(y, 0, im_clamp_h)
			var c = im.get_pixel(ix, iy)
			buffer.set_pixel(x - min_x, y - min_y, c)
	
	min_x = int(pos.x)
	min_y = int(pos.y)
	max_x = min_x + brush.get_width()
	max_y = min_y + brush.get_height()
	var min_noclamp_x := min_x
	var min_noclamp_y := min_y

	min_x = clampi(min_x, 0, im.get_width())
	min_y = clampi(min_y, 0, im.get_height())
	max_x = clampi(max_x, 0, im.get_width())
	max_y = clampi(max_y, 0, im.get_height())
	
	# Apply blur
	for y in range(min_y, max_y):
		var by := y - min_noclamp_y

		for x in range(min_x, max_x):
			var bx := x - min_noclamp_x

			var shape_value := brush.get_pixel(bx, by).r * factor

			var p10 = buffer.get_pixel(bx + 1, by    ).r
			var p01 = buffer.get_pixel(bx,     by + 1).r
			var p11 = buffer.get_pixel(bx + 1, by + 1).r
			var p21 = buffer.get_pixel(bx + 2, by + 1).r
			var p12 = buffer.get_pixel(bx + 1, by + 2).r
			
			var m = (p10 + p01 + p11 + p21 + p12) * 0.2
			var p = lerpf(p11, m, shape_value * factor)

			im.set_pixel(x, y, Color(p, p, p))


func paint_indexed_splat(index_map: Image, weight_map: Image, brush: Image, pos: Vector2, \
	texture_index: int, factor: float):
	
	var min_x := pos.x
	var min_y := pos.y
	var max_x := min_x + brush.get_width()
	var max_y := min_y + brush.get_height()
	var min_noclamp_x := min_x
	var min_noclamp_y := min_y

	min_x = clampi(min_x, 0, index_map.get_width())
	min_y = clampi(min_y, 0, index_map.get_height())
	max_x = clampi(max_x, 0, index_map.get_width())
	max_y = clampi(max_y, 0, index_map.get_height())
	
	var texture_index_f := float(texture_index) / 255.0
	var all_texture_index_f := Color(texture_index_f, texture_index_f, texture_index_f)
	var ci := texture_index % 3
	var cm := Color(-1, -1, -1)
	cm[ci] = 1

	for y in range(min_y, max_y):
		var by := y - min_noclamp_y

		for x in range(min_x, max_x):
			var bx := x - min_noclamp_x

			var shape_value := brush.get_pixel(bx, by).r * factor
			if shape_value == 0.0:
				continue

			var i := index_map.get_pixel(x, y)
			var w := weight_map.get_pixel(x, y)
			
			# Decompress third weight to make computations easier
			w[2] = 1.0 - w[0] - w[1]
			
			# The index map tells which textures to blend.
			# The weight map tells their blending amounts.
			# This brings the limitation that up to 3 textures can blend at a time in a given pixel.
			# Painting this in real time can be a challenge.
			
			# The approach here is a compromise for simplicity.
			# Each texture is associated a fixed component of the index map (R, G or B),
			# so two neighbor pixels having the same component won't be guaranteed to blend.
			# In other words, texture T will not be able to blend with T + N * k,
			# where k is an integer, and N is the number of components in the index map (up to 4).
			# It might still be able to blend due to a special case when an area is uniform,
			# but not otherwise.
			
			# Dynamic component assignment sounds like the alternative, however I wasn't able
			# to find a painting algorithm that wasn't confusing, at least the current one is
			# predictable.
			
			# Need to use approximation because Color is float but GDScript uses doubles...
			if abs(i[ci] - texture_index_f) > 0.001:
				# Pixel does not have our texture index,
				# transfer its weight to other components first
				if w[ci] > shape_value:
					w -= cm * shape_value
					
				elif w[ci] >= 0.0:
					w[ci] = 0.0
					i[ci] = texture_index_f
					
			else:
				# Pixel has our texture index, increase its weight
				if w[ci] + shape_value < 1.0:
					w += cm * shape_value
					
				else:
					# Pixel weight is full, we can set all components to the same index.
					# Need to nullify other weights because they would otherwise never reach
					# zero due to normalization
					w = Color(0, 0, 0)
					w[ci] = 1.0
					i = all_texture_index_f
			
			# No `saturate` function in Color??
			w[0] = clampf(w[0], 0.0, 1.0)
			w[1] = clampf(w[1], 0.0, 1.0)
			w[2] = clampf(w[2], 0.0, 1.0)
			
			# Renormalize
			w /= w[0] + w[1] + w[2]
			
			index_map.set_pixel(x, y, i)
			weight_map.set_pixel(x, y, w)
