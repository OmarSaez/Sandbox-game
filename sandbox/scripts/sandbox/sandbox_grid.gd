extends Node2D
class_name SandboxGrid

# Grid config
@export var grid_scale: int = 8
var grid_width: int
var grid_height: int
var dynamic_grid_height: int # Logic floor (at HUD top)

# --- CUSTOM NPC COLORS (Editable in Inspector) ---
@export_group("NPC Visuals")
@export var npc_color_acid: Color = Color("#7ae267ff")  # Neon Green
@export var npc_color_fire: Color = Color("#FF4500")  # Orange-Red
@export var npc_color_exp: Color = Color("#FFFFFF")   # White
@export var npc_color_hit: Color = Color("#db2525ff")   # Normal Hit Red
@export var npc_color_death: Color = Color("#5c0000ff") # Dark Agony Red


# Simulation Data
var cells: PackedInt32Array
var tags_array: PackedInt32Array
var color_buffer: PackedByteArray 
var charge_array: PackedByteArray # Track electric pulses (0 = none, 5 = full, counts down)

# GPU Rendering Data (Primary: ID Texture | Secondary: Charge Texture)
var charge_tex: ImageTexture 
var charge_img: Image

# Simulation Chunking
const CHUNK_SIZE = 16
var chunks_active: PackedByteArray 
var next_chunks_active: PackedByteArray
var chunks_x: int
var chunks_y: int

# Pre-calculated visual data
var material_colors_bytes = PackedByteArray() # RGBA bytes for each material

# Material data mapping
var material_colors_raw = PackedColorArray() 
var material_tags_raw = PackedInt32Array() 
var selected_material: int = 1
var current_weather: int = 0 
# UI State
var is_mouse_over_ui: bool = false
var brush_radius: int = 2 
var current_language: String = "es" # "es" or "en"
var ui_scale_level: int = 1 # Start at 1.2x by default
func _get_ui_scale() -> float:
	var scales = [1.0, 1.2, 1.5, 2.0]
	return scales[ui_scale_level]

var ui_elements = {} # To track nodes for re-labeling
var tools_panel: PanelContainer
var disaster_panel: PanelContainer
var npc_panel: PanelContainer
var selected_team: int = 0 
var mouse_was_pressed: bool = false
var active_npcs = [] # Array of dicts: { "pos": Vector2i, "team": int, "dir": int, "type": string, "hp": float, etc }
var active_projectiles = [] # { pos: Vector2, vel: Vector2, team: int, type: string }
var npc_update_timer: float = 0.0
var sfx_pool: Array[AudioStreamPlayer] = []
var next_sfx_idx: int = 0
var brush_player: AudioStreamPlayer # Dedicated for looping placement
var weather_player: AudioStreamPlayer # Dedicated for rain/storm loop
var quake_player: AudioStreamPlayer
var tornado_player: AudioStreamPlayer
var tsunami_player: AudioStreamPlayer
var firework_player: AudioStreamPlayer # Dedicated for rocket fuse
var ascent_player: AudioStreamPlayer   # Dedicated for rocket flying up
var volcano_loop_player: AudioStreamPlayer # Dedicated for volcano bubbling loop
var fire_loop_player: AudioStreamPlayer    # Dedicated for global crackling/burning
const SFX_POOL_SIZE = 8

# Mapeo: ID del Material -> Nombre del archivo (SONIDO EN BUCLE / LOOP) MP3
# Estos sonidos se repiten mientras mantienes el pincel presionado.
var material_sfx = {
	1: "sand",      # Arena
	2: "water",     # Agua
	3: "fire",      # Fuego
	4: "oil",       # Petróleo
	5: "tnt",       # TNT
	6: "earth",     # Tierra
	8: "metal",     # Metal
	9: "elec",      # Electricidad
	10: "gravel",   # Grava
	11: "lava",     # Lava
	12: "obsidian", # Obsidiana
	13: "acid",     # Ácido
	14: "coal",     # Carbón / Brazas (pincel)
	16: "wood",     # Madera
	18: "fireworks",# Cohetes (pincel)
	19: "fuse",      # Cohete encendido (subida)
	20: "seed",     # Semilla
	21: "grass",    # Pasto
	24: "vine",     # Liana
	25: "cem_fresh",# Cemento fresco
	26: "cement",   # Cemento sólido
	27: "volcan_brush", # Pincel del volcán
	29: "volcan_active", # Base activa (burbujeo)
	70: "ice"       # Hielo
}

# Mapeo: Nombre de Acción -> Nombre del archivo (UNA SOLA VEZ / ONE-SHOT) WAV
# Estos sonidos suenan una sola vez cuando ocurre el evento.
var action_sfx = {
	"npc_hit": "hit",             # Cuando un NPC recibe daño
	"npc_death": "death",         # Cuando un NPC muere
	"npc_place": "place_npc",     # Al colocar un NPC en el mapa
	"explosion": "explode",       # Detonación de TNT o Volcán
	"lightning": "lightning",     # Impacto de rayo (clima)
	"earthquake": "quake",        # Inicio de Terremoto
	"tornado": "tornado",         # Inicio de Tornado
	"tsunami": "tsunami",         # Inicio de Tsunami
	"ui_click": "click",          # Al pulsar botones de la interfaz
	"warrior_attack": "sword_swing", # Ataque de Guerrero
	"archer_shoot": "bow_shoot",     # Disparo de Arquero
	"miner_dig": "pickaxe_hit",      # Minero picando tierra
	
	# Sonidos Continuos de Clima / Desastres (LOOP EN TIEMPO REAL) MP3
	"weather_1": "rain_light",
	"weather_2": "rain_med",
	"weather_3": "rain_storm",
	"quake_loop": "quake_loop",
	"tornado_loop": "tornado_loop",
	"firework_launch": "rocket_launch",
	"firework_ascent": "rocket_launch_ascent",
	"firework_burst": "firework_explode", # Sonido de explosión de colores en el aire
	"fuse_burning": "fuse",
	
	# --- SISTEMA SIMPLIFICADO DEL VOLCÁN ---
	"volcan_brush": "volcan",          # (PINCEL) Sonido al dibujar
	"volcan_active": "volcan_bubbles", # (LOOP) Burbujeo constante cuando el volcán funciona
	"volcan_burst": "volcan_explode",   # (ONE-SHOT) Pequeños estallidos de lava
	"burn_loop": "fire_crackle"        # (LOOP) Sonido de cosas quemándose (fuego, lava, carbón)
}

var last_action_times = {} # Para controlar la saturación de sonidos
var is_volcano_active = false 
var is_fire_active = false

