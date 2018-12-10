HeightMap terrain plugin for Godot Engine 3.x
================================================

![Editor screenshot](https://user-images.githubusercontent.com/1311555/49705861-a5275380-fc19-11e8-8338-9ad364d2db8d.png)

Heightmap-based terrain for Godot 3.0.2 and later.
It supports texture painting, colouring, holes, level of detail and grass.

Although the plugin can be used, it is still under development. Some features might be missing or bugs can occur.
Please refer to the issue tracker if you have any problem.

This repository holds the latest development version, which means it has the latest features but can also have bugs.
For a "stable" version, use the asset library or download from a commit tagged with a version.


Installation
--------------

This is a regular editor plugin.
Copy the contents of `addons/zylann.hterrain` into the same folder in your project, and activate it in your project settings.

The plugin now comes with no extra assets to stay lightweight.
If you want to try an example scene, you can install this demo once the plugin is setup and active:
https://github.com/Zylann/godot_hterrain_demo


Usage
----------

I haven't written much docs yet, but I wrote a note about creating a terrain because there are some gotchas:
https://github.com/Zylann/godot_heightmap_native_plugin/blob/master/addons/zylann.hterrain/doc/main.md

I also made a video about the 0.8 version of the plugin:
https://www.youtube.com/watch?v=eZuvfIHDeT4&


Language notes
----------------------

The plugin is currently fully implemented in GDScript.
It contains code for a C++ implementation using GDNative, however it doesn't work well, is getting outdated and will probably be archived some day.
The reason is, the plugin may still change so maintaining two versions on all platforms is too much work for me, and I found it actually works decently without C++.
Eventually, one day some performance-sensitive areas could be implemented using GDNative, to optionally give some boost.
