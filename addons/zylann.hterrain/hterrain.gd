tool
extends Spatial

const QuadTreeLod = preload("./util/quad_tree_lod.gd")
const Mesher = preload("./hterrain_mesher.gd")
const Grid = preload("./util/grid.gd")
const HTerrainData = preload("./hterrain_data.gd")
const HTerrainChunk = preload("./hterrain_chunk.gd")
const HTerrainChunkDebug = preload("./hterrain_chunk_debug.gd")
const Util = preload("./util/util.gd")
const HTerrainCollider = preload("./hterrain_collider.gd")
const Logger = preload("./util/logger.gd")

const CLASSIC4_SHADER_PATH = "res://addons/zylann.hterrain/shaders/simple4.shader"
const CLASSIC4_LITE_SHADER_PATH = "res://addons/zylann.hterrain/shaders/simple4_lite.shader"
const _NORMAL_BAKER_PATH = "res://addons/zylann.hterrain/tools/normalmap_baker.gd"

const SHADER_PARAM_HEIGHT_TEXTURE = "u_terrain_heightmap"
const SHADER_PARAM_NORMAL_TEXTURE = "u_terrain_normalmap"
const SHADER_PARAM_COLOR_TEXTURE = "u_terrain_colormap"
const SHADER_PARAM_SPLAT_TEXTURE = "u_terrain_splatmap"

const SHADER_PARAM_INVERSE_TRANSFORM = "u_terrain_inverse_transform"
const SHADER_PARAM_NORMAL_BASIS = "u_terrain_normal_basis"

const SHADER_PARAM_GROUND_PREFIX = "u_ground_" # + name + _0, _1, _2, _3...

# Those parameters are filtered out in the inspector,
# because they are not supposed to be set through it
const _api_shader_params = {
	"u_terrain_heightmap": true,
	"u_terrain_normalmap": true,
	"u_terrain_colormap": true,
	"u_terrain_splatmap": true,
	"u_terrain_globalmap": true,

	"u_terrain_inverse_transform": true,
	"u_terrain_normal_basis": true,

	"u_ground_albedo_bump_0": true,
	"u_ground_albedo_bump_1": true,
	"u_ground_albedo_bump_2": true,
	"u_ground_albedo_bump_3": true,

	"u_ground_normal_roughness_0": true,
	"u_ground_normal_roughness_1": true,
	"u_ground_normal_roughness_2": true,
	"u_ground_normal_roughness_3": true
}

const SHADER_SIMPLE4 = "Classic4"
const SHADER_SIMPLE4_LITE = "Classic4Lite"
const SHADER_CUSTOM = "Custom"

# Note: the alpha channel is used to pack additional maps
const GROUND_ALBEDO_BUMP = 0
const GROUND_NORMAL_ROUGHNESS = 1
const GROUND_TEXTURE_TYPE_COUNT = 2

const MIN_CHUNK_SIZE = 16
const MAX_CHUNK_SIZE = 64

const _ground_enum_to_name = [
	"albedo_bump",
	"normal_roughness"
]

const DEBUG_AABB = false

signal transform_changed(global_transform)

export var collision_enabled := true setget set_collision_enabled
export(float, 0.0, 1.0) var ambient_wind := 0.0 setget set_ambient_wind
export(int, 2, 5) var lod_scale := 2.0 setget set_lod_scale, get_lod_scale

# TODO Replace with `size` in world units?
# Prefer using this instead of scaling the node's transform.
# Spatial.scale isn't used because it's not suitable for terrains,
# it would scale grass too and other environment objects.
export var map_scale := Vector3(1, 1, 1) setget set_map_scale

var _custom_shader : Shader = null
var _shader_type := SHADER_SIMPLE4
var _material := ShaderMaterial.new()
var _material_params_need_update := false
# Array of 2-textures arrays
var _ground_textures := []

var _data: HTerrainData = null

var _mesher := Mesher.new()
var _lodder := QuadTreeLod.new()
var _viewer_pos_world := Vector3()

# [lod][z][x] -> chunk
# This container owns chunks
var _chunks := []
var _chunk_size: int = 32
var _pending_chunk_updates := []

var _detail_layers := []

var _collider: HTerrainCollider = null

# Stats & debug
var _updated_chunks := 0
var _logger = Logger.get_for(self)

# Editor-only
var _normals_baker = null


func _init():
	_logger.debug("Create HeightMap")

	_lodder.set_callbacks( \
		funcref(self, "_cb_make_chunk"), \
		funcref(self,"_cb_recycle_chunk"), \
		funcref(self, "_cb_get_vertical_bounds"))

	set_notify_transform(true)

	# TODO Temporary!
	# This is a workaround for https://github.com/godotengine/godot/issues/24488
	_material.set_shader_param("u_ground_uv_scale", 20)
	_material.set_shader_param("u_depth_blending", true)

	_material.shader = load(CLASSIC4_SHADER_PATH)

	_ground_textures.resize(get_ground_texture_slot_count())
	for slot in len(_ground_textures):
		var e = []
		e.resize(GROUND_TEXTURE_TYPE_COUNT)
		_ground_textures[slot] = e

	if collision_enabled:
		if _check_heightmap_collider_support():
			_collider = HTerrainCollider.new(self)


