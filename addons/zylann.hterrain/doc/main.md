HTerrain plugin documentation
===============================

This is a stub documentation to be written in the future.
I may write a few things here for now, but they are subject to change and be improved when I'll get to work on a bigger documentation pass.


Creating a terrain in Godot 3.0.2
--------------------------------------

Creating a terrain from scratch in this version of Godot is really awkward, due to a major lack in the script API. There is no way to define custom resource savers and loaders, so what the plugin should do automatically has to be done manually using workarounds:

1) Create a new HTerrainData resource in the inspector. You don't need to modify anything on it.

2) Save it as a .tres file

3) Create a HTerrain node

4) Select its data property, and load the .tres resource you saved earlier. Doing that should make a terrain appear. If you can't see it, make sure you have a light or an environment in your scene.

5) Change the resolution if needed, then click the Heightmap menu --> Save


Creating a terrain in Godot 3.1
----------------------------------

This is what I want to implement once Godot gets the API I need:

1) Create a new HTerrain node: a new terrain will apear

2) The node will have a warning sign next to it until you select a folder to save its data. Click on the data_directory property, and select where terrain data will be saved.

3) Save your scene with Ctrl+S

