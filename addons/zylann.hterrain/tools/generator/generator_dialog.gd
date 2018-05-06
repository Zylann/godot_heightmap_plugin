tool
extends WindowDialog


# TODO Cap this resolution to terrain size, in case it is smaller (bigger uses chunking)
const VIEWPORT_RESOLUTION = 513
const NOISE_PERM_TEXTURE_SIZE = 256

const HTerrainData = preload("../../hterrain_data.gd")

signal progress_notified(info) # { "progress": real, "message": string, "finished": bool }

onready var _inspector = get_node("VBoxContainer/Editor/Settings/Inspector")
onready var _preview_topdown = get_node("VBoxContainer/Editor/Preview")

var _dummy_texture = load("res://addons/zylann.hterrain/tools/icons/empty.png")
var _noise_texture = null
var _generator_shader = load("res://addons/zylann.hterrain/tools/generator/terrain_generator.shader")

# One viewport per terrain map
var _viewports = [null, null]
var _viewport_cis = [null, null]

var _terrain = null

var _applying = false


func _ready():
	_inspector.set_prototype({
		"seed": { "type": TYPE_INT, "randomizable": true, "range": { "min": -100000, "max": 100000 }, "slidable": false},
		"base_height": { "type": TYPE_REAL, "range": {"min": -500.0, "max": 500.0, "step": 0.1 }},
		"height_range": { "type": TYPE_REAL, "range": {"min": 0.0, "max": 1000.0, "step": 0.1 }, "default_value": 100.0 },
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
				
				if _viewports[0] != null:
					# TODO https://github.com/godotengine/godot/issues/18160
					print("WHAAAAT? NOTIFICATION_VISIBILITY_CHANGED was called twice when made visible!!")
					return
				
				if _noise_texture == null:
					print("Regenerating perm texture")
					var random_seed = _inspector.get_value("seed")
					_regen_noise_perm_texture(random_seed)
				
				print("Creating generator viewport")
				
				for map in [HTerrainData.CHANNEL_HEIGHT, HTerrainData.CHANNEL_NORMAL]:

					# Create a viewport which renders a map of the terrain offscreen
					var size = Vector2(VIEWPORT_RESOLUTION, VIEWPORT_RESOLUTION)
					var viewport = Viewport.new()
					viewport.size = size
					viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
					viewport.render_target_v_flip = true
					
					var mat = ShaderMaterial.new()
					mat.shader = _generator_shader
					mat.set_shader_param("noise_texture", _noise_texture)
					mat.set_shader_param("u_mode", map)
					
					# Canvas item within the viewport to do the actual rendering
					var viewport_ci = TextureRect.new()
					viewport_ci.expand = true
					viewport_ci.texture = _dummy_texture
					viewport_ci.rect_size = size
					viewport_ci.material = mat
					viewport.add_child(viewport_ci)
					
					add_child(viewport)

					_viewports[map] = viewport
					_viewport_cis[map] = viewport_ci
				
				var heights_texture = _viewports[HTerrainData.CHANNEL_HEIGHT].get_texture()
				var normals_texture = _viewports[HTerrainData.CHANNEL_NORMAL].get_texture()

				heights_texture.flags = Texture.FLAG_FILTER
				normals_texture.flags = Texture.FLAG_FILTER

				# Assign output texture to display it in the editor with some effects
				_preview_topdown.texture = heights_texture
				_preview_topdown.material.set_shader_param("u_normal_texture", normals_texture)
				
				_inspector.trigger_all_modified()
			
			else:
				if not _applying:
					_destroy_viewport()


func _regen_noise_perm_texture(random_seed):
	_noise_texture = generate_perm_texture(_noise_texture, NOISE_PERM_TEXTURE_SIZE, \
		random_seed, Texture.FLAG_FILTER | Texture.FLAG_REPEAT)


func _destroy_viewport():
	print("Destroying generator viewport")
	# Destroy viewport, it's not needed when the window is not open
	for i in range(len(_viewports)):
		_viewports[i].queue_free()
		_viewports[i] = null
		_viewport_cis[i] = null	


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
	
	
	if key == "seed":
		_regen_noise_perm_texture(value)
	else:
		# TODO Remove seed param from the shader?
		for i in range(len(_viewports)):
			_viewport_cis[i].material.set_shader_param("u_" + key, value)
	
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

	var dst_heights = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	if dst_heights == null:
		print("ERROR: terrain heightmap image isn't loaded")
		return

	var dst_normals = data.get_image(HTerrainData.CHANNEL_NORMAL)
	if dst_normals == null:
		print("ERROR: terrain normal image isn't loaded")
		return
	
	var cs = VIEWPORT_RESOLUTION
	var cw = dst_heights.get_width() / (cs - 1)
	var ch = dst_heights.get_height() / (cs - 1)
	
	var heights_render_target = _viewports[HTerrainData.CHANNEL_HEIGHT].get_texture()
	var normals_render_target = _viewports[HTerrainData.CHANNEL_NORMAL].get_texture()

	dst_heights.lock()
	dst_normals.lock()

	# The viewport renders an off-by-one region where upper bound pixels are shared with the next region.
	# So to avoid seams we need to slightly alter the offset for the render region
	var vp_offby1 = float(cs - 1) / float(cs)
	
	# Calculate by chunks so we don't completely freeze the editor
	for cy in range(ch):
		for cx in range(cw):
			print(513.0 * Vector2(cx, cy) * vp_offby1)

			for i in range(len(_viewports)):
				_viewport_cis[i].material.set_shader_param("u_offset", Vector2(cx, cy) * vp_offby1)
			
			var progress = float(cy * cw + cx) / float(cw * ch)
			
			emit_signal("progress_notified", {
				"progress": progress,
				"message": "Calculating heightmap (" + str(cx) + ", " + str(cy) + ")"
			})
			
			yield(get_tree(), "idle_frame")
			
			var dst_x = cx * (cs - 1)
			var dst_y = cy * (cs - 1)
			
			print("Grabbing ", cx, ", ", cy)
			# Note: it should be okay for normals to be calculated within the same rect,
			# because they come from the generator, not an image, so the available values aren't clamped.
			var heights_im = heights_render_target.get_data()
			var normals_im = normals_render_target.get_data()

			heights_im.convert(dst_heights.get_format())
			normals_im.convert(dst_normals.get_format())

			dst_heights.blit_rect(heights_im, Rect2(0, 0, heights_im.get_width(), heights_im.get_height()), Vector2(dst_x, dst_y))
			dst_normals.blit_rect(normals_im, Rect2(0, 0, normals_im.get_width(), normals_im.get_height()), Vector2(dst_x, dst_y))

	dst_heights.unlock()
	dst_normals.unlock()
	
	_destroy_viewport()
	
	data.notify_region_change([0, 0], [dst_heights.get_width(), dst_heights.get_height()], HTerrainData.CHANNEL_HEIGHT)
	
	_applying = false

	emit_signal("progress_notified", { "finished": true })
	print("Done")


static func generate_perm_texture(tex, res, random_seed, tex_flags):
	var im = Image.new()
	im.create(res, res, false, Image.FORMAT_RF)
	
	seed(random_seed)
	
	im.lock()
	for y in range(0, im.get_height()):
		for x in range(0, im.get_width()):
			var r = randf()
			im.set_pixel(x, y, Color(r, r, r, 1.0))
	im.unlock()
	
	if tex == null:
		tex = ImageTexture.new()
	tex.create_from_image(im, tex_flags)
	
	return tex