func _get_property_list():
	var props = [
		{
			# Terrain data is exposed only as a path in the editor,
			# because it can only be saved if it has a directory selected.
			# That property is not used in scene saving (data is instead).
			"name": "data_directory",
			"type": TYPE_STRING,
			"usage": PROPERTY_USAGE_EDITOR,
			"hint": PROPERTY_HINT_DIR
		},
		{
			# The actual data resource is only exposed for storage.
			# I had to name it so that Godot won't try to assign _data directly
			# instead of using the setter I made...
			"name": "_terrain_data",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_STORAGE,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "HTerrainData"
		},
		{
			"name": "chunk_size",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE,
			#"hint": PROPERTY_HINT_ENUM,
			"hint_string": "16, 32"
		},
		{
			"name": "shader_type",
			"type": TYPE_STRING,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": "Classic4,Classic4Lite,Custom"
		},
		{
			# Had to specify it like this because need to be in category...
			"name": "custom_shader",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Shader"
		}
	]

	if _material.shader != null:
		var shader_params = VisualServer.shader_get_param_list(_material.shader.get_rid())
		for p in shader_params:
			if _api_shader_params.has(p.name):
				continue
			var cp = {}
			for k in p:
				cp[k] = p[k]
			cp.name = str("shader_params/", p.name)
			props.append(cp)

	for i in range(get_ground_texture_slot_count()):
		for t in _ground_enum_to_name:
			props.append({
				"name": "ground/" + t + "_" + str(i),
				"type": TYPE_OBJECT,
				"usage": PROPERTY_USAGE_STORAGE,
				"hint": PROPERTY_HINT_RESOURCE_TYPE,
				"hint_string": "Texture"
			})

	return props


func _get(key: String):

	if key == "data_directory":
		return _get_data_directory()

	if key == "_terrain_data":
		if _data == null or _data.resource_path == "":
			# Consider null if the data is not set or has no path,
			# because in those cases we can't save the terrain properly
			return null
		else:
			return _data

	if key.begins_with("ground/"):
		for ground_texture_type in range(GROUND_TEXTURE_TYPE_COUNT):
			var type_name = _ground_enum_to_name[ground_texture_type]
			if key.begins_with(str("ground/", type_name, "_")):
				var i = key.right(len(key) - 1).to_int()
				return get_ground_texture(i, ground_texture_type)

	elif key == "shader_type":
		return get_shader_type()

	elif key == "custom_shader":
		return get_custom_shader()

	elif key.begins_with("shader_params/"):
		var param_name = key.right(len("shader_params/"))
		return get_shader_param(param_name)

	elif key == "chunk_size":
		return _chunk_size


func _set(key: String, value):

	if key == "data_directory":
		_set_data_directory(value)

	# Can't use setget when the exported type is custom,
	# because we were also are forced to use _get_property_list...
	elif key == "_terrain_data":
		set_data(value)

	if key.begins_with("ground/"):
		for ground_texture_type in range(GROUND_TEXTURE_TYPE_COUNT):
			var type_name = _ground_enum_to_name[ground_texture_type]
			if key.begins_with(str("ground/", type_name, "_")):
				var i = key.right(len(key) - 1).to_int()
				set_ground_texture(i, ground_texture_type, value)

	elif key == "shader_type":
		set_shader_type(value)

	elif key == "custom_shader":
		set_custom_shader(value)

	elif key.begins_with("shader_params/"):
		var param_name = key.right(len("shader_params/"))
		set_shader_param(param_name, value)

	elif key == "chunk_size":
		set_chunk_size(value)


func get_shader_param(param_name: String):
	return _material.get_shader_param(param_name)


func set_shader_param(param_name: String, v):
	_material.set_shader_param(param_name, v)


func _set_data_directory(dir: String):
	if dir != _get_data_directory():
		if dir == "":
			set_data(null)
		else:
			var fpath := dir.plus_file(HTerrainData.META_FILENAME)
			var f := File.new()
			if f.file_exists(fpath):
				# Load existing
				var d = load(fpath)
				set_data(d)
			else:
				# Create new
				var d := HTerrainData.new()
				d.resource_path = fpath
				set_data(d)
	else:
		_logger.warn("Setting twice the same terrain directory??")


func _get_data_directory() -> String:
	if _data != null:
		return _data.resource_path.get_base_dir()
	return ""


func _check_heightmap_collider_support() -> bool:
	var v = Engine.get_version_info()
	if v.major == 3 and v.minor == 0 and v.patch < 4:
		_logger.error("Heightmap collision shape not supported in this version of Godot,"
			+ " please upgrade to 3.0.4 or later")
		return false
	return true


