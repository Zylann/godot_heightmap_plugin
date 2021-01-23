use gdnative::api::FuncRef;
use gdnative::core_types::{Color, Rect2};
use gdnative::prelude::*;
use std::cell::RefCell;

pub type HTerrainChunk = Variant;

#[derive(Clone, Copy)]
struct Vector2i {
	x: u32,
	y: u32
}

struct Quad {
	children: Option<Box<[Quad; 4]>>,
	origin: Vector2i,
	data: HTerrainChunk,
}


#[derive(NativeClass)]
#[inherit(Object)]
pub struct QuadTreeLod {
	tree: RefCell<Quad>,
	max_depth: u32,
	base_size: u32,
	split_scale: f32,
	make_func: Option<Ref<FuncRef>>,
	recycle_func: Option<Ref<FuncRef>>,
	vertical_bounds_func: Option<Ref<FuncRef>>,
}


impl Quad {
	fn new() -> Self {
		Self {
			children: None,
			origin: Vector2i { x: 0, y: 0 },
			data: Variant::new(),
		}
	}

	fn has_children(&self) -> bool {
		!self.children.is_none()
	}
}

#[methods]
impl QuadTreeLod {
	pub fn new(_owner: &Object) -> Self {
		Self {
			tree: RefCell::new(Quad::new()),
			max_depth: 0,
			base_size: 16,
			split_scale: 2.0,
			make_func: None,
			recycle_func: None,
			vertical_bounds_func: None,
		}
	}

	#[export]
	pub fn set_callbacks(&mut self, _owner: &Object, make_func: Ref<FuncRef>, recycle_func: Ref<FuncRef>, vertical_bounds_func: Ref<FuncRef>) {
		self.make_func = Some(make_func);
		self.recycle_func = Some(recycle_func);
		self.vertical_bounds_func = Some(vertical_bounds_func);
	}

	#[export]
	pub fn clear(&mut self, _owner: &Object) {
		if let Ok(ref mut quad) = self.tree.try_borrow_mut() {
			self.join_all_recursively(quad, self.max_depth);
			self.max_depth = 0;
			self.base_size = 0;
		} else {
			godot_error!("tree is already borrowed mutably (BUG)");
		}
	}

	fn compute_lod_count(base_size: u32, full_size: u32) -> u32 {
		let mut po = 0;
		let mut full_size = full_size;
		while full_size > base_size {
			full_size >>= 1;
			po += 1;
		}
		po
	}

	#[export]
	pub fn create_from_sizes(&mut self, _owner: &Object, base_size: u32, full_size: u32) {
		self.clear(_owner);
		self.base_size = base_size;
		self.max_depth = Self::compute_lod_count(base_size, full_size);
	}

	#[export]
	pub fn get_lod_count(&self, _owner: &Object) -> u32 {
		self.max_depth + 1
	}

	#[export]
	pub fn set_split_scale(&mut self, _owner: &Object, split_scale: f32) {
		let min = 2.0;
		let max = 5.0;

		self.split_scale = if split_scale < min {
			min
		} else if split_scale > max {
			max
		} else {
			split_scale
		};
	}

	#[export]
	pub fn get_split_scale(&self, _owner: &Object) -> f32 {
		self.split_scale
	}

	#[export]
	#[profiled]
	pub fn update(&self, _owner: &Object, view_pos: Vector3) {
		if let Ok(ref mut quad) = self.tree.try_borrow_mut() {
			self.quad_update(
				quad,
				self.max_depth,
				view_pos,
			);

			if !quad.has_children() && quad.data.is_nil() {
				quad.data = self.make_chunk(self.max_depth, Vector2i { x: 0, y: 0 })
			}
		} else {
			godot_error!("tree is already borrowed mutably (BUG)");
		}
	}

	#[export]
	pub fn get_lod_size(&self, _owner: &Object, lod: u32) -> u32 {
		Self::get_lod_size_static(lod)
	}

	fn get_lod_size_static(lod: u32) -> u32 {
		1 << lod
	}

