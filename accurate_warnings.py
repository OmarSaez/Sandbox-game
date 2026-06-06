import sys

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

def get_indent(line):
    return line[:len(line) - len(line.lstrip())]

for i in range(len(lines)):
    line = lines[i]
    if 'var lbl_icon = Label.new()' in line and i < 150:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var lbl_pct = Label.new()' in line and i < 150:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var old_id = cells[idx] & 0xFFFF' in line and i > 6680 and i < 6700:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var head_pix = _get_cell(p_head.x, p_head.y)' in line:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    elif 'var title = Label.new()' in line and i > 13160 and i < 13170:
        lines[i] = get_indent(line) + '@warning_ignore("confusable_local_declaration")\n' + line
    
    # Unused vars
    elif 'var old_cells = dict["grid"]' in line:
        lines[i] = line.replace('var old_cells', 'var _old_cells')
    elif 'var old_charge = dict["charge"]' in line:
        lines[i] = line.replace('var old_charge', 'var _old_charge')
    elif 'var old_tags = dict["tags"]' in line:
        lines[i] = line.replace('var old_tags', 'var _old_tags')
    elif 'var old_paint = dict["cell_paint"]' in line:
        lines[i] = line.replace('var old_paint', 'var _old_paint')
    elif 'var mat_color = _get_cell_color(nx, ny)' in line:
        lines[i] = line.replace('var mat_color', 'var _mat_color')
    elif 'var bx_out = 0; var by_out = 0' in line:
        lines[i] = line.replace('var bx_out = 0; var by_out = 0', 'var _bx_out = 0; var _by_out = 0')
    
    # Unused params
    elif 'func _explode(cx, cy, radius, flags, ignore_budget = false):' in line:
        lines[i] = line.replace('ignore_budget', '_ignore_budget')
    elif 'func _show_unified_tutorial_bubble(text_key: String, focus_element: Control, grid_pos: Vector2i = Vector2i(-1, -1)):' in line:
        lines[i] = line.replace('grid_pos:', '_grid_pos:')
    elif 'func _simulate_pipes(delta):' in line:
        lines[i] = line.replace('delta):', '_delta):')

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Fixed warnings')
