@tool
extends Resource

const MODE_TEXTURES = 0
const MODE_TEXTURE_ARRAYS = 1
const MODE_COUNT = 2

const _mode_names = ["Textures", "TextureArrays"]

const SRC_TYPE_ALBEDO = 0
const SRC_TYPE_BUMP = 1
const SRC_TYPE_NORMAL = 2
const SRC_TYPE_ROUGHNESS = 3
const SRC_TYPE_COUNT = 4

const _src_texture_type_names = ["albedo", "bump", "normal", "roughness"]

# Ground texture types (used by the terrain system)
const TYPE_ALBEDO_BUMP = 0
const TYPE_NORMAL_ROUGHNESS = 1
const TYPE_COUNT = 2

const _texture_type_names = ["albedo_bump", "normal_roughness"]

const _type_to_src_types = [
	[SRC_TYPE_ALBEDO, SRC_TYPE_BUMP],
	[SRC_TYPE_NORMAL, SRC_TYPE_ROUGHNESS]
]

const _src_default_color_codes = [
	"#ff000000",
	"#ff888888",
	"#ff8888ff",
	"#ffffffff"
]

# TODO We may get rid of modes in the future, and only use TextureArrays.
# It exists for now for backward compatibility, but it makes the API a bit confusing
var _mode := MODE_TEXTURES
# [type][slot] -> StreamTexture or TextureArray
var _textures := [[], []]


static func get_texture_type_name(tt: int) -> String:
	return _texture_type_names[tt]


static func get_source_texture_type_name(tt: int) -> String:
	return _src_texture_type_names[tt]


static func get_source_texture_default_color_code(tt: int) -> String:
	return _src_default_color_codes[tt]


static func get_import_mode_name(mode: int) -> String:
	return _mode_names[mode]


static func get_src_types_from_type(t: int) -> Array:
	return _type_to_src_types[t]


static func get_max_slots_for_mode(mode: int) -> int:
	match mode:
		MODE_TEXTURES:
			# This is a legacy mode, where shaders can only have up to 4
			return 4
		MODE_TEXTURE_ARRAYS:
			# Will probably be lifted some day
			return 16
	return 0


func _get_property_list() -> Array:
	return [
		{
			"name": "mode",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_STORAGE
		},
		{
			"name": "textures",
			"type": TYPE_ARRAY,
			"usage": PROPERTY_USAGE_STORAGE
		}
	]


func _get(key: StringName):
	if key == &"mode":
		return _mode
	if key == &"textures":
		return _textures


func _set(key: StringName, value):
	if key == &"mode":
		# Not using set_mode() here because otherwise it could reset stuff set before...
		_mode = value
	if key == &"textures":
		_textures = value


func get_slots_count() -> int:
	if _mode == MODE_TEXTURES:
		return get_texture_count()

	elif _mode == MODE_TEXTURE_ARRAYS:
		# TODO What if there are two texture arrays of different size?
		var texarray : TextureLayered = _textures[TYPE_ALBEDO_BUMP][0]
		if texarray == null:
			texarray = _textures[TYPE_NORMAL_ROUGHNESS][0]
			if texarray == null:
				return 0
		return texarray.get_layers()

	else:
		assert(false)
		return 0


func get_texture_count() -> int:
	var texs = _textures[TYPE_ALBEDO_BUMP]
	return len(texs)


func get_texture(slot_index: int, ground_texture_type: int) -> Texture2D:
	if _mode == MODE_TEXTURE_ARRAYS:
		# Can't get a single texture at once
		return null

	elif _mode == MODE_TEXTURES:
		var texs = _textures[ground_texture_type]
		if slot_index >= len(texs):
			return null
		return texs[slot_index]

	else:
		assert(false)
		return null


func set_texture(slot_index: int, ground_texture_type: int, texture: Texture2D):
	assert(_mode == MODE_TEXTURES)
	var texs = _textures[ground_texture_type]
	if texs[slot_index] != texture:
		texs[slot_index] = texture
		emit_changed()


func get_texture_array(ground_texture_type: int) -> TextureLayered:
	if _mode != MODE_TEXTURE_ARRAYS:
		return null
	var texs = _textures[ground_texture_type]
	return texs[0]


func set_texture_array(ground_texture_type: int, texarray: TextureLayered):
	assert(_mode == MODE_TEXTURE_ARRAYS)
	var texs = _textures[ground_texture_type]
	if texs[0] != texarray:
		texs[0] = texarray
		emit_changed()


# TODO This function only exists because of a flaw in UndoRedo
# See https://github.com/godotengine/godot/issues/36895
func set_texture_null(slot_index: int, ground_texture_type: int):
	set_texture(slot_index, ground_texture_type, null)


# TODO This function only exists because of a flaw in UndoRedo
# See https://github.com/godotengine/godot/issues/36895
func set_texture_array_null(ground_texture_type: int):
	set_texture_array(ground_texture_type, null)


func get_mode() -> int:
	return _mode


func set_mode(mode: int):
	# This effectively clears slots
	_mode = mode
	clear()


func clear():
	match _mode:
		MODE_TEXTURES:
			for type in TYPE_COUNT:
				_textures[type] = []
		MODE_TEXTURE_ARRAYS:
			for type in TYPE_COUNT:
				_textures[type] = [null]
		_:
			assert(false)
	emit_changed()


func insert_slot(i: int) -> int:
	assert(_mode == MODE_TEXTURES)
	if i == -1:
		i = get_texture_count()
	for type in TYPE_COUNT:
		_textures[type].insert(i, null)
	emit_changed()
	return i


func remove_slot(i: int):
	assert(_mode == MODE_TEXTURES)
	if i == -1:
		i = get_slots_count() - 1
	for type in TYPE_COUNT:
		_textures[type].remove_at(i)
	emit_changed()


func has_any_textures() -> bool:
	for type in len(_textures):
		var texs = _textures[type]
		for i in len(texs):
			if texs[i] != null:
				return true
	return false


#func set_textures(textures: Array):
#	_textures = textures


# Cannot type hint because it would cause circular dependency
#func migrate_from_1_4(terrain):
#	var textures := []
#	for type in TYPE_COUNT:
#		textures.append([])
#	
#	if terrain.is_using_texture_array():
#		for type in TYPE_COUNT:
#			var tex : TextureArray = terrain.get_ground_texture_array(type)
#			textures[type] = [tex]
#		_mode = MODE_TEXTURE_ARRAYS
#		
#	else:
#		for index in terrain.get_max_ground_texture_slot_count():
#			for type in TYPE_COUNT:
#				var tex : Texture = terrain.get_ground_texture(type, index)
#				textures[type].append(tex)
#		_mode = MODE_TEXTURES
#	
#	_textures = textures
