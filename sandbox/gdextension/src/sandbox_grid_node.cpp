#include "sandbox_grid_node.h"
#include <cstdlib>

using namespace godot;

void SandboxGridNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("process_physics", "state", "width", "height", "frame_count"), &SandboxGridNode::process_physics);
}

SandboxGridNode::SandboxGridNode() {
}

SandboxGridNode::~SandboxGridNode() {
}

// Fast PRNG for perfect chaos
static uint32_t fast_rand_seed = 123456789;
static inline uint32_t fast_rand() {
	fast_rand_seed ^= fast_rand_seed << 13;
	fast_rand_seed ^= fast_rand_seed >> 17;
	fast_rand_seed ^= fast_rand_seed << 5;
	return fast_rand_seed;
}

Dictionary SandboxGridNode::process_physics(Dictionary state, int width, int height, int frame_count) {
	PackedInt32Array cells = state["cells"];
	PackedInt64Array tags_array = state["tags_array"];
	
	int32_t* cells_ptr = cells.ptrw();
	int64_t* tags_ptr = tags_array.ptrw();
	
	bool sweep_reverse_base = (frame_count % 2 == 0);

	// Process from bottom to top
	for (int y = height - 1; y >= 0; y--) {
		int row_idx = y * width;
		bool sweep_reverse = (sweep_reverse_base != (y % 2 == 0));

		for (int xi = 0; xi < width; xi++) {
			int x = sweep_reverse ? (width - 1 - xi) : xi;
			int idx = row_idx + x;
			
			int32_t raw_id = cells_ptr[idx];
			int32_t pure_id = raw_id & 0xFFFF;
			
			if (pure_id == 0) continue;
			
			uint64_t t = tags_ptr[idx];
			
			if (!(t & GRAV_UP) && !(t & GRAV_STATIC)) {
				// GRAV_SLOW check
				if ((t & GRAV_SLOW) && (fast_rand() % 100 > 30)) {
					continue; // 70% chance to not move
				}
				
				// Falling physics
				int ny = y + 1;
				if (ny < height) {
					int n_idx = row_idx + width + x;
					if ((cells_ptr[n_idx] & 0xFFFF) == 0) {
						// Fall down
						cells_ptr[idx] = 0;
						tags_ptr[idx] = 0;
						cells_ptr[n_idx] = raw_id;
						tags_ptr[n_idx] = t;
					}
					else if (t & LIQUID) {
						if ((fast_rand() % 100) > 75) { // Slower spread (25% chance) to reduce high-speed flickering/jitter
							// Spread left/right
							int side = (fast_rand() % 2 == 0) ? 1 : -1;
							int side_idx = idx + side;
							if (x + side >= 0 && x + side < width && (cells_ptr[side_idx] & 0xFFFF) == 0) {
								cells_ptr[idx] = 0;
								tags_ptr[idx] = 0;
								cells_ptr[side_idx] = raw_id;
								tags_ptr[side_idx] = t;
								// Prevent horizontal teleportation
								if (!sweep_reverse && side == 1) xi++;
								else if (sweep_reverse && side == -1) xi++;
							} else if (x - side >= 0 && x - side < width && (cells_ptr[idx - side] & 0xFFFF) == 0) {
								cells_ptr[idx] = 0;
								tags_ptr[idx] = 0;
								cells_ptr[idx - side] = raw_id;
								tags_ptr[idx - side] = t;
								// Prevent horizontal teleportation
								if (!sweep_reverse && side == -1) xi++;
								else if (sweep_reverse && side == 1) xi++;
							}
						}
					}
					else if (t & POWDER) {
						// Diagonal fall (only check ONE random side per frame to create organic ruggedness)
						int side = (fast_rand() % 2 == 0) ? 1 : -1;
						int side_idx = n_idx + side;
						if (x + side >= 0 && x + side < width && (cells_ptr[side_idx] & 0xFFFF) == 0) {
							cells_ptr[idx] = 0;
							tags_ptr[idx] = 0;
							cells_ptr[side_idx] = raw_id;
							tags_ptr[side_idx] = t;
						}
					}
				}
			}
		}
	}

	state["cells"] = cells;
	state["tags_array"] = tags_array;
	return state;
}
