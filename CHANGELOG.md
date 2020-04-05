Changelog
============

This is a high-level changelog for each released versions of the plugin.
For a more detailed list of past and incoming changes, see the commit history.


1.2
------

- Added GDNative component to accelerate some parts of the plugin (Windows only, more platforms to come).
- Platforms where GDNative doesn't run will fallback on GDScript
- Larger brush sizes can be used on platforms where the GDNative component is supported
- Added proper "smooth" brush, old smooth is now called "level".
- Added EXR format to terrain exporter
- Improved UI for high-DPI displays
- Using the generator can be undone
- More type hints in the codebase
- The plugin no longer prints debug logs, unless Godot is executed in verbose mode
- Fix terrain not hiding if its parent node is hidden
- Fix z-fighting artifacts when the terrain is hidden and shown back
- Fix offset brush when the 3D viewport is in half-resolution mode
- Fix 8-bit PNG heightmap export


1.1.1
------

- Added configuration warning if the terrain node has no data assigned
- Grey out menu items if conditions for them to work aren't fulfilled.
- Increased maximum chunk size to 64 to help performance tuning. Default is now 32.
- Fixed `map_scale` not working
- Fixed inspector becoming blank when shader type is set to "custom" while no shader was assigned yet
- Fixed tiny imprecision when importing raw heightmaps
- Fixed version check causing the collider to be offset in Godot 3.1.2


1.1
--------

- Added tool to export heightmap data to a raw file or image
- Add ability to change base density of grass
- Collision hits now report `collider` as the terrain node instead of `null`
- Most of function signatures in the API now use typed GDScript
- Fixed whitespace at the end of `plugin.gd` seen as an error in Godot 3.2
- Fixed collider vertically offset due to a change in the Bullet module
- Fixed inspector not updating properties when the shader is changed
- Fixed terrain not saving if the scene is saved just after a non-undoable action (using a workaround)
- Fixed terrain areas becoming black if resized bigger


1.0.2
------

- Fix grass shader, it wasn't handling vertical map scale correctly
- Fix smooth brush behaving like raise/lower in opacity lower than max
- Fix terrain not saving changes made from the generator


1.0.1
------

- Remove obsolete Save and Load menus, they don't work anymore


1.0 Move to Godot 3.1
------------------------

- Saving a scene now saves terrains properly
- Grass layers are now nodes for ease of use
- Customizable grass shaders
- Customizable grass distance
- New documentation
- Fixed resize causing artifacts on heightmap and brushes (engine side)
- Fixed pickable collider causing a huge slowdown (raycasting is still slow but needs a fix in Bullet Physics)


0.10
------

- Added morphologic erosion to terrain generator
- Added global map baking
- Added ground shader parameter to blend towards global map over distance
- Added properties to tint grass using the global map
- Added property to tweak shading at the bottom of grass
- Speed up sculpting by moving normals baking to GPU
- Slightly improved LOD performance
- Increased default file dialog size when selecting grass texture
- Fixed issue with grass shading based on ground normals
- Fixed grass preview lighting (was too dark)


0.9.1
------------

- Reduce checkbox size in generator tool
- Make zoom slower in generator tool
- Fixed brush decal not showing up at certain angles
- Fixed script error in some of the tools
- Fixed terrain inspector not allowing to set shader textures


0.9
---------

- Bring back configurable brush shapes
- Improved terrain generator UI with 3D preview, baseline and draggable offset
- Added tool to generate a full mesh of the terrain so Godot can bake a navmesh
- The strength of sculpting tools is now proportional to brush size
- Terrain resources generate a greyscale thumbnail
- Resizing can be done by cropping or expanding in a given direction (Terrain menu)
- Fixed potential cleanup error when the editor closes
- Fixed custom types not cleaned up when the plugin is disabled
- Fixed LOD to take height into account on tall mountains
- Fixed terrain textures being lossy-compressed when reopening the project
- Fixed grass painting being available when there are no detail layers


0.8.1
------

- Heightmaps are now saved as `.res` so they are included in export
- Fixed cursor decal not showing when creating a terrain from scratch
- Fixed editor nodes not cleaned up when the plugin is disabled
- Select grass tool after adding a new grass type


0.8
-----

- Custom ground shaders
- Added a variant of the default shader which uses less texture samplers
- Collision is active by default
- Collision works in editor so other tools can use it (update is manual)
- Compatibility breakage: packed bump and roughness were swapped in ground shader API
- Fixed a few culling bugs
- Fixed error when adding a detail layer while looking far away
- Fixed normals not updating when generating a terrain over an existing one
- Fixed terrain LOD updating around the game's camera instead of the editor's camera


0.7
---

- Added basic ambient wind (waving grass)
- Improved import of heightmaps, splatmaps and colormaps
- Option to double chunk size (better quality and less draw calls but more vertices)
- LOD scale can be changed (better quality but more draw calls)

0.6.1
------

- Collisions are now working with Godot 3.0.4 and later
- Fix errors when clicking while the terrain has no data

0.6
-----

- Terrain can be scaled using special `map_scale` property
- Improved icons
- Grass can be erased properly
- Saving only saves what's needed
- Fixed grass culling

0.5: port to Godot 3.0.2
---------------------------

- Added level of detail
- Added grass painting
- Added generator
- Changed collision to use Bullet (on Godot master branch only)
- Improved texture paint to use a splatmap
- More shading features
- Various other changes in UI and API

0.4
----

- Added texture paint through vertex colors
- Added HumanSheeple's shader to support up to 18 textures
- Added jump to the demo, I guess
- Fix Modo navigation conflict

0.3
----

- Added collisions
- Improved demo with a simple character controller
- New icon

0.2
----

- Added flatten brush mode
- Fix terrain having no default size

0.1.1
------

- Fix bottom panel editor conflict

0.1: Initial release in Godot 2.1
-----------------------------------

- Heightmap edition with undo/redo
- Small demo with simple texture-less shader
