tool
extends WindowDialog


# TODO Cap this resolution to terrain size, in case it is smaller (bigger uses chunking)
const VIEWPORT_RESOLUTION = 513

const HTerrainData = preload("../../hterrain_data.gd")

signal progress_notified(info) # { "progress": real, "message": string, "finished": bool }

onready var _inspector = get_node("VBoxContainer/Editor/Settings/Inspector")
onready var _preview_topdown = get_node("VBoxContainer/Editor/Preview")

var _dummy_texture = load("res://addons/zylann.hterrain/tools/icons/empty.png")
var _noise_texture = load("res://addons/zylann.hterrain/tools/generator/noise.png")
var _generator_shader = load("res://addons/zylann.hterrain/tools/generator/terrain_generator.shader")

var _viewport = null
var _viewport_ci = null

var _terrain = null

var _applying = false


func _ready():
	_inspector.set_prototype({
		# The shader isn't good at the moment, so seeding is limited
		"seed": { "type": TYPE_INT, "randomizable": true, "range": { "min": -1000, "max": 1000 }, "slidable": false},
		"base_height": { "type": TYPE_REAL, "range": {"min": -500.0, "max": 500.0, "step": 0.1 }},
		"height_range": { "type": TYPE_REAL, "range": {"min": 0.0, "max": 1000.0, "step": 0.1 }, "default_value": 500.0 },
		"scale": { "type": TYPE_REAL, "range": {"min": 1.0, "max": 1000.0, "step": 1.0}, "default_value": 100.0 },
		"roughness": { "type": TYPE_REAL, "range": {"min": 0.0, "max": 1.0, "step": 0.01}, "default_value": 0.5 },
		"curve": { "type": TYPE_REAL, "range": {"min": 1.0, "max": 10.0, "step": 0.1}, "default_value": 1.0 },
		"octaves": { "type": TYPE_INT, "range": {"min": 1, "max": 10, "step": 1}, "default_value": 4 }
	})
	# TEST
	#if _is_in_edited_scene():
	#	return
	#call_deferred("popup_centered_minsize")


func set_terrain(terrain):
	_terrain = terrain


func _is_in_edited_scene():
	#                               .___.
	#           /)               ,-^     ^-. 
	#          //               /           \
	# .-------| |--------------/  __     __  \-------------------.__
	# |WMWMWMW| |>>>>>>>>>>>>> | />>\   />>\ |>>>>>>>>>>>>>>>>>>>>>>:>
	# `-------| |--------------| \__/   \__/ |-------------------'^^
	#          \\               \    /|\    /
	#           \)               \   \_/   /
	#                             |       |
	#                             |+H+H+H+|
	#                             \       /
	#                              ^-----^
	# TODO https://github.com/godotengine/godot/issues/17592
	# This may break some day, don't fly planes with this bullshit
	return is_inside_tree() and ((get_parent() is Control) == false)


func _notification(what):
	match what:
		
		NOTIFICATION_VISIBILITY_CHANGED:
			
			# We don't want any of this to run in an edited scene
			if _is_in_edited_scene():
				return
		
			if visible:
				assert(not _applying)
				
				if _viewport != null:
					# TODO https://github.com/godotengine/godot/issues/18160
					print("WHAAAAT? NOTIFICATION_VISIBILITY_CHANGED was called twice when made visible!!")
					return
				
				print("Creating generator viewport")
				
				# Create a viewport which renders a heightmap offscreen
				var size = Vector2(VIEWPORT_RESOLUTION, VIEWPORT_RESOLUTION)
				_viewport = Viewport.new()
				_viewport.size = size
				_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
				_viewport.render_target_v_flip = true
				
				var mat = ShaderMaterial.new()
				mat.shader = _generator_shader
				mat.set_shader_param("noise_texture", _noise_texture)
				
				# Canvas item within the viewport to do the actual rendering
				_viewport_ci = TextureRect.new()
				_viewport_ci.expand = true
				_viewport_ci.texture = _dummy_texture
				_viewport_ci.rect_size = size
				_viewport_ci.material = mat
				_viewport.add_child(_viewport_ci)
				
				add_child(_viewport)
				
				# Assign output texture to display it in the editor with some effects
				_preview_topdown.texture = _viewport.get_texture()
				
				_inspector.trigger_all_modified()
			
			else:
				if not _applying:
					_destroy_viewport()


func _destroy_viewport():
	print("Destroying generator viewport")
	# Destroy viewport, it's not needed when the window is not open
	_viewport.queue_free()
	_viewport = null
	_viewport_ci = null	


func _on_CancelButton_pressed():
	hide()


func _on_ApplyButton_pressed():
	_applying = true
	hide()
	_apply()


func _on_Inspector_property_changed(key, value):
	if key == "scale":
		if abs(value) < 0.01:
			value = 0.0
		else:
			value = 1.0 / value
	
	_viewport_ci.material.set_shader_param("u_" + key, value)
	
	if key == "height_range" or key == "base_height":
		_preview_topdown.material.set_shader_param("u_" + key, value)


func _apply():
	if _terrain == null:
		print("ERROR: cannot apply, terrain is null")
		return
	
	var data = _terrain.get_data()
	if data == null:
		print("ERROR: cannot apply, terrain data is null")
		return

	var dst = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	if dst == null:
		print("ERROR: heightmap image isn't loaded")
		return
	
	var cs = VIEWPORT_RESOLUTION
	var cw = dst.get_width() / (cs - 1)
	var ch = dst.get_height() / (cs - 1)
	
	var render_target = _viewport.get_texture()
	dst.lock()

	# The viewport renders an off-by-one region where upper bound pixels are shared with the next region.
	# So to avoid seams we need to slightly alter the offset for the render region
	var vp_offby1 = float(cs - 1) / float(cs)
	
	# Calculate by chunks so we don't completely freeze the editor
	for cy in range(ch):
		for cx in range(cw):
			print(513.0 * Vector2(cx, cy) * vp_offby1)
			_viewport_ci.material.set_shader_param("u_offset", Vector2(cx, cy) * vp_offby1)
			
			var progress = float(cy * cw + cx) / float(cw * ch)
			
			emit_signal("progress_notified", {
				"progress": progress,
				"message": "Calculating heightmap (" + str(cx) + ", " + str(cy) + ")"
			})
			
			yield(get_tree(), "idle_frame")
			
			var dst_x = cx * (cs - 1)
			var dst_y = cy * (cs - 1)
			
			print("Grabbing ", cx, ", ", cy)
			var im = render_target.get_data()
			im.convert(dst.get_format())
			dst.blit_rect(im, Rect2(0, 0, im.get_width(), im.get_height()), Vector2(dst_x, dst_y))
			
			# TODO Calculate normals on GPU too (in general, not just here), this is what makes the operation so slow
			data.update_normals(dst_x, dst_y, cs, cs)

	dst.unlock()
	
	_destroy_viewport()
	
	data.notify_region_change([0, 0], [dst.get_width(), dst.get_height()], HTerrainData.CHANNEL_HEIGHT)
	
	_applying = false

	emit_signal("progress_notified", { "finished": true })
	print("Done")
