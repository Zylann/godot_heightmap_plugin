@tool

# Stuff not exposed by Godot for making .import files

const COMPRESS_LOSSLESS = 0
const COMPRESS_LOSSY = 1
const COMPRESS_VRAM_COMPRESSED = 2
const COMPRESS_VRAM_UNCOMPRESSED = 3
const COMPRESS_BASIS_UNIVERSAL = 4

const ROUGHNESS_DETECT = 0
const ROUGHNESS_DISABLED = 1
# Godot internally subtracts 2 to magically obtain a `Image.RoughnessChannel` enum
# (also not exposed)
const ROUGHNESS_RED = 2
const ROUGHNESS_GREEN = 3
const ROUGHNESS_BLUE = 4
const ROUGHNESS_ALPHA = 5
const ROUGHNESS_GRAY = 6
