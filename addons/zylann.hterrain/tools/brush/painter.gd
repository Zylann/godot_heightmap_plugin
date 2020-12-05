
# Core logic to paint a texture using shaders, with undo/redo support.
# Operations are delayed so results are only available the next frame.
# This doesn't implement UI, only the painting logic.
#
# Note: due to the absence of channel separation function in Image,
# you may need to use multiple painters at once if your application exploits multiple channels.
# Example: when painting a heightmap, it would be doable to output height in R, normalmap in GB, and
# then separate channels in two images at the end.

tool
extends Node

const Logger = preload("../../util/logger.gd")
const Util = preload("../../util/util.gd")

const UNDO_CHUNK_SIZE = 64
const BRUSH_TEXTURE_SHADER_PARAM = "u_brush_texture"

# Emitted when a region of the painted texture actually changed.
# Note 1: the image might not have changed yet at this point.
# Note 2: the user could still be in the middle of dragging the brush.
signal texture_region_changed(rect)

# Godot doesn't support 32-bit float rendering, so painting is limited to 16-bit depth.
# We should get this in Godot 4.0, either as Compute or renderer improvement
const _hdr_formats = [
	Image.FORMAT_RH,
	Image.FORMAT_RGH,
	Image.FORMAT_RGBH,
	Image.FORMAT_RGBAH
]

const _supported_formats = [
	Image.FORMAT_R8,
	Image.FORMAT_RG8,
	Image.FORMAT_RGB8,
	Image.FORMAT_RGBA8,
	Image.FORMAT_RH,
	Image.FORMAT_RGH,
	Image.FORMAT_RGBH,
	Image.FORMAT_RGBAH
]

var _viewport : Viewport
var _viewport_sprite : Sprite
var _brush_size := 32
var _brush_position := Vector2()
var _brush_texture : Texture
var _last_brush_position := Vector2()
var _brush_material := ShaderMaterial.new()
var _image : Image
var _texture : ImageTexture
var _cmd_paint := false
var _pending_paint_render := false
var _modified_chunks := {}
var _modified_shader_params := {}

var _debug_display : TextureRect
var _logger = Logger.get_for(self)


func _ready():
	if Util.is_in_edited_scene(self):
		return
	_viewport = Viewport.new()
	_viewport.size = Vector2(_brush_size, _brush_size)
	_viewport.render_target_update_mode = Viewport.UPDATE_ONCE
	_viewport.render_target_v_flip = true
	_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ONLY_NEXT_FRAME
	_viewport.hdr = false
	_viewport.transparent_bg = true
	# Apparently HDR doesn't work if this is set to 2D... so let's waste a depth buffer :/
	#_viewport.usage = Viewport.USAGE_2D
	#_viewport.keep_3d_linear
	
	_viewport_sprite = Sprite.new()
	_viewport_sprite.centered = false
	_viewport_sprite.material = _brush_material
	_viewport.add_child(_viewport_sprite)
	
	add_child(_viewport)


func set_debug_display(dd: TextureRect):
	_debug_display = dd
	_debug_display.texture = _viewport.get_texture()


func set_image(image: Image, texture: ImageTexture):
	assert((image == null and texture == null) or (image != null and texture != null))
	_image = image
	_texture = texture
	_viewport_sprite.texture = _texture
	if image != null:
		_viewport.hdr = image.get_format() in _hdr_formats
	#print("PAINTER VIEWPORT HDR: ", _viewport.hdr)


func set_brush_size(new_size: int):
	_brush_size = new_size


func get_brush_size() -> int:
	return _brush_size


func set_brush_texture(texture: Texture):
	_brush_material.set_shader_param(BRUSH_TEXTURE_SHADER_PARAM, texture)


func set_brush_shader(shader: Shader):
	if _brush_material.shader != shader:
		_brush_material.shader = shader


func set_brush_shader_param(p: String, v):
	_modified_shader_params[p] = true
	_brush_material.set_shader_param(p, v)


func clear_brush_shader_params():
	for key in _modified_shader_params:
		_brush_material.set_shader_param(key, null)
	_modified_shader_params.clear()


# You must call this from an `_input` function or similar.
func paint_input(center_pos: Vector2):
	var vp_size = Vector2(_brush_size, _brush_size)
	if _viewport.size != vp_size:
		# Do this lazily so the brush slider won't lag while adjusting it
		# TODO An "sliding_ended" handling might produce better user experience
		_viewport.size = vp_size

	# Need to floor the position in case the brush has an odd size
	var brush_pos := (center_pos - Vector2(_brush_size, _brush_size) * 0.5).round()
	_viewport.render_target_update_mode = Viewport.UPDATE_ONCE
	_viewport_sprite.position = -brush_pos
	_brush_position = brush_pos
	_cmd_paint = true

	# Using a Color because Godot doesn't understand vec4
	var rect := Color()
	rect.r = brush_pos.x / _texture.get_width()
	rect.g = brush_pos.y / _texture.get_height()
	rect.b = _brush_size / _texture.get_width()
	rect.a = _brush_size / _texture.get_height()
	_brush_material.set_shader_param("u_texture_rect", rect)


