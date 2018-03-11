#ifndef POD_VECTOR_H
#define POD_VECTOR_H

#include <stdlib.h>
#include <string.h>
#include <core/GodotGlobal.hpp>

#include "macros.h"

// Contiguous data container for POD types.
// Please do not use this with types that don't support raw member-wise copy.
template <typename T>
class PodVector {

public:
	PodVector() : m_data(nullptr), m_capacity(0), m_size(0) {
	}

	PodVector(const PodVector<T> & p_other) {
		*this = p_other;
	}

	~PodVector() {
		hard_clear();
	}

	inline size_t size() const {
		return m_size;
	}

	inline size_t capacity() const {
		return m_capacity;
	}

	bool contains(const T &p_value) const {
		for(size_t i = 0; i < m_size; ++i) {
			if(m_data[i] == p_value)
				return true;
		}
		return false;
	}

	bool find(const T &p_value, size_t &out_index) const {
		for(size_t i = 0; i < m_size; ++i) {
			if(m_data[i] == p_value) {
				out_index = i;
				return true;
			}
		}
		return false;
	}

	bool unordered_remove(const T &p_value) {
		size_t i;
		if(find(p_value, i)) {
			unordered_remove_at(i);
			return true;
		}
		return false;
	}

	void unordered_remove_at(size_t i) {
		assert(i < size());
		size_t last = size() - 1;
		m_data[i] = m_data[last];
		resize_no_init(last);
	}

	void fill(const T & p_value) {
		for(size_t i = 0; i < m_size; ++i) {
			m_data[i] = value;
		}
	}

	void fill_range(const T & p_value, size_t p_begin, size_t p_size) {
		size_t end = p_begin + p_size;
		assert(end <= m_size);
		for(size_t i = p_begin; i < end; ++i) {
			m_data[i] = p_value;
		}
	}

	void resize_no_init(size_t p_size) {

		if(p_size == 0) {

			// Capacity won't shrink in this case,
			// you need to call shrink explicitely for this to happen
			clear();

		} else if(p_size > m_capacity) {
			resize_capacity(p_size);
		}

		m_size = p_size;
	}

	void resize(size_t p_size, const T & p_fill_value) {
		if(p_size > m_size) {
			size_t old_size = m_size;
			resize_no_init(p_size);
			fill_range(p_fill_value, old_size, p_size);
		} else {
			resize_no_init(p_size);
		}
	}

	void clear() {
		m_size = 0;
	}

	void hard_clear() {
		m_size = 0;
		m_capacity = 0;
		if(m_data != nullptr) {
			godot::api->godot_free(m_data);
			m_data = nullptr;
		}
	}

	const T *raw() {
		return m_data;
	}

	void push_back(const T & p_value) {

		if(m_size == m_capacity) {
			resize_capacity(m_capacity + (m_capacity / 2) + 1);
		}

		m_data[m_size] = p_value;
		++m_size;
	}

	void pop_back() {
		assert(m_size != 0);
		--m_size;
	}

	void shrink() {
		if(m_capacity != m_size) {
			resize_capacity(m_size);
		}
	}

	const T & operator[](size_t p_index) const {
		assert(p_index < m_size);
		return m_data[p_index];
	}

	T & operator[](size_t p_index) {
		assert(p_index < m_size);
		return m_data[p_index];
	}

	PodVector<T> & operator=(const PodVector<T> &p_other) {
		if(m_size < p_other.m_size) {
			resize_no_init(p_other.m_size);
		}
		memcpy(m_data, p_other.m_data, m_size * sizeof(T));
	}

private:
	void resize_capacity(size_t p_capacity) {

		if(m_data == nullptr) {
			m_data = static_cast<T*>(godot::api->godot_alloc(p_capacity * sizeof(T)));

		} else {
			if(p_capacity != 0) {
				m_data = static_cast<T*>(godot::api->godot_realloc(m_data, p_capacity * sizeof(T)));
			} else {
				godot::api->godot_free(m_data);
				m_data = nullptr;
			}
		}

		m_capacity = p_capacity;
	}

private:
	T *m_data;
	size_t m_capacity;
	size_t m_size;

};


#endif // POD_VECTOR_H
