import sys, re

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Unused variables
text = text.replace('var old_cells = dict["grid"]', 'var _old_cells = dict["grid"]')
text = text.replace('var old_charge = dict["charge"]', 'var _old_charge = dict["charge"]')
text = text.replace('var old_tags = dict["tags"]', 'var _old_tags = dict["tags"]')
text = text.replace('var old_paint = dict["cell_paint"]', 'var _old_paint = dict["cell_paint"]')

text = text.replace('var mat_color = _get_cell_color(nx, ny)', 'var _mat_color = _get_cell_color(nx, ny)')
text = text.replace('func _explode(cx, cy, radius, flags, ignore_budget = false):', 'func _explode(cx, cy, radius, flags, _ignore_budget = false):')
text = text.replace('var bx_out = 0; var by_out = 0', 'var _bx_out = 0; var _by_out = 0')
text = text.replace('func _show_unified_tutorial_bubble(text_key: String, focus_element: Control, grid_pos: Vector2i = Vector2i(-1, -1)):', 'func _show_unified_tutorial_bubble(text_key: String, focus_element: Control, _grid_pos: Vector2i = Vector2i(-1, -1)):')
text = text.replace('func _simulate_pipes(delta):', 'func _simulate_pipes(_delta):')

# 2. Confusable Declarations
# Safely rename lbl_icon, lbl_pct without breaking the whole file!
text = text.replace('var lbl_icon = Label.new()\n\t\t\t\tlbl_icon.text', 'var _lbl_icon_c = Label.new()\n\t\t\t\t_lbl_icon_c.text')
text = text.replace('_lbl_icon_c.text = " [color=#ff0000]!" if failed else " [color=#00ff00]✔"\n\t\t\t\tlbl_icon.add_theme', '_lbl_icon_c.text = " [color=#ff0000]!" if failed else " [color=#00ff00]✔"\n\t\t\t\t_lbl_icon_c.add_theme')
text = text.replace('_lbl_icon_c.add_theme_font_size_override("font_size", 14)\n\t\t\t\tlbl_icon.add_theme', '_lbl_icon_c.add_theme_font_size_override("font_size", 14)\n\t\t\t\t_lbl_icon_c.add_theme')
text = text.replace('_lbl_icon_c.add_theme_constant_override("outline_size", 4)\n\t\t\t\tvbox.add_child(lbl_icon)', '_lbl_icon_c.add_theme_constant_override("outline_size", 4)\n\t\t\t\tvbox.add_child(_lbl_icon_c)')

text = text.replace('var lbl_pct = Label.new()\n\t\t\t\t\tlbl_pct.text', 'var _lbl_pct_c = Label.new()\n\t\t\t\t\t_lbl_pct_c.text')
text = text.replace('_lbl_pct_c.text = "(" + str(int(pct)) + "%)"\n\t\t\t\t\tlbl_pct.add_theme', '_lbl_pct_c.text = "(" + str(int(pct)) + "%)"\n\t\t\t\t\t_lbl_pct_c.add_theme')
text = text.replace('_lbl_pct_c.add_theme_font_size_override("font_size", 12)\n\t\t\t\t\tlbl_pct.add_theme', '_lbl_pct_c.add_theme_font_size_override("font_size", 12)\n\t\t\t\t\t_lbl_pct_c.add_theme')
text = text.replace('_lbl_pct_c.add_theme_constant_override("outline_size", 3)\n\t\t\t\t\tvbox.add_child(lbl_pct)', '_lbl_pct_c.add_theme_constant_override("outline_size", 3)\n\t\t\t\t\tvbox.add_child(_lbl_pct_c)')

