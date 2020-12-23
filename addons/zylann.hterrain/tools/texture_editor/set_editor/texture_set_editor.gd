tool
extends Control

const HTerrainTextureSet = preload("../../../hterrain_texture_set.gd")
const EditorUtil = preload("../../util/editor_util.gd")
const Util = preload("../../../util/util.gd")

const ColorShader = preload("../display_color.shader")
const ColorSliceShader = preload("../display_color_slice.shader")
const AlphaShader = preload("../display_alpha.shader")
const AlphaSliceShader = preload("../display_alpha_slice.shader")
const EmptyTexture = preload("../../icons/empty.png")

signal import_selected

onready var _slots_list = $VB/HS/VB/SlotsList
onready var _albedo_preview = $VB/HS/VB2/GC/AlbedoPreview
onready var _bump_preview = $VB/HS/VB2/GC/BumpPreview
onready var _normal_preview = $VB/HS/VB2/GC/NormalPreview
onready var _roughness_preview = $VB/HS/VB2/GC/RoughnessPreview
onready var _load_albedo_button = $VB/HS/VB2/GC/LoadAlbedo
onready var _load_normal_button = $VB/HS/VB2/GC/LoadNormal
onready var _clear_albedo_button = $VB/HS/VB2/GC/ClearAlbedo
onready var _clear_normal_button = $VB/HS/VB2/GC/ClearNormal
onready var _mode_selector = $VB/HS/VB2/GC2/ModeSelector
onready var _add_slot_button = $VB/HS/VB/HB/AddSlot
onready var _remove_slot_button = $VB/HS/VB/HB/RemoveSlot

var _texture_set : HTerrainTextureSet
var _undo_redo : UndoRedo

var _mode_confirmation_dialog : ConfirmationDialog
var _delete_slot_confirmation_dialog : ConfirmationDialog
var _load_texture_dialog : WindowDialog
var _load_texture_array_dialog : WindowDialog
var _load_texture_type := -1


func _ready():
	if Util.is_in_edited_scene(self):
		return
	for id in HTerrainTextureSet.MODE_COUNT:
		var mode_name = HTerrainTextureSet.get_import_mode_name(id)
		_mode_selector.add_item(mode_name, id)


func setup_dialogs(parent: Node):
	var d = EditorUtil.create_open_texture_dialog()
	d.connect("file_selected", self, "_on_LoadTextureDialog_file_selected")
	_load_texture_dialog = d
	parent.add_child(d)

	d = EditorUtil.create_open_texture_array_dialog()
	d.connect("file_selected", self, "_on_LoadTextureArrayDialog_file_selected")
	_load_texture_array_dialog = d
	parent.add_child(d)
	
	d = ConfirmationDialog.new()
	d.connect("confirmed", self, "_on_ModeConfirmationDialog_confirmed")
	# This is ridiculous.
	# See https://github.com/godotengine/godot/issues/17460
#	d.connect("modal_closed", self, "_on_ModeConfirmationDialog_cancelled")
#	d.get_close_button().connect("pressed", self, "_on_ModeConfirmationDialog_cancelled")
#	d.get_cancel().connect("pressed", self, "_on_ModeConfirmationDialog_cancelled")
	_mode_confirmation_dialog = d
	parent.add_child(d)


func _notification(what: int):
	if Util.is_in_edited_scene(self):
		return
	
	if what == NOTIFICATION_EXIT_TREE:
		# Have to check for null in all of them,
		# because otherwise it breaks in the scene editor...
		if _load_texture_dialog != null:
			_load_texture_dialog.queue_free()
		if _load_texture_array_dialog != null:
			_load_texture_array_dialog.queue_free()
	
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			set_texture_set(null)


func set_undo_redo(ur: UndoRedo):
	_undo_redo = ur


