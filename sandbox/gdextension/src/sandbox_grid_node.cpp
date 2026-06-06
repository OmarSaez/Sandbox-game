#include "sandbox_grid_node.h"
#include <cstdlib>

using namespace godot;

void SandboxGridNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("process_physics", "state", "width", "height", "frame_count"), &SandboxGridNode::process_physics);
	ClassDB::bind_method(D_METHOD("process_electricity", "state", "width", "height", "frame_count"), &SandboxGridNode::process_electricity);
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
	PackedByteArray charge_visual_buffer = state["charge_visual_buffer"];
	
	int32_t* cells_ptr = cells.ptrw();
	int64_t* tags_ptr = tags_array.ptrw();
	int32_t* charge_ptr = charge_array.ptrw();
	uint8_t* charge_visual_ptr = charge_visual_buffer.ptrw();
	const int64_t* mat_tags = material_tags_raw.ptr();
	
	Array explosions_queue;
	
	// Helper lambda for setting cells
	auto set_cell = [&](int cx, int cy, int32_t cid) {
		int t_idx = cy * width + cx;
		uint64_t m_tags = (cid == 0) ? 0 : mat_tags[cid];
		
		int variant = 0;
		if (cid > 0 && (m_tags & ((1ULL << 25) | (1ULL << 26)))) { // TEXTURE_DOUBLE | TEXTURE_TRIPLE
			int mix_prob = 35; // Default MIX_MEDIUM
			if (m_tags & (1ULL << 27)) mix_prob = 15; // MIX_LOW
			else if (m_tags & (1ULL << 29)) mix_prob = 55; // MIX_HIGH
			
			if ((fast_rand() % 100) < mix_prob) {
				variant = 1;
				if ((m_tags & (1ULL << 26)) && (fast_rand() % 100) < 35) {
					variant = 2;
				}
			}
		}
		
		cells_ptr[t_idx] = (cid == 0) ? 0 : (cid | (variant << 24));
		tags_ptr[t_idx] = m_tags;
		if (cid == 0) {
			charge_ptr[t_idx] = 0;
			charge_visual_ptr[t_idx] = 0;
		}
	};
	
	// Helper lambda for swapping cells
	auto swap_cells = [&](int cx1, int cy1, int cx2, int cy2) {
		int idx1 = cy1 * width + cx1;
		int idx2 = cy2 * width + cx2;
		
		int32_t temp_c = cells_ptr[idx1];
		uint64_t temp_t = tags_ptr[idx1];
		int32_t temp_charge = charge_ptr[idx1];
		uint8_t temp_cv = charge_visual_ptr[idx1];
		
		cells_ptr[idx1] = cells_ptr[idx2];
		tags_ptr[idx1] = tags_ptr[idx2];
		charge_ptr[idx1] = charge_ptr[idx2];
		charge_visual_ptr[idx1] = charge_visual_ptr[idx2];
		
		cells_ptr[idx2] = temp_c;
		tags_ptr[idx2] = temp_t;
		charge_ptr[idx2] = temp_charge;
		charge_visual_ptr[idx2] = temp_cv;
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

	// Helper lambda for explosions
	auto execute_explosion = [&](int ex, int ey, int radius, int flags) {
		bool is_heavy_load = explosions_queue.size() > 10;
		int radius_sq = radius * radius;
		for (int ry = -radius; ry <= radius; ry++) {
			for (int rx = -radius; rx <= radius; rx++) {
				int dist_sq = rx * rx + ry * ry;
				if (dist_sq <= radius_sq) {
					int tx = ex + rx;
					int ty = ey + ry;
					if (tx < 0 || tx >= width || ty < 0 || ty >= height) continue;
					
					int t_idx = ty * width + tx;
					int32_t raw_id = cells_ptr[t_idx];
					int32_t t_id = raw_id & 0xFFFF;
					if (t_id <= 0) continue;
					
					uint64_t t_tags = tags_ptr[t_idx];
					if (t_tags & INVINCIBLE) continue;
					
					if (t_tags & EXPLOSIVE) {
						if (t_id == 7 || t_id == 71 || t_id == 72 || t_id == 77 || t_id == 19) continue;
						
						if (t_id == 27 || t_id == 28 || t_id == 29) {
							if (t_id == 27) {
								set_cell(tx, ty, 29);
								charge_ptr[t_idx] = 80 + (fast_rand() % 70);
								charge_visual_ptr[t_idx] = 160;
							}
						} else if (t_id == 18) {
							set_cell(tx, ty, 19);
							charge_ptr[t_idx] = (20 + (fast_rand() % 30)) | flags;
							charge_visual_ptr[t_idx] = 160;
						} else {
							uint64_t m_tags = mat_tags[t_id];
							int ign_flags = 0;
							if (t_id == 5 || t_id == 20) {
								ign_flags = flags;
							} else {
								if (m_tags & (1ULL << 31)) ign_flags |= 64;
								if (m_tags & (1ULL << 21)) ign_flags |= 128;
								if (m_tags & (1ULL << 32)) ign_flags |= 256;
								if (m_tags & (1ULL << 33)) ign_flags |= 512;
								if (m_tags & (1ULL << 34)) ign_flags |= 1024;
								if (m_tags & (1ULL << 35)) ign_flags |= 2048;
								if (m_tags & (1ULL << 36)) ign_flags |= 4096;
								if (m_tags & (1ULL << 37)) ign_flags |= 8192;
								if (m_tags & (1ULL << 38)) ign_flags |= 16384;
								if (m_tags & (1ULL << 39)) ign_flags |= 32768;
								if (m_tags & (1ULL << 40)) ign_flags |= 65536;
								if (m_tags & (1ULL << 45)) ign_flags |= 131072;
								if (m_tags & (1ULL << 46)) ign_flags |= 262144;
								if (m_tags & (1ULL << 47)) ign_flags |= 524288;
							}
							set_cell(tx, ty, (t_id == 5) ? 7 : 71);
							charge_ptr[t_idx] = (25 + (fast_rand() % 20)) | ign_flags;
							charge_visual_ptr[t_idx] = 160;
						}
						continue;
					}
					
					if (t_tags & ANTI_EXPLOSIVE) continue;
					
					if (dist_sq < (radius * 0.4f) * (radius * 0.4f)) {
						set_cell(tx, ty, 0);
					} else {
						float prob = 0.5f - ((float)dist_sq / (float)radius_sq) * 0.5f;
						if ((fast_rand() % 100) < (prob * 100.0f)) {
							float push_dist = 1.0f + (fast_rand() % 400) / 100.0f;
							float len = sqrt((float)rx*rx + (float)ry*ry);
							if (len == 0) len = 1;
							int nx = tx + (int)(rx * push_dist / len);
							int ny = ty + (int)(ry * push_dist / len);
							if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
								if ((cells_ptr[ny * width + nx] & 0xFFFF) == 0) swap_cells(tx, ty, nx, ny);
								else set_cell(tx, ty, 0);
							} else {
								set_cell(tx, ty, 0);
							}
						}
					}
				}
			}
		}
		
		if (flags & 128) {
			int count = is_heavy_load ? 15 : 30;
			for(int i=0; i<count; i++) {
				int dist = 2 + (fast_rand() % 5);
				float ang = (fast_rand() % 6283) / 1000.0f;
				int sx = ex + (int)(cos(ang) * dist);
				int sy = ey + (int)(sin(ang) * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) {
						set_cell(sx, sy, 43);
						int deg = (int)(ang * 180.0f / 3.14159f);
						if (deg < 0) deg += 360;
						int dir_idx = (int)((deg + 112.5f) / 45.0f) % 8;
						charge_ptr[sy * width + sx] = ((60 + (fast_rand() % 40)) << 3) | dir_idx;
					}
				}
			}
		}
		if (flags & 64) {
			int count = is_heavy_load ? 20 : 45;
			for(int i=0; i<count; i++) {
				int dist = 2 + (fast_rand() % 7);
				float ang = (fast_rand() % 6283) / 1000.0f;
				int sx = ex + (int)(cos(ang) * dist);
				int sy = ey + (int)(sin(ang) * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) {
						set_cell(sx, sy, 44);
						int deg = (int)(ang * 180.0f / 3.14159f);
						if (deg < 0) deg += 360;
						int dir_idx = (int)((deg + 112.5f) / 45.0f) % 8;
						charge_ptr[sy * width + sx] = ((30 + (fast_rand() % 30)) << 3) | dir_idx;
					}
				}
			}
		}
		if (flags & 256) {
			int count = is_heavy_load ? 50 : 120;
			for(int i=0; i<count; i++) {
				float dist = radius * 0.45f + (fast_rand() % 200) / 100.0f;
				float ang = (fast_rand() % 6283) / 1000.0f;
				int sx = ex + (int)(cos(ang) * dist);
				int sy = ey + (int)(sin(ang) * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) set_cell(sx, sy, 2);
				}
			}
		}
		if (flags & 512) {
			int count = is_heavy_load ? 35 : 80;
			for(int i=0; i<count; i++) {
				float dist = radius * 0.45f + (fast_rand() % 300) / 100.0f;
				float ang = (fast_rand() % 6283) / 1000.0f;
				int sx = ex + (int)(cos(ang) * dist);
				int sy = ey + (int)(sin(ang) * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) set_cell(sx, sy, 11);
				}
			}
		}
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

			// EXPLOSIVE IGNITION (Fire, Acid)
			if ((t & EXPLOSIVE) && charge_ptr[idx] == 0) {
				if (has_tag_neighbor(x, y, INCENDIARY) || has_tag_neighbor(x, y, ACID)) {
					int32_t flags = 0;
					if (has_tag_neighbor(x, y, ACID)) flags |= 64; // EXP_ACID
					// Normal fire/incendiary just gets 0 flags (normal explosion)
					charge_ptr[idx] = (25 + (fast_rand() % 20)) | flags;
					charge_visual_ptr[idx] = 160;
				}
			}
			
			// EXPLOSIVE TIMER (Any Primed Explosive)
			if ((t & EXPLOSIVE) && charge_ptr[idx] > 0) {
				int32_t charge = charge_ptr[idx];
				int32_t timer = charge & 63;
				int32_t flags = charge & 0xFFFFFFC0;
				bool is_gunpowder = (pure_id == 20 || pure_id == 71 || pure_id == 72);
				
				timer -= 1;
				if (timer <= 0) {
					Array expl;
					expl.push_back(x);
					expl.push_back(y);
					int radius = is_gunpowder ? 8 : 12;
					expl.push_back(radius);
					expl.push_back(String("explosion"));
					expl.push_back(flags);
					expl.push_back(is_gunpowder);
					explosions_queue.push_back(expl);
					set_cell(x, y, 0); // Clear pixel
					execute_explosion(x, y, radius, flags);
					destroyed = true;
					goto interaction_done;
				}
				
				charge_ptr[idx] = flags | timer;
				if (frame_count % 10 < 5) {
					charge_visual_ptr[idx] = 255;
				} else {
					charge_visual_ptr[idx] = (timer * 4 > 255) ? 255 : (timer * 4);
				}
			}

			// VOLATILE INERTIA (Sparks, projectiles)
			if ((t & VOLATILE)) {
				int32_t charge = charge_ptr[idx];
				int32_t energy = charge >> 3;
				int32_t dir_idx = charge & 7;
				
				if (energy <= 0) {
					set_cell(x, y, 0); destroyed = true; goto interaction_done;
				}
				
				int dxs[8] = {0, 1, 1, 1, 0, -1, -1, -1};
				int dys[8] = {-1, -1, 0, 1, 1, 1, 0, -1};
				int dx = dxs[dir_idx];
				int dy = dys[dir_idx];
				
				int nx = x + dx;
				int ny = y + dy;
				if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
					set_cell(x, y, 0); destroyed = true; goto interaction_done;
				}
				
				if ((cells_ptr[ny * width + nx] & 0xFFFF) == 0) {
					int new_energy = energy;
					if (frame_count % 2 == 0) new_energy -= 1;
					charge_ptr[idx] = (new_energy << 3) | dir_idx;
					swap_cells(x, y, nx, ny);
					destroyed = true; // Moved, don't process gravity this frame for this empty slot
					goto interaction_done;
				} else {
					if (pure_id == 44) set_cell(x, y, 13); // Acid projectile to liquid acid
					else set_cell(x, y, 0); // Vanish
					destroyed = true; goto interaction_done;
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
						swap_cells(x, y, x, ny);
					}
					else if (t & LIQUID) {
						if ((fast_rand() % 100) > 75) { // Slower spread (25% chance) to reduce high-speed flickering/jitter
							// Spread left/right
							int side = (fast_rand() % 2 == 0) ? 1 : -1;
							int side_idx = idx + side;
							if (x + side >= 0 && x + side < width && (cells_ptr[side_idx] & 0xFFFF) == 0) {
								swap_cells(x, y, x + side, y);
								// Prevent horizontal teleportation
								if (!sweep_reverse && side == 1) xi++;
								else if (sweep_reverse && side == -1) xi++;
							} else if (x - side >= 0 && x - side < width && (cells_ptr[idx - side] & 0xFFFF) == 0) {
								swap_cells(x, y, x - side, y);
								// Prevent horizontal teleportation
								if (!sweep_reverse && side == -1) xi++;
								else if (sweep_reverse && side == 1) xi++;
							}
						}
					}
					else if (t & POWDER) {
						// Diagonal fall (only check ONE random side per frame to create organic ruggedness)
						int side = (fast_rand() % 2 == 0) ? 1 : -1;
						int side_idx = (ny * width) + (x + side);
						if (x + side >= 0 && x + side < width && (cells_ptr[side_idx] & 0xFFFF) == 0) {
							swap_cells(x, y, x + side, ny);
						}
					}
				}
			}
		}
	}

	state["cells"] = cells;
	state["tags_array"] = tags_array;
	state["charge_array"] = charge_array;
	state["charge_visual_buffer"] = charge_visual_buffer;
	state["explosions"] = explosions_queue;
	return state;
}


