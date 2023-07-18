@tool
extends Control

const HT_Util = preload("../../util/util.gd")
const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const HT_MinimapOverlay = preload("./minimap_overlay.gd")

const HT_MinimapShader = preload("./minimap_normal.gdshader")
# TODO Can't preload because it causes the plugin to fail loading if assets aren't imported
#const HT_WhiteTexture = preload("../icons/white.png")
const WHITE_TEXTURE_PATH = "res://addons/zylann.hterrain/tools/icons/white.png"

const MODE_QUADTREE = 0
const MODE_NORMAL = 1

@onready var _popup_menu : PopupMenu = $PopupMenu
@onready var _color_rect : ColorRect = $ColorRect
@onready var _overlay : HT_MinimapOverlay = $Overlay

var _terrain : HTerrain = null
var _mode := MODE_NORMAL
var _camera_transform := Transform3D()


func _ready():
	if HT_Util.is_in_edited_scene(self):
		return
	
	_set_mode(_mode)
	
	_popup_menu.add_item("Quadtree mode", MODE_QUADTREE)
	_popup_menu.add_item("Normal mode", MODE_NORMAL)


func set_terrain(node: HTerrain):
	if _terrain != node:
		_terrain = node
		set_process(_terrain != null)


func set_camera_transform(ct: Transform3D):
	if _camera_transform == ct:
		return
	if _terrain == null:
		return
	var data = _terrain.get_data()
	if data == null:
		return
	var to_local := _terrain.get_internal_transform().affine_inverse()
	var pos := _get_xz(to_local * _camera_transform.origin)
	var size := Vector2(data.get_resolution(), data.get_resolution())
	pos /= size
	var dir := _get_xz(to_local.basis * (-_camera_transform.basis.z)).normalized()
	_overlay.set_cursor_position_normalized(pos, dir)
	_camera_transform = ct


static func _get_xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_RIGHT:
					_popup_menu.position = get_screen_position() + event.position
					_popup_menu.popup()
				MOUSE_BUTTON_LEFT:
					# Teleport there?
					pass


func _process(delta):
	if _terrain != null:
		if _mode == MODE_QUADTREE:
			queue_redraw()
		else:
			_update_normal_material()


func _set_mode(mode: int):
	if mode == MODE_QUADTREE:
		_color_rect.hide()
	else:
		var mat := ShaderMaterial.new()
		mat.shader = HT_MinimapShader
		_color_rect.material = mat
		_color_rect.show()
		_update_normal_material()
	_mode = mode
	queue_redraw()


func _update_normal_material():
	if _terrain == null:
		return
	var data : HTerrainData = _terrain.get_data()
	if data == null:
		return

	var normalmap = data.get_texture(HTerrainData.CHANNEL_NORMAL)
	_set_if_changed(_color_rect.material, "u_normalmap", normalmap)

	var globalmap : Texture
	if data.has_texture(HTerrainData.CHANNEL_GLOBAL_ALBEDO, 0):
		globalmap = data.get_texture(HTerrainData.CHANNEL_GLOBAL_ALBEDO)
	if globalmap == null:
		globalmap = load(WHITE_TEXTURE_PATH)
	_set_if_changed(_color_rect.material, "u_globalmap", globalmap)


# Need to check if it has changed, otherwise Godot's update spinner
# indicates that the editor keeps redrawing every frame,
# which is not intended and consumes more power.
static func _set_if_changed(sm: ShaderMaterial, param: String, v):
	if sm.get_shader_parameter(param) != v:
		sm.set_shader_parameter(param, v)


func _draw():
	if _terrain == null:
		return
	
	if _mode == MODE_QUADTREE:
		var lod_count := _terrain.get_lod_count()
	
		if lod_count > 0:
			# Fit drawing to rect
			
			var qsize = 1 << (lod_count - 1)
			var vsize := size
			draw_set_transform(Vector2(0, 0), 0, Vector2(vsize.x / qsize, vsize.y / qsize))
	
			_terrain._edit_debug_draw(self)


func _on_PopupMenu_id_pressed(id: int):
	_set_mode(id)
