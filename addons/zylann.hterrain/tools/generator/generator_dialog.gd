tool
extends WindowDialog


# TODO Cap this resolution to terrain size, in case it is smaller (bigger uses chunking)
const VIEWPORT_RESOLUTION = 512
const NOISE_PERM_TEXTURE_SIZE = 256

const HTerrainData = preload("../../hterrain_data.gd")
const HTerrainMesher = preload("../../hterrain_mesher.gd")
const Util = preload("../../util/util.gd")
const TextureGenerator = preload("texture_generator.gd")

signal progress_notified(info) # { "progress": real, "message": string, "finished": bool }
signal permanent_change_performed(message)

onready var _inspector = get_node("VBoxContainer/Editor/Settings/Inspector")
onready var _preview = get_node("VBoxContainer/Editor/Preview/TerrainPreview")
onready var _progress_bar = get_node("VBoxContainer/Editor/Preview/ProgressBar")

var _dummy_texture = load("res://addons/zylann.hterrain/tools/icons/empty.png")
var _noise_texture = null
var _terrain = null
var _applying = false
var _generator = null
var _generated_textures = [null, null]
var _dialog_visible = false


static func get_shader(shader_name):
	var path = "res://addons/zylann.hterrain/tools/generator/shaders".plus_file(str(shader_name, ".shader"))
	#print("Loading ", path)
	return load(path)


func _ready():
	_inspector.set_prototype({
		"seed": { "type": TYPE_INT, "randomizable": true, "range": { "min": -100000, "max": 100000 }, "slidable": false},
		"offset": { "type": TYPE_VECTOR2 },
		"base_height": { "type": TYPE_REAL, "range": {"min": -500.0, "max": 500.0, "step": 0.1 }},
		"height_range": { "type": TYPE_REAL, "range": {"min": 0.0, "max": 2000.0, "step": 0.1 }, "default_value": 150.0 },
		"scale": { "type": TYPE_REAL, "range": {"min": 1.0, "max": 1000.0, "step": 1.0}, "default_value": 50.0 },
		"roughness": { "type": TYPE_REAL, "range": {"min": 0.0, "max": 1.0, "step": 0.01}, "default_value": 0.4 },
		"curve": { "type": TYPE_REAL, "range": {"min": 1.0, "max": 10.0, "step": 0.1}, "default_value": 1.0 },
		"octaves": { "type": TYPE_INT, "range": {"min": 1, "max": 10, "step": 1}, "default_value": 6 },
		"erosion_steps": { "type": TYPE_INT, "range": {"min": 0, "max": 100, "step": 1}, "default_value": 0 },
		"erosion_weight": { "type": TYPE_REAL, "range": { "min": 0.0, "max": 1.0 }, "default_value": 0.5 },
		"erosion_slope_factor": { "type": TYPE_REAL, "range": { "min": 0.0, "max": 1.0 }, "default_value": 0.0 },
		"erosion_slope_direction": { "type": TYPE_VECTOR2, "default_value": Vector2(0, 0) },
		"erosion_slope_invert": { "type": TYPE_BOOL, "default_value": false },
		"dilation": { "type": TYPE_REAL, "range": { "min": 0.0, "max": 1.0 }, "default_value": 0.0 },
		"show_sea": { "type": TYPE_BOOL, "default_value": true },
		"shadows": { "type": TYPE_BOOL, "default_value": true }
	})

	_generator = TextureGenerator.new()
	_generator.set_resolution(Vector2(VIEWPORT_RESOLUTION, VIEWPORT_RESOLUTION))
	# Setup the extra pixels we want on max edges for terrain
	# TODO I wonder if it's not better to let the generator shaders work in pixels instead of NDC,
	# rather than putting a padding system there
	_generator.set_output_padding([0, 1, 0, 1])
	_generator.connect("output_generated", self, "_on_TextureGenerator_output_generated")
	_generator.connect("completed", self, "_on_TextureGenerator_completed")
	_generator.connect("progress_reported", self, "_on_TextureGenerator_progress_reported")
	add_child(_generator)


# TEST
func _input(event):
	if Engine.editor_hint:
		return
	if event is InputEventKey and event.pressed and not visible:
		call_deferred("popup_centered_minsize")


