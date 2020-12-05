HeightMap terrain plugin for Godot Engine
=========================================

![Editor screenshot](https://user-images.githubusercontent.com/1311555/49705861-a5275380-fc19-11e8-8338-9ad364d2db8d.png)

Heightmap-based terrain for Godot 3.1 and 3.2.
It supports texture painting, colouring, holes, level of detail and grass, while still targetting the Godot API.

**Note:** The current Godot `master` branch isn't supported yet. Use Godot 3.2 if you want to use this plugin.

This repository holds the latest development version, which means it has the latest features but can also have bugs.
For a "stable" version, use the asset library or download from a commit tagged with a version.
The `master` branch is the latest development version, and may have bugs. Some major features can also be in other branches until they are done. For release versions, check the Git branches named after those versions, like `0.10`.

To get the last version that supported Godot 3.0.6, checkout [branch `0.10`](https://github.com/Zylann/godot_heightmap_plugin/tree/0.10).


Installation
--------------

This is a regular editor plugin.
Copy the contents of `addons/zylann.hterrain` into the same folder in your project, and activate it in your project settings.

The plugin now comes with no extra assets to stay lightweight.
If you want to try an example scene, you can install this demo once the plugin is setup and active:
https://github.com/Zylann/godot_hterrain_demo


Usage
----------

- [Documentation](https://hterrain-plugin.readthedocs.io/en/latest/)

- I also made a video about the 0.8 version of the plugin: https://www.youtube.com/watch?v=eZuvfIHDeT4& Careful, it's a bit old and may not entirely reflect the last version. Use the text docs for most up to date information.


Why this is a plugin
----------------------

Godot has no terrain system for 3D at the moment, so I made one.
The plugin is currently fully implemented in GDScript. I wish I could make it a C++ module, but being a GDScript plugin allows much faster iteration and everyone can try it and modify it much more easily. Recently, some parts started to be implemented as a GDNative library to speed them up (only on supported platforms).
Godot could get a terrain system in the future, maybe in 4.x or after, but it's going to be a long wait, so developping this plugin allows me to explore a lot of things up-front, such as procedural generation and editor tools, which could still be of use later.


GLES2 support
---------------

Due to a number of things GLES2 doesn't support officially, and the disparity of extensions Godot is currently trying to use, making this plugin work in GLES2 is quite a lot of work. Some things might be easier, others need completely different implementations.

Here are some of the causes:

- `textureSize` doesn't work in shaders. If the following issues can be solved, we could rewrite all shaders without using this function so they are compatible between both renderers.

- High range textures get clamped to 0..1, making heightmaps completely flat (GLES2 actually supports this through an extension, but Godot doesn't appear to use it).

- `VisualServer` has `set_data_partial`, but it's not implemented so editing terrain doesn't work. GLES2 should also support partial texture update.

- GLES2 does not require texture fetch from vertex shader to work, so some rare mobile devices implement it, others don't. This plugin heavily relies on displacing vertices from shader. Generating unique meshes would require a huge rewrite just so it works on those devices and would use a ton more memory to store all the required meshes and LODs.

- The procedural generator doesn't work, and likely never will in GLES2 because it relies on HDR framebuffers.

- For more info, see https://github.com/Zylann/godot_heightmap_plugin/issues/96


Supporters
-----------

This plugin is a non-profit project developped by voluntary contributors. The following is the list of the current donors.
Thanks for your support :)

### Supporters

```
- wacyym
- Sergey Lapin (slapin)
- Jonas (NoFr1ends)
- lenis0012
```
