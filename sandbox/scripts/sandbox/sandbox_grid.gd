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
# UI State
var is_mouse_over_ui: bool = false
var brush_radius: int = 2 
var current_language: String = "es" # "es" or "en"
var ui_elements = {} # To track nodes for re-labeling
var tools_panel: PanelContainer
var disaster_panel: PanelContainer

var tr = {
	"es": {
		"disasters": "🌪️ Desastres",
		"tools": "🛠️ Herramientas",
		"lang": "🌐 Idioma",
		"brush": "🖌️ Pincel",
		"weather": "⛈️ Clima",
		"quake": "🫨 Sismo",
		"tornado": "🌪️ Tornado",
		"tsunami": "🌊 Tsunami",
		"off": "Off",
		"light": "Ligero",
		"med": "Medio",
		"storm": "Tormenta",
		"brutal": "¡BRUTAL!",
		"heavy": "Fuerte",
		# Materials
		"sand": "Arena",
		"water": "Agua",
		"fire": "Fuego",
		"tnt": "TNT",
		"earth": "Tierra",
		"metal": "Metal",
		"elec": "Elect.",
		"gravel": "Grava",
		"lava": "Lava",
		"obisid": "Obsidiana",
		"acid": "Ácido",
		"wood": "Madera",
		"petro": "Petróleo",
		"fireworks": "Cohetes",
		"seed": "Semilla",
		"grass": "Pasto",
		"vine": "Liana",
		"cem_fresh": "Cem. Fresco",
		"cement": "Cemento",
		"volcan": "Volcán",
		"reset": "Limpiar Todo"
	},
	"en": {
		"disasters": "🌪️ Disasters",
		"tools": "🛠️ Tools",
		"lang": "🌐 Language",
		"brush": "🖌️ Brush",
		"weather": "⛈️ Weather",
		"quake": "🫨 Quake",
		"tornado": "🌪️ Tornado",
		"tsunami": "🌊 Tsunami",
		"off": "Off",
		"light": "Light",
		"med": "Medium",
		"storm": "Storm",
		"brutal": "BRUTAL!",
		"heavy": "Heavy",
		# Materials
		"sand": "Sand",
		"water": "Water",
		"fire": "Fire",
		"tnt": "TNT",
		"earth": "Earth",
		"metal": "Metal",
		"elec": "Elec",
		"gravel": "Gravel",
		"lava": "Lava",
		"obisid": "Obsidian",
		"acid": "Acid",
		"wood": "Wood",
		"petro": "Oil",
		"fireworks": "Fireworks",
		"seed": "Seed",
		"grass": "Grass",
		"vine": "Vine",
		"cem_fresh": "Fresh Cement",
		"cement": "Cement",
		"volcan": "Volcano",
		"reset": "Clear All"
	}
}

# Earthquake settings
var earthquake_intensity: int = 0
var earthquake_timer: float = 0.0

# Tornado settings
var tornado_intensity: int = 0
var tornado_timer: float = 0.0
var tornado_x: float = 0.0
var tornado_target_x: float = 0.0
var tornado_ground_y: float = 0.0

# Tsunami settings
var tsunami_intensity: int = 0
var tsunami_timer: float = 0.0
var tsunami_wave_x: float = 0.0
var surface_cache = PackedInt32Array()

# Fireworks tracking
var active_fireworks = [] 
var visual_sparks = []

# Display
@onready var texture_rect: TextureRect = $Display
var img: Image

