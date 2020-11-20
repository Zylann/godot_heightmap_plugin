tool
extends Control

const EmptyTexture = preload("../../icons/empty.png")

signal load_pressed
signal clear_pressed


onready var _label = $Label
onready var _texture_rect = $TextureRect

onready var _buttons = [
	$LoadButton,
	$ClearButton
]

var _material : Material


func set_label(text: String):
	_label.text = text


func set_texture(tex: Texture):
	if tex == null:
		_texture_rect.texture = EmptyTexture
		_texture_rect.material = null
	else:
		_texture_rect.texture = tex
		_texture_rect.material = _material


func set_texture_tooltip(msg: String):
	_texture_rect.hint_tooltip = msg


func _on_LoadButton_pressed():
	emit_signal("load_pressed")


func _on_ClearButton_pressed():
	emit_signal("clear_pressed")


func set_material(mat: Material):
	_material = mat
	if _texture_rect.texture != EmptyTexture:
		_texture_rect.material = _material


func set_enabled(enabled: bool):
	for b in _buttons:
		b.disabled = not enabled

