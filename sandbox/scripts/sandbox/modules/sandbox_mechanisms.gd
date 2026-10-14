class_name SandboxMechanismsManager
extends Node

## SandboxMechanismsManager
## Manages all mechanisms, circuits, logic gates, pistons, cannons, pipes,
## doors, and phase blocks in the sandbox simulation.

var grid: Node = null

# UI Panels
var circuit_panel: PanelContainer = null
var cannon_settings_panel: PanelContainer = null
var led_color_panel: PanelContainer = null

# State Flags & Tool Selections
var is_mechanism_mode_active: bool = false
var selected_circuit_tool: String = "wire"
var is_hollowing_pipe: bool = false
var selected_piston_length: int = 10
var is_piston_insulated: bool = false
var selected_led_color: int = 0 # 0=Red, 1=Blue, 2=Green, 3=Yellow, 4=White, 5=Pink, 6=Celeste, 7=Rainbow
var prev_pipe_gx: int = -1
var prev_pipe_gy: int = -1
var is_npc_door_updating: bool = false
var is_pipe_dirty: bool = false
var is_phase_block_updating: bool = false

# Active Collections
var active_logic_gates: Array = []
var active_pistons: Array = []
var active_cannons: Array = []
var active_pipes: Array = []
var active_pipes_x2: Array = []
var current_drawing_pipe_path: Array = []
var active_battery_indices: Dictionary = {} # Set of cell indices containing battery blocks
var active_electricity_source_indices: Dictionary = {} # Set of cell indices containing electricity
var door_registry: Dictionary = {} # Set of cell indices where NPC Door (91) is placed
var door_close_timers: Dictionary = {} # cell_idx -> float close delay timer
var phase_block_registry: Dictionary = {} # Set of cell indices where Phase Block (92) is placed

# Constants
const CANNON_POWER_MIN: float = 0.4
const CANNON_POWER_MED: float = 0.7
const CANNON_POWER_MAX: float = 1.25

const LOGIC_GATE_SHAPES: Dictionary = {
	0: [ # UP
		[0, 1, 0],
		[1, 1, 1],
		[1, 0, 1]
	],
	1: [ # RIGHT
		[1, 1, 0],
		[0, 1, 1],
		[1, 1, 0]
	],
	2: [ # DOWN
		[1, 0, 1],
		[1, 1, 1],
		[0, 1, 0]
	],
	3: [ # LEFT
		[0, 1, 1],
		[1, 1, 0],
		[0, 1, 1]
	]
}

func setup(p_grid: Node) -> void:
	grid = p_grid

func clear_all_mechanisms() -> void:
	active_logic_gates.clear()
	active_pistons.clear()
	active_cannons.clear()
	active_pipes.clear()
	active_pipes_x2.clear()
	door_registry.clear()
	door_close_timers.clear()
	phase_block_registry.clear()
	active_battery_indices.clear()
	active_electricity_source_indices.clear()
	current_drawing_pipe_path.clear()
	prev_pipe_gx = -1
	prev_pipe_gy = -1
	is_npc_door_updating = false
	is_pipe_dirty = false
	is_phase_block_updating = false
	is_hollowing_pipe = false

# ==============================================================================
# DOORS & PHASE BLOCKS
# ==============================================================================

func get_connected_door_cells(start_idx: int) -> Array:
	var group = []
	var queue = [start_idx]
	var visited = {}
	visited[start_idx] = true
	
	var w = grid.grid_width
	var h = grid.dynamic_grid_height
	
	var q_idx = 0
	while q_idx < queue.size():
		var curr = queue[q_idx]
		q_idx += 1
		group.append(curr)
		
		var cx = curr % w
		var cy = curr / w
		
		# Left
		if cx > 0:
			var n = curr - 1
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
		# Right
		if cx < w - 1:
			var n = curr + 1
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
		# Up
		if cy > 0:
			var n = curr - w
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
		# Down
		if cy < h - 1:
			var n = curr + w
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
				
	return group

func update_npc_doors(delta: float) -> void:
	if door_registry.size() == 0: return
	
	is_npc_door_updating = true
	
	# 1. Proximity detection: Find door indices directly near any active NPC (within 8px)
	var triggered_door_cells = {}
	for npc in grid.active_npcs:
		if npc.hp <= 0: continue
		var o_vis = grid.NPC_VISUALS.get(npc.type, grid.NPC_VISUALS["warrior"])
		var npc_w = o_vis["width"]
		var npc_h = o_vis["height"]
		var min_x = npc.pos.x - 8
		var max_x = npc.pos.x + npc_w - 1 + 8
		var min_y = npc.pos.y - 8
		var max_y = npc.pos.y + npc_h + 8
		
		# Hybrid Scan: loop registry if small, otherwise scan local bounding box
		if door_registry.size() < 200:
			for idx in door_registry:
				if triggered_door_cells.has(idx): continue
				var dx = idx % grid.grid_width
				var dy = idx / grid.grid_width
				if dx >= min_x and dx <= max_x and dy >= min_y and dy <= max_y:
					triggered_door_cells[idx] = true
		else:
			for dy in range(min_y, max_y + 1):
				if dy < 0 or dy >= grid.dynamic_grid_height: continue
				var row_offset = dy * grid.grid_width
				for dx in range(min_x, max_x + 1):
					if dx < 0 or dx >= grid.grid_width: continue
					var idx = row_offset + dx
					if door_registry.has(idx):
						triggered_door_cells[idx] = true
				
	# 2. Connected Component Opening: Open entire connected door groups if any part is triggered
	var final_open_cells = {}
	for idx in triggered_door_cells:
		if final_open_cells.has(idx): continue
		var group = get_connected_door_cells(idx)
		for g_idx in group:
			final_open_cells[g_idx] = true
			
	# 3. Update timers and apply cell changes
	for idx in door_registry:
		var x = idx % grid.grid_width
		var y = idx / grid.grid_width
		
		if idx in final_open_cells:
			# NPC is near -> Open door and set/reset timer to 1.0 second
			door_close_timers[idx] = 1.0
			var tid = grid.cells[idx] & 0xFFFF
			if tid == 91:
				grid._set_cell(x, y, 0)
		else:
			# NPC not near -> Tick timer down
			var timer = door_close_timers.get(idx, 0.0)
			if timer > 0.0:
				timer -= delta
				door_close_timers[idx] = timer
				# Keep open (clear to Air if it closed early)
				var tid = grid.cells[idx] & 0xFFFF
				if tid == 91:
					grid._set_cell(x, y, 0)
			else:
				# Timer expired -> Close door (restore to 91)
				var tid = grid.cells[idx] & 0xFFFF
				if tid != 91:
					grid._set_cell(x, y, 91)
					
	is_npc_door_updating = false

