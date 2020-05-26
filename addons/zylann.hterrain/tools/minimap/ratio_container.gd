# Simple container keeping its children under the same aspect ratio

tool
extends Container


export(float) var ratio := 1.0


func _notification(what: int):
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children2()


# TODO Function with ugly name to workaround a Godot 3.1 issue
# See https://github.com/godotengine/godot/pull/38396
func _sort_children2():
	for i in get_child_count():
		var child = get_child(i)
		if not (child is Control):
			continue
		var w = rect_size.x
		var h = rect_size.x / ratio
		
		if h > rect_size.y:
			h = rect_size.y
			w = h * ratio

		var rect := Rect2(0, 0, w, h)
		
		fit_child_in_rect(child, rect)
		
