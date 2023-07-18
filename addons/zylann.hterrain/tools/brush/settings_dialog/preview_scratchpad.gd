@tool
extends Control

const HT_PreviewPainter = preload("./preview_painter.gd")
# TODO Can't preload because it causes the plugin to fail loading if assets aren't imported
#const HT_DefaultBrushTexture = preload("../shapes/round2.exr")
const HT_Brush = preload("../brush.gd")
const HT_Logger = preload("../../../util/logger.gd")
const HT_EditorUtil = preload("../../util/editor_util.gd")
const HT_Util = preload("../../../util/util.gd")

@onready var _texture_rect : TextureRect = $TextureRect
@onready var _painter : HT_PreviewPainter = $Painter

var _logger := HT_Logger.get_for(self)


func _ready():
	if HT_Util.is_in_edited_scene(self):
		# If it runs in the edited scene,
		# saving the scene would also save the ImageTexture in it...
		return
	reset_image()
	# Default so it doesn't crash when painting and can be tested
	var default_brush_texture = \
		HT_EditorUtil.load_texture(HT_Brush.DEFAULT_BRUSH_TEXTURE_PATH, _logger)
	_painter.get_brush().set_shapes([default_brush_texture])


func reset_image():
	var image = Image.create(_texture_rect.size.x, _texture_rect.size.y, false, Image.FORMAT_RGB8)
	image.fill(Color(1,1,1))
	
	# TEST
#	var fnl = FastNoiseLite.new()
#	for y in image.get_height():
#		for x in image.get_width():
#			var g = 0.5 + 0.5 * fnl.get_noise_2d(x, y)
#			image.set_pixel(x, y, Color(g, g, g, 1.0))
	
	var texture = ImageTexture.create_from_image(image)
	_texture_rect.texture = texture
	_painter.set_image_texture(image, texture)


func get_painter() -> HT_PreviewPainter:
	return _painter


func _gui_input(event):
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_painter.paint_input(event.position, event.pressure)
		queue_redraw()
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# TODO `pressure` is not available on button events
				# So I have to assume zero... which means clicks do not paint anything?
				_painter.paint_input(event.position, 0.0)
			else:
				_painter.get_brush().on_paint_end()


func _draw():
	var mpos = get_local_mouse_position()
	var brush = _painter.get_brush()
	draw_arc(mpos, 0.5 * brush.get_size(), -PI, PI, 32, Color(1, 0.2, 0.2), 2.0, true)

