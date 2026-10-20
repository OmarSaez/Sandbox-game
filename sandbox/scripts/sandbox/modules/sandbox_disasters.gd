class_name SandboxDisasterManager extends Node

# ==============================================================================
# SandboxDisasterManager - Gestor de Desastres Naturales y Clima
# Maneja la interfaz y la simulación física de desastres:
# - Volcán (retroalimentación auditiva y reset)
# - Tornado (vórtice cónico, detección de suelo, absorción elemental y shader)
# - Tsunami (onda gaussiana de líquidos)
# - Avión Bombardero (vuelo cinemático y bombardeo balístico)
# - Terremoto (sacudida de pantalla, licuefacción y pánico de NPCs)
# - Clima / Lluvia ácida y rayos
# ==============================================================================

var grid: Node = null

# --- Terremoto ---
var earthquake_intensity: int = 0
var earthquake_timer: float = 0.0

# --- Tornado ---
var tornado_intensity: int = 0
var tornado_timer: float = 0.0
var tornado_x: float = 0.0
var tornado_target_x: float = 0.0
var tornado_ground_y: float = 0.0
var tornado_visual: ColorRect = null
var tornado_element: int = 0 # 0: Polvo/Normal, 1: Fuego, 2: Ácido, 3: Eléctrico
var tornado_element_timer: float = 0.0
var tornado_absorb_fire: float = 0.0
var tornado_absorb_acid: float = 0.0
var tornado_absorb_elec: float = 0.0

# --- Tsunami ---
var tsunami_intensity: int = 0
var tsunami_timer: float = 0.0
var tsunami_wave_x: float = 0.0
var surface_cache: PackedInt32Array = PackedInt32Array()

# --- Avión Bombardero ---
var bombardero_intensity: int = 0
var bombardero_x: float = 0.0
var bombardero_y: float = 12.0
var bombardero_dir: float = 1.0
var bombardero_speed: float = 0.0
var bombardero_drop_prob: float = 0.0
var bombardero_pending_checks: Array = []
var bombardero_texture: Texture2D = null

# --- Clima y Desastres Futuros ---
var current_weather: int = 0
var acid_rain_intensity: int = 0
var lava_rain_intensity: int = 0
var meteor_storm_intensity: int = 0
var black_hole_intensity: int = 0
var sinkhole_intensity: int = 0
var sand_storm_intensity: int = 0

# --- UI Panel ---
var disaster_panel: PanelContainer = null


func setup(p_grid: Node) -> void:
	grid = p_grid
	if grid.grid_width > 0:
		surface_cache.resize(grid.grid_width)
	_setup_tornado_visual()
	if not bombardero_texture:
		bombardero_texture = load("res://assets/icon_game/avion_bombardero.png")


func _setup_tornado_visual() -> void:
	if not is_instance_valid(tornado_visual):
		tornado_visual = ColorRect.new()
		tornado_visual.name = "TornadoVisual"
		tornado_visual.visible = false
		tornado_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(tornado_visual)
		
		var t_mat = ShaderMaterial.new()
		t_mat.shader = load("res://scripts/sandbox/tornado_visual.gdshader")
		tornado_visual.material = t_mat


func clear_surface_cache() -> void:
	surface_cache.fill(0)


# ==============================================================================
# UI DE DESASTRES
# ==============================================================================

