#ifndef POINT2I_H
#define POINT2I_H

#include <core/String.hpp>

struct Point2i {

	union {
		struct {
			int x;
			int y;
		};

		int coord[2];
	};

	Point2i() : x(0), y(0) {
	}

	Point2i(const Point2i &p_other) : x(p_other.x), y(p_other.y) {
	}

	Point2i(int p_x, int p_y) : x(p_x), y(p_y) {
	}

	inline void operator/=(const int s) {
		x /= s;
		y /= s;
	}

	inline void operator*=(const int s) {
		x *= s;
		y *= s;
	}

	inline void operator-=(const Point2i p_other) {
		x -= p_other.x;
		y -= p_other.y;
	}

	inline void operator+=(const Point2i p_other) {
		x += p_other.x;
		y += p_other.y;
	}

	inline operator godot::String() const {
		return godot::String::num(x) + ", " + godot::String::num(y);
	}
};

inline Point2i operator+(const Point2i p_a, const Point2i p_b) {
	return Point2i(p_a.x + p_b.x, p_a.y + p_b.y);
}

inline Point2i operator-(const Point2i p_a, const Point2i p_b) {
	return Point2i(p_a.x - p_b.x, p_a.y - p_b.y);
}

inline Point2i operator*(const Point2i p_a, const Point2i p_b) {
	return Point2i(p_a.x * p_b.x, p_a.y * p_b.y);
}

inline Point2i operator/(const Point2i p_a, const Point2i p_b) {
	return Point2i(p_a.x / p_b.x, p_a.y / p_b.y);
}

inline Point2i operator*(const Point2i p_a, const int p_k) {
	return Point2i(p_a.x * p_k, p_a.y * p_k);
}

inline Point2i operator/(const Point2i p_a, const int p_k) {
	return Point2i(p_a.x / p_k, p_a.y / p_k);
}

inline bool operator==(const Point2i p_a, const Point2i p_b) {
	return p_a.x == p_b.x && p_a.y == p_b.y;
}

inline bool operator!=(const Point2i p_a, const Point2i p_b) {
	return p_a.x != p_b.x || p_a.y != p_b.y;
}

void clamp_min_max_excluded(Point2i &out_min, Point2i &out_max, Point2i min, Point2i max);


#endif // POINT2I_H