func set_collision_enabled(enabled: bool):
	if collision_enabled != enabled:
		collision_enabled = enabled
		if collision_enabled:
			if _check_heightmap_collider_support():
				_collider = HTerrainCollider.new(self)
				# Collision is not updated with data here,
				# because loading is quite a mess at the moment...
				# 1) This function can be called while no data has been set yet
				# 2) I don't want to update the collider more times than necessary
				#    because it's expensive
				# 3) I would prefer not defer that to the moment the terrain is
				#    added to the tree, because it would screw up threaded loading
		else:
			# Despite this object being a Reference,
			# this should free it, as it should be the only reference
			_collider = null


func _for_all_chunks(action):
	for lod in range(len(_chunks)):
		var grid = _chunks[lod]
		for y in range(len(grid)):
			var row = grid[y]
			for x in range(len(row)):
				var chunk = row[x]
				if chunk != null:
					action.exec(chunk)


func get_chunk_size() -> int:
	return _chunk_size


func set_chunk_size(p_cs: int):
	assert(typeof(p_cs) == TYPE_INT)
	_logger.debug(str("Setting chunk size to ", p_cs))
	var cs = Util.next_power_of_two(p_cs)
	if cs < MIN_CHUNK_SIZE:
		cs = MIN_CHUNK_SIZE
	if cs > MAX_CHUNK_SIZE:
		cs = MAX_CHUNK_SIZE
	if p_cs != cs:
		_logger.debug(str("Chunk size snapped to ", cs))
	if cs == _chunk_size:
		return
	_chunk_size = cs
	_reset_ground_chunks()


func set_map_scale(p_map_scale: Vector3):
	if map_scale == p_map_scale:
		return
	var e = 0.01
	assert(p_map_scale.x > e)
	assert(p_map_scale.y > e)
	assert(p_map_scale.z > e)
	map_scale = p_map_scale
	_on_transform_changed()


# Gets the global transform to apply to terrain geometry,
# which is different from Spatial.global_transform gives
# (that one must only have translation)
func get_internal_transform() -> Transform:
	# Terrain can only be scaled and translated,
	return Transform(Basis().scaled(map_scale), translation)


func _notification(what: int):
	match what:
		NOTIFICATION_PREDELETE:
			_logger.debug("Destroy HTerrain")
			# Note: might get rid of a circular ref in GDScript port
			_clear_all_chunks()

		NOTIFICATION_ENTER_WORLD:
			_logger.debug("Enter world")
			_for_all_chunks(EnterWorldAction.new(get_world()))
			if _collider != null:
				_collider.set_world(get_world())
				_collider.set_transform(get_internal_transform())

		NOTIFICATION_EXIT_WORLD:
			_logger.debug("Exit world")
			_for_all_chunks(ExitWorldAction.new())
			if _collider != null:
				_collider.set_world(null)

		NOTIFICATION_TRANSFORM_CHANGED:
			_on_transform_changed()

		NOTIFICATION_VISIBILITY_CHANGED:
			_logger.debug("Visibility changed")
			_for_all_chunks(VisibilityChangedAction.new(is_visible_in_tree()))


func _on_transform_changed():
	_logger.debug("Transform changed")
	var gt = get_internal_transform()

	_for_all_chunks(TransformChangedAction.new(gt))

	_material_params_need_update = true

	if _collider != null:
		_collider.set_transform(gt)

	emit_signal("transform_changed", gt)


func _enter_tree():
	_logger.debug("Enter tree")

	if Engine.editor_hint and _normals_baker == null:
		_normals_baker = load(_NORMAL_BAKER_PATH).new()
		add_child(_normals_baker)
		_normals_baker.set_terrain_data(_data)

	set_process(true)


func _clear_all_chunks():

	# The lodder has to be cleared because otherwise it will reference dangling pointers
	_lodder.clear()

	#_for_all_chunks(DeleteChunkAction.new())

	for i in range(len(_chunks)):
		_chunks[i].clear()


func _get_chunk_at(pos_x: int, pos_y: int, lod: int) -> HTerrainChunk:
	if lod < len(_chunks):
		return Grid.grid_get_or_default(_chunks[lod], pos_x, pos_y, null)
	return null


func get_data() -> HTerrainData:
	return _data


func has_data() -> bool:
	return _data != null


