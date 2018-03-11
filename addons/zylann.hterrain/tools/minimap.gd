tool
extends Control


var _terrain = null


func _enter_tree():
	set_process(false)


func set_terrain(node):
	if _terrain != node:
		_terrain = node
		set_process(_terrain != null)


func _process(delta):
	if _terrain != null:
		update()


func _draw():
	if _terrain != null:
		var lod_count = _terrain.get_lod_count()

		if lod_count > 0:
			# Fit drawing to rect
			
			var size = 1 << (lod_count - 1)
			var vsize = rect_size
			draw_set_transform(Vector2(0, 0), 0, Vector2(vsize.x / size, vsize.y / size))

			_terrain._edit_debug_draw(self)

