#ifndef MATH_H
#define MATH_H

namespace Math {

	static inline float lerp(float p_from, float p_to, float p_weight) {

		return p_from + (p_to - p_from) * p_weight;
	}

	static inline unsigned int next_power_of_2(unsigned int x) {

		--x;
		x |= x >> 1;
		x |= x >> 2;
		x |= x >> 4;
		x |= x >> 8;
		x |= x >> 16;

		return ++x;
	}

}


#endif // MATH_H
