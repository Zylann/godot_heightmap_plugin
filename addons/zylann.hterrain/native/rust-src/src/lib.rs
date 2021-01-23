pub mod util;

use gdnative::prelude::*;

fn init(handle: InitHandle) {
	handle.add_class::<util::QuadTreeLod>();
}

godot_init!(init);
