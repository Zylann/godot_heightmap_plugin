@tool

# Used to store temporary images on disk.
# This is useful for undo/redo as image edition can quickly fill up memory.

# Image data is stored in archive files together,
# because when dealing with many images it speeds up filesystem I/O on Windows.
# If the file exceeds a predefined size, a new one is created.
# Writing to disk is performed from a thread, to leave the main thread responsive.
# However if you want to obtain an image back while it didn't save yet, the main thread will block.
# When the application or plugin is closed, the files get cleared.

const HT_Logger = preload("./logger.gd")
const HT_Errors = preload("./errors.gd")

const CACHE_FILE_SIZE_THRESHOLD = 1048576
# For debugging
const USE_THREAD = true

var _cache_dir := ""
var _next_id := 0
var _session_id := ""
var _cache_image_info := {}
var _logger = HT_Logger.get_for(self)
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
	if not DirAccess.dir_exists_absolute(_cache_dir):
		var err := DirAccess.make_dir_absolute(_cache_dir)
		if err != OK:
			_logger.error("Could not create directory {0}: {1}" \
				.format([_cache_dir, HT_Errors.get_message(err)]))
	_save_thread_running = true 
	if USE_THREAD:
		_saving_thread.start(_save_thread_func)


# TODO Cannot cleanup the cache in destructor!
# Godot doesn't allow me to call clear()...
# https://github.com/godotengine/godot/issues/31166
func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		#clear()
		_save_thread_running = false
		_save_semaphore.post()
		if USE_THREAD:
			_saving_thread.wait_to_finish()


func _create_new_cache_file(fpath: String):
	var f := FileAccess.open(fpath, FileAccess.WRITE)
	if f == null:
		var err = FileAccess.get_open_error()
		_logger.error("Failed to create new cache file {0}: {1}" \
			.format([fpath, HT_Errors.get_message(err)]))
		return


func _get_current_cache_file_name() -> String:
	return _cache_dir.path_join(str(_session_id, "_", _current_cache_file_index, ".cache"))


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
	
	if not USE_THREAD:
		var before = Time.get_ticks_msec()
		while len(_save_queue) > 0:
			_save_thread_func()
			if Time.get_ticks_msec() - before > 10_000:
				_logger.error("Taking to long to empty save queue in non-threaded mode!")
	
	return id


static func _get_image_data_size(im: Image) -> int:
	return 1 + 4 + 4 + 4 + len(im.get_data())


static func _write_image(f: FileAccess, im: Image):
	f.store_8(im.get_format())
	f.store_32(im.get_width())
	f.store_32(im.get_height())
	var data : PackedByteArray = im.get_data()
	f.store_32(len(data))
	f.store_buffer(data)


static func _read_image(f: FileAccess) -> Image:
	var format := f.get_8()
	var width := f.get_32()
	var height := f.get_32()
	var data_size := f.get_32()
	var data := f.get_buffer(data_size)
	var im := Image.create_from_data(width, height, false, format, data)
	return im


func load_image(id: int) -> Image:
	var info := _cache_image_info[id] as Dictionary
	
	var timeout := 5.0
	var time_before := Time.get_ticks_msec()
	# We could just grab `image`, because the thread only reads it.
	# However it's still not safe to do that if we write or even lock it,
	# so we have to assume it still has ownership of it.
	while not info.saved:
		OS.delay_msec(8.0)
		_logger.debug("Waiting for cached image {0}...".format([id]))
		if Time.get_ticks_msec() - time_before > timeout:
			_logger.error("Could not get image {0} from cache. Something went wrong.".format([id]))
			return null
	
	var fpath := info.path as String
	
	var f := FileAccess.open(fpath, FileAccess.READ)
	if f == null:
		var err := FileAccess.get_open_error()
		_logger.error("Could not load cached image from {0}: {1}" \
			.format([fpath, HT_Errors.get_message(err)]))
		return null
	
	f.seek(info.data_offset)
	var im = _read_image(f)
	f = null # close file
	
	assert(im != null)
	return im


func clear():
	_logger.debug("Clearing image cache")
	
	var dir := DirAccess.open(_cache_dir)
	if dir == null:
		#var err = DirAccess.get_open_error()
		_logger.error("Could not open image file cache directory '{0}'" \
			.format([_cache_dir]))
		return
	
	dir.include_hidden = false
	dir.include_navigational = false

	var err := dir.list_dir_begin()
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
				_logger.error("Failed to delete cache file '{0}': {1}" \
					.format([_cache_dir.path_join(fpath), HT_Errors.get_message(err)]))

	_cache_image_info.clear()


func _save_thread_func():
	# Threads keep a reference to the object of the function they run.
	# So if the object is a Reference, and that reference owns the thread... we get a cycle.
	# We can break the cycle by removing 1 to the count inside the thread.
	# The thread's reference will never die unexpectedly because we stop and destroy the thread
	# in the destructor of the reference.
	# If that workaround explodes one day, another way could be to use an intermediary instance
	# extending Object, and run a function on that instead.
	#
	# I added this in Godot 3, and it seems to still be relevant in Godot 4 because if I don't
	# do it, objects are leaking.
	#
	# BUT it seems to end up triggering a crash in debug Godot builds due to unrefing RefCounted
	# with refcount == 0, so I guess it's wrong now?
	# So basically, either I do it and I risk a crash,
	# or I don't do it and then it causes a leak... 
	# TODO Make this shit use `Object`
	# 
	# if USE_THREAD:
	# 	unreference()

	while _save_thread_running:
		_save_queue_mutex.lock()
		var to_save := _save_queue.duplicate(false)
		_save_queue.clear()
		_save_queue_mutex.unlock()

		if len(to_save) == 0:
			if USE_THREAD:
				_save_semaphore.wait()
			continue
			
		var f : FileAccess
		var path := ""
		
		for item in to_save:
			# Keep re-using the same file if we did not change path.
			# It makes I/Os faster.
			if item.path != path:
				# Close previous file
				f = null

				path = item.path

				f = FileAccess.open(path, FileAccess.READ_WRITE)
				if f == null:
					var err := FileAccess.get_open_error()
					call_deferred("_on_error", "Could not open file {0}: {1}" \
						.format([path, HT_Errors.get_message(err)]))
					path = ""
					continue
			
			f.seek(item.data_offset)
			_write_image(f, item.image)
			# Notify main thread.
			# The thread does not modify data, only reads it.
			call_deferred("_on_image_saved", item)
		
		# Workaround some weird behavior in Godot 4:
		# when the next loop runs, `f` IS NOT CLEANED UP. A reference is still held before `var f`
		# is reached, which means the file is still locked while the thread is waiting on the
		# semaphore... so I have to explicitely "close" the file here.
		f = null
		
		if not USE_THREAD:
			break


func _on_error(msg: String):
	_logger.error(msg)


func _on_image_saved(item: Dictionary):
	_logger.debug(str("Saved ", item.path))
	item.saved = true
	# Should remove image from memory (for usually being last reference)
	item.image = null