text = text.replace('var old_id = cells[idx] & 0xFFFF\n\t\t\tif old_id', 'var _old_id_c = cells[idx] & 0xFFFF\n\t\t\tif _old_id_c')
text = text.replace('if _old_id_c == 600: active_metronome_indices.erase(idx)\n\t\t\telif old_id', 'if _old_id_c == 600: active_metronome_indices.erase(idx)\n\t\t\telif _old_id_c')
text = text.replace('elif _old_id_c == 88: active_battery_indices.erase(idx)\n\t\t\telif old_id', 'elif _old_id_c == 88: active_battery_indices.erase(idx)\n\t\t\telif _old_id_c')
text = text.replace('elif _old_id_c == 9: active_electricity_source_indices.erase(idx)\n\t\t\tif old_id', 'elif _old_id_c == 9: active_electricity_source_indices.erase(idx)\n\t\t\tif _old_id_c')
text = text.replace('if _old_id_c == 91 and not is_npc_door_updating:\n\t\t\t\t_trigger_door_update(x, y)\n\t\t\tif old_id', 'if _old_id_c == 91 and not is_npc_door_updating:\n\t\t\t\t_trigger_door_update(x, y)\n\t\t\tif _old_id_c')

text = text.replace('var old_id = cells[idx] & 0xFFFF\n\t\tif old_id', 'var _old_id_c = cells[idx] & 0xFFFF\n\t\tif _old_id_c')
text = text.replace('if _old_id_c == 600: active_metronome_indices.erase(idx)\n\t\telif old_id', 'if _old_id_c == 600: active_metronome_indices.erase(idx)\n\t\telif _old_id_c')
text = text.replace('elif _old_id_c == 88: active_battery_indices.erase(idx)\n\t\telif old_id', 'elif _old_id_c == 88: active_battery_indices.erase(idx)\n\t\telif _old_id_c')
text = text.replace('elif _old_id_c == 9: active_electricity_source_indices.erase(idx)\n\t\tif old_id', 'elif _old_id_c == 9: active_electricity_source_indices.erase(idx)\n\t\tif _old_id_c')
text = text.replace('if _old_id_c == 91 and not is_npc_door_updating:\n\t\t\t_trigger_door_update(x, y)\n\t\tif old_id', 'if _old_id_c == 91 and not is_npc_door_updating:\n\t\t\t_trigger_door_update(x, y)\n\t\tif _old_id_c')

text = text.replace('var head_pix = _get_cell(p_head.x, p_head.y)\n\t\t\t\t\t\tif head_pix', 'var _head_pix_c = _get_cell(p_head.x, p_head.y)\n\t\t\t\t\t\tif _head_pix_c')

text = text.replace('var title = Label.new()\n\ttitle.text = dict["name"]\n\ttitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER\n\ttitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n\ttitle.add_theme_font_size_override("font_size", 16)\n\ttitle_hbox.add_child(title)', 'var _title_c = Label.new()\n\t_title_c.text = dict["name"]\n\t_title_c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER\n\t_title_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n\t_title_c.add_theme_font_size_override("font_size", 16)\n\ttitle_hbox.add_child(_title_c)')

# 3. Dead code deletion
# Lines 6978 to 6998
text = re.sub(r'\t\t\t\t\t\t\t\t# === COMENTADO FASE 2: GRAVEDAD EN C\+\+ ===.*?\t\t\t\t\t\t\t\t# =========================================\n', '', text, flags=re.DOTALL)

# Lines 7406 to 7407
text = re.sub(r'\t# EXPLOSIVE TIMER \(TNT/Gunpowder\) - Movido a C\+\+ \(Fase 3\)\n\telif pure_id == 7 or pure_id == 77 or pure_id == 71 or pure_id == 72:\n\t\tpass\n', '', text)

# Lines 7454 to 7472
text = re.sub(r'\t# VOLATILE INERTIA \(Projectiles like Sparks\)\n\t# MOVIDO A C\+\+ FASE 3\n\tpass\n', '', text)
text = re.sub(r'\t# --- CORROSION \(ACID\) ---\n\t# MOVIDO A C\+\+ FASE 3\n\tpass\n\t# if \(tags & SandboxMaterial\.Tags\.ACID\):.*?# \t\t\t\t\t\tif \(n_tags & SandboxMaterial\.Tags\.SOLID\) and _get_lut_rand\(\) < 0\.1: _set_cell\(x, y, 0\); return\n', '', text, flags=re.DOTALL)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(text)
print('Applied safe replaces')
