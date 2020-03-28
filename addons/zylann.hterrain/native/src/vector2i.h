#ifndef VECTOR2I_H
#define VECTOR2I_H

#include <core/Vector2.hpp>

struct Vector2i {
    int x;
    int y;

    Vector2i(godot::Vector2 v) :
            x(static_cast<int>(v.x)),
            y(static_cast<int>(v.y)) {}

    bool any_zero() const {
        return x == 0 || y == 0;
    }
};

#endif // VECTOR2I_H
