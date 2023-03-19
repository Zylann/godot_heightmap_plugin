
# If you make a container-based UI inside a WindowDialog, there is a chance it will overflow
# because WindowDialogs don't adjust by themselves. This happens when the user has a different
# font size than yours, and can cause controls to be unusable (like buttons at the bottom).
# This script adjusts the size of the parent WindowDialog based on the first Container it finds
# when the node becomes visible.

@tool
# Needs to be a Control, otherwise we don't receive the notification...
extends Control

const HT_Util = preload("../../util/util.gd")


func _notification(what: int):
	if HT_Util.is_in_edited_scene(self):
		return
	if is_inside_tree() and what == Control.NOTIFICATION_VISIBILITY_CHANGED:
		#print("Visible ", is_visible_in_tree(), ", ", visible)
		call_deferred("_fit_to_contents")


func _fit_to_contents():
	var dialog : Window = get_parent()
	for child in dialog.get_children():
		if child is Container:
			var child_rect : Rect2 = child.get_global_rect()
			var dialog_rect := Rect2(Vector2(), dialog.size)
			#print("Dialog: ", dialog_rect, ", contents: ", child_rect, " ", child.get_path())
			if not dialog_rect.encloses(child_rect):
				var margin : Vector2 = child.get_rect().position
				#print("Fitting ", dialog.get_path(), " from ", dialog.rect_size, 
				#	" to ", child_rect.size + margin * 2.0)
				dialog.min_size = child_rect.size + margin * 2.0


#func _process(delta):
#	update()

# DEBUG
#func _draw():
#	var self_global_pos = get_global_rect().position
#
#	var dialog : Control = get_parent()
#	var dialog_rect := dialog.get_global_rect()
#	dialog_rect.position -= self_global_pos
#	draw_rect(dialog_rect, Color(1,1,0), false)
#
#	for child in dialog.get_children():
#		if child is Container:
#			var child_rect : Rect2 = child.get_global_rect()
#			child_rect.position -= self_global_pos
#			draw_rect(child_rect, Color(1,1,0,0.1))