func setup_disaster_ui() -> void:
	grid._set_panning_mode(false)
	var s = grid._get_ui_scale()
	var disaster_btn = grid._create_vertical_category_btn("🌪️", "disasters")
	disaster_btn.name = "DisasterBtn"
	grid.ui_elements["disaster_btn"] = disaster_btn
	disaster_btn.add_theme_font_override("font", grid._get_safe_font())
	disaster_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	disaster_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.action_hbox.add_child(disaster_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.2, 0.2, 1.0) # SOLID dark red-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.5, 0.4, 0.4)
	btn_style.corner_radius_top_left = 0; btn_style.corner_radius_top_right = 0
	btn_style.corner_radius_bottom_left = 0; btn_style.corner_radius_bottom_right = 0
	disaster_btn.add_theme_stylebox_override("normal", btn_style)
	disaster_btn.add_theme_stylebox_override("hover", btn_style)
	disaster_btn.add_theme_stylebox_override("pressed", btn_style)
	disaster_btn.set_meta("base_style", btn_style)
	
	# CREATE FRESH PANEL WITH STYLE
	var ui_root = grid.get_parent().get_node("UI")
	grid.ui_root = ui_root
	disaster_panel = PanelContainer.new()
	disaster_panel.name = "DisasterPanel"
	ui_root.add_child(disaster_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.1, 0.1, 0.95) # Near opaque dark red-grey
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.4, 0.4)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	disaster_panel.add_theme_stylebox_override("panel", panel_style)
	
	disaster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	grid._align_panel_to_hud(disaster_panel, 370 * s, 490 * s)
	# RESTORE STATE
	disaster_panel.visible = ui_root.get_meta("disaster_v", false)
	
	for child in disaster_panel.get_children(): 
		if is_instance_valid(child): child.free() # CLEAR OLD PANEL IMMEDIATELY
		
	var scroll = ScrollContainer.new()
	scroll.name = "DisasterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# DISASTER PANEL NEEDS A VBOX FOR THE TITLE
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	disaster_panel.add_child(main_vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = tr("disasters")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", grid._get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", 34 * s)
	grid.ui_elements["disaster_panel_title"] = title_lbl
	main_vbox.add_child(title_lbl)
	
	main_vbox.add_child(scroll)
	
	disaster_btn.pressed.connect(func(): 
		grid._toggle_category_panel(disaster_panel)
		if is_instance_valid(disaster_panel) and disaster_panel.visible:
			grid._show_menu_reminder("disaster", disaster_panel.get_child(0), "TUTORIAL_STEP_4")
	)
	
	disaster_panel.mouse_entered.connect(func(): grid.is_mouse_over_ui = true)
	disaster_panel.mouse_exited.connect(func(): grid.is_mouse_over_ui = false)
	
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	var create_row = func(label_key: String, options: Array, callback: Callable, is_upcoming: bool = false):
		var lbl = Label.new()
		lbl.text = tr(label_key) + ": "
		lbl.add_theme_font_size_override("font_size", 22.0 * s)
		lbl.add_theme_font_override("font", grid._get_safe_font())
		grid.ui_elements[label_key + "_lbl"] = lbl
		v_box.add_child(lbl)
		
		var flow = HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(flow)
		
		if is_upcoming:
			lbl.modulate = Color(0.5, 0.5, 0.5, 0.7)
			flow.modulate = Color(0.5, 0.5, 0.5, 0.7)
		
		for i in range(options.size()):
			var osk = options[i]
			var btn = Button.new()
			btn.text = tr(osk)
			btn.custom_minimum_size = Vector2(80.0 * s, 45.0 * s)
			btn.add_theme_font_size_override("font_size", 20.0 * s)
			btn.add_theme_font_override("font", grid._get_safe_font())
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			
			# PREMIUM BASE STYLE
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = Color(0.12, 0.12, 0.15, 0.8)
			b_style.border_width_left = 1; b_style.border_width_top = 1
			b_style.border_width_right = 1; b_style.border_width_bottom = 1
			b_style.border_color = Color(0.3, 0.3, 0.4)
			b_style.corner_radius_top_left = 10 * s; b_style.corner_radius_top_right = 10 * s
			b_style.corner_radius_bottom_left = 10 * s; b_style.corner_radius_bottom_right = 10 * s
			btn.add_theme_stylebox_override("normal", b_style)
			btn.add_theme_stylebox_override("hover", b_style)
			btn.add_theme_stylebox_override("pressed", b_style)
			btn.set_meta("base_style", b_style)
			
			if is_upcoming:
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.modulate = Color(0.6, 0.6, 0.6)
			else:
				var level = i
				btn.pressed.connect(func(): 
					grid._play_action_sound("ui_click")
					grid._on_arcade_selection_made(false)
					callback.call(level)
				)
			flow.add_child(btn)
			grid.ui_elements[label_key + "_btn_" + str(i)] = [btn, osk]

	create_row.call("weather", ["off", "light", "med", "storm"], func(l): 
		current_weather = l
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)
	var int_keys = ["off", "light", "med", "heavy"]
	create_row.call("acid_rain", int_keys, func(l): 
		acid_rain_intensity = l
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)
	create_row.call("quake", ["off", "light", "med", "brutal"], func(l): 
		earthquake_intensity = l
		if l > 0: 
			earthquake_timer = grid._get_lut_rand_range(5.0, 7.0)
			grid._play_action_sound("earthquake")
			grid._toggle_category_panel(disaster_panel)
		else:
			earthquake_timer = 0 # Reset para apagar sonido e intensidad
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)
	create_row.call("tornado", ["off", "light", "med", "heavy"], func(l):
		tornado_intensity = l
		if l > 0: 
			tornado_timer = 15.0; tornado_x = grid._get_lut_rand() * grid.grid_width; tornado_target_x = grid._get_lut_rand() * grid.grid_width
			tornado_ground_y = 0.0 # Start from the sky for landing animation
			tornado_element = 0 # Default normal
			grid._record_tornado_discovery(0) # Record normal type immediately
			grid._play_action_sound("tornado")
			grid._toggle_category_panel(disaster_panel)
		else:
			tornado_timer = 0 # Apagar instantáneamente
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)
	create_row.call("tsunami", ["off", "light", "med", "storm"], func(l):
		tsunami_intensity = l
		if l > 0: 
			tsunami_timer = 15.0; tsunami_wave_x = 0.0
			grid._play_action_sound("tsunami")
			grid._toggle_category_panel(disaster_panel)
		else:
			tsunami_timer = 0 # Apagar instantáneamente
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)
	
	create_row.call("bomber", ["off", "light", "med", "heavy"], func(l):
		bombardero_intensity = l
		if l > 0:
			start_bombardero()
			grid._toggle_category_panel(disaster_panel)
		else:
			stop_bombardero()
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)
	
	grid._add_ui_header(v_box, "coming_soon")
	
	create_row.call("lava_rain", int_keys, func(l): lava_rain_intensity = l; grid._update_menu_highlights(), true)
	create_row.call("met_storm", ["off", "light", "med", "storm"], func(l): meteor_storm_intensity = l; grid._update_menu_highlights(), true)
	create_row.call("black_hole", ["off", "light", "med", "heavy"], func(l): black_hole_intensity = l; grid._update_menu_highlights(), true)
	create_row.call("sinkhole", ["off", "light", "med", "heavy"], func(l): sinkhole_intensity = l; grid._update_menu_highlights(), true)
	create_row.call("sand_storm", ["off", "light", "med", "storm"], func(l): sand_storm_intensity = l; grid._update_menu_highlights(), true)