func update_phase_blocks() -> void:
	if phase_block_registry.size() == 0: return
	
	is_phase_block_updating = true
	var w = grid.grid_width
	var h = grid.dynamic_grid_height
	
	var invalid_indices = []
	for idx in phase_block_registry:
		if idx < 0 or idx >= grid.cells.size():
			invalid_indices.append(idx)
			continue
		var cx = idx % w
		var cy = idx / w
		
		# Check neighbors for electricity charge
		var is_powered = false
		
		# Left
		if cx > 0:
			var n = idx - 1
			if n >= 0 and n < grid.charge_array.size() and (grid.charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
		# Right
		if not is_powered and cx < w - 1:
			var n = idx + 1
			if n >= 0 and n < grid.charge_array.size() and (grid.charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
		# Up
		if not is_powered and cy > 0:
			var n = idx - w
			if n >= 0 and n < grid.charge_array.size() and (grid.charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
		# Down
		if not is_powered and cy < h - 1:
			var n = idx + w
			if n >= 0 and n < grid.charge_array.size() and (grid.charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
				
		var curr_mat = grid.cells[idx] & 0xFFFF
		if is_powered:
			if curr_mat == 92:
				grid.cells[idx] = 0
				grid.tags_array[idx] = 0
				grid._activate_chunk(cx / 4, cy / 4)
		else:
			if curr_mat != 92:
				# Re-solidify: overwrite whatever material is inside
				grid.cells[idx] = 92
				grid.tags_array[idx] = SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED
				grid._activate_chunk(cx / 4, cy / 4)
				
	for idx in invalid_indices:
		phase_block_registry.erase(idx)
	is_phase_block_updating = false

# ==============================================================================
# LOGIC GATES & CIRCUIT BLOCKS
# ==============================================================================

func simulate_logic_gates() -> void:
	if not is_instance_valid(grid) or grid.cells.size() == 0: return
	var i = active_logic_gates.size() - 1
	while i >= 0:
		var gate = active_logic_gates[i]
		var grid_pos = gate["grid_pos"]
		var orientation = gate["orientation"]
		var type = gate["type"]
		
		# Center cell row 1, col 1
		var cx = grid_pos.x
		var cy = grid_pos.y
		var center_gx = (cx + 1) * 4
		var center_gy = (cy + 1) * 4
		var center_idx = center_gy * grid.grid_width + center_gx
		
		if center_idx >= grid.cells.size():
			active_logic_gates.remove_at(i)
			i -= 1
			continue
			
		var center_mid = grid.cells[center_idx] & 0xFFFF
		if center_mid < 81 or center_mid > 87:
			# Gate center was overwritten, remove it!
			active_logic_gates.remove_at(i)
			i -= 1
			continue
		
		var pin_A_r = 0
		var pin_A_c = 0
		var pin_B_r = 0
		var pin_B_c = 0
		var pin_out_r = 0
		var pin_out_c = 0
		
		match orientation:
			0: # UP
				pin_A_r = 2; pin_A_c = 0
				pin_B_r = 2; pin_B_c = 2
				pin_out_r = 0; pin_out_c = 1
			1: # RIGHT
				pin_A_r = 0; pin_A_c = 0
				pin_B_r = 2; pin_B_c = 0
				pin_out_r = 1; pin_out_c = 2
			2: # DOWN
				pin_A_r = 0; pin_A_c = 0
				pin_B_r = 0; pin_B_c = 2
				pin_out_r = 2; pin_out_c = 1
			3: # LEFT
				pin_A_r = 0; pin_A_c = 2
				pin_B_r = 2; pin_B_c = 2
				pin_out_r = 1; pin_out_c = 0
		
		var bx_A = (cx + pin_A_c) * 4
		var by_A = (cy + pin_A_r) * 4
		var bx_B = (cx + pin_B_c) * 4
		var by_B = (cy + pin_B_r) * 4
		var _bx_out = (cx + pin_out_c) * 4
		var _by_out = (cy + pin_out_r) * 4
		
		var val_A = grid._is_cell_charged(bx_A, by_A)
		var val_B = grid._is_cell_charged(bx_B, by_B)
		
		var out_val = false
		match type:
			"not":
				out_val = not (val_A or val_B)
			"and":
				out_val = val_A and val_B
			"or":
				out_val = val_A or val_B
			"nand":
				out_val = not (val_A and val_B)
			"nor":
				out_val = not (val_A or val_B)
			"xor":
				out_val = val_A != val_B
			"xnor":
				out_val = val_A == val_B
				
		gate["output_active"] = out_val
		i -= 1

func load_active_logic_gates(dict: Dictionary) -> void:
	active_logic_gates.clear()
	if dict.has("active_logic_gates"):
		var old_w = int(dict.get("width", grid.grid_width))
		var old_h = int(dict.get("height", grid.grid_height))
		var y_offset_px = old_h - grid.grid_height
		y_offset_px = int(floor(float(y_offset_px) / 4.0)) * 4
		var x_offset_px = int((old_w - grid.grid_width) / 2.0)
		x_offset_px = int(floor(float(x_offset_px) / 4.0)) * 4
		
		var offset_logic_x = int(x_offset_px / 4.0)
		var offset_logic_y = int(y_offset_px / 4.0)
		
		var max_tx = int(grid.grid_width / 4.0)
		var max_ty = int(grid.grid_height / 4.0)

		for gate_data in dict["active_logic_gates"]:
			var gate = gate_data.duplicate(true)
			if gate.has("grid_pos"):
				var pos = gate["grid_pos"]
				var px = 0
				var py = 0
				if pos is Vector2 or pos is Vector2i:
					px = int(pos.x)
					py = int(pos.y)
				elif typeof(pos) == TYPE_DICTIONARY:
					px = int(pos.get("x", 0))
					py = int(pos.get("y", 0))
				gate["grid_pos"] = Vector2i(px - offset_logic_x, py - offset_logic_y)
				
				# Bounds check: logic gate spans 3x3 tiles
				if gate["grid_pos"].x >= 0 and gate["grid_pos"].x + 2 < max_tx and gate["grid_pos"].y >= 0 and gate["grid_pos"].y + 2 < max_ty:
					active_logic_gates.append(gate)

func get_gate_pin_cell_indices(gate, pin_type: String) -> Array:
	var cx = gate["grid_pos"].x
	var cy = gate["grid_pos"].y
	var orientation = gate["orientation"]
	
	var r = 0
	var c = 0
	
	if pin_type == "out":
		match orientation:
			0: r = 0; c = 1 # UP
			1: r = 1; c = 2 # RIGHT
			2: r = 2; c = 1 # DOWN
			3: r = 1; c = 0 # LEFT
	elif pin_type == "in_a":
		match orientation:
			0: r = 2; c = 0 # UP
			1: r = 0; c = 0 # RIGHT
			2: r = 0; c = 2 # DOWN
			3: r = 2; c = 2 # LEFT
	elif pin_type == "in_b":
		match orientation:
			0: r = 2; c = 2 # UP
			1: r = 2; c = 0 # RIGHT
			2: r = 0; c = 0 # DOWN
			3: r = 0; c = 2 # LEFT
			
	var pins = []
	var bx = (cx + c) * 4
	var by = (cy + r) * 4
	for dy in range(4):
		var gy = by + dy
		if gy < 0 or gy >= grid.grid_height: continue
		var row_offset = gy * grid.grid_width
		for dx in range(4):
			var gx = bx + dx
			if gx < 0 or gx >= grid.grid_width: continue
			pins.append(row_offset + gx)
	return pins

func get_logic_gate_output_pins(gate) -> Array:
	return get_gate_pin_cell_indices(gate, "out")

func place_circuit_block(gx: int, gy: int, mat_id: int) -> void:
	# Places a 4x4 block (16 pixels) to fully occupy the grid cell
	for oy in range(4):
		for ox in range(4):
			grid._set_cell(gx + ox, gy + oy, mat_id)

func get_logic_gate_cell_variant(r: int, c: int, orientation: int) -> int:
	match orientation:
		0: # UP
			if r == 0 and c == 1: return 14 # Output (Top)
			elif r == 2 and c == 0: return 12 # Input A (Bottom)
			elif r == 2 and c == 2: return 12 # Input B (Bottom)
		1: # RIGHT
			if r == 1 and c == 2: return 15 # Output (Right)
			elif r == 0 and c == 0: return 13 # Input A (Left)
			elif r == 2 and c == 0: return 13 # Input B (Left)
		2: # DOWN
			if r == 2 and c == 1: return 16 # Output (Bottom)
			elif r == 0 and c == 2: return 10 # Input A (Top)
			elif r == 0 and c == 0: return 10 # Input B (Top)
		3: # LEFT
			if r == 1 and c == 0: return 17 # Output (Left)
			elif r == 2 and c == 2: return 11 # Input A (Right)
			elif r == 0 and c == 2: return 11 # Input B (Right)
	return 0

func draw_logic_gate_shape(grid_pos: Vector2i, orientation: int, erase: bool, type: String = "and") -> void:
	var shape = LOGIC_GATE_SHAPES.get(orientation, LOGIC_GATE_SHAPES[0])
	var mat = 0
	if not erase:
		match type:
			"not": mat = 81
			"and": mat = 82
			"or": mat = 83
			"nand": mat = 84
			"nor": mat = 85
			"xor": mat = 86
			"xnor": mat = 87
			_: mat = 82
	for r in range(3):
		for c in range(3):
			if shape[r][c] == 1:
				var cell_mat = mat
				if not erase and mat > 0:
					var variant = get_logic_gate_cell_variant(r, c, orientation)
					cell_mat = mat | (variant << 24)
				place_circuit_block((grid_pos.x + c) * 4, (grid_pos.y + r) * 4, cell_mat)

# ==============================================================================
# RECONSTRUCTION FROM CELLS
# ==============================================================================

func reconstruct_sources_from_cells(dict: Dictionary = {}) -> void:
	var old_pipe_elements = {}
	for p in active_pipes:
		if p.has("path") and p.has("elements"):
			for i in range(p.path.size()):
				var coord = p.path[i]
				if i < p.elements.size():
					old_pipe_elements[coord] = p.elements[i]
					
	var old_pipe_x2_elements = {}
	for p in active_pipes_x2:
		if p.has("path") and p.has("elements"):
			for i in range(p.path.size()):
				var coord = p.path[i]
				if i < p.elements.size():
					old_pipe_x2_elements[coord] = p.elements[i]
					
	active_battery_indices.clear()
	active_electricity_source_indices.clear()
	door_registry.clear()
	door_close_timers.clear()
	phase_block_registry.clear()
	grid.active_metronome_indices.clear()
	active_pistons.clear()
	
	if dict.has("active_pistons"):
		var p_y_offset = 0
		var p_x_offset = 0
		if dict.has("width") and dict.has("height"):
			var old_w = int(dict["width"])
			var old_h = int(dict["height"])
			p_y_offset = old_h - grid.grid_height
			p_y_offset = int(floor(float(p_y_offset) / 4.0)) * 4
			p_x_offset = int((old_w - grid.grid_width) / 2.0)
			p_x_offset = int(floor(float(p_x_offset) / 4.0)) * 4
		for p_data in dict["active_pistons"]:
			var p = p_data.duplicate(true)
			if p.has("pos"):
				var px = p["pos"].x
				var py = p["pos"].y
				if px is float: px = int(px)
				if py is float: py = int(py)
				p["pos"] = Vector2i(px - p_x_offset, py - p_y_offset)
			active_pistons.append(p)
			
	active_cannons.clear()
	active_pipes.clear()
	active_pipes_x2.clear()
	
	# 1. Restore open doors, powered phase blocks, and timers from save dict if present
	var translate_idx = func(old_idx: int) -> int:
		if not dict.has("width") or not dict.has("height"):
			return old_idx
		var old_w = int(dict["width"])
		var old_h = int(dict["height"])
		var old_y = int(old_idx / float(old_w))
		var old_x = old_idx % old_w
		
		var y_offset = old_h - grid.grid_height
		y_offset = int(floor(float(y_offset) / 4.0)) * 4
		var x_offset = int((old_w - grid.grid_width) / 2.0)
		x_offset = int(floor(float(x_offset) / 4.0)) * 4
		
		var new_x = old_x - x_offset
		var new_y = old_y - y_offset
		if new_x >= 0 and new_x < grid.grid_width and new_y >= 0 and new_y < grid.grid_height:
			return new_y * grid.grid_width + new_x
		return -1

	if dict.has("door_registry"):
		for idx in dict["door_registry"]:
			var new_idx = translate_idx.call(int(idx))
			if new_idx != -1:
				door_registry[new_idx] = true
	if dict.has("door_close_timers"):
		var timers = dict["door_close_timers"]
		for idx_str in timers:
			var new_idx = translate_idx.call(int(idx_str))
			if new_idx != -1:
				door_close_timers[new_idx] = float(timers[idx_str])
	if dict.has("phase_block_registry"):
		for idx in dict["phase_block_registry"]:
			var new_idx = translate_idx.call(int(idx))
			if new_idx != -1:
				phase_block_registry[new_idx] = true
			
	# 2. Loop over cells to reconstruct batteries, electricity source blocks, metronomes, and solid doors/phase blocks
	if grid.cells.size() == 0: return
	var special_indices = grid.get_special_source_indices(grid.cells)
	for idx in special_indices:
		var mid = grid.cells[idx] & 0xFFFF
		if mid == 88:
			active_battery_indices[idx] = true
		elif mid == 9:
			active_electricity_source_indices[idx] = true
		elif mid == 600:
			grid.active_metronome_indices[idx] = true
		elif mid == 91:
			door_registry[idx] = true
		elif mid == 92:
			phase_block_registry[idx] = true
		elif mid == 95 or mid == 195 or mid == 295 or mid == 395 or mid == 495 or mid == 595 or mid == 695 or mid == 795:
			var px = idx % grid.grid_width
			var py = int(idx / float(grid.grid_width))
			var val = grid.cells[idx]
			var variant = (val >> 24) & 0xFF
			var local_x = variant & 0x0F
			var local_y = variant >> 4
			var gx = px - local_x + 3
			var gy = py - local_y + 3
			var already_registered = false
			for c in active_cannons:
				if c.pos.x == gx and c.pos.y == gy:
					already_registered = true
					break
			if not already_registered:
				var orient = int((mid - 95) / 100.0)
				var new_c = {
					"pos": Vector2i(gx, gy),
					"orientation": orient,
					"cooldown": 0.0
				}
				active_cannons.append(new_c)
		elif mid == 93:
			var px = idx % grid.grid_width
			var py = int(idx / float(grid.grid_width))
			var already_registered = false
			for p in active_pistons:
				var orient = p.get("orientation", 0)
				var in_base = false
				if orient == 0:
					in_base = (px >= p.pos.x and px < p.pos.x + 4 and py >= p.pos.y + 1 and py < p.pos.y + 4)
				elif orient == 1:
					in_base = (px >= p.pos.x and px < p.pos.x + 3 and py >= p.pos.y and py < p.pos.y + 4)
				elif orient == 2:
					in_base = (px >= p.pos.x and px < p.pos.x + 4 and py >= p.pos.y and py < p.pos.y + 3)
				elif orient == 3:
					in_base = (px >= p.pos.x + 1 and px < p.pos.x + 4 and py >= p.pos.y and py < p.pos.y + 4)
				if in_base:
					already_registered = true
					break
			if not already_registered:
				# Base layout boundary hits starting pixel.
				# Scan the 4x4 bounding box to identify base pixels and head location to find orientation:
				var gx = px
				var gy = py
				# Find top-left of the 4x4 grid cell:
				gx = int(floor(float(px) / 4.0) * 4.0)
				gy = int(floor(float(py) / 4.0) * 4.0)
				
				var detected_orient = 0
				if grid._get_cell(gx + 3, gy) == 94 and grid._get_cell(gx + 3, gy + 3) == 94:
					detected_orient = 1 # RIGHT
				elif grid._get_cell(gx, gy + 3) == 94 and grid._get_cell(gx + 3, gy + 3) == 94:
					detected_orient = 2 # DOWN
				elif grid._get_cell(gx, gy) == 94 and grid._get_cell(gx, gy + 3) == 94:
					detected_orient = 3 # LEFT
				
				# Scan along the detected orientation direction to find the current extension
				var ext = 0
				for ey in range(0, 61):
					var head_found = true
					var head_pixels = []
					if detected_orient == 0: # UP
						var ty = gy - ey
						for ox in range(4):
							head_pixels.append(Vector2i(gx + ox, ty))
					elif detected_orient == 1: # RIGHT
						var tx = gx + 3 + ey
						for oy in range(4):
							head_pixels.append(Vector2i(tx, gy + oy))
					elif detected_orient == 2: # DOWN
						var ty = gy + 3 + ey
						for ox in range(4):
							head_pixels.append(Vector2i(gx + ox, ty))
					elif detected_orient == 3: # LEFT
						var tx = gx - ey
						for oy in range(4):
							head_pixels.append(Vector2i(tx, gy + oy))
							
					for pix in head_pixels:
						if pix.x < 0 or pix.x >= grid.grid_width or pix.y < 0 or pix.y >= grid.grid_height or grid._get_cell(pix.x, pix.y) != 94:
							head_found = false
							break
					if head_found:
						ext = ey
					else:
						break
				var new_p = {
					"pos": Vector2i(gx, gy),
					"current_ext": float(ext),
					"target_ext": selected_piston_length,
					"is_active": false,
					"orientation": detected_orient,
					"is_insulated": (mid == 193)
				}
				active_pistons.append(new_p)

	# Reconstruct pipes paths from cells
	var pipe_blocks = {}
	for idx_pt in range(grid.cells.size()):
		if (grid.cells[idx_pt] & 0xFFFF) == 96:
			var px = idx_pt % grid.grid_width
			var py = int(idx_pt / float(grid.grid_width))
			var gx = int(floor(float(px) / 4.0) * 4.0)
			var gy = int(floor(float(py) / 4.0) * 4.0)
			pipe_blocks[Vector2i(gx, gy)] = true
			
	var unvisited = pipe_blocks.keys()
	
	var get_neighbors = func(pt: Vector2i) -> Array:
		var npts = []
		var dirs = [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]
		for d in dirs:
			var target = pt + d
			if pipe_blocks.has(target):
				npts.append(target)
		return npts
		
	while unvisited.size() > 0:
		var start = unvisited[0]
		for pt in unvisited:
			if get_neighbors.call(pt).size() == 1:
				start = pt
				break
				
		var path = [start]
		unvisited.erase(start)
		
		var current = start
		while true:
			var neighbors = get_neighbors.call(current)
			var next_block = null
			for n in neighbors:
				if n in unvisited:
					next_block = n
					break
			if next_block != null:
				path.append(next_block)
				unvisited.erase(next_block)
				current = next_block
			else:
				break
				
		var elem_list = []
		for pt in path:
			if old_pipe_elements.has(pt):
				elem_list.append(old_pipe_elements[pt])
			else:
				elem_list.append([])
		var initial_flow_dir = 0
		for list in elem_list:
			if list.size() > 0:
				initial_flow_dir = list[0].get("dir", 0)
				break
		active_pipes.append({
			"path": path,
			"elements": elem_list,
			"flow_dir": initial_flow_dir
		})
		
	for p in active_pipes:
		update_pipe_visuals(p)

	# Reconstruct pipe_x2 paths from cells
	var pipe_x2_blocks = {}
	for idx_pt in range(grid.cells.size()):
		if (grid.cells[idx_pt] & 0xFFFF) == 97:
			var px = idx_pt % grid.grid_width
			var py = int(idx_pt / float(grid.grid_width))
			var gx = int(floor(float(px) / 8.0) * 8.0)
			var gy = int(floor(float(py) / 8.0) * 8.0)
			pipe_x2_blocks[Vector2i(gx, gy)] = true
			
	var unvisited_x2 = pipe_x2_blocks.keys()
	
	var get_neighbors_x2 = func(pt: Vector2i) -> Array:
		var npts = []
		var dirs = [Vector2i(8, 0), Vector2i(-8, 0), Vector2i(0, 8), Vector2i(0, -8)]
		for d in dirs:
			var target = pt + d
			if pipe_x2_blocks.has(target):
				npts.append(target)
		return npts
		
	while unvisited_x2.size() > 0:
		var start = unvisited_x2[0]
		for pt in unvisited_x2:
			if get_neighbors_x2.call(pt).size() == 1:
				start = pt
				break
				
		var path = [start]
		unvisited_x2.erase(start)
		
		var current = start
		while true:
			var neighbors = get_neighbors_x2.call(current)
			var next_block = null
			for n in neighbors:
				if n in unvisited_x2:
					next_block = n
					break
			if next_block != null:
				path.append(next_block)
				unvisited_x2.erase(next_block)
				current = next_block
			else:
				break
				
		var elem_list = []
		for pt in path:
			var item = old_pipe_x2_elements.get(pt, null)
			if item is Dictionary and item.has("a") and item.has("b"):
				var flat = []
				for elem in item["a"]:
					flat.append(elem)
				for elem in item["b"]:
					flat.append(elem)
				elem_list.append(flat)
			elif item is Array:
				elem_list.append(item)
			else:
				elem_list.append([])
		var initial_flow_dir_x2 = 0
		for list in elem_list:
			if list.size() > 0:
				initial_flow_dir_x2 = list[0].get("dir", 0)
				break
		active_pipes_x2.append({
			"path": path,
			"elements": elem_list,
			"flow_dir": initial_flow_dir_x2
		})
		
	for p in active_pipes_x2:
		update_pipe_x2_visuals(p)

# ==============================================================================
# PISTONS
# ==============================================================================

func get_piston_direction(orientation: int) -> Vector2i:
	match orientation:
		0: return Vector2i(0, -1) # UP
		1: return Vector2i(1, 0)  # RIGHT
		2: return Vector2i(0, 1)  # DOWN
		3: return Vector2i(-1, 0) # LEFT
	return Vector2i(0, -1)

func get_piston_head_pixels(p, ext: int) -> Array:
	var px = p.pos.x
	var gy = p.pos.y
	var pixels = []
	var orient = p.get("orientation", 0)
	if orient == 0: # UP
		var ty = gy - ext
		for ox in range(4):
			pixels.append(Vector2i(px + ox, ty))
	elif orient == 1: # RIGHT
		var tx = px + 3 + ext
		for oy in range(4):
			pixels.append(Vector2i(tx, gy + oy))
	elif orient == 2: # DOWN
		var ty = gy + 3 + ext
		for ox in range(4):
			pixels.append(Vector2i(px + ox, ty))
	elif orient == 3: # LEFT
		var tx = px - ext
		for oy in range(4):
			pixels.append(Vector2i(tx, gy + oy))
	return pixels

func get_piston_base_pixels(p) -> Array:
	var px = p.pos.x
	var gy = p.pos.y
	var pixels = []
	var orient = p.get("orientation", 0)
	if orient == 0: # UP
		for oy in range(1, 4):
			for ox in range(4):
				pixels.append(Vector2i(px + ox, gy + oy))
	elif orient == 1: # RIGHT
		for oy in range(4):
			for ox in range(3):
				pixels.append(Vector2i(px + ox, gy + oy))
	elif orient == 2: # DOWN
		for oy in range(3):
			for ox in range(4):
				pixels.append(Vector2i(px + ox, gy + oy))
	elif orient == 3: # LEFT
		for oy in range(4):
			for ox in range(1, 4):
				pixels.append(Vector2i(px + ox, gy + oy))
	return pixels

func place_piston(gx: int, gy: int) -> void:
	if gx < 0 or gx + 3 >= grid.grid_width or gy < 0 or gy + 3 >= grid.grid_height:
		return
		
	# Check if there is an existing piston at this exact snapping coordinate gx, gy
	var existing_idx = -1
	for idx in range(active_pistons.size()):
		if active_pistons[idx].pos.x == gx and active_pistons[idx].pos.y == gy:
			existing_idx = idx
			break
			
	if existing_idx != -1:
		# Rotate existing piston!
		var p = active_pistons[existing_idx]
		
		# 1. Erase old piston shape (base + head + any extension)
		var _base_mat_to_erase = 193 if p.get("is_insulated", false) else 93
		var base_pix_erase = get_piston_base_pixels(p)
		for pix in base_pix_erase:
			grid._set_cell(pix.x, pix.y, 0)
			
		var ext_limit = int(p.current_ext)
		for ext_val in range(ext_limit + 1):
			@warning_ignore("confusable_local_declaration")
			var head_pix = get_piston_head_pixels(p, ext_val)
			for pix in head_pix:
				grid._set_cell(pix.x, pix.y, 0)
				
		# 2. Update orientation
		p.orientation = (p.get("orientation", 0) + 1) % 4
		p.current_ext = 0.0
		
		# 3. Draw new piston shape
		var b_mat_new = 193 if p.get("is_insulated", false) else 93
		var h_mat_new = 194 if p.get("is_insulated", false) else 94
		var base_pix = get_piston_base_pixels(p)
		for pix in base_pix:
			grid._set_cell(pix.x, pix.y, b_mat_new)
		@warning_ignore("confusable_local_declaration")
		var head_pix = get_piston_head_pixels(p, 0)
		for pix in head_pix:
			grid._set_cell(pix.x, pix.y, h_mat_new)
			
		grid._play_action_sound("ui_click")
		return
		
	# Remove overlapping pistons
	var i = active_pistons.size() - 1
	while i >= 0:
		var p = active_pistons[i]
		if abs(p.pos.x - gx) < 4 and abs(p.pos.y - gy) < 4:
			# Erase cells of overlapping piston to prevent orphans
			for oy in range(4):
				for ox in range(4):
					grid._set_cell(p.pos.x + ox, p.pos.y + oy, 0)
			var ext_limit = int(p.current_ext)
			for ext_val in range(ext_limit + 1):
				@warning_ignore("confusable_local_declaration")
				var head_pix = get_piston_head_pixels(p, ext_val)
				for pix in head_pix:
					grid._set_cell(pix.x, pix.y, 0)
			active_pistons.remove_at(i)
		i -= 1

	var base_mat_new = 193 if is_piston_insulated else 93
	var head_mat_new = 194 if is_piston_insulated else 94
	for oy in range(1, 4):
		for ox in range(4):
			grid._set_cell(gx + ox, gy + oy, base_mat_new)
			
	for ox in range(4):
		grid._set_cell(gx + ox, gy, head_mat_new)
			
	var new_p = {
		"pos": Vector2i(gx, gy),
		"current_ext": 0.0,
		"target_ext": selected_piston_length,
		"is_active": false,
		"orientation": 0,
		"is_insulated": is_piston_insulated
	}
	active_pistons.append(new_p)
	
	if not grid.is_piston_tutorial_done:
		grid._show_piston_tutorial_bubble(Vector2i(gx, gy))

func is_piston_base_powered(p) -> bool:
	var px = p.pos.x
	var gy = p.pos.y
	var orient = p.get("orientation", 0)
	
	if orient == 0: # UP
		var r1 = (gy + 1) * grid.grid_width
		var r2 = (gy + 2) * grid.grid_width
		var r3 = (gy + 3) * grid.grid_width
		var i = r1 + px
		if grid.charge_array[i] > 0 or active_battery_indices.has(i): return true
		if grid.charge_array[i+1] > 0 or active_battery_indices.has(i+1): return true
		if grid.charge_array[i+2] > 0 or active_battery_indices.has(i+2): return true
		if grid.charge_array[i+3] > 0 or active_battery_indices.has(i+3): return true
		i = r2 + px
		if grid.charge_array[i] > 0 or active_battery_indices.has(i): return true
		if grid.charge_array[i+1] > 0 or active_battery_indices.has(i+1): return true
		if grid.charge_array[i+2] > 0 or active_battery_indices.has(i+2): return true
		if grid.charge_array[i+3] > 0 or active_battery_indices.has(i+3): return true
		i = r3 + px
		if grid.charge_array[i] > 0 or active_battery_indices.has(i): return true
		if grid.charge_array[i+1] > 0 or active_battery_indices.has(i+1): return true
		if grid.charge_array[i+2] > 0 or active_battery_indices.has(i+2): return true
		if grid.charge_array[i+3] > 0 or active_battery_indices.has(i+3): return true
	elif orient == 1: # RIGHT
		for oy in range(4):
			var r = (gy + oy) * grid.grid_width + px
			if grid.charge_array[r] > 0 or active_battery_indices.has(r): return true
			if grid.charge_array[r+1] > 0 or active_battery_indices.has(r+1): return true
			if grid.charge_array[r+2] > 0 or active_battery_indices.has(r+2): return true
	elif orient == 2: # DOWN
		for oy in range(3):
			var r = (gy + oy) * grid.grid_width + px
			if grid.charge_array[r] > 0 or active_battery_indices.has(r): return true
			if grid.charge_array[r+1] > 0 or active_battery_indices.has(r+1): return true
			if grid.charge_array[r+2] > 0 or active_battery_indices.has(r+2): return true
			if grid.charge_array[r+3] > 0 or active_battery_indices.has(r+3): return true
	elif orient == 3: # LEFT
		for oy in range(4):
			var r = (gy + oy) * grid.grid_width + px + 1
			if grid.charge_array[r] > 0 or active_battery_indices.has(r): return true
			if grid.charge_array[r+1] > 0 or active_battery_indices.has(r+1): return true
			if grid.charge_array[r+2] > 0 or active_battery_indices.has(r+2): return true
			
	return false

func activate_piston_chunks(px: int, gy: int) -> void:
	var start_cx = int(px / 4.0)
	var end_cx = int((px + 4) / 4.0)
	var start_cy = clamp(int((gy - 64) / 4.0), 0, int(grid.grid_height / 4.0))
	var end_cy = clamp(int((gy + 16) / 4.0), 0, int(grid.grid_height / 4.0))
	for cy in range(start_cy, end_cy + 1):
		for cx in range(start_cx, end_cx + 1):
			grid._activate_chunk(cx, cy)

func simulate_pistons() -> void:
	if active_pistons.size() == 0: return
	
	var old_exts = []
	for p in active_pistons:
		old_exts.append(p.current_ext)
	
	# Piston processing in C++ (Extremely fast, handles all block pushes directly)
	var state = grid._pack_state_for_cpp()
	state = grid.process_pistons(active_pistons, state, grid.grid_width, grid.dynamic_grid_height, 0.0)
	var new_pistons = state["new_pistons"]
	
	grid.cells = state["cells"]
	grid.tags_array = state["tags_array"]
	grid.charge_array = state["charge_array"]
	grid.next_chunks_active = state["next_chunks_active"]
	grid.cell_paint_colors = state["cell_paint_colors"]
	
	# NPC Push logic (Needs to be done in GDScript since NPCs are nodes/complex objects)
	for i in range(active_pistons.size()):
		var _p_old = active_pistons[i]
		if i >= new_pistons.size(): break # In case it was deleted
		var p_new = new_pistons[i]
		
		var p_old_ext = old_exts[i]
		
		# If piston extended, push NPCs
		if p_new.current_ext > p_old_ext:
			var px = p_new.pos.x
			var gy = p_new.pos.y
			var orient = p_new.get("orientation", 0)
			var ext = int(p_old_ext)
			# Find push_height by checking how many blocks are in front
			var push_height = 0
			var step_idx = 1
			while true:
				var p0: Vector2i; var p3: Vector2i
				if orient == 0:
					var ty = gy - ext - step_idx
					p0 = Vector2i(px, ty); p3 = Vector2i(px + 3, ty)
				elif orient == 1:
					var tx = px + 3 + ext + step_idx
					p0 = Vector2i(tx, gy); p3 = Vector2i(tx, gy + 3)
				elif orient == 2:
					var ty = gy + 3 + ext + step_idx
					p0 = Vector2i(px, ty); p3 = Vector2i(px + 3, ty)
				elif orient == 3:
					var tx = px - ext - step_idx
					p0 = Vector2i(tx, gy); p3 = Vector2i(tx, gy + 3)
					
				if p0.x < 0 or p0.x >= grid.grid_width or p0.y < 0 or p0.y >= grid.dynamic_grid_height or p3.x < 0 or p3.x >= grid.grid_width or p3.y < 0 or p3.y >= grid.dynamic_grid_height: break
				
				var has_blocks = false
				if orient == 0 or orient == 2:
					for ox in range(4):
						if grid._get_cell(p0.x + ox, p0.y) != 0: has_blocks = true; break
				else:
					for oy in range(4):
						if grid._get_cell(p0.x, p0.y + oy) != 0: has_blocks = true; break
						
				if not has_blocks: break
				push_height += 1
				if push_height > 120: break
				step_idx += 1
				
			var col_left = px
			var col_right = px + 4
			if orient == 0: # UP
				var col_bottom = gy - ext + 1
				var col_top = gy - ext - push_height
				for npc in grid.active_npcs:
					if npc.pos.x >= col_left - 10 and npc.pos.x <= col_right + 10:
						if npc.pos.y >= col_top - 4 and npc.pos.y <= col_bottom + 2:
							npc.pos.y -= 1.0
			elif orient == 1: # RIGHT
				var col_start = gy
				var col_end = gy + 4
				var ext_start = px + 3 + ext
				var ext_end = px + 3 + ext + push_height
				for npc in grid.active_npcs:
					if npc.pos.y >= col_start - 10 and npc.pos.y <= col_end + 10:
						if npc.pos.x >= ext_start - 2 and npc.pos.x <= ext_end + 4:
							npc.pos.x += 1.0
			elif orient == 2: # DOWN
				var col_top = gy + 3 + ext
				var col_bottom = gy + 3 + ext + push_height
				for npc in grid.active_npcs:
					if npc.pos.x >= col_left - 10 and npc.pos.x <= col_right + 10:
						if npc.pos.y >= col_top - 2 and npc.pos.y <= col_bottom + 4:
							npc.pos.y += 1.0
			elif orient == 3: # LEFT
				var col_start = gy
				var col_end = gy + 4
				var ext_start = px - ext - push_height
				var ext_end = px - ext
				for npc in grid.active_npcs:
					if npc.pos.y >= col_start - 10 and npc.pos.y <= col_end + 10:
						if npc.pos.x >= ext_start - 4 and npc.pos.x <= ext_end + 2:
							npc.pos.x -= 1.0

	active_pistons = new_pistons

# ==============================================================================
# CANNONS & CANNON SETTINGS
# ==============================================================================

func get_cannon_active_cells(orient: int, inlet_side: String = "") -> Array:
	if inlet_side == "":
		if orient == 0: inlet_side = "left"
		elif orient == 1: inlet_side = "bottom"
		elif orient == 2: inlet_side = "bottom"
		elif orient == 3: inlet_side = "bottom"
		elif orient == 4: inlet_side = "right"
		else: inlet_side = "left"

	var list = []
	# 1. Base / Stand (depends on inlet_side, shifted by +1)
	if inlet_side == "bottom":
		list.append(Vector2i(4, 8))
		list.append(Vector2i(5, 8))
		list.append(Vector2i(6, 8))
		list.append(Vector2i(7, 8))
		list.append(Vector2i(4, 9))
		list.append(Vector2i(7, 9))
		list.append(Vector2i(4, 10))
		list.append(Vector2i(7, 10))
		list.append(Vector2i(4, 11))
		list.append(Vector2i(7, 11))
	elif inlet_side == "top":
		list.append(Vector2i(4, 3))
		list.append(Vector2i(5, 3))
		list.append(Vector2i(6, 3))
		list.append(Vector2i(7, 3))
		list.append(Vector2i(4, 2))
		list.append(Vector2i(7, 2))
		list.append(Vector2i(4, 1))
		list.append(Vector2i(7, 1))
		list.append(Vector2i(4, 0))
		list.append(Vector2i(7, 0))
	elif inlet_side == "left":
		list.append(Vector2i(3, 4))
		list.append(Vector2i(3, 5))
		list.append(Vector2i(3, 6))
		list.append(Vector2i(3, 7))
		list.append(Vector2i(2, 4))
		list.append(Vector2i(2, 7))
		list.append(Vector2i(1, 4))
		list.append(Vector2i(1, 7))
		list.append(Vector2i(0, 4))
		list.append(Vector2i(0, 7))
	elif inlet_side == "right":
		list.append(Vector2i(8, 4))
		list.append(Vector2i(8, 5))
		list.append(Vector2i(8, 6))
		list.append(Vector2i(8, 7))
		list.append(Vector2i(9, 4))
		list.append(Vector2i(9, 7))
		list.append(Vector2i(10, 4))
		list.append(Vector2i(10, 7))
		list.append(Vector2i(11, 4))
		list.append(Vector2i(11, 7))
	
	# 2. Main Body (always active, shifted by +1)
	for py in range(4, 8):
		for px in range(4, 8):
			list.append(Vector2i(px, py))
			
	# 3. Pivot & Barrel (depends on orientation, shifted by +1)
	if orient == 0: # 0 deg (Right)
		list.append(Vector2i(8, 5))
		list.append(Vector2i(8, 6))
		list.append(Vector2i(9, 5))
		list.append(Vector2i(9, 6))
	elif orient == 1: # 45 deg (Top-Right)
		list.append(Vector2i(7, 3))
		list.append(Vector2i(8, 4))
		list.append(Vector2i(8, 2))
		list.append(Vector2i(8, 3))
		list.append(Vector2i(9, 3))
	elif orient == 2: # 90 deg (Up)
		list.append(Vector2i(5, 3))
		list.append(Vector2i(6, 3))
		list.append(Vector2i(5, 1))
		list.append(Vector2i(6, 1))
		list.append(Vector2i(5, 2))
		list.append(Vector2i(6, 2))
	elif orient == 3: # 135 deg (Top-Left)
		list.append(Vector2i(4, 3))
		list.append(Vector2i(3, 4))
		list.append(Vector2i(3, 2))
		list.append(Vector2i(3, 3))
		list.append(Vector2i(2, 3))
	elif orient == 4: # 180 deg (Left)
		list.append(Vector2i(3, 5))
		list.append(Vector2i(3, 6))
		list.append(Vector2i(2, 5))
		list.append(Vector2i(2, 6))
	elif orient == 5: # 225 deg (Bottom-Left)
		list.append(Vector2i(4, 8))
		list.append(Vector2i(3, 7))
		list.append(Vector2i(3, 9))
		list.append(Vector2i(3, 8))
		list.append(Vector2i(2, 8))
	elif orient == 6: # 270 deg (Down)
		list.append(Vector2i(5, 8))
		list.append(Vector2i(6, 8))
		list.append(Vector2i(5, 10))
		list.append(Vector2i(6, 10))
		list.append(Vector2i(5, 9))
		list.append(Vector2i(6, 9))
	elif orient == 7: # 315 deg (Bottom-Right)
		list.append(Vector2i(7, 8))
		list.append(Vector2i(8, 7))
		list.append(Vector2i(8, 9))
		list.append(Vector2i(8, 8))
		list.append(Vector2i(9, 8))
		
	return list

func place_cannon(gx: int, gy: int) -> void:
	if gx - 4 < 0 or gx + 7 >= grid.grid_width or gy - 4 < 0 or gy + 7 >= grid.grid_height:
		return
		
	# Check if there is an existing cannon at this exact snapping coordinate gx, gy
	var existing_idx = -1
	for idx in range(active_cannons.size()):
		if active_cannons[idx].pos.x == gx and active_cannons[idx].pos.y == gy:
			existing_idx = idx
			break
			
	if existing_idx != -1:
		var c = active_cannons[existing_idx]
		open_cannon_settings_panel(c)
		return
		
	# Remove any overlapping cannons (anchors within 6 cells)
	var i = active_cannons.size() - 1
	while i >= 0:
		var c = active_cannons[i]
		if abs(c.pos.x - gx) < 6 and abs(c.pos.y - gy) < 6:
			# Clear their 12x12 area
			for py in range(12):
				for px in range(12):
					var tx = c.pos.x + px - 4
					var ty = c.pos.y + py - 4
					if tx >= 0 and tx < grid.grid_width and ty >= 0 and ty < grid.grid_height:
						grid._set_cell(tx, ty, 0)
			active_cannons.remove_at(i)
		i -= 1
		
	# Place new cannon (initial orientation 0: Right)
	var new_c = {
		"pos": Vector2i(gx, gy),
		"orientation": 0,
		"cooldown": 0.0,
		"inlet_side": "left"
	}
	active_cannons.append(new_c)
	
	# Clear the 12x12 area
	for py in range(12):
		for px in range(12):
			var tx = gx + px - 4
			var ty = gy + py - 4
			grid._set_cell(tx, ty, 0)
			
	# Write active cells for orientation 0
	var active_cells = get_cannon_active_cells(0, "left")
	var mat_id = 95
	for pt in active_cells:
		var tx = gx + pt.x - 4
		var ty = gy + pt.y - 4
		var variant = pt.x | (pt.y << 4)
		var val_encoded = mat_id | (variant << 24)
		grid._set_cell(tx, ty, val_encoded)
		
	grid._play_action_sound("ui_click")
	
	if not grid.is_cannon_tutorial_done:
		grid._show_cannon_tutorial_bubble(Vector2i(gx, gy))

func is_cannon_powered(c) -> bool:
	var cx = c.pos.x
	var cy = c.pos.y
	for oy in range(4):
		for ox in range(4):
			var idx = (cy + oy) * grid.grid_width + (cx + ox)
			if idx >= 0 and idx < grid.cells.size():
				if grid.charge_array[idx] > 0 or active_battery_indices.has(idx):
					return true
	return false

func is_pipe_connected_on_inlet(c, pt: Vector2i, is_x2: bool) -> bool:
	var inlet_side = c.get("inlet_side", "left")
	var cx = c.pos.x
	var cy = c.pos.y
	
	if pt.x == cx + 2 and pt.y == cy + 2:
		return true
		
	if not is_x2:
		if inlet_side == "left":
			return pt.x == cx - 5 and pt.y >= cy and pt.y <= cy + 3
		elif inlet_side == "right":
			return pt.x == cx + 8 and pt.y >= cy and pt.y <= cy + 3
		elif inlet_side == "top":
			return pt.y == cy - 5 and pt.x >= cx and pt.x <= cx + 3
		elif inlet_side == "bottom":
			return pt.y == cy + 8 and pt.x >= cx and pt.x <= cx + 3
	else:
		if inlet_side == "left":
			return abs(pt.x - (cx - 5)) <= 4 and abs(pt.y - (cy + 1.5)) <= 4
		elif inlet_side == "right":
			return abs(pt.x - (cx + 8)) <= 4 and abs(pt.y - (cy + 1.5)) <= 4
		elif inlet_side == "top":
			return abs(pt.y - (cy - 5)) <= 4 and abs(pt.x - (cx + 1.5)) <= 4
		elif inlet_side == "bottom":
			return abs(pt.y - (cy + 8)) <= 4 and abs(pt.x - (cx + 1.5)) <= 4
	return false

func find_connected_pipe_and_endpoint(c) -> Dictionary:
	for p in active_pipes:
		var path = p.get("path", [])
		var L = path.size()
		if L == 0: continue
		
		# Check start endpoint (path[0])
		var pt0 = path[0]
		if is_pipe_connected_on_inlet(c, pt0, false):
			return { "pipe": p, "endpoint_idx": 0 }
				
		# Check end endpoint (path[L-1])
		var ptL = path[L - 1]
		if is_pipe_connected_on_inlet(c, ptL, false):
			return { "pipe": p, "endpoint_idx": L - 1 }
				
	for p in active_pipes_x2:
		var path = p.get("path", [])
		var L = path.size()
		if L == 0: continue
		
		# Check start endpoint (path[0]) for double pipe (8x8 blocks)
		var pt0 = path[0]
		if is_pipe_connected_on_inlet(c, pt0, true):
			return { "pipe": p, "endpoint_idx": 0 }
				
		# Check end endpoint (path[L-1]) for double pipe (8x8 blocks)
		var ptL = path[L - 1]
		if is_pipe_connected_on_inlet(c, ptL, true):
			return { "pipe": p, "endpoint_idx": L - 1 }
				
	return {}

func find_connected_cannon(pt: Vector2i) -> Dictionary:
	for c in active_cannons:
		if abs(pt.x - c.pos.x) <= 4 and abs(pt.y - c.pos.y) <= 8:
			if abs(pt.x - c.pos.x) < 4 or abs(pt.y - c.pos.y) < 8:
				return { "cannon": c }
	return {}

func is_cannon_base_material(mat: int) -> bool:
	return mat == 95 or mat == 195 or mat == 295 or mat == 395 or mat == 495 or mat == 595 or mat == 695 or mat == 795

func get_next_cannon_shoot_material(c) -> int:
	var loaded_mat = c.get("loaded_material", 0)
	if loaded_mat > 0:
		c["loaded_material"] = 0
		return loaded_mat
		
	var end_info = find_connected_pipe_and_endpoint(c)
	if not end_info.is_empty():
		var p = end_info["pipe"]
		var idx = end_info["endpoint_idx"]
		var elems = p.elements[idx]
		for i in range(elems.size()):
			var elem = elems[i]
			if not elem.has("npc_id") and elem.get("mat", 0) > 0:
				var mat = elem.mat
				elems.remove_at(i)
				return mat
				
	return find_cannon_inlet_material(c)

func fire_cannon(c, loaded_mat1: int = 0, loaded_mat2: int = 0, is_stream: bool = false) -> void:
	var orient = c.get("orientation", 0)
	var start_x = float(c.pos.x)
	var start_y = float(c.pos.y)
	var vx = 0.0
	var vy = 0.0
	
	var center_x = start_x
	var center_y = start_y
	var px = 0.0
	var py = 0.0
	
	if orient == 0: # 0 deg (Right)
		center_x += 5.5
		center_y += 1.5
		vx = 180.0
		vy = 0.0
		px = 0.0
		py = 1.0
	elif orient == 1: # 45 deg (Top-Right)
		center_x += 5.0
		center_y -= 2.0
		vx = 127.28
		vy = -127.28
		px = 0.707
		py = 0.707
	elif orient == 2: # 90 deg (Up)
		center_x += 1.5
		center_y -= 3.0
		vx = 0.0
		vy = -180.0
		px = 1.0
		py = 0.0
	elif orient == 3: # 135 deg (Top-Left)
		center_x -= 2.0
		center_y -= 2.0
		vx = -127.28
		vy = -127.28
		px = -0.707
		py = 0.707
	elif orient == 4: # 180 deg (Left)
		center_x -= 2.0
		center_y += 1.5
		vx = -180.0
		vy = 0.0
		px = 0.0
		py = 1.0
	elif orient == 5: # 225 deg (Bottom-Left)
		center_x -= 2.0
		center_y += 5.0
		vx = -127.28
		vy = 127.28
		px = -0.707
		py = -0.707
	elif orient == 6: # 270 deg (Down)
		center_x += 1.5
		center_y += 6.0
		vx = 0.0
		vy = 180.0
		px = 1.0
		py = 0.0
	elif orient == 7: # 315 deg (Bottom-Right)
		center_x += 5.0
		center_y += 5.0
		vx = 127.28
		vy = 127.28
		px = 0.707
		py = -0.707
		
	var power = c.get("shoot_power", CANNON_POWER_MED)
	vx *= power
	vy *= power
	
	var vol_boost = -18.0 if is_stream else -5.0
	grid._play_action_sound("explosion", 0.05, vol_boost, 1.8)
	
	var posA = Vector2(center_x - px * 0.5, center_y - py * 0.5)
	var posB = Vector2(center_x + px * 0.5, center_y + py * 0.5)
	
	var launch_projectile = func(pos: Vector2, mat: int):
		if mat > 0 and mat != 3:
			# Launch block material
			var tx = int(round(pos.x))
			var ty = int(round(pos.y))
			var success = false
			if tx >= 0 and tx < grid.grid_width and ty >= 0 and ty < grid.dynamic_grid_height:
				var old_mat = grid._get_cell(tx, ty)
				grid._set_cell(tx, ty, mat)
				success = grid._launch_flying_block(tx, ty, vx, vy, -1, 3.0, 120.0)
				if not success:
					grid._set_cell(tx, ty, old_mat)
			if not success:
				grid.active_projectiles.append({
					"pos": pos,
					"vel": Vector2(vx, vy),
					"team": -1,
					"type": "thrown_rock",
					"life": 3.0,
					"block_material": mat,
					"atk_dmg": 1.5,
					"gravity": 120.0
				})
		else:
			# Launch fireball
			grid.active_projectiles.append({
				"pos": pos,
				"vel": Vector2(vx, vy),
				"team": -1,
				"type": "fireball",
				"life": 3.0,
				"atk_dmg": 1.0,
				"gravity": 0.0
			})

	var fire_A = false
	var fire_B = false
	
	if loaded_mat1 > 0:
		fire_A = true
	if loaded_mat2 > 0:
		fire_B = true
	if loaded_mat1 == 0 and loaded_mat2 == 0:
		fire_A = true
		fire_B = true
		
	if fire_A:
		launch_projectile.call(posA, loaded_mat1)
	if fire_B:
		launch_projectile.call(posB, loaded_mat2)

func find_cannon_inlet_material(c) -> int:
	var cx = c.pos.x
	var cy = c.pos.y
	var inlet_side = c.get("inlet_side", "")
	
	# Fallback if inlet_side is not set yet
	if inlet_side == "":
		var orient = c.get("orientation", 0)
		if orient == 0: inlet_side = "left"
		elif orient == 1: inlet_side = "bottom"
		elif orient == 2: inlet_side = "bottom"
		elif orient == 3: inlet_side = "bottom"
		elif orient == 4: inlet_side = "right"
		else: inlet_side = "left"
		c["inlet_side"] = inlet_side
		
	var check_cells = []
	if inlet_side == "left":
		for oy in range(4):
			check_cells.append(Vector2i(cx - 5, cy + oy))
	elif inlet_side == "right":
		for oy in range(4):
			check_cells.append(Vector2i(cx + 8, cy + oy))
	elif inlet_side == "top":
		for ox in range(4):
			check_cells.append(Vector2i(cx + ox, cy - 5))
	elif inlet_side == "bottom":
		for ox in range(4):
			check_cells.append(Vector2i(cx + ox, cy + 8))
			
	for pt in check_cells:
		if pt.x >= 0 and pt.x < grid.grid_width and pt.y >= 0 and pt.y < grid.dynamic_grid_height:
			var mat = grid._get_cell(pt.x, pt.y)
			if mat > 0 and not is_cannon_base_material(mat) and mat != 96:
				var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
				if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
					# Absorb the cell
					grid._set_cell(pt.x, pt.y, 0)
					return mat
	return 0

func simulate_cannons(delta: float) -> void:
	if not is_instance_valid(grid) or grid.cells.size() == 0: return
	var idx = active_cannons.size() - 1
	while idx >= 0:
		if idx >= active_cannons.size():
			idx -= 1
			continue
		var c = active_cannons[idx]
		
		# Lazy cleanup: check if cannon base still exists
		var base_cx = c.pos.x + 2
		var base_cy = c.pos.y + 2
		if base_cx < 0 or base_cx >= grid.grid_width or base_cy < 0 or base_cy >= grid.grid_height:
			active_cannons.remove_at(idx)
			idx -= 1
			continue
		var base_mat = grid.cells[base_cy * grid.grid_width + base_cx] & 0xFFFF
		if not is_cannon_base_material(base_mat):
			# Clear all parts of this cannon structure to avoid orphaned pieces
			for py in range(10):
				for px in range(10):
					var tx = c.pos.x + px - 3
					var ty = c.pos.y + py - 3
					if tx >= 0 and tx < grid.grid_width and ty >= 0 and ty < grid.dynamic_grid_height:
						var m = grid.cells[ty * grid.grid_width + tx] & 0xFFFF
						if is_cannon_base_material(m):
							grid._set_cell(tx, ty, 0)
			active_cannons.remove_at(idx)
			idx -= 1
			continue
			
		if c.get("cooldown", 0.0) > 0.0:
			c.cooldown -= delta
			
		if c.get("cooldown", 0.0) <= 0.0:
			var powered = is_cannon_powered(c)
			var is_stream = powered
			var cooldown_time = 0.06 if powered else 1.0
			
			var loaded1 = get_next_cannon_shoot_material(c)
			if loaded1 > 0:
				var loaded2 = get_next_cannon_shoot_material(c)
				if loaded2 == 0:
					loaded2 = loaded1
				fire_cannon(c, loaded1, loaded2, is_stream)
				c.cooldown = cooldown_time
			else:
				# 2. If no material loaded, fallback to electricity powered firing (infinite fireballs)
				if powered:
					fire_cannon(c, 0, 0, is_stream)
					c.cooldown = cooldown_time
			
		idx -= 1

func is_orientation_allowed(orient: int, inlet_side: String) -> bool:
	if inlet_side == "left":
		return orient != 3 and orient != 4 and orient != 5
	elif inlet_side == "right":
		return orient != 7 and orient != 0 and orient != 1
	elif inlet_side == "top":
		return orient != 1 and orient != 2 and orient != 3
	elif inlet_side == "bottom":
		return orient != 5 and orient != 6 and orient != 7
	return true

func open_cannon_settings_panel(c) -> void:
	if is_instance_valid(cannon_settings_panel):
		cannon_settings_panel.queue_free()
		
	var s = grid._get_ui_scale()
	
	cannon_settings_panel = PanelContainer.new()
	cannon_settings_panel.name = "CannonSettingsPanel"
	grid.ui_root.add_child(cannon_settings_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95) # Dark premium slate
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.8, 0.6, 0.2) # Glowing gold border
	panel_style.corner_radius_top_left = 24
	panel_style.corner_radius_top_right = 24
	panel_style.corner_radius_bottom_left = 24
	panel_style.corner_radius_bottom_right = 24
	cannon_settings_panel.add_theme_stylebox_override("panel", panel_style)
	cannon_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	grid._align_panel_to_hud(cannon_settings_panel, 340 * s, 460 * s)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15 * s)
	cannon_settings_panel.add_child(main_vbox)
	
	# Header
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	var spacer_left = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_left)
	
	var title = Label.new()
	title.text = "Controlador"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", grid._get_safe_font())
	title.add_theme_font_size_override("font_size", 28 * s)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	header_hbox.add_child(title)
	
	var spacer_right = Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_right)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40 * s, 40 * s)
	close_btn.add_theme_font_override("font", grid._get_safe_font())
	close_btn.add_theme_font_size_override("font_size", 18 * s)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.35, 0.15, 0.15, 0.8)
	close_style.set_corner_radius_all(20 * s)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.pressed.connect(func():
		grid._play_action_sound("ui_click")
		cannon_settings_panel.queue_free()
	)
	header_hbox.add_child(close_btn)
	
	var div = ColorRect.new()
	div.custom_minimum_size.y = 2 * s
	div.color = Color(0.3, 0.3, 0.4, 0.5)
	main_vbox.add_child(div)
	
	# Direction row
	var dir_hbox = HBoxContainer.new()
	dir_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dir_hbox.add_theme_constant_override("separation", 20 * s)
	main_vbox.add_child(dir_hbox)
	
	var btn_left = Button.new()
	btn_left.text = "◀"
	btn_left.custom_minimum_size = Vector2(50 * s, 50 * s)
	btn_left.add_theme_font_size_override("font_size", 22 * s)
	var arrow_style = StyleBoxFlat.new()
	arrow_style.bg_color = Color(0.2, 0.2, 0.28, 0.9)
	arrow_style.border_width_left = 1; arrow_style.border_width_top = 1; arrow_style.border_width_right = 1; arrow_style.border_width_bottom = 1
	arrow_style.border_color = Color(0.5, 0.5, 0.6)
	arrow_style.set_corner_radius_all(10 * s)
	btn_left.add_theme_stylebox_override("normal", arrow_style)
	dir_hbox.add_child(btn_left)
	
	var dir_label = Label.new()
	dir_label.text = "Dirección"
	dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dir_label.add_theme_font_override("font", grid._get_safe_font())
	dir_label.add_theme_font_size_override("font_size", 20 * s)
	dir_hbox.add_child(dir_label)
	
	var btn_right = Button.new()
	btn_right.text = "▶"
	btn_right.custom_minimum_size = Vector2(50 * s, 50 * s)
	btn_right.add_theme_font_size_override("font_size", 22 * s)
	btn_right.add_theme_stylebox_override("normal", arrow_style)
	dir_hbox.add_child(btn_right)
	
	# Preview
	var preview_container = PanelContainer.new()
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.04, 0.04, 0.06, 1.0)
	preview_style.border_width_left = 2; preview_style.border_width_top = 2; preview_style.border_width_right = 2; preview_style.border_width_bottom = 2
	preview_style.border_color = Color(0.25, 0.25, 0.35)
	preview_style.corner_radius_top_left = 12
	preview_style.corner_radius_top_right = 12
	preview_style.corner_radius_bottom_left = 12
	preview_style.corner_radius_bottom_right = 12
	preview_container.add_theme_stylebox_override("panel", preview_style)
	preview_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(preview_container)
	
	var preview_ctrl = Control.new()
	preview_ctrl.custom_minimum_size = Vector2(180 * s, 180 * s)
	preview_container.add_child(preview_ctrl)
	
	var conn_label = Label.new()
	conn_label.text = "Conexión de Tubería"
	conn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conn_label.add_theme_font_override("font", grid._get_safe_font())
	conn_label.add_theme_font_size_override("font_size", 18 * s)
	conn_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(conn_label)
	
	var update_inlet_buttons_ref = [null]
	
	var redraw_preview = func():
		preview_ctrl.queue_redraw()
		
	var update_cannon_in_grid = func():
		for py in range(12):
			for px in range(12):
				var tx = c.pos.x + px - 4
				var ty = c.pos.y + py - 4
				if tx >= 0 and tx < grid.grid_width and ty >= 0 and ty < grid.grid_height:
					grid._set_cell(tx, ty, 0)
					
		var inlet_side = c.get("inlet_side", "left")
		var active_cells = get_cannon_active_cells(c.orientation, inlet_side)
		var mat_id = 95 + c.orientation * 100
		for pt in active_cells:
			var tx = c.pos.x + pt.x - 4
			var ty = c.pos.y + pt.y - 4
			if tx >= 0 and tx < grid.grid_width and ty >= 0 and ty < grid.grid_height:
				var variant = pt.x | (pt.y << 4)
				var val_encoded = mat_id | (variant << 24)
				grid._set_cell(tx, ty, val_encoded)
				
	var change_orientation = func(delta_orient: int):
		grid._play_action_sound("ui_click")
		c.orientation = (c.orientation + delta_orient) % 8
		if c.orientation < 0: c.orientation += 8
		
		# If the current inlet side is blocked by the new barrel orientation, auto-switch to an allowed side
		if not is_orientation_allowed(c.orientation, c.get("inlet_side", "left")):
			for candidate in ["left", "bottom", "right", "top"]:
				if is_orientation_allowed(c.orientation, candidate):
					c["inlet_side"] = candidate
					break
					
		update_cannon_in_grid.call()
		if update_inlet_buttons_ref[0] != null:
			update_inlet_buttons_ref[0].call()
		redraw_preview.call()

	btn_left.pressed.connect(func():
		change_orientation.call(1) # Giro contra-horario
	)
	
	btn_right.pressed.connect(func():
		change_orientation.call(-1) # Giro horario
	)
	
	# Allow touching the preview directly to change connection side
	preview_ctrl.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var rel = event.position - preview_ctrl.size / 2.0
			var clicked_side = ""
			if abs(rel.x) > abs(rel.y):
				clicked_side = "right" if rel.x > 0 else "left"
			else:
				clicked_side = "bottom" if rel.y > 0 else "top"
				
			if is_orientation_allowed(c.orientation, clicked_side):
				c["inlet_side"] = clicked_side
				grid._play_action_sound("ui_click")
				update_cannon_in_grid.call()
				if update_inlet_buttons_ref[0] != null:
					update_inlet_buttons_ref[0].call()
				redraw_preview.call()
	)
	
	preview_ctrl.draw.connect(func():
		var size = preview_ctrl.size
		var pixel_size = size.x / 12.0
		var inlet_side = c.get("inlet_side", "left")
		var orient = c.orientation
		var active_cells = get_cannon_active_cells(orient, inlet_side)
		
		# Draw active cannon pixels using the exact game shader palette
		for pt in active_cells:
			var px = pt.x
			var py = pt.y
			var is_body = (px >= 4 and px <= 7 and py >= 4 and py <= 7)
			var is_pivot = false
			var is_barrel = false
			
			if orient == 0:
				if px == 8 and (py == 5 or py == 6): is_pivot = true
				elif px == 9 and (py == 5 or py == 6): is_barrel = true
			elif orient == 1:
				if (px == 7 and py == 3) or (px == 8 and py == 4): is_pivot = true
				elif (px == 8 and (py == 2 or py == 3)) or (px == 9 and py == 3): is_barrel = true
			elif orient == 2:
				if (px == 5 or px == 6) and py == 3: is_pivot = true
				elif (px == 5 or px == 6) and (py == 1 or py == 2): is_barrel = true
			elif orient == 3:
				if (px == 4 and py == 3) or (px == 3 and py == 4): is_pivot = true
				elif (px == 3 and (py == 2 or py == 3)) or (px == 2 and py == 3): is_barrel = true
			elif orient == 4:
				if px == 3 and (py == 5 or py == 6): is_pivot = true
				elif px == 2 and (py == 5 or py == 6): is_barrel = true
			elif orient == 5:
				if (px == 4 and py == 8) or (px == 3 and py == 7): is_pivot = true
				elif (px == 3 and (py == 9 or py == 8)) or (px == 2 and py == 8): is_barrel = true
			elif orient == 6:
				if (px == 5 or px == 6) and py == 8: is_pivot = true
				elif (px == 5 or px == 6) and (py == 10 or py == 9): is_barrel = true
			elif orient == 7:
				if (px == 7 and py == 8) or (px == 8 and py == 7): is_pivot = true
				elif (px == 8 and (py == 9 or py == 8)) or (px == 9 and py == 8): is_barrel = true
				
			var is_base = not is_body and not is_pivot and not is_barrel
			var cell_color = Color(0.35, 0.46, 0.57) # Steel blue default
			
			if is_base:
				cell_color = Color(0.96, 0.96, 0.98) # Creamy white
			elif is_pivot:
				cell_color = Color(0.96, 0.1, 0.1) # Bright red
			elif is_body:
				if px >= 5 and px <= 6 and py >= 5 and py <= 6:
					cell_color = Color(0.85, 0.35, 0.1) # Warm ember core
				elif px == 4 or px == 7 or py == 4 or py == 7:
					cell_color = Color(0.22, 0.28, 0.35) # Dark metallic frame
				else:
					cell_color = Color(0.35, 0.46, 0.57) # Steel blue body
			elif is_barrel:
				var is_tip = false
				if orient == 0 and px == 9: is_tip = true
				elif orient == 1 and px == 9 and py == 2: is_tip = true
				elif orient == 2 and py == 1: is_tip = true
				elif orient == 3 and px == 2 and py == 2: is_tip = true
				elif orient == 4 and px == 2: is_tip = true
				elif orient == 5 and px == 2 and py == 9: is_tip = true
				elif orient == 6 and py == 10: is_tip = true
				elif orient == 7 and px == 9 and py == 9: is_tip = true
				
				if is_tip:
					cell_color = Color(0.18, 0.22, 0.28) # Dark muzzle opening
				else:
					cell_color = Color(0.35, 0.46, 0.57) # Barrel body
					
			preview_ctrl.draw_rect(Rect2(px * pixel_size, py * pixel_size, pixel_size, pixel_size), cell_color)

		# Draw interactive inlet indicators around perimeter
		var indicator_radius = 5.0 * s
		var indicator_positions = {
			"left": Vector2(8 * s, size.y / 2.0),
			"right": Vector2(size.x - 8 * s, size.y / 2.0),
			"top": Vector2(size.x / 2.0, 8 * s),
			"bottom": Vector2(size.x / 2.0, size.y - 8 * s)
		}
		for side_name in indicator_positions.keys():
			var ipos = indicator_positions[side_name]
			var allowed = is_orientation_allowed(orient, side_name)
			if side_name == inlet_side:
				preview_ctrl.draw_circle(ipos, indicator_radius + 3 * s, Color(0.2, 0.7, 1.0, 0.9))
				preview_ctrl.draw_circle(ipos, indicator_radius, Color(1.0, 0.84, 0.0, 1.0))
			elif allowed:
				preview_ctrl.draw_circle(ipos, indicator_radius, Color(0.3, 0.8, 0.4, 0.5))
			else:
				preview_ctrl.draw_circle(ipos, indicator_radius - 1 * s, Color(0.8, 0.2, 0.2, 0.4))
	)
	
	# Inlet side selection buttons
	var inlet_grid = GridContainer.new()
	inlet_grid.columns = 4
	inlet_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inlet_grid.add_theme_constant_override("h_separation", 10 * s)
	main_vbox.add_child(inlet_grid)
	
	var sides = ["left", "right", "top", "bottom"]
	var side_labels = ["Izquierda", "Derecha", "Arriba", "Abajo"]
	var side_btns = []
	
	var update_inlet_buttons = func():
		var current_inlet = c.get("inlet_side", "left")
		for idx in range(sides.size()):
			var side = sides[idx]
			var btn = side_btns[idx]
			var is_allowed = is_orientation_allowed(c.orientation, side)
			btn.disabled = not is_allowed
			var b_style = StyleBoxFlat.new()
			if side == current_inlet:
				b_style.bg_color = Color(0.2, 0.5, 0.8, 1.0) # Active
				b_style.border_color = Color(1.0, 0.84, 0.0)
				b_style.border_width_left = 2; b_style.border_width_top = 2; b_style.border_width_right = 2; b_style.border_width_bottom = 2
			elif not is_allowed:
				b_style.bg_color = Color(0.12, 0.12, 0.15, 0.4) # Disabled
				b_style.border_color = Color(0.2, 0.2, 0.25)
				b_style.border_width_left = 1; b_style.border_width_top = 1; b_style.border_width_right = 1; b_style.border_width_bottom = 1
			else:
				b_style.bg_color = Color(0.15, 0.15, 0.22, 0.8) # Normal
				b_style.border_color = Color(0.4, 0.4, 0.5)
				b_style.border_width_left = 1; b_style.border_width_top = 1; b_style.border_width_right = 1; b_style.border_width_bottom = 1
			b_style.set_corner_radius_all(8 * s)
			btn.add_theme_stylebox_override("normal", b_style)
			btn.add_theme_stylebox_override("disabled", b_style)
			
	update_inlet_buttons_ref[0] = update_inlet_buttons
			
	for idx in range(sides.size()):
		var side = sides[idx]
		var btn = Button.new()
		btn.text = side_labels[idx]
		btn.custom_minimum_size = Vector2(70 * s, 36 * s)
		btn.add_theme_font_override("font", grid._get_safe_font())
		btn.add_theme_font_size_override("font_size", 14 * s)
		btn.pressed.connect(func():
			grid._play_action_sound("ui_click")
			if is_orientation_allowed(c.orientation, side):
				c["inlet_side"] = side
				update_cannon_in_grid.call()
				update_inlet_buttons.call()
				redraw_preview.call()
		)
		side_btns.append(btn)
		inlet_grid.add_child(btn)
		
	update_inlet_buttons.call()
	
	# Power adjustment row
	var power_label = Label.new()
	power_label.text = "Potencia de Disparo"
	power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_label.add_theme_font_override("font", grid._get_safe_font())
	power_label.add_theme_font_size_override("font_size", 18 * s)
	power_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(power_label)
	
	var slider_hbox = HBoxContainer.new()
	slider_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slider_hbox.add_theme_constant_override("separation", 10 * s)
	main_vbox.add_child(slider_hbox)
	
	var power_val_label = Label.new()
	power_val_label.custom_minimum_size = Vector2(50 * s, 0)
	power_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_val_label.add_theme_font_override("font", grid._get_safe_font())
	power_val_label.add_theme_font_size_override("font_size", 18 * s)
	power_val_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	
	var update_power_label = func(val: float):
		if val <= 0.5:
			power_val_label.text = "Min"
		elif val <= 0.9:
			power_val_label.text = "Med"
		else:
			power_val_label.text = "Max"
			
	update_power_label.call(c.get("shoot_power", CANNON_POWER_MED))
	slider_hbox.add_child(power_val_label)
	
	var power_slider = HSlider.new()
	power_slider.custom_minimum_size = Vector2(180 * s, 30 * s)
	power_slider.min_value = CANNON_POWER_MIN
	power_slider.max_value = CANNON_POWER_MAX
	power_slider.step = 0.05
	power_slider.value = c.get("shoot_power", CANNON_POWER_MED)
	power_slider.value_changed.connect(func(val):
		c["shoot_power"] = val
		update_power_label.call(val)
		grid._play_action_sound("ui_click")
	)
	slider_hbox.add_child(power_slider)

