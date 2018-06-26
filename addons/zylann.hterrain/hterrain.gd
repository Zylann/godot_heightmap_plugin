tool
extends Spatial

const QuadTreeLod = preload("util/quad_tree_lod.gd")
const Mesher = preload("hterrain_mesher.gd")
const Grid = preload("util/grid.gd")
var HTerrainData = load("res://addons/zylann.hterrain/hterrain_data.gd")
const HTerrainChunk = preload("hterrain_chunk.gd")
const Util = preload("util/util.gd")
const HTerrainCollider = preload("hterrain_collider.gd")
const DetailRenderer = preload("detail/detail_renderer.gd")

const DefaultShader = preload("shaders/simple4.shader")

const CHUNK_SIZE = 16

const SHADER_PARAM_HEIGHT_TEXTURE = "u_terrain_heightmap"
const SHADER_PARAM_NORMAL_TEXTURE = "u_terrain_normalmap"
const SHADER_PARAM_COLOR_TEXTURE = "u_terrain_colormap"
const SHADER_PARAM_SPLAT_TEXTURE = "u_terrain_splatmap"
const SHADER_PARAM_INVERSE_TRANSFORM = "u_terrain_inverse_transform"
const SHADER_PARAM_NORMAL_BASIS = "u_terrain_normal_basis"
const SHADER_PARAM_GROUND_PREFIX = "u_ground_" # + name + _0, _1, _2, _3...
const SHADER_PARAM_DEPTH_BLENDING = "u_depth_blending"
const SHADER_PARAM_TRIPLANAR = "u_triplanar"
const SHADER_PARAM_GROUND_TEXTURE_SCALE = "u_ground_uv_scale"

const SHADER_SIMPLE4 = 0
#const SHADER_ARRAY = 1
#const SHADER_ATLAS = 2

# Note: the alpha channel is used to pack additional maps
const GROUND_ALBEDO_ROUGHNESS = 0
const GROUND_NORMAL_BUMP = 1
const GROUND_TEXTURE_TYPE_COUNT = 2

const _ground_enum_to_name = [
	"albedo_roughness",
	"normal_bump"
]

signal progress_notified(info)
# Same as progress_notified once finished, but more convenient to yield
signal progress_complete
signal transform_changed(global_transform)


export var depth_blending = false
export var cliff_triplanar = false
export var ground_texture_scale = 20.0
export var collision_enabled = false setget set_collision_enabled
export var async_loading = false
export(float, 0.0, 1.0) var ambient_wind = 0.0 setget set_ambient_wind

# Prefer using this instead of scaling the node's transform.
# Spatial.scale isn't used because it's not suitable for terrains,
# it would scale grass too and other environment objects.
export var map_scale = Vector3(1, 1, 1) setget set_map_scale

var _custom_material = null
var _material = ShaderMaterial.new()
var _data = null

var _mesher = Mesher.new()
var _lodder = QuadTreeLod.new()
var _details = DetailRenderer.new()

var _pending_chunk_updates = []

# [lod][pos]
# This container owns chunks
var _chunks = []

var _collider = null

# Stats
var _updated_chunks = 0

# Editor-only
var _edit_manual_viewer_pos = Vector3()


func _init():
	print("Create HeightMap")
	_lodder.set_callbacks(funcref(self, "_cb_make_chunk"), funcref(self,"_cb_recycle_chunk"))
	_details.set_terrain(self)
	set_notify_transform(true)


func _get_property_list():
	var props = [
		{
			# Must do this to export a custom resource type
			"name": "data",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "HTerrainData"
		}
	]
	
	for i in range(get_ground_texture_slot_count()):
		for t in _ground_enum_to_name:
			props.append({
				"name": "ground/" + t + "_" + str(i),
				"type": TYPE_OBJECT,
				"usage": PROPERTY_USAGE_STORAGE,
				"hint": PROPERTY_HINT_RESOURCE_TYPE,
				"hint_string": "Texture"
			})

	props.append({
		"name": "_detail_objects_data",
		"type": TYPE_ARRAY,
		"usage": PROPERTY_USAGE_STORAGE
	})
	
	return props


func _get(key):
	
	if key == "data":
		return get_data()
	
	if key.begins_with("ground/"):
		for ground_texture_type in range(GROUND_TEXTURE_TYPE_COUNT):
			var type_name = _ground_enum_to_name[ground_texture_type]
			if key.begins_with(str("ground/", type_name, "_")):
				var i = key.right(len(key) - 1).to_int()
				return get_ground_texture(i, ground_texture_type)

	if key == "_detail_objects_data":
		return _details.serialize()


