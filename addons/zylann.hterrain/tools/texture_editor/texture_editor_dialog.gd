tool
extends AcceptDialog

const HTerrain = preload("../../hterrain.gd")

# Need to know when albedo changed because it's used as the "main" preview
signal albedo_changed(slot, texture)

var _terrain = null
var _slot = 0

onready var _albedo_preview = get_node("GridContainer/AlbedoPreview")
onready var _normal_preview = get_node("GridContainer/NormalPreview")
onready var _bump_preview = get_node("GridContainer/BumpPreview")
onready var _roughness_preview = get_node("GridContainer/RoughnessPreview")

var _load_dialog = null
var _load_dialog_tex_type = -1

var _empty_icon = preload("../icons/empty.png")


func set_terrain(terrain):
	_terrain = terrain
	_update_previews()


func set_load_texture_dialog(dialog):
	_load_dialog = dialog


func set_slot(slot):
	if _terrain == null:
		return
	_slot = slot
	_update_previews()


func _update_previews():
	_albedo_preview.texture = _get_preview_texture(_slot, HTerrain.GROUND_ALBEDO_BUMP)
	_roughness_preview.texture = _get_preview_texture(_slot, HTerrain.GROUND_ALBEDO_BUMP)
	_normal_preview.texture = _get_preview_texture(_slot, HTerrain.GROUND_NORMAL_ROUGHNESS)
	_bump_preview.texture = _get_preview_texture(_slot, HTerrain.GROUND_NORMAL_ROUGHNESS)


func _get_preview_texture(slot, tex_type):
	if _terrain == null:
		return _empty_icon
	var tex = _terrain.get_ground_texture(slot, tex_type)
	if tex == null:
		return _empty_icon
	return tex


func _open_load_dialog(tex_type):
	_load_dialog_tex_type = tex_type
	_load_dialog.connect("file_selected", self, "_on_LoadTextureDialog_file_selected")
	_load_dialog.popup_centered_ratio()


func _on_LoadTextureDialog_file_selected(fpath):
	var tex = load(fpath)
	if tex == null:
		return
	_set_texture(tex, _load_dialog_tex_type)


func _set_texture(tex, type):
	# TODO Make it undoable
	_terrain.set_ground_texture(_slot, type, tex)
	_update_previews()
	if type == HTerrain.GROUND_ALBEDO_BUMP:
		emit_signal("albedo_changed", _slot, tex)


func _on_LoadAlbedo_pressed():
	_open_load_dialog(HTerrain.GROUND_ALBEDO_BUMP)


func _on_LoadNormal_pressed():
	_open_load_dialog(HTerrain.GROUND_NORMAL_ROUGHNESS)


func _on_ClearAlbedo_pressed():
	_set_texture(null, HTerrain.GROUND_ALBEDO_BUMP)


func _on_ClearNormal_pressed():
	_set_texture(null, HTerrain.GROUND_NORMAL_ROUGHNESS)