# ==============================================================================
# SIMULACIÓN DE TSUNAMI
# ==============================================================================

func process_tsunami(delta: float) -> void:
	if tsunami_timer <= 0:
		tsunami_intensity = 0
		if is_instance_valid(grid.tsunami_player) and grid.tsunami_player.playing: grid.tsunami_player.stop()
		grid._update_menu_highlights()
		return
	
	tsunami_timer -= delta
	
	# Move the wave front from Left to Right (Gaussian Center)
	tsunami_wave_x += (grid.grid_width / 5.0) * delta * 5.0
	if tsunami_wave_x > grid.grid_width + 150:
		tsunami_intensity = 0 # STOP AFTER ONE PASS
		grid._update_menu_highlights()
		return
	
	# Wave Configuration Constants (HALF POWER)
	var radius = 25 + (20 * tsunami_intensity)
	var max_wave_height = 4 + (3 * tsunami_intensity) # MEGA = ~13 pixels total
	var sigma_sq = pow(radius / 2.5, 2)
	
	var g_width = grid.grid_width
	var g_height = grid.grid_height
	var cells = grid.cells
	var mat_tags = grid.material_tags_raw
	
	# Determine Sea Reference Level (Reference height outside the wave)
	var ref_x = int(tsunami_wave_x - radius - 10)
	if ref_x >= 0 and ref_x < g_width:
		for gy in range(5, g_height - 5):
			var idx = gy * g_width + ref_x
			if (cells[idx] & 0xFF) > 0 and (mat_tags[grid._get_tags_id(cells[idx] & 0xFF)] & SandboxMaterial.Tags.LIQUID):
				break
	
	for ox in range(-radius, radius):
		var rx = int(tsunami_wave_x + ox)
		if rx < 0 or rx >= g_width: continue
		
		# Gaussian Height target
		var dist_sq = float(ox * ox)
		var gauss_h = int(max_wave_height * exp(-dist_sq / (2.0 * sigma_sq)))
		if gauss_h <= 1: continue
		
		# Find surface and material
		var y_top = -1
		var mid = 0
		for gy in range(5, g_height - 5):
			var idx = gy * g_width + rx
			if idx >= 0 and idx < cells.size():
				var raw_id = cells[idx]
				var pure_id = raw_id & 0xFFFF
				if pure_id > 0 and grid._get_tags_id(pure_id) < mat_tags.size():
					if (mat_tags[grid._get_tags_id(pure_id)] & SandboxMaterial.Tags.LIQUID):
						y_top = gy
						mid = raw_id # Keep variant info
						break
		
		if y_top == -1: continue
		if rx < surface_cache.size():
			surface_cache[rx] = y_top
		
		# SOLID PIXEL SPAWNING (Smooth, no tremor)
		for i in range(gauss_h):
			var target_y = y_top - i
			var source_y = y_top + i + 1
			
			if target_y > 5 and source_y < g_height:
				# Purely mathematical shift, no randf()
				if grid._get_cell(rx, target_y) == 0:
					var check_id = grid._get_cell(rx, source_y) & 0xFFFF
					if check_id > 0 and grid._get_tags_id(check_id) < mat_tags.size() and (mat_tags[grid._get_tags_id(check_id)] & SandboxMaterial.Tags.LIQUID):
						grid._swap_cells(rx, source_y, rx, target_y)
					else:
						grid._set_cell(rx, target_y, mid)


# ==============================================================================
# SIMULACIÓN DE AVIÓN BOMBARDERO
# ==============================================================================

