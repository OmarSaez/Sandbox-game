import sys, re

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

def get_indent(line):
    return line[:len(line) - len(line.lstrip())]

for i in range(len(lines)):
    line = lines[i]
    
    # Unused variables
    if 'var old_cells = dict["grid"]' in line:
        lines[i] = line.replace('var old_cells', 'var _old_cells')
    elif 'var old_charge = dict["charge"]' in line:
        lines[i] = line.replace('var old_charge', 'var _old_charge')
    elif 'var old_tags = dict["tags"]' in line:
        lines[i] = line.replace('var old_tags', 'var _old_tags')
    elif 'var old_paint = dict["cell_paint"]' in line:
        lines[i] = line.replace('var old_paint', 'var _old_paint')
    elif 'var bx_out = (cx + pin_out_c) * 4' in line:
        lines[i] = line.replace('var bx_out', 'var _bx_out')
    elif 'var by_out = (cy + pin_out_r) * 4' in line:
        lines[i] = line.replace('var by_out', 'var _by_out')
    elif re.search(r'var mat_color(\s*=\s*mat_colors_1\[mat\] if mat < mat_colors_1\.size\(\) else Color\("#717E80"\))', line):
        lines[i] = re.sub(r'var mat_color(\s*=)', r'var _mat_color\1', line)
    
    # Unused parameters
    elif 'func _explode(x, y, radius, sfx_action: String = "explosion", ignition_flags = 0, ignore_budget = false, volume_boost: float = 0.0):' in line:
        lines[i] = line.replace('ignore_budget', '_ignore_budget')
    elif 'func _show_unified_tutorial_bubble(grid_pos: Vector2i, text_key: String, on_got_it: Callable, border_color: Color, bubble_h_unscaled: float)' in line:
        lines[i] = line.replace('grid_pos', '_grid_pos')
    elif 'func _simulate_pipes(delta: float):' in line:
        lines[i] = line.replace('delta', '_delta')
        
    # Confusable variables (Add Warning Ignore precisely)
    elif 'var lbl_icon = Label.new()' in line and i < 150:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var lbl_pct = Label.new()' in line and i < 150:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var old_id = cells[idx] & 0xFFFF' in line and (i > 6680 and i < 6740):
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var head_pix = _get_cell(p_head.x, p_head.y)' in line:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var title = Label.new()' in line and (i > 13160 and i < 13170):
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
        
    # Integer Division fixes safely without warning ignore
    elif 'var c_idx = (Engine.get_frames_drawn() / 15) % colors.size()' in line:
        lines[i] = line.replace('Engine.get_frames_drawn() / 15', 'int(Engine.get_frames_drawn() / 15.0)')
    elif 'var cx = prev_snapped_gx / snap' in line:
        lines[i] = line.replace('prev_snapped_gx / snap', 'int(prev_snapped_gx / float(snap))')
    elif 'var cy = prev_snapped_gy / snap' in line:
        lines[i] = line.replace('prev_snapped_gy / snap', 'int(prev_snapped_gy / float(snap))')
    elif 'var target_cx = gx / snap' in line:
        lines[i] = line.replace('gx / snap', 'int(gx / float(snap))')
    elif 'var target_cy = gy / snap' in line:
        lines[i] = line.replace('gy / snap', 'int(gy / float(snap))')
    elif 'var cx = gx / snap' in line:
        lines[i] = line.replace('gx / snap', 'int(gx / float(snap))')
    elif 'var cy = gy / snap' in line:
        lines[i] = line.replace('gy / snap', 'int(gy / float(snap))')
    elif 'var alt_emoji = "✨" if (_ai_tick_count / 10) % 2 == 0 else "🔥"' in line:
        lines[i] = line.replace('(_ai_tick_count / 10)', 'int(_ai_tick_count / 10.0)')
    elif 'var py2 = idx / grid_width' in line:
        lines[i] = line.replace('idx / grid_width', 'int(idx / float(grid_width))')
    elif 'var max_tx = grid_width / 4' in line:
        lines[i] = line.replace('grid_width / 4', 'int(grid_width / 4.0)')
    elif 'var max_ty = grid_height / 4' in line:
        lines[i] = line.replace('grid_height / 4', 'int(grid_height / 4.0)')
    elif 'var old_y = old_idx / old_w' in line:
        lines[i] = line.replace('old_idx / old_w', 'int(old_idx / float(old_w))')
    elif 'var py = idx / grid_width' in line:
        lines[i] = line.replace('idx / grid_width', 'int(idx / float(grid_width))')
    elif 'var orient = (mid - 95) / 100' in line:
        lines[i] = line.replace('(mid - 95) / 100', 'int((mid - 95) / 100.0)')
    elif 'var py = idx_pt / grid_width' in line:
        lines[i] = line.replace('idx_pt / grid_width', 'int(idx_pt / float(grid_width))')
    elif 'var start_cx = px / 4' in line:
        lines[i] = line.replace('px / 4', 'int(px / 4.0)')
    elif 'var end_cx = (px + 4) / 4' in line:
        lines[i] = line.replace('(px + 4) / 4', 'int((px + 4) / 4.0)')
    elif 'var start_cy = clamp((gy - 64) / 4, 0, grid_height / 4)' in line:
        lines[i] = line.replace('(gy - 64) / 4', 'int((gy - 64) / 4.0)').replace('grid_height / 4', 'int(grid_height / 4.0)')
    elif 'var end_cy = clamp((gy + 16) / 4, 0, grid_height / 4)' in line:
        lines[i] = line.replace('(gy + 16) / 4', 'int((gy + 16) / 4.0)').replace('grid_height / 4', 'int(grid_height / 4.0)')
    elif 'ej_y = pt.y + int(block_size / 2)' in line:
        lines[i] = line.replace('block_size / 2', 'block_size / 2.0')
    elif 'ej_x = pt.x + int(block_size / 2)' in line:
        lines[i] = line.replace('block_size / 2', 'block_size / 2.0')

text = "".join(lines)

# Delete dead code blocks
text = re.sub(r'\t\t\t\t\t\t\t\t# === COMENTADO FASE 2: GRAVEDAD EN C\+\+ ===.*?\t\t\t\t\t\t\t\t# =========================================\n', '', text, flags=re.DOTALL)
text = re.sub(r'\t# EXPLOSIVE TIMER \(TNT/Gunpowder\) - Movido a C\+\+ \(Fase 3\)\n\telif pure_id == 7 or pure_id == 77 or pure_id == 71 or pure_id == 72:\n\t\tpass\n', '', text)
text = re.sub(r'\t# VOLATILE INERTIA \(Projectiles like Sparks\)\n\t# MOVIDO A C\+\+ FASE 3\n\tpass\n', '', text)
text = re.sub(r'\t# --- CORROSION \(ACID\) ---\n\t# MOVIDO A C\+\+ FASE 3\n\tpass\n\t# if \(tags & SandboxMaterial\.Tags\.ACID\):.*?# \t\t\t\t\t\tif \(n_tags & SandboxMaterial\.Tags\.SOLID\) and _get_lut_rand\(\) < 0\.1: _set_cell\(x, y, 0\); return\n', '', text, flags=re.DOTALL)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(text)
print('Fixed all correctly')
