import sys, re

filepath = 'sandbox/gdextension/src/sandbox_grid_node.cpp'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Bounds check process_electricity arrays
# phase_blocks_indices
text = text.replace(
'''	for (int i = 0; i < phase_blocks_indices.size(); ++i) {
		is_pb[int(phase_blocks_indices[i])] = true;
	}''',
'''	for (int i = 0; i < phase_blocks_indices.size(); ++i) {
		int idx = int(phase_blocks_indices[i]);
		if (idx >= 0 && idx < width * height) is_pb[idx] = true;
	}''')

# prev_charges_arr
text = text.replace(
'''	for (int i = 0; i < prev_charges_arr.size(); ++i) {
		prev_charges[int(prev_charges_arr[i])] = true;
	}''',
'''	for (int i = 0; i < prev_charges_arr.size(); ++i) {
		int idx = int(prev_charges_arr[i]);
		if (idx >= 0 && idx < width * height) prev_charges[idx] = true;
	}''')

# prev_active_music_charges_arr
text = text.replace(
'''	for (int i = 0; i < prev_active_music_charges_arr.size(); ++i) {
		prev_music[int(prev_active_music_charges_arr[i])] = true;
	}''',
'''	for (int i = 0; i < prev_active_music_charges_arr.size(); ++i) {
		int idx = int(prev_active_music_charges_arr[i]);
		if (idx >= 0 && idx < width * height) prev_music[idx] = true;
	}''')

# active_charge_indices (in_active array mapping)
text = text.replace(
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		in_active[int(active_charge_indices[i])] = true;
	}''',
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = int(active_charge_indices[i]);
		if (idx >= 0 && idx < width * height) in_active[idx] = true;
	}''')

# sources_indices array mapping
text = text.replace(
'''	for (int i = 0; i < sources_indices.size(); ++i) {
		int idx = sources_indices[i];
		charge_ptr[idx] = 100;
		charge_visual_ptr[idx] = 100;
		if (!in_active[idx]) {
			active_charge_indices.append(idx);
			in_active[idx] = true;
		}
	}''',
'''	for (int i = 0; i < sources_indices.size(); ++i) {
		int idx = sources_indices[i];
		if (idx < 0 || idx >= width * height) continue;
		charge_ptr[idx] = 100;
		charge_visual_ptr[idx] = 100;
		if (!in_active[idx]) {
			active_charge_indices.append(idx);
			in_active[idx] = true;
		}
	}''')

# active_charge_indices loop bounds check
text = text.replace(
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		if (charge_ptr[idx] == 100) {
			wave_fronts.push_back(idx);
		}
	}''',
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		if (idx < 0 || idx >= width * height) continue;
		if (charge_ptr[idx] == 100) {
			wave_fronts.push_back(idx);
		}
	}''')

text = text.replace(
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		int32_t mid = cells_ptr[idx] & 0xFFFF;''',
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		if (idx < 0 || idx >= width * height) continue;
		int32_t mid = cells_ptr[idx] & 0xFFFF;''')

text = text.replace(
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		if (charge_ptr[idx] == 0) {
			charge_visual_ptr[idx] = 0;
		}
	}''',
'''	for (int i = 0; i < active_charge_indices.size(); ++i) {
		int idx = active_charge_indices[i];
		if (idx < 0 || idx >= width * height) continue;
		if (charge_ptr[idx] == 0) {
			charge_visual_ptr[idx] = 0;
		}
	}''')

# 2. Add bounds check for mat_tags in process_physics
# Get size
text = text.replace(
'''	const int64_t* mat_tags = material_tags_raw.ptr();''',
'''	const int64_t* mat_tags = material_tags_raw.ptr();
	int mat_tags_size = material_tags_raw.size();''')

# set_cell
text = text.replace(
'''		uint64_t m_tags = (cid == 0) ? 0 : mat_tags[cid];''',
'''		uint64_t m_tags = (cid == 0 || cid >= mat_tags_size) ? 0 : mat_tags[cid];''')

# has_tag_neighbor
text = text.replace(
'''				if (nid > 0 && (mat_tags[nid] & check_tag)) return true;''',
'''				if (nid > 0 && nid < mat_tags_size && (mat_tags[nid] & check_tag)) return true;''')

# execute_explosion
text = text.replace(
'''							uint64_t m_tags = mat_tags[t_id];''',
'''							uint64_t m_tags = (t_id < mat_tags_size) ? mat_tags[t_id] : 0;''')

# ACID and FIRE
text = text.replace(
'''								uint64_t n_tags = mat_tags[nid];''',
'''								uint64_t n_tags = (nid < mat_tags_size) ? mat_tags[nid] : 0;''')

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(text)
print('Fixed bounds checking in C++')
