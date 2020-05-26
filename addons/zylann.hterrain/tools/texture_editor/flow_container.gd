tool
extends Container

const SEPARATION = 2


func _notification(what: int):
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children2()


# TODO Function with ugly name to workaround a Godot 3.1 issue
# See https://github.com/godotengine/godot/pull/38396
func _sort_children2():
	#print("Sort")
	var max_x := rect_size.x - SEPARATION
	var pos := Vector2(SEPARATION, SEPARATION)
	var line_height := 0
	
	for i in get_child_count():
		var child = get_child(i)
		if not child is Control:
			continue
		
		var rect = child.get_rect()

		if rect.size.y > line_height:
			line_height = rect.size.y
		
		if pos.x + rect.size.x > max_x:
			pos.x = SEPARATION
			pos.y += line_height + SEPARATION
			line_height = rect.size.y
		
		rect.position = pos
		fit_child_in_rect(child, rect)
		
		pos.x += rect.size.x + SEPARATION
	
	rect_min_size.y = pos.y + line_height

