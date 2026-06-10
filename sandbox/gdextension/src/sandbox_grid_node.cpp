#include "sandbox_grid_node.h"
#include <cstdlib>

using namespace godot;

void SandboxGridNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("process_physics", "state", "width", "height", "frame_count"), &SandboxGridNode::process_physics);
	ClassDB::bind_method(D_METHOD("process_electricity", "state", "width", "height", "frame_count"), &SandboxGridNode::process_electricity);
	ClassDB::bind_method(D_METHOD("map_grid_data", "state", "dict", "grid_width", "grid_height"), &SandboxGridNode::map_grid_data);
	ClassDB::bind_method(D_METHOD("get_special_source_indices", "cells"), &SandboxGridNode::get_special_source_indices);
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
	int mat_tags_size = material_tags_raw.size();
	
	Array explosions_queue;
	
	// Helper lambda for setting cells
	auto set_cell = [&](int cx, int cy, int32_t cid) {
		int t_idx = cy * width + cx;
		uint64_t m_tags = (cid == 0 || cid >= mat_tags_size) ? 0 : mat_tags[cid];
		
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
	
	// Vector to track charged cells that moved during physics
	std::vector<int> moved_charges;
	moved_charges.reserve(100);

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
		
		if (temp_charge > 0) moved_charges.push_back(idx2);
		if (charge_ptr[idx1] > 0) moved_charges.push_back(idx1);
	};
	
	// Helper lambda for checking tag neighbors
	auto has_tag_neighbor = [&](int cx, int cy, uint64_t check_tag) -> bool {
		for (int ny = cy - 1; ny <= cy + 1; ny++) {
			for (int nx = cx - 1; nx <= cx + 1; nx++) {
				if (nx == cx && ny == cy) continue;
				if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
				int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
				if (nid > 0 && nid < mat_tags_size && (mat_tags[nid] & check_tag)) return true;
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
							// Do nothing to volcano elements directly in explosions
						} else if (t_id == 18) {
							set_cell(tx, ty, 19);
							charge_ptr[t_idx] = (20 + (fast_rand() % 30)) | flags;
							charge_visual_ptr[t_idx] = 160;
						} else {
							uint64_t m_tags = (t_id < mat_tags_size) ? mat_tags[t_id] : 0;
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
						if (flags & (128 | 1048576)) {
							// VOLCANO EFFECT (Push out materials)
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
						} else {
							// CLASSIC EFFECT (Just clear empty spaces organically)
							float prob = 1.0f - ((float)dist_sq / (float)radius_sq);
							if ((fast_rand() % 100) < (prob * 100.0f)) {
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
								uint64_t n_tags = (nid < mat_tags_size) ? mat_tags[nid] : 0;
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
								uint64_t n_tags = (nid < mat_tags_size) ? mat_tags[nid] : 0;
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

			// VOLCANO LOGIC (pure_id 27, 28, 29)
			if (pure_id == 27 || pure_id == 28 || pure_id == 29) {
				if (pure_id == 27) { // Static block
					if (has_tag_neighbor(x, y, INCENDIARY) || charge_ptr[idx] > 10) {
						if ((fast_rand() % 100) < 5) {
							set_cell(x, y, 29); // Transform to ACTIVE BASE
							charge_ptr[idx] = 80 + (fast_rand() % 71); // 80 to 150
						} else {
							charge_ptr[idx] += 1;
							if ((fast_rand() % 100) < 25) { // Spread heat (increased slightly)
								int nx = x + (fast_rand() % 3) - 1;
								int ny = y + (fast_rand() % 3) - 1;
								if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
									if ((cells_ptr[ny * width + nx] & 0xFFFF) == 27) {
										charge_ptr[ny * width + nx] += 10;
									}
								}
							}
						}
					}
				} else if (pure_id == 29) { // Erupting Base
					charge_ptr[idx] -= 1;
					int current_charge = charge_ptr[idx];
					
					if ((fast_rand() % 100) < 25) { // Spread heat while erupting so the chain doesn't stop
						int nx = x + (fast_rand() % 3) - 1;
						int ny = y + (fast_rand() % 3) - 1;
						if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
							if ((cells_ptr[ny * width + nx] & 0xFFFF) == 27) {
								charge_ptr[ny * width + nx] += 10;
							}
						}
					}
					
					if (current_charge % 35 == 0 && current_charge > 0) { // Slightly fewer rockets to reduce congestion
						int tx = x + (fast_rand() % 3) - 1;
						int ny = y - 1;
						if (tx >= 0 && tx < width && ny >= 0 && ny < height) {
							int n_id = cells_ptr[ny * width + tx] & 0xFFFF;
							if (n_id != 13 && n_id != 26 && n_id != 5) {
								int shot_count = current_charge / 35;
								String sfx = (shot_count % 2 != 0) ? String("volcan_burst") : String("");
								
								// Push plug explosion
								Array expl; expl.push_back(x); expl.push_back(ny); expl.push_back(2);
								expl.push_back(sfx); expl.push_back(1048576); expl.push_back(false);
								explosions_queue.push_back(expl);
								execute_explosion(x, ny, 2, 1048576); // Actually do it in C++
								
								set_cell(tx, ny, 28);
								// More fuel for rockets so they break through the mountain
								charge_ptr[ny * width + tx] = -(150 + (fast_rand() % 100));
							}
						}
					}
					
					if ((fast_rand() % 100) < 30) { // Smoke
						int sx = x + (fast_rand() % 5) - 2;
						int sy = y - 1;
						if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
							if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) set_cell(sx, sy, 15);
						}
					}
					
					if ((fast_rand() % 100) < 15) { // Lava leak
						int lx = x + (fast_rand() % 5) - 2;
						int ly = y - 1;
						if (lx >= 0 && lx < width && ly >= 0 && ly < height) {
							if ((cells_ptr[ly * width + lx] & 0xFFFF) == 0) set_cell(lx, ly, 11);
						}
					}
					
					if (current_charge <= 0) {
						if ((fast_rand() % 100) < 20) {
							Array expl; expl.push_back(x); expl.push_back(y); expl.push_back(10);
							expl.push_back(String("volcan_burst")); expl.push_back(1048576); expl.push_back(false);
							explosions_queue.push_back(expl);
							set_cell(x, y, 0);
							execute_explosion(x, y, 10, 1048576);
						} else {
							set_cell(x, y, 0); // Just vanish quietly
						}
						
						// Burnout cluster (generate lava AFTER explosion so it survives)
						for(int dy = -5; dy <= 5; dy++) {
							for(int dx = -5; dx <= 5; dx++) {
								if (dx*dx + dy*dy <= 25) {
									int cx = x + dx; int cy = y + dy;
									if (cx >= 0 && cx < width && cy >= 0 && cy < height) {
										int cnid = cells_ptr[cy * width + cx] & 0xFFFF;
										if (cnid == 0 || cnid == 27 || cnid == 29) {
											set_cell(cx, cy, 11);
										}
									}
								}
							}
						}
						destroyed = true;
					}
				} else if (pure_id == 28) { // Ascending projectile
					int current_fuel = charge_ptr[idx];
					if (current_fuel < 0) { // Moved here this frame
						charge_ptr[idx] = -current_fuel; // Make positive for next frame
						goto interaction_done;
					}
					
					if (current_fuel <= 0) {
						for(int dy = -6; dy <= 6; dy++) {
							for(int dx = -6; dx <= 6; dx++) {
								int cx = x + dx; int cy = y + dy;
								if (cx >= 0 && cx < width && cy >= 0 && cy < height) {
									int cnid = cells_ptr[cy * width + cx] & 0xFFFF;
									if (cnid == 0 || cnid == 27 || cnid == 29) {
										if (dx*dx + dy*dy <= 16) set_cell(cx, cy, 15);
										else if (dx*dx + dy*dy <= 36) set_cell(cx, cy, 11);
									}
								}
							}
						}
						Array expl; expl.push_back(x); expl.push_back(y); expl.push_back(12);
						expl.push_back(String("volcan_burst")); expl.push_back(1048576); expl.push_back(false);
						explosions_queue.push_back(expl);
						set_cell(x, y, 0);
						execute_explosion(x, y, 12, 1048576);
						destroyed = true; goto interaction_done;
					}
					
					if (y < 5) {
						set_cell(x, y, 11);
						Array expl; expl.push_back(x); expl.push_back(y); expl.push_back(6);
						expl.push_back(String("volcan_burst")); expl.push_back(1048576); expl.push_back(false);
						explosions_queue.push_back(expl);
						execute_explosion(x, y, 6, 1048576);
						destroyed = true; goto interaction_done;
					}
					
					int dxs[5] = {0, -1, 1, -1, 1};
					int dys[5] = {-1, -1, -1, 0, 0};
					bool moved = false;
					
					for(int d=0; d<5; d++) {
						int tx = x + dxs[d];
						int ty = y + dys[d];
						if (tx >= 0 && tx < width && ty >= 0 && ty < height) {
							int nid = cells_ptr[ty * width + tx] & 0xFFFF;
							if (nid == 28) continue;
							
							uint64_t n_tags = (nid > 0) ? mat_tags[nid] : 0;
							if (nid == 0 || !(n_tags & (1ULL << 43))) { // INVINCIBLE
								bool is_solid = (nid > 0 && nid != 11 && nid != 15 && nid != 3 && nid != 9 && nid != 27 && nid != 29);
								if (is_solid) {
									int break_chance = (dys[d] < 0) ? 2 : 1;
									if ((fast_rand() % 100) >= break_chance) {
										continue; // Just try next direction, don't lose fuel per bump!
									}
									current_fuel -= 5;
									for(int cdy = -1; cdy <= 1; cdy++) {
										for(int cdx = -1; cdx <= 1; cdx++) {
											int cx = tx + cdx; int cy = ty + cdy;
											if (cx >= 0 && cx < width && cy >= 0 && cy < height) {
												int cid = cells_ptr[cy * width + cx] & 0xFFFF;
												if (cid > 0 && cid != 28) {
													uint64_t c_tags = mat_tags[cid];
													if (!(c_tags & (1ULL << 43))) { // 1ULL << 43 is INVINCIBLE
														int r = fast_rand() % 100;
														if (r < 30) set_cell(cx, cy, 11);
														else if (r < 50 && current_fuel < 60) set_cell(cx, cy, 15);
														else set_cell(cx, cy, 0);
													}
												}
											}
										}
									}
								}
								
								int trail_id = 11;
								if (current_fuel < 60 && (fast_rand() % 100) < 20) trail_id = 15;
								set_cell(x, y, trail_id);
								
								set_cell(tx, ty, 28);
								// Negative if moving up, so it doesn't get processed again this frame
								int new_fuel = current_fuel - 1;
								charge_ptr[ty * width + tx] = (ty < y) ? -new_fuel : new_fuel;
								moved = true;
								destroyed = true;
								break;
							}
						}
					}
					
					if (!moved) {
						current_fuel -= 1;
						charge_ptr[idx] = current_fuel;
						if (current_fuel < 60 && current_fuel > 5 && (current_fuel % 20 == 0)) {
							if ((fast_rand() % 100) < 15) {
								for(int dy = -10; dy <= 10; dy++) {
									for(int dx = -10; dx <= 10; dx++) {
										int cx = x + dx; int cy = y + dy;
										if (cx >= 0 && cx < width && cy >= 0 && cy < height && dx*dx + dy*dy <= 100) {
											if ((cells_ptr[cy * width + cx] & 0xFFFF) == 0) set_cell(cx, cy, 11);
										}
									}
								}
								Array expl; expl.push_back(x); expl.push_back(y); expl.push_back(18);
								expl.push_back(String("volcan_burst")); expl.push_back(1048576); expl.push_back(false);
								explosions_queue.push_back(expl);
								set_cell(x, y, 0);
								execute_explosion(x, y, 18, 1048576);
								destroyed = true; goto interaction_done;
							}
						}
					}
				}
				
				if (destroyed) goto interaction_done;
				// Do not process generic explosive timer or flammable for Volcano blocks
				goto interaction_done; 
			}			// EXPLOSIVE IGNITION (Fire, Acid)
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
	
	PackedInt32Array out_moved_charges;
	out_moved_charges.resize(moved_charges.size());
	int32_t* moved_ptr = out_moved_charges.ptrw();
	for (int i = 0; i < moved_charges.size(); ++i) {
		moved_ptr[i] = moved_charges[i];
	}
	state["moved_charges"] = out_moved_charges;
	
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
		int idx = int(phase_blocks_indices[i]);
		if (idx >= 0 && idx < width * height) is_pb[idx] = true;
	}
	
	// Prev charges fast lookup (for LED rainbow pulsing)
	std::vector<bool> prev_charges(width * height, false);
	for (int i = 0; i < prev_charges_arr.size(); ++i) {
		int idx = int(prev_charges_arr[i]);
		if (idx >= 0 && idx < width * height) prev_charges[idx] = true;
	}
	
	std::vector<bool> prev_music(width * height, false);
	for (int i = 0; i < prev_active_music_charges_arr.size(); ++i) {
		int idx = int(prev_active_music_charges_arr[i]);
		if (idx >= 0 && idx < width * height) prev_music[idx] = true;
	}
	
	// Fast lookup to prevent duplicates
	std::vector<bool> in_active(width * height, false);
	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = int(active_charge_indices[i]);
		if (idx >= 0 && idx < width * height) in_active[idx] = true;
	}

	// Initialize sources to 100
	for (int i = 0; i < sources_indices.size(); ++i) {
		int idx = sources_indices[i];
		if (idx < 0 || idx >= width * height) continue;
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
	queue_x.reserve(32768);
	queue_y.reserve(32768);
	
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
		if (idx < 0 || idx >= width * height) continue;
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
		if (idx < 0 || idx >= width * height) continue;
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
		if (idx < 0 || idx >= width * height) continue;
		if (charge_ptr[idx] == 0) {
			charge_visual_ptr[idx] = 0;
		}
	}
	
	// Create GDScript-friendly array
	PackedInt32Array out_active_charges;
	out_active_charges.resize(new_active_charges.size());
	int32_t* out_ptr = out_active_charges.ptrw();
	for (int i = 0; i < new_active_charges.size(); ++i) {
		out_ptr[i] = new_active_charges[i];
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

Dictionary SandboxGridNode::map_grid_data(Dictionary state, Dictionary dict, int grid_width, int grid_height) {
	PackedInt32Array cells = state["cells"];
	PackedInt64Array tags_array = state["tags_array"];
	PackedInt32Array charge_array = state["charge_array"];
	PackedInt32Array cell_paint_colors = state["cell_paint_colors"];
	PackedByteArray charge_visual_buffer = state["charge_visual_buffer"];
	PackedByteArray chunks_active = state["chunks_active"];
	int chunks_x = state["chunks_x"];
	int chunks_y = state["chunks_y"];
	
	int32_t* cells_ptr = cells.ptrw();
	int64_t* tags_ptr = tags_array.ptrw();
	int32_t* charge_ptr = charge_array.ptrw();
	int32_t* cell_paint_ptr = cell_paint_colors.ptrw();
	uint8_t* charge_visual_ptr = charge_visual_buffer.ptrw();
	uint8_t* chunks_active_ptr = chunks_active.ptrw();
	
	int old_w = dict["width"];
	int old_h = dict["height"];
	int y_offset = old_h - grid_height;
	y_offset = (int)floor((float)y_offset / 4.0f) * 4;
	int x_offset = (old_w - grid_width) / 2;
	x_offset = (int)floor((float)x_offset / 4.0f) * 4;
	
	PackedInt32Array old_cells = dict["grid"];
	PackedInt32Array old_charge = dict["charge"];
	PackedInt64Array old_tags = dict["tags"];
	PackedInt32Array old_paint = dict["cell_paint"];
	
	const int32_t* old_cells_ptr = old_cells.ptr();
	const int32_t* old_charge_ptr = old_charge.ptr();
	const int64_t* old_tags_ptr = old_tags.ptr();
	const int32_t* old_paint_ptr = old_paint.ptr();
	
	std::vector<int> next_charge_indices;
	std::vector<int> active_metronome_indices;
	
	auto activate_chunk = [&](int x, int y) {
		int cx = x / 8;
		int cy = y / 8;
		if (cx >= 0 && cx < chunks_x && cy >= 0 && cy < chunks_y) {
			chunks_active_ptr[cy * chunks_x + cx] = 60;
		}
	};
	
	for (int new_y = 0; new_y < grid_height; ++new_y) {
		int old_y = new_y + y_offset;
		if (old_y < 0 || old_y >= old_h) continue;
		
		for (int new_x = 0; new_x < grid_width; ++new_x) {
			int old_x = new_x + x_offset;
			if (old_x < 0 || old_x >= old_w) continue;
			
			int old_idx = old_y * old_w + old_x;
			int new_idx = new_y * grid_width + new_x;
			
			int32_t c_val = old_cells_ptr[old_idx];
			int32_t charge_val = old_charge_ptr[old_idx];
			uint64_t tags = old_tags_ptr[old_idx];
			
			cells_ptr[new_idx] = c_val;
			charge_ptr[new_idx] = charge_val;
			tags_ptr[new_idx] = tags;
			cell_paint_ptr[new_idx] = old_paint_ptr[old_idx];
			
			if (charge_val > 0) {
				next_charge_indices.push_back(new_idx);
				charge_visual_ptr[new_idx] = (charge_val > 255) ? 255 : charge_val;
			}
			
			if (c_val != 0) {
				int32_t pure_id = c_val & 0xFFFF;
				if (pure_id == 600) {
					active_metronome_indices.push_back(new_idx);
				}
				
				// Smart chunk activation: only activate if it's dynamic
				if (charge_val > 0 || pure_id == 600 || pure_id == 27 || pure_id == 28 || pure_id == 29 ||
					(tags & (LIQUID | GAS | POWDER | ELECTRICITY | VOLATILE | BURN_SMOKE | BURN_COAL | VIRUS | RADIOACTIVE | VORTEX | EXP_ACID | EXP_WATER | EXP_LAVA | EXP_GAS | EXP_PINATA))) {
					activate_chunk(new_x, new_y);
				}
			}
		}
	}
	
	PackedInt32Array out_next_charge;
	out_next_charge.resize(next_charge_indices.size());
	int32_t* next_ptr = out_next_charge.ptrw();
	for (size_t i = 0; i < next_charge_indices.size(); ++i) {
		next_ptr[i] = next_charge_indices[i];
	}
	
	PackedInt32Array out_metronomes;
	out_metronomes.resize(active_metronome_indices.size());
	int32_t* metro_ptr = out_metronomes.ptrw();
	for (size_t i = 0; i < active_metronome_indices.size(); ++i) {
		metro_ptr[i] = active_metronome_indices[i];
	}
	
	state["cells"] = cells;
	state["charge_array"] = charge_array;
	state["tags_array"] = tags_array;
	state["cell_paint_colors"] = cell_paint_colors;
	state["charge_visual_buffer"] = charge_visual_buffer;
	state["chunks_active"] = chunks_active;
	state["next_charge_indices"] = out_next_charge;
	state["active_metronome_indices"] = out_metronomes;
	
	return state;
}

PackedInt32Array SandboxGridNode::get_special_source_indices(PackedInt32Array cells) {
	std::vector<int> special_indices;
	int size = cells.size();
	const int32_t* ptr = cells.ptr();
	for (int i = 0; i < size; ++i) {
		int32_t mid = ptr[i] & 0xFFFF;
		if (mid == 88 || mid == 9 || mid == 600 || mid == 91 || mid == 92 || 
		    mid == 93 || mid == 94 || mid == 194 || mid == 294 || mid == 394 ||
		    mid == 95 || mid == 195 || mid == 295 || mid == 395 || mid == 495 || mid == 595 || mid == 695 || mid == 795) {
			special_indices.push_back(i);
		}
	}
	PackedInt32Array out;
	out.resize(special_indices.size());
	int32_t* out_ptr = out.ptrw();
	for (size_t i = 0; i < special_indices.size(); ++i) {
		out_ptr[i] = special_indices[i];
	}
	return out;
}
