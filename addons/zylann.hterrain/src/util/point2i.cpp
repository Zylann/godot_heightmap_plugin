#include "point2i.h"

void clamp_min_max_excluded(Point2i &out_min, Point2i &out_max, Point2i min, Point2i max) {

	if (out_min.x < min.x)
		out_min.x = min.x;
	if (out_min.y < min.y)
		out_min.y = min.y;

	if (out_min.x > max.x)
		// Means the rectangle has zero length.
		// Position is invalid but shouldn't be iterated anyways
		out_min.x = max.x;
	if (out_min.y > max.y)
		out_min.y = max.y;

	if (out_max.x < min.x)
		// Means the rectangle has zero length.
		// Position is invalid but shouldn't be iterated anyways
		out_max.x = min.x;
	if (out_max.y < min.y)
		out_max.y = min.y;

	if (out_max.x > max.x)
		out_max.x = max.x;
	if (out_max.y > max.y)
		out_max.y = max.y;
}
