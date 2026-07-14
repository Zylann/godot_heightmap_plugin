@tool
extends AcceptDialog

signal generate_selected(lod)

@onready var _preview_label : Label = $VBoxContainer/PreviewLabel
@onready var _lod_spinbox : SpinBox = $VBoxContainer/HBoxContainer/LODSpinBox

var _terrain : HTerrain = null


func _init() -> void:
	get_ok_button().hide()


func set_terrain(terrain: HTerrain) -> void:
	_terrain = terrain


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible and _terrain != null:
			_update_preview()


func _on_LODSpinBox_value_changed(_unused_value: float) -> void:
	_update_preview()


func _update_preview() -> void:
	assert(_terrain != null)
	assert(_terrain.get_data() != null)
	var resolution := _terrain.get_data().get_resolution()
	var stride := int(_lod_spinbox.value)
	resolution /= stride
	var s := HTerrainMesher.get_mesh_size(resolution, resolution)
	_preview_label.text = str( \
		HT_Util.format_integer(s.vertices), " vertices, ", \
		HT_Util.format_integer(s.triangles), " triangles")


func _on_Generate_pressed() -> void:
	var stride := int(_lod_spinbox.value)
	generate_selected.emit(stride)
	hide()


func _on_Cancel_pressed() -> void:
	hide()