func _set(key, value):
	# Can't use setget when the exported type is custom,
	# because we were also are forced to use _get_property_list...
	if key == "data":
		set_data(value)
	
	for ground_texture_type in range(GROUND_TEXTURE_TYPE_COUNT):
		var type_name = _ground_enum_to_name[ground_texture_type]
		if key.begins_with(str("ground/", type_name, "_")):
			var i = key.right(len(key) - 1).to_int()
			set_ground_texture(i, ground_texture_type, value)

	if key == "_detail_objects_data":
		return _details.deserialize(value)


func get_custom_material():
	return _custom_material


# TODO Remove this once 3.x contains heightmap shape fix, because it's broken in 3.0.2
# You need this PR: https://github.com/godotengine/godot/pull/17806
static func _check_heightmap_collider_support():
	var v = Engine.get_version_info()
	if v.major == 3 and v.minor == 0 and v.patch < 4:
		print("Heightmap collision shape not supported in this version of Godot, please upgrade to 3.0.4 or later")
		return false
	return true


func set_collision_enabled(enabled):
	if collision_enabled != enabled:
		collision_enabled = enabled
		if collision_enabled:
			if not Engine.editor_hint and _check_heightmap_collider_support():
				_collider = HTerrainCollider.new()
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


func set_map_scale(p_map_scale):
	if map_scale == p_map_scale:
		return
	map_scale = p_map_scale
	_on_transform_changed()


# Gets the global transform to apply to terrain geometry,
# which is different from Spatial.global_transform gives (that one must only have translation)
func get_internal_transform():
	# Terrain can only be scaled and translated,
	return Transform(Basis().scaled(map_scale), translation)


func _notification(what):
	match what:
		
		NOTIFICATION_PREDELETE:
			print("Destroy HTerrain")
			# Note: might get rid of a circular ref in GDScript port
			_clear_all_chunks()

		NOTIFICATION_ENTER_WORLD:
			print("Enter world")
			_for_all_chunks(EnterWorldAction.new(get_world()))
			if _collider != null:
				_collider.set_world(get_world())
				_collider.set_transform(get_internal_transform())
			_details.on_terrain_world_changed(get_world())
			
		NOTIFICATION_EXIT_WORLD:
			print("Exit world");
			_for_all_chunks(ExitWorldAction.new())
			if _collider != null:
				_collider.set_world(null)
			_details.on_terrain_world_changed(null)
			
		NOTIFICATION_TRANSFORM_CHANGED:
			_on_transform_changed()
			
		NOTIFICATION_VISIBILITY_CHANGED:
			print("Visibility changed");
			_for_all_chunks(VisibilityChangedAction.new(is_visible()))
			_details.on_terrain_visibility_changed(is_visible())
			# TODO Turn off processing if not visible?


func _on_transform_changed():
	print("Transform changed");
	var gt = get_internal_transform()

	_for_all_chunks(TransformChangedAction.new(gt))

	_update_material()

	if _collider != null:
		_collider.set_transform(gt)

	_details.on_terrain_transform_changed(gt)

	emit_signal("transform_changed", gt)