# Don't commit until this is false
func is_operation_pending() -> bool:
	return _pending_paint_render or _cmd_paint


# Applies changes to the Image, and returns modified chunks for UndoRedo.
func commit() -> Dictionary:
	if is_operation_pending():
		_logger.error("Painter commit() was called while an operation is still pending")
	return _commit_modified_chunks()


func has_modified_chunks() -> bool:
	return len(_modified_chunks) > 0


func _process(delta: float):
	if _pending_paint_render:
		_pending_paint_render = false
	
		#print("Paint result at frame ", Engine.get_frames_drawn())
		var data := _viewport.get_texture().get_data()
		data.convert(_image.get_format())
		
		var brush_pos = _last_brush_position
		
		var dst_x : int = clamp(brush_pos.x, 0, _texture.get_width())
		var dst_y : int = clamp(brush_pos.y, 0, _texture.get_height())
		
		var src_x : int = max(-brush_pos.x, 0)
		var src_y : int = max(-brush_pos.y, 0)
		var src_w : int = min(max(_brush_size - src_x, 0), _texture.get_width() - dst_x)
		var src_h : int = min(max(_brush_size - src_y, 0), _texture.get_height() - dst_y)
		
		if src_w != 0 and src_h != 0:
			_mark_modified_chunks(dst_x, dst_y, src_w, src_h)
			VisualServer.texture_set_data_partial(
				_texture.get_rid(), data, src_x, src_y, src_w, src_h, dst_x, dst_y, 0, 0)
			emit_signal("texture_region_changed", Rect2(dst_x, dst_y, src_w, src_h))
	
	# Input is handled just before process, so we still have to wait till next frame
	if _cmd_paint:
		_pending_paint_render = true
		_last_brush_position = _brush_position
		# Consume input
		_cmd_paint = false


func _mark_modified_chunks(bx: int, by: int, bw: int, bh: int):
	var cs := UNDO_CHUNK_SIZE
	
	var cmin_x := bx / cs
	var cmin_y := by / cs
	var cmax_x := (bx + bw - 1) / cs + 1
	var cmax_y := (by + bh - 1) / cs + 1
	
	for cy in range(cmin_y, cmax_y):
		for cx in range(cmin_x, cmax_x):
			_modified_chunks[Vector2(cx, cy)] = true


func _commit_modified_chunks() -> Dictionary:
	var time_before := OS.get_ticks_msec()
	
	var cs := UNDO_CHUNK_SIZE
	var chunks_positions := []
	var chunks_initial_data := []
	var chunks_final_data := []

	#_logger.debug("About to commit ", len(_modified_chunks), " chunks")
	
	# TODO get_data_partial() would be nice...
	var final_image := _texture.get_data()
	for cpos in _modified_chunks:
		var cx : int = cpos.x
		var cy : int = cpos.y
		
		var x := cx * cs
		var y := cy * cs
		var w : int = min(cs, _image.get_width() - x)
		var h : int = min(cs, _image.get_height() - y)
		
		var rect := Rect2(x, y, w, h)
		var initial_data := _image.get_rect(rect)
		var final_data := final_image.get_rect(rect)
		
		chunks_positions.append(cpos)
		chunks_initial_data.append(initial_data)
		chunks_final_data.append(final_data)
		#_image_equals(initial_data, final_data)
		
		# TODO We could also just replace the image with `final_image`...
		# TODO Use `final_data` instead?
		_image.blit_rect(final_image, rect, rect.position)
	
	_modified_chunks.clear()
	
	var time_spent := OS.get_ticks_msec() - time_before
	_logger.debug("Spent {0} ms to commit paint operation".format([time_spent]))
	
	return {
		"chunk_positions": chunks_positions,
		"chunk_initial_datas": chunks_initial_data,
		"chunk_final_datas": chunks_final_data
	}


# DEBUG
#func _input(event):
#	if event is InputEventKey:
#		if event.pressed:
#			if event.control and event.scancode == KEY_SPACE:
#				print("Saving painter viewport ", name)
#				var im = _viewport.get_texture().get_data()
#				im.convert(Image.FORMAT_RGBA8)
#				im.save_png(str("test_painter_viewport_", name, ".png"))


#static func _image_equals(im_a: Image, im_b: Image) -> bool:
#	if im_a.get_size() != im_b.get_size():
#		print("Diff size: ", im_a.get_size, ", ", im_b.get_size())
#		return false
#	if im_a.get_format() != im_b.get_format():
#		print("Diff format: ", im_a.get_format(), ", ", im_b.get_format())
#		return false
#	im_a.lock()
#	im_b.lock()
#	for y in im_a.get_height():
#		for x in im_a.get_width():
#			var ca = im_a.get_pixel(x, y)
#			var cb = im_b.get_pixel(x, y)
#			if ca != cb:
#				print("Diff pixel ", x, ", ", y)
#				return false
#	im_a.unlock()
#	im_b.unlock()
#	print("SAME")
#	return true
