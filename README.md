HeightMap terrain plugin for Godot Engine 3.x
================================================

![Editor screenshot](https://zylannprods.fr/images/godot/plugins/hterrain/screenshots/2018_04_02.png)

Heightmap-based terrain for Godot 3.0.2 and later.
It supports texture painting, colouring, holes, level of detail and grass.

Although the plugin can be used, it is still under development. Some features might be missing or bugs can occur.
Please refer to the issue tracker if you have any problem.


Installation
--------------

This is a regular editor plugin.
Copy the contents of `addons/zylann.hterrain` into the same folder in your project, and activate it in your project settings.

The plugin now comes with no extra assets to stay lightweight.
If you want to try an example scene, you can install this demo once the plugin is setup and active:
https://github.com/Zylann/godot_hterrain_demo


Language notes
----------------------

The plugin is currently fully implemented in GDScript.
It contains code for a C++ implementation using GDNative, however it doesn't work well, is getting outdated and will probably be archived some day.
The reason is, the plugin may still change so maintaining two versions on all platforms is too much work for me, and I found it actually works decently without C++.
Eventually, one day some performance-sensitive areas could be implemented using GDNative, to optionally give some boost.