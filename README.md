HeightMap terrain plugin for Godot Engine
=========================================

![Editor screenshot](https://user-images.githubusercontent.com/1311555/49705861-a5275380-fc19-11e8-8338-9ad364d2db8d.png)

Heightmap-based terrain for Godot 4.1+.
It supports texture painting, colouring, holes, level of detail and grass, while still targetting the Godot API.

This repository holds the latest development version, which means it has the latest features, latest fixes, but can also have bugs.
You may use the version on the asset library, but if the changelog has fixes or improvements you need, the `master` branch of this repo can be better.

To get the last version that supported Godot 3.0.6, checkout [branch `0.10`](https://github.com/Zylann/godot_heightmap_plugin/tree/0.10) (no longer maintained).

To get the last version that supported Godot 3.x, checkout [branch `godot3`](https://github.com/Zylann/godot_heightmap_plugin/tree/godot3) (no longer maintained)


Installation
--------------

This is a regular editor plugin.
Copy the contents of `addons/zylann.hterrain` into the same folder in your project, and activate it in your project settings.

The plugin now comes with no extra assets to stay lightweight.
If you want to try an example scene, you can install this demo once the plugin is setup and active:
https://github.com/Zylann/godot_hterrain_demo


Usage
----------

[Documentation](https://hterrain-plugin.readthedocs.io/en/latest/)


Why this is a plugin
----------------------

Godot has no terrain system for 3D at the moment, so I made one.
The plugin is fully implemented in GDScript, mainly for ease of change and compatibility. There is no plan to implement a GDExtension part.
Godot could get a terrain system in the future, but it's going to be a long wait, so developping this plugin allows to explore a lot of things up-front, such as procedural generation and editor tools, which could still be of use later.


Supporters
-----------

This plugin is a non-profit project developed by voluntary contributors. The following is the list of the current donors.
Thanks for your support :)

### Gold supporters

```
Aaron Franke (aaronfranke)
```

### Silver supporters

```
TheConceptBoy
Chris Bolton (yochrisbolton)
Gamerfiend (Snowminx) 
greenlion (Justin Swanhart) 
segfault-god (jp.owo.Manda)
RonanZe
Phyronnaz
NoFr1ends (Lynx)
```

### Supporters

```
rcorre (Ryan Roden-Corrent) 
duchainer (Raphaël Duchaîne)
MadMartian
stackdump (stackdump.eth)
Treer
MrGreaterThan
lenis0012
nan0m (Fabian)
```
