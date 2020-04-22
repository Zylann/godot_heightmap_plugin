
# Editor-specific utilities.
# This script cannot be loaded in an exported game.

tool

# TODO There is no script API to access editor scale
# Ported from https://github.com/godotengine/godot/blob/
# 5fede4a81c67961c6fb2309b9b0ceb753d143566/editor/editor_node.cpp#L5515-L5554
static func get_dpi_scale(editor_settings: EditorSettings) -> float:
	var display_scale = editor_settings.get("interface/editor/display_scale")
	var custom_display_scale = editor_settings.get("interface/editor/custom_display_scale")
	var edscale := 0.0

	match display_scale:
		0:
			# Try applying a suitable display scale automatically
			var screen = OS.current_screen
			var large = OS.get_screen_dpi(screen) >= 192 and OS.get_screen_size(screen).x > 2000
			edscale = 2.0 if large else 1.0
		1:
			edscale = 0.75
		2:
			edscale = 1.0
		3:
			edscale = 1.25
		4:
			edscale = 1.5
		5:
			edscale = 1.75
		6:
			edscale = 2.0
		_:
			edscale = custom_display_scale

	return edscale