Dictionary SandboxGridNode::process_electricity(Dictionary state, int width, int height, int frame_count) {
	PackedInt32Array cells = state["cells"];
	PackedInt64Array tags_array = state["tags_array"];
	PackedInt32Array charge_array = state["charge_array"];
	PackedByteArray charge_visual_buffer = state["charge_visual_buffer"];
	PackedInt32Array powered_frame = state["powered_frame"];
	PackedByteArray next_chunks_active = state["next_chunks_active"];
	
	Array active_charge_indices = state["active_charge_indices"];
	Array sources_indices = state["sources_indices"]; 
	Array phase_blocks_indices = state["phase_blocks_indices"];
	Array prev_charges_arr = state["prev_charges"];
	Array prev_active_music_charges_arr = state["prev_active_music_charges"];
	
	int32_t* cells_ptr = cells.ptrw();
	int64_t* tags_ptr = tags_array.ptrw();
	int32_t* charge_ptr = charge_array.ptrw();
	uint8_t* charge_visual_ptr = charge_visual_buffer.ptrw();
	int32_t* powered_frame_ptr = powered_frame.ptrw();
	uint8_t* chunks_active_ptr = next_chunks_active.ptrw();
	
	int chunks_x = width / 16;
	if (width % 16 != 0) chunks_x++;
	
	auto activate_chunk = [&](int cx, int cy) {
		int chunk_x = cx / 16;
		int chunk_y = cy / 16;
		int c_idx = chunk_y * chunks_x + chunk_x;
		if (c_idx >= 0 && c_idx < next_chunks_active.size() && chunks_active_ptr[c_idx] < 60) {
			chunks_active_ptr[c_idx] = 60;
		}
	};
	
	// Phase Blocks fast lookup
	std::vector<bool> is_pb(width * height, false);
	for (int i = 0; i < phase_blocks_indices.size(); ++i) {
		is_pb[int(phase_blocks_indices[i])] = true;
	}
	
	// Prev charges fast lookup (for LED rainbow pulsing)
	std::vector<bool> prev_charges(width * height, false);
	for (int i = 0; i < prev_charges_arr.size(); ++i) {
		prev_charges[int(prev_charges_arr[i])] = true;
	}
	
	std::vector<bool> prev_music(width * height, false);
	for (int i = 0; i < prev_active_music_charges_arr.size(); ++i) {
		prev_music[int(prev_active_music_charges_arr[i])] = true;
	}
	
	// Fast lookup to prevent duplicates
	std::vector<bool> in_active(width * height, false);
	for (int i = 0; i < active_charge_indices.size(); ++i) {
		in_active[int(active_charge_indices[i])] = true;
	}

	// Initialize sources to 100
	for (int i = 0; i < sources_indices.size(); ++i) {
		int idx = sources_indices[i];
		charge_ptr[idx] = 100;
		charge_visual_ptr[idx] = 100;
		if (!in_active[idx]) {
			active_charge_indices.append(idx);
			in_active[idx] = true;
		}
	}
	
	// BFS Queue
	std::vector<int> queue_x;
	std::vector<int> queue_y;
	queue_x.reserve(2000);
	queue_y.reserve(2000);
	
	for (int i = 0; i < sources_indices.size(); ++i) {
		int idx = sources_indices[i];
		int gy = idx / width;
		int gx = idx % width;
		queue_x.push_back(gx);
		queue_y.push_back(gy);
		powered_frame_ptr[idx] = frame_count;
	}
	
	// 3. BFS from constant sources
	int head = 0;
	while (head < queue_x.size()) {
		int cx = queue_x[head];
		int cy = queue_y[head];
		head++;
		
		for (int dy = -1; dy <= 1; ++dy) {
			int ny = cy + dy;
			if (ny < 0 || ny >= height) continue;
			int row_offset = ny * width;
			for (int dx = -1; dx <= 1; ++dx) {
				if (dx == 0 && dy == 0) continue;
				int nx = cx + dx;
				if (nx < 0 || nx >= width) continue;
				
				int n_idx = row_offset + nx;
				if (powered_frame_ptr[n_idx] == frame_count) continue;
				
				int32_t n_pid = cells_ptr[n_idx] & 0xFFFF;
				if (n_pid <= 0 && !is_pb[n_idx]) continue;
				
				if (n_pid >= 81 && n_pid <= 87) {
					int n_var = (cells_ptr[n_idx] >> 24) & 0xFF;
					if (n_var < 10) continue;
				}
				
				if (charge_ptr[n_idx] > 0) {
					powered_frame_ptr[n_idx] = frame_count;
					queue_x.push_back(nx);
					queue_y.push_back(ny);
				}
			}
		}
	}
	
	// 4. Perform propagation wave
	std::vector<int> new_active_charges;
	new_active_charges.reserve(active_charge_indices.size() + 1000);
	std::vector<int> wave_fronts;
	
	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		if (charge_ptr[idx] == 100) {
			wave_fronts.push_back(idx);
		}
	}
	
	static uint32_t rng_state = 123456789;
	auto fast_rand = [&]() -> uint32_t {
		rng_state ^= rng_state << 13;
		rng_state ^= rng_state >> 17;
		rng_state ^= rng_state << 5;
		return rng_state;
	};
	
	Array out_sparks;
	
	for (int i = 0; i < wave_fronts.size(); ++i) {
		int idx = wave_fronts[i];
		int y = idx / width;
		int x = idx % width;
		
		for (int dy = -1; dy <= 1; ++dy) {
			int ny = y + dy;
			if (ny < 0 || ny >= height) continue;
			int row_offset = ny * width;
			for (int dx = -1; dx <= 1; ++dx) {
				if (dx == 0 && dy == 0) continue;
				int nx = x + dx;
				if (nx < 0 || nx >= width) continue;
				
				int n_idx = row_offset + nx;
				if (charge_ptr[n_idx] == 0) {
					int32_t n_pid = cells_ptr[n_idx] & 0xFFFF;
					bool pb = is_pb[n_idx];
					if (n_pid <= 0 && !pb) continue;
					
					if (n_pid >= 81 && n_pid <= 87) {
						int n_var = (cells_ptr[n_idx] >> 24) & 0xFF;
						if (n_var < 10) continue;
					}
					
					uint64_t n_tags = tags_ptr[n_idx];
					if ((n_tags & EXPLOSIVE) && (n_tags & ELECTRIC_ACTIVATED)) {
						if (charge_ptr[n_idx] == 0) {
							charge_ptr[n_idx] = 40 | 128; // EXP_ELECTRIC
							charge_visual_ptr[n_idx] = 160;
						}
					} else if (pb || (n_tags & (CONDUCTOR | ELECTRIC_ACTIVATED))) {
						charge_ptr[n_idx] = 100;
						new_active_charges.push_back(n_idx);
						activate_chunk(nx, ny);
						
						if ((fast_rand() % 1000) < 10) { 
							out_sparks.append(Vector2(nx, ny));
						}
					}
				}
			}
		}
	}
	
	// 5. Apply decay
	int decay_rate = 20;
	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		int32_t mid = cells_ptr[idx] & 0xFFFF;
		
		if (mid == 7 || mid == 77 || mid == 71 || mid == 72 || mid == 19 || mid == 5 || mid == 20) {
			new_active_charges.push_back(idx);
			continue;
		}
		
		if (powered_frame_ptr[idx] == frame_count) {
			charge_ptr[idx] = 100;
			new_active_charges.push_back(idx);
		} else {
			int old_val = charge_ptr[idx];
			int next_val = (old_val - decay_rate > 0) ? (old_val - decay_rate) : 0;
			charge_ptr[idx] = next_val;
			if (next_val > 0) {
				new_active_charges.push_back(idx);
				int gy = idx / width;
				int gx = idx % width;
				activate_chunk(gx, gy);
			}
		}
	}
	
	// LED Rainbow & Visual Buffer
	Array out_music_notes;
	
	for (int i = 0; i < new_active_charges.size(); ++i) {
		int idx = new_active_charges[i];
		int32_t raw_val = cells_ptr[idx];
		int32_t mid = raw_val & 0xFFFF;
		
		// Visual buffer
		int c = charge_ptr[idx];
		charge_visual_ptr[idx] = (c < 0) ? 0 : (c > 255 ? 255 : c);
		
		// LED
		if (mid == 89) {
			int variant = (raw_val >> 24) & 0xFF;
			if ((variant & 8) != 0) {
				bool is_new_pulse = !prev_charges[idx];
				bool is_30_frames = (frame_count % 30 == 0);
				if (is_new_pulse || is_30_frames) {
					int current_color_idx = variant & 7;
					int next_color_idx = (current_color_idx + 1) % 7;
					int new_variant = 8 | next_color_idx;
					cells_ptr[idx] = 89 | (new_variant << 24);
					int gy = idx / width;
					int gx = idx % width;
					activate_chunk(gx, gy);
				}
			}
		}
		
		// Music
		uint64_t m_tags = tags_ptr[idx];
		if (m_tags & MUSIC) {
			int gy = idx / width;
			int gx = idx % width;
			if (gx % 2 == 0 && gy % 2 == 0) {
				if (!prev_music[idx]) {
					if (mid == 600) {
						out_music_notes.append(Vector2(5, 0));
					} else {
						int inst = (mid - 500) / 16;
						int note = (mid - 500) % 16;
						out_music_notes.append(Vector2(inst, note));
					}
				}
			}
		}
	}
	
	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		if (charge_ptr[idx] == 0) {
			charge_visual_ptr[idx] = 0;
		}
	}
	
	// Create GDScript-friendly array
	Array out_active_charges;
	for (int i = 0; i < new_active_charges.size(); ++i) {
		out_active_charges.append(new_active_charges[i]);
	}
	
	state["cells"] = cells;
	state["charge_array"] = charge_array;
	state["charge_visual_buffer"] = charge_visual_buffer;
	state["powered_frame"] = powered_frame;
	state["next_chunks_active"] = next_chunks_active;
	
	state["active_charge_indices"] = out_active_charges;
	state["out_sparks"] = out_sparks;
	state["out_music_notes"] = out_music_notes;
	return state;
}