var sfx_cache = {} # Cache for loaded AudioStreams

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
		"ui_size": "Tamaño UI",
		"size": "Escala",
		"reset": "Limpiar Todo",
		"npc": "👥 NPCs",
		"warrior": "⚔️ Guerrero",
		"archer": "🏹 Arquero",
		"miner": "⛏️ Minero",
		"team_red": "🔴 Rojo",
		"team_blue": "🔵 Azul",
		"team_yellow": "🟡 Amarillo",
		"team_green": "🟢 Verde",
		"ice": "Hielo"
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
		"cem_fresh": "Fresh Cem.",
		"cement": "Cement",
		"volcan": "Volcano",
		"ui_size": "UI Size",
		"size": "Scale",
		"reset": "Clear All",
		"npc": "👥 NPCs",
		"warrior": "⚔️ Warrior",
		"archer": "🏹 Archer",
		"miner": "⛏️ Miner",
		"team_red": "🔴 Red",
		"team_blue": "🔵 Blue",
		"team_yellow": "🟡 Yellow",
		"team_green": "🟢 Green",
		"ice": "Ice"
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
	# 0. GLOBAL VISUAL STABILITY (Fixes grey margins on Tablets/Modern Devices)
	RenderingServer.set_default_clear_color(Color(0.04, 0.04, 0.04, 1.0))
	
	var global_bg = ColorRect.new()
	global_bg.name = "GlobalBG"
	global_bg.color = Color(0.1, 0.1, 0.12, 1.0) # Dynamic Dark Theme
	global_bg.anchor_right = 1.0
	global_bg.anchor_bottom = 1.0
	global_bg.offset_right = 0
	global_bg.offset_bottom = 0
	get_parent().add_child.call_deferred(global_bg)
	get_parent().move_child.call_deferred(global_bg, 0) # Background Layer
	
	# Setup SFX Pool
	for i in range(SFX_POOL_SIZE):
		var asp = AudioStreamPlayer.new()
		asp.bus = "Master" # You can create a "SFX" bus later
		add_child(asp)
		sfx_pool.append(asp)
	
	# Dedicated Brush Player
	brush_player = AudioStreamPlayer.new()
	brush_player.bus = "Master"
	add_child(brush_player)
	
	# Environmental Players
	weather_player = AudioStreamPlayer.new(); add_child(weather_player)
	quake_player = AudioStreamPlayer.new(); add_child(quake_player)
	tornado_player = AudioStreamPlayer.new(); add_child(tornado_player)
	tsunami_player = AudioStreamPlayer.new(); add_child(tsunami_player)
	firework_player = AudioStreamPlayer.new(); add_child(firework_player)
	ascent_player = AudioStreamPlayer.new(); add_child(ascent_player)
	volcano_loop_player = AudioStreamPlayer.new(); add_child(volcano_loop_player)
	fire_loop_player = AudioStreamPlayer.new(); add_child(fire_loop_player)
	
	# Calculate grid size (Smart Height: Exactly above the UI)
	var viewport_size = get_viewport_rect().size
	
	grid_width = floor(viewport_size.x / grid_scale)
	grid_height = floor(viewport_size.y / grid_scale)
	dynamic_grid_height = grid_height # Full initial
	
	# Update Display node size to match the grid exactly
	$Display.custom_minimum_size = Vector2(grid_width * grid_scale, grid_height * grid_scale)
	$Display.size = $Display.custom_minimum_size
	
	# Init arrays
	cells.resize(grid_width * grid_height)
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	color_buffer.resize(grid_width * grid_height * 4)
	surface_cache.resize(grid_width)
	
	material_colors_bytes.resize(256 * 4)
	material_colors_bytes.fill(0)
	
	chunks_x = ceil(float(grid_width) / CHUNK_SIZE)
	chunks_y = ceil(float(grid_height) / CHUNK_SIZE)
	chunks_active.resize(chunks_x * chunks_y)
	chunks_active.fill(60) # 1s settle for absolute visual stability
	next_chunks_active.resize(chunks_x * chunks_y)
	next_chunks_active.fill(60)
	
	tags_array.resize(grid_width * grid_height)
	charge_array.resize(grid_width * grid_height)
	
	# GPU Image Buffers
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8) # Main ID Texture
	charge_img = Image.create(grid_width, grid_height, false, Image.FORMAT_L8) # Charge (Grayscale)
	
	material_colors_raw.resize(256) # Pre-size for plenty of materials
	material_tags_raw.resize(256)
	
	# Setup materials
	_register_material(0, Color(0, 0, 0, 0), SandboxMaterial.Tags.NONE)
	#Sand
	_register_material(1, Color("FFF9C4"), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_NORMAL)
	#Water
	_register_material(2, Color("80D0FF"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.CONDUCTOR)
	#Fire
	_register_material(3, Color("FCD123"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC)
	# Petroleum (Dark Purple + Flammable)
	_register_material(4, Color("560075"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.BURN_SMOKE)
	
	# TNT (Static + Explosive + Electric Activated)
	_register_material(5, Color("FF0000"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Earth (Slow gravity)
	_register_material(6, Color("#66503D"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW)
	
	# Primed TNT (Flashes white, soon to BOOM)
	_register_material(7, Color.WHITE, SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Metal (Solid + Conductor)
	_register_material(8, Color("EDEDED"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Electricity (Energy!)
	_register_material(9, Color("FFF300"), SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC)
	
	# Gravel (Gray stones)
	_register_material(10, Color("999288"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL)
	
	# Lava (Slow Liquid + Hot)
	_register_material(11, Color("FF8200"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_SLOW)
	
	# Obsidian (Hard Rock + Anti-Acid + Anti-Explosive)
	_register_material(12, Color("1E023B"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_ACID | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	
	# Acid (Neon Green + Melts things + Conductive + SELF-IMMUNE)
	_register_material(13, Color("#39FF14"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.ANTI_ACID)
	
	# Coal (Brazas - Dark Brown/Black)
	_register_material(14, Color("#1A1110"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.INCENDIARY)
	
	# Smoke (Light Gray Gas)
	_register_material(15, Color("454545ff"), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.BURN_NONE)
	
	# Wood (Strong Brown)
	_register_material(16, Color("66380C"), SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.BURN_COAL | SandboxMaterial.Tags.SOLID)
	
	# Cloud (Whity Gray Gas)
	_register_material(17, Color("8C8C8C"), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP)

	# Fuegos Artificiales (Rosa brillante) + Anti-Explosivo para que no se muevan al encenderse la bateria
	_register_material(18, Color("FF7D7D"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	
	# Fill with empty
	cells.fill(0)
	charge_array.fill(0)
	
	# Texture setup
	texture_rect.texture = ImageTexture.create_from_image(img)
	texture_rect.anchor_right = 1.0
	texture_rect.anchor_bottom = 1.0
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	charge_tex = ImageTexture.create_from_image(charge_img)

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
	
	# --- CRYOGENIC SYSTEM ---
	# 60: Ice (Light Cyan Static Solid)
	_register_material(60, Color("#DDF0FF"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC)
	
	# --- VOLCANO SYSTEM ---
	# 27: Volcan (Block) - Neon Orange + Anti-Explosive
	_register_material(27, Color("#FF5F1F"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	# 28: Eruption (Projectile) - Bright Yellow/Orange - Handled manually
	_register_material(28, Color("#FFFF00"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.ANTI_EXPLOSIVE)
	# 29: Active Base (Launcher) - Glowing Orange-Red
	_register_material(29, Color("#FF4500"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE)

	# --- NPC SYSTEM ---
	# 30: Warrior (Dummy/Master)
	_register_material(30, Color.SLATE_GRAY, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 31: NPC Part Gray
	_register_material(31, Color.GRAY, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 32: NPC Part Dark Gray
	_register_material(32, Color(0.2, 0.2, 0.2), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 33: NPC Part Skin
	_register_material(33, Color("#FFDBAC"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 34: Team Red
	_register_material(34, Color.RED, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 35: Team Blue
	_register_material(35, Color.BLUE, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 36: Team Yellow
	_register_material(36, Color.YELLOW, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 37: Team Green
	_register_material(37, Color("#00FF00"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	
	# --- ARCHER SYSTEM ---
	# 40: Archer Master
	_register_material(40, Color("#228B22"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 41: Archer Cloth
	_register_material(41, Color("#8B4513"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 42: Arrow Pixel
	_register_material(42, Color("#D2B48C"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC)
	
	# --- MINER SYSTEM ---
	# 50: Miner Master
	_register_material(50, Color("#555555"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	# 51: Miner Helmet
	_register_material(51, Color("#FFD700"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)

	# --- CUSTOM NPC DAMAGE COLORS (IDs 60-64) ---
	_register_material(60, npc_color_acid, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(61, npc_color_fire, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(62, npc_color_exp, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(63, npc_color_hit, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(64, npc_color_death, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	
	# --- CRYOGENIC SYSTEM ---
	# 70: Ice (Light Cyan Static Solid)
	_register_material(70, Color("#bbe0fcff"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC)


	# UI SETUP (Must happen AFTER materials are registered)
	_setup_main_ui_containers()
	
	# FORCE START HIDDEN
	tools_panel.visible = false
	disaster_panel.visible = false
	if npc_panel: npc_panel.visible = false
	
	_register_material(19, Color(1, 0.8, 0.9), SandboxMaterial.Tags.GRAV_STATIC) # Firework Fuse

	# INITIAL HIGHLIGHT
	_update_highlights()
	
	# FINAL SHADER & PALETTE SYNC (Critical Fix for Black Elements)
	var palette_img = Image.create(256, 1, false, Image.FORMAT_RGBA8)
	palette_img.fill(Color(0,0,0,0))
	for i in range(256):
		palette_img.set_pixel(i, 0, material_colors_raw[i])
	var palette_tex = ImageTexture.create_from_image(palette_img)
	
	var shader = load("res://scripts/sandbox/sandbox_render.gdshader")
	var s_mat = ShaderMaterial.new()
	s_mat.shader = shader
	s_mat.set_shader_parameter("palette_tex", palette_tex)
	s_mat.set_shader_parameter("charge_tex", charge_tex) # Dedicated link
	texture_rect.material = s_mat

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
	_add_button("ice", 70)
	
	# FIND the scroll vbox to add the final spacer
	var s = _get_ui_scale()
	var scroll_vbox = material_grid.get_parent()
	if scroll_vbox and scroll_vbox.name == "ScrollVBox":
		var spacer = Control.new()
		spacer.name = "FinalSpacer"
		spacer.custom_minimum_size = Vector2(0, 15 * s) # TIGHT PADDING (Enough to see labels)
		scroll_vbox.add_child(spacer)


func _setup_ui():
	_setup_tools_ui() # Tools on top
	_setup_npc_ui() # NPCs in the middle
	_setup_disaster_ui() # Disasters below

var material_grid: HFlowContainer
var action_vbox: VBoxContainer

var material_scroll: ScrollContainer

func _setup_main_ui_containers():
	var s = _get_ui_scale()
	var ui_root = get_parent().get_node("UI")
	var main_controls = ui_root.get_node("Controls")
	
	# 1. CAPTURE VISIBILITY (Fixes auto-open and lost state bugs)
	var tools_v = is_instance_valid(tools_panel) and tools_panel.visible
	var disaster_v = is_instance_valid(disaster_panel) and disaster_panel.visible
	var npc_v = is_instance_valid(npc_panel) and npc_panel.visible
	
	# 2. PURGE OLD UI CLONES & ACTION NODES
	ui_elements.clear()
	for child in ui_root.get_children():
		if child.name.begins_with("ToolsPanel") or child.name.begins_with("DisasterPanel") or child.name.begins_with("NPCPanel"):
			child.get_parent().remove_child(child)
			child.queue_free()
			
	for child in main_controls.get_children():
		if child.name == "ActionScroll" or child.name.begins_with("ActionButtons"):
			child.get_parent().remove_child(child)
			child.queue_free()
	
	# 2. FIND MaterialGrid (Wherever it is)
	if not material_grid:
		material_grid = main_controls.find_child("MaterialGrid", true, false)
	
	if not material_grid: return
		
	# 3. FIND OR WRAP in Scroll
	var existing_scroll = main_controls.find_child("MaterialScroll", true, false)
	var scroll_vbox: VBoxContainer
	
	if existing_scroll:
		material_scroll = existing_scroll
		scroll_vbox = material_scroll.find_child("ScrollVBox", true, false)
	else:
		# FIRST TIME WRAPPING
		var parent = material_grid.get_parent()
		var idx = material_grid.get_index()
		
		# CLONE original layout
		var orig_anchors = [material_grid.anchor_left, material_grid.anchor_top, material_grid.anchor_right, material_grid.anchor_bottom]
		var orig_offsets = [material_grid.offset_left, material_grid.offset_top, material_grid.offset_right, material_grid.offset_bottom]
		
		parent.remove_child(material_grid)
		
		material_scroll = ScrollContainer.new()
		material_scroll.name = "MaterialScroll"
		material_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		material_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		material_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# NEW: Use a VBox inside scroll to force vertical padding
		scroll_vbox = VBoxContainer.new()
		scroll_vbox.name = "ScrollVBox"
		scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# APPLY CLONED LAYOUT
		material_scroll.anchor_left = orig_anchors[0]
		material_scroll.anchor_top = orig_anchors[1]
		material_scroll.anchor_right = orig_anchors[2]
		material_scroll.anchor_bottom = orig_anchors[3]
		material_scroll.offset_left = orig_offsets[0]
		material_scroll.offset_top = orig_offsets[1]
		material_scroll.offset_right = orig_offsets[2]
		material_scroll.offset_bottom = orig_offsets[3]

		parent.add_child(material_scroll)
		parent.move_child(material_scroll, idx)
		material_scroll.add_child(scroll_vbox)
		scroll_vbox.add_child(material_grid)
		
		material_scroll.mouse_entered.connect(func(): is_mouse_over_ui = true)
		material_scroll.mouse_exited.connect(func(): is_mouse_over_ui = false)
		material_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ALWAYS Refresh Scroll Height for the current scale
	# NEW: LARGER TALL HUD with logical CAP (max 210px) 
	var h = min(185 * s, 210)
	
	# UPDATE PHYSICAL BOUNDARY
	dynamic_grid_height = grid_height - ceil(h / grid_scale)
	
	material_scroll.custom_minimum_size = Vector2(0, h)
	material_scroll.anchor_top = 1.0
	material_scroll.anchor_bottom = 1.0
	material_scroll.anchor_left = 0
	material_scroll.anchor_right = 1.0
	
	material_scroll.offset_top = -h
	material_scroll.offset_bottom = 0
	material_scroll.offset_left = 0
	material_scroll.offset_right = -175 * s # Leave space for ActionButtons

	# PUSH GAME VIEW (TextureRect) ABOVE HUD
	if not is_instance_valid(texture_rect): 
		texture_rect = get_node_or_null("/root/SandboxMain/TextureRect")
		
	if texture_rect:
		texture_rect.anchor_top = 0
		texture_rect.anchor_bottom = 1.0
		texture_rect.offset_bottom = -h # Align exactly with top of the tall HUD
		texture_rect.offset_top = 0

	# 4. UNIVERSAL HUD FOOTER BACKGROUND (Adaptive Background for any device)
	var footer_bg = main_controls.find_child("HUD_Footer_BG", true, false)
	if is_instance_valid(footer_bg): 
		footer_bg.get_parent().remove_child(footer_bg)
		footer_bg.queue_free()
		
	footer_bg = PanelContainer.new()
	footer_bg.name = "HUD_Footer_BG"
	var foot_style = StyleBoxFlat.new()
	foot_style.bg_color = Color(0.12, 0.12, 0.15, 1.0) # Match Material Slot Dark Grey
	footer_bg.add_theme_stylebox_override("panel", foot_style)
	main_controls.add_child(footer_bg)
	main_controls.move_child(footer_bg, 0) # ALWAYS BEHIND MATERIAL/ACTION
	
	footer_bg.anchor_top = 1.0
	footer_bg.anchor_bottom = 1.0
	footer_bg.anchor_left = 0
	footer_bg.anchor_right = 1.0
	footer_bg.offset_top = -h
	footer_bg.offset_bottom = 0
	footer_bg.offset_left = 0
	footer_bg.offset_right = 0
	footer_bg.mouse_filter = Control.MOUSE_FILTER_STOP # Block game world clicks

	# 5. FRESH ACTION ZONE REBUILD (Fixes scroll bugs on scale change)
	var action_scroll = ScrollContainer.new()
	action_scroll.name = "ActionScroll"
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_controls.add_child(action_scroll)
	
	action_vbox = VBoxContainer.new()
	action_vbox.name = "ActionButtons"
	action_scroll.add_child(action_vbox)
		
	# PIN SCROLL to HUD Floor
	action_scroll.anchor_bottom = 1.0
	action_scroll.anchor_top = 1.0
	action_scroll.anchor_left = 1.0
	action_scroll.anchor_right = 1.0
	
	action_scroll.offset_bottom = 0
	action_scroll.offset_top = -h
	action_scroll.offset_left = -170 * s 
	action_scroll.offset_right = 0
	
	action_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_vbox.add_theme_constant_override("separation", 3 * s)
	action_vbox.alignment = BoxContainer.ALIGNMENT_CENTER # FLOAT IN CENTER OF TALL AREA
	action_scroll.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE DRAG
	
	# CLEAN MATERIAL GRID
	if material_grid:
		for child in material_grid.get_children(): 
			if is_instance_valid(child): 
				child.get_parent().remove_child(child)
				child.queue_free()
		material_grid.add_theme_constant_override("h_separation", 10 * s)
		material_grid.add_theme_constant_override("v_separation", 10 * s)

	# 5. CONSTRUCT ALL SUB-UI
	ui_root.set_meta("tools_v", tools_v)
	ui_root.set_meta("disaster_v", disaster_v)
	ui_root.set_meta("npc_v", npc_v)
	
	_setup_tools_ui()
	_setup_disaster_ui()
	_setup_npc_panel_node()
	_setup_npc_ui()         
	
	_setup_materials_within_grid()
	_update_highlights() # Restore selection marks


func _setup_tools_ui():
	var s = _get_ui_scale()
	var ui_root = get_parent().get_node("UI")
	
	var tools_btn = Button.new()
	tools_btn.name = "ToolsBtn"
	tools_btn.custom_minimum_size = Vector2(160 * s, 58 * s) # BEEFY 58px Height for "Better Body"
	tools_btn.add_theme_font_size_override("font_size", 14 * s)
	tools_btn.text = tr[current_language]["tools"]
	ui_elements["tools_btn"] = tools_btn
	tools_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	action_vbox.add_child(tools_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.2, 0.25, 1.0) # SOLID dark blue-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.4, 0.5)
	btn_style.corner_radius_top_left = 5; btn_style.corner_radius_top_right = 5
	btn_style.corner_radius_bottom_left = 5; btn_style.corner_radius_bottom_right = 5
	tools_btn.add_theme_stylebox_override("normal", btn_style)
	tools_btn.add_theme_stylebox_override("hover", btn_style)
	tools_btn.add_theme_stylebox_override("pressed", btn_style)
	
	# CREATE FRESH PANEL WITH STYLE
	tools_panel = PanelContainer.new()
	tools_panel.name = "ToolsPanel"
	ui_root.add_child(tools_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.95) # Near opaque dark blue-grey
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.4, 0.5)
	panel_style.corner_radius_top_left = 10; panel_style.corner_radius_top_right = 10
	tools_panel.add_theme_stylebox_override("panel", panel_style)
	tools_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# RESTORE STATE
	tools_panel.visible = ui_root.get_meta("tools_v", false)
	
	# COMPACT DYNAMIC POSITIONING
	tools_panel.anchor_left = 0.5
	tools_panel.anchor_right = 0.5
	tools_panel.anchor_top = 1.0
	tools_panel.anchor_bottom = 1.0
	
	var panel_width = 530 * s
	var panel_height = 220 * s
	var h = 185 * s # Match the Tall HUD height
	var bottom_gap = h + (5 * s) # Dynamic GAP above HUD floor
	
	tools_panel.offset_left = -panel_width / 2
	tools_panel.offset_right = panel_width / 2
	tools_panel.offset_bottom = -bottom_gap
	tools_panel.offset_top = -bottom_gap - panel_height
	
	# DYNAMIC BOX (NOW INSIDE SCROLL)
	var scroll = ScrollContainer.new()
	scroll.name = "ToolsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_panel.add_child(scroll)
	
	tools_btn.pressed.connect(func(): 
		if is_instance_valid(disaster_panel): disaster_panel.visible = false
		if is_instance_valid(npc_panel): npc_panel.visible = false
		if is_instance_valid(tools_panel): tools_panel.visible = !tools_panel.visible
	)
	
	tools_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	tools_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	var create_row = func(label_key: String, options: Array, callback: Callable):
		var lbl = Label.new()
		lbl.text = tr[current_language][label_key] + ": "
		lbl.add_theme_font_size_override("font_size", 14 * s)
		ui_elements[label_key + "_lbl"] = lbl
		v_box.add_child(lbl)
		
		var flow = HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(flow)
		
		for i in range(options.size()):
			var btn = Button.new()
			btn.text = options[i]
			btn.custom_minimum_size = Vector2(80 * s, 45 * s)
			btn.add_theme_font_size_override("font_size", 14 * s)
			var level = i
			btn.pressed.connect(func(): callback.call(level))
			flow.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = btn 

	# Language Row (First Tool)
	var lang_options = ["Español", "English"]
	create_row.call("lang", lang_options, func(l):
		current_language = "en" if l == 1 else "es"
		_refresh_ui_text()
		_update_highlights()
	)

	# UI SCALE ROW (Now 2nd)
	var scale_labels = [tr[current_language]["size"] + " 1.0", tr[current_language]["size"] + " 1.2", tr[current_language]["size"] + " 1.5", tr[current_language]["size"] + " 2.0"]
	create_row.call("ui_size", scale_labels, func(l): 
		ui_scale_level = l
		ui_root.set_meta("tools_v", true) # Safe persistence
		call_deferred("_setup_main_ui_containers") # DEFERRED: Separation from click event
	)

	# BRUSH SIZE ROW (Now 3rd)
	var brush_sizes = [0, 1, 2, 5, 7, 12]
	var brush_labels = ["1", "3", "5", "10", "15", "25"]
	create_row.call("brush", brush_labels, func(l): 
		brush_radius = brush_sizes[l]
		_update_highlights()
	)
	
	# DIRECT RESET BUTTON (Bottom of Tools)
	var reset_btn = Button.new()
	reset_btn.text = tr[current_language]["reset"]
	reset_btn.custom_minimum_size = Vector2(0, 50 * s) # SCALED
	reset_btn.add_theme_font_size_override("font_size", 16 * s) # SCALED
	reset_btn.pressed.connect(func():
		_clear_all()
	)
	ui_elements["reset_btn"] = reset_btn
	v_box.add_child(reset_btn)

func _setup_disaster_ui():
	var s = _get_ui_scale()
	var disaster_btn = Button.new()
	disaster_btn.name = "DisasterBtn"
	disaster_btn.custom_minimum_size = Vector2(160 * s, 58 * s) # BEEFY 58px Height for "Better Body"
	disaster_btn.add_theme_font_size_override("font_size", 14 * s) # Compact font
	disaster_btn.text = tr[current_language]["disasters"]
	ui_elements["disaster_btn"] = disaster_btn
	disaster_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	action_vbox.add_child(disaster_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.2, 0.2, 1.0) # SOLID dark red-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.5, 0.4, 0.4)
	btn_style.corner_radius_top_left = 5; btn_style.corner_radius_top_right = 5
	btn_style.corner_radius_bottom_left = 5; btn_style.corner_radius_bottom_right = 5
	disaster_btn.add_theme_stylebox_override("normal", btn_style)
	disaster_btn.add_theme_stylebox_override("hover", btn_style)
	disaster_btn.add_theme_stylebox_override("pressed", btn_style)
	
	# CREATE FRESH PANEL WITH STYLE
	var ui_root = get_parent().get_node("UI")
	disaster_panel = PanelContainer.new()
	disaster_panel.name = "DisasterPanel"
	ui_root.add_child(disaster_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.1, 0.1, 0.95) # Near opaque dark red-grey
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.4, 0.4)
	panel_style.corner_radius_top_left = 10; panel_style.corner_radius_top_right = 10
	disaster_panel.add_theme_stylebox_override("panel", panel_style)
	
	disaster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	disaster_panel.anchor_left = 0.5
	disaster_panel.anchor_right = 0.5
	disaster_panel.anchor_top = 1.0
	disaster_panel.anchor_bottom = 1.0
	
	var d_width = 530 * s
	var d_height = 250 * s
	var h = 185 * s # Match the Tall HUD height
	var d_bottom_gap = h + (5 * s)
	
	disaster_panel.offset_left = -d_width / 2
	disaster_panel.offset_right = d_width / 2
	disaster_panel.offset_bottom = -d_bottom_gap
	disaster_panel.offset_top = -d_bottom_gap - d_height
	# RESTORE STATE
	disaster_panel.visible = ui_root.get_meta("disaster_v", false)
	
	for child in disaster_panel.get_children(): 
		if is_instance_valid(child): child.free() # CLEAR OLD PANEL IMMEDIATELY
		
	var scroll = ScrollContainer.new()
	scroll.name = "DisasterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disaster_panel.add_child(scroll)
	
	disaster_btn.pressed.connect(func(): 
		if is_instance_valid(tools_panel): tools_panel.visible = false
		if is_instance_valid(npc_panel): npc_panel.visible = false
		if is_instance_valid(disaster_panel): disaster_panel.visible = !disaster_panel.visible
	)
	
	disaster_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	disaster_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	var create_row = func(label_key: String, options_keys: Array, callback: Callable):
		var lbl = Label.new()
		lbl.text = tr[current_language][label_key] + ": "
		lbl.add_theme_font_size_override("font_size", 14 * s)
		ui_elements[label_key + "_lbl"] = lbl
		v_box.add_child(lbl)
		
		var flow = HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(flow)
		
		for i in range(options_keys.size()):
			var osk = options_keys[i]
			var btn = Button.new()
			btn.text = tr[current_language][osk]
			btn.custom_minimum_size = Vector2(80 * s, 45 * s)
			btn.add_theme_font_size_override("font_size", 14 * s)
			btn.pressed.connect(func(): callback.call(i))
			flow.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = [btn, osk]

	create_row.call("weather", ["off", "light", "med", "storm"], func(l): 
		current_weather = l
		_update_highlights()
	)
	create_row.call("quake", ["off", "light", "med", "brutal"], func(l): 
		earthquake_intensity = l
		if l > 0: 
			earthquake_timer = randf_range(5.0, 7.0)
			_play_action_sound("earthquake")
		else:
			earthquake_timer = 0 # Reset para apagar sonido e intensidad
		_update_highlights()
	)
	create_row.call("tornado", ["off", "light", "med", "heavy"], func(l):
		tornado_intensity = l
		if l > 0: 
			tornado_timer = 15.0; tornado_x = randf()*grid_width; tornado_target_x = randf()*grid_width
			_play_action_sound("tornado")
		else:
			tornado_timer = 0 # Apagar instantáneamente
		_update_highlights()
	)
	create_row.call("tsunami", ["off", "light", "med", "storm"], func(l):
		tsunami_intensity = l
		if l > 0: 
			tsunami_timer = 15.0; tsunami_wave_x = 0.0
			_play_action_sound("tsunami")
		else:
			tsunami_timer = 0 # Apagar instantáneamente
		_update_highlights()
	)

func _refresh_ui_text():
	var s = _get_ui_scale()
	for key in ui_elements:
		var node_data = ui_elements[key]
		
		# Handle direct button nodes (Tools/Disasters)
		if key == "tools_btn": 
			node_data.text = tr[current_language]["tools"]
			node_data.custom_minimum_size = Vector2(160 * s, 38 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "disaster_btn": 
			node_data.text = tr[current_language]["disasters"]
			node_data.custom_minimum_size = Vector2(160 * s, 38 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "npc_btn": 
			node_data.text = tr[current_language]["npc"]
			node_data.custom_minimum_size = Vector2(160 * s, 38 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "reset_btn": 
			node_data.text = tr[current_language]["reset"]
			node_data.custom_minimum_size = Vector2(0, 38 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "warrior_btn":
			node_data.text = tr[current_language]["warrior"]
			node_data.custom_minimum_size = Vector2(120 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "archer_btn":
			node_data.text = tr[current_language]["archer"]
			node_data.custom_minimum_size = Vector2(120 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "miner_btn":
			node_data.text = tr[current_language]["miner"]
			node_data.custom_minimum_size = Vector2(120 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		
		# Handle Labels (Main labels for rows and material names)
		elif node_data is Label:
			if key.ends_with("_mat_lbl"):
				var pure_key = key.replace("_mat_lbl", "")
				if tr[current_language].has(pure_key):
					node_data.text = tr[current_language][pure_key]
					node_data.add_theme_font_size_override("font_size", 12 * s) # Scale material label font
			elif key.ends_with("_lbl"):
				var pure_key = key.replace("_lbl", "")
				if tr[current_language].has(pure_key):
					node_data.text = tr[current_language][pure_key] + ": "
					node_data.custom_minimum_size = Vector2(120 * s, 0)
					node_data.add_theme_font_size_override("font_size", 14 * s)
		
		# Handle Intensity Buttons (Stored as Array [Btn, Key])
		elif node_data is Array:
			var btn = node_data[0]
			var osk = node_data[1]
			btn.text = tr[current_language][osk]
			btn.custom_minimum_size = Vector2(80 * s, 45 * s)
			btn.add_theme_font_size_override("font_size", 14 * s)
		# Handle other buttons in rows (lang, brush, ui_size)
		elif node_data is Button:
			if key.begins_with("lang_btn_") or key.begins_with("brush_btn_"):
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key.begins_with("ui_size_btn_"):
				var idx = int(key.split("_")[-1])
				var scale_labels = [tr[current_language]["size"] + " 1.0", tr[current_language]["size"] + " 1.2", tr[current_language]["size"] + " 1.5", tr[current_language]["size"] + " 2.0"]
				node_data.text = scale_labels[idx]
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key.begins_with("team_btn_"):
				var idx = int(key.split("_")[-1])
				var team_keys = ["team_red", "team_blue", "team_yellow", "team_green"]
				node_data.text = tr[current_language][team_keys[idx]]
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 12 * s)

func _add_button(key: String, mat_id: int):
	var s = _get_ui_scale()
	
	# The master container for the whole slot (Clickable area)
	var slot_pnl = PanelContainer.new()
	var slot_style = StyleBoxEmpty.new() # Invisible but stops mouse
	slot_pnl.add_theme_stylebox_override("panel", slot_style)
	slot_pnl.mouse_filter = Control.MOUSE_FILTER_PASS # PASS: ALLOW SCROLL ON DRAG (MOBILE)
	slot_pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL # LIQUID FILL (JUSTIFY)
	slot_pnl.custom_minimum_size = Vector2(110 * s, 85 * s) 
	
	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 2 * s) # COMPACT SPACE
	main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS # Pass to slot_pnl
	slot_pnl.add_child(main_vbox)
	
	# The Stack Container (Icon base + Selection overlays)
	var stack = Control.new()
	var icon_w = 90 * s
	var icon_h = 46 * s
	stack.custom_minimum_size = Vector2(icon_w, icon_h)
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	main_vbox.add_child(stack)
	
	# 1. ICON LAYER (Always visible material color)
	var icon_panel = PanelContainer.new()
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = material_colors_raw[mat_id]
	var radius = int(8 * s)
	icon_style.corner_radius_top_left = radius
	icon_style.corner_radius_top_right = radius
	icon_style.corner_radius_bottom_left = radius
	icon_style.corner_radius_bottom_right = radius
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	icon_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(icon_panel)
	
	# 2. SELECTION OVERLAY (Only visible when selected)
	var selection_overlay = PanelContainer.new()
	var sel_style = StyleBoxFlat.new()
	sel_style.draw_center = false # TRANSPARENT CENTER (On Top)
	sel_style.corner_radius_top_left = radius
	sel_style.corner_radius_top_right = radius
	sel_style.corner_radius_bottom_left = radius
	sel_style.corner_radius_bottom_right = radius
	
	selection_overlay.add_theme_stylebox_override("panel", sel_style)
	selection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_overlay.visible = false # Managed by _update_highlights
	stack.add_child(selection_overlay)
	
	var btn_lbl = Label.new()
	btn_lbl.name = "MatLabel"
	btn_lbl.text = tr[current_language][key]
	btn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	btn_lbl.add_theme_font_size_override("font_size", 18 * s) # EVEN LARGER TEXT
	main_vbox.add_child(btn_lbl)
	
	# CENTRALIZED INPUT (Whole slot)
	slot_pnl.gui_input.connect(func(event):
		if not is_instance_valid(event) or not is_instance_valid(slot_pnl): return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			selected_material = mat_id
			_update_highlights()
	)
	slot_pnl.set_meta("mat_id", mat_id)
	
	ui_elements[key + "_icon_pnl"] = selection_overlay # Store overlay for highlight
	ui_elements[key + "_mat_lbl"] = btn_lbl
	
	material_grid.add_child(slot_pnl)
	
	main_vbox.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _update_highlights():
	# Update Material Selection (Icons & Labels)
	for slot in material_grid.get_children():
		if not is_instance_valid(slot): continue
		
		var mat_id = slot.get_meta("mat_id", -1)
		var main_vbox = slot.get_child(0)
		var stack = main_vbox.get_child(0)
		var overlay = stack.get_child(1) # Selection Overlay
		var label = main_vbox.get_child(1)
		
		if mat_id == selected_material:
			overlay.visible = true
			var sel_style = overlay.get_theme_stylebox("panel").duplicate()
			
			# DOUBLE BORDER ON TOP: Black shadow/outer + White inner
			sel_style.border_width_left = 6
			sel_style.border_width_top = 6
			sel_style.border_width_right = 6
			sel_style.border_width_bottom = 6
			sel_style.border_color = Color.WHITE
			
			# Draw the 6px BLACK border behind the white via shadow (solid sharp)
			sel_style.shadow_color = Color.BLACK
			sel_style.shadow_size = 6
			
			overlay.add_theme_stylebox_override("panel", sel_style)
			label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			overlay.visible = false
			label.remove_theme_color_override("font_color")

	# 2. Update Tool/Disaster/NPC Highlights (Buttons)
	for key in ui_elements:
		var node_data = ui_elements[key]
		if key.contains("_btn"):
			var btn = node_data
			if node_data is Array: btn = node_data[0]
			
			if is_instance_valid(btn) and btn is Button:
				# Check if this button is the active one
				var is_active = false
				if key.begins_with("brush_btn_"):
					var idx = int(key.split("_")[-1])
					var brush_sizes = [0, 1, 2, 5, 7, 12]
					if brush_sizes[idx] == brush_radius: is_active = true
				elif key.begins_with("lang_btn_"):
					var idx = int(key.split("_")[-1])
					if (idx == 1 and current_language == "en") or (idx == 0 and current_language == "es"): is_active = true
				elif key.begins_with("ui_size_btn_"):
					var idx = int(key.split("_")[-1])
					if idx == ui_scale_level: is_active = true
				elif key.begins_with("weather_btn_"):
					if int(key.split("_")[-1]) == current_weather: is_active = true
				elif key.begins_with("quake_btn_"):
					if int(key.split("_")[-1]) == earthquake_intensity: is_active = true
				elif key.begins_with("tornado_btn_"):
					if int(key.split("_")[-1]) == tornado_intensity: is_active = true
				elif key.begins_with("tsunami_btn_"):
					if int(key.split("_")[-1]) == tsunami_intensity: is_active = true
				elif key == "warrior_btn":
					if selected_material == 30: is_active = true
				elif key == "archer_btn":
					if selected_material == 40: is_active = true
				elif key == "miner_btn":
					if selected_material == 50: is_active = true
				elif key.begins_with("team_btn_"):
					var idx = int(key.split("_")[-1])
					if idx == selected_team: is_active = true
				
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
	if npc_panel and npc_panel.visible and npc_panel.get_global_rect().has_point(m_pos):
		return true
	if material_scroll and material_scroll.get_global_rect().has_point(m_pos):
		return true
	if action_vbox and action_vbox.get_global_rect().has_point(m_pos):
		return true
		
	return false

func _register_material(id, color, tags):
	material_colors_raw[id] = color
	material_tags_raw[id] = tags
	
	# Pre-calculate bytes for the fast loop
	var base = id * 4
	material_colors_bytes[base] = int(color.r * 255)
	material_colors_bytes[base + 1] = int(color.g * 255)
	material_colors_bytes[base + 2] = int(color.b * 255)
	material_colors_bytes[base + 3] = int(color.a * 255)

# --- SFX SYSTEM ---
func _get_sfx_stream(sfx_name: String) -> AudioStream:
	if sfx_cache.has(sfx_name):
		return sfx_cache[sfx_name]
	
	var extensions = [".ogg", ".mp3", ".wav"]
	for ext in extensions:
		var path = "res://assets/audio/sfx/" + sfx_name + ext
		if FileAccess.file_exists(path):
			var stream = load(path)
			# Ensure it loops if it's a placement sound (Logic handled in _manage_brush_sound)
			sfx_cache[sfx_name] = stream
			return stream
	return null

func _play_sfx(sfx_name: String):
	if sfx_name == "": return
	
	var stream = _get_sfx_stream(sfx_name)
	if not stream: return

	# Force loop OFF for general one-shots from pool
	if "loop" in stream: stream.loop = false 

	# Play using next available player in pool
	var player = sfx_pool[next_sfx_idx]
	player.stream = stream
	player.play()
	
	next_sfx_idx = (next_sfx_idx + 1) % SFX_POOL_SIZE

func _manage_brush_sound(id: int):
	# Si no hay ID, es un NPC o está sobre la UI -> DETENER SONIDO
	if id == -1 or (material_tags_raw[id] & SandboxMaterial.Tags.NPC):
		if brush_player.playing: brush_player.stop()
		return
	
	if material_sfx.has(id):
		_manage_looping_player(brush_player, material_sfx[id])
	else:
		if brush_player.playing: brush_player.stop()

func _manage_looping_player(player: AudioStreamPlayer, key: String):
	# Resolve filename from action_sfx dictionary if it exists
	var sfx_name = key
	if action_sfx.has(key):
		sfx_name = action_sfx[key]
		
	var stream = _get_sfx_stream(sfx_name)
	if stream:
		# Asegurar que el LOOP esté activado
		if "loop" in stream: stream.loop = true
		if "loop_mode" in stream: stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		
		if player.stream != stream:
			player.stream = stream
			player.play()
		elif not player.playing:
			player.play()
	else:
		if player.playing: player.stop()

func _play_material_sound(id: int):
	if material_sfx.has(id):
		_play_sfx(material_sfx[id])

func _play_action_sound(action: String, min_interval: float = 0.08):
	if action_sfx.has(action):
		# Sistema de seguridad contra saturación: 
		# No permite que la MISMA acción suene repetidamente en menos de min_interval segundos
		var now = Time.get_ticks_msec() / 1000.0
		if last_action_times.has(action):
			if now - last_action_times[action] < min_interval:
				return
		
		last_action_times[action] = now
		_play_sfx(action_sfx[action])

func _process(delta):
	# Handle input with robust UI blocking
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _is_any_ui_blocking():
		var m_pos = get_local_mouse_position()
		var gx = int(m_pos.x / grid_scale)
		var gy = int(m_pos.y / grid_scale)
		
		# NPC Special placement: only place on initial click
		if (material_tags_raw[selected_material] & SandboxMaterial.Tags.NPC):
			if not mouse_was_pressed:
				_place_npc(gx, gy)
				_play_action_sound("npc_place")
			_manage_brush_sound(-1) # Stop brush if switching to NPC
		else:
			_manage_brush_sound(selected_material)
			_draw_circle(gx, gy, brush_radius, selected_material)
		mouse_was_pressed = true
	else:
		mouse_was_pressed = false
		_manage_brush_sound(-1) # Stop sound when finger lifted

	# Simulation
	_step_simulation()
	
	# NPC AI & Physics
	_process_npcs(delta)
	
	# Projectiles (Arrows)
	_process_projectiles(delta)
	
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
		if tsunami_player.playing: tsunami_player.stop()
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
		if tornado_player.playing: tornado_player.stop()
		return
	
	tornado_timer -= delta
	
	# Play sound loop while tornado is active
	_manage_looping_player(tornado_player, "tornado_loop")
	
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
		earthquake_intensity = 0
		if quake_player.playing: quake_player.stop()
		return
	
	earthquake_timer -= delta
	
	# Play sound loop while earthquake is active
	_manage_looping_player(quake_player, "quake_loop")
	
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
	if current_weather == 0: 
		if weather_player.playing: weather_player.stop()
		return
	
	# Manage weather sound loop (rain_light, rain_med, rain_storm)
	var w_key = "weather_" + str(current_weather)
	_manage_looping_player(weather_player, w_key)
	
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
	_play_action_sound("lightning")
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
		
		# Wake up simulation
		_activate_chunk(x, y)
		
		# Reset charge - but IF IT IS ELECTRICITY, give it initial charge to spark!
		if (material_tags_raw[mat_id] & SandboxMaterial.Tags.ELECTRICITY):
			charge_array[idx] = 101
		else:
			charge_array[idx] = 0
			
func _activate_chunk(gx, gy):
	var cx = int(gx / CHUNK_SIZE)
	var cy = int(gy / CHUNK_SIZE)
	if cx >= 0 and cx < chunks_x and cy >= 0 and cy < chunks_y:
		var c_idx = cy * chunks_x + cx
		# PERFORMANCE OPTIMIZATION: Skip redundant wakeups
		if next_chunks_active[c_idx] >= 60: return
		next_chunks_active[c_idx] = 60
		# Wake neighbors
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var ncx = cx + ox
				var ncy = cy + oy
				if ncx >= 0 and ncx < chunks_x and ncy >= 0 and ncy < chunks_y:
					next_chunks_active[ncy * chunks_x + ncx] = 60

func _get_cell(x, y):
	if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
		return cells[y * grid_width + x]
	return -1

func _step_simulation():
	# Reset flags de sonidos ambientales
	is_volcano_active = false
	is_fire_active = false
	
	# Update active chunk countdowns
	chunks_active = next_chunks_active.duplicate()
	for i in range(next_chunks_active.size()):
		if next_chunks_active[i] > 0:
			next_chunks_active[i] -= 1
	
	# Pass 1: Electricity Pulse Processing (GLOBAL)
	_process_electricity()
	
	# Pass 2 & 3: Movement and Interactions (Calculated)
	# ... after main loops conclude, manage the persistent sounds once ...
	
	# Pass 2: RISING and SPECIAL particles (Top-to-Bottom by Active Chunks)
	for cy in range(chunks_y):
		for cx in range(chunks_x):
			var c_idx = cy * chunks_x + cx
			if chunks_active[c_idx] == 0: continue
			
			var x_start = cx * CHUNK_SIZE
			var y_start = cy * CHUNK_SIZE
			var x_end = min(x_start + CHUNK_SIZE, grid_width)
			var y_end = min(y_start + CHUNK_SIZE, grid_height)
			
			for y in range(y_start, y_end):
				var sweep = range(x_start, x_end)
				if Engine.get_frames_drawn() % 2 == 0: sweep = range(x_end - 1, x_start - 1, -1)
				for x in sweep:
					var idx = y * grid_width + x
					var mat_id = cells[idx]
					if mat_id == 0: continue
					
					var tags = tags_array[idx]
					
					if mat_id == 7: # Primed TNT
						if randf() < 0.05: _explode(x, y, 10)
						_activate_chunk(x, y) # Keep alive
						continue

					if (tags & SandboxMaterial.Tags.GRAV_UP):
						if mat_id != 28: # Volcan
							_move_particle(x, y, mat_id, tags, -1)
						_process_interactions(x, y, idx, mat_id, tags)

	# Pass 3: FALLING/STATIC particles (Bottom-to-Top by Active Chunks)
	for cy in range(chunks_y - 1, -1, -1):
		for cx in range(chunks_x):
			var c_idx = cy * chunks_x + cx
			if chunks_active[c_idx] == 0: continue
			
			var x_start = cx * CHUNK_SIZE
			var y_start = cy * CHUNK_SIZE
			var x_end = min(x_start + CHUNK_SIZE, grid_width)
			var y_end = min(y_start + CHUNK_SIZE, grid_height)
			
			var y = y_end - 1
			while y >= y_start:
				var x_start_row = x_start
				var x_dir = 1
				if Engine.get_frames_drawn() % 2 == 0:
					x_start_row = x_end - 1
					x_dir = -1
				
				var x = x_start_row
				var count = x_end - x_start
				while count > 0:
					var idx = y * grid_width + x
					var mid = cells[idx]
					
					# FASTER INLINE FLOW (Avoid most calls)
					if mid > 0 and mid != 7: # Skip air/primed
						var tags = tags_array[idx]
						if not (tags & SandboxMaterial.Tags.GRAV_UP): 
							if (tags & SandboxMaterial.Tags.GRAV_STATIC): # Stationary but interactive
								_process_interactions(x, y, idx, mid, tags)
							else:
								# GRAVITY INLINED for speed
								var should_move = true
								if (tags & SandboxMaterial.Tags.GRAV_SLOW) and randf() > 0.3:
									should_move = false
								
								if should_move:
									# Basic Move try
									var ny = y + 1
									if ny < dynamic_grid_height:
										var n_idx = ny * grid_width + x
										if cells[n_idx] == 0: # Down
											_swap_cells(x, y, x, ny)
										elif (tags & SandboxMaterial.Tags.LIQUID):
											# Liquis flow side-ways too
											if randf() > 0.5:
												if x < grid_width - 1 and cells[idx + 1] == 0: _swap_cells(x, y, x + 1, y)
												elif x > 0 and cells[idx - 1] == 0: _swap_cells(x, y, x - 1, y)
										elif (tags & SandboxMaterial.Tags.POWDER):
											# Powders move diagonally
											var dx = 1 if randf() > 0.5 else -1
											var nx = x + dx
											if nx >= 0 and nx < grid_width:
												var ni = ny * grid_width + nx
												if cells[ni] == 0: _swap_cells(x, y, nx, ny)

								# Always check interactions (e.g. fire spreading)
								_process_interactions(x, y, idx, mid, tags)
					x += x_dir
					count -= 1
				y -= 1
	
	# === GESTIÓN GLOBAL DE SONIDOS AMBIENTALES ===
	if is_volcano_active: 
		_manage_looping_player(volcano_loop_player, "volcan_active")
	else: 
		if volcano_loop_player.playing: volcano_loop_player.stop()
		
	if is_fire_active:
		_manage_looping_player(fire_loop_player, "burn_loop")
	else:
		if fire_loop_player.playing: fire_loop_player.stop()

func _process_electricity():
	# Sequential processing (Beat Machine Pulse)
	for i in range(cells.size()):
		var charge = charge_array[i]
		if charge == 0: continue
		
		# 1. SYNCHRONIZE NEW PULSE (Fix for propagation death)
		if charge == 101:
			charge_array[i] = 100
			continue
		
		# 2. SPREAD LOGIC (Only if full 100)
		if charge == 100:
			var x = i % grid_width
			var y = i / grid_width
			var mid = cells[i]
			var my_tags = material_tags_raw[mid]
			if (my_tags & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)):
				# Scan neighbors for 0-charge conductors
				for ny in range(y - 1, y + 2):
					if ny < 0 or ny >= grid_height: continue
					for nx in range(x - 1, x + 2):
						if nx < 0 or nx >= grid_width: continue
						if nx == x and ny == y: continue
						var n_idx = ny * grid_width + nx
						var n_id = cells[n_idx]
						if n_id <= 0: continue
						var n_tags = tags_array[n_idx]
						if (n_tags & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)) and charge_array[n_idx] == 0:
							charge_array[n_idx] = 101 # NEW PULSE (Wait 1 frame)
							_activate_chunk(nx, ny)
		
		# 3. DECAY LOGIC (-5 per frame)
		if (material_tags_raw[cells[i]] & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)):
			charge_array[i] -= 5
			if charge_array[i] > 100: charge_array[i] = 100
			if charge_array[i] > 0:
				_activate_chunk(i % grid_width, i / grid_width)
		elif cells[i] == 7: # TNT logic (Leave 19 for main loop)
			charge_array[i] -= 5
			if charge_array[i] > 0:
				_activate_chunk(i % grid_width, i / grid_width)



func _move_particle(x, y, _mat_id, tags, v_dir):
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
	
	# Wake up chunks
	_activate_chunk(x1, y1)
	_activate_chunk(x2, y2)

func _process_interactions(x, y, idx, mat_id, tags):
	# PULSANT ELECTRICAL SOURCE (Wait for previous pulse to clear)
	if mat_id == 9:
		if charge_array[idx] == 0:
			# Automatically start a new single pulse
			charge_array[idx] = 101
		
	# FIRE AND HEAT REACTIONS
	if (tags & SandboxMaterial.Tags.INCENDIARY):
		if mat_id == 3: is_fire_active = true # Sonido solo para el fuego
		# Incendiary materials (Fire 3, Lava 11) extinguish or burn out
		if mat_id == 3:
			if randf() < 0.1: _set_cell(x, y, 0)
		elif mat_id == 14: # Coal burnout (Glowing Brazas)
			is_fire_active = true
			if randf() < 0.002: # 6x Faster (About 3-4s per pixel)
				_set_cell(x, y, 0)
				if _get_cell(x, y - 1) == 0: _set_cell(x, y - 1, 15)
			if randf() < 0.1 and _get_cell(x, y-1) == 0: # 20x more fire
				_set_cell(x, y - 1, 3)
		
		# Spreading fire to neighbors
		_check_neighbors_for_reaction(x, y, true)

	# FLAMMABLE / REACTIVE MATERIALS (Independent of being incendiary themselves)
	
	# Wood (16) or Coal (14) or Fireworks (18) or Petro (4) ignition
	if (tags & SandboxMaterial.Tags.FLAMMABLE) or (tags & SandboxMaterial.Tags.EXPLOSIVE):
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY) or charge_array[idx] > 50:
			if mat_id == 16: # Wood (50/50 Split Brasa vs Consumption)
				if randf() < 0.5: 
					_set_cell(x, y, 14 if randf() < 0.5 else 3)
			elif mat_id == 4: # Petro catches fire
				if randf() < 0.1: _set_cell(x, y, 3)
			
			# GENERIC ELECTRIC ACTIVATED TRIGGER
			elif mat_id == 18: # Special Fireworks Fuse logic (PRIORITY)
				_set_cell(x, y, 19)
				charge_array[idx] = randi_range(20, 70)
			elif (tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED):
				if (tags & SandboxMaterial.Tags.EXPLOSIVE):
					_set_cell(x, y, 7) # PRIME TNT/EXPLOSIVE
					charge_array[idx] = randi_range(30, 60)
	
	# FUSE LOGIC (Standalone Fireworks)
	if mat_id == 19: 
		_manage_looping_player(firework_player, "fuse_burning")
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

	# --- CRYOGENICS (ICE ID 60) ---
	if mat_id == 60:
		# 1. Melt if near heat (Incendiary)
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY):
			if randf() < 0.2:
				_set_cell(x, y, 2) # Become Water
				return
		
		# 2. Freeze adjacent Water (Only 1% per frame for cool slow growth)
		if randf() < 0.05:
			for ny in range(y - 1, y + 2):
				if ny < 0 or ny >= grid_height: continue
				for nx in range(x - 1, x + 2):
					if nx < 0 or nx >= grid_width: continue
					if nx == x and ny == y: continue
					if cells[ny * grid_width + nx] == 2: # WATER
						_set_cell(nx, ny, 60) # FREEZE!
						return

	# --- CRYOGENICS (ICE ID 70) ---
	if mat_id == 70:
		# 1. Thermal Shock / Vaporization
		for ny in range(y - 1, y + 2):
			if ny < 0 or ny >= grid_height: continue
			for nx in range(x - 1, x + 2):
				if nx < 0 or nx >= grid_width: continue
				if nx == x and ny == y: continue
				var n_idx = ny * grid_width + nx
				var n_id = cells[n_idx]
				
				if n_id == 11: # LAVA (Extreme Heat)
					_set_cell(x, y, 17) # Vaporize Ice -> Cloud
					_set_cell(nx, ny, 12) # Cool Lava -> Obsidian
					return
				elif n_id == 3: # FIRE (High Heat)
					_set_cell(x, y, 2) # Melt Ice -> Water
					_set_cell(nx, ny, 15) # Extinguish Fire -> Smoke
					return
				elif n_id == 15 or n_id == 17: # SMOKE/CLOUD (Warm Air)
					if randf() < 0.02: # Slow melting
						_set_cell(x, y, 2) # Melt Ice -> Water
						return
		
		# 2. Freeze adjacent Water (Slow growth)
		if randf() < 0.05:
			for ny in range(y - 1, y + 2):
				if ny < 0 or ny >= grid_height: continue
				for nx in range(x - 1, x + 2):
					if nx < 0 or nx >= grid_width: continue
					if nx == x and ny == y: continue
					if cells[ny * grid_width + nx] == 2: # WATER
						_set_cell(nx, ny, 70) # FREEZE!
						return

	# ELECTRIC SEEDING (Only decay temporary sparks, not persistent liquids/solids like Acid/Metal)
	if (tags & SandboxMaterial.Tags.ELECTRICITY):
		if not (tags & (SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.SOLID)):
			if randf() < 0.7: _set_cell(x, y, 0)

	# --- CORROSION (ACID) ---
	if (tags & SandboxMaterial.Tags.ACID):
		if randf() < 0.4: # Reaction Speed
			for ny in range(y - 1, y + 2):
				for nx in range(x - 1, x + 2):
					if nx == x and ny == y: continue
					var nid = _get_cell(nx, ny)
					if nid > 0:
						var n_tags = material_tags_raw[nid]
						if not (n_tags & SandboxMaterial.Tags.ANTI_ACID):
							# CORROSION: Destroy material and spark ELECTRICITY
							_set_cell(nx, ny, 9) 
							
							# Acid has 30% chance to evaporate upon reaction
							if randf() < 0.3:
								_set_cell(x, y, 0)
								return # Evaporated into gas/nothing
							
							# If eating a SOLID, it's harder work (10% extra consumption)
							if (n_tags & SandboxMaterial.Tags.SOLID) and randf() < 0.1:
								_set_cell(x, y, 0)
								return

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
		is_volcano_active = true
		charge_array[idx] -= 1
		# Launch projectile every 20-25 frames
		if charge_array[idx] % 25 == 0:
			var tx = x + randi_range(-1, 1)
			var n_id = _get_cell(tx, y-1)
			# Launch if NOT a core solid (Metal, Cement, Earth, or another Volcan)
			if n_id != 13 and n_id != 26 and n_id != 5 and n_id != 27:
				_explode(x, y-1, 2, "volcan_burst") # PUSH the plug out of the way!
				_set_cell(tx, y-1, 28)
				charge_array[(y-1) * grid_width + tx] = randi_range(30, 60) # Projectile fuel
		
		# Smoking Base + LAVA PUDDLES (Triple effect)
		if randf() < 0.3: # Reduced from 0.6
			var sx = x + randi_range(-2, 2)
			if _get_cell(sx, y-1) == 0: _set_cell(sx, y-1, 15)
		
		if randf() < 0.15: # Leak real lava at base
			var lx = x + randi_range(-2, 2)
			if _get_cell(lx, y-1) == 0: _set_cell(lx, y-1, 11)
			
		if charge_array[idx] <= 0:
			_draw_circle(x, y, 5, 11) # Burnout cluster (Slightly bigger)
			_explode(x, y, 10, "volcan_burst") # Bigger final burnout

	elif mat_id == 28: # Ascending projectile
		is_volcano_active = true
		# FASTER MOVEMENT: Move up 3px per frame manually
		var current_fuel = charge_array[idx]
		
		for i in range(3):
			# Detonate if energy spent
			if current_fuel <= 0:
				_draw_circle(x, y, 6, 11) # Finale: MASSIVE cluster of LAVA
				_draw_circle(x, y, 5, 15) # Reduced cloud of SMOKE (from 10 to 5)
				_explode(x, y, 12, "volcan_burst") # Huge Final burst
				
				# Finale FIREWORKS: 50+ Bright Sparks
				for j in range(50):
					visual_sparks.append({
						"x": float(x), "y": float(y),
						"vx": randf_range(-120, 120), "vy": randf_range(-150, 50),
						"color": [Color.YELLOW, Color("#FFFF33"), Color.WHITE, Color.ORANGE].pick_random(),
						"life": randf_range(0.4, 0.8)
					})
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
				
				# 2. Leave trail of ELECTRICITY (9), FIRE (3) and SMOKE (15)
				# Reduced smoke probability: (15 if rand < 0.2 instead of 0.4)
				var trail_id = 15 if randf() < 0.2 else (9 if randf() < 0.5 else 3)
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
				
				# 4. GHOST SPARKS (High-Density Electric Aura)
				for j in range(12): # Increased density (12 sparks per sub-step!)
					visual_sparks.append({
						"x": float(x) + randf_range(-6, 6),
						"y": float(y) + randf_range(0, 10),
						"vx": randf_range(-60, 60),
						"vy": randi_range(40, 100),
						"color": [Color.YELLOW, Color("#FFFF33"), Color.WHITE, Color.ORANGE].pick_random(),
						"life": randf_range(0.2, 0.5)
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
		# ... logic existing ...
		pass
	
	# 7. FRESH CEMENT HARDENING (mat_id 25)
	if mat_id == 25:
		if charge_array[idx] == 0:
			charge_array[idx] = randi_range(60, 120) # 1-2 seconds at 60fps
		
		charge_array[idx] -= 1
		if charge_array[idx] <= 1:
			_set_cell(x, y, 26) # Harden to Solid Cement

func _setup_npc_panel_node():
	# If it exists but was lost during a UI refresh, we need to ensure it's in the tree
	var ui_root = get_parent().get_node("UI")
	
	npc_panel = PanelContainer.new()
	npc_panel.name = "NPCPanel"
	ui_root.add_child(npc_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.15, 0.1, 0.95) # Near opaque dark green-grey
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.5, 0.4)
	panel_style.corner_radius_top_left = 10; panel_style.corner_radius_top_right = 10
	npc_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Compact dynamic positioning (Middle menu)
	var s = _get_ui_scale()
	npc_panel.anchor_left = 0.5
	npc_panel.anchor_right = 0.5
	npc_panel.anchor_top = 1.0
	npc_panel.anchor_bottom = 1.0
	
	var p_width = 530 * s
	var p_height = 200 * s
	var h = 185 * s # Match the Tall HUD height
	var bottom_gap = h + (5 * s)
	
	npc_panel.offset_left = -p_width / 2
	npc_panel.offset_right = p_width / 2
	npc_panel.offset_bottom = -bottom_gap
	npc_panel.offset_top = -bottom_gap - p_height
	
	# RESTORE STATE
	npc_panel.visible = ui_root.get_meta("npc_v", false)
	
	# SETUP INTERNAL SCROLL (REPLACEMENT FOR DIRECT VBOX)
	for child in npc_panel.get_children(): 
		if is_instance_valid(child): child.free()
		
	var scroll = ScrollContainer.new()
	scroll.name = "NPCScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_panel.add_child(scroll)
	
	var v_box = VBoxContainer.new()
	v_box.name = "NPCVBox"
	v_box.add_theme_constant_override("separation", 10 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	npc_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	npc_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _setup_npc_ui():
	var s = _get_ui_scale()
	var npc_btn = Button.new()
	npc_btn.name = "NPCBtn"
	npc_btn.custom_minimum_size = Vector2(160 * s, 58 * s) # BEEFY 58px Height for "Better Body"
	npc_btn.add_theme_font_size_override("font_size", 14 * s) # Compact font
	npc_btn.text = tr[current_language]["npc"]
	ui_elements["npc_btn"] = npc_btn
	npc_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	action_vbox.add_child(npc_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.25, 0.2, 1.0) # SOLID dark green-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.5, 0.4)
	btn_style.corner_radius_top_left = 5; btn_style.corner_radius_top_right = 5
	btn_style.corner_radius_bottom_left = 5; btn_style.corner_radius_bottom_right = 5
	npc_btn.add_theme_stylebox_override("normal", btn_style)
	npc_btn.add_theme_stylebox_override("hover", btn_style)
	npc_btn.add_theme_stylebox_override("pressed", btn_style)
	
	npc_btn.pressed.connect(func():
		if is_instance_valid(tools_panel): tools_panel.visible = false
		if is_instance_valid(disaster_panel): disaster_panel.visible = false
		if is_instance_valid(npc_panel): npc_panel.visible = !npc_panel.visible
	)
	
	# Clear and Fill
	if is_instance_valid(npc_panel):
		var scroll = npc_panel.get_child(0) as ScrollContainer
		var v_box = scroll.get_child(0) as VBoxContainer
		for child in v_box.get_children(): 
			if is_instance_valid(child): child.queue_free()
		
		# NPC Selection (NOW RESPONSIVE)
		var npc_lbl = Label.new()
		npc_lbl.text = tr[current_language]["npc"] + ": "
		npc_lbl.add_theme_font_size_override("font_size", 14 * s)
		v_box.add_child(npc_lbl)
		
		var npc_flow = HFlowContainer.new()
		npc_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(npc_flow)
		
		var create_npc_btn = func(key: String, id: int):
			var btn = Button.new()
			btn.text = tr[current_language][key]
			btn.custom_minimum_size = Vector2(100 * s, 45 * s)
			btn.pressed.connect(func():
				selected_material = id # Master Warrior Material
				_update_highlights()
			)
			ui_elements[key + "_btn"] = btn
			npc_flow.add_child(btn)
		
		create_npc_btn.call("warrior", 30)
		create_npc_btn.call("archer", 40)
		create_npc_btn.call("miner", 50)
		
		# Teams Row (NOW RESPONSIVE)
		var team_lbl = Label.new()
		team_lbl.text = "Team: "
		team_lbl.add_theme_font_size_override("font_size", 14 * s)
		v_box.add_child(team_lbl)
		
		var team_flow = HFlowContainer.new()
		team_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(team_flow)
		
		var team_keys = ["team_red", "team_blue", "team_yellow", "team_green"]
		for i in range(4):
			var t_btn = Button.new()
			t_btn.text = tr[current_language][team_keys[i]]
			t_btn.custom_minimum_size = Vector2(80 * s, 45 * s)
			t_btn.add_theme_font_size_override("font_size", 12 * s)
			var tidx = i
			t_btn.pressed.connect(func():
				selected_team = tidx
				_update_highlights()
			)
			ui_elements["team_btn_" + str(i)] = t_btn
			team_flow.add_child(t_btn)

func _place_npc(x, y):
	var start_x = x - 1
	var start_y = y - 4
	
	var n_type = "warrior"
	if selected_material == 40 or selected_material == 41: n_type = "archer"
	elif selected_material == 50 or selected_material == 51: n_type = "miner"
	
	# Register in entity list
	var new_npc = {
		"pos": Vector2i(start_x, start_y),
		"team": selected_team,
		"dir": 1 if randf() > 0.5 else -1,
		"type": n_type,
		"hp": 100.0,
		"attack_cooldown": 0.0,
		"hit_flash": 0,
		"hit_type": "none",
		"dig_timer": 0.0,
		"spawn_y": start_y,
		"mine_state": "ramp",
		"state_steps": 25,
		"fall_depth": 0, # Track for acrobat flips
		"last_dig_time": 0,
		"miss_counter": 0 # For Archer tactical repositioning
	}
	active_npcs.append(new_npc)
	
	# Initial draw
	_draw_npc_pixels(new_npc)

func _draw_npc_pixels(npc, override_mat = -1):
	var sx = npc.pos.x
	var sy = npc.pos.y
	
	# --- ROBUST CLEARING (4x7 scan area to catch shake/vfx leftovers) ---
	if override_mat == 0:
		for oy in range(-1, 7):
			for ox in range(-1, 3):
				var tx = sx + ox; var ty = sy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var tid = cells[ty * grid_width + tx]
					# ONLY clear if it belongs to the NPC system to avoid eating terrain
					if tid > 0 and (material_tags_raw[tid] & SandboxMaterial.Tags.NPC):
						_set_cell(tx, ty, 0)
		return

	
	var is_dead = npc.hp <= 0
	var is_flashing = npc.hit_flash > 0
	
	# --- POLISH: SHAKE & TOPPLE EFFECTS ---
	if is_flashing and not is_dead:
		# NPCs vibrate when taking damage
		sx += randi_range(-1, 1)
		sy += randi_range(-1, 1)
	elif is_dead:
		# NPCs "fall over" slightly and sink when dead
		sy += 2 
		sx += 1 if (npc.dir > 0) else -1
		# Flicker effect (Red / Clear)
		if (npc.hit_flash % 2 == 0): override_mat = 0 # Don't draw on some frames
	
	var team_mat = 34 + npc.team
	
	var is_archer = npc.type == "archer"
	var is_miner = npc.type == "miner"
	
	var m_head = (41 if is_archer else (50 if is_miner else 31)) if override_mat == -1 else override_mat
	var m_skin = 33 if override_mat == -1 else override_mat
	var m_body = (40 if is_archer else (50 if is_miner else 32)) if override_mat == -1 else override_mat
	var m_legs = (50 if is_miner else 31) if override_mat == -1 else override_mat
	var m_team = team_mat if override_mat == -1 else override_mat
	var m_helmet = 51 if override_mat == -1 else override_mat
	
	# Override for hit flash (More vibrant colors)
	if is_flashing and override_mat == -1:
		var f_mat = 62 # Default to White (Exp slot)
		if is_dead: f_mat = 64 # Death Color Slot
		elif npc.hit_type == "acid": f_mat = 60 # Acid Slot
		elif npc.hit_type == "fire": f_mat = 61 # Fire Slot
		elif npc.hit_type == "explosive": f_mat = 62 # Exp Slot
		else: f_mat = 63 # Normal Hit Slot
		m_head = f_mat; m_skin = f_mat; m_body = f_mat; m_legs = f_mat; m_team = f_mat; m_helmet = f_mat
	
	# HEAD
	_set_cell(sx, sy, m_head if not is_miner else m_helmet)
	_set_cell(sx+1, sy, m_skin)
	_set_cell(sx, sy+1, m_head)
	_set_cell(sx+1, sy+1, m_head)
	
	# BODY
	_set_cell(sx, sy+2, m_body)
	_set_cell(sx+1, sy+2, m_team)
	_set_cell(sx, sy+3, m_team)
	_set_cell(sx+1, sy+3, m_body)
	
	# LEGS
	_set_cell(sx, sy+4, m_legs)
	_set_cell(sx+1, sy+4, m_legs)

func _process_npcs(delta):
	npc_update_timer += delta
	if npc_update_timer < 0.05: return 
	npc_update_timer = 0.0
	
	var dead_indices = []
	
	for i in range(active_npcs.size()):
		var npc = active_npcs[i]
		if npc.hit_flash > 0: 
			npc.hit_flash -= 1
			if npc.hit_flash == 0: npc.hit_type = "none" # Clear damage state when flash ends
		
		# 0. PRE-PROCESS: Clear pixels so they don't block their own environmental checks
		_draw_npc_pixels(npc, 0)
		
		# 1. Damage from Environment
		if _check_npc_environment_damage(npc):
			if npc.hp <= 0:
				# Red death animation handled at bottom
				pass
		
		# 2. Store old position and data for AI/Physics
		var np = npc.pos
		
		# 2. AI: TARGET SELECTION & BEHAVIOR
		if npc.attack_cooldown > 0: npc.attack_cooldown -= 0.05
		var target = _find_closest_enemy(npc, 250.0) # Larger radar (250px)
		var is_attacking = false
		
		# DEFAULT PATROL (If no target, keep moving to explore)
		if !target and npc.type != "miner":
			if Engine.get_frames_drawn() % 120 == 0: npc.dir = 1 if randf() > 0.5 else -1
			if npc.dir == 0: npc.dir = 1
			
		if target and npc.type != "miner":
			var dist_x = target.pos.x - np.x
			var dx_abs = abs(dist_x)
			var dy_abs = abs(target.pos.y - np.y)
			
			if npc.type == "warrior":
				var target_below = target.pos.y > np.y + 8
				
				# GLOBAL SWEEP: If target is below, walk SIDE-TO-SIDE until ledge found
				if target_below:
					if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
				else:
					npc.dir = 1 if dist_x > 0 else -1
				
				if dx_abs < 6 and dy_abs < 6:
					is_attacking = true
					if npc.attack_cooldown <= 0:
						_attack_npc(npc, target)
						npc.attack_cooldown = 0.6
				
				# Stop ONLY if on same level AND close in X
				if dx_abs < 4 and !target_below: npc.dir = 0 
			elif npc.type == "archer":
				var target_below = target.pos.y > np.y + 12
				
				# REPOSITION MODE: If frustrated (miss_counter < 0), force horizontal move
				if npc.miss_counter < 0:
					npc.miss_counter += 1
					if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
				else:
					if dx_abs > 120: npc.dir = 1 if dist_x > 0 else -1
					elif dx_abs < 50:
						npc.dir = -1 if dist_x > 0 else 1
					else:
						# GLOBAL HUNT: Walk until hole or ledge
						if target_below:
							if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
						else:
							npc.dir = 0
				
				is_attacking = true
				if npc.attack_cooldown <= 0:
					_shoot_arrow(npc, target)
					npc.miss_counter += 1
					if npc.miss_counter >= 3: npc.miss_counter = -40 # Reposition for 40 ticks
					npc.attack_cooldown = 1.1 if dx_abs > 50 else 1.5
		
		# 3. MINER AI
		if npc.type == "miner":
			var dig_speed = 0.05
			if npc.hit_flash > 0: 
				dig_speed = 0.15 # PANIC DIGGING (3x Speed)
				if npc.hit_flash == 5: npc.dir = -npc.dir # Escape manure!
				
			npc.dig_timer += dig_speed
			if npc.dig_timer >= 0.15:
				npc.dig_timer = 0.0
				if !_can_npc_fit(np.x, np.y + 1): # Grounded
					npc.state_steps -= 1
					var is_underground = _get_cell(np.x, np.y - 4) != 0
					if not is_underground and npc.mine_state == "gallery":
						npc.mine_state = "ramp"; npc.state_steps = 25
						
					if npc.state_steps <= 0:
						if npc.mine_state == "ramp":
							npc.mine_state = "gallery"
							npc.state_steps = randi_range(60, 100)
						else:
							npc.mine_state = "ramp"
							npc.state_steps = randi_range(15, 25)
					
					var dig_down = (npc.mine_state == "ramp")
					_miner_dig(npc, dig_down)
					
					var next_x = np.x + npc.dir
					var next_y = np.y + (1 if dig_down else 0)
					
					if next_x < 5 or next_x > grid_width - 5:
						npc.dir = -npc.dir
					elif next_y >= dynamic_grid_height - 10:
						if npc.hp > 0: # Only trigger death once to allow animation to finish
							npc.hp = 0
							npc.hit_flash = 10 # 0.5s of red before dying

					elif _can_npc_fit(next_x, next_y):
						np.x = next_x ; np.y = next_y
					elif !dig_down and _can_npc_fit(next_x, np.y - 1):
						np.x = next_x ; np.y -= 1 # Step up
					else:
						npc.dir = -npc.dir
		
		# 4. PHYSICS & MOVEMENT (Gravity)
		if _can_npc_fit(np.x, np.y + 1, npc.team):
			np.y += 1 # Standard Gravity
			npc.fall_depth += 1
		elif npc.type != "miner": # Warriors/Archers climbing logic
			# BOUNCE EXPLORATION: Flip direction if landed from height
			if npc.fall_depth >= 3:
				npc.dir = -npc.dir
			npc.fall_depth = 0
			
			if npc.dir != 0:
				var tx = np.x + (npc.dir * 2) # FORWARD LUNGE CHECK (2px)
				var moved = false
				
				# TACTICAL JUMP: If target is above, always try to jump/catch ledges
				var target_above = target and target.pos.y < np.y - 12
				
				# 10px VERTICAL RAYCAST (Smart Climbing)
				# Scan upwards to see if it can step up or climb
				for dy in range(0, -11, -1):
					if _can_npc_fit(tx, np.y + dy, npc.team):
						# If target is above, only move if we are actually GOING UP
						if !target_above or dy < 0:
							np.x = tx; np.y += dy
							moved = true; break
				
				# IF TARGET IS ABOVE and we are NOT moving yet, try harder to jump
				if !moved and target_above:
					# Try a straight upward leap scan
					for dy in range(-1, -11, -1):
						if _can_npc_fit(np.x, np.y + dy, npc.team):
							np.y += dy; moved = true; break
				
				# GAP JUMP & LUNGE: If simple climb fails, try jumping over gaps
				if not moved:
					var std_tx = np.x + npc.dir # Fallback to 1px step
					if _can_npc_fit(std_tx, np.y, npc.team): # Horizontal Gap Jump
						np.x = std_tx; moved = true
					elif _can_npc_fit(std_tx, np.y - 4, npc.team): # Lunge onto ramp
						np.x = std_tx; np.y -= 4; moved = true
				
				# WALL REBOUND: If blocked by something > 8px
				if not moved and !target_above: # Only rebound if not actively trying to jump up
					if !is_attacking: npc.dir = -npc.dir
		
		# 5. FINAL RENDER: Redraw at the new position
		npc.pos = np
		_draw_npc_pixels(npc)
			
		if npc.hp <= 0 and npc.hit_flash <= 0:
			_draw_npc_pixels(npc, 0)
			_play_action_sound("npc_death")
			dead_indices.append(i)

	dead_indices.sort(); dead_indices.reverse()
	for idx in dead_indices: active_npcs.remove_at(idx)
	
	# 6. REPAIR PASS: Redraw all NPCs to fix erasures from neighbor wide-clearing
	# This ensures everyone is solid and visually complete for the next frame
	for npc in active_npcs:
		_draw_npc_pixels(npc)

func _miner_dig(npc, dig_down=false):
	# Sonar solo una vez cada 3 segundos (3000ms)
	var now = Time.get_ticks_msec()
	if now - npc.last_dig_time >= 3000:
		_play_action_sound("miner_dig")
		npc.last_dig_time = now
		
	var tx = npc.pos.x + (npc.dir * 3) # PUSH WOOD 3px AHEAD to avoid 'tunnel-traps'
	var dy_offset = 1 if dig_down else 0
	
	# Tube height (Same 7px, but wider inner)
	var ty_start = npc.pos.y - 2 + dy_offset
	var ty_end = npc.pos.y + 5 + dy_offset
	
	# 1. PLACE WOOD SUPPORTS (Asymmetric Engineering)
	var beam_len = 3 if dig_down else 6
	
	# CEILING: Proactive (Ahead) and Predictive (Radar Sealing)
	var tx_c = npc.pos.x + (npc.dir * 3)
	for ox in range(0, beam_len):
		var wx = tx_c + (ox * npc.dir)
		if wx < 0 or wx >= grid_width: continue
		if ty_start >= 0:
			# RADAR CHECK: Look ahead 3px to see if mountain is coming
			var mountain_ahead = false
			for rx in range(0, 4):
				var r_check = wx + (rx * npc.dir)
				if r_check >= 0 and r_check < grid_width:
					var look_id = _get_cell(r_check, ty_start)
					if look_id != 0 and look_id != 16:
						mountain_ahead = true; break
			
			if mountain_ahead:
				_set_cell(wx, ty_start, 16)
	
	# FLOOR: Protective (From Behind) to avoid falling
	var tx_f = npc.pos.x - (npc.dir * 2) 
	var f_len = 6 # Extended floor coverage
	for ox in range(0, f_len):
		var wx = tx_f + (ox * npc.dir)
		if wx < 0 or wx >= grid_width: continue
		if ty_end < dynamic_grid_height:
			var tid = _get_cell(wx, ty_end)
			if tid != 16: # Ensure we don't mess with existing supports
				_set_cell(wx, ty_end, 16)
				
	# 2. CLEAR THE PATH (Wider 4px Tunnel for 'Better Air')
	for dx in range(0, 4):
		for dy in range(ty_start + 1, ty_end):
			var cx = npc.pos.x + (dx * npc.dir) # Start clearing from the miner's face
			var cy = dy 
			if cx < 0 or cx >= grid_width or cy < 0 or cy >= dynamic_grid_height: continue
			var tid = _get_cell(cx, cy)
			if tid == 9 or tid == 12: continue
			_set_cell(cx, cy, 0)

func _shoot_arrow(npc, target):
	_play_action_sound("archer_shoot")
	var dx = float(target.pos.x - npc.pos.x)
	var dy = float(target.pos.y - npc.pos.y)
	var dir = 1 if dx > 0 else -1
	
	# TRAJECTORY MATH (Slowed down to 130px for visibility & precision)
	var vx = dir * 130.0 # Horizontal speed (Reduced from 220)
	var t = abs(dx) / 130.0 # Time to travel distance
	if t < 0.05: t = 0.05 # Prevent division by zero
	
	var arrow_gravity = 200.0
	# Formula: dy = vy * t + 0.5 * g * t^2 -> vy = (dy / t) - (0.5 * g * t)
	var vy = (dy / t) - (0.5 * arrow_gravity * t)
	
	# Safety cap for vy
	vy = clamp(vy, -160.0, 40.0) 
	
	active_projectiles.append({
		"pos": Vector2(npc.pos.x + dir*2, npc.pos.y + 1),
		"vel": Vector2(vx, vy),
		"team": npc.team,
		"type": "arrow",
		"life": 2.5
	})

func _process_projectiles(delta):
	var to_remove = []
	for i in range(active_projectiles.size()):
		var p = active_projectiles[i]
		# Erase old (from grid)
		_set_cell(int(p.pos.x), int(p.pos.y), 0)
		
		p.pos += p.vel * delta
		p.vel.y += 200.0 * delta # Gravity for arrow
		p.life -= delta
		
		var gx = int(p.pos.x)
		var gy = int(p.pos.y)
		
		# 1. World Bounds
		if gx < 0 or gx >= grid_width or gy < 0 or gy >= dynamic_grid_height or p.life <= 0:
			to_remove.append(i); continue
			
		# 2. NPC Collision
		var hit_npc = null
		for other in active_npcs:
			if other.team != p.team:
				# 2x5 simple bbox
				if gx >= other.pos.x and gx <= other.pos.x + 1 and gy >= other.pos.y and gy <= other.pos.y + 4:
					hit_npc = other; break
		
		if hit_npc:
			hit_npc.hp -= 40.0 # High damage (3 arrows = kill)
			hit_npc.hit_flash = 4 # Flash
			hit_npc.hit_type = "normal"
			_play_action_sound("npc_hit")
			# Visual sparks on impact
			for j in range(5):
				visual_sparks.append({"x":float(gx),"y":float(gy),"vx":randf_range(-40,40),"vy":randf_range(-40,0),"color":Color.WHITE,"life":0.3})
			to_remove.append(i); continue
			
		# 3. Grid Collision (Solids)
		var tid = _get_cell(gx, gy)
		if tid != 0 and tid != 15 and tid != 3 and tid != 17:
			to_remove.append(i); continue # Stuck in ground
			
		# Draw new
		_set_cell(gx, gy, 42)
	
	to_remove.reverse()
	for idx in to_remove: active_projectiles.remove_at(idx)

func _find_closest_enemy(me, radar_range):
	var closest = null
	var min_dist = radar_range
	for other in active_npcs:
		if other.team != me.team:
			var d = me.pos.distance_to(other.pos)
			if d < min_dist:
				min_dist = d
				closest = other
	return closest

func _attack_npc(attacker, victim):
	victim.hp -= 15.0 # Damage
	victim.hit_flash = 5
	victim.hit_type = "normal"
	_play_action_sound("npc_hit")
	_play_action_sound("warrior_attack")
	
	# 1. TEAM FX (Impact Particles)
	var t_colors = [Color.RED, Color("1E90FF"), Color.YELLOW, Color.GREEN]
	var bleed_color = t_colors[victim.team] if victim.team < t_colors.size() else Color.WHITE
	for i in range(10):
		visual_sparks.append({
			"x": float(victim.pos.x) + randf_range(0, 2),
			"y": float(victim.pos.y) + randf_range(0, 5),
			"vx": randf_range(-80, 80),
			"vy": randf_range(-120, -30),
			"color": bleed_color if randf() > 0.4 else Color.WHITE,
			"life": randf_range(0.3, 0.7)
		})
	
	# 2. AGGRESSIVE LUNGE: Kinetic boost towards victim (3px Turbo)
	var ldir = 1 if attacker.pos.x < victim.pos.x else -1
	for d in range(3, 0, -1):
		var lx = attacker.pos.x + ldir * d
		var ly = attacker.pos.y - 1
		if _can_npc_fit(lx, ly, attacker.team):
			attacker.pos.x = lx
			attacker.pos.y = ly
			break
		
	# 3. POWER KNOCKBACK (35% chance to push victim in parabola)
	if randf() < 0.35:
		var push_dir = 1 if attacker.pos.x < victim.pos.x else -1
		var dist = randi_range(5, 8) # Stronger reach
		# Find furthest possible push spot (Parabolic trajectory)
		for d in range(dist, 0, -1):
			var new_x = victim.pos.x + push_dir * d
			var new_y = victim.pos.y - 4 # Steep lift (4px)
			if _can_npc_fit(new_x, new_y, victim.team):
				_draw_npc_pixels(victim, 0) # Clear OLD
				victim.pos.x = new_x
				victim.pos.y = new_y
				_draw_npc_pixels(victim)   # Redraw NEW
				break

func _check_npc_environment_damage(npc) -> bool:
	var took_damage = false
	# Check key damage points (Head, Chest, Feet, and Ground Below)
	var check_points = [
		npc.pos,                  # Head
		npc.pos + Vector2i(1, 2), # Chest
		npc.pos + Vector2i(0, 4), # Feet
		npc.pos + Vector2i(0, 5), # Floor (below feet)
		npc.pos + Vector2i(1, 5), # Floor right
		npc.pos + Vector2i(-1, 2),# Left Side
		npc.pos + Vector2i(2, 2), # Right Side
		npc.pos + Vector2i(-1, 4),# Left Foot Side
		npc.pos + Vector2i(2, 4)  # Right Foot Side
	]
	
	for p in check_points:
		if p.x < 0 or p.x >= grid_width or p.y < 0 or p.y >= dynamic_grid_height: continue
		var tid = cells[p.y * grid_width + p.x] # Use raw cells for speed
		var t_tags = material_tags_raw[tid]
		
		
		# Detailed Damage Detection with Priority (Acid > Fire)
		if (t_tags & SandboxMaterial.Tags.ACID):
			npc.hp -= 3.5 
			npc.hit_flash = 5
			npc.hit_type = "acid"
			took_damage = true
			if randf() < 0.4: # More Acid Bubbles
				visual_sparks.append({"x":float(p.x)+randf_range(-2,2),"y":float(p.y),"vx":randf_range(-10,10),"vy":randf_range(-40,-20),"color":Color("#39FF14"),"life":0.6})
		elif (t_tags & SandboxMaterial.Tags.INCENDIARY):
			npc.hp -= 1.2
			took_damage = true
			if npc.hit_type != "acid": 
				npc.hit_flash = 5
				npc.hit_type = "fire"
			if randf() < 0.3: # Improved Fire Particles (Sparks + INTENSE Smoke)
				visual_sparks.append({"x":float(p.x),"y":float(p.y),"vx":randf_range(-15,15),"vy":randf_range(-35,-15),"color":Color("#FF8200"),"life":0.5})
				# High density smoke
				if randf() < 0.7: 
					visual_sparks.append({"x":float(p.x),"y":float(p.y),"vx":randf_range(-10,10),"vy":randf_range(-60,-30),"color":Color.WEB_GRAY,"life":1.5})


	# SUFFOCATION CHECK: Must touch Air (0), Smoke (15), or Cloud (17) AT THE BOUNDARY
	var air_found = false
	for oy in range(-1, 6): # 1px ring around 2x5
		for ox in range(-1, 3):
			# Skip the internal body area (0,0 to 1,4) because it's cleared to AIR during processing
			if oy >= 0 and oy <= 4 and ox >= 0 and ox <= 1: continue
			
			var tx = npc.pos.x + ox
			var ty = npc.pos.y + oy
			if tx < 0 or tx >= grid_width or ty < 0 or ty >= dynamic_grid_height: continue
			var nid = cells[ty * grid_width + tx]
			if nid == 0 or nid == 15 or nid == 17:
				air_found = true; break
		if air_found: break
	
	if !air_found:
		npc.hp -= 3.0 # Ahogo (Suffocation)
		npc.hit_flash = 4 # Blinking red for struggle visibility
		took_damage = true
		
	return took_damage

func _can_npc_fit(gx, gy, moving_team = -1) -> bool:
	# Bounding check
	if gx < 0 or gx + 1 >= grid_width or gy < 0 or gy + 4 >= dynamic_grid_height:
		return false
	
	# 2x5 area check
	for oy in range(5):
		for ox in range(2):
			var tid = _get_cell(gx + ox, gy + oy)
			# Only allow fitting through non-solid materials (Air, Smoke, Fire, Cloud)
			if tid != 0 and tid != 15 and tid != 3 and tid != 17:
				return false
	return true

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
						if n_id == 14: continue # BRASAS: Do not consume already burning coal!
						
						if randf() < 0.8: # FAST Carbonization for Wood
							if n_id == 18:
								_set_cell(nx, ny, 19) # Ignite Firework
								charge_array[n_idx] = randi_range(20, 70)
							elif (n_tags & SandboxMaterial.Tags.BURN_COAL):
								if randf() < 0.5: # 50% chance to become persistent coal
									_set_cell(nx, ny, 14)
								else: # 50% chance to be consumed as fire
									_set_cell(nx, ny, 3)
							elif (n_tags & SandboxMaterial.Tags.BURN_SMOKE):
								# Release smoke above if possible
								if _get_cell(nx, ny - 1) == 0:
									_set_cell(nx, ny - 1, 15)
								if randf() < 0.1: _set_cell(nx, ny, 3) # Turn to Fire (Lower chance)
								else: _set_cell(nx, ny, 0)
							else:
								_set_cell(nx, ny, 3) # Spread Fire!
					elif (n_tags & SandboxMaterial.Tags.EXPLOSIVE):
						if n_id == 27: # Volcan persistent ignition
							_set_cell(nx, ny, 29)
							charge_array[nx + ny * grid_width] = randi_range(80, 120)
						elif n_id == 18:
							_set_cell(nx, ny, 19)
							charge_array[n_idx] = randi_range(20, 70)
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
						elif n_id == 18: # IGNITE FIREWORK
							_set_cell(nx, ny, 19)
							charge_array[n_idx] = randi_range(20, 70)
						else:
							_set_cell(nx, ny, 7) # Prime TNT

func _explode(x, y, radius, sfx_action: String = "explosion"):
	_set_cell(x, y, 0)
	_play_action_sound(sfx_action)
	
	# NPC BLAST PHYSICS
	var center = Vector2i(x, y)
	for npc in active_npcs:
		var dist = Vector2(npc.pos).distance_to(Vector2(center))
		if dist < radius:
			var ratio = 1.0 - (dist / radius)
			npc.hp -= ratio * 120.0 # Lethal at center
			npc.hit_flash = 12
			npc.hit_type = "explosive"
			
			# Knockback (Fly away from center)
			var blast_dir = (Vector2(npc.pos) - Vector2(center)).normalized()
			if blast_dir.length() < 0.1: blast_dir = Vector2.UP
			
			var push_dist = int(ratio * 25.0)
			for d in range(push_dist, 0, -1):
				var nx = npc.pos.x + int(blast_dir.x * d)
				var ny = npc.pos.y + int(blast_dir.y * d) - 8 # Lift
				if _can_npc_fit(nx, ny, npc.team):
					_draw_npc_pixels(npc, 0)
					npc.pos.x = nx; npc.pos.y = ny
					_draw_npc_pixels(npc)
					break
			
			for s in range(5):
				visual_sparks.append({"x":float(npc.pos.x),"y":float(npc.pos.y),"vx":randf_range(-50,50),"vy":randf_range(-80,0),"color":Color.DARK_GRAY,"life":0.6})

	
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
	# ZERO-COPY GPU RENDER PASS (Peak GDScript Performance)
	# 1. Update Tornado Parameters
	var s_mat = texture_rect.material as ShaderMaterial
	if s_mat:
		s_mat.set_shader_parameter("tornado_x", float(tornado_x))
		s_mat.set_shader_parameter("tornado_ground_y", float(tornado_ground_y))
		s_mat.set_shader_parameter("tornado_intensity", float(tornado_intensity))
		
	# 2. BULK DATA TRANSFER (ID Map -> GPU)
	img.set_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, cells.to_byte_array())
	
	# 3. VISUAL OVERLAY (Paint sparks over the physical grid)
	for spark in visual_sparks:
		var sx = int(spark.x); var sy = int(spark.y)
		if sx >= 0 and sx < grid_width and sy >= 0 and sy < grid_height:
			var sc = spark.color; sc.a = spark.life
			# Marker: Ensure G > 0 to bypass ID lookup and keep actual color
			sc.g = max(0.01, sc.g)
			img.set_pixel(sx, sy, sc)
			
	for fw in active_fireworks:
		var fx = int(fw.x); var fy = int(fw.y)
		if fx >= 0 and fx < grid_width and fy >= 0 and fy < grid_height:
			var fc = fw.color
			fc.g = max(0.01, fc.g) # Bypass ID lookup
			img.set_pixel(fx, fy, fc) # Bright head
			
	# Update Charge Texture for Shader effects
	charge_img.set_data(grid_width, grid_height, false, Image.FORMAT_L8, charge_array)
	charge_tex.update(charge_img)
	
	texture_rect.texture.update(img)

func _launch_firework(x, y):
	_set_cell(x, y, 0) # Clear the station
	_play_action_sound("firework_launch")
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
	if active_fireworks.size() > 0:
		_manage_looping_player(ascent_player, "firework_ascent")
	else:
		if ascent_player.playing: ascent_player.stop()

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
	_play_action_sound("firework_burst")
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
	active_npcs.clear()
	active_projectiles.clear()
	_update_texture()
	_update_highlights()