	fn quad_update(
		&self,
		quad: &mut Quad,
		lod: u32,
		view_pos: Vector3,
	) {
		let lod_factor = Self::get_lod_size_static(lod);
		let chunk_size = self.base_size * lod_factor;
		let mut world_center =
			Vector3::new(quad.origin.x as f32 + 0.5, 0.0, quad.origin.y as f32 + 0.5)
				* chunk_size as f32;

		if let Some(f) = &self.vertical_bounds_func {
			let args = [
				Variant::from_u64(quad.origin.x as u64),
				Variant::from_u64(quad.origin.y as u64),
				Variant::from_u64(lod as u64),
			];
			let vbounds = unsafe { f.assume_safe().call_func(&args) };
			if let Some(v) = vbounds.try_to_vector2() {
				world_center.y = (v.x + v.y) / 2.0;
			} else {
				godot_error!(
					"Unexpected type returned from vertical_bounds_func: {:?}",
					vbounds
				);
				return;
			}
		}

		let world_center = world_center;
		let split_distance = self.base_size as f32 * lod_factor as f32 * self.split_scale;

		if let Some(children) = &mut quad.children {
			let mut no_split_child = true;

			for child in children.iter_mut() {
				self.quad_update(child, lod - 1, view_pos);
				if child.has_children() {
					no_split_child = false;
				}
			}

			if no_split_child
				&& world_center.distance_squared_to(view_pos) > split_distance * split_distance
			{
				for child in children.iter_mut() {
					self.recycle_chunk(child.data.clone(), child.origin, lod - 1);
				}
				quad.children = None;
				quad.data = self.make_chunk(lod, quad.origin);
			}
		} else {
			if lod > 0
				&& world_center.distance_squared_to(view_pos) < split_distance * split_distance
			{
				let mut children = Box::new([Quad::new(), Quad::new(), Quad::new(), Quad::new()]);

				for (i, child) in children.iter_mut().enumerate() {
					child.origin = Vector2i {
						x: quad.origin.x * 2 + (i as u32 & 1),
						y: quad.origin.y * 2 + ((i as u32 & 2) >> 1),
					};
					child.data = self.make_chunk(lod - 1, child.origin);
				}

				quad.children = Some(children);

				if !quad.data.is_nil() {
					self.recycle_chunk(quad.data.clone(), quad.origin, lod);
					quad.data = Variant::new();
				}
			}
		}
	}

	fn join_all_recursively(&self, quad: &mut Quad, lod: u32) {
		if let Some(children) = &mut quad.children {
			for child in children.iter_mut() {
				self.join_all_recursively(child, lod - 1);
			}
		} else if !quad.data.is_nil() {
			self.recycle_chunk(quad.data.clone(), quad.origin, lod);
		}
	}

	fn make_chunk(&self, lod: u32, origin: Vector2i) -> HTerrainChunk {
		if let Some(f) = &self.make_func {
			let args = [
				Variant::from_u64(origin.x as u64),
				Variant::from_u64(origin.y as u64),
				Variant::from_u64(lod as u64),
			];
			unsafe { f.assume_safe().call_func(&args) }
		} else {
			Variant::new()
		}
	}

	fn recycle_chunk(&self, chunk: HTerrainChunk, origin: Vector2i, lod: u32) {
		if let Some(f) = &self.recycle_func {
			let args = [
				chunk,
				Variant::from_u64(origin.x as u64),
				Variant::from_u64(origin.y as u64),
				Variant::from_u64(lod as u64),
			];
			unsafe { f.assume_safe().call_func(&args) };
		}
	}

	#[export]
	pub fn debug_draw_tree(&self, _owner: &Object, ci: Ref<CanvasItem>) {
		if let Ok(ref quad) = self.tree.try_borrow() {
			Self::debug_draw_tree_recursive(unsafe { ci.assume_safe().as_ref() }, quad, self.max_depth, 0);
		} else {
			godot_error!("tree is already borrowed mutably (BUG)");
		}
	}

	fn debug_draw_tree_recursive(ci: &CanvasItem, quad: &Quad, lod_index: u32, child_index: u32) {
		if let Some(children) = &quad.children {
			for (i, child) in children.iter().enumerate() {
				Self::debug_draw_tree_recursive(ci, child, lod_index - 1, i as u32)
			}
		} else {
			let size = Self::get_lod_size_static(lod_index);
			let checker = if child_index == 1 || child_index == 2 {
				1.0
			} else {
				0.0
			};
			let chunk_indicator = if quad.data.is_nil() { 0.0 } else { 1.0 };
			let r = Rect2::new(
				Point2::new(quad.origin.x as f32, quad.origin.y as f32) * size as f32,
				Size2::new(size as f32, size as f32),
			);
			ci.draw_rect(
				r,
				Color::rgb(1.0 - lod_index as f32 * 0.2, 0.2 * checker, chunk_indicator),
				true,
				1.0,
				false,
			);
		}
	}
}
