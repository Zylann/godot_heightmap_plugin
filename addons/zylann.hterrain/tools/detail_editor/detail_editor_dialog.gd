tool
extends WindowDialog

const DetailRenderer = preload("res://addons/zylann.hterrain/detail/detail_renderer.gd")

signal confirmed(params)

onready var _inspector = get_node("VBoxContainer/HBoxContainer/Properties/Inspector")
onready var _preview = get_node("VBoxContainer/HBoxContainer/Preview")

var _empty_texture = load("res://addons/zylann.hterrain/tools/icons/empty.png")
var _viewport = null
var _preview_mesh_instance = null
var _detail_shader = load(DetailRenderer.DETAIL_SHADER_PATH)
var _is_ready = false
var _dummy_heightmap = null
var _dummy_normalmap = null
var _dummy_detailmap = null
var _dummy_globalmap = null


func _ready():
	# TODO Take formats from HTerrainData, don't assume them (though it doesn't really matter here)
	_dummy_heightmap = _create_dummy_texture(Image.FORMAT_RH, Color(0, 0, 0, 0))
	_dummy_normalmap = _create_dummy_texture(Image.FORMAT_RGB8, Color(0.5, 0.5, 1.0, 0.0))
	_dummy_detailmap = _create_dummy_texture(Image.FORMAT_L8, Color(1, 1, 1, 1))
	_dummy_globalmap = _create_dummy_texture(Image.FORMAT_RGB8, Color(0.4, 0.8, 0.4))
	
	_inspector.set_prototype({
		"texture": { "type": TYPE_OBJECT, "object_type": Resource },
		"bottom_shade": { "type": TYPE_REAL, "range": { "min": 0.0, "max": 1.0 }, "default_value": 0.0 },
		"global_map_tint_bottom": { "type": TYPE_REAL, "range": { "min": 0.0, "max": 1.0 }, "default_value": 0.0 },
		"global_map_tint_top": { "type": TYPE_REAL, "range": { "min": 0.0, "max": 1.0 }, "default_value": 0.0 }
	})


func set_params(params):
	for k in params:
		_inspector.set_value(k, params[k])


static func _create_dummy_texture(format, color):
	var im = Image.new()
	im.create(4, 4, false, format)
	im.fill(color)
	var tex = ImageTexture.new()
	tex.create_from_image(im, 0)
	return tex


func _on_OkButton_pressed():
	hide()
	emit_signal("confirmed", _inspector.get_values())


func _on_Inspector_property_changed(key, value):
	if _viewport == null:
		return
	
	match key:
		# TODO Mapping params all over the place isn't ideal. Custom shaders may need arbitrary params.
		"texture":
			_preview_mesh_instance.material_override.set_shader_param("u_albedo_alpha", value)
		"bottom_shade":
			_preview_mesh_instance.material_override.set_shader_param("u_bottom_ao", value)
		"global_map_tint_bottom":
			_preview_mesh_instance.material_override.set_shader_param("u_globalmap_tint_bottom", value)
		"global_map_tint_top":
			_preview_mesh_instance.material_override.set_shader_param("u_globalmap_tint_top", value)


func _notification(what):
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			
			if visible:
				if _viewport != null:
					return
				
				# Creating a viewport on the fly because none of this should exist
				# while there is no preview to show
				
				var world = World.new()
				
				_viewport = Viewport.new()
				_viewport.size = Vector2(200, 200)
				_viewport.world = world
				_viewport.own_world = true
				
				print("Making mat for viewport: ", _inspector.get_value("texture"))
				var mat = ShaderMaterial.new()
				mat.shader = _detail_shader
				mat.set_shader_param("u_terrain_heightmap", _dummy_heightmap)
				mat.set_shader_param("u_terrain_detailmap", _dummy_detailmap)
				mat.set_shader_param("u_terrain_normalmap", _dummy_normalmap)
				mat.set_shader_param("u_terrain_globalmap", _dummy_globalmap)
				mat.set_shader_param("u_albedo_alpha", _inspector.get_value("texture"))
				mat.set_shader_param("u_globalmap_tint_bottom", _inspector.get_value("global_map_tint_bottom"))
				mat.set_shader_param("u_globalmap_tint_top", _inspector.get_value("global_map_tint_top"))
				mat.set_shader_param("u_bottom_ao", _inspector.get_value("bottom_shade"))
				mat.set_shader_param("u_view_distance", 100)
				
				var mi = MeshInstance.new()
				mi.mesh = DetailRenderer.create_quad()
				mi.material_override = mat
				_preview_mesh_instance = mi
				_viewport.add_child(mi)
				
				var light = DirectionalLight.new()
				light.rotation_degrees = Vector3(-60, -35, 0)
				_viewport.add_child(light)
				
				var camera = Camera.new()
				_viewport.add_child(camera)
				
				# Add viewport under the Control
				_preview.add_child(_viewport)

				# Doing this at the end because it doesn't work until inside the tree
				var aabb = mi.get_aabb()
				var target_pos = aabb.position + aabb.size / 2.0
				camera.look_at_from_position(Vector3(0, 1, -1), target_pos, Vector3(0, 1, 0))
			
			else:
				if _viewport == null:
					return
				_viewport.queue_free()
				_viewport = null
				_preview_mesh_instance = null

				