# ==============================================================================
# PIPES (STANDARD & X2)
# ==============================================================================

func place_pipe(gx: int, gy: int) -> void:
	if gx < 0 or gx + 3 >= grid.grid_width or gy < 0 or gy + 3 >= grid.grid_height:
		return
		
	# Check if we already have a pipe at this snapping coordinate
	var existing = false
	for p in active_pipes:
		if p.has("path") and Vector2i(gx, gy) in p.path:
			existing = true
			break
			
	if not existing:
		# Draw the 4x4 block of material ID 96
		for oy in range(4):
			for ox in range(4):
				grid._set_cell(gx + ox, gy + oy, 96)
		reconstruct_sources_from_cells()
		grid._play_action_sound("ui_click")

func place_pipe_x2(gx: int, gy: int) -> void:
	if gx < 0 or gx + 7 >= grid.grid_width or gy < 0 or gy + 7 >= grid.grid_height:
		return
		
	# Check if we already have a pipe x2 at this snapping coordinate
	var existing = false
	for p in active_pipes_x2:
		if p.has("path") and Vector2i(gx, gy) in p.path:
			existing = true
			break
			
	if not existing:
		# Draw the 8x8 block of material ID 97
		for oy in range(8):
			for ox in range(8):
				grid._set_cell(gx + ox, gy + oy, 97)
		reconstruct_sources_from_cells()
		grid._play_action_sound("ui_click")

