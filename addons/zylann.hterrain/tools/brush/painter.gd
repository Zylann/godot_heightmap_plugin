
# Core logic to paint a texture using shaders, with undo/redo support.
# Operations are delayed so results are only available the next frame.
# This doesn't implement UI or brush behavior, only rendering logic.
#
# Note: due to the absence of channel separation function in Image,
# you may need to use multiple painters at once if your application exploits multiple channels.
# Example: when painting a heightmap, it would be doable to output height in R, normalmap in GB, and
# then separate channels in two images at the end.

tool
extends Node

const HT_Logger = preload("../../util/logger.gd")
const HT_Util = preload("../../util/util.gd")
const HT_NoBlendShader = preload("./no_blend.gdshader")

const UNDO_CHUNK_SIZE = 64

# All painting shaders can use these common parameters
const SHADER_PARAM_SRC_TEXTURE = "u_src_texture"
const SHADER_PARAM_SRC_RECT = "u_src_rect"
const SHADER_PARAM_OPACITY = "u_opacity"

const _API_SHADER_PARAMS = [
	SHADER_PARAM_SRC_TEXTURE,
	SHADER_PARAM_SRC_RECT,
	SHADER_PARAM_OPACITY
]

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

# - Viewport (size of edited region + margin to allow quad rotation)
#   |- Background
#   |    Fills pixels with unmodified source image.
#   |- Brush sprite
#        Size of actual brush, scaled/rotated, modifies source image.
#        Assigned texture is the brush texture, src image is a shader param

var _viewport : Viewport
var _viewport_bg_sprite : Sprite
var _viewport_brush_sprite : Sprite
var _brush_size := 32
var _brush_scale := 1.0
var _brush_position := Vector2()
var _brush_opacity := 1.0
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
var _logger = HT_Logger.get_for(self)


func _init():
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
	
	# There is no "blend_disabled" option on standard CanvasItemMaterial...
	var no_blend_material := ShaderMaterial.new()
	no_blend_material.shader = HT_NoBlendShader
	_viewport_bg_sprite = Sprite.new()
	_viewport_bg_sprite.centered = false
	_viewport_bg_sprite.material = no_blend_material
	_viewport.add_child(_viewport_bg_sprite)
	
	_viewport_brush_sprite = Sprite.new()
	_viewport_brush_sprite.centered = true
	_viewport_brush_sprite.material = _brush_material
	_viewport_brush_sprite.position = _viewport.size / 2.0
	_viewport.add_child(_viewport_brush_sprite)
	
	add_child(_viewport)


func set_debug_display(dd: TextureRect):
	_debug_display = dd
	_debug_display.texture = _viewport.get_texture()


func set_image(image: Image, texture: ImageTexture):
	assert((image == null and texture == null) or (image != null and texture != null))
	_image = image
	_texture = texture
	_viewport_bg_sprite.texture = _texture
	_brush_material.set_shader_param(SHADER_PARAM_SRC_TEXTURE, _texture)
	if image != null:
		_viewport.hdr = image.get_format() in _hdr_formats
	#print("PAINTER VIEWPORT HDR: ", _viewport.hdr)


# Sets the size of the brush in pixels.
# This will cause the internal viewport to resize, which is expensive.
# If you need to frequently change brush size during a paint stroke, prefer using scale instead.
func set_brush_size(new_size: int):
	_brush_size = new_size


func get_brush_size() -> int:
	return _brush_size


func set_brush_rotation(rotation: float):
	_viewport_brush_sprite.rotation = rotation


func get_brush_rotation() -> float:
	return _viewport_bg_sprite.rotation


# The difference between size and scale, is that size is in pixels, while scale is a multiplier.
# Scale is also a lot cheaper to change, so you may prefer changing it instead of size if that
# happens often during a painting stroke.
func set_brush_scale(s: float):
	_brush_scale = clamp(s, 0.0, 1.0)
	#_viewport_brush_sprite.scale = Vector2(s, s)


func get_brush_scale() -> float:
	return _viewport_bg_sprite.scale.x


func set_brush_opacity(opacity: float):
	_brush_opacity = clamp(opacity, 0.0, 1.0)


func get_brush_opacity() -> float:
	return _brush_opacity


func set_brush_texture(texture: Texture):
	_viewport_brush_sprite.texture = texture


func set_brush_shader(shader: Shader):
	if _brush_material.shader != shader:
		_brush_material.shader = shader


func set_brush_shader_param(p: String, v):
	assert(not _API_SHADER_PARAMS.has(p))
	_modified_shader_params[p] = true
	_brush_material.set_shader_param(p, v)


func clear_brush_shader_params():
	for key in _modified_shader_params:
		_brush_material.set_shader_param(key, null)
	_modified_shader_params.clear()


# If we want to be able to rotate the brush quad every frame,
# we must prepare a bigger viewport otherwise the quad will not fit inside
static func _get_size_fit_for_rotation(src_size: Vector2) -> Vector2:
	var d = int(ceil(src_size.length()))
	return Vector2(d, d)


# You must call this from an `_input` function or similar.
func paint_input(center_pos: Vector2):
	var vp_size = _get_size_fit_for_rotation(Vector2(_brush_size, _brush_size))
	if _viewport.size != vp_size:
		# Do this lazily so the brush slider won't lag while adjusting it
		# TODO An "sliding_ended" handling might produce better user experience
		_viewport.size = vp_size
		_viewport_brush_sprite.position = _viewport.size / 2.0

	# Need to floor the position in case the brush has an odd size
	var brush_pos := (center_pos - _viewport.size * 0.5).round()
	_viewport.render_target_update_mode = Viewport.UPDATE_ONCE
	_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ONLY_NEXT_FRAME
	_viewport_bg_sprite.position = -brush_pos
	_brush_position = brush_pos
	_cmd_paint = true
	
	# We want this quad to have a specific size, regardless of the texture assigned to it
	_viewport_brush_sprite.scale = \
		_brush_scale * Vector2(_brush_size, _brush_size) / _viewport_brush_sprite.texture.get_size()

	# Using a Color because Godot doesn't understand vec4
	var rect := Color()
	rect.r = brush_pos.x / _texture.get_width()
	rect.g = brush_pos.y / _texture.get_height()
	rect.b = _viewport.size.x / _texture.get_width()
	rect.a = _viewport.size.y / _texture.get_height()
	# In order to make sure that u_brush_rect is never bigger than the brush:
	# 1. we ceil() the result of lower-left corner
	# 2. we floor() the result of upper-right corner
	# and then rederive width and height from the result
#	var half_brush:Vector2 = Vector2(_brush_size, _brush_size) / 2
#	var brush_LL := (center_pos - half_brush).ceil()
#	var brush_UR := (center_pos + half_brush).floor()
#	rect.r = brush_LL.x / _texture.get_width()
#	rect.g = brush_LL.y / _texture.get_height()
#	rect.b = (brush_UR.x - brush_LL.x) / _texture.get_width()
#	rect.a = (brush_UR.y - brush_LL.y) / _texture.get_height()
	_brush_material.set_shader_param(SHADER_PARAM_SRC_RECT, rect)
	_brush_material.set_shader_param(SHADER_PARAM_OPACITY, _brush_opacity)


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
		var src_w : int = min(max(_viewport.size.x - src_x, 0), _texture.get_width() - dst_x)
		var src_h : int = min(max(_viewport.size.y - src_y, 0), _texture.get_height() - dst_y)
		
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
			#print("Marking chunk ", Vector2(cx, cy))
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