func set_texture_set(texture_set: HTerrainTextureSet):
	if _texture_set == texture_set:
		return
	
	if _texture_set != null:
		_texture_set.disconnect("changed", self, "_on_texture_set_changed")

	_texture_set = texture_set
	
	if _texture_set != null:
		_texture_set.connect("changed", self, "_on_texture_set_changed")
		_update_ui_from_data()


func _on_texture_set_changed():
	_update_ui_from_data()


func _update_ui_from_data():
	var prev_selected_items = _slots_list.get_selected_items()
	
	_slots_list.clear()
	
	var slots_count := _texture_set.get_slots_count()
	for slot_index in slots_count:
		_slots_list.add_item("Texture {0}".format([slot_index]))
	
	_set_selected_id(_mode_selector, _texture_set.get_mode())
	
	if _slots_list.get_item_count() > 0:
		if len(prev_selected_items) > 0:
			var i : int = prev_selected_items[0]
			if i >= _slots_list.get_item_count():
				i = _slots_list.get_item_count() - 1
			_select_slot(i)
		else:
			_select_slot(0)
	else:
		_clear_previews()
	
	var max_slots := HTerrainTextureSet.get_max_slots_for_mode(_texture_set.get_mode())
	_add_slot_button.disabled = slots_count >= max_slots
	_remove_slot_button.disabled = slots_count == 0

	var buttons = [
		_load_albedo_button, 
		_load_normal_button, 
		_clear_albedo_button, 
		_clear_normal_button
	]
	
	if _texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES:
		_add_slot_button.visible = true
		_remove_slot_button.visible = true
		_load_albedo_button.text = "Load..."
		_load_normal_button.text = "Load..."
		
		for b in buttons:
			b.disabled = slots_count == 0
		
	else:
		_add_slot_button.visible = false
		_remove_slot_button.visible = false
		_load_albedo_button.text = "Load Array..."
		_load_normal_button.text = "Load Array..."

		for b in buttons:
			b.disabled = false


static func _set_selected_id(ob: OptionButton, id: int):
	for i in ob.get_item_count():
		if ob.get_item_id(i) == id:
			ob.selected = i
			break


func select_slot(slot_index: int):
	var count = _texture_set.get_slots_count()
	if count > 0:
		if slot_index >= count:
			slot_index = count - 1
		_select_slot(slot_index)


func _clear_previews():
	_albedo_preview.texture = EmptyTexture
	_bump_preview.texture = EmptyTexture
	_normal_preview.texture = EmptyTexture
	_roughness_preview.texture = EmptyTexture
	
	_albedo_preview.hint_tooltip = _get_resource_path_or_empty(null)
	_bump_preview.hint_tooltip = _get_resource_path_or_empty(null)
	_normal_preview.hint_tooltip = _get_resource_path_or_empty(null)
	_roughness_preview.hint_tooltip = _get_resource_path_or_empty(null)