func update_pipe_visuals(p, pass_index = -1) -> void:
	var path = p.path
	var L = path.size()
	
	var phase = grid._frame_count % 10
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
			grid._set_cell(gx, gy, 96)
			grid._set_cell(gx + 3, gy, 96)
			grid._set_cell(gx, gy + 3, 96)
			grid._set_cell(gx + 3, gy + 3, 96)
			
			if is_top_open:
				grid._set_cell(gx + 1, gy, 0)
				grid._set_cell(gx + 2, gy, 0)
			else:
				grid._set_cell(gx + 1, gy, 96)
				grid._set_cell(gx + 2, gy, 96)
				
			if is_bottom_open:
				grid._set_cell(gx + 1, gy + 3, 0)
				grid._set_cell(gx + 2, gy + 3, 0)
			else:
				grid._set_cell(gx + 1, gy + 3, 96)
				grid._set_cell(gx + 2, gy + 3, 96)
				
			if is_left_open:
				grid._set_cell(gx, gy + 1, 0)
				grid._set_cell(gx, gy + 2, 0)
			else:
				grid._set_cell(gx, gy + 1, 96)
				grid._set_cell(gx, gy + 2, 96)
				
			if is_right_open:
				grid._set_cell(gx + 3, gy + 1, 0)
				grid._set_cell(gx + 3, gy + 2, 0)
			else:
				grid._set_cell(gx + 3, gy + 1, 96)
				grid._set_cell(gx + 3, gy + 2, 96)
				
			# Core interior
			grid._set_cell(gx + 1, gy + 1, 0)
			grid._set_cell(gx + 2, gy + 1, 0)
			grid._set_cell(gx + 1, gy + 2, 0)
			grid._set_cell(gx + 2, gy + 2, 0)
			
		is_hollowing_pipe = false
		
	if pass_index == -1 or pass_index == 1:
		# Second pass: dynamic elements/liquids inside the pipe
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
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
						
			var elem_mat = 0
			var elem_npc_id = -1
			if i < p.elements.size():
				for elem in p.elements[i]:
					if elem.has("npc_id"):
						elem_npc_id = elem.npc_id
						break
					elif elem.get("mat", 0) > 0 and elem_mat == 0:
						elem_mat = elem.mat
					
			if elem_npc_id != -1:
				var npc: Variant = find_npc_by_id(elem_npc_id)
				if npc != null:
					var cur_pt = path[i]
					var next_pt = cur_pt
					if flow_dir != 0:
						var next_i = i + flow_dir
						if next_i >= 0 and next_i < L:
							next_pt = path[next_i]
						else:
							var end_side = find_pipe_endpoint_opening_side(p, i)
							if end_side == "left": next_pt = cur_pt + Vector2i(-4, 0)
							elif end_side == "right": next_pt = cur_pt + Vector2i(4, 0)
							elif end_side == "top": next_pt = cur_pt + Vector2i(0, -4)
							elif end_side == "bottom": next_pt = cur_pt + Vector2i(0, 4)
					var t = float(grid._frame_count % 10) / 10.0
					var interp = Vector2(cur_pt).lerp(Vector2(next_pt), t)
					npc.pos = interp + Vector2(1.0, 2.0)
					npc.vel = Vector2.ZERO
					npc["is_in_pipe"] = true
					npc.current_emoji = "😮"
					npc.emoji_timer = 2.0
					
				# Clean air (0) inside pipe core - no pink block
				grid._set_cell(gx + 1, gy + 1, 0)
				grid._set_cell(gx + 2, gy + 1, 0)
				grid._set_cell(gx + 1, gy + 2, 0)
				grid._set_cell(gx + 2, gy + 2, 0)
				
				if is_top_open:
					grid._set_cell(gx + 1, gy, 0); grid._set_cell(gx + 2, gy, 0)
				if is_bottom_open:
					grid._set_cell(gx + 1, gy + 3, 0); grid._set_cell(gx + 2, gy + 3, 0)
				if is_left_open:
					grid._set_cell(gx, gy + 1, 0); grid._set_cell(gx, gy + 2, 0)
				if is_right_open:
					grid._set_cell(gx + 3, gy + 1, 0); grid._set_cell(gx + 3, gy + 2, 0)
			elif elem_mat > 0:
				grid._set_cell(gx + 1, gy + 1, elem_mat)
				grid._set_cell(gx + 2, gy + 1, elem_mat)
				grid._set_cell(gx + 1, gy + 2, elem_mat)
				grid._set_cell(gx + 2, gy + 2, elem_mat)
				
				if is_top_open:
					grid._set_cell(gx + 1, gy, elem_mat); grid._set_cell(gx + 2, gy, elem_mat)
				if is_bottom_open:
					grid._set_cell(gx + 1, gy + 3, elem_mat); grid._set_cell(gx + 2, gy + 3, elem_mat)
				if is_left_open:
					grid._set_cell(gx, gy + 1, elem_mat); grid._set_cell(gx, gy + 2, elem_mat)
				if is_right_open:
					grid._set_cell(gx + 3, gy + 1, elem_mat); grid._set_cell(gx + 3, gy + 2, elem_mat)
			else:
				# Clean air (0) - no purple ghost blocks
				grid._set_cell(gx + 1, gy + 1, 0)
				grid._set_cell(gx + 2, gy + 1, 0)
				grid._set_cell(gx + 1, gy + 2, 0)
				grid._set_cell(gx + 2, gy + 2, 0)
				
				if is_top_open:
					grid._set_cell(gx + 1, gy, 0); grid._set_cell(gx + 2, gy, 0)
				if is_bottom_open:
					grid._set_cell(gx + 1, gy + 3, 0); grid._set_cell(gx + 2, gy + 3, 0)
				if is_left_open:
					grid._set_cell(gx, gy + 1, 0); grid._set_cell(gx, gy + 2, 0)
				if is_right_open:
					grid._set_cell(gx + 3, gy + 1, 0); grid._set_cell(gx + 3, gy + 2, 0)

