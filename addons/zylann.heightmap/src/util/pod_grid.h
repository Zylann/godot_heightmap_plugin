#ifndef POD_GRID_H
#define POD_GRID_H

#include "pod_vector.h"
#include "point2i.h"

// Grid contiguous storage. Must only contain POD types.
template <typename T>
class PodGrid2D {
public:
	inline Point2i size() const { return m_size; }

	inline int area() const {
		return m_size.x * m_size.y;
	}

	inline T get(Point2i pos) const {
		return m_data[index(pos)];
	}

	inline T get(int x, int y) const {
		return m_data[index(x, y)];
	}

	inline const T *raw() const {
		return m_data.ptr();
	}

	inline T operator[](int i) const {
		return m_data[i];
	}

	inline T &operator[](int i) {
		return m_data[i];
	}

	inline void set(Point2i pos, T v) {
		set(pos.x, pos.y, v);
	}

	inline void set(int x, int y, T v) {
		m_data[index(x, y)] = v;
	}

	inline T get_or_default(int x, int y) const {
		if (is_valid_pos(x, y))
			return get(x, y);
		return T();
	}

	inline T get_or_default(Point2i pos) const {
		return get_or_default(pos.x, pos.y);
	}

	inline T get_clamped(int x, int y) const {
		if (x < 0)
			x = 0;
		if (y < 0)
			y = 0;
		if (x >= m_size.x)
			x = m_size.x - 1;
		if (y >= m_size.y)
			y = m_size.y - 1;
		return get(x, y);
	}

	inline bool is_valid_pos(int x, int y) const {
		return x >= 0 && y >= 0 && x < m_size.x && y < m_size.y;
	}

	inline bool is_valid_pos(Point2i pos) const {
		return is_valid_pos(pos.x, pos.y);
	}

	inline int index(Point2i pos) const {
		return index(pos.x, pos.y);
	}

	inline int index(int x, int y) const {
		return y * m_size.x + x;
	}

	void clear() {
		m_data.clear();
		m_size = Point2i();
	}

	void resize(Point2i new_size, bool preserve_data, T defval = T()) {
		assert(new_size.x >= 0 && new_size.y >= 0);

		Point2i old_size = m_size;
		int new_area = new_size.x * new_size.y;

		if (preserve_data) {

			// The following resizes the grid in place,
			// so that it doesn't allocates more memory than needed.

			if (old_size.x == new_size.x) {
				// Column count didn't change, no need to offset any data
				m_data.resize(new_area, T());

			} else {
				// The number of columns did change

				if (new_area > m_data.size()) {
					// The array becomes bigger, enlarge it first so that we can offset the data
					m_data.resize(new_area, T());
				}

				// Now we need to offset rows

				if (new_size.x < old_size.x) {
					// Shrink columns
					// (the first column doesn't change)
					for (int y = 0; y < old_size.y; ++y) {
						int old_row_begin = y * old_size.x;
						int new_row_begin = y * new_size.x;

						for (int x = 0; x < new_size.x; ++x) {
							m_data[new_row_begin + x] = m_data[old_row_begin + x];
						}
					}

				} else if (new_size.x > old_size.x) {
					// Offset columns at bigger intervals:
					// Iterate backwards because otherwise we would overwrite the data we want to move
					// (The first column doesn't change either)

					// .     .     .
					// 1 2 3 4 5 6 7 8 9
					// .       .       .       .
					// 1 2 3 4 5 6 7 8 9 _ _ _ _ _ _ _
					// 1 2 3 _ 4 5 6 _ 7 8 9 _ _ _ _ _

					int y = old_size.y - 1;
					if (y >= new_size.y)
						y = new_size.y - 1;

					while (y >= 0) {
						int old_row_begin = y * old_size.x;
						int new_row_begin = y * new_size.x;

						int x = old_size.x - 1;
						while (x >= 0) {
							m_data[new_row_begin + x] = m_data[old_row_begin + x];
							x -= 1;
						}

						// Fill gaps with default values
						for (int x = old_size.x; x < new_size.x; ++x) {
							m_data[new_row_begin + x] = defval;
						}

						y -= 1;
					}
				}

				if (new_area < m_data.size()) {
					// The array becomes smaller, shrink it at the end so that we can offset the data in place
					m_data.resize(new_area, T());
				}
			}

			// Fill new rows with default value
			for (int y = old_size.y; y < new_size.y; ++y) {
				for (int x = 0; x < new_size.x; ++x) {
					m_data[x + y * new_size.x] = defval;
				}
			}

		} else {
			// Don't care about the data, just resize
			m_data.clear();
			m_data.resize(new_area, T());
		}

		m_size = new_size;
	}

	inline void fill(T value) {
		for (int i = 0; i < m_data.size(); ++i) {
			m_data[i] = value;
		}
	}

#if TODO
	PoolByteArray dump_region(Point2i min, Point2i max) const {

		ERR_FAIL_COND_V(!is_valid_pos(min), PoolByteArray());
		ERR_FAIL_COND_V(!is_valid_pos(max), PoolByteArray());

		PoolByteArray output;
		Point2i size = max - min;
		int area = size.x * size.y;
		output.resize(area * sizeof(T));

		{
			PoolByteArray::Write w8 = output.write();
			T *wt = (T *)w8.ptr();

			int i = 0;
			Point2i pos;
			for(pos.y = min.y; pos.y < max.y; ++pos.y) {
				for(pos.x = min.x; pos.x < max.x; ++pos.x) {
					T v = get(pos);
					wt[i] = v;
					++i;
				}
			}
		}

		return output;
	}

	void apply_dump(const PoolByteArray &data, Point2i min, Point2i max) {

		ERR_FAIL_COND(!is_valid_pos(min));
		ERR_FAIL_COND(!is_valid_pos(max));

		Point2i size = max - min;
		int area = size.x * size.y;

		ERR_FAIL_COND(area != data.size() / sizeof(T));

		{
			PoolByteArray::Read r = data.read();
			const T *rt = (const T*)r.ptr();

			int i = 0;
			Point2i pos;
			for(pos.y = min.y; pos.y < max.y; ++pos.y) {
				for(pos.x = min.x; pos.x < max.x; ++pos.x) {
					set(pos, rt[i]);
					++i;
				}
			}
		}
	}
#endif

	void clamp_min_max_excluded(Point2i &min, Point2i &max) const {

		if (min.x < 0)
			min.x = 0;
		if (min.y < 0)
			min.y = 0;

		if (min.x >= m_size.x)
			min.x = m_size.x - 1;
		if (min.y >= m_size.y)
			min.y = m_size.y - 1;

		if (max.x < 0)
			max.x = 0;
		if (max.y < 0)
			max.y = 0;

		if (max.x > m_size.x)
			max.x = m_size.x;
		if (max.y > m_size.y)
			max.y = m_size.y;
	}

private:
	PodVector<T> m_data;
	Point2i m_size;
};

#endif // POD_GRID_H