func _select_slot(slot_index: int):
	assert(slot_index >= 0)
	assert(slot_index < _texture_set.get_slots_count())
	
	if _texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES:
		var albedo_tex := \
			_texture_set.get_texture(slot_index, HTerrainTextureSet.TYPE_ALBEDO_BUMP)
		var normal_tex := \
			_texture_set.get_texture(slot_index, HTerrainTextureSet.TYPE_NORMAL_ROUGHNESS)
	
		_albedo_preview.texture = albedo_tex if albedo_tex != null else EmptyTexture
		_bump_preview.texture = albedo_tex if albedo_tex != null else EmptyTexture
		_normal_preview.texture = normal_tex if normal_tex != null else EmptyTexture
		_roughness_preview.texture = normal_tex if normal_tex != null else EmptyTexture
		
		_albedo_preview.hint_tooltip = _get_resource_path_or_empty(albedo_tex)
		_bump_preview.hint_tooltip = _get_resource_path_or_empty(albedo_tex)
		_normal_preview.hint_tooltip = _get_resource_path_or_empty(normal_tex)
		_roughness_preview.hint_tooltip = _get_resource_path_or_empty(normal_tex)

		_albedo_preview.material.shader = ColorShader
		_bump_preview.material.shader = AlphaShader
		_normal_preview.material.shader = ColorShader
		_roughness_preview.material.shader = AlphaShader
		
		_albedo_preview.material.set_shader_param("u_texture_array", null)
		_bump_preview.material.set_shader_param("u_texture_array", null)
		_normal_preview.material.set_shader_param("u_texture_array", null)
		_roughness_preview.material.set_shader_param("u_texture_array", null)
	
	else:
		var albedo_tex := _texture_set.get_texture_array(HTerrainTextureSet.TYPE_ALBEDO_BUMP)
		var normal_tex := _texture_set.get_texture_array(HTerrainTextureSet.TYPE_NORMAL_ROUGHNESS)
	
		_albedo_preview.texture = EmptyTexture
		_bump_preview.texture = EmptyTexture
		_normal_preview.texture = EmptyTexture
		_roughness_preview.texture = EmptyTexture
		
		_albedo_preview.hint_tooltip = _get_resource_path_or_empty(albedo_tex)
		_bump_preview.hint_tooltip = _get_resource_path_or_empty(albedo_tex)
		_normal_preview.hint_tooltip = _get_resource_path_or_empty(normal_tex)
		_roughness_preview.hint_tooltip = _get_resource_path_or_empty(normal_tex)
		
		_albedo_preview.material.shader = ColorSliceShader
		_bump_preview.material.shader = AlphaSliceShader
		_normal_preview.material.shader = ColorSliceShader if normal_tex != null else ColorShader
		_roughness_preview.material.shader = AlphaSliceShader if normal_tex != null else AlphaShader
		
		_albedo_preview.material.set_shader_param("u_texture_array", albedo_tex)
		_bump_preview.material.set_shader_param("u_texture_array", albedo_tex)
		_normal_preview.material.set_shader_param("u_texture_array", normal_tex)
		_roughness_preview.material.set_shader_param("u_texture_array", normal_tex)
	
	_albedo_preview.material.set_shader_param("u_index", slot_index)
	_bump_preview.material.set_shader_param("u_index", slot_index)
	_normal_preview.material.set_shader_param("u_index", slot_index)
	_roughness_preview.material.set_shader_param("u_index", slot_index)
	
	_slots_list.select(slot_index)


static func _get_resource_path_or_empty(res: Resource) -> String:
	if res != null:
		return res.resource_path
	return "<empty>"


func _on_ImportButton_pressed():
	emit_signal("import_selected")


func _on_CloseButton_pressed():
	hide()


func _on_AddSlot_pressed():
	assert(_texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES)
	var slot_index = _texture_set.get_slots_count()
	_undo_redo.create_action("HTerrainTextureSet: add slot")
	_undo_redo.add_do_method(_texture_set, "insert_slot", -1)
	_undo_redo.add_undo_method(_texture_set, "remove_slot", slot_index)
	_undo_redo.commit_action()


func _on_RemoveSlot_pressed():
	assert(_texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES)
	
	var slot_index = _slots_list.get_selected_items()[0]
	var textures = []
	for type in HTerrainTextureSet.TYPE_COUNT:
		textures.append(_texture_set.get_texture(slot_index, type))
	
	_undo_redo.create_action("HTerrainTextureSet: remove slot")

	_undo_redo.add_do_method(_texture_set, "remove_slot", slot_index)

	_undo_redo.add_undo_method(_texture_set, "insert_slot", slot_index)
	for type in len(textures):
		var texture = textures[type]
		# TODO This branch only exists because of a flaw in UndoRedo
		# See https://github.com/godotengine/godot/issues/36895
		if texture == null:
			_undo_redo.add_undo_method(_texture_set, "set_texture_null", slot_index, type)
		else:
			_undo_redo.add_undo_method(_texture_set, "set_texture", slot_index, type, texture)

	_undo_redo.commit_action()