func set_data(new_data: HTerrainData):
	assert(new_data == null or new_data is HTerrainData)

	_logger.debug(str("Set new data ", new_data))

	if _data == new_data:
		return

	if has_data():
		_logger.debug("Disconnecting old HeightMapData")
		_data.disconnect("resolution_changed", self, "_on_data_resolution_changed")
		_data.disconnect("region_changed", self, "_on_data_region_changed")
		_data.disconnect("map_changed", self, "_on_data_map_changed")
		_data.disconnect("map_added", self, "_on_data_map_added")
		_data.disconnect("map_removed", self, "_on_data_map_removed")

		if _normals_baker != null:
			_normals_baker.set_terrain_data(null)
			_normals_baker.queue_free()
			_normals_baker = null

	_data = new_data

	# Note: the order of these two is important
	_clear_all_chunks()

	if has_data():
		_logger.debug("Connecting new HeightMapData")

		# This is a small UX improvement so that the user sees a default terrain
		if is_inside_tree() and Engine.is_editor_hint():
			if _data.get_resolution() == 0:
				_data._edit_load_default()

		if _collider != null:
			_collider.create_from_terrain_data(_data)

		_data.connect("resolution_changed", self, "_on_data_resolution_changed")
		_data.connect("region_changed", self, "_on_data_region_changed")
		_data.connect("map_changed", self, "_on_data_map_changed")
		_data.connect("map_added", self, "_on_data_map_added")
		_data.connect("map_removed", self, "_on_data_map_removed")

		if _normals_baker != null:
			_normals_baker.set_terrain_data(_data)

		_on_data_resolution_changed()

	_material_params_need_update = true
	
	if has_method("update_configuration_warning"):
		call("update_configuration_warning")
	
	_logger.debug("Set data done")


# The collider might be used in editor for other tools (like snapping to floor),
# so the whole collider can be updated in one go.
# It may be slow for ingame use, so prefer calling it when appropriate.
func update_collider():
	assert(collision_enabled)
	assert(_collider != null)
	_collider.create_from_terrain_data(_data)


func _on_data_resolution_changed():
	_reset_ground_chunks()


func _reset_ground_chunks():
	if _data == null:
		return

	_clear_all_chunks()

	_pending_chunk_updates.clear()

	_lodder.create_from_sizes(_chunk_size, _data.get_resolution())

	_chunks.resize(_lodder.get_lod_count())

	var cres = _data.get_resolution() / _chunk_size
	var csize_x = cres
	var csize_y = cres

	for lod in range(_lodder.get_lod_count()):
		_logger.debug(str("Create grid for lod ", lod, ", ", csize_x, "x", csize_y))
		var grid = Grid.create_grid(csize_x, csize_y)
		_chunks[lod] = grid
		csize_x /= 2
		csize_y /= 2

	_mesher.configure(_chunk_size, _chunk_size, _lodder.get_lod_count())


func _on_data_region_changed(min_x, min_y, size_x, size_y, channel):
	# Testing only heights because it's the only channel that can impact geometry and LOD
	if channel == HTerrainData.CHANNEL_HEIGHT:
		set_area_dirty(min_x, min_y, size_x, size_y)

		if _normals_baker != null:
			_normals_baker.request_tiles_in_region(
				Vector2(min_x, min_y), Vector2(size_x, size_y))


func _on_data_map_changed(type: int, index: int):
	if type == HTerrainData.CHANNEL_DETAIL \
	or type == HTerrainData.CHANNEL_HEIGHT \
	or type == HTerrainData.CHANNEL_NORMAL \
	or type == HTerrainData.CHANNEL_GLOBAL_ALBEDO:

		for layer in _detail_layers:
			layer.update_material()

	if type != HTerrainData.CHANNEL_DETAIL:
		_material_params_need_update = true


func _on_data_map_added(type: int, index: int):
	if type == HTerrainData.CHANNEL_DETAIL:
		for layer in _detail_layers:
			layer.update_material()
	else:
		_material_params_need_update = true


func _on_data_map_removed(type: int, index: int):
	if type == HTerrainData.CHANNEL_DETAIL:
		for layer in _detail_layers:
			layer.update_material()
	else:
		_material_params_need_update = true


func get_shader_type() -> String:
	return _shader_type


func set_shader_type(type: String):
	if type == _shader_type:
		return
	_shader_type = type

	match _shader_type:
		SHADER_SIMPLE4:
			_material.shader = load(CLASSIC4_SHADER_PATH) as Shader
		SHADER_SIMPLE4_LITE:
			_material.shader = load(CLASSIC4_LITE_SHADER_PATH) as Shader
		SHADER_CUSTOM:
			_material.shader = _custom_shader
		_:
			_logger.error("Unknown shader type: '{0}'".format([_shader_type]))
			_material.shader = load(CLASSIC4_SHADER_PATH) as Shader

	_material_params_need_update = true
	
	if Engine.editor_hint:
		property_list_changed_notify()


func get_custom_shader() -> Shader:
	return _custom_shader


