@tool
extends Node

const HT_Painter = preload("./../painter.gd")
const HT_Brush = preload("./../brush.gd")

const HT_ColorShader = preload("../shaders/color.gdshader")

var _painter : HT_Painter
var _brush : HT_Brush


func _init():
	var p = HT_Painter.new()
	# The name is just for debugging
	p.set_name("Painter")
	add_child(p)
	_painter = p

	_brush = HT_Brush.new()


func set_image_texture(image: Image, texture: ImageTexture):
	_painter.set_image(image, texture)


func get_brush() -> HT_Brush:
	return _brush


# This may be called from an `_input` callback
func paint_input(position: Vector2, pressure: float):
	var p : HT_Painter = _painter
	
	if not _brush.configure_paint_input([p], position, pressure):
		return
	
	p.set_brush_shader(HT_ColorShader)
	p.set_brush_shader_param("u_color", Color(0,0,0,1))
	#p.set_image(_image, _texture)
	p.paint_input(position)
