extends Node2D
class_name SandboxGrid

# Grid config
@export var grid_scale: int = 8
var grid_width: int
var grid_height: int

# Simulation Data
var cells: PackedInt32Array
var tags_array: PackedInt32Array
var color_buffer: PackedByteArray 
var charge_array: PackedByteArray # New: Track electric pulses (0 = none, 5 = full, counts down)

# Material data mapping
var material_colors_raw = PackedColorArray() 
var material_tags_raw = PackedInt32Array() 
var selected_material: int = 1
var current_weather: int = 0 
var is_mouse_over_ui: bool = false
var brush_radius: int = 0 # 0 means 1 pixel

# Earthquake settings
var earthquake_intensity: int = 0 # 0=Off, 1=Light, 2=Med, 3=Intense
var earthquake_timer: float = 0.0

# Tornado settings
var tornado_intensity: int = 0 # 0=Off, 1=F1, 2=F3, 3=F5
var tornado_timer: float = 0.0
var tornado_x: float = 0.0
var tornado_target_x: float = 0.0
var tornado_ground_y: float = 0.0

# Tsunami settings
var tsunami_intensity: int = 0 # 0=Off, 1=Light, 2=Med, 3=Mega
var tsunami_timer: float = 0.0
var tsunami_wave_x: float = 0.0
var surface_cache = PackedInt32Array()

# Fireworks tracking
var active_fireworks = [] # Array of dictionaries: {x, y, target_y, color}
var visual_sparks = []    # Array of particle dicts: {x, y, vx, vy, color, life}

# Display
@onready var texture_rect: TextureRect = $Display
var img: Image