func set_custom_shader(shader: Shader):
	if _custom_shader == shader:
		return

	if _custom_shader != null:
		_custom_shader.disconnect("changed", self, "_on_custom_shader_changed")

	if Engine.is_editor_hint() and shader != null and is_inside_tree():
		# When the new shader is empty, allow to fork from the previous shader
		if shader.get_code().empty():
			_logger.debug("Populating custom shader with default code")
			var src = _material.shader
			if src == null:
				src = load(CLASSIC4_SHADER_PATH)
			shader.set_code(src.code)
			# TODO If code isn't empty,
			# verify existing parameters and issue a warning if important ones are missing

	_custom_shader = shader

	if _shader_type == SHADER_CUSTOM:
		_material.shader = _custom_shader

	if _custom_shader != null:
		_custom_shader.connect("changed", self, "_on_custom_shader_changed")
		if _shader_type == SHADER_CUSTOM:
			_material_params_need_update = true
	
	if Engine.editor_hint:
		property_list_changed_notify()


func _on_custom_shader_changed():
	_material_params_need_update = true


func _update_material_params():
	assert(_material != null)
	_logger.debug("Updating terrain material params")

	var height_texture
	var normal_texture
	var color_texture
	var splat_texture
	var global_texture
	var res = Vector2(-1, -1)

	# TODO Only get textures the shader supports

	if has_data():
		height_texture = _data.get_texture(HTerrainData.CHANNEL_HEIGHT)
		normal_texture = _data.get_texture(HTerrainData.CHANNEL_NORMAL)
		color_texture = _data.get_texture(HTerrainData.CHANNEL_COLOR)
		splat_texture = _data.get_texture(HTerrainData.CHANNEL_SPLAT)
		if _data.get_map_count(HTerrainData.CHANNEL_GLOBAL_ALBEDO) != 0:
			global_texture = _data.get_texture(HTerrainData.CHANNEL_GLOBAL_ALBEDO)
		res.x = _data.get_resolution()
		res.y = res.x

	# Set all parameters from the terrain sytem.

	if is_inside_tree():
		var gt = get_internal_transform()
		var t = gt.affine_inverse()
		_material.set_shader_param(SHADER_PARAM_INVERSE_TRANSFORM, t)

		# This is needed to properly transform normals if the terrain is scaled
		var normal_basis = gt.basis.inverse().transposed()
		_material.set_shader_param(SHADER_PARAM_NORMAL_BASIS, normal_basis)

	_material.set_shader_param(SHADER_PARAM_HEIGHT_TEXTURE, height_texture)
	_material.set_shader_param(SHADER_PARAM_NORMAL_TEXTURE, normal_texture)
	_material.set_shader_param(SHADER_PARAM_COLOR_TEXTURE, color_texture)
	_material.set_shader_param(SHADER_PARAM_SPLAT_TEXTURE, splat_texture)
	_material.set_shader_param("u_terrain_globalmap", global_texture)

	for slot in len(_ground_textures):
		var textures = _ground_textures[slot]
		for type in len(textures):
			var shader_param = get_ground_texture_shader_param(type, slot)
			_material.set_shader_param(shader_param, textures[type])


# Helper used for globalmap baking
func setup_globalmap_material(mat: ShaderMaterial):
	var color_texture: Texture
	var splat_texture: Texture

	if has_data():
		color_texture = _data.get_texture(HTerrainData.CHANNEL_COLOR)
		splat_texture = _data.get_texture(HTerrainData.CHANNEL_SPLAT)

	mat.set_shader_param("u_terrain_splatmap", splat_texture)
	mat.set_shader_param("u_terrain_colormap", color_texture)
	mat.set_shader_param("u_depth_blending", get_shader_param("u_depth_blending"))
	mat.set_shader_param("u_ground_uv_scale", get_shader_param("u_ground_uv_scale"))

	for slot in len(_ground_textures):
		var textures = _ground_textures[slot]
		for type in len(textures):
			var shader_param = get_ground_texture_shader_param(type, slot)
			var tex = textures[type]
			mat.set_shader_param(shader_param, tex)


func set_lod_scale(lod_scale: float):
	_lodder.set_split_scale(lod_scale)


func get_lod_scale() -> float:
	return _lodder.get_split_scale()


func get_lod_count() -> int:
	return _lodder.get_lod_count()


#        3
#      o---o
#    0 |   | 1
#      o---o
#        2
# Directions to go to neighbor chunks
const s_dirs = [
	[-1, 0], # SEAM_LEFT
	[1, 0], # SEAM_RIGHT
	[0, -1], # SEAM_BOTTOM
	[0, 1] # SEAM_TOP
]

#       7   6
#     o---o---o
#   0 |       | 5
#     o       o
#   1 |       | 4
#     o---o---o
#       2   3
#
# Directions to go to neighbor chunks of higher LOD
const s_rdirs = [
	[-1, 0],
	[-1, 1],
	[0, 2],
	[1, 2],
	[2, 1],
	[2, 0],
	[1, -1],
	[0, -1]
]


func _edit_update_viewer_position(camera: Camera):
	_update_viewer_position(camera)