func update_pipe_x2_visuals(p, pass_index = -1) -> void:
	var path = p.path
	var L = path.size()
	
	var phase = grid._frame_count % 10
	var flow_dir = p.get("flow_dir", 0)
	
	if pass_index == -1 or pass_index == 0:
		is_hollowing_pipe = true
		
		# First pass: static pipe structure (walls + air core 0)
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
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
						
			# Draw the 8x8 block with 1px border
			for oy in range(8):
				for ox in range(8):
					var is_edge = (ox == 0 or ox == 7 or oy == 0 or oy == 7)
					if not is_edge:
						grid._set_cell(gx + ox, gy + oy, 0)
					else:
						var is_open = false
						if ox == 0 and is_left_open and oy >= 1 and oy <= 6: is_open = true
						elif ox == 7 and is_right_open and oy >= 1 and oy <= 6: is_open = true
						elif oy == 0 and is_top_open and ox >= 1 and ox <= 6: is_open = true
						elif oy == 7 and is_bottom_open and ox >= 1 and ox <= 6: is_open = true
						
						grid._set_cell(gx + ox, gy + oy, 0 if is_open else 97)
						
		is_hollowing_pipe = false
		
	if pass_index == -1 or pass_index == 1:
		# Second pass: dynamic elements/liquids inside the pipe
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
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
						
			var elems = p.elements[i] if i < p.elements.size() else []
			var npc_in_block: Variant = null
			for elem in elems:
				if elem.has("npc_id"):
					npc_in_block = find_npc_by_id(elem.npc_id)
					break
					
			if npc_in_block != null:
				var cur_pt = path[i]
				var next_pt = cur_pt
				if flow_dir != 0:
					var next_i = i + flow_dir
					if next_i >= 0 and next_i < L:
						next_pt = path[next_i]
					else:
						var end_side = find_pipe_x2_endpoint_opening_side(p, i)
						if end_side == "left": next_pt = cur_pt + Vector2i(-8, 0)
						elif end_side == "right": next_pt = cur_pt + Vector2i(8, 0)
						elif end_side == "top": next_pt = cur_pt + Vector2i(0, -8)
						elif end_side == "bottom": next_pt = cur_pt + Vector2i(0, 8)
				var t = float(grid._frame_count % 10) / 10.0
				var interp = Vector2(cur_pt).lerp(Vector2(next_pt), t)
				npc_in_block.pos = interp + Vector2(3.0, 4.0)
				npc_in_block.vel = Vector2.ZERO
				npc_in_block["is_in_pipe"] = true
				npc_in_block.current_emoji = "😮"
				npc_in_block.emoji_timer = 2.0
				
				# Clean air (0) inside pipe core - no pink block
				for oy in range(1, 7):
					for ox in range(1, 7):
						grid._set_cell(gx + ox, gy + oy, 0)
				if is_top_open:
					for ox in range(1, 7): grid._set_cell(gx + ox, gy, 0)
				if is_bottom_open:
					for ox in range(1, 7): grid._set_cell(gx + ox, gy + 7, 0)
				if is_left_open:
					for oy in range(1, 7): grid._set_cell(gx, gy + oy, 0)
				if is_right_open:
					for oy in range(1, 7): grid._set_cell(gx + 7, gy + oy, 0)
			elif elems.size() > 0:
				var side = find_pipe_x2_endpoint_opening_side(p, i)
				var is_horiz = (side == "left" or side == "right")
				for elem in elems:
					var mat = elem.get("mat", 0)
					var lane = clamp(elem.get("lane", 2), 1, 6)
					if is_horiz:
						for ox in range(1, 7):
							grid._set_cell(gx + ox, gy + lane, mat)
						if is_left_open: grid._set_cell(gx, gy + lane, mat)
						if is_right_open: grid._set_cell(gx + 7, gy + lane, mat)
					else:
						for oy in range(1, 7):
							grid._set_cell(gx + lane, gy + oy, mat)
						if is_top_open: grid._set_cell(gx + lane, gy, mat)
						if is_bottom_open: grid._set_cell(gx + lane, gy + 7, mat)
			else:
				# Clean air (0) - no purple ghost blocks
				for oy in range(1, 7):
					for ox in range(1, 7):
						grid._set_cell(gx + ox, gy + oy, 0)
				if is_top_open:
					for ox in range(1, 7): grid._set_cell(gx + ox, gy, 0)
				if is_bottom_open:
					for ox in range(1, 7): grid._set_cell(gx + ox, gy + 7, 0)
				if is_left_open:
					for oy in range(1, 7): grid._set_cell(gx, gy + oy, 0)
				if is_right_open:
					for oy in range(1, 7): grid._set_cell(gx + 7, gy + oy, 0)

