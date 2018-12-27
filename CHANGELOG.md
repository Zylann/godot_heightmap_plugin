Changelog
============

This is a high-level changelog for each released versions of the plugin.
For a more detailed list of past and incoming changes, see the commit history.

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

Compatibility breakage:
- packed bump and roughness were swapped in ground shader API

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
