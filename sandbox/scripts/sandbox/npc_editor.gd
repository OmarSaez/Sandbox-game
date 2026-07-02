extends Control

const GRID_SIZE = 20

var grid_cells = []
var data_matrix = []
var current_brush = 1
var current_team_preview = 0 # 0: Red, 1: Blue, 2: Yellow, 3: Green
var is_drawing = false
var current_loaded_npc = "warrior"
var show_grid_lines = true

var palette_buttons = []
var color_pickers = {}

var custom_base_colors = {}
var custom_team_colors = {0: {}, 1: {}, 2: {}, 3: {}}

const SandboxGrid = preload("res://scripts/sandbox/sandbox_grid.gd")

const NPC_MAT_COLORS = {
	1001: Color("717E80"), 1002: Color("1F1F1F"), 1003: Color("FFE2BD"), 1008: Color("717E80"),
	1004: Color("E00000"), 1005: Color("008EE6"), 1006: Color("FFD000"), 1007: Color("00E317"),
	1070: Color("A83938"), 1071: Color("F2F2F2"), 1072: Color("FFD8B3"), 1074: Color("A83938"),
	1075: Color("384BA8"), 1076: Color("C79B1E"), 1077: Color("74A838"), 1011: Color("9C5B00"),
	1013: Color("FFBC78"), 1014: Color("9D00FF"), 1015: Color("594E61"), 1021: Color("FFFB00"),
	1022: Color("7D522D"), 1023: Color("FF8D00"), 1024: Color("000000"), 1041: Color("7A0000"),
	1042: Color("FFA691"), 1043: Color("EEEEEE"), 1044: Color("FFFFFF"), 1045: Color("DEDEDE"),
	1051: Color("5D9C36"), 1052: Color("4B245C"), 1053: Color("717E80"), 1054: Color("5D9C36"),
	1061: Color("4E822E"), 1062: Color("361B43"), 1063: Color("555F61"), 1064: Color("4E822E")
}

func _ready():
	_init_colors_for_loaded_npc()
	_build_ui()
	_init_grid()
	_populate_load_dropdown()
	_update_palette_buttons() # Initialize selection highlight

func _get_standard_team_color(team: int, type: String) -> Color:
	var mat_id = 1004 + team
	if type == "team_mage": mat_id = 1074 + team
	if NPC_MAT_COLORS.has(mat_id): return NPC_MAT_COLORS[mat_id]
	return Color.WHITE

func _init_colors_for_loaded_npc():
	var vis = SandboxGrid.NPC_VISUALS.get(current_loaded_npc, {})
	var palette = vis.get("palette", {})
	
	for i in range(1, 10):
		if palette.has(i):
			var val = palette[i]
			if typeof(val) == TYPE_COLOR:
				custom_base_colors[i] = val
			elif typeof(val) == TYPE_INT and NPC_MAT_COLORS.has(val):
				custom_base_colors[i] = NPC_MAT_COLORS[val]
			else:
				custom_base_colors[i] = Color.WHITE
		else:
			custom_base_colors[i] = Color(0.3, 0.3, 0.3)
			
	for t in range(4):
		custom_team_colors[t][10] = _get_standard_team_color(t, "team")
		custom_team_colors[t][11] = _get_standard_team_color(t, "team_mage")
		custom_team_colors[t][12] = Color.MAGENTA
		
	# Overwrite with actual array colors from palette if they exist
	for k in palette.keys():
		var val = palette[k]
		if typeof(val) == TYPE_ARRAY:
			var slot = 10
			if k == 4: slot = 10
			elif k == 8: slot = 11
			elif k == 9: slot = 12
			else: slot = k
			
			for t in range(min(4, val.size())):
				if typeof(val[t]) == TYPE_COLOR:
					custom_team_colors[t][slot] = val[t]

func _set_brush(idx: int):
	current_brush = idx
	_update_palette_buttons()