func set_terrain(terrain):
	_terrain = terrain


func _notification(what):
	match what:

		NOTIFICATION_VISIBILITY_CHANGED:

			# We don't want any of this to run in an edited scene
			if Util.is_in_edited_scene(self):
				return

			if visible:
				# TODO https://github.com/godotengine/godot/issues/18160
				if _dialog_visible:
					return
				_dialog_visible = true

				_preview.set_sea_visible(_inspector.get_value("show_sea"))
				_preview.set_shadows_enabled(_inspector.get_value("shadows"))

				if _noise_texture == null:
					_regen_noise_perm_texture(_inspector.get_value("seed"))

				_update_generator()

			else:
#				if not _applying:
#					_destroy_viewport()
				_preview.cleanup()
				for i in len(_generated_textures):
					_generated_textures[i] = null
				_dialog_visible = false


func _update_generator(preview=true):
	var scale = _inspector.get_value("scale")
	# Scale is inverted in the shader
	if abs(scale) < 0.01:
		scale = 0.0
	else:
		scale = 1.0 / scale

	# When previewing the resolution does not span the entire terrain,
	# so we apply a scale to some of the passes to make it cover it all.
	var preview_scale = 4.0 # As if 2049x2049

	# And when we get to generate it fully, sectors are used,
	# so the size or shape of the terrain doesn't matter
	var sectors = []

	# Get preview scale and sectors to generate.
	# Allowing null terrain to make it testable.
	if _terrain != null and _terrain.get_data() != null:
		var terrain_size = _terrain.get_data().get_resolution()

		if preview:
			preview_scale = float(terrain_size) / float(VIEWPORT_RESOLUTION)
			sectors.append(Vector2(0, 0))

		else:
			preview_scale = 1.0

			var cw = terrain_size / VIEWPORT_RESOLUTION
			var ch = terrain_size / VIEWPORT_RESOLUTION

			for y in ch:
				for x in cw:
					sectors.append(Vector2(x, y))

	var erosion_iterations = int(_inspector.get_value("erosion_steps"))
	erosion_iterations /= int(preview_scale)

	_generator.clear_passes()

	# Terrain textures need to have an off-by-one on their max edge,
	# which is shared with the other sectors.
	var base_offset_ndc = _inspector.get_value("offset")
	#var sector_size_offby1_ndc = float(VIEWPORT_RESOLUTION - 1) / padded_viewport_resolution

	for i in len(sectors):
		var sector = sectors[i]
		#var offset = sector * sector_size_offby1_ndc - Vector2(pad_offset_ndc, pad_offset_ndc)

#		var offset_px = sector * (VIEWPORT_RESOLUTION - 1) - Vector2(pad_offset_px, pad_offset_px)
#		var offset_ndc = offset_px / padded_viewport_resolution

		var progress = float(i) / len(sectors)

		var p = TextureGenerator.Pass.new()
		p.clear = true
		p.shader = get_shader("perlin_noise")
		# This pass generates the shapes of the terrain so will have to account for offset
		p.tile_pos = sector
		p.params = {
			"u_noise_texture": _noise_texture,
			"u_octaves": _inspector.get_value("octaves"),
			"u_seed": _inspector.get_value("seed"),
			"u_scale": scale * preview_scale,
			"u_offset": base_offset_ndc / preview_scale,
			"u_base_height": _inspector.get_value("base_height") / preview_scale,
			"u_height_range": _inspector.get_value("height_range") / preview_scale,
			"u_roughness": _inspector.get_value("roughness"),
			"u_curve": _inspector.get_value("curve")
		}
		_generator.add_pass(p)

		if erosion_iterations > 0:
			p = TextureGenerator.Pass.new()
			p.shader = get_shader("erode")
			# TODO More erosion config
			p.params = {
				"u_slope_factor": _inspector.get_value("erosion_slope_factor"),
				"u_slope_invert": _inspector.get_value("erosion_slope_invert"),
				"u_slope_up": _inspector.get_value("erosion_slope_direction"),
				"u_weight": _inspector.get_value("erosion_weight"),
				"u_dilation": _inspector.get_value("dilation")
			}
			p.iterations = erosion_iterations
			p.padding = p.iterations
			_generator.add_pass(p)

		_generator.add_output({
			"maptype": HTerrainData.CHANNEL_HEIGHT,
			"sector": sector,
			"progress": progress
		})

		p = TextureGenerator.Pass.new()
		p.shader = get_shader("bump2normal")
		p.padding = 1
		_generator.add_pass(p)

		_generator.add_output({
			"maptype": HTerrainData.CHANNEL_NORMAL,
			"sector": sector,
			"progress": progress
		})

	# TODO AO generation
	# TODO Splat generation
	_generator.run()