func _enter_tree():
	print("Enter tree")
		
	#   .                                                      .
	#          .n                   .                 .                  n.
	#    .   .dP                  dP                   9b                 9b.    .
	#   4    qXb         .       dX                     Xb       .        dXp     t
	#  dX.    9Xb      .dXb    __                         __    dXb.     dXP     .Xb
	#  9XXb._       _.dXXXXb dXXXXbo.                 .odXXXXb dXXXXb._       _.dXXP
	#   9XXXXXXXXXXXXXXXXXXXVXXXXXXXXOo.           .oOXXXXXXXXVXXXXXXXXXXXXXXXXXXXP
	#    `9XXXXXXXXXXXXXXXXXXXXX'~   ~`OOO8b   d8OOO'~   ~`XXXXXXXXXXXXXXXXXXXXXP'
	#      `9XXXXXXXXXXXP' `9XX'   DIE    `98v8P'  HUMAN   `XXP' `9XXXXXXXXXXXP'
	#          ~~~~~~~       9X.          .db|db.          .XP       ~~~~~~~
	#                          )b.  .dbo.dP'`v'`9b.odb.  .dX(
	#                        ,dXXXXXXXXXXXb     dXXXXXXXXXXXb.
	#                       dXXXXXXXXXXXP'   .   `9XXXXXXXXXXXb
	#                      dXXXXXXXXXXXXb   d|b   dXXXXXXXXXXXXb
	#                      9XXb'   `XXXXXb.dX|Xb.dXXXXX'   `dXXP
	#                       `'      9XXXXXX(   )XXXXXXP      `'
	#                                XXXX X.`v'.X XXXX
	#                                XP^X'`b   d'`X^XX
	#                                X. 9  `   '  P )X
	#                                `b  `       '  d'
	#                                 `             '
	# TODO This is temporary until I get saving and loading to work the proper way!
	# Terrain data should be able to load even before being assigned to its node.
	# This makes the terrain load automatically
	if _data != null and _data.get_resolution() == 0:
		# Note: async loading in editor is better UX
		if Engine.editor_hint or async_loading:
			_data.load_data_async()
		else:
			# The game will freeze until enough data is ready
			_data.load_data()
	
	set_process(true)


func _clear_all_chunks():

	# The lodder has to be cleared because otherwise it will reference dangling pointers
	_lodder.clear();

	#_for_all_chunks(DeleteChunkAction.new())

	for i in range(len(_chunks)):
		_chunks[i].clear()


func _get_chunk_at(pos_x, pos_y, lod):
	if lod < len(_chunks):
		return Grid.grid_get_or_default(_chunks[lod], pos_x, pos_y, null)
	return null


func get_data():
	return _data


func has_data():
	return _data != null


func set_data(new_data):
	assert(new_data == null or new_data is HTerrainData)

	print("Set new data ", new_data)

	if _data == new_data:
		return

	if has_data():
		print("Disconnecting old HeightMapData")
		_data.disconnect("resolution_changed", self, "_on_data_resolution_changed")
		_data.disconnect("region_changed", self, "_on_data_region_changed")
		_data.disconnect("progress_notified", self, "_on_data_progress_notified")
		_data.disconnect("map_changed", self, "_on_data_map_changed")
		_data.disconnect("map_added", self, "_on_data_map_added")
		_data.disconnect("map_removed", self, "_on_data_map_removed")

	_data = new_data

	# Note: the order of these two is important
	_clear_all_chunks()

	if has_data():
		print("Connecting new HeightMapData")

		# This is a small UX improvement so that the user sees a default terrain
		if is_inside_tree() and Engine.is_editor_hint():
			if _data.get_resolution() == 0:
				_data._edit_load_default()

		_data.connect("resolution_changed", self, "_on_data_resolution_changed")
		_data.connect("region_changed", self, "_on_data_region_changed")
		_data.connect("progress_notified", self, "_on_data_progress_notified")
		_data.connect("map_changed", self, "_on_data_map_changed")
		_data.connect("map_added", self, "_on_data_map_added")
		_data.connect("map_removed", self, "_on_data_map_removed")

		_on_data_resolution_changed()

		_update_material()

	print("Set data done")


func _on_data_progress_notified(info):
	emit_signal("progress_notified", info)
	
	if info.finished:
		if not Engine.editor_hint:
			# Update collider when data is loaded
			if _collider != null:
				_collider.create_from_terrain_data(_data)
		
		_details.reset()
		
		emit_signal("progress_complete")


func _on_data_resolution_changed():

	_clear_all_chunks();

	_pending_chunk_updates.clear();

	_lodder.create_from_sizes(CHUNK_SIZE, _data.get_resolution())

	_chunks.resize(_lodder.get_lod_count())

	var cres = _data.get_resolution() / CHUNK_SIZE
	var csize_x = cres
	var csize_y = cres
	
	for lod in range(_lodder.get_lod_count()):
		print("Create grid for lod ", lod, ", ", csize_x, "x", csize_y)
		var grid = Grid.create_grid(csize_x, csize_y)
		_chunks[lod] = grid
		csize_x /= 2
		csize_y /= 2

	_mesher.configure(CHUNK_SIZE, CHUNK_SIZE, _lodder.get_lod_count())
	_update_material()


