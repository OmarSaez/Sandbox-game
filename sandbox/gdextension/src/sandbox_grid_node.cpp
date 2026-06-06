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
	PackedInt32Array charge_array = state["charge_array"];
	PackedInt64Array material_tags_raw = state["material_tags_raw"];
	
	int32_t* cells_ptr = cells.ptrw();
	int64_t* tags_ptr = tags_array.ptrw();
	int32_t* charge_ptr = charge_array.ptrw();
	const int64_t* mat_tags = material_tags_raw.ptr();
	
	// Helper lambda for setting cells
	auto set_cell = [&](int cx, int cy, int32_t id) {
		int c_idx = cy * width + cx;
		cells_ptr[c_idx] = id;
		tags_ptr[c_idx] = (id == 0) ? 0 : mat_tags[id];
	};
	
	// Helper lambda for checking tag neighbors
	auto has_tag_neighbor = [&](int cx, int cy, uint64_t check_tag) -> bool {
		for (int ny = cy - 1; ny <= cy + 1; ny++) {
			for (int nx = cx - 1; nx <= cx + 1; nx++) {
				if (nx == cx && ny == cy) continue;
				if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
				int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
				if (nid > 0 && (mat_tags[nid] & check_tag)) return true;
			}
		}
		return false;
	};

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
			bool destroyed = false;
			
			// === INTERACTIONS (Phase 3: Fuego y Acido) ===
			
			// ACID
			if ((t & ACID)) {
				if ((fast_rand() % 100) < 20) { // 20% reaction speed
					for (int ny = y - 1; ny <= y + 1; ny++) {
						for (int nx = x - 1; nx <= x + 1; nx++) {
							if (nx == x && ny == y) continue;
							if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
							int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
							if (nid > 0 && nid != pure_id) {
								uint64_t n_tags = mat_tags[nid];
								if (!(n_tags & (ANTI_ACID | INVINCIBLE))) {
									set_cell(nx, ny, 44);
									if ((fast_rand() % 100) < 30) { set_cell(x, y, 0); destroyed = true; goto interaction_done; }
									if ((n_tags & SOLID) && (fast_rand() % 100) < 10) { set_cell(x, y, 0); destroyed = true; goto interaction_done; }
								}
							}
						}
					}
				}
			}
			
			// FIRE AND HEAT
			if ((t & INCENDIARY)) {
				if (pure_id == 3) { // Fire
					if ((fast_rand() % 100) < 10) { set_cell(x, y, 0); destroyed = true; goto interaction_done; }
				} else if (pure_id == 14) { // Coal burnout
					if ((fast_rand() % 1000) < 2) {
						set_cell(x, y, 0); destroyed = true;
						if (y > 0 && (cells_ptr[(y - 1) * width + x] & 0xFFFF) == 0) set_cell(x, y - 1, 15); // Smoke
						goto interaction_done;
					}
					if ((fast_rand() % 100) < 10 && y > 0 && (cells_ptr[(y - 1) * width + x] & 0xFFFF) == 0) {
						set_cell(x, y - 1, 3); // Emits fire up
					}
				}
				
				// Heat Reactions (Lava + Water = Obsidian)
				if ((fast_rand() % 100) < 50) {
					for (int ny = y - 1; ny <= y + 1; ny++) {
						for (int nx = x - 1; nx <= x + 1; nx++) {
							if (nx == x && ny == y) continue;
							if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
							int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
							if (nid > 0) {
								if ((pure_id == 11 && nid == 2) || (pure_id == 2 && nid == 11)) {
									set_cell(x, y, 12); set_cell(nx, ny, 12); destroyed = true; goto interaction_done; // Obsidian
								}
								uint64_t n_tags = mat_tags[nid];
								if ((n_tags & FLAMMABLE) && nid != 14) {
									if ((fast_rand() % 100) < 80) {
										if (nid == 18) { // TNT -> Primed TNT
											set_cell(nx, ny, 19); charge_ptr[ny * width + nx] = 20 + (fast_rand() % 50);
										} else if (n_tags & BURN_COAL) {
											set_cell(nx, ny, (fast_rand() % 2 == 0) ? 14 : 3);
										} else if (n_tags & BURN_SMOKE) {
											if (ny > 0 && (cells_ptr[(ny - 1) * width + nx] & 0xFFFF) == 0) set_cell(nx, ny - 1, 15);
											if ((fast_rand() % 100) < 10) set_cell(nx, ny, 3); else set_cell(nx, ny, 0);
										} else {
											set_cell(nx, ny, 3);
										}
									}
								} else if (n_tags & EXPLOSIVE) {
									if ((fast_rand() % 100) < 80) {
										if (nid == 27) { set_cell(nx, ny, 29); charge_ptr[ny * width + nx] = 80 + (fast_rand() % 40); }
										else if (nid == 18) { set_cell(nx, ny, 19); charge_ptr[ny * width + nx] = 20 + (fast_rand() % 50); }
									}
								}
							}
						}
					}
				}
			}
			
			// FLAMMABLE
			if ((t & FLAMMABLE)) {
				if (has_tag_neighbor(x, y, INCENDIARY) || charge_ptr[idx] > 50) {
					if (pure_id == 16) { // Wood
						if ((fast_rand() % 100) < 50) { set_cell(x, y, (fast_rand() % 2 == 0) ? 14 : 3); destroyed = true; goto interaction_done; }
					} else if (pure_id == 4) { // Petro
						if ((fast_rand() % 100) < 10) { set_cell(x, y, 3); destroyed = true; goto interaction_done; }
					}
				}
			}
			
			interaction_done:
			if (destroyed) continue;
			
			// Re-fetch in case interaction modified tags
			t = tags_ptr[idx];
			
			// === GRAVITY (Phase 2) ===
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
	state["charge_array"] = charge_array;
	return state;
}
