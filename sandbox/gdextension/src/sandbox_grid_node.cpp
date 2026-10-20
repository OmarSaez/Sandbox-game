#include "sandbox_grid_node.h"
#include <cstdlib>
#include <cmath>

using namespace godot;

static std::vector<int8_t> oval_16x8_dx;
static std::vector<int8_t> oval_16x8_dy;
static std::vector<int8_t> oval_20x10_dx;
static std::vector<int8_t> oval_20x10_dy;
static bool ovals_initialized = false;

static void init_oval_tables() {
	if (ovals_initialized) return;
	ovals_initialized = true;

	auto build_oval = [](int rx, int ry, int step, std::vector<int8_t>& out_dx, std::vector<int8_t>& out_dy) {
		float rx_sq = (float)(rx * rx);
		float ry_sq = (float)(ry * ry);
		for (int oy = -ry; oy <= ry; ++oy) {
			float oy_norm = (float)(oy * oy) / ry_sq;
			for (int ox = -rx; ox <= rx; ++ox) {
				if (((float)(ox * ox) / rx_sq + oy_norm) <= 1.0f) {
					int dist_sq = ox * ox + oy * oy;
					if (dist_sq <= 16 || ((std::abs(ox) % step == 0) && (std::abs(oy) % step == 0))) {
						out_dx.push_back((int8_t)ox);
						out_dy.push_back((int8_t)oy);
					}
				}
			}
		}
	};

	build_oval(16, 8, 4, oval_16x8_dx, oval_16x8_dy);
	build_oval(20, 10, 5, oval_20x10_dx, oval_20x10_dy);
}

void SandboxGridNode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("process_physics", "state", "width", "height", "frame_count"), &SandboxGridNode::process_physics);
	ClassDB::bind_method(D_METHOD("process_electricity", "state", "width", "height", "frame_count"), &SandboxGridNode::process_electricity);
	ClassDB::bind_method(D_METHOD("process_pistons", "active_pistons", "state", "width", "height", "delta"), &SandboxGridNode::process_pistons);
	ClassDB::bind_method(D_METHOD("map_grid_data", "state", "dict", "grid_width", "grid_height"), &SandboxGridNode::map_grid_data);
	ClassDB::bind_method(D_METHOD("get_special_source_indices", "cells"), &SandboxGridNode::get_special_source_indices);
}