func start_bombardero() -> void:
	# Decide random direction: -1 (right to left) or 1 (left to right)
	bombardero_dir = 1.0 if grid._get_lut_rand() < 0.5 else -1.0
	
	# Determine speed (crosses in 4.0s)
	bombardero_speed = grid.grid_width / 4.0
	
	# Determine Y position
	bombardero_y = 12.0
	
	# Start position outside grid
	if bombardero_dir == 1.0:
		bombardero_x = -40.0
	else:
		bombardero_x = grid.grid_width + 40.0
		
	# Determine check count and drop probability based on intensity
	var checks_count = 4
	if bombardero_intensity == 1:
		bombardero_drop_prob = 0.3
		checks_count = 4
	elif bombardero_intensity == 2:
		bombardero_drop_prob = 0.55
		checks_count = 8
	elif bombardero_intensity == 3:
		bombardero_drop_prob = 0.8
		checks_count = 12
		
	# Distribute check points between x = 15.0 and x = grid_width - 15.0
	bombardero_pending_checks.clear()
	var check_xs = []
	for i in range(checks_count):
		var fraction = (float(i) + 0.5) / float(checks_count)
		var cx = lerp(15.0, float(grid.grid_width) - 15.0, fraction)
		check_xs.append(cx)
		
	if bombardero_dir == 1.0:
		check_xs.sort()
	else:
		check_xs.sort()
		check_xs.reverse()
		
	bombardero_pending_checks = check_xs
	
	if not bombardero_texture:
		bombardero_texture = load("res://assets/icon_game/avion_bombardero.png")
		
	grid._manage_looping_player(grid.bombardero_player, "bomber_engine")
	if is_instance_valid(grid.bombardero_player):
		grid.bombardero_player.volume_db = -6.0


func stop_bombardero() -> void:
	bombardero_intensity = 0
	bombardero_pending_checks.clear()
	if is_instance_valid(grid.bombardero_player) and grid.bombardero_player.playing:
		grid.bombardero_player.stop()


func spawn_bomber_bomb(x: float, y: float) -> void:
	var bomb_r = 6
	if bombardero_intensity == 2:
		bomb_r = 12
	elif bombardero_intensity == 3:
		bomb_r = 20
		
	grid.active_projectiles.append({
		"pos": Vector2(x, y),
		"vel": Vector2(bombardero_dir * 15.0, 50.0), # forward momentum + initial downward vel
		"team": -1,
		"type": "bomber_bomb",
		"life": 8.0,
		"explosion_radius": bomb_r
	})
	grid._play_action_sound("bomb_drop", 0.05)


func process_bombardero(delta: float) -> void:
	if bombardero_intensity <= 0:
		return
		
	# Move the plane
	bombardero_x += bombardero_dir * bombardero_speed * delta
	
	# Perform checks
	if bombardero_dir == 1.0:
		while bombardero_pending_checks.size() > 0 and bombardero_x >= bombardero_pending_checks[0]:
			var _cx = bombardero_pending_checks.pop_front()
			if grid._get_lut_rand() < bombardero_drop_prob:
				spawn_bomber_bomb(bombardero_x, bombardero_y)
	else:
		while bombardero_pending_checks.size() > 0 and bombardero_x <= bombardero_pending_checks[0]:
			var _cx = bombardero_pending_checks.pop_front()
			if grid._get_lut_rand() < bombardero_drop_prob:
				spawn_bomber_bomb(bombardero_x, bombardero_y)
				
	# Check exit
	var is_finished = false
	if bombardero_dir == 1.0:
		if bombardero_x > grid.grid_width + 40.0:
			is_finished = true
	else:
		if bombardero_x < -40.0:
			is_finished = true
			
	if is_finished:
		stop_bombardero()
		grid._update_menu_highlights()


# ==============================================================================
# SIMULACIÓN DE TORNADO
# ==============================================================================

