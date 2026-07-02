import re

with open('sandbox/scripts/sandbox/sandbox_grid.gd', 'r', encoding='utf-8') as f:
    code = f.read()

code = code.replace('const NPC_VISUALS = {', 'var NPC_VISUALS = {')

func_resolve = """
var _next_dynamic_mat_id = 2000

func _resolve_custom_npc_colors():
	for npc_key in NPC_VISUALS:
		var vis = NPC_VISUALS[npc_key]
		var pal = vis.get("palette", {})
		for k in pal.keys():
			var val = pal[k]
			if typeof(val) == TYPE_STRING:
				if val.begins_with("#"):
					var c = Color(val)
					_register_material(_next_dynamic_mat_id, c, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
					pal[k] = _next_dynamic_mat_id
					_next_dynamic_mat_id += 1
			elif typeof(val) == TYPE_ARRAY:
				var new_arr = []
				for t_val in val:
					if typeof(t_val) == TYPE_STRING and t_val.begins_with("#"):
						var c = Color(t_val)
						_register_material(_next_dynamic_mat_id, c, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
						new_arr.append(_next_dynamic_mat_id)
						_next_dynamic_mat_id += 1
					else:
						new_arr.append(t_val)
				pal[k] = new_arr
"""

if 'func _init_materials():' in code and 'func _resolve_custom_npc_colors()' not in code:
    code = code.replace('func _init_materials():', func_resolve + '\nfunc _init_materials():')
    code = code.replace('func _ready():\n\t_load_workshop_economy()', 'func _ready():\n\t_resolve_custom_npc_colors()\n\t_load_workshop_economy()')

draw_old = """	else:
		var base_p = vis["palette"]
		for k in base_p.keys():
			var val = base_p[k]
			if typeof(val) == TYPE_STRING:
				if val == "team": p[k] = 1004 + npc.team
				elif val == "team_mage": p[k] = 1074 + npc.team
			else:
				p[k] = val"""

draw_new = """	else:
		var base_p = vis["palette"]
		for k in base_p.keys():
			var val = base_p[k]
			if typeof(val) == TYPE_STRING:
				if val == "team": p[k] = 1004 + npc.team
				elif val == "team_mage": p[k] = 1074 + npc.team
				else: p[k] = val # Failsafe
			elif typeof(val) == TYPE_ARRAY:
				if npc.team >= 0 and npc.team < val.size():
					p[k] = val[npc.team]
				else:
					p[k] = val[0] # Fallback
			else:
				p[k] = val"""

if draw_old in code:
    code = code.replace(draw_old, draw_new)

with open('sandbox/scripts/sandbox/sandbox_grid.gd', 'w', encoding='utf-8') as f:
    f.write(code)

print("Patch applied successfully.")