func find_pipe_x2_endpoint_opening_side(p, endpoint_idx: int) -> String:
	var path = p.path
	var L = path.size()
	if L == 0: return "none"
	
	if L == 1:
		return "horizontal"
		
	var pt = path[endpoint_idx]
	var neighbor = path[1] if endpoint_idx == 0 else path[L - 2]
	
	if neighbor.x > pt.x:
		return "left"
	elif neighbor.x < pt.x:
		return "right"
	elif neighbor.y > pt.y:
		return "top"
	elif neighbor.y < pt.y:
		return "bottom"
		
	return "none"

func find_npc_by_id(npc_id: int) -> Variant:
	for npc in grid.active_npcs:
		if npc.id == npc_id:
			return npc
	return null

func find_npc_at_pipe_endpoint(p, endpoint_idx: int, is_x2: bool) -> Variant:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	var min_x = 0
	var max_x = 0
	var min_y = 0
	var max_y = 0
	
	var block_size = 8 if is_x2 else 4
	
	if side == "left":
		min_x = gx - 2
		max_x = gx
		min_y = gy
		max_y = gy + block_size - 1
	elif side == "right":
		min_x = gx + block_size
		max_x = gx + block_size + 2
		min_y = gy
		max_y = gy + block_size - 1
	elif side == "top" or side == "horizontal":
		min_x = gx
		max_x = gx + block_size - 1
		min_y = gy - 2
		max_y = gy
	elif side == "bottom":
		min_x = gx
		max_x = gx + block_size - 1
		min_y = gy + block_size
		max_y = gy + block_size + 2
	else:
		return null
		
	for npc in grid.active_npcs:
		if npc.hp <= 0: continue
		if npc.get("is_in_pipe", false): continue
		
		var w = npc.get("width", 2)
		var h = npc.get("height", 6)
		if npc.get("is_lying", false):
			w = npc.get("height", 6)
			h = npc.get("width", 2)
			
		var overlap_x = not (npc.pos.x + w - 1 < min_x or npc.pos.x > max_x)
		var overlap_y = not (npc.pos.y + h - 1 < min_y or npc.pos.y > max_y)
		if overlap_x and overlap_y:
			return npc
	return null