func process_tornado(delta: float) -> void:
	if tornado_timer <= 0:
		tornado_intensity = 0
		tornado_element = 0
		tornado_element_timer = 0
		if is_instance_valid(tornado_visual):
			tornado_visual.visible = false # Ensure visual disappears
		if is_instance_valid(grid.tornado_player) and grid.tornado_player.playing: grid.tornado_player.stop()
		grid._update_menu_highlights()
		return
	
	tornado_timer -= delta
	
	# Play sound loop while tornado is active
	grid._manage_looping_player(grid.tornado_player, "tornado_loop")
	
	# 1. Autonomous Movement
	if abs(tornado_x - tornado_target_x) < 5:
		tornado_target_x = grid._get_lut_rand() * grid.grid_width
	
	tornado_x = lerp(tornado_x, tornado_target_x, delta * 0.5)
	
	# 1.5 Ground Tracking (Find the surface)
	var tx = int(tornado_x)
	var detected_y = grid.grid_height - 1 # Default bottom
	# SCAN FROM BOTTOM UP: Find the first solid mass connected to the floor
	# and then find the 'air gap' above it to identify the true surface.
	var found_floor = false
	for gy in range(grid.grid_height - 1, 40, -1):
		var c = grid._get_cell(tx, gy)
		var is_solid = (c > 0 and c != 17 and c != 15)
		
		if not found_floor:
			if is_solid: found_floor = true
		else:
			if not is_solid:
				# This is the air gap above the main ground mass
				detected_y = gy + 1
				break
	
	# If we are in intensity 3, the tornado is more 'sticky' to its height
	# Landing Animation: Faster lerp when descending from sky
	var is_landing = tornado_ground_y < detected_y - 50
	var lerp_val = 0.15 if is_landing else (0.05 if tornado_intensity < 3 else 0.02)
	tornado_ground_y = lerp(tornado_ground_y, float(detected_y), lerp_val)
	
	# Update Dedicated Visual Node
	if tornado_intensity > 0 and is_instance_valid(tornado_visual):
		tornado_visual.visible = true
		var t_width = (80.0 + tornado_intensity * 60.0) * grid.grid_scale
		tornado_visual.size = Vector2(t_width, tornado_ground_y * grid.grid_scale)
		tornado_visual.position = Vector2(tornado_x * grid.grid_scale - t_width * 0.5, 0)
		
		# --- LOGRO: MAESTRO DE VIENTOS (Detección de seguridad) ---
		if grid.achievement_manager and not grid.achievement_manager.achievements["wind_master"].unlocked:
			grid._record_tornado_discovery(tornado_element)
			
		if tornado_element_timer > 0:
			tornado_element_timer -= delta
			if tornado_element_timer <= 0:
				tornado_element = 0
		
		# Absorption decay
		tornado_absorb_fire = lerp(tornado_absorb_fire, 0.0, delta * 2.0)
		tornado_absorb_acid = lerp(tornado_absorb_acid, 0.0, delta * 2.0)
		tornado_absorb_elec = lerp(tornado_absorb_elec, 0.0, delta * 2.0)
		
		# Thresholds to switch element
		if tornado_absorb_elec > 150:
			tornado_element = 3; tornado_element_timer = 6.0; tornado_absorb_elec = 0
			grid._record_tornado_discovery(3)
		elif tornado_absorb_acid > 200:
			tornado_element = 2; tornado_element_timer = 6.0; tornado_absorb_acid = 0
			grid._record_tornado_discovery(2)
		elif tornado_absorb_fire > 200:
			tornado_element = 1; tornado_element_timer = 6.0; tornado_absorb_fire = 0
			grid._record_tornado_discovery(1)
		
		if tornado_visual.material:
			tornado_visual.material.set_shader_parameter("intensity", float(tornado_intensity))
			tornado_visual.material.set_shader_parameter("element_type", tornado_element)
	elif is_instance_valid(tornado_visual):
		tornado_visual.visible = false
	
	# 2. Conical Vortex Physics & Clouds
	# DELAY PHYSICS until the tornado touches the ground
	if is_landing:
		return
		
	# Spawn clouds at the top and internal dust to ensure it's always visible
	if grid._get_lut_rand() < 0.3:
		grid._set_cell(int(tornado_x + grid._get_lut_rand_range(-40, 40)), 2, 17)
		grid._set_cell(int(tornado_x + grid._get_lut_rand_range(-20, 20)), 1, 17)
	
	# INTERNAL DUST: Always spawn some particles inside the funnel so it's not 'empty'
	if grid._get_lut_rand() < 0.4:
		var spawn_y = int(tornado_ground_y - grid._get_lut_rand() * 150.0)
		if spawn_y > 0 and spawn_y < grid.grid_height:
			var rel_y_s = 1.0 - (float(spawn_y) / tornado_ground_y) if tornado_ground_y > 0 else 1.0
			var rad_s = (25.0 + tornado_intensity * 15.0) + (50.0 * tornado_intensity * rel_y_s)
			grid._set_cell(int(tornado_x + grid._get_lut_rand_range(-rad_s * 0.4, rad_s * 0.4)), spawn_y, 15)
	
	# OPTIMIZED ITERATIONS: Increased for major destruction
	var points_to_process = 2000 * tornado_intensity if tornado_intensity < 3 else 6000
	
	var g_width = grid.grid_width
	var g_height = grid.grid_height
	var cells = grid.cells
	var mat_tags = grid.material_tags_raw
	
	for i in range(points_to_process):
		# Sample with bias: 60% of samples focus on the area near the ground
		var ry: int
		if grid._get_lut_rand() < 0.6:
			ry = int(tornado_ground_y + grid._get_lut_rand_range(-40, 100))
		else:
			ry = int(grid._get_lut_rand() * g_height)
		
		if ry < 0 or ry >= g_height: continue

		# Variable Radius relative to current GROUND level
		var rel_y = 1.0 - (float(ry) / tornado_ground_y) if tornado_ground_y > 0 else 1.0
		
		# Variable Radius calculation
		var current_radius = 0.0
		if ry <= tornado_ground_y:
			current_radius = (25.0 + tornado_intensity * 15.0) + (50.0 * tornado_intensity * rel_y)
		else:
			# Dig slightly into the ground
			current_radius = max(0, (25.0 + tornado_intensity * 15.0) - (ry - tornado_ground_y))
			
		# OPTIMIZED SAMPLING: Only sample within the area that passes the suction_threshold
		var suction_threshold = 0.4 if ry < tornado_ground_y - 80 else 0.6
		var max_dist_x = current_radius * (1.0 - suction_threshold)
		
		var rx = int(tornado_x + grid._get_lut_rand_range(-max_dist_x, max_dist_x))
		
		if rx < 0 or rx >= g_width or ry < 0 or ry >= g_height: continue
		
		var tid = cells[ry * g_width + rx] & 0xFFFF # Inline fast lookup
		if tid == 0 or tid == 17: continue 
		
		var tags = mat_tags[grid._get_tags_id(tid)]
		
		# Absorption tracking (Prioritize Electricity/Acid tags if material has multiple)
		if (tags & SandboxMaterial.Tags.ELECTRICITY): tornado_absorb_elec += 1
		elif (tags & SandboxMaterial.Tags.ACID): tornado_absorb_acid += 1
		elif (tags & SandboxMaterial.Tags.INCENDIARY): tornado_absorb_fire += 1
		
		# Elemental Effects
		if tornado_element == 1: # FIRE
			if (tags & SandboxMaterial.Tags.FLAMMABLE):
				grid._set_cell(rx, ry, 3) # Ignite to Fire
			elif grid._get_lut_rand() < 0.05:
				grid._set_cell(rx, ry, 3)
		elif tornado_element == 2: # ACID
			if not (tags & SandboxMaterial.Tags.ANTI_ACID):
				if grid._get_lut_rand() < 0.2: grid._set_cell(rx, ry, 13) # Convert to Acid
		elif tornado_element == 3: # ELECTRIC
			grid.charge_array[ry * g_width + rx] = 255
			if grid._get_lut_rand() < 0.02: grid._set_cell(rx, ry, 43) # Spawn sparks
		
		# Vortex Forces
		var dist_x_abs = abs(tornado_x - rx)
		var pull_strength = 1.0 - (dist_x_abs / (current_radius + 1.0))

		var target_x = tornado_x + grid._get_lut_rand_range(-current_radius * 0.7, current_radius * 0.7)
		var dx = sign(target_x - rx)
		
		# Pull up FORCE: Massive buff for all levels
		var base_up = -8 if tornado_intensity < 2 else (-16 if tornado_intensity == 2 else -32)
		var dy = int(base_up * pull_strength)
		if dy >= 0: dy = -1 # Ensure it always moves up if caught
		
		if ry > tornado_ground_y: dy = 1 if grid._get_lut_rand() < 0.5 else -1 # Chaos/digging
		
		# Swirl/Orbital chance
		if grid._get_lut_rand() < 0.3: dx = -dx 
		
		# --- NPC INTERACTION (Fixes trails and adds physics) ---
		if (tags & SandboxMaterial.Tags.NPC):
			var nearby_npcs = grid._get_nearby_npcs(rx, ry, 15.0)
			for n in nearby_npcs:
				# Precise hit check for the NPC body
				if abs(n.pos.x - rx) <= 3 and ry >= n.pos.y and ry <= n.pos.y + 6:
					# Apply physics force instead of moving pixels directly
					n.vx += dx * pull_strength * 5.0
					n.vy += float(dy) * 0.4
					
					# Elemental Damage
					if tornado_element == 1: # Fire
						n.hp -= 0.6; n.hit_flash = 4; n.hit_type = "fire"
					elif tornado_element == 2: # Acid
						n.hp -= 1.0; n.hit_flash = 4; n.hit_type = "acid"
					elif tornado_element == 3: # Electric
						n.hp -= 0.5; n.hit_flash = 4; n.hit_type = "electric"
						
					if grid._get_lut_rand() < 0.05: grid._set_npc_emoji(n, "😱", 1.0)
			continue # SKIP manual pixel swap for NPCs to prevent tearing/trails
		
		# Suction Chance for normal materials
		if grid._get_lut_rand() < pull_strength:
			var nx = rx + dx
			var ny = ry + dy
			if nx >= 0 and nx < g_width and ny >= 0 and ny < g_height:
				# Suction can lift anything into air
				if grid._get_cell(nx, ny) == 0:
					grid._swap_cells(rx, ry, nx, ny)
				elif grid._get_lut_rand() < 0.2: # Can also mix with other particles inside funnel
					grid._swap_cells(rx, ry, nx, ny)