func _on_data_region_changed(min_x, min_y, max_x, max_y, channel):
	#print_line(String("_on_data_region_changed {0}, {1}, {2}, {3}").format(varray(min_x, min_y, max_x, max_y)));

	# Testing only heights because it's the only channel that can impact geometry and LOD
	if channel == HTerrainData.CHANNEL_HEIGHT:
		set_area_dirty(min_x, min_y, max_x - min_x, max_y - min_y)


func _on_data_map_changed(type, index):
	if type == HTerrainData.CHANNEL_DETAIL:
		_details.reset()


func _on_data_map_added(type, index):
	if type == HTerrainData.CHANNEL_DETAIL:
		_details.reset()


func _on_data_map_removed(type, index):
	if type == HTerrainData.CHANNEL_DETAIL:
		_details.remove_layer(index)


func set_custom_material(p_material):
	assert(p_material == null or p_material is ShaderMaterial)
	
	if _custom_material != p_material:
		_custom_material = p_material

		if _custom_material != null:

			if is_inside_tree() and Engine.is_editor_hint():

				# When the new shader is empty, allows to fork from the default shader

				if _custom_material.get_shader() == null:
					_custom_material.set_shader(Shader.new())

				var shader = _custom_material.get_shader()
				if shader != null:
					if shader.get_code().empty():
						shader.set_code(DefaultShader.code)
					
					# TODO If code isn't empty,
					# verify existing parameters and issue a warning if important ones are missing

		_update_material()


func _update_material():

	var instance_changed = false;

	if _custom_material != null:

		if _custom_material != _material:
			# Duplicate material but not the shader.
			# This is to ensure that users don't end up with internal textures assigned in the editor,
			# which could end up being saved as regular textures (which is not intented).
			# Also the HeightMap may use multiple instances of the material in the future,
			# if chunks need different params or use multiple textures (streaming)
			_material = _custom_material.duplicate(false)
			instance_changed = true

	else:

		if _material == null:
			_material = ShaderMaterial.new()
			instance_changed = true
		
		_material.set_shader(DefaultShader)

	if instance_changed:
		_for_all_chunks(SetMaterialAction.new(_material))

	_update_material_params()


func _update_material_params():

	assert(_material != null)
	
	var material = _material

	if _custom_material != null:
		# Copy all parameters from the custom material into the internal one
		# TODO We could get rid of this every frame if ShaderMaterial had a signal when a parameter changes...

		var from_shader = _custom_material.get_shader();
		var to_shader = _material.get_shader();

		assert(from_shader != null)
		assert(to_shader != null)
		# If that one fails, it means there is a bug in HeightMap code
		assert(from_shader == to_shader)

		# TODO Getting params could be optimized, by connecting to the Shader.changed signal and caching them

		var params_array = VisualServer.shader_get_param_list(from_shader.get_rid())

		var custom_material = _custom_material

		for i in range(len(params_array)):
			var d = params_array[i]
			var name = d["name"]
			material.set_shader_param(name, custom_material.get_shader_param(name))

	var height_texture
	var normal_texture
	var color_texture
	var splat_texture
	var res = Vector2(-1,-1)

	# TODO Only get textures the shader supports

	if has_data():
		height_texture = _data.get_texture(HTerrainData.CHANNEL_HEIGHT)
		normal_texture = _data.get_texture(HTerrainData.CHANNEL_NORMAL)
		color_texture = _data.get_texture(HTerrainData.CHANNEL_COLOR)
		splat_texture = _data.get_texture(HTerrainData.CHANNEL_SPLAT)
		res.x = _data.get_resolution()
		res.y = res.x

	if is_inside_tree():
		var gt = get_internal_transform()
		var t = gt.affine_inverse()
		material.set_shader_param(SHADER_PARAM_INVERSE_TRANSFORM, t)

		# This is needed to properly transform normals if the terrain is scaled
		var normal_basis = gt.basis.inverse().transposed()
		material.set_shader_param(SHADER_PARAM_NORMAL_BASIS, normal_basis)

	material.set_shader_param(SHADER_PARAM_HEIGHT_TEXTURE, height_texture)
	material.set_shader_param(SHADER_PARAM_NORMAL_TEXTURE, normal_texture)
	material.set_shader_param(SHADER_PARAM_COLOR_TEXTURE, color_texture)
	material.set_shader_param(SHADER_PARAM_SPLAT_TEXTURE, splat_texture)
	material.set_shader_param(SHADER_PARAM_DEPTH_BLENDING, depth_blending)
	material.set_shader_param(SHADER_PARAM_TRIPLANAR, cliff_triplanar)
	material.set_shader_param(SHADER_PARAM_GROUND_TEXTURE_SCALE, ground_texture_scale)