func _update_viewer_position(camera: Camera):
	if camera == null:
		var viewport := get_viewport()
		if viewport != null:
			camera = viewport.get_camera()
	if camera == null:
		return
	if camera.projection == Camera.PROJECTION_ORTHOGONAL:
		# In this mode, due to the fact Godot does not allow negative near plane,
		# users have to pull the camera node very far away, but it confuses LOD
		# into very low detail, while the seen area remains the same.
		# So we need to base LOD on a different metric.
		var cam_pos := camera.global_transform.origin
		var cam_dir := -camera.global_transform.basis.z
		var max_distance := camera.far * 1.2
		var hit_cell_pos = cell_raycast(cam_pos, cam_dir, max_distance)
		if hit_cell_pos != null:
			var cell_to_world = get_internal_transform()
			_viewer_pos_world = cell_to_world * hit_cell_pos
	else:
		_viewer_pos_world = camera.global_transform.origin


func _process(delta: float):
	if not Engine.is_editor_hint():
		# In editor, the camera is only accessible from an editor plugin
		_update_viewer_position(null)
	var viewer_pos := _viewer_pos_world

	if has_data():
		if _data.is_locked():
			# Can't use the data for now
			return

		if _data.get_resolution() != 0:
			var gt = get_internal_transform()
			var local_viewer_pos = gt.affine_inverse() * viewer_pos
			#var time_before = OS.get_ticks_msec()
			_lodder.update(local_viewer_pos)
			#var time_elapsed = OS.get_ticks_msec() - time_before
			#if Engine.get_frames_drawn() % 60 == 0:
			#	_logger.debug(str("Lodder time: ", time_elapsed))

		if _data.get_map_count(HTerrainData.CHANNEL_DETAIL) > 0:
			# Note: the detail system is not affected by map scale,
			# so we have to send viewer position in world space
			for layer in _detail_layers:
				layer.process(delta, viewer_pos)

	_updated_chunks = 0

	# Add more chunk updates for neighboring (seams):
	# This adds updates to higher-LOD chunks around lower-LOD ones,
	# because they might not needed to update by themselves, but the fact a neighbor
	# chunk got joined or split requires them to create or revert seams
	var precount = _pending_chunk_updates.size()
	for i in range(precount):
		var u = _pending_chunk_updates[i]

		# In case the chunk got split
		for d in 4:
			var ncpos_x = u.pos_x + s_dirs[d][0]
			var ncpos_y = u.pos_y + s_dirs[d][1]

			var nchunk := _get_chunk_at(ncpos_x, ncpos_y, u.lod)
			if nchunk != null and nchunk.is_active():
				# Note: this will append elements to the array we are iterating on,
				# but we iterate only on the previous count so it should be fine
				_add_chunk_update(nchunk, ncpos_x, ncpos_y, u.lod)

		# In case the chunk got joined
		if u.lod > 0:
			var cpos_upper_x = u.pos_x * 2
			var cpos_upper_y = u.pos_y * 2
			var nlod = u.lod - 1

			for rd in 8:
				var ncpos_upper_x = cpos_upper_x + s_rdirs[rd][0]
				var ncpos_upper_y = cpos_upper_y + s_rdirs[rd][1]

				var nchunk = _get_chunk_at(ncpos_upper_x, ncpos_upper_y, nlod)
				if nchunk != null and nchunk.is_active():
					_add_chunk_update(nchunk, ncpos_upper_x, ncpos_upper_y, nlod)

	# Update chunks
	var lvisible = is_visible_in_tree()
	for i in range(len(_pending_chunk_updates)):
		var u = _pending_chunk_updates[i]
		var chunk = _get_chunk_at(u.pos_x, u.pos_y, u.lod)
		assert(chunk != null)
		_update_chunk(chunk, u.lod, lvisible)
		_updated_chunks += 1

	_pending_chunk_updates.clear()

	if _material_params_need_update:
		_update_material_params()
		_material_params_need_update = false

	# DEBUG
#	if(_updated_chunks > 0):
#		_logger.debug(str("Updated {0} chunks".format(_updated_chunks)))


func _update_chunk(chunk: HTerrainChunk, lod: int, p_visible: bool):
	assert(has_data())

	# Check for my own seams
	var seams := 0
	var cpos_x := chunk.cell_origin_x / (_chunk_size << lod)
	var cpos_y := chunk.cell_origin_y / (_chunk_size << lod)
	var cpos_lower_x := cpos_x / 2
	var cpos_lower_y := cpos_y / 2

	# Check for lower-LOD chunks around me
	for d in 4:
		var ncpos_lower_x = (cpos_x + s_dirs[d][0]) / 2
		var ncpos_lower_y = (cpos_y + s_dirs[d][1]) / 2
		if ncpos_lower_x != cpos_lower_x or ncpos_lower_y != cpos_lower_y:
			var nchunk := _get_chunk_at(ncpos_lower_x, ncpos_lower_y, lod + 1)
			if nchunk != null and nchunk.is_active():
				seams |= (1 << d)

	var mesh := _mesher.get_chunk(lod, seams)
	chunk.set_mesh(mesh)

	# Because chunks are rendered using vertex shader displacement,
	# the renderer cannot rely on the mesh's AABB.
	var s := _chunk_size << lod
	var aabb := _data.get_region_aabb(chunk.cell_origin_x, chunk.cell_origin_y, s, s)
	aabb.position.x = 0
	aabb.position.z = 0
	chunk.set_aabb(aabb)

	chunk.set_visible(p_visible)
	chunk.set_pending_update(false)