func try_absorb_npc_at_endpoint(p, endpoint_idx: int, dir: int, is_x2: bool) -> bool:
	var npc: Variant = find_npc_at_pipe_endpoint(p, endpoint_idx, is_x2)
	if npc != null:
		# Always travel through pipe cleanly as emoji
		grid._draw_npc_pixels(npc, 0)
		npc["is_in_pipe"] = true
		npc["pipe_ref"] = p
		grid._set_npc_emoji(npc, "😮", 1.0)
		grid._play_action_sound("medic_heal")
		if is_x2:
			p.elements[endpoint_idx].append({ "mat": 0, "dir": dir, "npc_id": npc.id, "lane": 2 })
		else:
			p.elements[endpoint_idx].append({ "mat": 0, "dir": dir, "npc_id": npc.id })
		return true
	return false

func eject_npc_from_pipe(p, endpoint_idx: int, npc_id: int) -> bool:
	var npc: Variant = find_npc_by_id(npc_id)
	if npc == null: return true
	
	var path = p.path
	var pt = path[endpoint_idx]
	var is_x2 = active_pipes_x2.has(p)
	var side = find_pipe_x2_endpoint_opening_side(p, endpoint_idx) if is_x2 else find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	var target_x = float(pt.x)
	var target_y = float(pt.y)
	var vel_boost = Vector2.ZERO
	
	var block_size = 8 if is_x2 else 4
	
	if side == "left":
		target_x -= 6.0
		target_y += 1.0
		vel_boost = Vector2(-5.0, -3.0)
	elif side == "right":
		target_x += (block_size + 2.0)
		target_y += 1.0
		vel_boost = Vector2(5.0, -3.0)
	elif side == "top" or side == "horizontal":
		target_x += (block_size * 0.5 - 1.0)
		target_y -= 8.0
		vel_boost = Vector2(0.0, -6.0)
	elif side == "bottom":
		target_x += (block_size * 0.5 - 1.0)
		target_y += (block_size + 2.0)
		vel_boost = Vector2(0.0, 3.0)
		
	# Check if exit area has free space
	var tx = int(target_x)
	var ty = int(target_y)
	if tx >= 0 and tx < grid.grid_width and ty >= 0 and ty < grid.dynamic_grid_height:
		var mat = grid._get_cell(tx, ty)
		if mat != 0 and mat != 96 and mat != 97:
			# Blocked exit
			return false
			
	npc.pos = Vector2i(int(target_x), int(target_y))
	npc.vx = vel_boost.x
	npc.vy = vel_boost.y
	npc["is_in_pipe"] = false
	npc.erase("pipe_ref")
	grid._set_npc_emoji(npc, "😎", 1.5)
	grid._play_action_sound("bombardero_siren")
	grid._draw_npc_pixels(npc)
	return true

func find_pipe_endpoint_opening_side(p, endpoint_idx: int) -> String:
	var path = p.path
	var L = path.size()
	if L == 0: return "none"
	
	if L == 1:
		return "horizontal"
		
	var pt = path[endpoint_idx]
	var neighbor = path[1] if endpoint_idx == 0 else path[L - 2]
	
	if neighbor.x > pt.x:
		return "left"
	elif neighbor.x < pt.x:
		return "right"
	elif neighbor.y > pt.y:
		return "top"
	elif neighbor.y < pt.y:
		return "bottom"
		
	return "none"

func find_pipe_absorbable_cell_at_endpoint(p, endpoint_idx: int) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	if side == "left":
		for cy in [gy + 1, gy + 2]:
			var cx = gx - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 96:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
	elif side == "right":
		for cy in [gy + 1, gy + 2]:
			var cx = gx + 4
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 96:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
	elif side == "top" or side == "horizontal":
		for cx in [gx + 1, gx + 2]:
			var cy = gy - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 96:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
	elif side == "bottom":
		for cx in [gx + 1, gx + 2]:
			var cy = gy + 4
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 96:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
						
	return Vector2i(-1, -1)

func find_pipe_ejection_cell_at_endpoint(p, endpoint_idx: int) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	if side == "left":
		for cy in [gy + 1, gy + 2]:
			var cx = gx - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
	elif side == "right":
		for cy in [gy + 1, gy + 2]:
			var cx = gx + 4
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
	elif side == "top" or side == "horizontal":
		for cx in [gx + 1, gx + 2]:
			var cy = gy - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
	elif side == "bottom":
		for cx in [gx + 1, gx + 2]:
			var cy = gy + 4
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
					
	return Vector2i(-1, -1)

func find_pipe_x2_absorbable_cell_at_endpoint(p, endpoint_idx: int) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = find_pipe_x2_endpoint_opening_side(p, endpoint_idx)
	
	if side == "left":
		for cy in range(gy + 1, gy + 7):
			var cx = gx - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 97:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
	elif side == "right":
		for cy in range(gy + 1, gy + 7):
			var cx = gx + 8
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 97:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
	elif side == "top" or side == "horizontal":
		for cx in range(gx + 1, gx + 7):
			var cy = gy - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 97:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
	elif side == "bottom":
		for cx in range(gx + 1, gx + 7):
			var cy = gy + 8
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				var mat = grid._get_cell(cx, cy)
				if mat > 0 and not is_cannon_base_material(mat) and mat != 97:
					var tags = grid.material_tags_raw[grid._get_tags_id(mat)] if grid._get_tags_id(mat) < grid.material_tags_raw.size() else 0
					if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
						return Vector2i(cx, cy)
						
	return Vector2i(-1, -1)

func find_pipe_x2_ejection_cell_at_endpoint(p, endpoint_idx: int, preferred_lane: int = 2) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = find_pipe_x2_endpoint_opening_side(p, endpoint_idx)
	
	var lanes = [preferred_lane]
	for l in range(1, 7):
		if l != preferred_lane: lanes.append(l)
		
	if side == "left":
		for cy_lane in lanes:
			var cy = gy + cy_lane
			var cx = gx - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
	elif side == "right":
		for cy_lane in lanes:
			var cy = gy + cy_lane
			var cx = gx + 8
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
	elif side == "top" or side == "horizontal":
		for cx_lane in lanes:
			var cx = gx + cx_lane
			var cy = gy - 1
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
	elif side == "bottom":
		for cx_lane in lanes:
			var cx = gx + cx_lane
			var cy = gy + 8
			if cx >= 0 and cx < grid.grid_width and cy >= 0 and cy < grid.dynamic_grid_height:
				if grid._get_cell(cx, cy) == 0:
					return Vector2i(cx, cy)
					
	return Vector2i(-1, -1)