func set_lod_scale(lod_scale):
	_lodder.set_split_scale(lod_scale)


func get_lod_scale():
	return _lodder.get_split_scale()


func get_lod_count():
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

func _process(delta):
	
	# Get viewer pos
	var viewer_pos = _edit_manual_viewer_pos
	var viewport = get_viewport()
	if viewport != null:
		var camera = viewport.get_camera()
		if camera != null:
			viewer_pos = camera.get_global_transform().origin
	
	if has_data():
		# TODO I would like to do this without needing a ref to the scene tree...
		_data.emit_signal("_internal_process")
		
		if _data.is_locked():
			# Can't use the data for now
			return
		
		if _data.get_resolution() != 0:
			var gt = get_internal_transform()
			var local_viewer_pos = gt.affine_inverse() * viewer_pos
			_lodder.update(local_viewer_pos)
		
		if _data.get_map_count(HTerrainData.CHANNEL_DETAIL) > 0:
			# Note: the detail system is not affected by map scale,
			# so we have to send viewer position in world space
			_details.process(delta, viewer_pos)
	
	_updated_chunks = 0
	
	# Add more chunk updates for neighboring (seams):
	# This adds updates to higher-LOD chunks around lower-LOD ones,
	# because they might not needed to update by themselves, but the fact a neighbor
	# chunk got joined or split requires them to create or revert seams
	var precount = _pending_chunk_updates.size()
	for i in range(precount):
		var u = _pending_chunk_updates[i]

		# In case the chunk got split
		for d in range(4):

			var ncpos_x = u.pos_x + s_dirs[d][0]
			var ncpos_y = u.pos_y + s_dirs[d][1]
			
			var nchunk = _get_chunk_at(ncpos_x, ncpos_y, u.lod)

			if nchunk != null and nchunk.is_active():
				# Note: this will append elements to the array we are iterating on,
				# but we iterate only on the previous count so it should be fine
				_add_chunk_update(nchunk, ncpos_x, ncpos_y, u.lod)

		# In case the chunk got joined
		if u.lod > 0:
			var cpos_upper_x = u.pos_x * 2
			var cpos_upper_y = u.pos_y * 2
			var nlod = u.lod - 1

			for rd in range(8):

				var ncpos_upper_x = cpos_upper_x + s_rdirs[rd][0]
				var ncpos_upper_y = cpos_upper_y + s_rdirs[rd][1]
				
				var nchunk = _get_chunk_at(ncpos_upper_x, ncpos_upper_y, nlod)

				if nchunk != null and nchunk.is_active():
					_add_chunk_update(nchunk, ncpos_upper_x, ncpos_upper_y, nlod)

	# Update chunks
	for i in range(len(_pending_chunk_updates)):
		
		var u = _pending_chunk_updates[i]
		var chunk = _get_chunk_at(u.pos_x, u.pos_y, u.lod)
		assert(chunk != null)
		_update_chunk(chunk, u.lod)

	_pending_chunk_updates.clear()

	if Engine.editor_hint:
		# TODO I would reaaaally like to get rid of this... it just looks inefficient,
		# and it won't play nice if more materials are used internally.
		# Initially needed so that custom materials can be tweaked in editor.
		_update_material_params()

	# DEBUG
#	if(_updated_chunks > 0):
#		print("Updated {0} chunks".format(_updated_chunks))


func _update_chunk(chunk, lod):
	assert(has_data())

	# Check for my own seams
	var seams = 0;
	var cpos_x = chunk.cell_origin_x / (CHUNK_SIZE << lod)
	var cpos_y = chunk.cell_origin_y / (CHUNK_SIZE << lod)
	var cpos_lower_x = cpos_x / 2
	var cpos_lower_y = cpos_y / 2

	# Check for lower-LOD chunks around me
	for d in range(4):
		var ncpos_lower_x = (cpos_x + s_dirs[d][0]) / 2
		var ncpos_lower_y = (cpos_y + s_dirs[d][1]) / 2
		if ncpos_lower_x != cpos_lower_x or ncpos_lower_y != cpos_lower_y:
			var nchunk = _get_chunk_at(ncpos_lower_x, ncpos_lower_y, lod + 1)
			if nchunk != null and nchunk.is_active():
				seams |= (1 << d)

	var mesh = _mesher.get_chunk(lod, seams)
	chunk.set_mesh(mesh)

	# Because chunks are rendered using vertex shader displacement,
	# the renderer cannot rely on the mesh's AABB.
	var s = CHUNK_SIZE << lod;
	var aabb = _data.get_region_aabb(chunk.cell_origin_x, chunk.cell_origin_y, s, s)
	aabb.position.x = 0
	aabb.position.z = 0
	chunk.set_aabb(aabb)

	_updated_chunks += 1

	chunk.set_visible(is_visible())
	chunk.set_pending_update(false)