func _ready():
	# Calculate grid size based on viewport - Deducting 180px for the new Unified UI bar
	var actual_viewport_height = get_viewport_rect().size.y - 180
	var viewport_size = Vector2(get_viewport_rect().size.x, actual_viewport_height)
	
	grid_width = floor(viewport_size.x / grid_scale)
	grid_height = floor(viewport_size.y / grid_scale)
	
	# Update Display node size to match the grid exactly
	$Display.custom_minimum_size = Vector2(grid_width * grid_scale, grid_height * grid_scale)
	$Display.size = $Display.custom_minimum_size
	
	# Init arrays
	cells.resize(grid_width * grid_height)
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	color_buffer.resize(grid_width * grid_height * 4)
	surface_cache.resize(grid_width)
	
	tags_array.resize(grid_width * grid_height)
	charge_array.resize(grid_width * grid_height)
	
	material_colors_raw.resize(50) 
	material_tags_raw.resize(50)
	
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

	# --- NEW PLANT LIFE ---
	# Seed (Light Green)
	_register_material(20, Color("#A2D149"), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.SEED | SandboxMaterial.Tags.FLAMMABLE)
	# Grass (Bright Green)
	_register_material(21, Color("#4CAF50"), SandboxMaterial.Tags.PLANT | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.BURN_COAL)
	
	# Mark existing materials as FERTILE
	material_tags_raw[1] |= SandboxMaterial.Tags.FERTILE
	material_tags_raw[6] |= SandboxMaterial.Tags.FERTILE
	
	# --- WET STATES (For Debug & Realism) ---
	# Wet Sand (Darker Yellow)
	_register_material(22, Color("#C2B280").darkened(0.2), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.FERTILE)
	# Wet Earth (Darker Brown)
	_register_material(23, Color("#8B4513").darkened(0.2), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.FERTILE | SandboxMaterial.Tags.BURN_COAL)
	
	# --- NEW VINE (Stem) ---
	# Forest Green (Darker) - Now leaves coal when burned
	_register_material(24, Color("#3E5E2A"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.PLANT | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.BURN_COAL)

	# --- NEW CONSTRUCTION MATERIALS ---
	# Fresh Cement (Light Beige Liquid)
	_register_material(25, Color("#E5D3B3"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GRAV_NORMAL)
	# Cement (Solid Beige)
	_register_material(26, Color("#C2B280"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC)
	
	# --- VOLCANO SYSTEM ---
	# 27: Volcan (Block) - Neon Orange + Anti-Explosive
	_register_material(27, Color("#FF5F1F"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	# 28: Eruption (Projectile) - Bright Yellow/Orange - Handled manually
	_register_material(28, Color("#FFFF00"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	# 29: Active Base (Launcher) - Glowing Orange-Red
	_register_material(29, Color("#FF4500"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE)

	# UI SETUP (Must happen AFTER materials are registered)
	_setup_main_ui_containers()
	_setup_ui()
	
	# FORCE START HIDDEN
	tools_panel.visible = false
	disaster_panel.visible = false
	
	_register_material(19, Color(1, 0.8, 0.9), SandboxMaterial.Tags.GRAV_STATIC) # Firework Fuse

	# INITIAL HIGHLIGHT
	_update_highlights()

func _setup_materials_within_grid():
	if material_grid.get_child_count() > 0: return # Already setup physically?
	
	# Setup all material buttons (Unified)
	_add_button("sand", 1)
	_add_button("water", 2)
	_add_button("fire", 3)
	_add_button("tnt", 5)
	_add_button("earth", 6)
	_add_button("metal", 8)
	_add_button("elec", 9)
	_add_button("gravel", 10)
	_add_button("lava", 11)
	_add_button("obisid", 12)
	_add_button("acid", 13)
	_add_button("wood", 16)
	_add_button("petro", 4)
	_add_button("fireworks", 18)
	_add_button("seed", 20)
	_add_button("grass", 21)
	_add_button("vine", 24)
	_add_button("cem_fresh", 25)
	_add_button("cement", 26)
	_add_button("volcan", 27)


func _setup_ui():
	_setup_tools_ui() # Tools on top
	_setup_disaster_ui() # Disasters below

var material_grid: HFlowContainer
var action_vbox: VBoxContainer

func _setup_main_ui_containers():
	var ui_root = get_parent().get_node("UI")
	var main_controls = ui_root.get_node("Controls")
	
	# We no longer clear the controls! 
	# We expect 'MaterialGrid' and 'ActionButtons' to be physical nodes in the scene.
	
	# Reference existing nodes or create them if missing (Safety)
	if main_controls.has_node("MaterialGrid"):
		material_grid = main_controls.get_node("MaterialGrid")
	else:
		material_grid = HFlowContainer.new()
		material_grid.name = "MaterialGrid"
		main_controls.add_child(material_grid)
	
	if main_controls.has_node("ActionButtons"):
		action_vbox = main_controls.get_node("ActionButtons")
		action_vbox.mouse_entered.connect(func(): is_mouse_over_ui = true)
		action_vbox.mouse_exited.connect(func(): is_mouse_over_ui = false)
	else:
		action_vbox = VBoxContainer.new()
		action_vbox.name = "ActionButtons"
		action_vbox.mouse_entered.connect(func(): is_mouse_over_ui = true)
		action_vbox.mouse_exited.connect(func(): is_mouse_over_ui = false)
		main_controls.add_child(action_vbox)

	if material_grid:
		material_grid.mouse_entered.connect(func(): is_mouse_over_ui = true)
		material_grid.mouse_exited.connect(func(): is_mouse_over_ui = false)

	# Setup buttons within the material grid if they don't exist
	_setup_materials_within_grid()


func _setup_tools_ui():
	var ui_root = get_parent().get_node("UI")
	var tools_btn = Button.new()
	tools_btn.name = "ToolsBtn"
	tools_btn.custom_minimum_size = Vector2(150, 60)
	tools_btn.text = tr[current_language]["tools"]
	ui_elements["tools_btn"] = tools_btn
	action_vbox.add_child(tools_btn)
	
	tools_panel = ui_root.get_node("ToolsPanel")
	tools_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# SETUP INTERNAL BOX IF NOT PRESENT
	var v_box: VBoxContainer
	if tools_panel.get_child_count() == 0:
		v_box = VBoxContainer.new()
		v_box.add_theme_constant_override("separation", 15)
		tools_panel.add_child(v_box)
	else:
		v_box = tools_panel.get_child(0)
	
	tools_btn.pressed.connect(func(): 
		disaster_panel.visible = false
		tools_panel.visible = !tools_panel.visible
	)
	
	tools_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	tools_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	var create_row = func(label_key: String, options: Array, callback: Callable):
		var h_box = HBoxContainer.new()
		h_box.add_theme_constant_override("separation", 10)
		var lbl = Label.new()
		lbl.text = tr[current_language][label_key] + ": "
		lbl.custom_minimum_size = Vector2(120, 0)
		ui_elements[label_key + "_lbl"] = lbl
		h_box.add_child(lbl)
		for i in range(options.size()):
			var btn = Button.new()
			btn.text = options[i]
			btn.custom_minimum_size = Vector2(80, 45)
			var level = i
			btn.pressed.connect(func(): callback.call(level))
			h_box.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = btn # Store to refresh (if static text)
		v_box.add_child(h_box)

	# Language Row (First Tool)
	var lang_options = ["Español", "English"]
	create_row.call("lang", lang_options, func(l):
		current_language = "en" if l == 1 else "es"
		_refresh_ui_text()
		_update_highlights()
	)

	# BRUSH SIZE ROW
	var brush_sizes = [0, 1, 2, 5, 7, 12]
	var brush_labels = ["1px", "3px", "5px", "10px", "15px", "25px"]
	create_row.call("brush", brush_labels, func(l): 
		brush_radius = brush_sizes[l]
		_update_highlights()
	)
	
	# DIRECT RESET BUTTON (Bottom of Tools)
	var reset_btn = Button.new()
	reset_btn.text = tr[current_language]["reset"]
	reset_btn.custom_minimum_size = Vector2(0, 50)
	reset_btn.pressed.connect(func():
		_clear_all()
	)
	ui_elements["reset_btn"] = reset_btn
	v_box.add_child(reset_btn)

func _setup_disaster_ui():
	var disaster_btn = Button.new()
	disaster_btn.name = "DisasterBtn"
	disaster_btn.custom_minimum_size = Vector2(150, 60)
	disaster_btn.text = tr[current_language]["disasters"]
	ui_elements["disaster_btn"] = disaster_btn
	action_vbox.add_child(disaster_btn)
	
	var ui_root = get_parent().get_node("UI")
	disaster_panel = ui_root.get_node("DisasterPanel")
	disaster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var v_box: VBoxContainer
	if disaster_panel.get_child_count() == 0:
		v_box = VBoxContainer.new()
		v_box.add_theme_constant_override("separation", 15)
		disaster_panel.add_child(v_box)
	else:
		v_box = disaster_panel.get_child(0)
	
	disaster_btn.pressed.connect(func(): 
		tools_panel.visible = false
		disaster_panel.visible = !disaster_panel.visible
	)
	
	disaster_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	disaster_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	var create_row = func(label_key: String, options_keys: Array, callback: Callable):
		var h_box = HBoxContainer.new()
		h_box.add_theme_constant_override("separation", 10)
		var lbl = Label.new()
		lbl.text = tr[current_language][label_key] + ": "
		lbl.custom_minimum_size = Vector2(120, 0)
		ui_elements[label_key + "_lbl"] = lbl
		h_box.add_child(lbl)
		for i in range(options_keys.size()):
			var osk = options_keys[i]
			var btn = Button.new()
			btn.text = tr[current_language][osk]
			btn.custom_minimum_size = Vector2(80, 45)
			btn.pressed.connect(func(): callback.call(i))
			h_box.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = [btn, osk] # Store button and key for translation
		v_box.add_child(h_box)

	create_row.call("weather", ["off", "light", "med", "storm"], func(l): 
		current_weather = l
		_update_highlights()
	)
	create_row.call("quake", ["off", "light", "med", "brutal"], func(l): 
		earthquake_intensity = l
		if l > 0: earthquake_timer = randf_range(5.0, 7.0)
		_update_highlights()
	)
	create_row.call("tornado", ["off", "light", "med", "heavy"], func(l):
		tornado_intensity = l
		if l > 0: tornado_timer = 15.0; tornado_x = randf()*grid_width; tornado_target_x = randf()*grid_width
		_update_highlights()
	)
	create_row.call("tsunami", ["off", "light", "med", "storm"], func(l):
		tsunami_intensity = l
		if l > 0: tsunami_timer = 15.0; tsunami_wave_x = 0.0
		_update_highlights()
	)

func _refresh_ui_text():
	for key in ui_elements:
		var node_data = ui_elements[key]
		
		# Handle direct button nodes (Tools/Disasters)
		if key == "tools_btn": node_data.text = tr[current_language]["tools"]
		elif key == "disaster_btn": node_data.text = tr[current_language]["disasters"]
		elif key == "reset_btn": node_data.text = tr[current_language]["reset"]
		
		# Handle Labels (Main labels for rows and material names)
		elif node_data is Label:
			if key.ends_with("_mat_lbl"):
				var pure_key = key.replace("_mat_lbl", "")
				if tr[current_language].has(pure_key):
					node_data.text = tr[current_language][pure_key]
			elif key.ends_with("_lbl"):
				var pure_key = key.replace("_lbl", "")
				if tr[current_language].has(pure_key):
					node_data.text = tr[current_language][pure_key] + ": "
		
		# Handle Intensity Buttons (Stored as Array [Btn, Key])
		elif node_data is Array:
			var btn = node_data[0]
			var osk = node_data[1]
			btn.text = tr[current_language][osk]

func _add_button(key: String, mat_id: int):
	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.custom_minimum_size = Vector2(75, 70) # UNIFORM SIZE FOR ALL
	
	# Icon Wrapper (for border)
	var icon_panel = PanelContainer.new()
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(0,0,0,0) # Transparent background
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	icon_panel.custom_minimum_size = Vector2(50, 50) # 40 + 5 + 5 for border
	
	# Icon (ColorRect)
	var icon = ColorRect.new()
	icon.color = material_colors_raw[mat_id]
	icon.custom_minimum_size = Vector2(40, 40)
	icon.mouse_filter = Control.MOUSE_FILTER_PASS 
	
	# Connect icon click to selection
	icon.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			selected_material = mat_id
			_update_highlights()
	)
	icon.set_meta("mat_id", mat_id)
	
	icon_panel.add_child(icon)
	main_vbox.add_child(icon_panel)
	
	ui_elements[key + "_icon_pnl"] = icon_panel # Store panel for border
	
	var btn = Label.new()
	btn.text = tr[current_language][key]
	btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	# ALSO CLICKABLE LABEL
	btn.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			selected_material = mat_id
			_update_highlights()
	)
	ui_elements[key + "_mat_lbl"] = btn
	main_vbox.add_child(btn)
	
	material_grid.add_child(main_vbox) 
	
	main_vbox.mouse_entered.connect(func(): is_mouse_over_ui = true)
	main_vbox.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _update_highlights():
	# Update Material Selection (Icons & Labels)
	for child in material_grid.get_children():
		var icon_pnl = child.get_child(0)
		var label = child.get_child(1)
		var mat_id = icon_pnl.get_child(0).get_meta("mat_id")
		
		var style = icon_pnl.get_theme_stylebox("panel").duplicate()
		if mat_id == selected_material:
			# HIGHLIGHT: Bright border + Yellow text
			style.border_width_left = 5
			style.border_width_top = 5
			style.border_width_right = 5
			style.border_width_bottom = 5
			style.border_color = Color.WHITE
			icon_pnl.add_theme_stylebox_override("panel", style)
			label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			# DEFAULT: No border + White text
			style.border_width_left = 0
			style.border_width_top = 0
			style.border_width_right = 0
			style.border_width_bottom = 0
			icon_pnl.add_theme_stylebox_override("panel", style)
			label.remove_theme_color_override("font_color")

	# 2. Update Tool/Disaster Highlights (Buttons)
	for key in ui_elements:
		var node_data = ui_elements[key]
		if key.contains("_btn_"):
			var btn = node_data
			if node_data is Array: btn = node_data[0]
			
			if btn is Button:
				# Check if this button is the active one
				var is_active = false
				if key.begins_with("brush_btn_"):
					var idx = int(key.split("_")[-1])
					var brush_sizes = [0, 1, 2, 5, 7, 12]
					if brush_sizes[idx] == brush_radius: is_active = true
				elif key.begins_with("lang_btn_"):
					var idx = int(key.split("_")[-1])
					if (idx == 1 and current_language == "en") or (idx == 0 and current_language == "es"): is_active = true
				elif key.begins_with("weather_btn_"):
					if int(key.split("_")[-1]) == current_weather: is_active = true
				elif key.begins_with("quake_btn_"):
					if int(key.split("_")[-1]) == earthquake_intensity: is_active = true
				elif key.begins_with("tornado_btn_"):
					if int(key.split("_")[-1]) == tornado_intensity: is_active = true
				elif key.begins_with("tsunami_btn_"):
					if int(key.split("_")[-1]) == tsunami_intensity: is_active = true
				
				if is_active:
					btn.add_theme_color_override("font_color", Color.YELLOW)
					var highlight_style = StyleBoxFlat.new()
					highlight_style.bg_color = Color(0.3, 0.3, 0.4)
					highlight_style.border_width_bottom = 3
					highlight_style.border_color = Color.SKY_BLUE
					btn.add_theme_stylebox_override("normal", highlight_style)
				else:
					btn.remove_theme_color_override("font_color")
					btn.remove_theme_stylebox_override("normal")

func _is_any_ui_blocking() -> bool:
	if is_mouse_over_ui: return true # Original mouse_entered check
	
	# Fallback: Absolute Rect Check (For safety when clicking fast)
	var m_pos = texture_rect.get_global_mouse_position()
	
	if tools_panel and tools_panel.visible and tools_panel.get_global_rect().has_point(m_pos):
		return true
	if disaster_panel and disaster_panel.visible and disaster_panel.get_global_rect().has_point(m_pos):
		return true
	if material_grid and material_grid.get_global_rect().has_point(m_pos):
		return true
	if action_vbox and action_vbox.get_global_rect().has_point(m_pos):
		return true
		
	return false

func _register_material(id, color, tags):
	material_colors_raw[id] = color
	material_tags_raw[id] = tags

func _process(delta):
	# Handle input with robust UI blocking
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _is_any_ui_blocking():
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
		
	# Spontaneous Grass growth during rain or near water (SURFACE ONLY)
	if randf() < 0.2: # Check in 20% of frames
		for i in range(100): # 100 random samples per check
			var rx = randi() % grid_width
			var ry = randi() % (grid_height - 10) + 5
			var tid = _get_cell(rx, ry)
			if tid == 6 or tid == 1: # EARTH or SAND (FERTILE)
				if _get_cell(rx, ry-1) == 0: # Space above (Surface check)
					# Check for moisture (OVAL 20x10)
					if current_weather > 0 or _has_tag_within_oval(rx, ry, SandboxMaterial.Tags.LIQUID, 20, 10):
						if randf() < 0.1: # Organic chance
							_set_cell(rx, ry-1, 21) # GROW GRASS
							if i > 5: break

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
		# Reset charge - but IF IT IS ELECTRICITY, give it initial charge to spark!
		if (material_tags_raw[mat_id] & SandboxMaterial.Tags.ELECTRICITY):
			charge_array[idx] = 101
		else:
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
				if mat_id != 28: # Volcan 28 handles its own triple-speed movement
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
		
		# Only spread when charge is at its peak (100) AND emitter is a conductor
		if charge == 100:
			var my_tags = material_tags_raw[cells[i]]
			if (my_tags & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)):
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
		
		# Countdown charge (ONLY for conductors to avoid draining other logic like Vines)
		if (material_tags_raw[cells[i]] & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)):
			charge_array[i] -= 1
			# 101 drops to 100 to spread in the NEXT frame
			if charge_array[i] > 100: charge_array[i] = 100
		elif cells[i] == 19 or cells[i] == 7: # Fuse/Primed logic needs cooldown too
			charge_array[i] -= 1



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

	# --- BIOLOGICAL INTERACTIONS (PLANTS & SEEDS) ---
	# OPTIMIZATION: Only process 5% of biological pixels per frame to save FPS
	if randf() < 0.05:
		# 1. SEED LOGIC (mat_id 20)
		if mat_id == 20: 
			var is_on_fertile = _has_tag_neighbor(x, y, SandboxMaterial.Tags.FERTILE)
			var is_wet = _get_cell(x, y+1) == 22 or _get_cell(x, y+1) == 23 or _has_id_within_oval(x, y, 2, 15, 10) or current_weather > 0
			if is_on_fertile and is_wet:
				_set_cell(x, y, 21) # Transform to Grass
		
		# 2. PLANT GROWTH (mat_id 21 - Grass)
		elif mat_id == 21:
			# STRICT: Must detect water to grow
			if _has_id_within_oval(x, y, 2, 20, 10) or current_weather > 0:
				if randf() < 0.3:
					var gx = x + randi_range(-2, 2)
					var gy = y + randi_range(-2, 1)
					var tid = _get_cell(gx, gy)
					# BALANCE: Spaced out growth (< 4 neighbors)
					if (tid == 0 or tid == 2) and _has_tag_neighbor(gx, gy, SandboxMaterial.Tags.FERTILE):
						if _count_neighbor_id(gx, gy, 21) < 4:
							_set_cell(gx, gy, 21)
	
		# 3. MOISTURE ABSORPTION (ID 1 -> 22, ID 6 -> 23)
		elif mat_id == 1 or mat_id == 6:
			# Spread moisture more horizontally
			if current_weather > 0 or _has_id_within_oval(x, y, 2, 20, 10):
				_set_cell(x, y, 22 if mat_id == 1 else 23) # Transition to wet
		
		# 4. SPONTANEOUS GROWTH ON WET SOIL
		elif mat_id == 22 or mat_id == 23:
			var has_water = _has_id_within_oval(x, y, 2, 15, 10) or current_weather > 0
			if has_water:
				# ROOT LOGIC: Soil only turns to Grass if connected AND NOT crowded (< 3 neighbours)
				if randf() < 0.05 and _has_tag_neighbor(x, y, SandboxMaterial.Tags.PLANT):
					if _count_neighbor_id(x, y, 21) < 3:
						_set_cell(x, y, 21) # Transmute to Grass
				
				# Spontaneous VINE sprout (More frequent, Shorter 4-8px)
				if randf() < 0.15:
					if _get_cell(x, y-1) == 0 and _count_neighbor_id_radius(x, y, 24, 5) < 1:
						_set_cell(x, y-1, 24)
						charge_array[idx - grid_width] = randi_range(4, 8)

				# Or grow upward into space/water (Grass) if connected and not crowded
				if randf() < 0.1:
					var tid = _get_cell(x, y-1)
					if (tid == 0 or tid == 2) and _has_tag_neighbor(x, y, SandboxMaterial.Tags.PLANT):
						if _count_neighbor_id(x, y-1, 21) < 3:
							_set_cell(x, y-1, 21)
			else:
				# Dry out
				if current_weather == 0:
					if randf() < 0.1: _set_cell(x, y, 1 if mat_id == 22 else 6)

		# 5. VINE GROWTH (mat_id 24) - Vertical upward growth
		elif mat_id == 24:
			var h_left = charge_array[idx]
			if h_left > 0 and randf() < 0.3: # Faster growth speed
				var tid_up = _get_cell(x, y-1)
				if (tid_up == 0 or tid_up == 2):
					_set_cell(x, y-1, 24)
					charge_array[idx - grid_width] = h_left - 1 # Pass height gene (4-8)
					charge_array[idx] = 0 # Vine is now "mature"
		
	# 6. VOLCANO LOGIC (mat_id 27, 28, 29)
	if mat_id == 27: # Static block
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY) or charge_array[idx] > 50:
			_set_cell(x, y, 29) # Transform to ACTIVE BASE
			# Life duration for 3-5 shots (Approx 80-120 frames)
			charge_array[idx] = randi_range(80, 120)
	
	elif mat_id == 29: # Erupting Base
		charge_array[idx] -= 1
		# Launch projectile every 20-25 frames
		if charge_array[idx] % 25 == 0:
			var tx = x + randi_range(-1, 1)
			if _get_cell(tx, y-1) == 0 or _get_cell(tx, y-1) == 15:
				_set_cell(tx, y-1, 28)
				charge_array[(y-1) * grid_width + tx] = randi_range(30, 60) # Projectile fuel
		
		# Smoking Base + LAVA PUDDLES (Triple effect)
		if randf() < 0.2:
			if _get_cell(x, y-1) == 0: _set_cell(x, y-1, 15)
		if randf() < 0.15: # Leak real lava at base
			var lx = x + randi_range(-2, 2)
			if _get_cell(lx, y-1) == 0: _set_cell(lx, y-1, 11)
			
		if charge_array[idx] <= 0:
			_draw_circle(x, y, 4, 11) # Burnout cluster
			_explode(x, y, 6)

	elif mat_id == 28: # Ascending projectile
		# FASTER MOVEMENT: Move up 3px per frame manually
		var current_fuel = charge_array[idx]
		
		for i in range(3):
			# Detonate if energy spent
			if current_fuel <= 0:
				_draw_circle(x, y, 6, 11) # Finale: MASSIVE cluster of LAVA (Radius 6)
				_explode(x, y, 10) # Huge Final burst
				return
			
			var next_y = y - 1
			if next_y < 5: # Ceiling safety
				_set_cell(x, y, 11)
				_explode(x, y, 6)
				return
			
			var next_id = _get_cell(x, next_y)
			# Attempt move: Allow passing through Empty, Fire, Elec, Lava, and Smoke
			if next_id == 0 or next_id == 3 or next_id == 9 or next_id == 11 or next_id == 15:
				# 1. First, move the projectile to the new spot
				_swap_cells(x, y, x, next_y)
				
				# 2. Leave trail of ELECTRICITY (9) and FIRE (3) in the OLD spot
				var trail_id = 9 if randf() < 0.6 else 3
				_set_cell(x, y, trail_id)
				
				# 2.5 MASSIVE MAGMA LEAK: Triple lava per move step
				for j in range(3):
					var lx = x + randi_range(-2, 2)
					var ly = y + randi_range(-1, 1)
					if _get_cell(lx, ly) == 0 or _get_cell(lx, ly) == 15:
						_set_cell(lx, ly, 11)
				
				# 3. Update current state to the new position
				y = next_y
				idx = y * grid_width + x
				current_fuel -= 1
				charge_array[idx] = current_fuel
				
				# 4. GHOST SPARKS (Always on top of the grid)
				if randf() < 0.5:
					visual_sparks.append({
						"x": float(x) + randf_range(-4, 4),
						"y": float(y + 2),
						"vx": randf_range(-40, 40),
						"vy": randi_range(30, 70),
						"color": Color.YELLOW if randf() < 0.8 else Color.CYAN,
						"life": randf_range(0.3, 0.6)
					})
			else:
				# Blockage by real solids (Metal, Concrete, Earth)? Stop/Detonate
				current_fuel = 0 # Force detonation
				break

		# Additional Visual Sparks (Cyber-Electric aesthetics)
		if randf() < 0.8:
			var e_colors = [Color.YELLOW, Color.CYAN, Color.WHITE, Color("#FFFF33")]
			for i in range(4):
				visual_sparks.append({
					"x": float(x) + randf_range(-3, 3),
					"y": float(y + 1),
					"vx": randf_range(-50, 50),
					"vy": randf_range(20, 80),
					"color": e_colors[randi() % e_colors.size()],
					"life": randf_range(0.1, 0.4)
				})
	
	# 7. FRESH CEMENT HARDENING (mat_id 25) - Processed every frame for accuracy
	if mat_id == 25:
		if charge_array[idx] == 0:
			charge_array[idx] = randi_range(60, 120) # 1-2 seconds at 60fps
		
		charge_array[idx] -= 1
		if charge_array[idx] <= 1:
			_set_cell(x, y, 26) # Harden to Solid Cement
	
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

	return false

func _has_tag_neighbor(x, y, tag):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var nid = _get_cell(nx, ny)
			if nid > 0:
				if (material_tags_raw[nid] & tag):
					return true
	return false

func _has_tag_within_oval(x, y, tag, rx, ry):
	# Deterministic sweep with step for performance in oval
	for oy in range(-ry, ry + 1, 3): 
		for ox in range(-rx, rx + 1, 3):
			# Oval check: (x^2/rx^2) + (y^2/ry^2) <= 1
			if (float(ox*ox)/(rx*rx) + float(oy*oy)/(ry*ry)) <= 1.0:
				var nid = _get_cell(x + ox, y + oy)
				if nid > 0 and (material_tags_raw[nid] & tag):
					return true
	return false

func _has_id_within_oval(x, y, target_id, rx, ry):
	# Deterministic sweep with step for performance in oval
	for oy in range(-ry, ry + 1, 3): 
		for ox in range(-rx, rx + 1, 3):
			if (float(ox*ox)/(rx*rx) + float(oy*oy)/(ry*ry)) <= 1.0:
				if _get_cell(x + ox, y + oy) == target_id:
					return true
	return false

func _consume_neighbor_tag(x, y, tag):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var nid = _get_cell(nx, ny)
			if nid > 0:
				if (material_tags_raw[nid] & tag):
					_set_cell(nx, ny, 0) # EAT IT
					return true
	return false

func _count_neighbor_id(x, y, id):
	var count = 0
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			if _get_cell(nx, ny) == id:
				count += 1
	return count

func _count_neighbor_id_radius(x, y, id, radius):
	var count = 0
	for ny in range(y - radius, y + radius + 1):
		for nx in range(x - radius, x + radius + 1):
			if nx == x and ny == y: continue
			if _get_cell(nx, ny) == id:
				count += 1
	return count

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
						# Catch fire / Transmute based on producer type
						if randf() < 0.25: # Faster burning/transformation
							if (n_tags & SandboxMaterial.Tags.BURN_COAL):
								_set_cell(nx, ny, 14) # Become Coal
							elif (n_tags & SandboxMaterial.Tags.BURN_SMOKE):
								# Release smoke above if possible
								if _get_cell(nx, ny - 1) == 0:
									_set_cell(nx, ny - 1, 15)
								if randf() < 0.2: _set_cell(nx, ny, 3) # Turn to Fire
								else: _set_cell(nx, ny, 0)
							else:
								_set_cell(nx, ny, 3) # Spread Fire!
					elif (n_tags & SandboxMaterial.Tags.EXPLOSIVE):
						if n_id == 27: # Volcan persistent ignition
							_set_cell(nx, ny, 29)
							charge_array[nx + ny * grid_width] = randi_range(80, 120)
						else:
							_set_cell(nx, ny, 7) # Prime TNT
				else:
					# ONLY Electricity material can start a new pulse in a conductor
					if (n_tags & SandboxMaterial.Tags.CONDUCTOR):
						if charge_array[n_idx] == 0:
							charge_array[n_idx] = 101 # Start pulse
					elif (n_tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED):
						if n_id == 27: # Volcan activates as persistent launcher
							_set_cell(nx, ny, 29)
							charge_array[n_idx] = randi_range(80, 120)
						else:
							_set_cell(nx, ny, 7) # Prime TNT

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
				
				# Chain reaction: TRIGGER nearby launchers
				if (t_tags & SandboxMaterial.Tags.EXPLOSIVE):
					if t_id == 27: # Volcan launcher chain
						_set_cell(tx, ty, 29)
						# Give it ENERGY to launch multiple shots
						charge_array[tx + ty * grid_width] = randi_range(80, 120)
					else:
						_set_cell(tx, ty, 7) # Prime TNT
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
		
		# MIX COLOR IF CHARGED (Glowing effect - ONLY for conductors/electricity)
		if charge > 80 and (material_tags_raw[mat_id] & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRICITY)):
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
func _clear_all():
	cells.fill(0)
	charge_array.fill(0)
	tags_array.fill(0)
	surface_cache.fill(0)
	_update_texture()
	_update_highlights()
