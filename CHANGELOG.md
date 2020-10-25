Changelog
============

This is a high-level changelog for each released versions of the plugin.
For a more detailed list of past and incoming changes, see the commit history.



1.4
----

- Added properties to set collision layer and mask
- Added a parameter in `Classic4` shaders to reduce texture tiling
- Added a scale parameter to the default grass shader
- Added lookdev mode to visualise terrain maps with debug colors
- Added height picking to the flatten tool
- Adding and removing detail maps is now undoable
- Detail layer nodes no longer auto-select their index
- Breaking change: normal maps of ground textures now use OpenGL convention like Godot, instead of DirectX convention
- Fixed removal of detail maps not being saved properly
- Fixed GDNative library being registered with the wrong name on Linux
- Fixed error when selecting a detail layer node having an index out of range
- Fixed detail layers with a custom mesh disappearing when their density is left to default value


1.3.4
------

- GDNative acceleration now has a prebuilt binary on Linux
- Fixed collider being offset by half a cell
- Fixed default 1x1 shape data causing an assertion in Bullet since Godot 3.2.3, using 2x2 instead
- Fixed script syntax error to workaround Godot 3.1 limitation
- Fixed cast issue of integer ID from JSON when loading terrain data


1.3.3
-------

- Fixed error when using an orthogonal camera
- Fixed error when detail layer view distance is set to different values than default
- Fixed detail layers not painting properly when selecting one above 0


1.3.2
-----

- Fixed error when finishing a paint gesture while not having painted anything
- Fixed small inaccuracy between the heightmap pixels and visual position of vertices (#183)
- Fixed errors when setting `map_scale` to `0.01` and below
- Fixed error when saving a terrain with `map_scale` different than its default value


1.3.1
------

- Fixed new terrain maps saving with wrong import settings


1.3
----

- Added new Array shader allowing up to 256 ground textures, and new docs about this workflow
- Added shaded view to the minimap with a camera icon, quadtree view is optional
- Added simple "low-poly" shader without textures
- Added per-texture color factor and UV scale to the main Classic4 shader (thanks Tinmanjuggernaut)
- Added ability to specify a custom detail mesh, and bundled a few in `models/` folder
- Added an option to choose endianess when importing a raw heightmap
- Added EXR to heightmap import options
- Reworked ground texture selector to display packed and array textures correctly
- The default shader is now CLASSIC4_LITE, the other one needs extra setup
- Fixed rare terrain chunk popping due to vertical size wrongly rounded
- Fixed undo not working correctly with more than one detail layer
- Fixed texture editor allowing to load textures from outside the project (which doesn't work)
- Fixed texture editor not allowing to choose JPG images
- Fixed global translation not being taken into account (local was used as global)
- Fixed Godot crashing or running out of memory after lots of edits


1.2.1
------

- Optimized doc images to shorten download from assetlib (thanks to Calinou)
- Improved LOD in orthogonal projection where the camera is very far away
- Allow to choose lower terrain resolutions
- Optimized raycast when painting from large distances
- Limited detail layer max distance in the inspector, for performance reasons
- Fixed detail painting could not be erased
- Fixed import of splatmap and color map
- Fixed brush not working in orthogonal view
- Fixed grass chunks disappearing when their global density is changed
- Fixed error in exported game due to an editor-specific class being present in a script
- Fixed u_terrain_normal_basis parameter which should not appear in detail layer inspector
- Fixed lower brush not working


1.2  - a4d0a55493994bcf10b668ff1272ca1655c2ab32
-----------------------------------------------------

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


1.0 - Move to Godot 3.1 - a696ee41503ff41798d4fd401bf03b97c1177521
--------------------------------------------------------------------

- Saving a scene now saves terrains properly
- Grass layers are now nodes for ease of use
- Customizable grass shaders
- Customizable grass distance
- New documentation
- Fixed resize causing artifacts on heightmap and brushes (engine side)
- Fixed pickable collider causing a huge slowdown (raycasting is still slow but needs a fix in Bullet Physics)


0.10 - e4f3d560e6eabe6ae1d68bf80734737ce849cb2e
---------------------------------------------------

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
