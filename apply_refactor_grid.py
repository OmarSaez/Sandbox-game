import re

with open('sandbox/scripts/sandbox/sandbox_grid.gd', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update NPC_VISUALS to use direct colors
old_visuals_regex = r'var NPC_VISUALS = \{.*?\n\t\}\n\}'
new_visuals = """var NPC_VISUALS = {
	"warrior": {
		"width": 5, "height": 7,
		"palette": {
			1: Color("717E80"), 2: Color("1F1F1F"), 3: Color("FFE2BD"),
			4: [Color("E00000"), Color("008EE6"), Color("FFD000"), Color("00E317")],
			5: Color("717E80")
		},
		"frames": {
			"standing": [
				[1, 1, 1, 1, 0],
				[1, 3, 2, 1, 0],
				[1, 3, 3, 3, 0],
				[4, 2, 4, 2, 0],
				[3, 4, 2, 4, 3],
				[5, 5, 5, 5, 0],
				[5, 0, 0, 5, 0]
			],
			"lying": [
				[0, 0, 0, 0, 3, 0, 0],
				[1, 2, 3, 2, 4, 5, 5],
				[1, 3, 3, 4, 2, 5, 0],
				[1, 2, 3, 2, 4, 5, 0],
				[1, 1, 1, 4, 3, 5, 5]
			]
		}
	},
	"archer": {
		"width": 5, "height": 7,
		"palette": {
			1: Color("9C5B00"), 2: Color("9D00FF"), 3: Color("FFBC78"),
			4: [Color("E00000"), Color("008EE6"), Color("FFD000"), Color("00E317")],
			5: Color("594E61")
		},
		"frames": {
			"standing": [
				[1, 1, 1, 1, 0],
				[1, 3, 2, 1, 0],
				[1, 3, 3, 3, 0],
				[4, 4, 4, 4, 0],
				[3, 4, 4, 4, 3],
				[5, 5, 5, 5, 0],
				[5, 0, 0, 5, 0]
			],
			"lying": [
				[0, 0, 0, 0, 3, 0, 0],
				[1, 2, 3, 2, 4, 5, 5],
				[1, 3, 3, 4, 2, 5, 0],
				[1, 2, 3, 2, 4, 5, 0],
				[1, 1, 1, 4, 3, 5, 5]
			]
		}
	},
	"miner": {
		"width": 5, "height": 7,
		"palette": {
			1: Color("#FFFB00"), 2: Color("#FF8D00"), 3: Color("7D522D"),
			4: [Color("E00000"), Color("008EE6"), Color("FFD000"), Color("00E317")],
			5: Color("000000")
		},
		"frames": {
			"standing": [
				[1, 1, 1, 1, 0],
				[1, 3, 2, 1, 0],
				[1, 3, 3, 3, 0],
				[4, 2, 4, 2, 0],
				[3, 4, 2, 4, 3],
				[5, 5, 5, 5, 0],
				[5, 0, 0, 5, 0]
			],
			"lying": [
				[0, 0, 0, 0, 3, 0, 0],
				[1, 2, 3, 2, 4, 5, 5],
				[1, 3, 3, 4, 2, 5, 0],
				[1, 2, 3, 2, 4, 5, 0],
				[1, 1, 1, 4, 3, 5, 5]
			]
		}
	},
	"medic": {
		"width": 5, "height": 7,
		"palette": {
			1: Color("FFFFFF"), 2: Color("EEEEEE"), 3: Color("FFA691"),
			4: [Color("E00000"), Color("008EE6"), Color("FFD000"), Color("00E317")],
			5: Color("DEDEDE"), 6: Color("7A0000")
		},
		"frames": {
			"standing": [
				[1, 1, 1, 1, 0],
				[1, 3, 2, 1, 0],
				[1, 3, 3, 3, 0],
				[4, 6, 4, 6, 0],
				[3, 4, 6, 4, 3],
				[5, 5, 5, 5, 0],
				[5, 0, 0, 5, 0]
			],
			"lying": [
				[0, 0, 0, 0, 3, 0, 0],
				[1, 2, 3, 2, 4, 5, 5],
				[1, 3, 3, 4, 2, 5, 0],
				[1, 2, 3, 2, 4, 5, 0],
				[1, 1, 1, 4, 3, 5, 5]
			]
		}
	},
	"zombie": {
		"width": 5, "height": 7,
		"palette": {
			1: Color("5D9C36"), 2: Color("4B245C"), 3: Color("5D9C36"),
			4: Color("717E80"), 5: Color("5D9C36")
		},
		"frames": {
			"standing": [
				[1, 1, 1, 1, 0],
				[1, 3, 2, 1, 0],
				[1, 3, 3, 3, 0],
				[4, 2, 4, 2, 0],
				[3, 4, 2, 4, 3],
				[5, 5, 5, 5, 0],
				[5, 0, 0, 5, 0]
			],
			"lying": [
				[0, 0, 0, 0, 3, 0, 0],
				[1, 2, 3, 2, 4, 5, 5],
				[1, 3, 3, 4, 2, 5, 0],
				[1, 2, 3, 2, 4, 5, 0],
				[1, 1, 1, 4, 3, 5, 5]
			]
		}
	},
	"zombie_tank": {
		"width": 3, "height": 6,
		"palette": {
			1: Color("4E822E"), 2: Color("361B43"), 3: Color("4E822E"),
			4: Color("555F61"), 5: Color("4E822E")
		},
		"frames": {
			"standing": [
				[1, 1, 1],
				[1, 3, 3],
				[4, 2, 2],
				[2, 4, 4],
				[4, 4, 4],
				[5, 5, 5]
			],
			"lying": [
				[1, 3, 4, 2, 4, 5],
				[1, 1, 2, 4, 4, 5],
				[1, 3, 2, 2, 4, 5]
			]
		}
	},
	"mage": {
		"width": 2, "height": 6,
		"palette": {
			1: Color("F2F2F2"), 2: Color("A83938"), 3: Color("FFD8B3"),
			4: [Color("A83938"), Color("384BA8"), Color("C79B1E"), Color("74A838")],
			5: Color("717E80")
		},
		"frames": {
			"standing": [
				[4, 4],
				[1, 3],
				[4, 1],
				[4, 1],
				[4, 1],
				[5, 5]
			],
			"lying": [
				[4, 3, 4, 4, 4, 5],
				[4, 1, 1, 1, 1, 5]
			]
		}
	}
}"""
code = re.sub(old_visuals_regex, new_visuals, code, flags=re.DOTALL)

# 2. Add LEGACY comment to _init_materials
code = code.replace('_register_material(1001, Color("717E80"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza',
                    '# LEGACY NPC MATERIALS (DO NOT REMOVE. Needed for backwards compatibility with old saves)\n\t_register_material(1001, Color("717E80"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza')

# 3. Remove _resolve_custom_npc_colors function completely
resolve_func_regex = r'var _next_dynamic_mat_id = 2000.*?func _resolve_custom_npc_colors\(\):.*?elif typeof\(val\) == TYPE_ARRAY:.*?\n\t\t\t\tpal\[k\] = new_arr\n'
code = re.sub(resolve_func_regex, '', code, flags=re.DOTALL)
code = code.replace('\t_resolve_custom_npc_colors()\n', '')

# 4. Modify _draw_npc_pixels
draw_old = """	var p = {}
	if override_mat != -1:
		for k in range(1, 10): p[k] = override_mat
	elif is_flashing:
		var f_mat = 1033; if is_dead: f_mat = 1034
		elif npc.hit_type == "acid": f_mat = 1030
		elif npc.hit_type == "fire": f_mat = 1031
		elif npc.hit_type == "explosive": f_mat = 1032
		elif npc.hit_type == "electric": f_mat = 1035
		for k in range(1, 10): p[k] = f_mat
	else:
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
				p[k] = val
				
	# 2. Dibujar Matriz (Data-Driven)
	var frames = vis["frames"]
	var matrix = frames["lying"] if is_lying else frames["standing"]
	
	var h = matrix.size()
	var w = matrix[0].size() if h > 0 else 0
	
	for oy in range(h):
		var row = matrix[oy]
		for ox in range(w):
			var mat_key = row[ox]
			if mat_key != 0:
				var px = sx + ox if face_dir > 0 else sx + (w - 1 - ox)
				var py = sy + oy
				if is_lying:
					# Ajustar la altura al acostarse para que repose en el suelo
					py = sy + (vis["height"] - h) + oy
				_set_cell(px, py, p[mat_key])"""

draw_new = """	var master_mat_id = 1000
	if npc.type == "archer": master_mat_id = 1010
	elif npc.type == "miner": master_mat_id = 1020
	elif npc.type == "mage": master_mat_id = 1070
	elif npc.type == "zombie" or npc.type == "zombie_tank": master_mat_id = 1080
	elif npc.type == "medic": master_mat_id = 1040 # Assume 1040 is medic master if exists, else it will use 1000 logic for physics
	
	var p = {}
	if override_mat != -1:
		for k in range(1, 10): p[k] = _get_color_from_mat_id(override_mat)
	elif is_flashing:
		var f_mat = 1033; if is_dead: f_mat = 1034
		elif npc.hit_type == "acid": f_mat = 1030
		elif npc.hit_type == "fire": f_mat = 1031
		elif npc.hit_type == "explosive": f_mat = 1032
		elif npc.hit_type == "electric": f_mat = 1035
		for k in range(1, 10): p[k] = _get_color_from_mat_id(f_mat)
	else:
		var base_p = vis["palette"]
		for k in base_p.keys():
			var val = base_p[k]
			if typeof(val) == TYPE_ARRAY:
				if npc.team >= 0 and npc.team < val.size():
					p[k] = val[npc.team]
				else:
					p[k] = val[0] # Fallback
			else:
				p[k] = val
				
	# 2. Dibujar Matriz (Data-Driven)
	var frames = vis["frames"]
	var matrix = frames["lying"] if is_lying else frames["standing"]
	
	var h = matrix.size()
	var w = matrix[0].size() if h > 0 else 0
	
	for oy in range(h):
		var row = matrix[oy]
		for ox in range(w):
			var mat_key = row[ox]
			if mat_key != 0:
				var px = sx + ox if face_dir > 0 else sx + (w - 1 - ox)
				var py = sy + oy
				if is_lying:
					# Ajustar la altura al acostarse para que repose en el suelo
					py = sy + (vis["height"] - h) + oy
				_set_cell(px, py, master_mat_id)
				var c = p[mat_key]
				if typeof(c) == TYPE_COLOR:
					cell_paint_colors[py * grid_width + px] = _color_to_abgr32(c)"""
					
code = code.replace(draw_old, draw_new)

# Add _get_color_from_mat_id if it doesn't exist (it doesn't natively return Color for hit flashes).
get_color_func = """
func _get_color_from_mat_id(id: int) -> Color:
	var pure_id = id & 0xFFFF
	if mat_colors_1.has(pure_id): return mat_colors_1[pure_id]
	return Color.WHITE
"""
if "func _get_color_from_mat_id" not in code:
    code += get_color_func

with open('sandbox/scripts/sandbox/sandbox_grid.gd', 'w', encoding='utf-8') as f:
    f.write(code)

print("Patch applied to sandbox_grid.gd successfully.")
