tool
extends PanelContainer
# Had to use PanelContainer, because due to variable font sizes in the editor,
# the contents of the VBoxContainer can vary in size, and so in height.
# Which means the entire item can have variable size, not just because of DPI.
# In such cases, the hierarchy must be made of containers that grow based on their children.

onready var _texture_rect = $VB/TextureRect
onready var _label = $VB/Label

const ColorMaterial = preload("./display_color_material.tres")
const ColorSliceShader = preload("./display_color_slice.shader")
const DummyTexture = preload("../icons/empty.png")


var _selected := false


func set_text(text: String):
	_label.text = text


func set_texture(texture: Resource, texture_layer: int):
	if texture is TextureArray:
		var mat = _texture_rect.material
		if mat == null or not (mat is ShaderMaterial):
			mat = ShaderMaterial.new()
			mat.shader = ColorSliceShader
			_texture_rect.material = mat
		mat.set_shader_param("u_texture_array", texture)
		mat.set_shader_param("u_index", texture_layer)
		_texture_rect.texture = DummyTexture
	else:
		_texture_rect.texture = texture
		_texture_rect.material = ColorMaterial


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == BUTTON_LEFT:
				grab_focus()
				set_selected(true, true)
				if event.doubleclick:
					# Don't do this at home.
					# I do it here because this script is very related to its container anyways.
					get_parent().get_parent()._on_item_activated(self)


func set_selected(selected: bool, notify: bool):
	if selected == _selected:
		return
	_selected = selected
	update()
	if _selected:
		_label.modulate = Color(0,0,0)
	else:
		_label.modulate = Color(1,1,1)
	if notify:
		get_parent().get_parent()._on_item_selected(self)


func _draw():
	var color : Color
	if _selected:
		color = get_color("accent_color", "Editor")
	else:
		color = Color(0.0, 0.0, 0.0, 0.5)
	# Draw background
	draw_rect(Rect2(Vector2(), rect_size), color)
