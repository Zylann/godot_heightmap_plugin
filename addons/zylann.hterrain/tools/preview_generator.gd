tool
extends EditorResourcePreviewGenerator

const HTerrainData = preload("../hterrain_data.gd")
const Errors = preload("../util/errors.gd")

# TODO Use p_size argument in Godot 3.1
const SIZE = 64


func generate(res):
	if res == null or not (res is HTerrainData):
		return
	var normalmap = res.get_image(HTerrainData.CHANNEL_NORMAL)
	if normalmap == null:
		return null
	return _generate(normalmap, SIZE, SIZE)


func generate_from_path(path):
	# TODO Implement this properly when I can load my own extension...
	# The point is, a .tres file doesn't say much without looking inside,
	# but using `load` on an entire terrain just to have a thumbnail is crazy inefficient
	
	if not path.ends_with(".tres"):
		return null
	
	var f = File.new()
	var err = f.open(path, File.READ)
	if err != OK:
		printerr("Could not load ", path, ", error ", Errors.get_message(err))
		return null
	
	var line = f.get_line()
	if not line.begins_with("[gd_resource type=\"Resource\""):
		# Not a plain resource
		return null
	
	while not f.eof_reached():
		line = f.get_line()
		
		# Search for a line that says we use our custom script
		if line.find(HTerrainData.resource_path) != -1:
			# Assume we found a terrain resource
			var dir = path.get_base_dir()
			var fname = path.get_file().get_basename()
			var data_dir = str(fname, HTerrainData.DATA_FOLDER_SUFFIX)
			var normals_fname = str(HTerrainData.get_channel_name(HTerrainData.CHANNEL_NORMAL), ".png")
			var normals_path = dir.plus_file(data_dir).plus_file(normals_fname)
			var normals = Image.new()
			err = normals.load(normals_path)
			if err != OK:
				printerr("Could not load ", normals_path, ", error ", Errors.get_message(err))
				return null
			return _generate(normals, SIZE, SIZE)
		
		# Too late in the file, stop searching
		if line.begins_with("[resource]"):
			break
	
	return null


func handles(type):
	return type == "Resource"


static func _generate(normals, width, height):
	
	var im = Image.new()
	im.create(width, height, false, Image.FORMAT_RGB8)

	im.lock()
	normals.lock()

	var light_dir = Vector3(-1, -0.5, -1).normalized()
	
	for y in im.get_height():
		for x in im.get_width():

			var fx = float(x) / float(im.get_width())
			var fy = float(im.get_height() - y - 1) / float(im.get_height())
			var mx = int(fx * normals.get_width())
			var my = int(fy * normals.get_height())

			var n = _decode_normal(normals.get_pixel(mx, my))

			var ndot = -n.dot(light_dir)
			var gs = clamp(0.5 * ndot + 0.5, 0.0, 1.0)
			var col = Color(gs, gs, gs, 1.0)

			im.set_pixel(x, y, col)

	im.unlock();
	normals.unlock();
	
	var tex = ImageTexture.new()
	tex.create_from_image(im, 0)
	return tex


static func _decode_normal(c):
	return Vector3(2.0 * c.r - 1.0, 2.0 * c.b - 1.0, 2.0 * c.g - 1.0)
