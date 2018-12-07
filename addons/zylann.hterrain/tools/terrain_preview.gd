tool
extends ViewportContainer

const PREVIEW_MESH_LOD = 2

const HTerrainMesher = preload("../hterrain_mesher.gd")
const Util = preload("../util/util.gd")

signal dragged(relative, button_mask)

onready var _viewport = get_node("Viewport")
onready var _mesh_instance = get_node("Viewport/MeshInstance")
onready var _camera = get_node("Viewport/Camera")

# Use the simplest shader
var _shader = load("res://addons/zylann.hterrain/shaders/simple4_lite.shader")
var _yaw = 0.0
var _pitch = -PI / 6.0
var _distance = 0.0
var _default_distance = 0.0
var _sea_level_mesh = null


func setup(heights_texture, normals_texture):
	var mat = null
	if _mesh_instance.mesh == null or not (_mesh_instance.mesh is ArrayMesh):
		var terrain_size = heights_texture.get_width()
		var mesh_resolution = terrain_size / PREVIEW_MESH_LOD
		var mesh = HTerrainMesher.make_flat_chunk(mesh_resolution, mesh_resolution, PREVIEW_MESH_LOD, 0)
		mat = ShaderMaterial.new()
		mat.shader = _shader
		mesh.surface_set_material(0, mat)
		_mesh_instance.mesh = mesh
		_default_distance = _mesh_instance.get_aabb().size.x
		_distance = _default_distance
		#_mesh_instance.translation -= 0.5 * Vector3(terrain_size, 0, terrain_size)
		_update_camera()
	else:
		mat = _mesh_instance.mesh.surface_get_material(0)
	mat.set_shader_param("u_terrain_heightmap", heights_texture)
	mat.set_shader_param("u_terrain_normalmap", normals_texture)
	mat.set_shader_param("u_terrain_inverse_transform", Transform())
	mat.set_shader_param("u_terrain_normal_basis", Basis())
	
	if _sea_level_mesh == null:
		_sea_level_mesh = MeshInstance.new()
		var mesh = Util.create_wirecube_mesh()
		var mat2 = SpatialMaterial.new()
		mat2.flags_unshaded = true
		mat2.albedo_color = Color(0, 0.5, 1)
		mesh.surface_set_material(0, mat2)
		_sea_level_mesh.mesh = mesh
		var aabb = _mesh_instance.get_aabb()
		_sea_level_mesh.scale = aabb.size
		_viewport.add_child(_sea_level_mesh)


func _update_camera():
	var aabb = _mesh_instance.get_aabb()
	var target = aabb.position + 0.5 * aabb.size
	var trans = Transform()
	trans.basis = Basis(Quat(Vector3(0, 1, 0), _yaw) * Quat(Vector3(1, 0, 0), _pitch))
	var back = trans.basis.z
	trans.origin = target + back * _distance
	_camera.transform = trans


func cleanup():
	var mat = _mesh_instance.mesh.surface_get_material(0)
	assert(mat != null)
	mat.set_shader_param("u_terrain_heightmap", null)
	mat.set_shader_param("u_terrain_normalmap", null)


func _gui_input(event):
	if Util.is_in_edited_scene(self):
		return
	
	if event is InputEventMouseMotion:
		if event.button_mask & BUTTON_MASK_MIDDLE:
			var d = 0.01 * event.relative
			_yaw -= d.x
			_pitch -= d.y
			_update_camera()
		else:
			var rel = 0.01 * event.relative
			# Align dragging to view rotation
			rel = -rel.rotated(-_yaw)
			emit_signal("dragged", rel, event.button_mask)
	
	elif event is InputEventMouseButton:
		if event.pressed:
			
			var factor = 1.5
			var max_factor = 10.0
			var min_distance = _default_distance / max_factor
			var max_distance = _default_distance
			
			# Zoom in/out
			if event.button_index == BUTTON_WHEEL_DOWN:
				_distance = clamp(_distance * factor, min_distance, max_distance)
				_update_camera()

			elif event.button_index == BUTTON_WHEEL_UP:
				_distance = clamp(_distance / factor, min_distance, max_distance)
				_update_camera()
