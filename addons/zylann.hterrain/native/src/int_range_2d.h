#ifndef INT_RANGE_2D_H
#define INT_RANGE_2D_H

#include "math_funcs.h"
#include "vector2i.h"
#include <core/Rect2.hpp>

struct IntRange2D {
    int min_x;
    int min_y;
    int max_x;
    int max_y;

    static IntRange2D from_min_max(godot::Vector2 min_pos, godot::Vector2 max_pos) {
        return IntRange2D(godot::Rect2(min_pos, max_pos));
    }

    IntRange2D(godot::Rect2 rect) {
        min_x = static_cast<int>(rect.position.x);
        min_y = static_cast<int>(rect.position.y);
        max_x = static_cast<int>(rect.position.x + rect.size.x);
        max_y = static_cast<int>(rect.position.y + rect.size.y);
    }

    bool is_inside(Vector2i size) const {
        return min_x >= size.x &&
               min_y >= size.y &&
               max_x <= size.x &&
               max_y <= size.y;
    }

    void clip(Vector2i size) {
        min_x = Math::clamp(min_x, 0, size.x);
        min_y = Math::clamp(min_y, 0, size.y);
        max_x = Math::clamp(max_x, 0, size.x);
        max_y = Math::clamp(max_y, 0, size.y);
    }
};

#endif // INT_RANGE_2D_H