# ==============================================================================
# SIMULACIÓN DE TERREMOTO
# ==============================================================================

func process_earthquake(delta: float) -> void:
	if earthquake_timer <= 0:
		if is_instance_valid(grid.texture_rect) and grid.texture_rect.position != Vector2.ZERO:
			grid.texture_rect.position = Vector2.ZERO
		earthquake_intensity = 0
		if is_instance_valid(grid.quake_player) and grid.quake_player.playing: grid.quake_player.stop()
		grid._update_menu_highlights()
		return
	
	earthquake_timer -= delta
	
	# Play sound loop while earthquake is active
	grid._manage_looping_player(grid.quake_player, "quake_loop")
	
	# 1. Screen Shake (Visual) - Much more violent for higher intensities
	var shake_force = float(earthquake_intensity) * 6.0
	if earthquake_intensity >= 3: shake_force = 15.0 # Extra violent for BRUTAL
	
	if shake_force > 0 and is_instance_valid(grid.texture_rect):
		grid.texture_rect.position = Vector2(grid._get_lut_rand_range(-shake_force, shake_force), grid._get_lut_rand_range(-shake_force, shake_force))
	
	# 2. Physics Chaos (Actual material movement)
	# Scaled iterations: light=4000, med=8000, brutal=15000 per frame
	var iterations = 4000 * earthquake_intensity 
	# Max displacement range: light=8, med=16, brutal=24 pixels
	var max_offset = float(earthquake_intensity * 8.0) 
	
	var g_width = grid.grid_width
	var g_height = grid.grid_height
	var cells = grid.cells
	var mat_tags = grid.material_tags_raw
	
	for i in range(iterations):
		# Random sampling across the whole grid
		var rx = int(grid._get_lut_rand() * g_width)
		var ry = int(grid._get_lut_rand() * g_height)
		var idx = ry * g_width + rx
		
		# Skip air for performance optimization
		if cells[idx] == 0: continue
		
		# ANTI-TEARING: Don't move NPC pixels (they are managed as a single entity)
		var tid = cells[idx] & 0xFFFF
		if mat_tags[grid._get_tags_id(tid)] & SandboxMaterial.Tags.NPC: continue
		
		# Random direction and distance using LUT for "disparar" effect
		var dx = int(grid._get_lut_rand_range(-max_offset, max_offset))
		var dy = int(grid._get_lut_rand_range(-max_offset, max_offset))
		
		var nx = rx + dx
		var ny = ry + dy
		
		if nx >= 0 and nx < g_width and ny >= 0 and ny < g_height:
			# ANTI-TEARING: Don't overwrite NPC pixels at destination either
			var n_tid = cells[ny * g_width + nx] & 0xFFFF
			if not (mat_tags[grid._get_tags_id(n_tid)] & SandboxMaterial.Tags.NPC):
				# Massive mixing/dispersal: Swap regardless of what's there (liquefaction)
				grid._swap_cells(rx, ry, nx, ny)
				grid._activate_chunk(nx, ny) # Ensure it keeps moving/falling
			
	# 3. NPC Panic & Physical Displacement
	# NPCs should feel the earth moving without flying to the ceiling
	var shock_limit = float(earthquake_intensity) * 0.4
	for n in grid.active_npcs:
		if n.hp > 0:
			# Very small horizontal jitter
			n.vx += grid._get_lut_rand_range(-shock_limit, shock_limit)
			
			# Occasional small vertical "pop" to simulate ground shock, 
			# but rare enough that gravity (20Hz) can easily overcome it
			if grid._get_lut_rand() < 0.05: 
				n.vy -= grid._get_lut_rand() * float(earthquake_intensity) * 1.5
			
			# Chance to trip or show emoji (less frequent)
			if grid._get_lut_rand() < 0.02 * earthquake_intensity:
				grid._set_npc_emoji(n, ["🫨", "😱", "😨"].pick_random(), 0.8)
	
	# Automatic stop after timer
	if earthquake_timer <= 0:
		earthquake_intensity = 0


