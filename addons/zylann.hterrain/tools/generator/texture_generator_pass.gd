
# Name of the pass, for debug purposes
var debug_name := ""
# The viewport will be cleared at this pass
var clear := false
# Which main texture should be drawn.
# If not set, a default texture will be drawn.
# Note that it won't matter if the shader disregards it,
# and will only serve to provide UVs, due to https://github.com/godotengine/godot/issues/7298.
var texture : Texture = null
# Which shader to use
var shader : Shader = null
# Parameters for the shader
# TODO Use explicit Dictionary, dont allow null
var params = null
# How many pixels to pad the viewport on all edges, in case neighboring matters.
# Outputs won't have that padding, but can pick part of it in case output padding is used.
var padding := 0
# How many times this pass must be run
var iterations := 1
# If not empty, the viewport will be downloaded as an image before the next pass
var output := false
# Sent along the output
var metadata = null
# Used for tiled rendering, where each tile has the base resolution,
# in case the viewport cannot be made big enough to cover the final image,
# of if you are generating a pseudo-infinite terrain.
# TODO Have an API for this?
var tile_pos := Vector2()

func duplicate():
	var p = get_script().new()
	p.debug_name = debug_name
	p.clear = clear
	p.texture = texture
	p.shader = shader
	p.params = params
	p.padding = padding
	p.iterations = iterations
	p.output = output
	p.metadata = metadata
	p.tile_pos = tile_pos
	return p