func _add_chunk_update(chunk: HTerrainChunk, pos_x: int, pos_y: int, lod: int):
	if chunk.is_pending_update():
		#_logger.debug("Chunk update is already pending!")
		return

	assert(lod < len(_chunks))
	assert(pos_x >= 0)
	assert(pos_y >= 0)
	assert(pos_y < len(_chunks[lod]))
	assert(pos_x < len(_chunks[lod][pos_y]))

	# No update pending for this chunk, create one
	var u := PendingChunkUpdate.new()
	u.pos_x = pos_x
	u.pos_y = pos_y
	u.lod = lod
	_pending_chunk_updates.push_back(u)

	chunk.set_pending_update(true)

	# TODO Neighboring chunks might need an update too
	# because of normals and seams being updated


# Used when editing an existing terrain
func set_area_dirty(origin_in_cells_x: int, origin_in_cells_y: int, \
					size_in_cells_x: int, size_in_cells_y: int):

	var cpos0_x := origin_in_cells_x / _chunk_size
	var cpos0_y := origin_in_cells_y / _chunk_size
	var csize_x := (size_in_cells_x - 1) / _chunk_size + 1
	var csize_y := (size_in_cells_y - 1) / _chunk_size + 1

	# For each lod
	for lod in range(_lodder.get_lod_count()):
		# Get grid and chunk size
		var grid = _chunks[lod]
		var s := _lodder.get_lod_size(lod)

		# Convert rect into this lod's coordinates:
		# Pick min and max (included), divide them, then add 1 to max so it's excluded again
		var min_x := cpos0_x / s
		var min_y := cpos0_y / s
		var max_x := (cpos0_x + csize_x - 1) / s + 1
		var max_y := (cpos0_y + csize_y - 1) / s + 1

		# Find which chunks are within
		for cy in range(min_y, max_y):
			for cx in range(min_x, max_x):
				var chunk = Grid.grid_get_or_default(grid, cx, cy, null)
				if chunk != null and chunk.is_active():
					_add_chunk_update(chunk, cx, cy, lod)


# Called when a chunk is needed to be seen
func _cb_make_chunk(cpos_x: int, cpos_y: int, lod: int):
	# TODO What if cpos is invalid? _get_chunk_at will return NULL but that's still invalid
	var chunk := _get_chunk_at(cpos_x, cpos_y, lod)

	if chunk == null:
		# This is the first time this chunk is required at this lod, generate it
		
		var lod_factor := _lodder.get_lod_size(lod)
		var origin_in_cells_x := cpos_x * _chunk_size * lod_factor
		var origin_in_cells_y := cpos_y * _chunk_size * lod_factor

		if DEBUG_AABB:
			chunk = HTerrainChunkDebug.new(
				self, origin_in_cells_x, origin_in_cells_y, _material)
		else:
			chunk = HTerrainChunk.new(self, origin_in_cells_x, origin_in_cells_y, _material)
		chunk.parent_transform_changed(get_internal_transform())

		var grid = _chunks[lod]
		var row = grid[cpos_y]
		row[cpos_x] = chunk

	# Make sure it gets updated
	_add_chunk_update(chunk, cpos_x, cpos_y, lod)

	chunk.set_active(true)
	return chunk


# Called when a chunk is no longer seen
func _cb_recycle_chunk(chunk: HTerrainChunk, cx: int, cy: int, lod: int):
	chunk.set_visible(false)
	chunk.set_active(false)


func _cb_get_vertical_bounds(cpos_x: int, cpos_y: int, lod: int):
	var chunk_size := _chunk_size * _lodder.get_lod_size(lod)
	var origin_in_cells_x := cpos_x * chunk_size
	var origin_in_cells_y := cpos_y * chunk_size
	# This is a hack for speed,
	# because the proper algorithm appears to be too slow for GDScript.
	# It should be good enough for most common cases, unless you have super-sharp cliffs.
	return _data.get_point_aabb(
		origin_in_cells_x + chunk_size / 2, 
		origin_in_cells_y + chunk_size / 2)
#	var aabb = _data.get_region_aabb(
#		origin_in_cells_x, origin_in_cells_y, chunk_size, chunk_size)
#	return Vector2(aabb.position.y, aabb.end.y)