func simulate_pipes(_delta: float) -> void:
	if grid._frame_count % 10 != 0: return
	if active_pipes.size() == 0 and active_pipes_x2.size() == 0: return
	
	if true:
		for p in active_pipes:
			var path = p.get("path", [])
			var L = path.size()
			if L == 0: continue
			var end_idx = L - 1
			
			# 1. Check/update flow direction based on contents and input presence
			var total_elems = 0
			for list in p.elements:
				total_elems += list.size()
			if total_elems == 0:
				var empty_ticks = p.get("empty_ticks", 0) + 1
				p["empty_ticks"] = empty_ticks
				if empty_ticks >= 15:
					p["flow_dir"] = 0
			else:
				p["empty_ticks"] = 0
				
			if p.get("flow_dir", 0) == 0:
				if total_elems > 0:
					for list in p.elements:
						if list.size() > 0:
							p["flow_dir"] = list[0].get("dir", 1)
							break
				if p.get("flow_dir", 0) == 0:
					var npc_0 = find_npc_at_pipe_endpoint(p, 0, false)
					if npc_0 != null:
						p["flow_dir"] = 1
					else:
						var npc_end = find_npc_at_pipe_endpoint(p, end_idx, false)
						if npc_end != null:
							p["flow_dir"] = -1
						else:
							var absorb_pos_0 = find_pipe_absorbable_cell_at_endpoint(p, 0)
							if absorb_pos_0.x != -1:
								p["flow_dir"] = 1
							else:
								var absorb_pos_end = find_pipe_absorbable_cell_at_endpoint(p, end_idx)
								if absorb_pos_end.x != -1:
									p["flow_dir"] = -1
						
			var flow_dir = p.get("flow_dir", 0)
			if flow_dir == 1:
				# --- FORWARD SIMULATION (0 -> end_idx) ---
				# Eject at end
				var end_pt = path[end_idx]
				var end_elems = p.elements[end_idx]
				var next_end_elems = []
				var end_conn = find_connected_cannon(end_pt)
				for elem in end_elems:
					if elem.has("npc_id"):
						if not eject_npc_from_pipe(p, end_idx, elem.npc_id):
							next_end_elems.append(elem)
					elif not end_conn.is_empty():
						var c = end_conn["cannon"]
						if c.get("loaded_material", 0) == 0:
							c["loaded_material"] = elem.mat
						else:
							next_end_elems.append(elem)
					else:
						var empty_pos = find_pipe_ejection_cell_at_endpoint(p, end_idx)
						if empty_pos.x != -1:
							grid._set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_end_elems.append(elem)
				p.elements[end_idx] = next_end_elems
				
				# Propagate forward
				for i in range(L - 2, -1, -1):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i+1].size() < 4:
							p.elements[i+1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at start (0)
				while p.elements[0].size() < 4:
					if not try_absorb_npc_at_endpoint(p, 0, 1, false):
						var absorb_pos = find_pipe_absorbable_cell_at_endpoint(p, 0)
						if absorb_pos.x != -1:
							var mat = grid._get_cell(absorb_pos.x, absorb_pos.y)
							grid._set_cell(absorb_pos.x, absorb_pos.y, 0)
							p.elements[0].append({ "mat": mat, "dir": 1 })
						else:
							break
					else:
						break
			elif flow_dir == -1:
				# --- BACKWARD SIMULATION (end_idx -> 0) ---
				# Eject at start (0)
				var start_pt = path[0]
				var start_elems = p.elements[0]
				var next_start_elems = []
				var start_conn = find_connected_cannon(start_pt)
				for elem in start_elems:
					if elem.has("npc_id"):
						if not eject_npc_from_pipe(p, 0, elem.npc_id):
							next_start_elems.append(elem)
					elif not start_conn.is_empty():
						var c = start_conn["cannon"]
						if c.get("loaded_material", 0) == 0:
							c["loaded_material"] = elem.mat
						else:
							next_start_elems.append(elem)
					else:
						var empty_pos = find_pipe_ejection_cell_at_endpoint(p, 0)
						if empty_pos.x != -1:
							grid._set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_start_elems.append(elem)
				p.elements[0] = next_start_elems
				
				# Propagate backward
				for i in range(1, L):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i-1].size() < 4:
							p.elements[i-1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at end
				while p.elements[end_idx].size() < 4:
					if not try_absorb_npc_at_endpoint(p, end_idx, -1, false):
						var absorb_pos = find_pipe_absorbable_cell_at_endpoint(p, end_idx)
						if absorb_pos.x != -1:
							var mat = grid._get_cell(absorb_pos.x, absorb_pos.y)
							grid._set_cell(absorb_pos.x, absorb_pos.y, 0)
							p.elements[end_idx].append({ "mat": mat, "dir": -1 })
						else:
							break
					else:
						break

		# SIMULATION FOR PIPE X2
		for p in active_pipes_x2:
			var path = p.get("path", [])
			var L = path.size()
			if L == 0: continue
			var end_idx = L - 1
			
			var total_elems = 0
			for list in p.elements:
				total_elems += list.size()
			if total_elems == 0:
				var empty_ticks = p.get("empty_ticks", 0) + 1
				p["empty_ticks"] = empty_ticks
				if empty_ticks >= 15:
					p["flow_dir"] = 0
			else:
				p["empty_ticks"] = 0
				
			if p.get("flow_dir", 0) == 0:
				if total_elems > 0:
					for list in p.elements:
						if list.size() > 0:
							p["flow_dir"] = list[0].get("dir", 1)
							break
				if p.get("flow_dir", 0) == 0:
					var npc_0 = find_npc_at_pipe_endpoint(p, 0, true)
					if npc_0 != null:
						p["flow_dir"] = 1
					else:
						var npc_end = find_npc_at_pipe_endpoint(p, end_idx, true)
						if npc_end != null:
							p["flow_dir"] = -1
						else:
							var absorb_pos_0 = find_pipe_x2_absorbable_cell_at_endpoint(p, 0)
							if absorb_pos_0.x != -1:
								p["flow_dir"] = 1
							else:
								var absorb_pos_end = find_pipe_x2_absorbable_cell_at_endpoint(p, end_idx)
								if absorb_pos_end.x != -1:
									p["flow_dir"] = -1
						
			var flow_dir = p.get("flow_dir", 0)
			if flow_dir == 1:
				# Eject at end
				var end_elems = p.elements[end_idx]
				var next_end_elems = []
				for elem in end_elems:
					if elem.has("npc_id"):
						if not eject_npc_from_pipe(p, end_idx, elem.npc_id):
							next_end_elems.append(elem)
					else:
						var preferred_lane = elem.get("lane", 2)
						var empty_pos = find_pipe_x2_ejection_cell_at_endpoint(p, end_idx, preferred_lane)
						if empty_pos.x != -1:
							grid._set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_end_elems.append(elem)
				p.elements[end_idx] = next_end_elems
				
				# Propagate forward
				for i in range(L - 2, -1, -1):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i+1].size() < 32:
							p.elements[i+1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at start (0)
				while p.elements[0].size() < 32:
					if try_absorb_npc_at_endpoint(p, 0, 1, true):
						continue
					var absorb_pos = find_pipe_x2_absorbable_cell_at_endpoint(p, 0)
					if absorb_pos.x != -1:
						var mat = grid._get_cell(absorb_pos.x, absorb_pos.y)
						grid._set_cell(absorb_pos.x, absorb_pos.y, 0)
						var side = find_pipe_x2_endpoint_opening_side(p, 0)
						var pt = path[0]
						var lane = (absorb_pos.y - pt.y) if (side == "left" or side == "right") else (absorb_pos.x - pt.x)
						p.elements[0].append({ "mat": mat, "dir": 1, "lane": lane })
					else:
						break
			elif flow_dir == -1:
				# Eject at start (0)
				var start_elems = p.elements[0]
				var next_start_elems = []
				for elem in start_elems:
					if elem.has("npc_id"):
						if not eject_npc_from_pipe(p, 0, elem.npc_id):
							next_start_elems.append(elem)
					else:
						var preferred_lane = elem.get("lane", 2)
						var empty_pos = find_pipe_x2_ejection_cell_at_endpoint(p, 0, preferred_lane)
						if empty_pos.x != -1:
							grid._set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_start_elems.append(elem)
				p.elements[0] = next_start_elems
				
				# Propagate backward
				for i in range(1, L):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i-1].size() < 32:
							p.elements[i-1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at end
				while p.elements[end_idx].size() < 32:
					if try_absorb_npc_at_endpoint(p, end_idx, -1, true):
						continue
					var absorb_pos = find_pipe_x2_absorbable_cell_at_endpoint(p, end_idx)
					if absorb_pos.x != -1:
						var mat = grid._get_cell(absorb_pos.x, absorb_pos.y)
						grid._set_cell(absorb_pos.x, absorb_pos.y, 0)
						var side = find_pipe_x2_endpoint_opening_side(p, end_idx)
						var pt = path[end_idx]
						var lane = (absorb_pos.y - pt.y) if (side == "left" or side == "right") else (absorb_pos.x - pt.x)
						p.elements[end_idx].append({ "mat": mat, "dir": -1, "lane": lane })
					else:
						break

# ==============================================================================
# LED COLOR PANEL
# ==============================================================================

func open_led_color_panel(color_btn_ref) -> void:
	if is_instance_valid(led_color_panel):
		led_color_panel.queue_free()
		led_color_panel = null
		return
		
	# Close other settings panels if open to prevent overlap
	if is_instance_valid(cannon_settings_panel):
		cannon_settings_panel.queue_free()
		cannon_settings_panel = null
		
	var s = grid._get_ui_scale()
	led_color_panel = PanelContainer.new()
	led_color_panel.name = "LEDColorPanel"
	grid.ui_root.add_child(led_color_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95) # Dark premium slate
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.25, 0.45, 0.85) # Blue theme border
	panel_style.corner_radius_top_left = 20 * s
	panel_style.corner_radius_top_right = 20 * s
	panel_style.corner_radius_bottom_left = 20 * s
	panel_style.corner_radius_bottom_right = 20 * s
	led_color_panel.add_theme_stylebox_override("panel", panel_style)
	led_color_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	grid._align_panel_to_hud(led_color_panel, 280 * s, 190 * s)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	led_color_panel.add_child(main_vbox)
	
	# Header
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	var spacer_left = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_left)
	
	var title = Label.new()
	title.text = tr("led_color_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", grid._get_safe_font())
	title.add_theme_font_size_override("font_size", 20 * s)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	header_hbox.add_child(title)
	
	var spacer_right = Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_right)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30 * s, 30 * s)
	close_btn.add_theme_font_override("font", grid._get_safe_font())
	close_btn.add_theme_font_size_override("font_size", 14 * s)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.35, 0.15, 0.15, 0.8)
	close_style.set_corner_radius_all(15 * s)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_style)
	close_btn.add_theme_stylebox_override("pressed", close_style)
	close_btn.pressed.connect(func():
		grid._play_action_sound("ui_click")
		led_color_panel.queue_free()
		led_color_panel = null
	)
	header_hbox.add_child(close_btn)
	
	# Grid of colors
	var grid_cont = GridContainer.new()
	grid_cont.columns = 4
	grid_cont.add_theme_constant_override("h_separation", 8 * s)
	grid_cont.add_theme_constant_override("v_separation", 8 * s)
	grid_cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(grid_cont)
	
	var colors = [
		Color(1.0, 0.1, 0.1),      # Red
		Color(0.15, 0.45, 1.0),    # Blue
		Color(0.15, 1.0, 0.15),    # Green
		Color(1.0, 0.85, 0.05),    # Yellow
		Color(1.0, 1.0, 1.0),      # White
		Color(1.0, 0.25, 0.75),    # Pink
		Color(0.2, 0.8, 1.0),      # Celeste
		Color(0.5, 0.5, 0.5)       # Rainbow placeholder (animated stylebox)
	]
	
	var led_emojis = ["🔴", "🔵", "🟢", "🟡", "⚪", "💗", "💠", "🌈"]
	
	for idx in range(8):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(50 * s, 50 * s)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		if idx == 7:
			btn.text = "🌈"
			btn.add_theme_font_override("font", grid._get_safe_font())
			btn.add_theme_font_size_override("font_size", 20 * s)
		
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = colors[idx]
		b_style.set_corner_radius_all(10 * s)
		if idx == selected_led_color:
			b_style.border_width_left = 2
			b_style.border_width_top = 2
			b_style.border_width_right = 2
			b_style.border_width_bottom = 2
			b_style.border_color = Color(1.0, 1.0, 0.0) # Highlight yellow
			
		btn.add_theme_stylebox_override("normal", b_style)
		btn.add_theme_stylebox_override("hover", b_style)
		btn.add_theme_stylebox_override("pressed", b_style)
		
		btn.pressed.connect(func():
			grid._play_action_sound("ui_click")
			selected_led_color = idx
			if is_instance_valid(color_btn_ref):
				color_btn_ref.text = led_emojis[selected_led_color]
			
			# Select LED tool automatically
			grid.selected_material = 89
			selected_circuit_tool = ""
			is_mechanism_mode_active = true
			grid._close_music_menu()
			
			# Close panel
			led_color_panel.queue_free()
			led_color_panel = null
		)
		
		# Tag the rainbow button so we can animate it
		if idx == 7:
			btn.set_meta("is_rainbow_btn", true)
			
		grid_cont.add_child(btn)
