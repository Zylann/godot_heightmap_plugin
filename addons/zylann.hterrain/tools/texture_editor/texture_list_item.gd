@tool
extends PanelContainer
# Had to use PanelContainer, because due to variable font sizes in the editor,
# the contents of the VBoxContainer can vary in size, and so in height.
# Which means the entire item can have variable size, not just because of DPI.
# In such cases, the hierarchy must be made of containers that grow based on their children.

const HT_ColorMaterial = preload("./display_color_material.tres")
const HT_ColorSliceShader = preload("./display_color_slice.gdshader")
# TODO Can't preload because it causes the plugin to fail loading if assets aren't imported
#const HT_DummyTexture = preload("../icons/empty.png")
const DUMMY_TEXTURE_PATH = "res://addons/zylann.hterrain/tools/icons/empty.png"

@onready var _texture_rect : TextureRect = $VB/TextureRect
@onready var _label : Label = $VB/Label


var _selected := false


func set_text(text: String):
	_label.text = text


func set_texture(texture: Texture, texture_layer: int):
	if texture is TextureLayered:
		var mat = _texture_rect.material
		if mat == null or not (mat is ShaderMaterial):
			mat = ShaderMaterial.new()
			mat.shader = HT_ColorSliceShader
			_texture_rect.material = mat
		mat.set_shader_parameter("u_texture_array", texture)
		mat.set_shader_parameter("u_index", texture_layer)
		_texture_rect.texture = load(DUMMY_TEXTURE_PATH)
	else:
		_texture_rect.texture = texture
		_texture_rect.material = HT_ColorMaterial


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				grab_focus()
				set_selected(true, true)
				if event.double_click:
					# Don't do this at home.
					# I do it here because this script is very related to its container anyways.
					get_parent().get_parent()._on_item_activated(self)


func set_selected(selected: bool, notify: bool):
	if selected == _selected:
		return
	_selected = selected
	queue_redraw()
	if _selected:
		_label.modulate = Color(0,0,0)
	else:
		_label.modulate = Color(1,1,1)
	if notify:
		get_parent().get_parent()._on_item_selected(self)


func _draw():
	var color : Color
	if _selected:
		color = get_theme_color("accent_color", "Editor")
	else:
		color = Color(0.0, 0.0, 0.0, 0.5)
	# Draw background
	draw_rect(Rect2(Vector2(), size), color)
