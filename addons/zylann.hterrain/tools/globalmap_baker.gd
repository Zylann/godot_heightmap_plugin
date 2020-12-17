
# Bakes a global albedo map using the same shader the terrain uses,
# but renders top-down in orthographic mode.

tool
extends Node

const HTerrain = preload("../hterrain.gd")
const HTerrainData = preload("../hterrain_data.gd")
const HTerrainMesher = preload("../hterrain_mesher.gd")

# Must be power of two
const DEFAULT_VIEWPORT_SIZE = 512

signal progress_notified(info)
signal permanent_change_performed(message)

var _terrain : HTerrain = null
var _viewport : Viewport = null
var _viewport_size := DEFAULT_VIEWPORT_SIZE
var _plane : MeshInstance = null
var _camera : Camera = null
var _sectors := []
var _sector_index := 0


func _ready():
	set_process(false)


func bake(terrain: HTerrain):
	assert(terrain != null)
	var data := terrain.get_data()
	assert(data != null)
	_terrain = terrain

	var splatmap := data.get_texture(HTerrainData.CHANNEL_SPLAT)
	var colormap := data.get_texture(HTerrainData.CHANNEL_COLOR)

	var terrain_size := data.get_resolution()
	
	if _viewport == null:
		_setup_scene(terrain_size)
	
	var cw := terrain_size / _viewport_size
	var ch := terrain_size / _viewport_size
	for y in ch:
		for x in cw:
			_sectors.append(Vector2(x, y))
	
	var mat := _plane.material_override
	_terrain.setup_globalmap_material(mat)

	_sector_index = 0
	set_process(true)


func _setup_scene(terrain_size: int):
	assert(_viewport == null)
	
	_viewport_size = DEFAULT_VIEWPORT_SIZE
	while _viewport_size > terrain_size:
		_viewport_size /= 2

	_viewport = Viewport.new()
	_viewport.size = Vector2(_viewport_size + 1, _viewport_size + 1)
	_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_v_flip = true
	_viewport.world = World.new()
	_viewport.own_world = true
	_viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	
	var mat := ShaderMaterial.new()
	
	_plane = MeshInstance.new()
	# Make a very small mesh, vertex precision isn't required
	var plane_res := 4
	_plane.mesh = \
		HTerrainMesher.make_flat_chunk(plane_res, plane_res, _viewport_size / plane_res, 0)
	_plane.material_override = mat
	_viewport.add_child(_plane)
	
	_camera = Camera.new()
	_camera.projection = Camera.PROJECTION_ORTHOGONAL
	_camera.size = _viewport.size.x
	_camera.near = 0.1
	_camera.far = 10.0
	_camera.current = true
	_camera.rotation_degrees = Vector3(-90, 0, 0)
	_viewport.add_child(_camera)
	
	add_child(_viewport)


func _cleanup_scene():
	_viewport.queue_free()
	_viewport = null
	_plane = null
	_camera = null


func _process(delta):
	if not is_processing():
		return

	if _sector_index > 0:
		_grab_image(_sectors[_sector_index - 1])

	if _sector_index >= len(_sectors):
		set_process(false)
		_finish()
		emit_signal("progress_notified", { "finished": true })
	else:
		_setup_pass(_sectors[_sector_index])
		_report_progress()
		_sector_index += 1


func _report_progress():
	var sector = _sectors[_sector_index]
	emit_signal("progress_notified", {
		"progress": float(_sector_index) / len(_sectors),
		"message": "Calculating sector (" + str(sector.x) + ", " + str(sector.y) + ")"
	})


func _setup_pass(sector: Vector2):
	# Note: we implicitely take off-by-one pixels into account
	var origin = sector * _viewport_size
	var center = origin + 0.5 * _viewport.size
	# The heightmap is left empty, so will default to white, which is a height of 1.
	# The camera must be placed above the terrain to see it.
	_camera.translation = Vector3(center.x, 2.0, center.y)
	_plane.translation = Vector3(origin.x, 0.0, origin.y)


func _grab_image(sector: Vector2):
	var tex := _viewport.get_texture()
	var src := tex.get_data()
	
	assert(_terrain != null)
	var data := _terrain.get_data()
	assert(data != null)
	
	if data.get_map_count(HTerrainData.CHANNEL_GLOBAL_ALBEDO) == 0:
		data._edit_add_map(HTerrainData.CHANNEL_GLOBAL_ALBEDO)
	
	var dst := data.get_image(HTerrainData.CHANNEL_GLOBAL_ALBEDO)
	
	src.convert(dst.get_format())
	var origin = sector * _viewport_size
	dst.blit_rect(src, Rect2(0, 0, src.get_width(), src.get_height()), origin)


func _finish():
	assert(_terrain != null)
	var data := _terrain.get_data() as HTerrainData
	assert(data != null)
	var dst := data.get_image(HTerrainData.CHANNEL_GLOBAL_ALBEDO)
	
	data.notify_region_change(Rect2(0, 0, dst.get_width(), dst.get_height()), 
		HTerrainData.CHANNEL_GLOBAL_ALBEDO)
	emit_signal("permanent_change_performed", "Bake globalmap")
	
	_cleanup_scene()
	_terrain = null