static func _get_height_or_default(im: Image, pos_x: int, pos_y: int):
	if pos_x < 0 or pos_y < 0 or pos_x >= im.get_width() or pos_y >= im.get_height():
		return 0.0
	return im.get_pixel(pos_x, pos_y).r


# Performs a raycast to the terrain without using the collision engine.
# This is mostly useful in the editor, where the collider can't be updated in realtime.
# Returns cell hit position as Vector2, or null if there was no hit.
func cell_raycast(origin_world: Vector3, dir_world: Vector3, max_distance: float):
	assert(typeof(origin_world) == TYPE_VECTOR3)
	assert(typeof(dir_world) == TYPE_VECTOR3)
	if not has_data():
		return false
	# Transform to local (takes map scale into account)
	var to_local := get_internal_transform().affine_inverse()
	var origin = to_local.xform(origin_world)
	var dir = to_local.basis.xform(dir_world)
	return _data.cell_raycast(origin, dir, max_distance)


# TODO Rename these "splat textures"

static func get_ground_texture_shader_param(ground_texture_type: int, slot: int) -> String:
	assert(typeof(slot) == TYPE_INT and slot >= 0)
	_check_ground_texture_type(ground_texture_type)
	return str(SHADER_PARAM_GROUND_PREFIX, 
		_ground_enum_to_name[ground_texture_type], "_", slot)


func get_ground_texture(slot: int, type: int) -> Texture:
	_check_slot(slot)
	var shader_param = get_ground_texture_shader_param(type, slot)
	return _material.get_shader_param(shader_param)


func set_ground_texture(slot: int, type: int, tex: Texture):
	_check_slot(slot)
	assert(tex == null or tex is Texture)
	var shader_param = get_ground_texture_shader_param(type, slot)
	_material.set_shader_param(shader_param, tex)
	_ground_textures[slot][type] = tex


func _internal_add_detail_layer(layer):
	assert(_detail_layers.find(layer) == -1)
	_detail_layers.append(layer)


func _internal_remove_detail_layer(layer):
	assert(_detail_layers.find(layer) != -1)
	_detail_layers.erase(layer)


# Returns a list copy of all child HTerrainDetailLayer nodes.
# The order in that list has no relevance.
func get_detail_layers() -> Array:
	return _detail_layers.duplicate()


# @obsolete
func set_detail_texture(slot, tex):
	_logger.error("HTerrain.set_detail_texture is obsolete, use HTerrainDetailLayer.texture instead")


# @obsolete
func get_detail_texture(slot):
	_logger.error("HTerrain.get_detail_texture is obsolete, use HTerrainDetailLayer.texture instead")


func set_ambient_wind(amplitude: float):
	if ambient_wind == amplitude:
		return
	ambient_wind = amplitude
	for layer in _detail_layers:
		layer.update_material()


func _check_slot(slot: int):
	assert(typeof(slot) == TYPE_INT)
	assert(slot >= 0 and slot < get_ground_texture_slot_count())


static func _check_ground_texture_type(ground_texture_type: int):
	assert(typeof(ground_texture_type) == TYPE_INT)
	assert(ground_texture_type >= 0 and ground_texture_type < GROUND_TEXTURE_TYPE_COUNT)


static func get_ground_texture_slot_count_for_shader(shader_type: String, logger):
	# TODO Deduce these from the shader used
	match shader_type:
		SHADER_SIMPLE4, \
		SHADER_SIMPLE4_LITE:
			return 4
		SHADER_CUSTOM:
			return 4
#		SHADER_ARRAY:
#			return 256
	logger.error("Invalid shader type specified ", shader_type)
	return 0


func get_ground_texture_slot_count() -> int:
	return get_ground_texture_slot_count_for_shader(_shader_type, _logger)


func _edit_debug_draw(ci):
	_lodder.debug_draw_tree(ci)


func _get_configuration_warning():
	if _data == null:
		return "The terrain is missing data.\n" \
			+ "Select the `Data Directory` property in the inspector to assign it."
	return ""


class PendingChunkUpdate:
	var pos_x := 0
	var pos_y := 0
	var lod := 0


class EnterWorldAction:
	var world : World = null
	func _init(w):
		world = w
	func exec(chunk):
		chunk.enter_world(world)


class ExitWorldAction:
	func exec(chunk):
		chunk.exit_world()


class TransformChangedAction:
	var transform : Transform
	func _init(t):
		transform = t
	func exec(chunk):
		chunk.parent_transform_changed(transform)


class VisibilityChangedAction:
	var visible := false
	func _init(v):
		visible = v
	func exec(chunk):
		chunk.set_visible(visible and chunk.is_active())


#class DeleteChunkAction:
#	func exec(chunk):
#		pass


class SetMaterialAction:
	var material : Material = null
	func _init(m):
		material = m
	func exec(chunk):
		chunk.set_material(material)


