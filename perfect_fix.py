import sys

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

replaces = [
    ('var c_idx = (Engine.get_frames_drawn() / 15) % colors.size()', 'var c_idx = int(Engine.get_frames_drawn() / 15.0) % colors.size()'),
    ('var cx = prev_snapped_gx / snap', 'var cx = int(prev_snapped_gx / float(snap))'),
    ('var cy = prev_snapped_gy / snap', 'var cy = int(prev_snapped_gy / float(snap))'),
    ('var target_cx = gx / snap', 'var target_cx = int(gx / float(snap))'),
    ('var target_cy = gy / snap', 'var target_cy = int(gy / float(snap))'),
    ('var cx = gx / snap', 'var cx = int(gx / float(snap))'),
    ('var cy = gy / snap', 'var cy = int(gy / float(snap))'),
    ('(_ai_tick_count / 10) % 2', 'int(_ai_tick_count / 10.0) % 2'),
    ('var py2 = idx / grid_width', 'var py2 = int(idx / float(grid_width))'),
    ('var max_tx = grid_width / 4', 'var max_tx = int(grid_width / 4.0)'),
    ('var max_ty = grid_height / 4', 'var max_ty = int(grid_height / 4.0)'),
    ('var old_y = old_idx / old_w', 'var old_y = int(old_idx / float(old_w))'),
    ('var py = idx / grid_width', 'var py = int(idx / float(grid_width))'),
    ('var orient = (mid - 95) / 100', 'var orient = int((mid - 95) / 100.0)'),
    ('var py = idx_pt / grid_width', 'var py = int(idx_pt / float(grid_width))'),
    ('var start_cx = px / 4', 'var start_cx = int(px / 4.0)'),
    ('var end_cx = (px + 4) / 4', 'var end_cx = int((px + 4) / 4.0)'),
    ('var start_cy = clamp((gy - 64) / 4, 0, grid_height / 4)', 'var start_cy = clamp(int((gy - 64) / 4.0), 0, int(grid_height / 4.0))'),
    ('var end_cy = clamp((gy + 16) / 4, 0, grid_height / 4)', 'var end_cy = clamp(int((gy + 16) / 4.0), 0, int(grid_height / 4.0))'),
    ('int(block_size / 2)', 'int(block_size / 2.0)')
]

for old, new in replaces:
    text = text.replace(old, new)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(text)
