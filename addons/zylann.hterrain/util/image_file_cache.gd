
# Used to store temporary images on disk.
# This is useful for undo/redo as image edition can quickly fill up memory.

const Logger = preload("./logger.gd")

var _cache_dir := ""
var _next_id := 0
var _session_id := ""
var _cache_image_info := {}
var _logger = Logger.get_for(self)


func _init(cache_dir: String):
	assert(cache_dir != "")
	_cache_dir = cache_dir
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 16:
		_session_id += str(rng.randi() % 10)
	_logger.debug(str("Image cache session ID: ", _session_id))
	var dir := Directory.new()
	if not dir.dir_exists(_cache_dir):
		var err = dir.make_dir(_cache_dir)
		if err != OK:
			_logger.error("Could not create directory {0}, error {1}" \
				.format([_cache_dir, err]))


# TODO Cannot cleanup the cache in destructor!
# Godot doesn't allow me to call clear()...
# https://github.com/godotengine/godot/issues/31166
#func _notification(what):
#	if what == NOTIFICATION_PREDELETE:
#		clear()


func save_image(im: Image) -> int:
	var id = _next_id
	var fpath = _cache_dir.plus_file(str(_session_id, "_", id))
	# TODO Could use a thread here
	
	var err
	match im.get_format():
		Image.FORMAT_R8,\
		Image.FORMAT_RG8,\
		Image.FORMAT_RGB8,\
		Image.FORMAT_RGBA8:
			fpath += ".png"
			err = im.save_png(fpath)
		Image.FORMAT_RH,\
		Image.FORMAT_RGH,\
		Image.FORMAT_RGBH,\
		Image.FORMAT_RGBAH:
			# TODO Can't save an EXR to user://
			# See https://github.com/godotengine/godot/issues/34490
#			fpath += ".exr"
#			err = im.save_exr(fpath)
			fpath += ".res"
			err = ResourceSaver.save(fpath, im)
		_:
			err = str("Cannot save image format ", im.get_format())

	# Remembering original format is important,
	# because Godot's image loader often force-converts into larger formats
	_cache_image_info[id] = {
		"format": im.get_format(),
		"path": fpath
	}
	
	if err != OK:
		_logger.error("Could not save image file to {0}, error {1}".format([fpath, err]))
	_next_id += 1
	return id


func load_image(id: int) -> Image:
	var info := _cache_image_info[id] as Dictionary
	var fpath := info.path as String

	var im : Image
	var err : int
	if fpath.ends_with(".res"):
		im = ResourceLoader.load(fpath)
		if im == null:
			err = ERR_CANT_OPEN
	else:
		im = Image.new()
		err = im.load(fpath)

	if err != OK:
		_logger.error("Could not load cached image from {0}, error {1}" \
			.format([fpath, err]))
		return null

	im.convert(info.format)
	return im


func clear():
	_logger.debug("Clearing image cache")
	
	var dir := Directory.new()
	var err := dir.open(_cache_dir)
	if err != OK:
		_logger.error("Could not open image file cache directory '{0}'" \
			.format([_cache_dir]))
		return
	
	err = dir.list_dir_begin(true, true)
	if err != OK:
		_logger.error("Could not start list_dir_begin in '{0}'".format([_cache_dir]))
		return
		
	while true:
		var fpath := dir.get_next()
		if fpath == "":
			break
		if fpath.ends_with(".png") or fpath.ends_with(".res"):
			_logger.debug(str("Deleted ", fpath))
			err = dir.remove(fpath)
			if err != OK:
				_logger.error("Failed to delete cache file '{0}'" \
					.format([_cache_dir.plus_file(fpath)]))

	_cache_image_info.clear()

