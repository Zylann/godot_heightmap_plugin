@tool

# Brush properties (shape, transform, timing and opacity).
# Other attributes like color, height or texture index are tool-specific,
# while brush properties apply to all of them.
# This is separate from Painter because it could apply to multiple Painters at once.

const HT_Errors = preload("../../util/errors.gd")
const HT_Painter = preload("./painter.gd")

const SHAPES_DIR = "addons/zylann.hterrain/tools/brush/shapes"
const DEFAULT_BRUSH_TEXTURE_PATH = SHAPES_DIR + "/round2.exr"
# Reasonable size for sliders to be usable
const MAX_SIZE_FOR_SLIDERS = 500
# Absolute size limit. Terrains can't be larger than that, and it will be very slow to paint
const MAX_SIZE = 4000

signal size_changed(new_size)
signal shapes_changed
signal shape_index_changed

var _size := 32
var _opacity := 1.0
var _random_rotation := false
var _pressure_enabled := false
var _pressure_over_scale := 0.5
var _pressure_over_opacity := 0.5
# TODO Rename stamp_*?
var _frequency_distance := 0.0
var _frequency_time_ms := 0
# Array of greyscale textures
var _shapes : Array[Texture2D] = []

var _shape_index := 0
var _shape_cycling_enabled := false
var _prev_position := Vector2(-999, -999)
var _prev_time_ms := 0


func set_size(size: int):
	if size < 1:
		size = 1
	if size != _size:
		_size = size
		size_changed.emit(_size)


func get_size() -> int:
	return _size


func set_opacity(opacity: float):
	_opacity = clampf(opacity, 0.0, 1.0)


func get_opacity() -> float:
	return _opacity


func set_random_rotation_enabled(enabled: bool):
	_random_rotation = enabled


func is_random_rotation_enabled() -> bool:
	return _random_rotation


func set_pressure_enabled(enabled: bool):
	_pressure_enabled = enabled


func is_pressure_enabled() -> bool:
	return _pressure_enabled


func set_pressure_over_scale(amount: float):
	_pressure_over_scale = clampf(amount, 0.0, 1.0)


func get_pressure_over_scale() -> float:
	return _pressure_over_scale


func set_pressure_over_opacity(amount: float):
	_pressure_over_opacity = clampf(amount, 0.0, 1.0)


func get_pressure_over_opacity() -> float:
	return _pressure_over_opacity


func set_frequency_distance(d: float):
	_frequency_distance = maxf(d, 0.0)


func get_frequency_distance() -> float:
	return _frequency_distance


func set_frequency_time_ms(t: int):
	if t < 0:
		t = 0
	_frequency_time_ms = t


func get_frequency_time_ms() -> int:
	return _frequency_time_ms


func set_shapes(shapes: Array[Texture2D]):
	assert(len(shapes) >= 1)
	for s in shapes:
		assert(s != null)
		assert(s is Texture2D)
	_shapes = shapes.duplicate(false)
	if _shape_index >= len(_shapes):
		_shape_index = len(_shapes) - 1
	shapes_changed.emit()


func get_shapes() -> Array[Texture2D]:
	return _shapes.duplicate(false)


func get_shape(i: int) -> Texture2D:
	return _shapes[i]


func get_shape_index() -> int:
	return _shape_index


func set_shape_index(i: int):
	assert(i >= 0)
	assert(i < len(_shapes))
	_shape_index = i
	shape_index_changed.emit()


func set_shape_cycling_enabled(enable: bool):
	_shape_cycling_enabled = enable


func is_shape_cycling_enabled() -> bool:
	return _shape_cycling_enabled


static func load_shape_from_image_file(fpath: String, logger, retries := 1) -> Texture2D:
	var im := Image.new()
	var err := im.load(fpath)
	if err != OK:
		if retries > 0:
			# TODO There is a bug with Godot randomly being unable to load images.
			# See https://github.com/Zylann/godot_heightmap_plugin/issues/219
			# Attempting to workaround this by retrying (I suspect it's because of non-initialized
			# variable in Godot's C++ code...)
			logger.error("Could not load image at '{0}', error {1}. Retrying..." \
				.format([fpath, HT_Errors.get_message(err)]))
			return load_shape_from_image_file(fpath, logger, retries - 1)
		else:
			logger.error("Could not load image at '{0}', error {1}" \
				.format([fpath, HT_Errors.get_message(err)]))
			return null
	var tex := ImageTexture.create_from_image(im)
	return tex


# Call this while handling mouse or pen input.
# If it returns false, painting should not run.
func configure_paint_input(painters: Array[HT_Painter], position: Vector2, pressure: float) -> bool:
	assert(len(_shapes) != 0)
	
	# DEBUG
	#pressure = 0.5 + 0.5 * sin(OS.get_ticks_msec() / 200.0)
	
	if position.distance_to(_prev_position) < _frequency_distance:
		return false
	var now := Time.get_ticks_msec()
	if (now - _prev_time_ms) < _frequency_time_ms:
		return false
	_prev_position = position
	_prev_time_ms = now
	
	for painter_index in len(painters):
		var painter : HT_Painter = painters[painter_index]
		
		if _random_rotation:
			painter.set_brush_rotation(randf_range(-PI, PI))
		else:
			painter.set_brush_rotation(0.0)

		painter.set_brush_texture(_shapes[_shape_index])
		painter.set_brush_size(_size)
		
		if _pressure_enabled:
			painter.set_brush_scale(lerpf(1.0, pressure, _pressure_over_scale))
			painter.set_brush_opacity(_opacity * lerpf(1.0, pressure, _pressure_over_opacity))
		else:
			painter.set_brush_scale(1.0)
			painter.set_brush_opacity(_opacity)
		
		#painter.paint_input(position)

	if _shape_cycling_enabled:
		_shape_index += 1
		if _shape_index >= len(_shapes):
			_shape_index = 0
	
	return true


# Call this when the user releases the pen or mouse button
func on_paint_end():
	_prev_position = Vector2(-999, -999)
	_prev_time_ms = 0


