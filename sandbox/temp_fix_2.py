import re

path = 'c:/Users/omaez/OneDrive/Escritorio/Proyecto juego/Sandbox-game/sandbox/scripts/sandbox/sandbox_grid.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

pipe1_code = """func _update_pipe_visuals(p, pass_index = -1):
	var path = p.path
	var L = path.size()
	
	var phase = _frame_count % 10
	var flow_dir = p.get("flow_dir", 0)
	
	if pass_index == -1 or pass_index == 0:
		is_hollowing_pipe = true
		
		# First pass: static pipe structure (walls + air core 0)
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			# Find connections to adjacent blocks in path
			var has_left_conn = false
			var has_right_conn = false
			var has_top_conn = false
			var has_bottom_conn = false
			
			if i > 0:
				var prev = path[i - 1]
				if prev.x == pt.x - 4 and prev.y == pt.y: has_left_conn = true
				elif prev.x == pt.x + 4 and prev.y == pt.y: has_right_conn = true
				elif prev.x == pt.x and prev.y == pt.y - 4: has_top_conn = true
				elif prev.x == pt.x and prev.y == pt.y + 4: has_bottom_conn = true
			if i < L - 1:
				var next = path[i + 1]
				if next.x == pt.x - 4 and next.y == pt.y: has_left_conn = true
				elif next.x == pt.x + 4 and next.y == pt.y: has_right_conn = true
				elif next.x == pt.x and next.y == pt.y - 4: has_top_conn = true
				elif next.x == pt.x and next.y == pt.y + 4: has_bottom_conn = true
				
			# Open visual endpoints opposite to connections
			var is_left_open = has_left_conn
			var is_right_open = has_right_conn
			var is_top_open = has_top_conn
			var is_bottom_open = has_bottom_conn
			
			if L == 1:
				is_left_open = true
				is_right_open = true
			else:
				if i == 0 or i == L - 1:
					var conn_count = int(has_left_conn) + int(has_right_conn) + int(has_top_conn) + int(has_bottom_conn)
					if conn_count == 1:
						if has_left_conn: is_right_open = true
						elif has_right_conn: is_left_open = true
						elif has_top_conn: is_bottom_open = true
						elif has_bottom_conn: is_top_open = true
						
			# Draw outer pipe walls (96) and empty cores/openings
			_set_cell(gx, gy, 96)
			_set_cell(gx + 3, gy, 96)
			_set_cell(gx, gy + 3, 96)
			_set_cell(gx + 3, gy + 3, 96)
			
			if is_top_open:
				_set_cell(gx + 1, gy, 0)
				_set_cell(gx + 2, gy, 0)
			else:
				_set_cell(gx + 1, gy, 96)
				_set_cell(gx + 2, gy, 96)
				
			if is_bottom_open:
				_set_cell(gx + 1, gy + 3, 0)
				_set_cell(gx + 2, gy + 3, 0)
			else:
				_set_cell(gx + 1, gy + 3, 96)
				_set_cell(gx + 2, gy + 3, 96)
				
			if is_left_open:
				_set_cell(gx, gy + 1, 0)
				_set_cell(gx, gy + 2, 0)
			else:
				_set_cell(gx, gy + 1, 96)
				_set_cell(gx, gy + 2, 96)
				
			if is_right_open:
				_set_cell(gx + 3, gy + 1, 0)
				_set_cell(gx + 3, gy + 2, 0)
			else:
				_set_cell(gx + 3, gy + 1, 96)
				_set_cell(gx + 3, gy + 2, 96)
				
			# Draw inner core (0)
			_set_cell(gx + 1, gy + 1, 0)
			_set_cell(gx + 2, gy + 1, 0)
			_set_cell(gx + 1, gy + 2, 0)
			_set_cell(gx + 2, gy + 2, 0)

		is_hollowing_pipe = false

	if pass_index == -1 or pass_index == 1:
		# Second pass: draw traveling elements at interpolated position
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			var elems = p.elements[i]
			if elems.size() == 0: continue
			
			# Compute interpolation target
			var next_pt = pt
			if flow_dir == 1:
				if i < L - 1:
					next_pt = path[i + 1]
				else:
					next_pt = pt
			elif flow_dir == -1:
				if i > 0:
					next_pt = path[i - 1]
				else:
					next_pt = pt
					
			var offset = Vector2i(0, 0)
			if flow_dir != 0:
				var diff = next_pt - pt
				offset = Vector2i(
					int(round(float(diff.x) / 10.0 * float(phase))),
					int(round(float(diff.y) / 10.0 * float(phase)))
				)
				
			var is_horizontal = false
			if i > 0:
				var prev = path[i - 1]
				if prev.x != pt.x: is_horizontal = true
			elif i < L - 1:
				var next = path[i + 1]
				if next.x != pt.x: is_horizontal = true
			else:
				is_horizontal = true
				
			var count = 0
			for elem in elems:
				var mat = elem.mat
				if mat > 0:
					var cx = count % 4
					var cy = count / 4
					if is_horizontal:
						var tx = gx + cx + offset.x
						if flow_dir == -1: tx = gx + 3 - cx + offset.x
						var ty = gy + 1 + cy + offset.y
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 96: _set_cell(tx, ty, mat)
					else:
						var ty = gy + cx + offset.y
						if flow_dir == -1: ty = gy + 3 - cx + offset.y
						var tx = gx + 1 + cy + offset.x
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 96: _set_cell(tx, ty, mat)
				count += 1
"""