func _toggle_grid(toggled_on: bool):
	show_grid_lines = toggled_on
	var grid = find_child("CanvasGrid", true, false)
	if grid:
		var sep = 1 if show_grid_lines else 0
		grid.add_theme_constant_override("h_separation", sep)
		grid.add_theme_constant_override("v_separation", sep)

func _build_ui():
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(PRESET_FULL_RECT)
	add_child(hbox)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(scroll)
	
	var left_panel = VBoxContainer.new()
	left_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(left_panel)
	
	var title = Label.new()
	title.text = "NPC Laboratory"
	left_panel.add_child(title)
	left_panel.add_child(HSeparator.new())
	
	var load_lbl = Label.new()
	load_lbl.text = "Load Base NPC:"
	left_panel.add_child(load_lbl)
	
	var load_dropdown = OptionButton.new()
	load_dropdown.name = "LoadDropdown"
	left_panel.add_child(load_dropdown)
	var load_btn = Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load_pressed)
	left_panel.add_child(load_btn)
	left_panel.add_child(HSeparator.new())
	
	var team_lbl = Label.new()
	team_lbl.text = "Preview Team Colors:"
	left_panel.add_child(team_lbl)
	
	var team_dropdown = OptionButton.new()
	team_dropdown.name = "TeamDropdown"
	team_dropdown.add_item("Red (Team 0)")
	team_dropdown.add_item("Blue (Team 1)")
	team_dropdown.add_item("Yellow (Team 2)")
	team_dropdown.add_item("Green (Team 3)")
	team_dropdown.item_selected.connect(_on_team_preview_changed)
	left_panel.add_child(team_dropdown)
	left_panel.add_child(HSeparator.new())
	
	var pal_lbl = Label.new()
	pal_lbl.text = "Base Colors (1-9):"
	left_panel.add_child(pal_lbl)
	
	var base_grid = GridContainer.new()
	base_grid.columns = 2
	left_panel.add_child(base_grid)
	
	var eraser_btn = Button.new()
	eraser_btn.text = "Eraser (0)"
	eraser_btn.custom_minimum_size = Vector2(100, 35)
	eraser_btn.pressed.connect(func(): _set_brush(0))
	base_grid.add_child(eraser_btn)
	palette_buttons.append(eraser_btn)
	
	base_grid.add_child(Control.new())
	
	for i in range(1, 10):
		var hbox_col = HBoxContainer.new()
		var btn = Button.new()
		btn.text = "Color " + str(i)
		btn.custom_minimum_size = Vector2(80, 35)
		btn.pressed.connect(func(): _set_brush(i))
		hbox_col.add_child(btn)
		
		var picker = ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(40, 35)
		picker.color = _get_display_color(i, 0)
		picker.color_changed.connect(func(c): _on_color_picked(i, c))
		hbox_col.add_child(picker)
		
		base_grid.add_child(hbox_col)
		palette_buttons.append(btn)
		color_pickers[i] = picker

	left_panel.add_child(HSeparator.new())
	
	var team_pal_lbl = Label.new()
	team_pal_lbl.text = "Team Colors (10-12):"
	left_panel.add_child(team_pal_lbl)
	
	var team_grid = VBoxContainer.new()
	left_panel.add_child(team_grid)
	
	for i in range(10, 13):
		var hbox_col = HBoxContainer.new()
		var btn = Button.new()
		btn.text = "Team Slot " + str(i)
		btn.custom_minimum_size = Vector2(120, 35)
		btn.pressed.connect(func(): _set_brush(i))
		hbox_col.add_child(btn)
		
		var picker = ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(50, 35)
		picker.color = _get_display_color(i, 0)
		picker.color_changed.connect(func(c): _on_color_picked(i, c))
		hbox_col.add_child(picker)
		
		team_grid.add_child(hbox_col)
		palette_buttons.append(btn)
		color_pickers[i] = picker
		
	left_panel.add_child(HSeparator.new())
	
	var grid_toggle = CheckButton.new()
	grid_toggle.text = "Show Grid Lines"
	grid_toggle.button_pressed = true
	grid_toggle.toggled.connect(_toggle_grid)
	left_panel.add_child(grid_toggle)
	
	var export_btn = Button.new()
	export_btn.text = "EXPORT TO CLIPBOARD"
	export_btn.pressed.connect(_on_export_pressed)
	left_panel.add_child(export_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "Clear Grid"
	clear_btn.pressed.connect(_init_grid)
	left_panel.add_child(clear_btn)
	
	# ScrollContainer for right panel so it can hold the big grid
	var right_scroll = ScrollContainer.new()
	right_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(right_scroll)
	
	var right_panel = CenterContainer.new()
	right_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = SIZE_EXPAND_FILL
	right_scroll.add_child(right_panel)
	
	var canvas_bg = ColorRect.new()
	canvas_bg.color = Color(0.1, 0.1, 0.1)
	# 28 size per cell + 1px spacing
	canvas_bg.custom_minimum_size = Vector2(GRID_SIZE * 29, GRID_SIZE * 29)
	right_panel.add_child(canvas_bg)
	
	var grid = GridContainer.new()
	grid.name = "CanvasGrid"
	grid.columns = GRID_SIZE
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	canvas_bg.add_child(grid)

func _init_grid():
	var grid = find_child("CanvasGrid", true, false)
	if grid:
		for c in grid.get_children():
			c.queue_free()
			
	grid_cells.clear()
	data_matrix.clear()
	
	for y in range(GRID_SIZE):
		var row = []
		for x in range(GRID_SIZE):
			row.append(0)
			
			var cell = ColorRect.new()
			cell.custom_minimum_size = Vector2(28, 28)
			cell.color = Color(0.15, 0.15, 0.15)
			
			cell.gui_input.connect(_on_cell_gui_input.bind(x, y))
			
			if grid: grid.add_child(cell)
			grid_cells.append(cell)
		data_matrix.append(row)

func _get_display_color(val: int, team: int) -> Color:
	if val == 0: return Color(0.15, 0.15, 0.15)
	if val >= 1 and val <= 9:
		if custom_base_colors.has(val): return custom_base_colors[val]
	if val >= 10 and val <= 12:
		if custom_team_colors[team].has(val): return custom_team_colors[team][val]
	return Color.MAGENTA

func _on_cell_gui_input(event: InputEvent, x: int, y: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_drawing = event.pressed
			if is_drawing: _paint_cell(x, y)
	elif event is InputEventMouseMotion:
		if is_drawing: _paint_cell(x, y)

func _paint_cell(x: int, y: int):
	data_matrix[y][x] = current_brush
	var idx = y * GRID_SIZE + x
	grid_cells[idx].color = _get_display_color(current_brush, current_team_preview)

func _on_team_preview_changed(index: int):
	current_team_preview = index
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var val = data_matrix[y][x]
			var idx = y * GRID_SIZE + x
			grid_cells[idx].color = _get_display_color(val, current_team_preview)
	_update_palette_buttons()

func _on_color_picked(i: int, color: Color):
	if i >= 1 and i <= 9:
		custom_base_colors[i] = color
	elif i >= 10 and i <= 12:
		custom_team_colors[current_team_preview][i] = color
	_update_palette_buttons()
	_on_team_preview_changed(current_team_preview)

func _update_palette_buttons():
	for i in range(palette_buttons.size()):
		var btn = palette_buttons[i]
		var btn_idx = i if i <= 9 else i + 0
		var c = _get_display_color(btn_idx, current_team_preview)
		
		var style = StyleBoxFlat.new()
		style.bg_color = c
		if btn_idx == 0: style.bg_color = Color(0.2, 0.2, 0.2)
		
		if btn_idx == current_brush:
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
			style.border_color = Color.WHITE
			# If the color is very bright, make the border black so it's visible
			if c.v > 0.8 and c.s < 0.2:
				style.border_color = Color.BLACK
				
		btn.add_theme_stylebox_override("normal", style)
		
		if color_pickers.has(btn_idx):
			color_pickers[btn_idx].color = c

func _populate_load_dropdown():
	var dropdown = find_child("LoadDropdown", true, false)
	for key in SandboxGrid.NPC_VISUALS.keys():
		dropdown.add_item(key)

func _on_load_pressed():
	var dropdown = find_child("LoadDropdown", true, false)
	var npc_name = dropdown.get_item_text(dropdown.selected)
	var vis = SandboxGrid.NPC_VISUALS.get(npc_name)
	if not vis: return
	
	current_loaded_npc = npc_name
	_init_colors_for_loaded_npc()
	
	_init_grid()
	var frames = vis.get("frames", {})
	var standing = frames.get("standing", [])
	
	var h = standing.size()
	var w = standing[0].size() if h > 0 else 0
	
	var start_x = (GRID_SIZE - w) / 2
	var start_y = (GRID_SIZE - h) / 2
	
	for y in range(h):
		var row = standing[y]
		for x in range(w):
			var val = row[x]
			if val != 0:
				if typeof(val) == TYPE_STRING:
					pass
				else:
					if val == 4: val = 10
					elif val == 8: val = 11
					elif val == 9: val = 12
					
					current_brush = val
					_paint_cell(start_x + x, start_y + y)
				
	_set_brush(1)

func _get_mat_id_for_color(c: Color) -> Variant:
	for mat_id in NPC_MAT_COLORS:
		if NPC_MAT_COLORS[mat_id].is_equal_approx(c):
			return mat_id
	return "\"#" + c.to_html(false) + "\""

func _on_export_pressed():
	var min_x = GRID_SIZE; var max_x = -1
	var min_y = GRID_SIZE; var max_y = -1
	
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if data_matrix[y][x] != 0:
				min_x = min(min_x, x); max_x = max(max_x, x)
				min_y = min(min_y, y); max_y = max(max_y, y)
				
	if max_x == -1: 
		print("Grid is empty!")
		return
		
	var out_w = max_x - min_x + 1
	var out_h = max_y - min_y + 1
	
	var out_matrix = []
	var used_indices = {}
	for y in range(min_y, max_y + 1):
		var row = []
		for x in range(min_x, max_x + 1):
			var val = data_matrix[y][x]
			row.append(val)
			if val != 0: used_indices[val] = true
		out_matrix.append(row)
		
	var str_matrix = "[\n"
	for row in out_matrix:
		str_matrix += "\t\t\t\t" + str(row) + ",\n"
	str_matrix += "\t\t\t]"
	
	var pal_str = "{"
	
	for i in range(1, 10):
		if used_indices.has(i):
			pal_str += "%d: Color(\"%s\"), " % [i, custom_base_colors[i].to_html(false)]
			
	for i in range(10, 13):
		if used_indices.has(i):
			var arr_str = "["
			for t in range(4):
				arr_str += "Color(\"%s\")" % custom_team_colors[t][i].to_html(false)
				if t < 3: arr_str += ", "
			arr_str += "]"
			pal_str += "%d: %s, " % [i, arr_str]
				
	pal_str += "}"
	
	var code = "\"custom_npc\": {\n"
	code += "\t\"width\": %d, \"height\": %d,\n" % [out_w, out_h]
	code += "\t\"palette\": %s,\n" % pal_str
	code += "\t\"frames\": {\n"
	code += "\t\t\"standing\": " + str_matrix + ",\n"
	code += "\t\t\"lying\": [] # TODO: Dibuja y pega aqui tu version acostado\n"
	code += "\t}\n"
	code += "}"
	
	print("--- EXPORTED NPC CODE ---")
	print(code)
	DisplayServer.clipboard_set(code)