func _on_SlotsList_item_selected(index: int):
	_select_slot(index)


func _open_load_texture_dialog(type: int):
	_load_texture_type = type
	if _texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES:
		_load_texture_dialog.popup_centered_ratio()
	else:
		_load_texture_array_dialog.popup_centered_ratio()


func _on_LoadAlbedo_pressed():
	_open_load_texture_dialog(HTerrainTextureSet.TYPE_ALBEDO_BUMP)


func _on_LoadNormal_pressed():
	_open_load_texture_dialog(HTerrainTextureSet.TYPE_NORMAL_ROUGHNESS)


func _set_texture_action(slot_index: int, texture: Texture, type: int):
	var prev_texture = _texture_set.get_texture(slot_index, type)
	
	_undo_redo.create_action("HTerrainTextureSet: load texture")
	
	# TODO This branch only exists because of a flaw in UndoRedo
	# See https://github.com/godotengine/godot/issues/36895
	if texture == null:
		_undo_redo.add_do_method(_texture_set, "set_texture_null", slot_index, type)
	else:
		_undo_redo.add_do_method(_texture_set, "set_texture", slot_index, type, texture)
	_undo_redo.add_do_method(self, "_select_slot", slot_index)
	
	# TODO This branch only exists because of a flaw in UndoRedo
	# See https://github.com/godotengine/godot/issues/36895
	if prev_texture == null:
		_undo_redo.add_undo_method(_texture_set, "set_texture_null", slot_index, type)
	else:
		_undo_redo.add_undo_method(_texture_set, "set_texture", slot_index, type, prev_texture)
	_undo_redo.add_undo_method(self, "_select_slot", slot_index)
	
	_undo_redo.commit_action()


func _set_texture_array_action(slot_index: int, texture_array: TextureArray, type: int):
	var prev_texture_array = _texture_set.get_texture_array(type)
	
	_undo_redo.create_action("HTerrainTextureSet: load texture array")
	
	# TODO This branch only exists because of a flaw in UndoRedo
	# See https://github.com/godotengine/godot/issues/36895
	if texture_array == null:
		_undo_redo.add_do_method(_texture_set, "set_texture_array_null", type)
	else:
		_undo_redo.add_do_method(_texture_set, "set_texture_array", type, texture_array)
	_undo_redo.add_do_method(self, "_select_slot", slot_index)
	
	# TODO This branch only exists because of a flaw in UndoRedo
	# See https://github.com/godotengine/godot/issues/36895
	if prev_texture_array == null:
		_undo_redo.add_undo_method(_texture_set, "set_texture_array_null", type)
	else:
		_undo_redo.add_undo_method(_texture_set, "set_texture_array", type, prev_texture_array)
	_undo_redo.add_undo_method(self, "_select_slot", slot_index)
	
	_undo_redo.commit_action()


func _on_LoadTextureDialog_file_selected(fpath: String):
	assert(_texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES)
	var texture = load(fpath)
	assert(texture != null)
	var slot_index : int = _slots_list.get_selected_items()[0]
	_set_texture_action(slot_index, texture, _load_texture_type)


func _on_LoadTextureArrayDialog_file_selected(fpath: String):
	assert(_texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURE_ARRAYS)
	var texture_array = load(fpath)
	assert(texture_array != null)
	var slot_index : int = _slots_list.get_selected_items()[0]
	_set_texture_array_action(slot_index, texture_array, _load_texture_type)


func _on_ClearAlbedo_pressed():
	var slot_index : int = _slots_list.get_selected_items()[0]
	if _texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES:
		_set_texture_action(slot_index, null, HTerrainTextureSet.TYPE_ALBEDO_BUMP)
	else:
		_set_texture_array_action(slot_index, null, HTerrainTextureSet.TYPE_ALBEDO_BUMP)


