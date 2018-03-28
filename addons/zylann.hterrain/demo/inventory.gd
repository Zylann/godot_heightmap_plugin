extends Node


const RbCube = preload("rb_cube.tscn")


func _input(event):
	if event is InputEventKey:
		if event.pressed:
			if event.scancode == KEY_1:
				throw_cube()
	
	elif event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == BUTTON_LEFT:
				throw_cube()


func throw_cube():
	var head = get_parent().get_node("Camera")
	var trans = head.global_transform

	var forward = -trans.basis.z
	var up = trans.basis.y
	var right = trans.basis.x
	
	var box = RbCube.instance()
	box.translation = trans.origin + forward * 3.0
	var dir = forward + up * rand_range(-0.5, 0.5) + right * rand_range(-0.5, 0.5)
	dir = dir.normalized()
	box.set_linear_velocity(dir * 30.0)
	get_parent().get_parent().add_child(box)
