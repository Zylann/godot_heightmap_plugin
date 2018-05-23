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


func _ready():
	# TODO Take formats from HTerrainData, don't assume them (though it doesn't really matter here)
	_dummy_heightmap = _create_dummy_texture(Image.FORMAT_RH, Color(0, 0, 0, 0))
	_dummy_normalmap = _create_dummy_texture(Image.FORMAT_RGB8, Color(0.5, 0.5, 1.0, 0.0))
	_dummy_detailmap = _create_dummy_texture(Image.FORMAT_L8, Color(1, 1, 1, 1))
	
	_inspector.set_prototype({
		"texture": { "type": TYPE_OBJECT, "object_type": Resource }
	})


func set_params(texture):
	_inspector.set_value("texture", texture)


static func _create_dummy_texture(format, color):
	var im = Image.new()
	im.create(4, 4, false, format)
	im.fill(color)
	var tex = ImageTexture.new()
	tex.create_from_image(im, 0)
	return tex


func _on_OkButton_pressed():
	hide()
	emit_signal("confirmed", {
		"texture": _inspector.get_value("texture")
	})


func _on_Inspector_property_changed(key, value):
	if _viewport == null:
		return
	if key == "texture":
		_preview_mesh_instance.material_override.set_shader_param("u_albedo_alpha", value)


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
				mat.set_shader_param("u_albedo_alpha", _inspector.get_value("texture"))
				mat.set_shader_param("u_view_distance", 100)
				
				var mi = MeshInstance.new()
				mi.mesh = DetailRenderer.create_quad()
				mi.material_override = mat
				_preview_mesh_instance = mi
				_viewport.add_child(mi)
				
				var light = DirectionalLight.new()
				light.rotation = Vector3(-60, -35, 0)
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

				