tool
extends ViewportContainer

const PREVIEW_MESH_LOD = 2

const HTerrainMesher = preload("../hterrain_mesher.gd")
const HT_Util = preload("../util/util.gd")

signal dragged(relative, button_mask)

onready var _viewport = $Viewport
onready var _mesh_instance = $Viewport/MeshInstance
onready var _camera = $Viewport/Camera
onready var _light = $Viewport/DirectionalLight

# Use the simplest shader
var _shader = load("res://addons/zylann.hterrain/shaders/simple4_lite.shader")
var _yaw := 0.0
var _pitch := -PI / 6.0
var _distance := 0.0
var _default_distance := 0.0
var _sea_outline : MeshInstance = null
var _sea_plane : MeshInstance = null
var _mesh_resolution := 0


func _ready():
	if _sea_outline == null:
		var mesh = HT_Util.create_wirecube_mesh()
		var mat2 = SpatialMaterial.new()
		mat2.flags_unshaded = true
		mat2.albedo_color = Color(0, 0.5, 1)
		mesh.surface_set_material(0, mat2)
		_sea_outline = MeshInstance.new()
		_sea_outline.mesh = mesh
		_viewport.add_child(_sea_outline)
	
	if _sea_plane == null:
		var mesh = PlaneMesh.new()
		mesh.size = Vector2(1, 1)
		var mat2 = SpatialMaterial.new()
		mat2.flags_unshaded = true
		mat2.albedo_color = Color(0, 0.5, 1, 0.5)
		mat2.flags_transparent = true
		mesh.material = mat2
		_sea_plane = MeshInstance.new()
		_sea_plane.mesh = mesh
		_sea_plane.hide()
		_viewport.add_child(_sea_plane)


func setup(heights_texture: Texture, normals_texture: Texture):
	var terrain_size = heights_texture.get_width()
	var mesh_resolution = terrain_size / PREVIEW_MESH_LOD
	
	if _mesh_resolution != mesh_resolution or not (_mesh_instance.mesh is ArrayMesh):
		_mesh_resolution = mesh_resolution
		var mesh = HTerrainMesher.make_flat_chunk(
			_mesh_resolution, _mesh_resolution, PREVIEW_MESH_LOD, 0)
		_mesh_instance.mesh = mesh
		_default_distance = _mesh_instance.get_aabb().size.x
		_distance = _default_distance
		#_mesh_instance.translation -= 0.5 * Vector3(terrain_size, 0, terrain_size)
		_update_camera()

	var mat = _mesh_instance.mesh.surface_get_material(0)
	
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = _shader
		_mesh_instance.mesh.surface_set_material(0, mat)
			
	mat.set_shader_param("u_terrain_heightmap", heights_texture)
	mat.set_shader_param("u_terrain_normalmap", normals_texture)
	mat.set_shader_param("u_terrain_inverse_transform", Transform())
	mat.set_shader_param("u_terrain_normal_basis", Basis())

	var aabb = _mesh_instance.get_aabb()
	_sea_outline.scale = aabb.size

	aabb = _mesh_instance.get_aabb()
	_sea_plane.scale = Vector3(aabb.size.x, 1, aabb.size.z)
	_sea_plane.translation = Vector3(aabb.size.x, 0, aabb.size.z) / 2.0


func set_sea_visible(visible: bool):
	_sea_plane.visible = visible


func set_shadows_enabled(enabled: bool):
	_light.shadow_enabled = enabled


func _update_camera():
	var aabb = _mesh_instance.get_aabb()
	var target = aabb.position + 0.5 * aabb.size
	var trans = Transform()
	trans.basis = Basis(Quat(Vector3(0, 1, 0), _yaw) * Quat(Vector3(1, 0, 0), _pitch))
	var back = trans.basis.z
	trans.origin = target + back * _distance
	_camera.transform = trans


func cleanup():
	if _mesh_instance != null:
		var mat = _mesh_instance.mesh.surface_get_material(0)
		assert(mat != null)
		mat.set_shader_param("u_terrain_heightmap", null)
		mat.set_shader_param("u_terrain_normalmap", null)


func _gui_input(event: InputEvent):
	if HT_Util.is_in_edited_scene(self):
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
			
			var factor = 1.2
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
