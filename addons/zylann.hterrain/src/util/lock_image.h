#ifndef LOCK_IMAGE_H
#define LOCK_IMAGE_H

#include <core/Ref.hpp>
#include <Image.hpp>

struct LockImage {
	LockImage(godot::Ref<godot::Image> im) {
		_im = im;
		_im->lock();
	}
	~LockImage() {
		_im->unlock();
	}
	godot::Ref<godot::Image> _im;
};

#endif // LOCK_IMAGE_H
