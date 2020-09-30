
# Used to store temporary images on disk.
# This is useful for undo/redo as image edition can quickly fill up memory.

# Image data is stored in archive files together,
# because when dealing with many images it speeds up filesystem I/O on Windows.
# If the file exceeds a predefined size, a new one is created.
# Writing to disk is performed from a thread, to leave the main thread responsive.
# However if you want to obtain an image back while it didn't save yet, the main thread will block.
# When the application or plugin is closed, the files get cleared.

const Logger = preload("./logger.gd")

const CACHE_FILE_SIZE_THRESHOLD = 1048576

var _cache_dir := ""
var _next_id := 0
var _session_id := ""
var _cache_image_info := {}
var _logger = Logger.get_for(self)
var _current_cache_file_index := 0
var _cache_file_offset := 0

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
func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		#clear()
		_save_thread_running = false
		_save_semaphore.post()
		_saving_thread.wait_to_finish()


func _create_new_cache_file(fpath: String):
	var f := File.new()
	var err := f.open(fpath, File.WRITE)
	if err != OK:
		_logger.error("Failed to create new cache file {0}, error {1}".format([fpath, err]))
		return
	f.close()


func _get_current_cache_file_name() -> String:
	return _cache_dir.plus_file(str(_session_id, "_", _current_cache_file_index, ".cache"))


func save_image(im: Image) -> int:
	assert(im != null)
	if im.has_mipmaps():
		# TODO Add support for this? Didn't need it so far
		_logger.error("Caching an image with mipmaps, this isn't supported")
	
	var fpath := _get_current_cache_file_name()
	if _next_id == 0:
		# First file
		_create_new_cache_file(fpath)

	var id := _next_id
	_next_id += 1
	
	var item := {
		# Duplicate the image so we are sure nothing funny will happen to it
		# while the thread saves it
		"image": im.duplicate(),
		"path": fpath,
		"data_offset": _cache_file_offset,
		"saved": false
	}
	
	_cache_file_offset += _get_image_data_size(im)
	if _cache_file_offset >= CACHE_FILE_SIZE_THRESHOLD:
		_cache_file_offset = 0
		_current_cache_file_index += 1
		_create_new_cache_file(_get_current_cache_file_name())

	_cache_image_info[id] = item
	
	_save_queue_mutex.lock()
	_save_queue.append(item)
	_save_queue_mutex.unlock()
	
	_save_semaphore.post()
	
	return id


static func _get_image_data_size(im: Image) -> int:
	return 1 + 4 + 4 + 4 + len(im.get_data())


static func _write_image(f: File, im: Image):
	f.store_8(im.get_format())
	f.store_32(im.get_width())
	f.store_32(im.get_height())
	var data := im.get_data()
	f.store_32(len(data))
	f.store_buffer(data)


static func _read_image(f: File) -> Image:
	var format := f.get_8()
	var width := f.get_32()
	var height := f.get_32()
	var data_size := f.get_32()
	var data := f.get_buffer(data_size)
	var im = Image.new()
	im.create_from_data(width, height, false, format, data)
	return im


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
	
	var f := File.new()
	var err = f.open(fpath, File.READ)
	if err != OK:
		_logger.error("Could not load cached image from {0}, error {1}" \
			.format([fpath, err]))
		return null
	
	f.seek(info.data_offset)
	var im = _read_image(f)
	f.close()
	
	assert(im != null)
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
		
	# Delete all cache files
	while true:
		var fpath := dir.get_next()
		if fpath == "":
			break
		if fpath.ends_with(".cache"):
			_logger.debug(str("Deleting ", fpath))
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
		
		if len(to_save) == 0:
			_save_semaphore.wait()
			continue
			
		var f := File.new()
		var path := ""
		
		for item in to_save:
			# Keep re-using the same file if we did not change path.
			# It makes I/Os faster.
			if item.path != path:
				path = item.path
				if f.is_open():
					f.close()
				var err := f.open(path, File.READ_WRITE)
				if err != OK:
					call_deferred("_on_error", "Could not open file {0}, error {1}" \
						.format([path, err]))
					continue
			
			f.seek(item.data_offset)
			_write_image(f, item.image)
			# Notify main thread.
			# The thread does not modify data, only reads it.
			call_deferred("_on_image_saved", item)


func _on_error(msg: String):
	_logger.error(msg)


func _on_image_saved(item: Dictionary):
	_logger.debug(str("Saved ", item.path))
	item.saved = true
	# Should remove image from memory (for usually being last reference)
	item.image = null


