import re

with open('sandbox/scripts/sandbox/npc_editor.gd', 'r', encoding='utf-8') as f:
    code = f.read()

# Modify _on_export_pressed in npc_editor.gd
export_old = """	for i in range(1, 10):
		if used_indices.has(i):
			var mapped = _get_mat_id_for_color(custom_base_colors[i])
			if typeof(mapped) == TYPE_STRING: pal_str += "%d: %s, " % [i, mapped]
			else: pal_str += "%d: %d, " % [i, mapped]
			
	for i in range(10, 13):
		if used_indices.has(i):
			var is_standard_team = true
			var is_standard_mage = true
			for t in range(4):
				if not custom_team_colors[t][i].is_equal_approx(_get_standard_team_color(t, "team")):
					is_standard_team = false
				if not custom_team_colors[t][i].is_equal_approx(_get_standard_team_color(t, "team_mage")):
					is_standard_mage = false
					
			if is_standard_team:
				pal_str += "%d: \\\"team\\\", " % i
			elif is_standard_mage:
				pal_str += "%d: \\\"team_mage\\\", " % i
			else:
				var arr_str = "["
				for t in range(4):
					arr_str += "\\\"#%s\\\"" % custom_team_colors[t][i].to_html(false)
					if t < 3: arr_str += ", "
				arr_str += "]"
				pal_str += "%d: %s, " % [i, arr_str]"""

export_new = """	for i in range(1, 10):
		if used_indices.has(i):
			pal_str += "%d: Color(\\\"%s\\\"), " % [i, custom_base_colors[i].to_html(false)]
			
	for i in range(10, 13):
		if used_indices.has(i):
			var arr_str = "["
			for t in range(4):
				arr_str += "Color(\\\"%s\\\")" % custom_team_colors[t][i].to_html(false)
				if t < 3: arr_str += ", "
			arr_str += "]"
			pal_str += "%d: %s, " % [i, arr_str]"""

code = code.replace(export_old, export_new)

# Also remove _get_mat_id_for_color since it's no longer used
mat_id_func_regex = r'func _get_mat_id_for_color.*?return "\\\\\\"#".*?"\\\\\\""\n'
code = re.sub(mat_id_func_regex, '', code, flags=re.DOTALL)

with open('sandbox/scripts/sandbox/npc_editor.gd', 'w', encoding='utf-8') as f:
    f.write(code)

print("npc_editor.gd updated successfully.")