# ==============================================================================
# SIMULACIÓN DE CLIMA Y RAYOS
# ==============================================================================

func process_weather() -> void:
	if current_weather == 0 and acid_rain_intensity == 0: 
		if is_instance_valid(grid.weather_player) and grid.weather_player.playing: grid.weather_player.stop()
		return
	
	# Manage weather sound loop (rain_light, rain_med, rain_storm)
	var max_intensity = max(current_weather, acid_rain_intensity)
	var w_key = "weather_" + str(max_intensity)
	grid._manage_looping_player(grid.weather_player, w_key)
	
	# Always spawn some clouds at the top if weather or acid rain is active
	for i in range(5):
		grid._set_cell(int(grid._get_lut_rand() * grid.grid_width), 1, 17)
	
	# Spawn normal rain based on intensity
	if current_weather > 0:
		var rain_chance = 0.05 if current_weather == 1 else (0.2 if current_weather == 2 else 0.5)
		if grid._get_lut_rand() < rain_chance:
			# Spawn multiple droplets based on level
			for i in range(current_weather * 2):
				grid._set_cell(int(grid._get_lut_rand() * grid.grid_width), 5 + int(grid._get_lut_rand() * 5), 2) # Spawn Water
				
	# Spawn acid rain based on intensity
	if acid_rain_intensity > 0:
		var acid_rain_chance = 0.05 if acid_rain_intensity == 1 else (0.2 if acid_rain_intensity == 2 else 0.5)
		if grid._get_lut_rand() < acid_rain_chance:
			# Spawn multiple acid droplets based on level
			for i in range(acid_rain_intensity * 2):
				grid._set_cell(int(grid._get_lut_rand() * grid.grid_width), 5 + int(grid._get_lut_rand() * 5), 13) # Spawn Acid
			
	# Lightning in Storm (Level 3)
	if max_intensity == 3 and grid._get_lut_rand() < 0.01: # Rare but impactful
		strike_lightning()
		
	# Spontaneous Grass growth during normal rain or near water (SURFACE ONLY)
	if current_weather > 0 and grid._get_lut_rand() < 0.2: # Check in 20% of frames
		for i in range(100): # 100 random samples per check
			var rx = int(grid._get_lut_rand() * grid.grid_width)
			var ry = int(grid._get_lut_rand() * (grid.grid_height - 10)) + 5
			var tid = grid._get_cell(rx, ry)
			if tid == 6 or tid == 1: # EARTH or SAND (FERTILE)
				if grid._get_cell(rx, ry-1) == 0: # Space above (Surface check)
					# Check for moisture (OVAL 20x10)
					if current_weather > 0 or grid._has_tag_within_oval(rx, ry, SandboxMaterial.Tags.LIQUID, 20, 10):
						if grid._get_lut_rand() < 0.1: # Organic chance
							grid._set_cell(rx, ry-1, 21) # GROW GRASS
							if i > 5: break


