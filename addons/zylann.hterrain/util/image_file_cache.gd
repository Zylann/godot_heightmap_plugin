
# Used to store temporary images on disk.
# This is useful for undo/redo as image edition can quickly fill up memory.

const Logger = preload("./logger.gd")

var _cache_dir := ""
var _next_id := 0
var _session_id := ""
var _cache_image_info := {}
var _logger = Logger.get_for(self)

var _saving_thread := Thread.new()
var _save_queue := []
var _save_queue_mutex := Mutex.new()
var _save_semaphore := Semaphore.new()
var _save_thread_running := false


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
	_save_thread_running = true 
	_saving_thread.start(self, "_save_thread_func")


# TODO Cannot cleanup the cache in destructor!
# Godot doesn't allow me to call clear()...
# https://github.com/godotengine/godot/issues/31166
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		#clear()
		print("Destroying")
		_save_thread_running = false
		_save_semaphore.post()
		_saving_thread.wait_to_finish()
		print("Destroyed")


func save_image(im: Image) -> int:
	var id := _next_id
	var fpath := _cache_dir.plus_file(str(_session_id, "_", id))

	var ext := _get_image_extension(im)
	if ext == "":
		_logger.error(str("Cannot save image format ", im.get_format()))
		return -1
	fpath += "."
	fpath += ext
	
	var item = {
		"image": im,
		# Remembering original format is important,
		# because Godot's image loader often force-converts into larger formats
		"format": im.get_format(),
		"path": fpath,
		"saved": false
	}

	_cache_image_info[id] = item
	
	_save_queue_mutex.lock()
	_save_queue.append(item)
	_save_queue_mutex.unlock()
	
	_save_semaphore.post()
	
	_next_id += 1
	return id


func load_image(id: int) -> Image:
	var info := _cache_image_info[id] as Dictionary
	
	var timeout = 5.0
	var time_before = OS.get_ticks_msec()
	# We could just grab `image`, because the thread only reads it.
	# However it's still not safe to do that if we write or even lock it,
	# so we have to assume it still has ownership of it.
	while not info.saved:
		OS.delay_msec(8.0)
		_logger.debug("Waiting for cached image {0}...".format([id]))
		if OS.get_ticks_msec() - time_before > timeout:
			_logger.error("Could not get image {0} from cache. Something went wrong.".format([id]))
			return null
	
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


func _save_thread_func(_unused_userdata):
	# Threads keep a reference to the function they run.
	# So if it's a Reference, and that reference owns the thread... we get a cycle.
	# We can break the cycle by removing 1 to the count inside the thread.
	# The thread's reference will never die unexpectedly because we stop and destroy the thread
	# in the destructor of the reference.
	# If that workaround explodes one day, another way could be to use an intermediary instance
	# extending Object, and run a function on that instead
	unreference()

	while _save_thread_running:
		_save_queue_mutex.lock()
		var to_save := _save_queue.duplicate(false)
		_save_queue.clear()
		_save_queue_mutex.unlock()
		
		if len(to_save) > 0:
			for item in to_save:
				_save_image(item.image, item.path)
				# Notify main thread
				call_deferred("_on_image_saved", item)
		else:
			_save_semaphore.wait()


func _on_image_saved(item: Dictionary):
	_logger.debug(str("Saved ", item.path))
	item.saved = true
	# Should remove image from memory (for usually being last reference)
	item.image = null


static func _save_image(im: Image, fpath: String) -> int:
	var err
	if fpath.ends_with(".png"):
		err = im.save_png(fpath)
	else:
		err = ResourceSaver.save(fpath, im)
	return err


static func _get_image_extension(im: Image) -> String:
	match im.get_format():
		Image.FORMAT_R8,\
		Image.FORMAT_RG8,\
		Image.FORMAT_RGB8,\
		Image.FORMAT_RGBA8:
			return "png"
		Image.FORMAT_RH,\
		Image.FORMAT_RGH,\
		Image.FORMAT_RGBH,\
		Image.FORMAT_RGBAH:
			# TODO Can't save an EXR to user://
			# See https://github.com/godotengine/godot/issues/34490
#			fpath += ".exr"
#			err = im.save_exr(fpath)
			return "res"
	return ""


