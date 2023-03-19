@tool
extends Control


@export var cursor_texture : Texture
@export var out_of_range_texture : Texture

@onready var _sprite : Sprite2D = $Cursor

var _pos := Vector2()
var _rot := 0.0


func set_cursor_position_normalized(pos_norm: Vector2, dir: Vector2):
	if Rect2(0, 0, 1, 1).has_point(pos_norm):
		_sprite.texture = cursor_texture
	else:
		pos_norm.x = clampf(pos_norm.x, 0.0, 1.0)
		pos_norm.y = clampf(pos_norm.y, 0.0, 1.0)
		_sprite.texture = out_of_range_texture
	
	_sprite.position = pos_norm * size
	_sprite.rotation = dir.angle()