func strike_lightning() -> void:
	grid._play_action_sound("lightning")
	var lx = int(grid._get_lut_rand() * grid.grid_width)
	# Trace a bolt from top to first solid/liquid or bottom
	for ly in range(0, grid.grid_height):
		var target_id = grid._get_cell(lx, ly)
		# Ignite everything in the bolt path
		grid._set_cell(lx, ly, 9) # Deploy Electricity!
		# If we hit something non-empty, stop bolt and create small explosion
		# NEW: Ignore rain (2) so it hits the ground
		if target_id > 0 and target_id != 17 and target_id != 15 and target_id != 2:
			grid._explode(lx, ly, 5, "explosion", grid.EXP_VOLCANO | 128) # Small localized explosion
			break


func strike_lightning_at(lx: int) -> void:
	grid._play_action_sound("lightning_user")
	# Trace a bolt straight down from the top at the given column
	for ly in range(0, grid.grid_height):
		var target_id = grid._get_cell(lx, ly)
		grid._set_cell(lx, ly, 9) # Deploy Electricity!
		# Stop bolt at first solid/liquid (ignore rain=2, steam=17, snow=15)
		if target_id > 0 and target_id != 17 and target_id != 15 and target_id != 2:
			grid._explode(lx, ly, 5, "explosion", grid.EXP_VOLCANO | 128) # Small localized explosion
			break


# ==============================================================================
# REINICIO GLOBAL DE DESASTRES
# ==============================================================================

func reset_all_disasters() -> void:
	current_weather = 0
	earthquake_intensity = 0; earthquake_timer = 0.0
	tornado_intensity = 0; tornado_timer = 0.0
	tsunami_intensity = 0; tsunami_timer = 0.0
	bombardero_intensity = 0
	
	# Future/Upcoming Resets
	acid_rain_intensity = 0
	lava_rain_intensity = 0
	meteor_storm_intensity = 0
	black_hole_intensity = 0
	sinkhole_intensity = 0
	sand_storm_intensity = 0
	
	if is_instance_valid(tornado_visual):
		tornado_visual.visible = false
	if is_instance_valid(grid.texture_rect) and grid.texture_rect.position != Vector2.ZERO:
		grid.texture_rect.position = Vector2.ZERO
	
	# Stop all looping players
	if is_instance_valid(grid.weather_player) and grid.weather_player.playing: grid.weather_player.stop()
	if is_instance_valid(grid.quake_player) and grid.quake_player.playing: grid.quake_player.stop()
	if is_instance_valid(grid.tornado_player) and grid.tornado_player.playing: grid.tornado_player.stop()
	if is_instance_valid(grid.tsunami_player) and grid.tsunami_player.playing: grid.tsunami_player.stop()
	if is_instance_valid(grid.volcano_loop_player) and grid.volcano_loop_player.playing: grid.volcano_loop_player.stop()
	if is_instance_valid(grid.bombardero_player) and grid.bombardero_player.playing: grid.bombardero_player.stop()
	bombardero_pending_checks.clear()
