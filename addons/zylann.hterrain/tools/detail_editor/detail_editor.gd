tool
extends Control

const HTerrainData = preload("../../hterrain_data.gd")
const HTerrainDetailLayer = preload("../../hterrain_detail_layer.gd")

signal detail_selected(index)
# Emitted when the tool added or removed a detail map
signal detail_list_changed

onready var _item_list = $ItemList
onready var _confirmation_dialog = $ConfirmationDialog

var _terrain = null
var _dialog_target = -1
var _placeholder_icon = load("res://addons/zylann.hterrain/tools/icons/icon_grass.svg")
var _detail_layer_icon = load("res://addons/zylann.hterrain/tools/icons/icon_detail_layer_node.svg")


func set_terrain(terrain):
	if _terrain == terrain:
		return
	_terrain = terrain
	_update_list()


func set_layer_index(i):
	_item_list.select(i, true)


func _update_list():
	_item_list.clear()
	
	if _terrain == null:
		return
	
	var layers = _terrain.get_detail_layers()
	var layers_by_index = {}
	for layer in layers:
		if not layers_by_index.has(layer.layer_index):
			layers_by_index[layer.layer_index] = []
		layers_by_index[layer.layer_index].append(layer.name)

	var data = _terrain.get_data()
	if data != null:
		# Display layers from what terrain data actually contains,
		# because layer nodes are just what makes them rendered and aren't much restricted.
		var layer_count = data.get_map_count(HTerrainData.CHANNEL_DETAIL)
		for i in layer_count:
			# TODO Show a preview icon
			_item_list.add_item(str("Map ", i), _placeholder_icon)
			
			if layers_by_index.has(i):
				# TODO How to keep names updated with node names?
				var names = PoolStringArray(layers_by_index[i]).join(", ")
				if len(names) == 1:
					_item_list.set_item_tooltip(i, "Used by " + names)
				else:
					_item_list.set_item_tooltip(i, "Used by " + names)
				# Remove custom color
				# TODO Use fg version when available in Godot 3.1, I want to only highlight text
				_item_list.set_item_custom_bg_color(i, Color(0, 0, 0, 0))
			else:
				# TODO Use fg version when available in Godot 3.1, I want to only highlight text
				_item_list.set_item_custom_bg_color(i, Color(1.0, 0.2, 0.2, 0.3))
				_item_list.set_item_tooltip(i, "This map isn't used by any layer. " \
					+ "Add a HTerrainDetailLayer node as child of the terrain.")


func _on_Add_pressed():
	assert(_terrain != null)
	assert(_terrain.get_data() != null)
	
	# TODO Make undoable
	var layer = HTerrainDetailLayer.new()
	# TODO Workarounds for https://github.com/godotengine/godot/issues/21410
	layer.set_meta("_editor_icon", _detail_layer_icon)
	layer.name = "HTerrainDetailLayer"
	_terrain.add_child(layer)
	layer.owner = get_tree().edited_scene_root
	# Note: detail layers auto-add their data map in the editor,
	# and may also pick an unused one if available
	
	_update_list()
	emit_signal("detail_list_changed")
	
	var index = layer.layer_index
	_item_list.select(index)
	# select() doesn't trigger the signal
	emit_signal("detail_selected", index)


func _on_Remove_pressed():
	var selected = _item_list.get_selected_items()
	if len(selected) == 0:
		return
	_dialog_target = _item_list.get_selected_items()[0]
	_confirmation_dialog.popup_centered()


func _on_ConfirmationDialog_confirmed():
	var data = _terrain.get_data()
	data._edit_remove_map(HTerrainData.CHANNEL_DETAIL, _dialog_target)
	
	# Delete nodes that were referencing that map.
	var layers = _terrain.get_detail_layers()
	for layer in layers:
		if layer.layer_index == _dialog_target:
			layer.get_parent().remove_child(layer)
			layer.call_deferred("free")
		else:
			# Shift down layer indexes
			if layer.layer_index > _dialog_target:
				layer.layer_index -= 1
	
	_update_list()
	emit_signal("detail_list_changed")


func _on_ItemList_item_selected(index):
	emit_signal("detail_selected", index)


	