func _on_ClearNormal_pressed():
	var slot_index : int = _slots_list.get_selected_items()[0]
	if _texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES:
		_set_texture_action(slot_index, null, HTerrainTextureSet.TYPE_NORMAL_ROUGHNESS)
	else:
		_set_texture_array_action(slot_index, null, HTerrainTextureSet.TYPE_NORMAL_ROUGHNESS)


func _on_ModeSelector_item_selected(index: int):
	var id = _mode_selector.get_selected_id()
	if id == _texture_set.get_mode():
		return
	
	# Early-cancel the change in OptionButton, so we won't need to rely on
	# the (inexistent) cancel signal from ConfirmationDialog
	_set_selected_id(_mode_selector, _texture_set.get_mode())
	
	if not _texture_set.has_any_textures():
		_switch_mode_action()
		
	else:
		if _texture_set.get_mode() == HTerrainTextureSet.MODE_TEXTURES:
			_mode_confirmation_dialog.window_title = "Switch to TextureArrays"
			_mode_confirmation_dialog.dialog_text = \
				"This will unload all textures currently setup. Do you want to continue?"
			_mode_confirmation_dialog.popup_centered()
		
		else:
			_mode_confirmation_dialog.window_title = "Switch to Textures"
			_mode_confirmation_dialog.dialog_text = \
				"This will unload all textures currently setup. Do you want to continue?"
			_mode_confirmation_dialog.popup_centered()


func _on_ModeConfirmationDialog_confirmed():
	_switch_mode_action()


func _switch_mode_action():
	var mode := _texture_set.get_mode()
	var ur := _undo_redo
	
	if mode == HTerrainTextureSet.MODE_TEXTURES:
		ur.create_action("HTerrainTextureSet: switch to TextureArrays")
		ur.add_do_method(_texture_set, "set_mode", HTerrainTextureSet.MODE_TEXTURE_ARRAYS)
		backup_for_undo(_texture_set, ur)
	
	else:
		ur.create_action("HTerrainTextureSet: switch to Textures")
		ur.add_do_method(_texture_set, "set_mode", HTerrainTextureSet.MODE_TEXTURES)
		backup_for_undo(_texture_set, ur)
	
	ur.commit_action()


static func backup_for_undo(texture_set: HTerrainTextureSet, ur: UndoRedo):
	var mode := texture_set.get_mode()

	ur.add_undo_method(texture_set, "clear")
	ur.add_undo_method(texture_set, "set_mode", mode)
	
	if mode == HTerrainTextureSet.MODE_TEXTURES:
		# Backup slots
		var slot_count := texture_set.get_slots_count()
		var type_textures := []
		for type in HTerrainTextureSet.TYPE_COUNT:
			var textures := []
			for slot_index in slot_count:
				textures.append(texture_set.get_texture(slot_index, type))
			type_textures.append(textures)

		for type in len(type_textures):
			var textures = type_textures[type]
			for slot_index in len(textures):
				ur.add_undo_method(texture_set, "insert_slot", slot_index)
				var texture = textures[slot_index]
				# TODO This branch only exists because of a flaw in UndoRedo
				# See https://github.com/godotengine/godot/issues/36895
				if texture == null:
					ur.add_undo_method(texture_set, "set_texture_null", slot_index, type)
				else:
					ur.add_undo_method(texture_set, "set_texture", slot_index, type, texture)
	
	else:
		# Backup slots
		var type_textures := []
		for type in HTerrainTextureSet.TYPE_COUNT:
			type_textures.append(texture_set.get_texture_array(type))

		for type in len(type_textures):
			var texture_array = type_textures[type]
			# TODO This branch only exists because of a flaw in UndoRedo
			# See https://github.com/godotengine/godot/issues/36895
			if texture_array == null:
				ur.add_undo_method(texture_set, "set_texture_array_null", type)
			else:
				ur.add_undo_method(texture_set, "set_texture_array", type, texture_array)


#func _on_ModeConfirmationDialog_cancelled():
#	print("Cancelled")
#	_set_selected_id(_mode_selector, _texture_set.get_mode())

