extends Spatial


func _physics_process(delta):
	var head = get_node("Camera")
	
	var forward = -head.transform.basis.z
	var right = head.transform.basis.x
	var up = Vector3(0, 1, 0)
	
	var dir = Vector3()
	
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A):
		dir -= right
	
	elif Input.is_key_pressed(KEY_D):
		dir += right
	
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W):
		dir += forward
	
	elif Input.is_key_pressed(KEY_S):
		dir -= forward
	
	if Input.is_key_pressed(KEY_SHIFT):
		dir -= up
	
	elif Input.is_key_pressed(KEY_SPACE):
		dir += up
	
	var dir_len = dir.length()
	if dir_len > 0.01:
		
		dir /= dir_len
		
		var speed = 30.0
		var motor = dir * (speed * delta)
		
		translate(motor)