func _regen_noise_perm_texture(random_seed):
	_noise_texture = generate_perm_texture(_noise_texture, NOISE_PERM_TEXTURE_SIZE, \
		random_seed, Texture.FLAG_FILTER | Texture.FLAG_REPEAT)


func _on_CancelButton_pressed():
	hide()


func _on_ApplyButton_pressed():
	hide()
	_apply()


func _on_Inspector_property_changed(key, value):
	match key:
		"show_sea":
			_preview.set_sea_visible(value)
		"shadows":
			_preview.set_shadows_enabled(value)
		"seed":
			_regen_noise_perm_texture(value)
			_update_generator()
		_:
			_update_generator()


func _on_TerrainPreview_dragged(relative, button_mask):
	if button_mask & BUTTON_MASK_LEFT:
		var offset = _inspector.get_value("offset")
		offset += relative
		_inspector.set_value("offset", offset)


func _apply():
	if _terrain == null:
		printerr("ERROR: cannot apply, terrain is null")
		return

	var data = _terrain.get_data()
	if data == null:
		printerr("ERROR: cannot apply, terrain data is null")
		return

	var dst_heights = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	if dst_heights == null:
		printerr("ERROR: terrain heightmap image isn't loaded")
		return

	var dst_normals = data.get_image(HTerrainData.CHANNEL_NORMAL)
	if dst_normals == null:
		printerr("ERROR: terrain normal image isn't loaded")
		return

	_applying = true

	_update_generator(false)


func _on_TextureGenerator_progress_reported(info):
	if _applying:
		return
	var p = 0.0
	if info.pass_index == 1:
		p = float(info.iteration) / float(info.iteration_count)
	_progress_bar.show()
	_progress_bar.ratio = p


func _on_TextureGenerator_output_generated(image, info):
	if not _applying:
		# Update preview
		# TODO Improve TextureGenerator so we can get a ViewportTexture per output?
		var tex = _generated_textures[info.maptype]
		if tex == null:
			tex = ImageTexture.new()
		tex.create_from_image(image, Texture.FLAG_FILTER)
		_generated_textures[info.maptype] = tex

		var num_set = 0
		for v in _generated_textures:
			if v != null:
				num_set += 1
		if num_set == len(_generated_textures):
			_preview.setup( \
				_generated_textures[HTerrainData.CHANNEL_HEIGHT],
				_generated_textures[HTerrainData.CHANNEL_NORMAL])
	else:
		assert(_terrain != null)
		var data = _terrain.get_data()
		assert(data != null)
		var dst = data.get_image(info.maptype)
		assert(dst != null)

		image.convert(dst.get_format())

		dst.blit_rect(image, \
			Rect2(0, 0, image.get_width(), image.get_height()), \
			info.sector * VIEWPORT_RESOLUTION)

		emit_signal("progress_notified", {
			"progress": info.progress,
			"message": "Calculating sector (" + str(info.sector.x) + ", " + str(info.sector.y) + ")"
		})

#		if info.maptype == HTerrainData.CHANNEL_NORMAL:
#			image.save_png(str("normal_sector_", info.sector.x, "_", info.sector.y, ".png"))


func _on_TextureGenerator_completed():
	_progress_bar.hide()

	if not _applying:
		return
	_applying = false

	assert(_terrain != null)
	var data = _terrain.get_data()
	var resolution = data.get_resolution()
	data.notify_region_change(Rect2(0, 0, resolution, resolution), HTerrainData.CHANNEL_HEIGHT)

	emit_signal("progress_notified", { "finished": true })
	emit_signal("permanent_change_performed", "Generate terrain")
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