SandboxGridNode::SandboxGridNode() {
	for (int i = 0; i < 256; ++i) {
		float ang = (float)i * (6.28318530718f / 256.0f);
		cos_lut_256[i] = cosf(ang);
		sin_lut_256[i] = sinf(ang);
	}
	init_oval_tables();
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
	PackedInt32Array cell_paint_colors = state["cell_paint_colors"];
	PackedByteArray chunks_active = state["chunks_active"];
	PackedByteArray next_chunks_active = state["next_chunks_active"];

	int chunks_x = state.get("chunks_x", (width + 15) / 16);
	int chunks_y = state.get("chunks_y", (height + 15) / 16);
	float view_zoom = state.get("view_zoom", 1.0f);
	float cam_min_x = state.get("cam_min_x", 0.0f);
	float cam_max_x = state.get("cam_max_x", (float)width);
	float cam_min_y = state.get("cam_min_y", 0.0f);
	float cam_max_y = state.get("cam_max_y", (float)height);
	int current_weather = state.get("current_weather", 0);
	int music_tempo_frames = state.get("music_tempo_frames", 30);
	if (music_tempo_frames <= 0) music_tempo_frames = 30;

	int32_t* cells_ptr = cells.ptrw();
	int64_t* tags_ptr = tags_array.ptrw();
	int32_t* charge_ptr = charge_array.ptrw();
	uint8_t* charge_visual_ptr = charge_visual_buffer.ptrw();
	int32_t* cell_paint_ptr = cell_paint_colors.ptrw();
	const int64_t* mat_tags = material_tags_raw.ptr();
	int mat_tags_size = material_tags_raw.size();
	const uint8_t* chunks_active_ptr = chunks_active.ptr();
	uint8_t* next_chunks_ptr = next_chunks_active.ptrw();
	int chunks_total = next_chunks_active.size();
	bool use_chunks = (chunks_active.size() >= chunks_x * chunks_y && chunks_total >= chunks_x * chunks_y);

	bool paint_changed = false;
	bool charge_changed = false;
	bool is_fire_active = false;
	bool is_volcano_active = false;
	bool fuse_burned = false;

	Array explosions_queue;
	Array launched_fireworks;
	Array vortex_npc_pulls;
	Array repel_npc_pushes;
	Array vortex_sparks;
	Array repel_sparks;
	Array heat_music_notes;

	// Vector to track charged cells that moved or were seeded during physics
	std::vector<int> moved_charges;
	moved_charges.reserve(128);

	auto get_tags_id = [](int32_t pure_id) -> int32_t {
		return (pure_id >= 1000) ? 7 : pure_id;
	};

	auto activate_chunk = [&](int gx, int gy) {
		if (!use_chunks) return;
		int cx = gx >> 4;
		int cy = gy >> 4;
		if (cx < 0 || cx >= chunks_x || cy < 0 || cy >= chunks_y) return;
		int c_idx = cy * chunks_x + cx;
		if (next_chunks_ptr[c_idx] == 61) return; // Already expanded neighbors this frame
		next_chunks_ptr[c_idx] = 61;
		int ny_min = (cy > 0) ? (cy - 1) : 0;
		int ny_max = (cy + 1 < chunks_y) ? (cy + 1) : (chunks_y - 1);
		int nx_min = (cx > 0) ? (cx - 1) : 0;
		int nx_max = (cx + 1 < chunks_x) ? (cx + 1) : (chunks_x - 1);
		for (int ny = ny_min; ny <= ny_max; ++ny) {
			int row_off = ny * chunks_x;
			for (int nx = nx_min; nx <= nx_max; ++nx) {
				if (next_chunks_ptr[row_off + nx] < 60) {
					next_chunks_ptr[row_off + nx] = 60;
				}
			}
		}
	};

	auto keep_chunk_awake = [&](int gx, int gy) {
		if (!use_chunks) return;
		int cx = gx >> 4;
		int cy = gy >> 4;
		if (cx >= 0 && cx < chunks_x && cy >= 0 && cy < chunks_y) {
			int c_idx = cy * chunks_x + cx;
			if (next_chunks_ptr[c_idx] < 15) {
				next_chunks_ptr[c_idx] = 15;
			}
		}
	};

	// Helper lambda for setting cells
	auto set_cell = [&](int cx, int cy, int32_t cid) {
		int t_idx = cy * width + cx;
		int32_t tags_id = get_tags_id(cid);
		uint64_t m_tags = (cid <= 0 || tags_id >= mat_tags_size) ? 0 : mat_tags[tags_id];

		int variant = 0;
		if (cid > 0 && (m_tags & ((1ULL << 25) | (1ULL << 26)))) { // TEXTURE_DOUBLE | TEXTURE_TRIPLE
			int mix_prob = 35; // Default MIX_MEDIUM
			if (m_tags & (1ULL << 27)) mix_prob = 15; // MIX_LOW
			else if (m_tags & (1ULL << 29)) mix_prob = 55; // MIX_HIGH

			if ((fast_rand() % 100) < (uint32_t)mix_prob) {
				variant = 1;
				if ((m_tags & (1ULL << 26)) && (fast_rand() % 100) < 35) {
					variant = 2;
				}
			}
		}

		cells_ptr[t_idx] = (cid == 0) ? 0 : (cid | (variant << 24));
		tags_ptr[t_idx] = m_tags;
		if (cell_paint_ptr[t_idx] != 0) {
			cell_paint_ptr[t_idx] = 0;
			paint_changed = true;
		}
		if (cid == 0) {
			if (charge_ptr[t_idx] != 0 || charge_visual_ptr[t_idx] != 0) {
				charge_ptr[t_idx] = 0;
				charge_visual_ptr[t_idx] = 0;
				charge_changed = true;
			}
		}
		activate_chunk(cx, cy);
	};

	auto is_electric_charge_carrier = [](int32_t pid, uint64_t tags) -> bool {
		if (pid == 19 || pid == 24 || pid == 25 || pid == 27 || pid == 28 || pid == 29 || pid == 43 || pid == 44) return false;
		if (tags & (VOLATILE | EXPLOSIVE)) return false;
		return true;
	};

	// Helper lambda for swapping cells (respecting camera zoom boundaries & moving paint)
	auto swap_cells = [&](int cx1, int cy1, int cx2, int cy2) -> bool {
		if (cx1 < 0 || cx1 >= width || cy1 < 0 || cy1 >= height || cx2 < 0 || cx2 >= width || cy2 < 0 || cy2 >= height) return false;
		if (view_zoom > 1.0f) {
			bool in_cam1 = (cx1 >= cam_min_x && cx1 < cam_max_x && cy1 >= cam_min_y && cy1 < cam_max_y);
			bool in_cam2 = (cx2 >= cam_min_x && cx2 < cam_max_x && cy2 >= cam_min_y && cy2 < cam_max_y);
			if (in_cam1 != in_cam2) return false;
		}

		int idx1 = cy1 * width + cx1;
		int idx2 = cy2 * width + cx2;

		int32_t temp_c = cells_ptr[idx1];
		uint64_t temp_t = tags_ptr[idx1];
		int32_t temp_charge = charge_ptr[idx1];
		uint8_t temp_cv = charge_visual_ptr[idx1];
		int32_t temp_paint = cell_paint_ptr[idx1];

		cells_ptr[idx1] = cells_ptr[idx2];
		tags_ptr[idx1] = tags_ptr[idx2];
		charge_ptr[idx1] = charge_ptr[idx2];
		charge_visual_ptr[idx1] = charge_visual_ptr[idx2];
		cell_paint_ptr[idx1] = cell_paint_ptr[idx2];

		cells_ptr[idx2] = temp_c;
		tags_ptr[idx2] = temp_t;
		charge_ptr[idx2] = temp_charge;
		charge_visual_ptr[idx2] = temp_cv;
		cell_paint_ptr[idx2] = temp_paint;

		if (temp_paint != 0 || cell_paint_ptr[idx1] != 0) {
			paint_changed = true;
		}

		if (temp_charge > 0) {
			charge_changed = true;
			if (is_electric_charge_carrier(temp_c & 0xFFFF, temp_t)) {
				moved_charges.push_back(idx2);
			}
		}
		if (charge_ptr[idx1] > 0) {
			charge_changed = true;
			if (is_electric_charge_carrier(cells_ptr[idx1] & 0xFFFF, tags_ptr[idx1])) {
				moved_charges.push_back(idx1);
			}
		}

		activate_chunk(cx1, cy1);
		activate_chunk(cx2, cy2);
		return true;
	};

	// Helper lambda for checking tag neighbors
	auto has_tag_neighbor = [&](int cx, int cy, uint64_t check_tag) -> bool {
		for (int ny = cy - 1; ny <= cy + 1; ny++) {
			if (ny < 0 || ny >= height) continue;
			int r_off = ny * width;
			for (int nx = cx - 1; nx <= cx + 1; nx++) {
				if (nx == cx && ny == cy) continue;
				if (nx < 0 || nx >= width) continue;
				int32_t nid = cells_ptr[r_off + nx] & 0xFFFF;
				if (nid > 0) {
					int32_t tid = get_tags_id(nid);
					if (tid < mat_tags_size && (mat_tags[tid] & check_tag)) return true;
				}
			}
		}
		return false;
	};

	auto count_neighbor_id = [&](int cx, int cy, int32_t target_id) -> int {
		int count = 0;
		for (int ny = cy - 1; ny <= cy + 1; ny++) {
			if (ny < 0 || ny >= height) continue;
			int r_off = ny * width;
			for (int nx = cx - 1; nx <= cx + 1; nx++) {
				if (nx == cx && ny == cy) continue;
				if (nx < 0 || nx >= width) continue;
				if ((cells_ptr[r_off + nx] & 0xFFFF) == target_id) count++;
			}
		}
		return count;
	};

	auto count_neighbor_id_radius = [&](int cx, int cy, int32_t target_id, int radius) -> int {
		int count = 0;
		for (int ny = cy - radius; ny <= cy + radius; ny++) {
			if (ny < 0 || ny >= height) continue;
			int r_off = ny * width;
			for (int nx = cx - radius; nx <= cx + radius; nx++) {
				if (nx == cx && ny == cy) continue;
				if (nx < 0 || nx >= width) continue;
				if ((cells_ptr[r_off + nx] & 0xFFFF) == target_id) count++;
			}
		}
		return count;
	};

	auto has_id_in_oval = [&](int cx, int cy, int32_t target_id, const std::vector<int8_t>& dxs, const std::vector<int8_t>& dys) -> bool {
		size_t count = dxs.size();
		for (size_t i = 0; i < count; ++i) {
			int nx = cx + dxs[i];
			int ny = cy + dys[i];
			if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
				if ((cells_ptr[ny * width + nx] & 0xFFFF) == target_id) return true;
			}
		}
		return false;
	};

	auto compute_lab_explosive_flags = [&](uint64_t m_tags) -> int {
		int ign_flags = 0;
		if (m_tags & EXP_ACID) ign_flags |= 64;
		if (m_tags & EXP_ELECTRIC) ign_flags |= 128;
		if (m_tags & EXP_WATER) ign_flags |= 256;
		if (m_tags & EXP_LAVA) ign_flags |= 512;
		if (m_tags & EXP_NPC) ign_flags |= 1024;
		if (m_tags & EXP_LIFE) ign_flags |= 2048;
		if (m_tags & EXP_GAS) ign_flags |= 131072;
		if (m_tags & EXP_QUAKE) ign_flags |= 262144;
		if (m_tags & EXP_PINATA) ign_flags |= 524288;

		if (m_tags & EXP_TEAM_RED) ign_flags |= 4096;
		else if (m_tags & EXP_TEAM_BLUE) ign_flags |= 8192;
		else if (m_tags & EXP_TEAM_GREEN) ign_flags |= 16384;
		else if (m_tags & EXP_TEAM_YELLOW) ign_flags |= 32768;

		if (m_tags & EXP_TEAM_MIXED) ign_flags |= 65536;
		return ign_flags;
	};

	auto prime_explosive = [&](int px, int py, int32_t pid, int manual_flags) {
		if (px < 0 || px >= width || py < 0 || py >= height) return;
		int p_idx = py * width + px;
		int32_t current_id = cells_ptr[p_idx] & 0xFFFF;
		if (charge_ptr[p_idx] > 0) return;
		if (current_id == 7 || current_id == 77 || current_id == 71 || current_id == 72) return;
		if (pid == 27 || pid == 28 || pid == 29) return;

		int32_t tid = get_tags_id(pid);
		uint64_t m_tags = (tid > 0 && tid < mat_tags_size) ? mat_tags[tid] : 0;
		if (m_tags & INVINCIBLE) return;

		int ign_flags = 0;
		if (pid == 5 || pid == 20) {
			if (manual_flags != -1) ign_flags = manual_flags;
		} else {
			ign_flags = compute_lab_explosive_flags(m_tags);
		}

		charge_ptr[p_idx] = (25 + (fast_rand() % 20)) | ign_flags;
		charge_visual_ptr[p_idx] = 160;
		charge_changed = true;
		activate_chunk(px, py);
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
							charge_changed = true;
						} else {
							int32_t tid = get_tags_id(t_id);
							uint64_t m_tags = (tid < mat_tags_size) ? mat_tags[tid] : 0;
							int ign_flags = (t_id == 5 || t_id == 20) ? flags : compute_lab_explosive_flags(m_tags);
							set_cell(tx, ty, (t_id == 5) ? 7 : 71);
							charge_ptr[t_idx] = (25 + (fast_rand() % 20)) | ign_flags;
							charge_visual_ptr[t_idx] = 160;
							charge_changed = true;
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
								float len = sqrtf((float)(rx * rx + ry * ry));
								if (len == 0.0f) len = 1.0f;
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
			for (int i = 0; i < count; i++) {
				int dist = 2 + (fast_rand() % 5);
				uint32_t lut_i = fast_rand() & 255;
				int sx = ex + (int)(cos_lut_256[lut_i] * dist);
				int sy = ey + (int)(sin_lut_256[lut_i] * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) {
						set_cell(sx, sy, 43);
						int deg = (int)((float)lut_i * (360.0f / 256.0f));
						int dir_idx = (int)((deg + 112.5f) / 45.0f) % 8;
						charge_ptr[sy * width + sx] = ((60 + (fast_rand() % 40)) << 3) | dir_idx;
					}
				}
			}
		}
		if (flags & 64) {
			int count = is_heavy_load ? 20 : 45;
			for (int i = 0; i < count; i++) {
				int dist = 2 + (fast_rand() % 7);
				uint32_t lut_i = fast_rand() & 255;
				int sx = ex + (int)(cos_lut_256[lut_i] * dist);
				int sy = ey + (int)(sin_lut_256[lut_i] * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) {
						set_cell(sx, sy, 44);
						int deg = (int)((float)lut_i * (360.0f / 256.0f));
						int dir_idx = (int)((deg + 112.5f) / 45.0f) % 8;
						charge_ptr[sy * width + sx] = ((30 + (fast_rand() % 30)) << 3) | dir_idx;
					}
				}
			}
		}
		if (flags & 256) {
			int count = is_heavy_load ? 50 : 120;
			for (int i = 0; i < count; i++) {
				float dist = radius * 0.45f + (fast_rand() % 200) / 100.0f;
				uint32_t lut_i = fast_rand() & 255;
				int sx = ex + (int)(cos_lut_256[lut_i] * dist);
				int sy = ey + (int)(sin_lut_256[lut_i] * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) set_cell(sx, sy, 2);
				}
			}
		}
		if (flags & 512) {
			int count = is_heavy_load ? 35 : 80;
			for (int i = 0; i < count; i++) {
				float dist = radius * 0.45f + (fast_rand() % 300) / 100.0f;
				uint32_t lut_i = fast_rand() & 255;
				int sx = ex + (int)(cos_lut_256[lut_i] * dist);
				int sy = ey + (int)(sin_lut_256[lut_i] * dist);
				if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
					if ((cells_ptr[sy * width + sx] & 0xFFFF) == 0) set_cell(sx, sy, 11);
				}
			}
		}
	};

	bool sweep_reverse_base = (frame_count % 2 == 0);

	// =========================================================================
	// PASS 1: RISING GASES / GRAV_UP (Top to Bottom) - Chunk-aware
	// =========================================================================
	for (int y = 0; y < height; ++y) {
		int row_idx = y * width;
		int cy = y >> 4;
		int chunk_row_idx = cy * chunks_x;
		bool sweep_reverse = (sweep_reverse_base != ((y & 1) == 0));

		for (int xi = 0; xi < width; ++xi) {
			int x = sweep_reverse ? (width - 1 - xi) : xi;
			int cx = x >> 4;
			if (use_chunks && chunks_active_ptr[chunk_row_idx + cx] == 0) {
				int skip = sweep_reverse ? (x & 15) : (15 - (x & 15));
				xi += skip;
				continue;
			}

			int idx = row_idx + x;
			int32_t raw_id = cells_ptr[idx];
			int32_t pure_id = raw_id & 0xFFFF;
			if (pure_id == 0 || pure_id == 28) continue;

			uint64_t t = tags_ptr[idx];
			if (!(t & GRAV_UP) || (t & GRAV_STATIC)) continue;

			// Cloud/Vapor (17) condensation at top of map
			if (pure_id == 17 && y < 30 && (fast_rand() % 1000) < 5) {
				set_cell(x, y, 2);
				continue;
			}

			if ((t & GRAV_SLOW) && (fast_rand() % 100) < 50) {
				keep_chunk_awake(x, y);
				continue;
			}

			// Gas random diffusion
			if ((t & GAS) && (fast_rand() % 100) < 30) {
				int rx = x + ((fast_rand() & 1) ? 1 : -1);
				int ry = y + ((fast_rand() & 1) ? 1 : -1);
				if (rx >= 0 && rx < width && ry >= 0 && ry < height && (cells_ptr[ry * width + rx] & 0xFFFF) == 0) {
					swap_cells(x, y, rx, ry);
					continue;
				}
			}

			int next_y = y - 1;
			if (next_y < 0) continue;

			if ((cells_ptr[next_y * width + x] & 0xFFFF) == 0) {
				swap_cells(x, y, x, next_y);
				continue;
			}

			if (t & (POWDER | LIQUID | GAS)) {
				int side = (fast_rand() & 1) ? 1 : -1;
				if (x + side >= 0 && x + side < width && (cells_ptr[next_y * width + (x + side)] & 0xFFFF) == 0) {
					swap_cells(x, y, x + side, next_y);
				} else if (x - side >= 0 && x - side < width && (cells_ptr[next_y * width + (x - side)] & 0xFFFF) == 0) {
					swap_cells(x, y, x - side, next_y);
				} else if (t & (LIQUID | GAS)) {
					if (x + side >= 0 && x + side < width && (cells_ptr[row_idx + (x + side)] & 0xFFFF) == 0) {
						if (swap_cells(x, y, x + side, y)) {
							if (!sweep_reverse && side == 1) xi++;
							else if (sweep_reverse && side == -1) xi++;
						}
					} else if (x - side >= 0 && x - side < width && (cells_ptr[row_idx + (x - side)] & 0xFFFF) == 0) {
						if (swap_cells(x, y, x - side, y)) {
							if (!sweep_reverse && side == -1) xi++;
							else if (sweep_reverse && side == 1) xi++;
						}
					}
				}
			}
		}
	}

	// =========================================================================
	// PASS 2: INTERACTIONS + FALLING GRAVITY (Bottom to Top) - Chunk-aware
	// =========================================================================
	for (int y = height - 1; y >= 0; y--) {
		int row_idx = y * width;
		int cy = y >> 4;
		int chunk_row_idx = cy * chunks_x;
		bool sweep_reverse = (sweep_reverse_base != ((y & 1) == 0));

		for (int xi = 0; xi < width; xi++) {
			int x = sweep_reverse ? (width - 1 - xi) : xi;
			int cx = x >> 4;
			if (use_chunks && chunks_active_ptr[chunk_row_idx + cx] == 0) {
				int skip = sweep_reverse ? (x & 15) : (15 - (x & 15));
				xi += skip;
				continue;
			}

			int idx = row_idx + x;
			int32_t raw_id = cells_ptr[idx];
			int32_t pure_id = raw_id & 0xFFFF;
			if (pure_id == 0) continue;

			uint64_t t = tags_ptr[idx];
			bool destroyed = false;

			// === INTERACTIONS ===

			// 1. PULSANT ELECTRICAL SOURCE (ID 9)
			if (pure_id == 9) {
				keep_chunk_awake(x, y);
				if (charge_ptr[idx] == 0) {
					charge_ptr[idx] = 101;
					charge_changed = true;
					moved_charges.push_back(idx);
				}
			}

			// 2. METRONOME (ID 600)
			if (pure_id == 600) {
				keep_chunk_awake(x, y);
				if (frame_count % music_tempo_frames == 0) {
					if ((x & 1) == 0 && (y & 1) == 0) {
						if (charge_ptr[idx] <= 10) {
							charge_ptr[idx] = 101;
							charge_changed = true;
							moved_charges.push_back(idx);
						}
					}
				}
			}

			// 3. VIRUS / EXPAND LOGIC (Laboratory Exclusive)
			if (t & VIRUS) {
				keep_chunk_awake(x, y);
				if ((fast_rand() % 100) < 5) {
					int nx = x + ((int)(fast_rand() % 3) - 1);
					int ny = y + ((int)(fast_rand() % 3) - 1);
					if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
						int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
						if (nid > 0 && nid != pure_id && nid < 1000) {
							int32_t n_tid = get_tags_id(nid);
							uint64_t n_tags = (n_tid < mat_tags_size) ? mat_tags[n_tid] : 0;
							bool is_enemy_virus = (n_tags & VIRUS) != 0;
							bool is_protected = (n_tags & (ANTI_ACID | INVINCIBLE)) != 0;
							if (is_enemy_virus || !is_protected) {
								set_cell(nx, ny, pure_id);
							}
						}
					}
				}
			}

			// 4. RADIOACTIVE LOGIC (Laboratory Exclusive)
			if (t & RADIOACTIVE) {
				keep_chunk_awake(x, y);
				if ((fast_rand() % 1000) < 5) {
					for (int ny = y - 1; ny <= y + 1; ny++) {
						if (ny < 0 || ny >= height) continue;
						for (int nx = x - 1; nx <= x + 1; nx++) {
							if (nx == x && ny == y) continue;
							if (nx < 0 || nx >= width) continue;
							int n_idx = ny * width + nx;
							if (charge_ptr[n_idx] < 50) {
								charge_ptr[n_idx] = 101;
								charge_changed = true;
								moved_charges.push_back(n_idx);
							}
						}
					}
					if ((fast_rand() % 100) < 10 && y > 0 && (cells_ptr[(y - 1) * width + x] & 0xFFFF) == 0) {
						set_cell(x, y - 1, 43);
						charge_ptr[(y - 1) * width + x] = (40 << 3) | 0;
					}
				}
			}

			// 5. VORTEX LOGIC (Laboratory Exclusive)
			if (t & VORTEX) {
				keep_chunk_awake(x, y);
				if ((fast_rand() % 100) < 10) {
					for (int i = 0; i < 20; ++i) {
						uint32_t lut_i = fast_rand() & 255;
						int dist = (int)(fast_rand() % 45);
						int vx = x + (int)(cos_lut_256[lut_i] * dist);
						int vy = y + (int)(sin_lut_256[lut_i] * dist);
						if (vx >= 0 && vx < width && vy >= 0 && vy < height && (vx != x || vy != y)) {
							int32_t vid = cells_ptr[vy * width + vx] & 0xFFFF;
							if (vid > 0 && vid != pure_id && vid < 500) {
								int32_t v_tid = get_tags_id(vid);
								uint64_t n_tags = (v_tid < mat_tags_size) ? mat_tags[v_tid] : 0;
								if (!(n_tags & INVINCIBLE)) {
									int dx_v = x - vx;
									int dy_v = y - vy;
									int d_sq = dx_v * dx_v + dy_v * dy_v;
									if (d_sq <= 36) {
										set_cell(vx, vy, 0);
										if ((fast_rand() % 100) < 5 && vortex_sparks.size() < 64) {
											vortex_sparks.push_back(Vector2((float)vx, (float)vy));
										}
									} else if (!(n_tags & GRAV_STATIC)) {
										int dx = (dx_v > 0) ? 1 : (dx_v < 0 ? -1 : 0);
										int dy = (dy_v > 0) ? 1 : (dy_v < 0 ? -1 : 0);
										if (dy < 0 && (fast_rand() % 100) < 40) dy = -1;
										int tx = vx + dx;
										int ty = vy + dy;
										if (tx >= 0 && tx < width && ty >= 0 && ty < height) {
											int32_t tid = cells_ptr[ty * width + tx] & 0xFFFF;
											if (tid == 0 || tid < 500) {
												swap_cells(vx, vy, tx, ty);
											}
										}
									}
								}
							}
						}
					}
					if ((fast_rand() % 100) < 10 && vortex_npc_pulls.size() < 32) {
						vortex_npc_pulls.push_back(Vector2i(x, y));
					}
				}
			}

			// 6. REPEL LOGIC (Laboratory Exclusive)
			if (t & REPEL) {
				keep_chunk_awake(x, y);
				if ((fast_rand() % 100) < 10) {
					for (int i = 0; i < 30; ++i) {
						uint32_t lut_i = fast_rand() & 255;
						int dist = (int)(fast_rand() % 35);
						int vx = x + (int)(cos_lut_256[lut_i] * dist);
						int vy = y + (int)(sin_lut_256[lut_i] * dist);
						if (vx >= 0 && vx < width && vy >= 0 && vy < height && (vx != x || vy != y)) {
							int32_t vid = cells_ptr[vy * width + vx] & 0xFFFF;
							if (vid > 0 && vid != pure_id && vid < 1000) {
								int32_t v_tid = get_tags_id(vid);
								uint64_t n_tags = (v_tid < mat_tags_size) ? mat_tags[v_tid] : 0;
								if (!(n_tags & GRAV_STATIC)) {
									int sx = (vx > x) ? 1 : (vx < x ? -1 : 0);
									int sy = (vy > y) ? 1 : (vy < y ? -1 : 0);
									int dx = sx * (2 + (int)(fast_rand() % 5));
									int dy = sy * (1 + (int)(fast_rand() % 4));
									if (dy == 0) dy = -1;
									int tx = vx + dx;
									int ty = vy + dy;
									if (tx >= 0 && tx < width && ty >= 0 && ty < height) {
										if ((cells_ptr[ty * width + tx] & 0xFFFF) == 0) {
											if (swap_cells(vx, vy, tx, ty)) {
												if ((fast_rand() % 100) < 5 && repel_sparks.size() < 64) {
													repel_sparks.push_back(Vector4((float)vx, (float)vy, (float)dx, (float)dy));
												}
											}
										}
									}
								}
							}
						}
					}
					if ((fast_rand() % 100) < 2 && repel_npc_pushes.size() < 32) {
						repel_npc_pushes.push_back(Vector2i(x, y));
					}
				}
			}

			// 7. ACID
			if (t & ACID) {
				keep_chunk_awake(x, y);
				if ((fast_rand() % 100) < 20) {
					for (int ny = y - 1; ny <= y + 1; ny++) {
						if (ny < 0 || ny >= height) continue;
						for (int nx = x - 1; nx <= x + 1; nx++) {
							if (nx == x && ny == y) continue;
							if (nx < 0 || nx >= width) continue;
							int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
							if (nid > 0 && nid != pure_id) {
								int32_t n_tid = get_tags_id(nid);
								uint64_t n_tags = (n_tid < mat_tags_size) ? mat_tags[n_tid] : 0;
								if (!(n_tags & (ANTI_ACID | INVINCIBLE))) {
									set_cell(nx, ny, 44);
									charge_ptr[ny * width + nx] = ((15 + (fast_rand() % 15)) << 3) | (fast_rand() & 7);
									if ((fast_rand() % 100) < 30) { set_cell(x, y, 0); destroyed = true; goto interaction_done; }
									if ((n_tags & SOLID) && (fast_rand() % 100) < 10) { set_cell(x, y, 0); destroyed = true; goto interaction_done; }
								}
							}
						}
					}
				}
			}

			// 8. FIRE AND HEAT
			if (t & INCENDIARY) {
				keep_chunk_awake(x, y);
				if (pure_id == 3 || pure_id == 14) {
					is_fire_active = true;
				}
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

				// Heat Reactions (Lava + Water = Obsidian, Flammable ignition)
				if ((fast_rand() % 100) < 50) {
					for (int ny = y - 1; ny <= y + 1; ny++) {
						if (ny < 0 || ny >= height) continue;
						for (int nx = x - 1; nx <= x + 1; nx++) {
							if (nx == x && ny == y) continue;
							if (nx < 0 || nx >= width) continue;
							int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
							if (nid > 0) {
								if ((pure_id == 11 && nid == 2) || (pure_id == 2 && nid == 11)) {
									set_cell(x, y, 12); set_cell(nx, ny, 12); destroyed = true; goto interaction_done; // Obsidian
								}
								int32_t n_tid = get_tags_id(nid);
								uint64_t n_tags = (n_tid < mat_tags_size) ? mat_tags[n_tid] : 0;
								if ((n_tags & FLAMMABLE) && nid != 14) {
									if ((fast_rand() % 100) < 80) {
										if (nid == 18) { // Firework fuse
											set_cell(nx, ny, 19);
											charge_ptr[ny * width + nx] = 20 + (fast_rand() % 50);
											charge_changed = true;
											fuse_burned = true;
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
										if (nid == 27) {
											set_cell(nx, ny, 29);
											charge_ptr[ny * width + nx] = 80 + (fast_rand() % 40);
											activate_chunk(nx, ny);
										} else if (nid == 18) {
											set_cell(nx, ny, 19);
											charge_ptr[ny * width + nx] = 20 + (fast_rand() % 50);
											charge_changed = true;
											fuse_burned = true;
										} else {
											bool source_is_elec = (pure_id == 9 || (t & ELECTRICITY));
											if (!source_is_elec || (n_tags & ELECTRIC_ACTIVATED)) {
												prime_explosive(nx, ny, nid, source_is_elec ? 128 : 0);
											}
										}
									}
								}
							}
						}
					}
				}
			}

			// 9. VOLCANO LOGIC (pure_id 27, 28, 29)
			if (pure_id == 27 || pure_id == 28 || pure_id == 29) {
				if (pure_id == 27) { // Static block
					if (charge_ptr[idx] > 0) keep_chunk_awake(x, y);
					if (has_tag_neighbor(x, y, INCENDIARY) || charge_ptr[idx] > 10) {
						is_volcano_active = true;
						keep_chunk_awake(x, y);
						if ((fast_rand() % 100) < 5) {
							set_cell(x, y, 29); // Transform to ACTIVE BASE
							charge_ptr[idx] = 80 + (fast_rand() % 71); // 80 to 150
						} else {
							charge_ptr[idx] += 1;
							if ((fast_rand() % 100) < 25) { // Spread heat
								int nx = x + (fast_rand() % 3) - 1;
								int ny = y + (fast_rand() % 3) - 1;
								if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
									if ((cells_ptr[ny * width + nx] & 0xFFFF) == 27) {
										charge_ptr[ny * width + nx] += 10;
										activate_chunk(nx, ny);
									}
								}
							}
						}
					}
				} else if (pure_id == 29) { // Erupting Base
					is_volcano_active = true;
					keep_chunk_awake(x, y);
					charge_ptr[idx] -= 1;
					int current_charge = charge_ptr[idx];

					if ((fast_rand() % 100) < 25) { // Spread heat while erupting so the chain doesn't stop
						int nx = x + (fast_rand() % 3) - 1;
						int ny = y + (fast_rand() % 3) - 1;
						if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
							if ((cells_ptr[ny * width + nx] & 0xFFFF) == 27) {
								charge_ptr[ny * width + nx] += 10;
								activate_chunk(nx, ny);
							}
						}
					}

					if (current_charge % 35 == 0 && current_charge > 0) {
						int tx = x + (fast_rand() % 3) - 1;
						int ny = y - 1;
						if (tx >= 0 && tx < width && ny >= 0 && ny < height) {
							int n_id = cells_ptr[ny * width + tx] & 0xFFFF;
							if (n_id != 13 && n_id != 26 && n_id != 5) {
								int shot_count = current_charge / 35;
								String sfx = (shot_count % 2 != 0) ? String("volcan_burst") : String("");

								Array expl; expl.push_back(x); expl.push_back(ny); expl.push_back(2);
								expl.push_back(sfx); expl.push_back(1048576); expl.push_back(false);
								explosions_queue.push_back(expl);
								execute_explosion(x, ny, 2, 1048576);

								set_cell(tx, ny, 28);
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
							set_cell(x, y, 0);
						}

						for (int dy = -5; dy <= 5; dy++) {
							for (int dx = -5; dx <= 5; dx++) {
								if (dx * dx + dy * dy <= 25) {
									int cx_v = x + dx; int cy_v = y + dy;
									if (cx_v >= 0 && cx_v < width && cy_v >= 0 && cy_v < height) {
										int cnid = cells_ptr[cy_v * width + cx_v] & 0xFFFF;
										if (cnid == 0 || cnid == 27 || cnid == 29) {
											set_cell(cx_v, cy_v, 11);
										}
									}
								}
							}
						}
						destroyed = true;
					}
				} else if (pure_id == 28) { // Ascending projectile
					is_volcano_active = true;
					keep_chunk_awake(x, y);
					int current_fuel = charge_ptr[idx];
					if (current_fuel < 0) { // Moved here this frame
						charge_ptr[idx] = -current_fuel;
						goto interaction_done;
					}

					if (current_fuel <= 0) {
						for (int dy = -6; dy <= 6; dy++) {
							for (int dx = -6; dx <= 6; dx++) {
								int cx_v = x + dx; int cy_v = y + dy;
								if (cx_v >= 0 && cx_v < width && cy_v >= 0 && cy_v < height) {
									int cnid = cells_ptr[cy_v * width + cx_v] & 0xFFFF;
									if (cnid == 0 || cnid == 27 || cnid == 29) {
										if (dx * dx + dy * dy <= 16) set_cell(cx_v, cy_v, 15);
										else if (dx * dx + dy * dy <= 36) set_cell(cx_v, cy_v, 11);
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

					for (int d = 0; d < 5; d++) {
						int tx = x + dxs[d];
						int ty = y + dys[d];
						if (tx >= 0 && tx < width && ty >= 0 && ty < height) {
							int nid = cells_ptr[ty * width + tx] & 0xFFFF;
							if (nid == 28) continue;

							int32_t n_tid = get_tags_id(nid);
							uint64_t n_tags = (nid > 0 && n_tid < mat_tags_size) ? mat_tags[n_tid] : 0;
							if (nid == 0 || !(n_tags & INVINCIBLE)) {
								bool is_solid = (nid > 0 && nid != 11 && nid != 15 && nid != 3 && nid != 9 && nid != 27 && nid != 29);
								if (is_solid) {
									int break_chance = (dys[d] < 0) ? 2 : 1;
									if ((fast_rand() % 100) >= (uint32_t)break_chance) {
										continue;
									}
									current_fuel -= 5;
									for (int cdy = -1; cdy <= 1; cdy++) {
										for (int cdx = -1; cdx <= 1; cdx++) {
											int cx_v = tx + cdx; int cy_v = ty + cdy;
											if (cx_v >= 0 && cx_v < width && cy_v >= 0 && cy_v < height) {
												int cid = cells_ptr[cy_v * width + cx_v] & 0xFFFF;
												if (cid > 0 && cid != 28) {
													int32_t c_tid = get_tags_id(cid);
													uint64_t c_tags = (c_tid < mat_tags_size) ? mat_tags[c_tid] : 0;
													if (!(c_tags & INVINCIBLE)) {
														int r = fast_rand() % 100;
														if (r < 30) set_cell(cx_v, cy_v, 11);
														else if (r < 50 && current_fuel < 60) set_cell(cx_v, cy_v, 15);
														else set_cell(cx_v, cy_v, 0);
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
								for (int dy = -10; dy <= 10; dy++) {
									for (int dx = -10; dx <= 10; dx++) {
										int cx_v = x + dx; int cy_v = y + dy;
										if (cx_v >= 0 && cx_v < width && cy_v >= 0 && cy_v < height && dx * dx + dy * dy <= 100) {
											if ((cells_ptr[cy_v * width + cx_v] & 0xFFFF) == 0) set_cell(cx_v, cy_v, 11);
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
				goto interaction_done;
			}

			// 10. EXPLOSIVE IGNITION (Fire, Acid, or Direct Electric Contact when ELECTRIC_ACTIVATED)
			if ((t & EXPLOSIVE) && charge_ptr[idx] == 0) {
				bool has_acid = has_tag_neighbor(x, y, ACID);
				bool has_elec = (t & ELECTRIC_ACTIVATED) && (count_neighbor_id(x, y, 9) > 0);
				bool has_fire = false;
				if (!has_acid && !has_elec) {
					for (int ny = y - 1; ny <= y + 1; ny++) {
						if (ny < 0 || ny >= height) continue;
						for (int nx = x - 1; nx <= x + 1; nx++) {
							if (nx == x && ny == y) continue;
							if (nx < 0 || nx >= width) continue;
							int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
							if (nid > 0 && nid != 9) {
								int32_t n_tid = get_tags_id(nid);
								uint64_t n_tags = (n_tid < mat_tags_size) ? mat_tags[n_tid] : 0;
								if ((n_tags & INCENDIARY) && !(n_tags & ELECTRICITY)) {
									has_fire = true;
									break;
								}
							}
						}
						if (has_fire) break;
					}
				}
				if (has_acid || has_elec || has_fire) {
					int trigger_type = 0;
					if (has_acid) trigger_type = 64;
					else if (has_elec) trigger_type = 128;
					prime_explosive(x, y, pure_id, trigger_type);
				}
			}

			// 11. EXPLOSIVE TIMER (Any Primed Explosive)
			if ((t & EXPLOSIVE) && charge_ptr[idx] > 0) {
				keep_chunk_awake(x, y);
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
					set_cell(x, y, 0);
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
				charge_changed = true;
			}

			// 12. FIREWORKS IGNITION & FUSE COUNTDOWN (Materials 18 & 19)
			if (pure_id == 18) {
				if (charge_ptr[idx] > 50 || ((fast_rand() % 100) < 10 && has_tag_neighbor(x, y, INCENDIARY))) {
					set_cell(x, y, 19);
					charge_ptr[idx] = 20 + (fast_rand() % 50);
					charge_visual_ptr[idx] = (uint8_t)charge_ptr[idx];
					charge_changed = true;
					fuse_burned = true;
					keep_chunk_awake(x, y);
					destroyed = true;
					goto interaction_done;
				}
			} else if (pure_id == 19) {
				keep_chunk_awake(x, y);
				int32_t c = charge_ptr[idx] - 1;
				charge_ptr[idx] = c;
				int32_t vis_c = c & 63;
				charge_visual_ptr[idx] = (vis_c < 0) ? 0 : (vis_c > 255 ? 255 : (uint8_t)vis_c);
				charge_changed = true;
				if (c <= 0 || vis_c <= 0) {
					set_cell(x, y, 0);
					launched_fireworks.push_back(Vector2i(x, y));
					destroyed = true;
					goto interaction_done;
				}
			}

			// 13. MUSIC HEAT INTERACTION
			if (t & MUSIC) {
				if ((x & 1) == 0 && (y & 1) == 0 && has_tag_neighbor(x, y, INCENDIARY)) {
					heat_music_notes.push_back(pure_id);
				}
			}

			// 14. CRYOGENICS (Materials 60 & 70)
			if (pure_id == 60) {
				if (has_tag_neighbor(x, y, INCENDIARY)) {
					keep_chunk_awake(x, y);
					if ((fast_rand() % 100) < 20) {
						set_cell(x, y, 2);
						destroyed = true;
						goto interaction_done;
					}
				}
				if ((fast_rand() % 100) < 5) {
					for (int ny = y - 1; ny <= y + 1; ny++) {
						if (ny < 0 || ny >= height) continue;
						for (int nx = x - 1; nx <= x + 1; nx++) {
							if (nx < 0 || nx >= width || (nx == x && ny == y)) continue;
							if ((cells_ptr[ny * width + nx] & 0xFFFF) == 2) {
								set_cell(nx, ny, 60);
								goto cryo_60_done;
							}
						}
					}
				}
				cryo_60_done:;
			} else if (pure_id == 70) {
				bool has_water_or_warm = false;
				for (int ny = y - 1; ny <= y + 1; ny++) {
					if (ny < 0 || ny >= height) continue;
					for (int nx = x - 1; nx <= x + 1; nx++) {
						if (nx < 0 || nx >= width || (nx == x && ny == y)) continue;
						int32_t n_pid = cells_ptr[ny * width + nx] & 0xFFFF;
						if (n_pid == 11) {
							set_cell(x, y, 17);
							set_cell(nx, ny, 12);
							destroyed = true;
							goto interaction_done;
						} else if (n_pid == 3) {
							set_cell(x, y, 2);
							set_cell(nx, ny, 15);
							destroyed = true;
							goto interaction_done;
						} else if (n_pid == 15 || n_pid == 17) {
							has_water_or_warm = true;
							if ((fast_rand() % 100) < 2) {
								set_cell(x, y, 2);
								destroyed = true;
								goto interaction_done;
							}
						} else if (n_pid == 2) {
							has_water_or_warm = true;
							if ((fast_rand() % 100) < 5) {
								set_cell(nx, ny, 70);
								goto cryo_70_done;
							}
						}
					}
				}
				cryo_70_done:;
				if (has_water_or_warm) keep_chunk_awake(x, y);
			}

			// 15. VOLATILE INERTIA (Sparks, projectiles)
			if (t & VOLATILE) {
				keep_chunk_awake(x, y);
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
					destroyed = true;
					goto interaction_done;
				} else {
					if (pure_id == 44) set_cell(x, y, 13); // Acid projectile to liquid acid
					else set_cell(x, y, 0); // Vanish
					destroyed = true; goto interaction_done;
				}
			}

			// 16. ELECTRIC SEEDING DECAY (Pure Static Electricity)
			if (t & ELECTRICITY) {
				keep_chunk_awake(x, y);
				if (!(t & (LIQUID | SOLID | VOLATILE))) {
					if ((fast_rand() % 100) < 70) {
						set_cell(x, y, 0);
						destroyed = true;
						goto interaction_done;
					}
				}
			}

			// 17. FLAMMABLE
			if (t & FLAMMABLE) {
				if (has_tag_neighbor(x, y, INCENDIARY) || charge_ptr[idx] > 50) {
					keep_chunk_awake(x, y);
					if (pure_id == 16) { // Wood
						if ((fast_rand() % 100) < 50) { set_cell(x, y, (fast_rand() % 2 == 0) ? 14 : 3); destroyed = true; goto interaction_done; }
					} else if (pure_id == 4) { // Petro
						if ((fast_rand() % 100) < 10) { set_cell(x, y, 3); destroyed = true; goto interaction_done; }
					}
				}
			}

			// 18. BIOLOGICAL INTERACTIONS (PLANTS & SEEDS: 1, 6, 21, 22, 23, 24)
			if (pure_id == 24 && charge_ptr[idx] > 0) {
				keep_chunk_awake(x, y);
			}
			if ((pure_id == 1 || pure_id == 6 || (pure_id >= 21 && pure_id <= 24)) && (fast_rand() % 100) < 2) {
				if (pure_id == 21) { // Grass
					if (current_weather > 0 || has_id_in_oval(x, y, 2, oval_20x10_dx, oval_20x10_dy)) {
						keep_chunk_awake(x, y);
						if ((fast_rand() % 100) < 30) {
							int gx = x + ((int)(fast_rand() % 5) - 2);
							int gy = y + ((int)(fast_rand() % 5) - 2);
							if (gx >= 0 && gx < width && gy >= 0 && gy < height) {
								int g_idx = gy * width + gx;
								if ((cells_ptr[g_idx] & 0xFFFF) == 0) {
									bool can_grow = false;
									for (int oy = -1; oy <= 1 && !can_grow; oy++) {
										int ny = gy + oy;
										if (ny < 0 || ny >= height) continue;
										for (int ox = -1; ox <= 1; ox++) {
											int nx = gx + ox;
											if (nx < 0 || nx >= width) continue;
											int32_t nid = cells_ptr[ny * width + nx] & 0xFFFF;
											int32_t n_tid = get_tags_id(nid);
											if (nid > 0 && n_tid < mat_tags_size && (mat_tags[n_tid] & FERTILE)) {
												can_grow = true;
												break;
											}
										}
									}
									if (can_grow && (fast_rand() % 100) < 70) {
										if (count_neighbor_id(gx, gy, 21) < 4) {
											set_cell(gx, gy, 21);
										}
									}
								}
							}
						}
					}
				} else if (pure_id == 1 || pure_id == 6) { // Fertile Soil
					if (current_weather > 0 || has_id_in_oval(x, y, 2, oval_16x8_dx, oval_16x8_dy)) {
						set_cell(x, y, (pure_id == 1) ? 22 : 23);
					}
				} else if (pure_id == 22 || pure_id == 23) { // Wet Soil
					keep_chunk_awake(x, y);
					if (current_weather > 0 || has_id_in_oval(x, y, 2, oval_20x10_dx, oval_20x10_dy)) {
						if ((fast_rand() % 100) < 5 && has_tag_neighbor(x, y, PLANT)) {
							if (count_neighbor_id(x, y, 21) < 4) {
								set_cell(x, y, 21);
							}
						} else if ((fast_rand() % 100) < 15) {
							if (y > 0 && (cells_ptr[idx - width] & 0xFFFF) == 0) {
								if (count_neighbor_id_radius(x, y, 24, 2) < 2) {
									set_cell(x, y - 1, 24);
									if ((fast_rand() & 1) == 0) {
										charge_ptr[idx - width] = 1 + (fast_rand() % 3); // Flowers (1-3)
									} else {
										charge_ptr[idx - width] = 104 + (fast_rand() % 4); // Vines (104-107)
									}
								}
							}
						}
					} else {
						if (current_weather == 0 && (fast_rand() % 100) < 10) {
							set_cell(x, y, (pure_id == 22) ? 1 : 6);
						}
					}
				} else if (pure_id == 24) { // Vines
					int32_t h_left = charge_ptr[idx];
					if (h_left > 0 && (fast_rand() % 100) < 30 && y > 0) {
						if ((cells_ptr[idx - width] & 0xFFFF) == 0) {
							if (count_neighbor_id(x, y - 1, 24) < 2) {
								if (h_left == 1) {
									int32_t flower_colors[4] = {31, 32, 33, 34};
									set_cell(x, y - 1, flower_colors[fast_rand() & 3]);
								} else if (h_left == 101) {
									set_cell(x, y - 1, 24);
								} else {
									set_cell(x, y - 1, 24);
									charge_ptr[idx - width] = h_left - 1;
								}
								charge_ptr[idx] = 0;
							}
						}
					}
				}
			}

			// 19. FRESH CEMENT HARDENING (Material 25)
			if (pure_id == 25) {
				keep_chunk_awake(x, y);
				if (charge_ptr[idx] == 0) {
					charge_ptr[idx] = 60 + (fast_rand() % 60);
				}
				charge_ptr[idx] -= 1;
				if (charge_ptr[idx] <= 1) {
					set_cell(x, y, 26);
					destroyed = true;
					goto interaction_done;
				}
			}

			interaction_done:
			if (destroyed) continue;

			// Re-fetch in case interaction modified tags
			t = tags_ptr[idx];

			// === GRAVITY (Phase 2: Falling Powders, Liquids, Solids) ===
			if (!(t & GRAV_UP) && !(t & GRAV_STATIC)) {
				// GRAV_SLOW check
				if ((t & GRAV_SLOW) && (fast_rand() % 100 > 30)) {
					keep_chunk_awake(x, y);
					continue; // 70% chance to not move, keep chunk awake so slow liquids/powders don't freeze
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
						int side = (fast_rand() % 2 == 0) ? 1 : -1;
						int side_idx = idx + side;
						bool can_flow = ((x + side >= 0 && x + side < width && (cells_ptr[side_idx] & 0xFFFF) == 0) ||
						                 (x - side >= 0 && x - side < width && (cells_ptr[idx - side] & 0xFFFF) == 0));
						if (can_flow) {
							if ((fast_rand() % 100) > 75) {
								if (x + side >= 0 && x + side < width && (cells_ptr[side_idx] & 0xFFFF) == 0) {
									if (swap_cells(x, y, x + side, y)) {
										if (!sweep_reverse && side == 1) xi++;
										else if (sweep_reverse && side == -1) xi++;
									}
								} else if (x - side >= 0 && x - side < width && (cells_ptr[idx - side] & 0xFFFF) == 0) {
									if (swap_cells(x, y, x - side, y)) {
										if (!sweep_reverse && side == -1) xi++;
										else if (sweep_reverse && side == 1) xi++;
									}
								}
							} else {
								keep_chunk_awake(x, y);
							}
						}
					}
					else if (t & POWDER) {
						// Diagonal fall (only check ONE random side per frame to create organic ruggedness)
						int side = (fast_rand() % 2 == 0) ? 1 : -1;
						int side_idx = (ny * width) + (x + side);
						if (x + side >= 0 && x + side < width && (cells_ptr[side_idx] & 0xFFFF) == 0) {
							swap_cells(x, y, x + side, ny);
						} else if (x - side >= 0 && x - side < width && (cells_ptr[(ny * width) + (x - side)] & 0xFFFF) == 0) {
							keep_chunk_awake(x, y);
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
	state["cell_paint_colors"] = cell_paint_colors;
	state["next_chunks_active"] = next_chunks_active;
	state["explosions"] = explosions_queue;
	state["launched_fireworks"] = launched_fireworks;
	state["vortex_npc_pulls"] = vortex_npc_pulls;
	state["repel_npc_pushes"] = repel_npc_pushes;
	state["vortex_sparks"] = vortex_sparks;
	state["repel_sparks"] = repel_sparks;
	state["heat_music_notes"] = heat_music_notes;
	state["fuse_burned"] = fuse_burned;
	state["is_fire_active"] = is_fire_active;
	state["is_volcano_active"] = is_volcano_active;
	state["paint_changed"] = paint_changed;
	state["charge_changed"] = charge_changed;

	PackedInt32Array out_moved_charges;
	out_moved_charges.resize(moved_charges.size());
	int32_t* moved_ptr = out_moved_charges.ptrw();
	for (size_t i = 0; i < moved_charges.size(); ++i) {
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
	
	// Pre-allocate optimization
	if (elec_lookup.size() < width * height) {
		elec_lookup.resize(width * height, 0);
	}
	
	// We use bits of the counter for different lookups to avoid allocating multiple vectors
	// bits 0-7: counter frame (increments)
	// We just increment counter by 4 each frame to give us 4 "flags"
	elec_lookup_counter += 4;
	if (elec_lookup_counter > 4000000000U) {
		std::fill(elec_lookup.begin(), elec_lookup.end(), 0);
		elec_lookup_counter = 4;
	}
	
	uint32_t FLAG_PB = elec_lookup_counter;
	uint32_t FLAG_PREV = elec_lookup_counter + 1;
	uint32_t FLAG_MUSIC = elec_lookup_counter + 2;
	uint32_t FLAG_INACTIVE = elec_lookup_counter + 3;
	
	// Phase Blocks fast lookup
	for (int i = 0; i < phase_blocks_indices.size(); ++i) {
		int idx = int(phase_blocks_indices[i]);
		if (idx >= 0 && idx < width * height) elec_lookup[idx] = FLAG_PB;
	}
	
	// Prev charges fast lookup (for LED rainbow pulsing)
	for (int i = 0; i < prev_charges_arr.size(); ++i) {
		int idx = int(prev_charges_arr[i]);
		if (idx >= 0 && idx < width * height) elec_lookup[idx] = FLAG_PREV;
	}
	
	for (int i = 0; i < prev_active_music_charges_arr.size(); ++i) {
		int idx = int(prev_active_music_charges_arr[i]);
		if (idx >= 0 && idx < width * height) elec_lookup[idx] = FLAG_MUSIC;
	}
	
	// Fast lookup to prevent duplicates
	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = int(active_charge_indices[i]);
		if (idx >= 0 && idx < width * height) elec_lookup[idx] = FLAG_INACTIVE;
	}

	// Initialize sources to 100
	for (int i = 0; i < sources_indices.size(); ++i) {
		int idx = sources_indices[i];
		if (idx < 0 || idx >= width * height) continue;
		charge_ptr[idx] = 100;
		charge_visual_ptr[idx] = 100;
		if (elec_lookup[idx] != FLAG_INACTIVE) {
			active_charge_indices.append(idx);
			elec_lookup[idx] = FLAG_INACTIVE;
		}
	}
	
	// BFS Queue
	elec_queue_x.clear();
	elec_queue_y.clear();
	
	for (int i = 0; i < sources_indices.size(); ++i) {
		int idx = sources_indices[i];
		int gy = idx / width;
		int gx = idx % width;
		elec_queue_x.push_back(gx);
		elec_queue_y.push_back(gy);
		powered_frame_ptr[idx] = frame_count;
	}
	
	// 3. BFS from constant sources
	int head = 0;
	while (head < elec_queue_x.size()) {
		int cx = elec_queue_x[head];
		int cy = elec_queue_y[head];
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
				if (n_pid <= 0 && elec_lookup[n_idx] != FLAG_PB) continue;
				
				if (n_pid >= 81 && n_pid <= 87) {
					int n_var = (cells_ptr[n_idx] >> 24) & 0xFF;
					if (n_var < 10) continue;
				}
				
				if (charge_ptr[n_idx] > 0) {
					powered_frame_ptr[n_idx] = frame_count;
					elec_queue_x.push_back(nx);
					elec_queue_y.push_back(ny);
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
			uint64_t t = tags_ptr[idx];
			if ((t & MUSIC) == 0) {
				wave_fronts.push_back(idx);
			}
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
					bool pb = (elec_lookup[n_idx] == FLAG_PB);
					if (n_pid <= 0 && !pb) continue;
					
					if (n_pid >= 81 && n_pid <= 87) {
						int n_var = (cells_ptr[n_idx] >> 24) & 0xFF;
						if (n_var < 10) continue;
					}
					
					uint64_t n_tags = tags_ptr[n_idx];
					if ((n_tags & EXPLOSIVE) && (n_tags & ELECTRIC_ACTIVATED)) {
						if (charge_ptr[n_idx] == 0) {
							if (n_pid == 27) {
								charge_ptr[n_idx] = 100;
								activate_chunk(nx, ny);
							} else if (n_pid != 7 && n_pid != 77 && n_pid != 71 && n_pid != 72 && n_pid != 28 && n_pid != 29 && !(n_tags & INVINCIBLE)) {
								int ign_flags = 0;
								if (n_pid == 5 || n_pid == 20) {
									ign_flags = 128; // EXP_ELECTRIC
								} else {
									if (n_tags & EXP_ACID) ign_flags |= 64;
									if (n_tags & EXP_ELECTRIC) ign_flags |= 128;
									if (n_tags & EXP_WATER) ign_flags |= 256;
									if (n_tags & EXP_LAVA) ign_flags |= 512;
									if (n_tags & EXP_NPC) ign_flags |= 1024;
									if (n_tags & EXP_LIFE) ign_flags |= 2048;
									if (n_tags & EXP_GAS) ign_flags |= 131072;
									if (n_tags & EXP_QUAKE) ign_flags |= 262144;
									if (n_tags & EXP_PINATA) ign_flags |= 524288;
									if (n_tags & EXP_TEAM_RED) ign_flags |= 4096;
									else if (n_tags & EXP_TEAM_BLUE) ign_flags |= 8192;
									else if (n_tags & EXP_TEAM_GREEN) ign_flags |= 16384;
									else if (n_tags & EXP_TEAM_YELLOW) ign_flags |= 32768;
									if (n_tags & EXP_TEAM_MIXED) ign_flags |= 65536;
								}
								charge_ptr[n_idx] = 40 | ign_flags;
								charge_visual_ptr[n_idx] = 160;
								activate_chunk(nx, ny);
							}
						}
					} else if (pb || (n_tags & (CONDUCTOR | ELECTRIC_ACTIVATED))) {
						charge_ptr[n_idx] = 100;
						
						if (elec_lookup[n_idx] != FLAG_INACTIVE) {
							new_active_charges.push_back(n_idx);
							elec_lookup[n_idx] = FLAG_INACTIVE;
						}
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
		uint64_t m_tags = tags_ptr[idx];
		
		if (mid == 7 || mid == 77 || mid == 71 || mid == 72 || mid == 19 || mid == 5 || mid == 20 ||
		    ((m_tags & EXPLOSIVE) != 0 && mid != 27 && mid != 28 && mid != 29)) {
			new_active_charges.push_back(idx);
			continue;
		}
		if (mid == 24 || mid == 25 || mid == 27 || mid == 28 || mid == 29 || mid == 43 || mid == 44) {
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
				bool is_new_pulse = (elec_lookup[idx] != FLAG_PREV);
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
			int bx = (gx % 2 == 0) ? (gx - 1) : gx;
			int by = (gy % 2 == 0) ? (gy - 1) : gy;
			int b_idx = by * width + bx;
			
			if (elec_lookup[b_idx] != FLAG_MUSIC) {
				elec_lookup[b_idx] = FLAG_MUSIC; // Prevent multiple triggers in same frame
				if (mid == 600) {
					out_music_notes.append(Vector3(5, 0, b_idx));
				} else {
					int inst = (mid - 500) / 16;
					int note = (mid - 500) % 16;
					out_music_notes.append(Vector3(inst, note, b_idx));
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
		int cx = x >> 4;
		int cy = y >> 4;
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

Dictionary SandboxGridNode::process_pistons(Array active_pistons, Dictionary state, int width, int height, float delta) {
	PackedInt32Array cells = state["cells"];
	PackedInt64Array tags_array = state["tags_array"];
	PackedInt32Array charge_array = state["charge_array"];
	PackedByteArray next_chunks_active = state["next_chunks_active"];
	PackedInt32Array cell_paint_colors = state["cell_paint_colors"];
	
	int32_t* cells_ptr = cells.ptrw();
	int64_t* tags_ptr = tags_array.ptrw();
	int32_t* charge_ptr = charge_array.ptrw();
	uint8_t* chunks_ptr = next_chunks_active.ptrw();
	int32_t* paint_ptr = cell_paint_colors.ptrw();
	bool paint_changed = false;
	
	int chunks_x = width / 16;
	if (width % 16 != 0) chunks_x++;
	
	auto move_cell = [&](int src_x, int src_y, int dst_x, int dst_y) {
		int src_idx = src_y * width + src_x;
		int dst_idx = dst_y * width + dst_x;
		
		if (paint_ptr[src_idx] != 0 || paint_ptr[dst_idx] != 0) {
			paint_changed = true;
		}
		cells_ptr[dst_idx] = cells_ptr[src_idx];
		tags_ptr[dst_idx] = tags_ptr[src_idx];
		charge_ptr[dst_idx] = charge_ptr[src_idx];
		paint_ptr[dst_idx] = paint_ptr[src_idx];
		
		// DO NOT clear src_idx. This allows the piston to leave a solid trail of piston arms
		// and prevents falling-through bugs. Retraction handles cleanup explicitly.
		
		int chunk_x = dst_x / 16;
		int chunk_y = dst_y / 16;
		int c_idx = chunk_y * chunks_x + chunk_x;
		if (c_idx >= 0 && c_idx < next_chunks_active.size() && chunks_ptr[c_idx] < 60) {
			chunks_ptr[c_idx] = 60;
		}
	};
	
	auto set_piston_head = [&](int x, int y, bool insulated) {
		int idx = y * width + x;
		if (paint_ptr[idx] != 0) {
			paint_ptr[idx] = 0;
			paint_changed = true;
		}
		if (insulated) {
			cells_ptr[idx] = 194;
			tags_ptr[idx] = (1ULL << 0) | (1ULL << 13); // SOLID | GRAV_STATIC
		} else {
			cells_ptr[idx] = 94;
			tags_ptr[idx] = (1ULL << 0) | (1ULL << 13) | (1ULL << 8); // SOLID | GRAV_STATIC | CONDUCTOR
		}
		
		int chunk_x = x / 16;
		int chunk_y = y / 16;
		int c_idx = chunk_y * chunks_x + chunk_x;
		if (c_idx >= 0 && c_idx < next_chunks_active.size() && chunks_ptr[c_idx] < 60) {
			chunks_ptr[c_idx] = 60;
		}
	};
	
	Array new_active;
	for (int i = 0; i < active_pistons.size(); ++i) {
		Dictionary p = active_pistons[i];
		Vector2i pos = p["pos"];
		int orient = p["orientation"];
		int target_ext = p["target_ext"];
		float current_ext = p["current_ext"];
		
		int base_cx = pos.x + 2;
		int base_cy = pos.y + 2;
		if (base_cx < 0 || base_cx >= width || base_cy < 0 || base_cy >= height) continue;
		
		int base_idx = base_cy * width + base_cx;
		int base_mat = cells_ptr[base_idx] & 0xFFFF;
		if (base_mat != 93 && base_mat != 193) continue;
		
		bool is_insulated = p.get("is_insulated", false);
		
		bool powered = false;
		for (int dy = -3; dy <= 3; ++dy) {
			for (int dx = -3; dx <= 3; ++dx) {
				int cx = base_cx + dx;
				int cy = base_cy + dy;
				if (cx >= 0 && cx < width && cy >= 0 && cy < height) {
					if (charge_ptr[cy * width + cx] > 0) {
						powered = true;
						break;
					}
				}
			}
			if (powered) break;
		}
		
		if (powered) {
			int target_px = target_ext * 4;
			if (target_px > 160) target_px = 160;
			
			if (current_ext < target_px) {
				int px = pos.x;
				int gy = pos.y;
				int ext = (int)current_ext;
				
				int push_height = 0;
				int step_idx = 1;
				bool blocked = false;
				
				while (true) {
					Vector2i p0, p1, p2, p3;
					if (orient == 0) {
						int ty = gy - ext - step_idx;
						p0 = Vector2i(px, ty); p1 = Vector2i(px + 1, ty); p2 = Vector2i(px + 2, ty); p3 = Vector2i(px + 3, ty);
					} else if (orient == 1) {
						int tx = px + 3 + ext + step_idx;
						p0 = Vector2i(tx, gy); p1 = Vector2i(tx, gy + 1); p2 = Vector2i(tx, gy + 2); p3 = Vector2i(tx, gy + 3);
					} else if (orient == 2) {
						int ty = gy + 3 + ext + step_idx;
						p0 = Vector2i(px, ty); p1 = Vector2i(px + 1, ty); p2 = Vector2i(px + 2, ty); p3 = Vector2i(px + 3, ty);
					} else if (orient == 3) {
						int tx = px - ext - step_idx;
						p0 = Vector2i(tx, gy); p1 = Vector2i(tx, gy + 1); p2 = Vector2i(tx, gy + 2); p3 = Vector2i(tx, gy + 3);
					}
					
					if (p0.x < 0 || p0.x >= width || p0.y < 0 || p0.y >= height || p3.x < 0 || p3.x >= width || p3.y < 0 || p3.y >= height) {
						blocked = true; break;
					}
					
					bool row_has_blocks = false;
					int m0, m1, m2, m3;
					if (orient == 0 || orient == 2) {
						int ro = p0.y * width;
						m0 = cells_ptr[ro + p0.x] & 0xFFFF; m1 = cells_ptr[ro + p1.x] & 0xFFFF;
						m2 = cells_ptr[ro + p2.x] & 0xFFFF; m3 = cells_ptr[ro + p3.x] & 0xFFFF;
					} else {
						m0 = cells_ptr[p0.y * width + p0.x] & 0xFFFF; m1 = cells_ptr[p1.y * width + p1.x] & 0xFFFF;
						m2 = cells_ptr[p2.y * width + p2.x] & 0xFFFF; m3 = cells_ptr[p3.y * width + p3.x] & 0xFFFF;
					}
					
					auto is_solid_block = [](int m) {
						return m == 93 || m == 94 || m == 193 || m == 194 || (m >= 81 && m <= 87) || m == 600;
					};
					if (is_solid_block(m0) || is_solid_block(m1) || is_solid_block(m2) || is_solid_block(m3)) {
						blocked = true; break;
					}
					
					if (m0 != 0 || m1 != 0 || m2 != 0 || m3 != 0) row_has_blocks = true;
					if (!row_has_blocks) break;
					
					push_height++;
					if (push_height > 120) { blocked = true; break; }
					step_idx++;
				}
				
				if (!blocked) {
					if (orient == 0) {
						for (int s = push_height; s >= 1; s--) {
							int ty = gy - ext - s;
							int dest_y = ty - 1;
							for (int ox = 0; ox < 4; ox++) {
								int tx = px + ox;
								if ((cells_ptr[ty * width + tx] & 0xFFFF) != 0) move_cell(tx, ty, tx, dest_y);
							}
						}
						for (int ox = 0; ox < 4; ox++) set_piston_head(px + ox, gy - ext - 1, is_insulated);
					} else if (orient == 1) {
						for (int s = push_height; s >= 1; s--) {
							int tx = px + 3 + ext + s;
							int dest_x = tx + 1;
							for (int oy = 0; oy < 4; oy++) {
								int ty = gy + oy;
								if ((cells_ptr[ty * width + tx] & 0xFFFF) != 0) move_cell(tx, ty, dest_x, ty);
							}
						}
						for (int oy = 0; oy < 4; oy++) set_piston_head(px + 3 + ext + 1, gy + oy, is_insulated);
					} else if (orient == 2) {
						for (int s = push_height; s >= 1; s--) {
							int ty = gy + 3 + ext + s;
							int dest_y = ty + 1;
							for (int ox = 0; ox < 4; ox++) {
								int tx = px + ox;
								if ((cells_ptr[ty * width + tx] & 0xFFFF) != 0) move_cell(tx, ty, tx, dest_y);
							}
						}
						for (int ox = 0; ox < 4; ox++) set_piston_head(px + ox, gy + 3 + ext + 1, is_insulated);
					} else if (orient == 3) {
						for (int s = push_height; s >= 1; s--) {
							int tx = px - ext - s;
							int dest_x = tx - 1;
							for (int oy = 0; oy < 4; oy++) {
								int ty = gy + oy;
								if ((cells_ptr[ty * width + tx] & 0xFFFF) != 0) move_cell(tx, ty, dest_x, ty);
							}
						}
						for (int oy = 0; oy < 4; oy++) set_piston_head(px - ext - 1, gy + oy, is_insulated);
					}
					
					p["current_ext"] = current_ext + 1.0f;
				}
			}
		} else {
			if (current_ext > 0) {
				int ext = (int)current_ext;
				int px = pos.x;
				int gy = pos.y;
				
				auto clear_head = [&](int tx, int ty) {
					int idx = ty * width + tx;
					if (paint_ptr[idx] != 0) paint_changed = true;
					cells_ptr[idx] = 0; tags_ptr[idx] = 0; charge_ptr[idx] = 0; paint_ptr[idx] = 0;
					int chunk_x = tx / 16; int chunk_y = ty / 16;
					int c_idx = chunk_y * chunks_x + chunk_x;
					if (c_idx >= 0 && c_idx < next_chunks_active.size() && chunks_ptr[c_idx] < 60) chunks_ptr[c_idx] = 60;
				};
				
				if (orient == 0) {
					int ty = gy - ext;
					for (int ox = 0; ox < 4; ox++) clear_head(px + ox, ty);
				} else if (orient == 1) {
					int tx = px + 3 + ext;
					for (int oy = 0; oy < 4; oy++) clear_head(tx, gy + oy);
				} else if (orient == 2) {
					int ty = gy + 3 + ext;
					for (int ox = 0; ox < 4; ox++) clear_head(px + ox, ty);
				} else if (orient == 3) {
					int tx = px - ext;
					for (int oy = 0; oy < 4; oy++) clear_head(tx, gy + oy);
				}
				
				p["current_ext"] = current_ext - 1.0f;
			}
		}
		new_active.append(p);
	}
	
	state["cells"] = cells;
	state["tags_array"] = tags_array;
	state["charge_array"] = charge_array;
	state["next_chunks_active"] = next_chunks_active;
	state["cell_paint_colors"] = cell_paint_colors;
	state["paint_changed"] = paint_changed;
	
	state["new_pistons"] = new_active;
	return state;
}

PackedInt32Array SandboxGridNode::get_special_source_indices(PackedInt32Array cells) {
	std::vector<int> special_indices;
	int size = cells.size();
	const int32_t* ptr = cells.ptr();
	for (int i = 0; i < size; ++i) {
		int32_t mid = ptr[i] & 0xFFFF;
		if (mid == 88 || mid == 9 || mid == 600 || mid == 91 || mid == 92 || 
		    mid == 93 || mid == 94 || mid == 193 || mid == 194 || mid == 194 || mid == 294 || mid == 394 ||
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