#	if (get_tree()->is_editor_hint() == false) {
#		// TODO Generate collider? Or delegate this to another node
#	}


func _add_chunk_update(chunk, pos_x, pos_y, lod):

	if chunk.is_pending_update():
		#print_line("Chunk update is already pending!");
		return

	assert(lod < len(_chunks))
	assert(pos_x >= 0)
	assert(pos_y >= 0)
	assert(pos_y < len(_chunks[lod]))
	assert(pos_x < len(_chunks[lod][pos_y]))

	# No update pending for this chunk, create one
	var u = PendingChunkUpdate.new()
	u.pos_x = pos_x
	u.pos_y = pos_y
	u.lod = lod
	_pending_chunk_updates.push_back(u)

	chunk.set_pending_update(true)

	# TODO Neighboring chunks might need an update too because of normals and seams being updated


func set_area_dirty(origin_in_cells_x, origin_in_cells_y, size_in_cells_x, size_in_cells_y):

	var cpos0_x = origin_in_cells_x / CHUNK_SIZE
	var cpos0_y = origin_in_cells_y / CHUNK_SIZE
	var csize_x = (size_in_cells_x - 1) / CHUNK_SIZE + 1
	var csize_y = (size_in_cells_y - 1) / CHUNK_SIZE + 1

	# For each lod
	for lod in range(_lodder.get_lod_count()):

		# Get grid and chunk size
		var grid = _chunks[lod]
		var s = _lodder.get_lod_size(lod)

		# Convert rect into this lod's coordinates:
		# Pick min and max (included), divide them, then add 1 to max so it's excluded again
		var min_x = cpos0_x / s
		var min_y = cpos0_y / s
		var max_x = (cpos0_x + csize_x - 1) / s + 1
		var max_y = (cpos0_y + csize_y - 1) / s + 1

		# Find which chunks are within
		var cy = min_y
		while cy < max_y:
			var cx = min_x
			while cx < max_x:
				
				var chunk = Grid.grid_get_or_default(grid, cx, cy, null)

				if chunk != null and chunk.is_active():
					_add_chunk_update(chunk, cx, cy, lod)
				
				cx += 1
			cy += 1
		

# Called when a chunk is needed to be seen
func _cb_make_chunk(cpos_x, cpos_y, lod):

	# TODO What if cpos is invalid? _get_chunk_at will return NULL but that's still invalid
	var chunk = _get_chunk_at(cpos_x, cpos_y, lod)

	if chunk == null:
		# This is the first time this chunk is required at this lod, generate it

		var lod_factor = _lodder.get_lod_size(lod)
		var origin_in_cells_x = cpos_x * CHUNK_SIZE * lod_factor
		var origin_in_cells_y = cpos_y * CHUNK_SIZE * lod_factor
		
		chunk = HTerrainChunk.new(self, origin_in_cells_x, origin_in_cells_y, _material)
		chunk.parent_transform_changed(get_internal_transform())
		
		var grid = _chunks[lod]
		var row = grid[cpos_y]
		row[cpos_x] = chunk

	# Make sure it gets updated
	_add_chunk_update(chunk, cpos_x, cpos_y, lod);

	chunk.set_active(true)

	return chunk;


# Called when a chunk is no longer seen
func _cb_recycle_chunk(chunk, cx, cy, lod):
	chunk.set_visible(false);
	chunk.set_active(false);


func _local_pos_to_cell(local_pos):
	return [
		int(local_pos.x),
		int(local_pos.z)
	]


static func _get_height_or_default(im, pos_x, pos_y):
	if pos_x < 0 or pos_y < 0 or pos_x >= im.get_width() or pos_y >= im.get_height():
		return 0
	return im.get_pixel(pos_x, pos_y).r


