import sys, re

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

# 3. mat_color unused at 10577 (which is now around 10579)
text = text.replace('var mat_color = mat_colors_1[mat] if mat < mat_colors_1.size() else Color("#717E80")', 'var _mat_color = mat_colors_1[mat] if mat < mat_colors_1.size() else Color("#717E80")')
text = text.replace('var _mat_color = mat_colors_1[mat] if mat < mat_colors_1.size() else Color("#717E80")\n\t\t\t\t\t\t_add_spark(float(gx) + _get_lut_rand_range(-1, 2), float(gy) + _get_lut_rand_range(-1, 2), _get_lut_rand_range(-80, 80), _get_lut_rand_range(-100, -30), mat_color', 'var mat_color = mat_colors_1[mat] if mat < mat_colors_1.size() else Color("#717E80")\n\t\t\t\t\t\t_add_spark(float(gx) + _get_lut_rand_range(-1, 2), float(gy) + _get_lut_rand_range(-1, 2), _get_lut_rand_range(-80, 80), _get_lut_rand_range(-100, -30), mat_color')

# 4. ignore_budget unused parameter
text = text.replace('ignore_budget = false', '_ignore_budget = false')

# 5. bx_out unused variable
text = text.replace('var bx_out = (cx + pin_out_c) * 4', 'var _bx_out = (cx + pin_out_c) * 4')

# 6. by_out unused variable
text = text.replace('var by_out = (cy + pin_out_r) * 4', 'var _by_out = (cy + pin_out_r) * 4')

# 7. grid_pos unused parameter
text = text.replace('func _show_unified_tutorial_bubble(grid_pos: Vector2i, text_key: String', 'func _show_unified_tutorial_bubble(_grid_pos: Vector2i, text_key: String')

# 8. delta unused parameter
text = text.replace('func _simulate_pipes(delta: float):', 'func _simulate_pipes(_delta: float):')


with open(filepath, 'w', encoding='utf-8') as f:
    f.write(text)
print('Fixed user screenshot exactly remaining')
