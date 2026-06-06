import sys, re

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Revert _old_id_c back to old_id, then add warning ignore
text = text.replace('_old_id_c', 'old_id')
text = text.replace('var old_id = cells[idx] & 0xFFFF', '@warning_ignore("confusable_local_declaration")\n\t\t\tvar old_id = cells[idx] & 0xFFFF')
# Deduplicate multiple @warning_ignore just in case
text = text.replace('@warning_ignore("confusable_local_declaration")\n\t\t\t@warning_ignore("confusable_local_declaration")', '@warning_ignore("confusable_local_declaration")')

# 2. mat_color at 10577
text = re.sub(r'var mat_color(\s*=\s*mat_colors_1\[mat\] if mat < mat_colors_1\.size\(\) else Color\("#717E80"\))', r'var _mat_color\1', text)

# 3. ignore_budget
text = text.replace('ignore_budget = false', '_ignore_budget = false')

# 4 & 5. bx_out and by_out
text = text.replace('var bx_out = (cx + pin_out_c) * 4', 'var _bx_out = (cx + pin_out_c) * 4')
text = text.replace('var by_out = (cy + pin_out_r) * 4', 'var _by_out = (cy + pin_out_r) * 4')

# 6. head_pix
text = text.replace('var head_pix = _get_cell(p_head.x, p_head.y)', '@warning_ignore("confusable_local_declaration")\n\t\t\t\t\t\tvar head_pix = _get_cell(p_head.x, p_head.y)')

# 7. grid_pos
text = text.replace('grid_pos: Vector2i, text_key: String', '_grid_pos: Vector2i, text_key: String')

# 8. delta
text = text.replace('func _simulate_pipes(delta: float):', 'func _simulate_pipes(_delta: float):')

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(text)
print('Fixed remaining issues')