pipe2_code = """func _update_pipe_x2_visuals(p, pass_index = -1):
	var path = p.path
	var L = path.size()
	
	var phase = _frame_count % 10
	var flow_dir = p.get("flow_dir", 0)
	
	if pass_index == -1 or pass_index == 0:
		# First pass: draw static structures (walls and cores set to 0)
		is_hollowing_pipe = true
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			# Find connections to adjacent blocks in path
			var has_left_conn = false
			var has_right_conn = false
			var has_top_conn = false
			var has_bottom_conn = false
			
			if i > 0:
				var prev = path[i - 1]
				if prev.x == pt.x - 8 and prev.y == pt.y: has_left_conn = true
				elif prev.x == pt.x + 8 and prev.y == pt.y: has_right_conn = true
				elif prev.x == pt.x and prev.y == pt.y - 8: has_top_conn = true
				elif prev.x == pt.x and prev.y == pt.y + 8: has_bottom_conn = true
			if i < L - 1:
				var next = path[i + 1]
				if next.x == pt.x - 8 and next.y == pt.y: has_left_conn = true
				elif next.x == pt.x + 8 and next.y == pt.y: has_right_conn = true
				elif next.x == pt.x and next.y == pt.y - 8: has_top_conn = true
				elif next.x == pt.x and next.y == pt.y + 8: has_bottom_conn = true
				
			var is_left_open = has_left_conn
			var is_right_open = has_right_conn
			var is_top_open = has_top_conn
			var is_bottom_open = has_bottom_conn
			
			if L == 1:
				is_left_open = true
				is_right_open = true
			else:
				if i == 0 or i == L - 1:
					var conn_count = int(has_left_conn) + int(has_right_conn) + int(has_top_conn) + int(has_bottom_conn)
					if conn_count == 1:
						if has_left_conn: is_right_open = true
						elif has_right_conn: is_left_open = true
						elif has_top_conn: is_bottom_open = true
						elif has_bottom_conn: is_top_open = true
						
			# Fill block with wall (97)
			for dy in range(8):
				for dx in range(8):
					_set_cell(gx + dx, gy + dy, 97)
					
			# Clear core to empty (0)
			for dy in range(2, 6):
				for dx in range(2, 6):
					_set_cell(gx + dx, gy + dy, 0)
					
			# Open visual endpoints
			if is_top_open:
				for dy in range(2):
					for dx in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)
			if is_bottom_open:
				for dy in range(6, 8):
					for dx in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)
			if is_left_open:
				for dx in range(2):
					for dy in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)
			if is_right_open:
				for dx in range(6, 8):
					for dy in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)

		is_hollowing_pipe = false

	if pass_index == -1 or pass_index == 1:
		# Second pass: draw elements at their interpolated positions
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			var block_elems = p.elements[i] if (p.has("elements") and i < p.elements.size()) else []
			if block_elems.size() == 0: continue
			
			var is_horizontal = false
			if i > 0:
				var prev = path[i - 1]
				if prev.x != pt.x: is_horizontal = true
			elif i < L - 1:
				var next = path[i + 1]
				if next.x != pt.x: is_horizontal = true
			else:
				is_horizontal = true
				
			# Compute interpolation target
			var next_pt = pt
			if flow_dir == 1:
				if i < L - 1:
					next_pt = path[i + 1]
				else:
					var side = _find_pipe_x2_endpoint_opening_side(p, i)
					var _ejection_dir = Vector2i(0, 0)
					if side == "bottom" or side == "horizontal": _ejection_dir = Vector2i(0, 1)
					elif side == "top": _ejection_dir = Vector2i(0, -1)
					elif side == "left": _ejection_dir = Vector2i(-1, 0)
					elif side == "right": _ejection_dir = Vector2i(1, 0)
					next_pt = pt
			elif flow_dir == -1:
				if i > 0:
					next_pt = path[i - 1]
				else:
					var side = _find_pipe_x2_endpoint_opening_side(p, i)
					var _ejection_dir = Vector2i(0, 0)
					if side == "bottom" or side == "horizontal": _ejection_dir = Vector2i(0, 1)
					elif side == "top": _ejection_dir = Vector2i(0, -1)
					elif side == "left": _ejection_dir = Vector2i(-1, 0)
					elif side == "right": _ejection_dir = Vector2i(1, 0)
					next_pt = pt
					
			var offset = Vector2i(0, 0)
			if flow_dir != 0:
				var diff = next_pt - pt
				offset = Vector2i(
					int(round(float(diff.x) / 10.0 * float(phase))),
					int(round(float(diff.y) / 10.0 * float(phase)))
				)
				
			var count = 0
			for elem in block_elems:
				var mat = elem.mat
				if mat > 0:
					var cx = count % 8
					var cy = count / 8
					
					var tx = gx
					var ty = gy
					
					if is_horizontal:
						tx = gx + cx + offset.x
						if flow_dir == -1: tx = gx + 7 - cx + offset.x
						ty = gy + 2 + cy + offset.y
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 97: _set_cell(tx, ty, mat)
					else:
						ty = gy + cx + offset.y
						if flow_dir == -1: ty = gy + 7 - cx + offset.y
						tx = gx + 2 + cy + offset.x
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 97: _set_cell(tx, ty, mat)
					
				count += 1
"""

content = re.sub(r'func _update_pipe_visuals\(p\):.*?(?=func _update_pipe_x2_visuals\(p\):)', pipe1_code + '\n\n', content, flags=re.DOTALL)
content = re.sub(r'func _update_pipe_x2_visuals\(p\):.*?(?=func _is_orientation_allowed)', pipe2_code + '\n\n', content, flags=re.DOTALL)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
