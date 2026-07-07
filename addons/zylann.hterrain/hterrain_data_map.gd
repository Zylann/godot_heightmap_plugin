# A map is an image/texture covering the terrain.
# The usage of a map depends on its type (heightmap, normalmap, splatmap...).
# This object is internal to `HTerrainData` and may preferably not be accessed directly.
class_name HTerrainDataMap

var texture: Texture2D

# Reference used in case we need the data CPU-side
var image: Image

# ID used for saving, because when adding/removing maps,
# we shouldn't rename texture files just because the indexes change.
# This is mostly for internal keeping.
# The API still uses indexes that may shift if your remove a map.
var id := -1

# Should be set to true if the map has unsaved modifications.
var modified := true

# Used for density maps, to know if an area contains any non-zero pixel.
var occupancy : HTerrainDataOccupancyMap = null


func _init(p_id: int):
	id = p_id
