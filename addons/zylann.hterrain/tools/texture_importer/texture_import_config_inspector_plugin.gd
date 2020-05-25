tool
extends EditorInspectorPlugin

const TextureImportConfig = preload("./texture_import_config.gd")
const TextureImportConfigEditorScene = preload("./texture_import_config_editor.tscn")


func can_handle(obj: Object) -> bool:
	return obj is TextureImportConfig


func parse_property(obj: Object, type: int, path: String, hint: int, hint_text: String, 
	usage: int) -> bool:
	
	# Default sub-resource editor sucks, so replace with my own
	
	if path != "_textures":
		return false
		
	var ed = TextureImportConfigEditorScene.instance()
	add_custom_control(ed)
	ed.call_deferred("set_config", obj)

	return true