# Performs a raycast to the terrain without using the collision engine.
# This is mostly useful in the editor, where the collider isn't running.
# It may be slow on very large distance, but should be enough for editing purpose.
# out_cell_pos is the returned hit position and must be specified as an array of 2 integers.
# Returns false if there is no hit.
func cell_raycast(origin_world, dir_world, out_cell_pos):
	assert(typeof(origin_world) == TYPE_VECTOR3)
	assert(typeof(dir_world) == TYPE_VECTOR3)
	assert(typeof(out_cell_pos) == TYPE_ARRAY)

	if not has_data():
		return false

	var heights = _data.get_image(HTerrainData.CHANNEL_HEIGHT)
	if heights == null:
		return false

	var to_local = get_internal_transform().affine_inverse()
	var origin = to_local.xform(origin_world)
	var dir = to_local.basis.xform(dir_world)

	heights.lock()

	var cpos = _local_pos_to_cell(origin)
	if origin.y < _get_height_or_default(heights, cpos[0], cpos[1]):
		# Below
		return false

	var unit = 1.0
	var d = 0.0
	var max_distance = 800.0
	var pos = origin

	# Slow, but enough for edition
	# TODO Could be optimized with a form of binary search
	while d < max_distance:
		pos += dir * unit
		cpos = _local_pos_to_cell(pos)
		if _get_height_or_default(heights, cpos[0], cpos[1]) > pos.y:
			cpos = _local_pos_to_cell(pos - dir * unit);
			out_cell_pos[0] = cpos[0]
			out_cell_pos[1] = cpos[1]
			return true
		
		d += unit

	return false
	

# TODO Rename these "splat textures"

static func get_ground_texture_shader_param(ground_texture_type, slot):
	assert(typeof(slot) == TYPE_INT and slot >= 0)
	_check_ground_texture_type(ground_texture_type)
	return SHADER_PARAM_GROUND_PREFIX + _ground_enum_to_name[ground_texture_type] + "_" + str(slot)


func get_ground_texture(slot, type):
	_check_slot(slot)
	var shader_param = get_ground_texture_shader_param(type, slot)
	return _material.get_shader_param(shader_param)


func set_ground_texture(slot, type, tex):
	_check_slot(slot)
	assert(tex == null or tex is Texture)
	var shader_param = get_ground_texture_shader_param(type, slot)
	_material.set_shader_param(shader_param, tex)


func set_detail_texture(slot, tex):
	_details.set_texture(slot, tex)


func get_detail_texture(slot):
	return _details.get_texture(slot)


func set_ambient_wind(amplitude):
	if ambient_wind == amplitude:
		return
	ambient_wind = amplitude
	_details.update_ambient_wind()


func _check_slot(slot):
	assert(typeof(slot) == TYPE_INT)
	assert(slot >= 0 and slot < get_ground_texture_slot_count())


static func _check_ground_texture_type(ground_texture_type):
	assert(typeof(ground_texture_type) == TYPE_INT)
	assert(ground_texture_type >= 0 and ground_texture_type < GROUND_TEXTURE_TYPE_COUNT)


static func get_ground_texture_slot_count_for_shader(mode):
	match mode:
		SHADER_SIMPLE4:
			return 4
#		SHADER_ARRAY:
#			return 256
	print("Invalid shader type specified ", mode)
	return 0


func get_ground_texture_slot_count():
	return get_ground_texture_slot_count_for_shader(SHADER_SIMPLE4)


func _edit_set_manual_viewer_pos(pos):
	_edit_manual_viewer_pos = pos


func _edit_debug_draw(ci):
	_lodder.debug_draw_tree(ci)


class PendingChunkUpdate:
	var pos_x = 0
	var pos_y = 0
	var lod = 0


class EnterWorldAction:
	var world = null
	func _init(w):
		world = w
	func exec(chunk):
		chunk.enter_world(world)


class ExitWorldAction:
	func exec(chunk):
		chunk.exit_world()


class TransformChangedAction:
	var transform = null
	func _init(t):
		transform = t
	func exec(chunk):
		chunk.parent_transform_changed(transform)


class VisibilityChangedAction:
	var visible = false
	func _init(v):
		visible = v
	func exec(chunk):
		chunk.set_visible(visible)


#class DeleteChunkAction:
#	func exec(chunk):
#		pass


class SetMaterialAction:
	var material = null
	func _init(m):
		material = m
	func exec(chunk):
		chunk.set_material(material)