func _ready():
	# Calculate grid size based on viewport - Deducting 150px for UI bar at the bottom
	var actual_viewport_height = get_viewport_rect().size.y - 150
	var viewport_size = Vector2(get_viewport_rect().size.x, actual_viewport_height)
	
	grid_width = floor(viewport_size.x / grid_scale)
	grid_height = floor(viewport_size.y / grid_scale)
	
	# Init arrays
	cells.resize(grid_width * grid_height)
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	color_buffer.resize(grid_width * grid_height * 4)
	surface_cache.resize(grid_width)
	
	tags_array.resize(grid_width * grid_height)
	charge_array.resize(grid_width * grid_height)
	
	material_colors_raw.resize(20) 
	material_tags_raw.resize(20)
	
	# Setup materials
	_register_material(0, Color(0, 0, 0, 0), SandboxMaterial.Tags.NONE)
	_register_material(1, Color.KHAKI, SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_NORMAL)
	_register_material(2, Color.SKY_BLUE, SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.CONDUCTOR)
	_register_material(3, Color.ORANGE_RED, SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC)
	# Petroleum (Dark Purple + Flammable)
	_register_material(4, Color("#2F0E4F"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.BURN_SMOKE)
	
	# TNT (Static + Explosive + Electric Activated)
	_register_material(5, Color.RED, SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Earth (Slow gravity)
	_register_material(6, Color.SADDLE_BROWN, SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW)
	
	# Primed TNT (Flashes white, soon to BOOM)
	_register_material(7, Color.WHITE, SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Metal (Solid + Conductor)
	_register_material(8, Color.LIGHT_GRAY, SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Electricity (Energy!)
	_register_material(9, Color.YELLOW, SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Gravel (Gray stones)
	_register_material(10, Color.SLATE_GRAY, SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL)
	
	# Lava (Slow Liquid + Hot)
	_register_material(11, Color.ORANGE, SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_SLOW)
	
	# Obsidian (Hard Rock + Anti-Acid + Anti-Explosive)
	_register_material(12, Color(0.1, 0.05, 0.2), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_ACID | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	
	# Acid (Neon Green + Melts things)
	_register_material(13, Color("#39FF14"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.GRAV_NORMAL)
	
	# Coal (Brazas - Dark Brown/Black)
	_register_material(14, Color("#1A1110"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.BURN_SMOKE | SandboxMaterial.Tags.INCENDIARY)
	
	# Smoke (Light Gray Gas)
	_register_material(15, Color(0.7, 0.7, 0.7, 0.5), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.BURN_NONE)
	
	# Wood (Strong Brown)
	_register_material(16, Color("#5D3A1A"), SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.BURN_COAL | SandboxMaterial.Tags.SOLID)
	
	# Cloud (Whity Gray Gas)
	_register_material(17, Color(0.9, 0.9, 0.9, 0.8), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP)

	# Fuegos Artificiales (Rosa brillante) + Anti-Explosivo para que no se muevan al encenderse la bateria
	_register_material(18, Color(1.0, 0.4, 0.7), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	
	# Fill with empty
	cells.fill(0)
	charge_array.fill(0)
	
	# Texture setup
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	texture_rect.texture = ImageTexture.create_from_image(img)
	texture_rect.size = viewport_size
	
	# Tool selection from UI
	var controls = get_parent().get_node("UI/Controls")
	controls.get_node("SandBtn").pressed.connect(func(): selected_material = 1)
	controls.get_node("WaterBtn").pressed.connect(func(): selected_material = 2)
	controls.get_node("OilBtn").visible = false # Remplazado por Petróleo
	controls.get_node("FireBtn").pressed.connect(func(): selected_material = 3)
	
	# New buttons
	_add_button("TNT", 5)
	_add_button("Earth", 6)
	_add_button("Metal", 8)
	_add_button("Elec", 9)
	_add_button("Gravel", 10)
	_add_button("Lava", 11)
	_add_button("Obisid", 12)
	_add_button("Acid", 13)
	_add_button("Wood", 16)
	_add_button("Petro", 4)
	_add_button("Fuegos Art.", 18)

	_register_material(19, Color(1, 0.8, 0.9), SandboxMaterial.Tags.GRAV_STATIC) # Firework Fuse (Removed Incendiary to avoid domino effect)
	
	# DISASTER MENU
	_setup_ui()


func _setup_ui():
	_setup_disaster_ui()
	_setup_tools_ui()

func _setup_tools_ui():
	var ui_root = get_parent().get_node("UI")
	var main_controls = ui_root.get_node("Controls")
	
	# Create a TOOLS toggle button
	var tools_btn = Button.new()
	tools_btn.text = "🛠️ Herramientas"
	main_controls.add_child(tools_btn)
	
	# Submenu container
	var tool_menu = HBoxContainer.new()
	tool_menu.visible = false
	ui_root.add_child(tool_menu)
	tool_menu.position = Vector2(0, get_viewport_rect().size.y - 350) # Stacked
	
	tools_btn.pressed.connect(func(): tool_menu.visible = !tool_menu.visible)
	
	var v_box = VBoxContainer.new()
	tool_menu.add_child(v_box)
	
	# Block signals
	tool_menu.mouse_entered.connect(func(): is_mouse_over_ui = true)
	tool_menu.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	# Helper (localized)
	var create_tool_row = func(label_text: String, options: Array, callback: Callable):
		var h_box = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = label_text + ": "
		lbl.custom_minimum_size = Vector2(100, 0)
		h_box.add_child(lbl)
		for i in range(options.size()):
			var btn = Button.new()
			btn.text = options[i]
			var level = i
			btn.pressed.connect(func(): callback.call(level))
			h_box.add_child(btn)
		v_box.add_child(h_box)

	# BRUSH SIZE ROW - Levels: 1, 3, 5, 10, 15, 25
	var brush_sizes = [0, 1, 2, 5, 7, 12] # Radius mapping
	var brush_labels = ["1px", "3px", "5px", "10px", "15px", "25px"]
	create_tool_row.call("🖌️ Pincel", brush_labels, func(l): brush_radius = brush_sizes[l])

func _setup_disaster_ui():
	var ui_root = get_parent().get_node("UI")
	var main_controls = ui_root.get_node("Controls")
	
	# Create a disaster toggle button
	var disaster_btn = Button.new()
	disaster_btn.text = "🌪️ Desastres"
	main_controls.add_child(disaster_btn)
	
	# Submenu container
	var sub_menu = HBoxContainer.new()
	sub_menu.visible = false
	ui_root.add_child(sub_menu)
	sub_menu.position = Vector2(0, get_viewport_rect().size.y - 300) # Above main UI
	
	disaster_btn.pressed.connect(func(): sub_menu.visible = !sub_menu.visible)
	
	# SETUP VERTICAL MENU
	var v_box = VBoxContainer.new()
	sub_menu.add_child(v_box)
	
	# Connect signals to block painting
	sub_menu.mouse_entered.connect(func(): is_mouse_over_ui = true)
	sub_menu.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	# Helper function to create rows
	var create_row = func(label_text: String, options: Array, callback: Callable):
		var h_box = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = label_text + ": "
		lbl.custom_minimum_size = Vector2(100, 0)
		h_box.add_child(lbl)
		for i in range(options.size()):
			var btn = Button.new()
			btn.text = options[i]
			var level = i
			btn.pressed.connect(func(): callback.call(level))
			h_box.add_child(btn)
		v_box.add_child(h_box)
	
	# Weather Row
	create_row.call("⛈️ Clima", ["Off", "Ligero", "Medio", "Tormenta"], func(l): current_weather = l)
	
	# Earthquake Row
	create_row.call("🫨 Sismo", ["Off", "Ligero", "Medio", "¡BRUTAL!"], func(l): 
		earthquake_intensity = l
		if l > 0: earthquake_timer = randf_range(5.0, 7.0)
	)
	
	# Tornado Row
	create_row.call("🌪️ Tornado", ["Off", "F1", "F3", "F5 🔥"], func(l):
		tornado_intensity = l
		if l > 0: 
			tornado_timer = 15.0
			tornado_x = randf() * grid_width
			tornado_target_x = randf() * grid_width
	)
	
	# Tsunami Row
	create_row.call("🌊 Tsunami", ["Off", "Marejada", "Maremoto", "MEGA"], func(l):
		tsunami_intensity = l
		if l > 0:
			tsunami_timer = 15.0
			tsunami_wave_x = 0.0
	)

func _add_button(text, mat_id):
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(func(): selected_material = mat_id)
	var controls = get_parent().get_node("UI/Controls")
	controls.add_child(btn)
	
	# Block painting when hovering material buttons too
	btn.mouse_entered.connect(func(): is_mouse_over_ui = true)
	btn.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _register_material(id, color, tags):
	material_colors_raw[id] = color
	material_tags_raw[id] = tags

func _process(delta):
	# Handle input
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_mouse_over_ui:
		var m_pos = get_local_mouse_position()
		var gx = int(m_pos.x / grid_scale)
		var gy = int(m_pos.y / grid_scale)
		_draw_circle(gx, gy, brush_radius, selected_material)

	# Simulation
	_step_simulation()
	
	# Weather system
	_process_weather()
	
	# Earthquake processing
	_process_earthquake(delta)
	
	# Tornado processing
	_process_tornado(delta)
	
	# Tsunami processing
	_process_tsunami(delta)
	
	# Fireworks updates
	_update_active_fireworks(delta)
	_update_visual_sparks(delta)
	
	# Render
	_update_texture()

func _process_tsunami(delta):
	if tsunami_timer <= 0:
		tsunami_intensity = 0
		return
	
	tsunami_timer -= delta
	
	# Move the wave front from Left to Right (Gaussian Center)
	tsunami_wave_x += (grid_width / 5.0) * delta * 5.0
	if tsunami_wave_x > grid_width + 150:
		tsunami_intensity = 0 # STOP AFTER ONE PASS
		return
	
	# Wave Configuration Constants (HALF POWER)
	var radius = 25 + (20 * tsunami_intensity)
	var max_wave_height = 4 + (3 * tsunami_intensity) # MEGA = ~13 pixels total
	var sigma_sq = pow(radius / 2.5, 2)
	
	# Determine SEA LEVEL (Reference height outside the wave)
	var ref_x = int(tsunami_wave_x - radius - 10)
	var sea_level = grid_height - 10 # Default to bottom if no water
	if ref_x >= 0 and ref_x < grid_width:
		for gy in range(5, grid_height - 5):
			var idx = gy * grid_width + ref_x
			if cells[idx] > 0 and (material_tags_raw[cells[idx]] & SandboxMaterial.Tags.LIQUID):
				sea_level = gy
				break
	
	for ox in range(-radius, radius):
		var rx = int(tsunami_wave_x + ox)
		if rx < 0 or rx >= grid_width: continue
		
		# Gaussian Height target
		var dist_sq = float(ox * ox)
		var gauss_h = int(max_wave_height * exp(-dist_sq / (2.0 * sigma_sq)))
		if gauss_h <= 1: continue
		
		# Find surface and material
		var y_top = -1
		var mid = 0
		for gy in range(5, grid_height - 5):
			var idx = gy * grid_width + rx
			if cells[idx] > 0 and (material_tags_raw[cells[idx]] & SandboxMaterial.Tags.LIQUID):
				y_top = gy
				mid = cells[idx]
				break
		
		if y_top == -1: continue
		surface_cache[rx] = y_top
		
		# SOLID PIXEL SPAWNING (Smooth, no tremor)
		for i in range(gauss_h):
			var target_y = y_top - i
			var source_y = y_top + i + 1
			
			if target_y > 5 and source_y < grid_height:
				# Purely mathematical shift, no randf()
				if _get_cell(rx, target_y) == 0:
					_set_cell(rx, target_y, mid)
					if (material_tags_raw[_get_cell(rx, source_y)] & SandboxMaterial.Tags.LIQUID):
						_set_cell(rx, source_y, 0)

func _process_tornado(delta):
	if tornado_timer <= 0:
		tornado_intensity = 0
		return
	
	tornado_timer -= delta
	
	# 1. Autonomous Movement
	if abs(tornado_x - tornado_target_x) < 5:
		tornado_target_x = randf() * grid_width
	
	tornado_x = lerp(tornado_x, tornado_target_x, delta * 0.5)
	
	# 1.5 Ground Tracking (Find the surface)
	var tx = int(tornado_x)
	var detected_y = grid_height - 1 # Default bottom
	for gy in range(2, grid_height - 4):
		# Look for a VERY DENSE surface (at least 4 pixels deep)
		var c1 = _get_cell(tx, gy)
		if c1 > 0 and c1 != 17 and c1 != 15:
			# Check 3 more pixels below to confirm it's ground
			if _get_cell(tx, gy + 1) > 0 and _get_cell(tx, gy + 2) > 0 and _get_cell(tx, gy + 3) > 0:
				detected_y = gy
				break
	
	# Smoothly interpolate height to avoid jittering when debris passes
	tornado_ground_y = lerp(tornado_ground_y, float(detected_y), 0.1)
	
	# 2. Conical Vortex Physics & Clouds
	# Spawn clouds at the top of the funnel
	if randf() < 0.2:
		_set_cell(int(tornado_x + randf_range(-40, 40)), 2, 17)
		_set_cell(int(tornado_x + randf_range(-20, 20)), 1, 17)
	
	var points_to_process = 3000 * tornado_intensity
	
	for i in range(points_to_process):
		# Sample randomly in the grid (biased towards tornado column)
		var ry = randi() % grid_height
		
		# Variable Radius relative to current GROUND level
		var rel_y = 1.0 - (float(ry) / tornado_ground_y) if tornado_ground_y > 0 else 1.0
		# Funnel only above ground, but with a small chaotic bit below
		var current_radius = 0.0
		if ry <= tornado_ground_y:
			current_radius = (4 + tornado_intensity) + (40.0 * tornado_intensity * rel_y)
		else:
			# Dig slightly into the ground (radius narrows downward)
			current_radius = max(0, (4 + tornado_intensity) - (ry - tornado_ground_y))
		
		var rx = int(tornado_x + randf_range(-current_radius, current_radius))
		
		if rx < 0 or rx >= grid_width or ry < 0 or ry >= grid_height: continue
		
		var tid = _get_cell(rx, ry)
		if tid == 0 or tid == 17: continue 
		
		# Vortex Forces
		var dist_x = tornado_x - rx
		var pull_strength = 1.0 - (abs(dist_x) / (current_radius + 1))
		
		var dx = sign(dist_x)
		# Pull up above ground, swirl/chaos below ground
		var dy = -2 if tornado_intensity < 3 else -4 
		if ry > tornado_ground_y: dy = 1 if randf() < 0.5 else -1 # Chaos/digging
		
		# Swirl/Orbital effect
		if randf() < 0.4: dx = -dx 
		
		# Apply force with probability
		if randf() < pull_strength:
			var nx = rx + dx
			var ny = ry + dy
			if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
				# Suction can lift anything into air
				if _get_cell(nx, ny) == 0:
					_swap_cells(rx, ry, nx, ny)
				elif randf() < 0.2: # Can also mix with other particles inside funnel
					_swap_cells(rx, ry, nx, ny)

func _process_earthquake(delta):
	if earthquake_timer <= 0:
		if texture_rect.position != Vector2.ZERO:
			texture_rect.position = Vector2.ZERO
		return
	
	earthquake_timer -= delta
	
	# 1. Screen Shake (Visual)
	var shake_force = earthquake_intensity * 5.0
	texture_rect.position = Vector2(randf_range(-shake_force, shake_force), randf_range(-shake_force, shake_force))
	
	# 2. Physics Shake (Actual material movement)
	# Increased iterations for MASSIVE destruction
	for i in range(3000 * earthquake_intensity):
		var rx = randi() % grid_width
		var ry = randi() % grid_height
		var idx = ry * grid_width + rx
		var tid = cells[idx]
		
		# In a earthquake, even static things can juggle a bit, but mostly powders/liquids
		var nx = rx + randi_range(-earthquake_intensity, earthquake_intensity)
		var ny = ry + randi_range(-earthquake_intensity, earthquake_intensity)
		
		if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
			# MIXING: Do not check for empty. Swap everything to cause liquefaction.
			# Only limit swapping for very stable solids? No, let's keep it chaotic.
			_swap_cells(rx, ry, nx, ny)
	
	# Automatic stop after timer
	if earthquake_timer <= 0:
		earthquake_intensity = 0

func _process_weather():
	if current_weather == 0: return
	
	# Always spawn some clouds at the top if weather is active
	for i in range(5):
		_set_cell(randi() % grid_width, 1, 17)
	
	# Spawn rain based on intensity
	var rain_chance = 0.05 if current_weather == 1 else (0.2 if current_weather == 2 else 0.5)
	if randf() < rain_chance:
		# Spawn multiple droplets based on level
		for i in range(current_weather * 2):
			_set_cell(randi() % grid_width, 5 + randi() % 5, 2) # Spawn Water
			
	# Lightning in Storm (Level 3)
	if current_weather == 3 and randf() < 0.01: # Rare but impactful
		_strike_lightning()

func _strike_lightning():
	var lx = randi() % grid_width
	# Trace a bolt from top to first solid/liquid or bottom
	for ly in range(0, grid_height):
		var target_id = _get_cell(lx, ly)
		# Ignite everything in the bolt path
		_set_cell(lx, ly, 9) # Deploy Electricity!
		# If we hit something non-empty, stop bolt and create small explosion
		# NEW: Ignore rain (2) so it hits the ground
		if target_id > 0 and target_id != 17 and target_id != 15 and target_id != 2:
			_explode(lx, ly, 5) # Small localized explosion
			break

func _draw_circle(cx, cy, radius, mat_id):
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x*x + y*y <= radius*radius:
				_set_cell(cx + x, cy + y, mat_id)

func _set_cell(x, y, mat_id):
	if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
		var idx = y * grid_width + x
		cells[idx] = mat_id
		tags_array[idx] = material_tags_raw[mat_id]
		# Reset charge if material changes manually
		charge_array[idx] = 0

func _get_cell(x, y):
	if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
		return cells[y * grid_width + x]
	return -1

func _step_simulation():
	# Pass 1: Electricity Pulse Processing
	_process_electricity()
	
	# Pass 2: RISING and SPECIAL particles (Top-to-Bottom)
	for y in range(grid_height):
		var sweep = range(grid_width)
		if Engine.get_frames_drawn() % 2 == 0: sweep = range(grid_width - 1, -1, -1)
		for x in sweep:
			var idx = y * grid_width + x
			var mat_id = cells[idx]
			if mat_id == 0: continue
			
			var tags = tags_array[idx]
			
			if mat_id == 7: # Primed TNT
				if randf() < 0.05: _explode(x, y, 10)
				continue

			if (tags & SandboxMaterial.Tags.GRAV_UP):
				_move_particle(x, y, mat_id, tags, -1)
				_process_interactions(x, y, idx, mat_id, tags)

	# Pass 3: FALLING/STATIC particles (Bottom-to-Top)
	for y in range(grid_height - 1, -1, -1):
		var sweep = range(grid_width)
		if Engine.get_frames_drawn() % 2 == 0: sweep = range(grid_width - 1, -1, -1)
		for x in sweep:
			var idx = y * grid_width + x
			var mat_id = cells[idx]
			if mat_id <= 0 or mat_id == 7: continue 
			
			var tags = tags_array[idx]
			if (tags & SandboxMaterial.Tags.GRAV_UP): continue
			
			if (tags & SandboxMaterial.Tags.GRAV_STATIC):
				pass 
			elif (tags & SandboxMaterial.Tags.GRAV_SLOW):
				# Random probability (Stochastic) makes it slow BUT smooth/organic
				if randf() < 0.3:
					_move_particle(x, y, mat_id, tags, 1)
			else:
				_move_particle(x, y, mat_id, tags, 1)
			
			_process_interactions(x, y, idx, mat_id, tags)

func _process_electricity():
	# Sequential processing to prevent infinite loops
	for i in range(cells.size()):
		var charge = charge_array[i]
		if charge == 0: continue
		
		# Only spread when charge is at its peak (100)
		if charge == 100:
			var x = i % grid_width
			var y = i / grid_width
			for ny in range(y - 1, y + 2):
				for nx in range(x - 1, x + 2):
					if nx == x and ny == y: continue
					if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
						var n_idx = ny * grid_width + nx
						var n_tags = tags_array[n_idx]
						# Only spread to conductors that are currently at 0 (IDLE)
						if (n_tags & SandboxMaterial.Tags.CONDUCTOR) and charge_array[n_idx] == 0:
							charge_array[n_idx] = 101 # Set to 'newly charged'
		
		# Countdown charge
		charge_array[i] -= 1
		# 101 drops to 100 to spread in the NEXT frame
		if charge_array[i] > 100: charge_array[i] = 100



func _move_particle(x, y, mat_id, tags, v_dir):
	var next_y = y + v_dir
	if next_y < 0 or next_y >= grid_height: return
	
	# Try directly moving
	if _get_cell(x, next_y) == 0:
		_swap_cells(x, y, x, next_y)
		return
	
	# Try diagonals (only for powder, liquids and gases)
	if (tags & (SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GAS)):
		var side = 1 if randf() > 0.5 else -1
		if _get_cell(x + side, next_y) == 0:
			_swap_cells(x, y, x + side, next_y)
		elif _get_cell(x - side, next_y) == 0:
			_swap_cells(x, y, x - side, next_y)
		elif (tags & (SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GAS)):
			if _get_cell(x + side, y) == 0:
				_swap_cells(x, y, x + side, y)
			elif _get_cell(x - side, y) == 0:
				_swap_cells(x, y, x - side, y)

func _swap_cells(x1, y1, x2, y2):
	var idx1 = y1 * grid_width + x1
	var idx2 = y2 * grid_width + x2
	var m1 = cells[idx1]
	var m2 = cells[idx2]
	var c1 = charge_array[idx1]
	var c2 = charge_array[idx2]
	
	cells[idx1] = m2
	tags_array[idx1] = material_tags_raw[m2]
	charge_array[idx1] = c2
	
	cells[idx2] = m1
	tags_array[idx2] = material_tags_raw[m1]
	charge_array[idx2] = c1

func _process_interactions(x, y, idx, mat_id, tags):
	# FIRE AND HEAT REACTIONS
	if (tags & SandboxMaterial.Tags.INCENDIARY):
		# Incendiary materials (Fire 3, Lava 11) extinguish or burn out
		if mat_id == 3:
			if randf() < 0.1: _set_cell(x, y, 0)
		elif mat_id == 14: # Coal burnout
			if randf() < 0.0006:
				_set_cell(x, y, 0)
				if _get_cell(x, y - 1) == 0: _set_cell(x, y - 1, 15)
			if randf() < 0.005 and _get_cell(x, y-1) == 0:
				_set_cell(x, y - 1, 3)
		
		# Spreading fire to neighbors
		_check_neighbors_for_reaction(x, y, true)

	# FLAMMABLE / REACTIVE MATERIALS (Independent of being incendiary themselves)
	
	# Wood (16) or Coal (14) or Fireworks (18) or Petro (4) ignition
	if (tags & SandboxMaterial.Tags.FLAMMABLE) or (tags & SandboxMaterial.Tags.EXPLOSIVE):
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY) or charge_array[idx] > 50:
			if mat_id == 16 or mat_id == 14 or mat_id == 4: # Wood/Coal/Petro catches fire
				if randf() < 0.1: _set_cell(x, y, 3)
			elif mat_id == 18: # Fireworks start fuse
				_set_cell(x, y, 19)
				charge_array[idx] = randi_range(20, 70)
	
	# FUSE LOGIC (Standalone)
	if mat_id == 19: # Firework Fuse
		charge_array[idx] -= 1
		# Visual flash (Pink/White)
		if Engine.get_frames_drawn() % 4 == 0:
			_set_cell(x, y, 18)
		elif Engine.get_frames_drawn() % 4 == 2:
			_set_cell(x, y, 19)
		
		if charge_array[idx] <= 0:
			_launch_firework(x, y)

	elif mat_id == 7: # Primed TNT
		charge_array[idx] -= 1
		if charge_array[idx] <= 0:
			_explode(x, y, 12)

	# ELECTRIC SEEDING (Active pulses)
	if (tags & SandboxMaterial.Tags.ELECTRICITY):
		if randf() < 0.7: _set_cell(x, y, 0)
		_check_neighbors_for_reaction(x, y, false)
	
	# PASS 3: Conductor Pulse (Triggering TNT/Devices)
	var charge = charge_array[idx]
	if charge == 100:
		_trigger_electric_devices(x, y)
	
	# PASS 4: Acid interaction (Melting things!)
	if (tags & SandboxMaterial.Tags.ACID):
		_check_neighbors_for_reaction(x, y, false)
	
	# PASS 5: Universal Dissipation (Smoke, etc)
	if mat_id == 15: # Smoke
		if randf() < 0.001:
			_set_cell(x, y, 0)

func _has_tag_neighbor(x, y, tag):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var nid = _get_cell(nx, ny)
			if nid > 0:
				if (material_tags_raw[nid] & tag):
					return true
	return false

func _trigger_electric_devices(x, y):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var n_id = _get_cell(nx, ny)
			if n_id > 0:
				var n_tags = material_tags_raw[n_id]
				if (n_tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED):
					_set_cell(nx, ny, 7) # Prime TNT


func _check_neighbors_for_reaction(x, y, is_heat):
	var my_id = _get_cell(x, y)
	
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var n_id = _get_cell(nx, ny)
			if n_id > 0:
				var n_idx = ny * grid_width + nx
				var n_tags = material_tags_raw[n_id]
				
				# Lava + Water -> Obsidian
				if (my_id == 11 and n_id == 2) or (my_id == 2 and n_id == 11):
					_set_cell(x, y, 12)
					_set_cell(nx, ny, 12)
					return

				# ACID LOGIC
				var my_tags = tags_array[y * grid_width + x]
				if (my_tags & SandboxMaterial.Tags.ACID):
					# If neighbor is NOT empty and NOT acid and NOT anti-acid
					if n_id > 0 and n_id != 13 and !(n_tags & SandboxMaterial.Tags.ANTI_ACID):
						if randf() < 0.6: # Faster melting speed (from 0.2 to 0.6)
							_set_cell(nx, ny, 0) # Dissolve neighbor
							# Optional: Acid might also be consumed (very slowly)
							if randf() < 0.05: _set_cell(x, y, 0)
							return

				if is_heat:
					if (n_tags & SandboxMaterial.Tags.FLAMMABLE):
						# Catch fire based on producer type
						if randf() < 0.05: # Slow burning/transformation
							if (n_tags & SandboxMaterial.Tags.BURN_COAL):
								_set_cell(nx, ny, 14) # Become Coal
							elif (n_tags & SandboxMaterial.Tags.BURN_SMOKE):
								# Release smoke above if possible
								if _get_cell(nx, ny - 1) == 0:
									_set_cell(nx, ny - 1, 15)
								# If it's Petroleum/Coal, eventually it disappears (turns to fire/nothing)
								if randf() < 0.2: _set_cell(nx, ny, 3) # Turn to Fire briefly
								else: _set_cell(nx, ny, 0)
							elif (n_tags & SandboxMaterial.Tags.BURN_NONE):
								_set_cell(nx, ny, 0)
							else:
								_set_cell(nx, ny, 3) # Default fire behavior
					elif (n_tags & SandboxMaterial.Tags.EXPLOSIVE):
						_set_cell(nx, ny, 7) # Prime TNT
				else:
					# ONLY Electricity material can start a new pulse in a conductor
					if (n_tags & SandboxMaterial.Tags.CONDUCTOR):
						if charge_array[n_idx] == 0:
							charge_array[n_idx] = 101 # Start pulse
					elif (n_tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED):
						_set_cell(nx, ny, 7) # Prime TNT via spark

func _explode(x, y, radius):
	_set_cell(x, y, 0)
	
	for ry in range(-radius, radius):
		for rx in range(-radius, radius):
			var dist_sq = rx*rx + ry*ry
			if dist_sq <= radius*radius:
				var tx = x + rx
				var ty = y + ry
				
				var t_id = _get_cell(tx, ty)
				if t_id <= 0: continue
				
				var t_idx = ty * grid_width + tx
				var t_tags = tags_array[t_idx]
				
				# Chain reaction: PRIME nearby explosives
				if (t_tags & SandboxMaterial.Tags.EXPLOSIVE):
					_set_cell(tx, ty, 7) # Prime it
					continue

				# ANTI-EXPLOSIVE CHECK: Skip physical movement/deletion
				if (t_tags & SandboxMaterial.Tags.ANTI_EXPLOSIVE):
					continue
				
				# Faster destruction check
				if dist_sq < (radius * 0.4) ** 2:
					_set_cell(tx, ty, 0) 
				else:
					# Displacement with random spread to avoid tight loops
					if randf() < 0.3:
						_push_particle(tx, ty, rx, ry)

func _push_particle(x, y, dx, dy):
	var nx = x + sign(dx) * 2
	var ny = y + sign(dy) * 2
	if _get_cell(nx, ny) == 0:
		_swap_cells(x, y, nx, ny)

func _update_texture():
	# HIGH PERFORMANCE RENDERING: Using color buffer and set_data
	for i in range(cells.size()):
		var mat_id = cells[i]
		var c = material_colors_raw[mat_id]
		var charge = charge_array[i]
		
		# VISUAL TORNADO FUNNEL (Background ghost effect)
		if tornado_intensity > 0 and mat_id == 0:
			var ix = i % grid_width
			var iy = i / grid_width
			# Only draw funnel ABOVE ground
			if iy <= tornado_ground_y:
				var rel_y = 1.0 - (float(iy) / tornado_ground_y) if tornado_ground_y > 0 else 1.0
				var cur_rad = (5 + tornado_intensity) + (40.0 * tornado_intensity * rel_y)
				if abs(ix - tornado_x) < cur_rad:
					c = Color(0.4, 0.4, 0.4, 0.4) 
		
		# MIX COLOR IF CHARGED (Glowing effect)
		if charge > 80:
			var pulse_color = Color.YELLOW
			# Sharp, short pulse (Brightest between 100 and 80)
			c = c.lerp(pulse_color, clamp(float(charge - 80) / 20.0, 0.0, 1.0))
		
		var base = i * 4
		color_buffer[base] = int(c.r * 255)
		color_buffer[base + 1] = int(c.g * 255)
		color_buffer[base + 2] = int(c.b * 255)
		color_buffer[base + 3] = int(c.a * 255)
	
	img.set_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, color_buffer)
	
	# DRAW VISUAL SPARKS (Ghost Fireworks - Over the grid)
	for spark in visual_sparks:
		var sx = int(spark.x)
		var sy = int(spark.y)
		if sx >= 0 and sx < grid_width and sy >= 0 and sy < grid_height:
			# Dim color based on life
			var s_color = spark.color
			s_color.a = spark.life
			img.set_pixel(sx, sy, s_color)
	
	texture_rect.texture.update(img)

func _launch_firework(x, y):
	_set_cell(x, y, 0) # Clear the station
	# Neon Palette for launch selection
	var neon_colors = [Color("#00FFFF"), Color("#FF00FF"), Color("#00FF00"), Color("#FFFF00"), Color("#FFFFFF")]
	var fw = {
		"x": float(x),
		"y": float(y),
		"target_y": max(15, y - randf_range(60, 250)), # Absolute ceiling margin
		"color": neon_colors[randi() % neon_colors.size()] # Lock color at launch!
	}
	active_fireworks.append(fw)

func _update_active_fireworks(delta):
	var to_remove = []
	for i in range(active_fireworks.size()):
		var fw = active_fireworks[i]
		fw.y -= 125.0 * delta # Half speed (125 instead of 250)
		
		# Sutil trail (Visual Sparks instead of physical Smoke)
		if randf() < 0.6:
			var trail_colors = [Color.GRAY, Color.YELLOW, Color.WHITE, Color.GOLD]
			var spark = {
				"x": float(fw.x) + randf_range(-1.2, 1.2),
				"y": float(fw.y + 1),
				"vx": randf_range(-10, 10),
				"vy": randf_range(20, 50), # Falling slightly
				"color": trail_colors[randi() % trail_colors.size()],
				"life": randf_range(0.2, 0.6) # Very short life for the trail
			}
			visual_sparks.append(spark)
			
		# Check if reached altitude or safe boundary
		if fw.y <= fw.target_y or fw.y < 15:
			_explode_firework(int(fw.x), int(fw.y), fw.color) # Use the locked color!
			to_remove.append(i)
	
	to_remove.reverse()
	for i in to_remove:
		active_fireworks.remove_at(i)

func _update_visual_sparks(delta):
	var to_remove = []
	for i in range(visual_sparks.size()):
		var s = visual_sparks[i]
		s.x += s.vx * delta
		s.y += s.vy * delta
		s.vy += 30.0 * delta # Visual gravity
		s.life -= 1.3 * delta # Slightly faster decay
		
		# Snap off if too dim to avoid 'noise'
		if s.life <= 0.2:
			to_remove.append(i)
	
	to_remove.reverse()
	for i in to_remove:
		visual_sparks.remove_at(i)

func _explode_firework(ex, ey, p_color):
	# Randomized explosion scale (Reduced max to 1/3 of previous)
	var size_mult = randf_range(0.4, 0.9) 
	var spark_count = int(100 * size_mult)  # High density!
	
	# Create GHOST particles (Visual only) 
	for i in range(spark_count):
		var ang = randf() * TAU
		var force = randf_range(20, 60) * size_mult # Slower, compact expansion
		var spark = {
			"x": float(ex),
			"y": float(ey),
			"vx": cos(ang) * force,
			"vy": sin(ang) * force,
			"color": p_color, 
			"life": randf_range(1.0, 1.8) # Snappier life
		}
		visual_sparks.append(spark)
