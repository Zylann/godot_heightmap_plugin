
# Helper class containing information about how to pack ground textures.
# Also allows to generate those textures, rather than having to do it with an image editor.

tool
extends Resource

const SlotConfig = preload("./texture_import_slot_config.gd")

signal slot_count_changed

export(Array, Resource) var _textures := []
export(int, 1, 2048) var _tile_size: int = 512
export(int, 1, 16) var _atlas_size: int = 4 setget set_atlas_size
export(String, FILE, "*.png") var _target_albedo_bump_path: String
export(String, FILE, "*.png") var _target_normal_roughness_path: String


func _init():
	set_atlas_size(_atlas_size)


func set_atlas_size(p_atlas_size: int):
	if p_atlas_size < 1:
		p_atlas_size = 1
	elif p_atlas_size >= 16:
		p_atlas_size = 16
	_atlas_size = p_atlas_size
	
	var slot_count = _atlas_size * _atlas_size
#	var old_slot_count = len(_textures)
	_textures.resize(slot_count)
#	for i in range(old_slot_count, slot_count):
#		_textures[i] = SlotConfig.new()
	emit_signal("slot_count_changed")


static func _load_image(path: String) -> Image:
	var im := Image.new()
	var err := im.load(path)
	if err != OK:
		push_error("Could not load image {0}, error {1}".format([path, err]))
		return null
	return im


func get_slot_count() -> int:
	return len(_textures)


func get_texture_config(index: int) -> SlotConfig:
	return _textures[index]


func set_texture_config(index: int, slot: SlotConfig):
	_textures[index] = slot


func generate_textures() -> bool:
	var ab_path := _target_albedo_bump_path
	var nr_path := _target_normal_roughness_path
	
	var texture_configs := _textures
	
	var atlas_pixel_size: int = _atlas_size * _tile_size
	
	var ab_atlas := Image.new()
	ab_atlas.create(atlas_pixel_size, atlas_pixel_size, false, Image.FORMAT_RGBA8)

	var nr_atlas := Image.new()
	nr_atlas.create(atlas_pixel_size, atlas_pixel_size, false, Image.FORMAT_RGBA8)
	
	ab_atlas.lock()
	nr_atlas.lock()
	
	# Fill atlas with packed pixel data
	for texture_index in len(texture_configs):
		var texture_config: SlotConfig = texture_configs[int(texture_index)]
		
		# TODO Unify two loops
		if texture_config == null or texture_config.albedo_path == "":
			continue
		
		var albedo_image := _load_image(texture_config.albedo_path)
		var bump_image := _load_image(texture_config.bump_path)
		var normal_image := _load_image(texture_config.normal_path)
		var roughness_image := _load_image(texture_config.roughness_path)
		
		var images := [
			albedo_image, 
			bump_image, 
			normal_image, 
			roughness_image
		]
		
		for im in images:
			if im == null:
				return false
			im.resize(_tile_size, _tile_size, Image.INTERPOLATE_BILINEAR)
		
		# TODO Casting to int because type hints don't work on iteration variables...
		var tx := int(texture_index) % _atlas_size
		var ty := int(texture_index) / _atlas_size
		
		var min_x := tx * _tile_size
		var min_y := ty * _tile_size
		
		for im in images:
			im.lock()
		
		for src_y in albedo_image.get_height():
			for src_x in albedo_image.get_width():
				var a := albedo_image.get_pixel(src_x, src_y)
				var b := bump_image.get_pixel(src_x, src_y)
				var n := normal_image.get_pixel(src_x, src_y)
				var r := roughness_image.get_pixel(src_x, src_y)
				
				var ax = min_x + src_x
				var ay = min_y + src_y
				
				# Pack values
				ab_atlas.set_pixel(ax, ay, Color(a.r, a.g, a.b, b.r))
				nr_atlas.set_pixel(ax, ay, Color(n.r, n.g, n.b, r.r))

		for im in images:
			im.unlock()
	
	# Fill remaining slots with color helpers
	var max_texture_index = _atlas_size * _atlas_size
	for texture_index in range(len(texture_configs), max_texture_index):
		# TODO Casting to int because type hints don't work on iteration variables...
		var tx := int(texture_index) % _atlas_size
		var ty := int(texture_index) / _atlas_size
		
		var min_x := tx * _tile_size
		var min_y := ty * _tile_size
		
		var checker := (tx + ty) & 1
		var col := Color(1, 0, 1) if checker == 1 else Color(0, 0, 1)
		
		for ay in range(min_y, min_y + _tile_size):
			for ax in range(min_x, min_x + _tile_size):
				ab_atlas.set_pixel(ax, ay, col)
				nr_atlas.set_pixel(ax, ay, col)

	ab_atlas.unlock()
	nr_atlas.unlock()

	ab_atlas.save_png(ab_path)
	nr_atlas.save_png(nr_path)

	return true
