tool
extends Node

const Painter = preload("./../painter.gd")
const Brush = preload("./../brush.gd")

const ColorShader = preload("../shaders/color.shader")

var _painter : Painter
var _brush : Brush


func _init():
	var p = Painter.new()
	# The name is just for debugging
	p.set_name("Painter")
	add_child(p)
	_painter = p

	_brush = Brush.new()


func set_image_texture(image: Image, texture: ImageTexture):
	_painter.set_image(image, texture)


func get_brush() -> Brush:
	return _brush


# This may be called from an `_input` callback
func paint_input(position: Vector2, pressure: float):
	var p : Painter = _painter
	
	if not _brush.configure_paint_input([p], position, pressure):
		return
	
	p.set_brush_shader(ColorShader)
	#p.set_brush_shader_param("u_factor", _opacity)
	p.set_brush_shader_param("u_color", Color(0,0,0,1))
	#p.set_image(_image, _texture)
	p.paint_input(position)
