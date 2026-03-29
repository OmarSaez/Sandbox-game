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
var mat_colors_1 = PackedColorArray()
var mat_colors_2 = PackedColorArray()
var mat_colors_3 = PackedColorArray()
var material_tags_raw = PackedInt32Array() 
var selected_material: int = 1
var current_weather: int = 0 
var is_paused: bool = false
# UI State
var is_mouse_over_ui: bool = false
var brush_radius: int = 2 
var current_language: String = "es" # Controlled by TranslationServer
var ui_scale_level: int = 1 # Start at 1.2x by default
func _get_ui_scale() -> float:
	var scales = [1.0, 1.2, 1.3, 1.5, 1.7, 2.0]
	return scales[ui_scale_level]

var ui_elements = {} # To track nodes for re-labeling
var tools_panel: PanelContainer
var disaster_panel: PanelContainer
var npc_panel: PanelContainer
var selected_team: int = 0 
var mouse_was_pressed: bool = false
@export var custom_emoji_font: Font 

var _combined_font: FontVariation 

func _get_safe_font() -> Font:
	if not _combined_font:
		_combined_font = FontVariation.new()
		
		# 1. FUENTE BASE (Texto estándar)
		var base_font = SystemFont.new()
		base_font.font_names = PackedStringArray(["sans-serif", "arial"])
		_combined_font.base_font = base_font
		
		# 2. FUENTE DE ICONOS (La que tú elijas en el Inspector)
		var emoji_f: Font = custom_emoji_font
		
		# Si no has puesto nada en el inspector, intenta buscar la carpeta por defecto
		if not emoji_f:
			var paths = [
				"res://assets/fonts/Twemoji.ttf",
				"res://assets/fonts/NotoColorEmoji.ttf",
				"res://assets/fonts/FluentEmoji.ttf"
			]
			for p in paths:
				if ResourceLoader.exists(p):
					emoji_f = load(p)
					break
		
		# 3. ÚLTIMO RECURSO: Sistema
		if not emoji_f:
			emoji_f = SystemFont.new()
			emoji_f.font_names = PackedStringArray(["Emoji", "ColorEmoji", "Noto Color Emoji"])
			emoji_f.multichannel_signed_distance_field = false
			
		if emoji_f:
			_combined_font.set_fallbacks([emoji_f])
			
	return _combined_font
var touch_started_on_ui: bool = false # NEW: Track if the touch session began over UI
var active_npcs = [] # Array of dicts: { "pos": Vector2i, "team": int, "dir": int, "type": string, "hp": float, etc }
const SPATIAL_CELL_SIZE = 32
var npc_spatial_grid = [] 
var spatial_grid_w = 0
var spatial_grid_h = 0
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
var action_btn_font_size: int = 18 # Unified size for the 3 main ActionButtons tamaño botones

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
	20: "sand",     # Pólvora (Gunpowder)
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
	"npc_hit": "hit",             # Cuando un NPC recibe daño normal (armas)
	"damage_npc": "damage_npc",   # Daño de entorno (fuego, ácido, explosivo, asfixia)
	"npc_death": "death",         # Cuando un NPC muere
	"npc_place": "spawn",         # Al colocar un NPC en el mapa
	"explosion": "explode",       # Detonación de TNT o Volcán
	"lightning": "lightning",     # Impacto de rayo (clima)
	"earthquake": "quake",        # Inicio de Terremoto
	"tornado": "tornado",         # Inicio de Tornado
	"tsunami": "tsunami",         # Inicio de Tsunami
	"ui_click": "click",          # Al pulsar botones de la interfaz
	"warrior_attack": "sword_swing", # Ataque de Guerrero
	"archer_shoot": "bow_shoot",     # Disparo de Arquero
	"miner_dig": "pickaxe_hit",      # Minero picando tierra
	"medic_heal": "medic_heal",      # SONIDO DEL MÉDICO
	
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

# Localization system (Standard tr() calls)

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

# Future Disaster settings (Scalability)
# Future Disaster settings (Scalability)
var acid_rain_intensity: int = 0
var lava_rain_intensity: int = 0
var meteor_storm_intensity: int = 0
var black_hole_intensity: int = 0
var sinkhole_intensity: int = 0
var sand_storm_intensity: int = 0

# Fireworks tracking
var active_fireworks = [] 
# Optimization #3: High-Performance Particle Pool (Packed Data)
const MAX_VISUAL_SPARKS = 1500
var vs_x := PackedFloat32Array()
var vs_y := PackedFloat32Array()
var vs_vx := PackedFloat32Array()
var vs_vy := PackedFloat32Array()
var vs_color := PackedColorArray()
var vs_life := PackedFloat32Array()
var vs_ptr := 0

# Optimization #4: Sparse Electricity/Charge System
var active_charge_indices := PackedInt32Array()
var next_charge_indices := PackedInt32Array()
var charge_queued_frame := PackedInt32Array()

# Display
@onready var texture_rect: TextureRect = $Display
var img: Image

func _ready():
	# 0. GLOBAL VISUAL STABILITY (Fixes grey margins on Tablets/Modern Devices)
	RenderingServer.set_default_clear_color(Color(0.04, 0.04, 0.04, 1.0))
	
	# AUTO-DETECT LANGUAGE
	var os_lang = TranslationServer.get_locale().split("_")[0]
	var supported = ["es", "en", "it", "fr", "de", "pt"]
	if supported.has(os_lang):
		TranslationServer.set_locale(os_lang)
	else:
		TranslationServer.set_locale("en") # Fallback
	current_language = TranslationServer.get_locale()
	var global_bg = ColorRect.new()
	global_bg.name = "GlobalBG"
	global_bg.color = Color(0.1, 0.1, 0.12, 1.0) # Dynamic Dark Theme
	global_bg.anchor_right = 1.0
	global_bg.anchor_bottom = 1.0
	global_bg.offset_right = 0
	global_bg.offset_bottom = 0
	get_parent().add_child.call_deferred(global_bg)
	
	# Init Particle Pool
	vs_x.resize(MAX_VISUAL_SPARKS); vs_y.resize(MAX_VISUAL_SPARKS)
	vs_vx.resize(MAX_VISUAL_SPARKS); vs_vy.resize(MAX_VISUAL_SPARKS)
	vs_color.resize(MAX_VISUAL_SPARKS); vs_life.resize(MAX_VISUAL_SPARKS)
	vs_life.fill(0.0)
	
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
	
	charge_queued_frame.resize(grid_width * grid_height)
	charge_queued_frame.fill(-1)
	
	# Update Display node size to match the grid exactly
	$Display.custom_minimum_size = Vector2(grid_width * grid_scale, grid_height * grid_scale)
	$Display.size = $Display.custom_minimum_size
	
	# Init arrays
	cells.resize(grid_width * grid_height)
	tags_array.resize(grid_width * grid_height)
	charge_array.resize(grid_width * grid_height)
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	color_buffer.resize(grid_width * grid_height * 4)
	surface_cache.resize(grid_width)
	
	material_colors_bytes.resize(2048 * 4)
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
	
	mat_colors_1.resize(2048)
	mat_colors_2.resize(2048)
	mat_colors_3.resize(2048)
	material_tags_raw.resize(2048)
	
	# === SPATIAL HASH SETUP ===
	spatial_grid_w = ceil(float(grid_width) / SPATIAL_CELL_SIZE)
	spatial_grid_h = ceil(float(grid_height) / SPATIAL_CELL_SIZE)
	npc_spatial_grid.resize(spatial_grid_w * spatial_grid_h)
	for i in range(npc_spatial_grid.size()):
		npc_spatial_grid[i] = []
		
	# Setup materials (0-255)
	_register_material(0, Color(0, 0, 0, 0), SandboxMaterial.Tags.NONE)
	
	# --- RAW MATERIALS (0-20) ---
	# 1: Arena
	_register_material(1, Color("FFF9C4"), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("FDEB7A")) # Arena
	# 2: Agua
	_register_material(2, Color("80D0FF"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.CONDUCTOR) # Agua
	# 3: Fuego
	_register_material(3, Color("EBB400"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_MEDIUM, Color("FF4500")) # Fuego
	# 4: Petroleo
	_register_material(4, Color("041200"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.BURN_SMOKE) # Petroleo
	# 5: TNT
	_register_material(5, Color("E30000"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.GRAV_STATIC) # TNT
	# 6: Tierra
	_register_material(6, Color("#66380C"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#4D2A09")) # Tierra
	
	# 8: Metal
	_register_material(8, Color("EDEDED"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.GRAV_STATIC) # Metal
	# 9: Electricidad
	_register_material(9, Color("FFF300"), SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC) # Electricidad
	# 10: Rocas
	_register_material(10, Color("4D4D4D"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#292929")) # Rocas
	# 11: Lava
	_register_material(11, Color("FF4000"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.TEXTURE_TRIPLE | SandboxMaterial.Tags.MIX_MEDIUM, Color("FF7A00"), Color("2A0000")) # Lava
	# 12: Obsidiana
	_register_material(12, Color("0E0017"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_ACID | SandboxMaterial.Tags.ANTI_EXPLOSIVE | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#59008F")) # Obsidiana
	# 13: Acido
	_register_material(13, Color("#39FF14"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.ANTI_ACID  | SandboxMaterial.Tags.TEXTURE_TRIPLE | SandboxMaterial.Tags.MIX_LOW, Color("B7FC49"), Color("F2FF00")) # Acido
	
	# 14: Carbon
	_register_material(14, Color("#1A1110"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#3D1A10")) # Carbon
	# 15: Humo
	_register_material(15, Color("454545ff"), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.BURN_NONE) # Humo
	# 16: Madera
	_register_material(16, Color("#3E2609"), SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.BURN_COAL | SandboxMaterial.Tags.SOLID) # Madera
	# 17: Vapor/Nube
	_register_material(17, Color("8C8C8C"), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP) # Nube/Vapor
	# 18: Mecha / Fuegos artificiales
	_register_material(18, Color("FF7D7D"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.ANTI_EXPLOSIVE) # Mecha / Fuegos artificiales
	# 19: Destello
	_register_material(19, Color(1, 0.8, 0.9), SandboxMaterial.Tags.GRAV_STATIC) # Destello Visual
	# 20: Polvora
	_register_material(20, Color("#6B6A66"), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Polvora
	
	# --- BIOLOGICALS (21-24) ---
	# 21: Pasto
	_register_material(21, Color("#4CAF50"), SandboxMaterial.Tags.PLANT | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.BURN_COAL) # Pasto
	# 24: Enredadera
	_register_material(24, Color("#3E5E2A"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.PLANT | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.BURN_COAL) # Enredadera / Tallo
	
	# Setup Fertility
	material_tags_raw[1] |= SandboxMaterial.Tags.FERTILE
	material_tags_raw[6] |= SandboxMaterial.Tags.FERTILE
	
	# 22: Arena Mojada
	_register_material(22, Color("#C2B280").darkened(0.2), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.FERTILE) # Arena Mojada
	# 23: Tierra Mojada
	_register_material(23, Color("#8B4513").darkened(0.2), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.FERTILE | SandboxMaterial.Tags.BURN_COAL) # Tierra Mojada
	
	# --- STATES AND VFX ---
	# 7: TNT Flash (Blanco)
	_register_material(7, Color.WHITE, SandboxMaterial.Tags.GRAV_STATIC) # TNT Flashing (Normal)
	# 77: TNT Flash (Rojo)
	_register_material(77, Color("FF0000"), SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE) # TNT Flashing (Red)
	# 43: Chispa
	_register_material(43, Color("#FFFF00"), SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.VOLATILE | SandboxMaterial.Tags.GRAV_STATIC) # Chispa Amarilla
	# 44: Proyectil Acido
	_register_material(44, Color("#39FF14"), SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.VOLATILE | SandboxMaterial.Tags.GRAV_STATIC) # Proyectil Acido
	
	# --- CONSTRUCTION ---
	# 25: Cemento Fresco
	_register_material(25, Color("#d3c1a9ff"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.MIX_LOW, Color("#757570")) 
	# 26: Cemento Solido
	_register_material(26, Color("#C2B280"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC) # Cemento Solido
	# 27: Volcan Bloque
	_register_material(27, Color("#FF5F1F"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE) # Volcan Bloque
	# 28: Proyectil Volcan
	_register_material(28, Color("#FFFF00"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.ANTI_EXPLOSIVE) # Proyectil Volcan
	# 29: Base de Volcan
	_register_material(29, Color("#FF4500"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE) # Base de Volcan Activa

	# --- NPC SYSTEM: GUERRERO (1000-1009) ---
	_register_material(1000, Color("1b977cff"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1001, Color("717E80"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza
	_register_material(1002, Color("1F1F1F"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso
	_register_material(1003, Color("FFE2BD"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel
	_register_material(1008, Color("717E80"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos
	
	# EQUIPOS (1004-1007)
	_register_material(1004, Color("E00000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Rojo
	_register_material(1005, Color("008EE6"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Azul
	_register_material(1006, Color("FFD000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Amarillo
	_register_material(1007, Color("00E317"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Verde
	
	# --- NPC SYSTEM: ARQUERO (1010-1019) ---
	_register_material(1010, Color("#228B22"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1011, Color("9C5B00"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza (Tela)
	_register_material(1012, Color("D46E00"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC) # Flecha
	_register_material(1013, Color("FFBC78"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel Arquero
	_register_material(1014, Color("9D00FF"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso Arquero
	_register_material(1015, Color("#594E61"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos Arquero
	
	# --- NPC SYSTEM: MINERO (1020-1029) ---
	_register_material(1020, Color("#555555"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1021, Color("#FFFB00"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Casco (Luz)
	_register_material(1022, Color("7D522D"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel Minero
	_register_material(1023, Color("#FF8D00"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso Minero
	_register_material(1024, Color("#000000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos Minero

	# --- NPC SYSTEM: MÉDICO (1040-1049) ---
	_register_material(1040, Color("#EEEEEE"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master/Uniforme
	_register_material(1041, Color("#7A0000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cruz Roja
	_register_material(1042, Color("FFA691"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel Médico
	_register_material(1043, Color("#EEEEEE"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso Médico
	_register_material(1044, Color("#FFFFFF"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza Médica
	_register_material(1045, Color("#DEDEDE"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos Médico
	
	# --- SISTEMA DE DAÑO Y HIT (1030-1035) ---
	_register_material(1030, npc_color_acid, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1031, npc_color_fire, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1032, npc_color_exp, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1033, npc_color_hit, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1034, npc_color_death, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1035, Color.CYAN, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)

	# --- CRYOGENIC SYSTEM (70-72) ---
	_register_material(70, Color("#bbe0fcff"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(71, Color.WHITE, SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(72, Color("#6B6A66"), SandboxMaterial.Tags.GRAV_STATIC)

	# UI AND TEXTURE SETUP (Must happen AFTER materials are registered)
	texture_rect.texture = ImageTexture.create_from_image(img)
	texture_rect.anchor_right = 1.0
	texture_rect.anchor_bottom = 1.0
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.show_behind_parent = true # Emojis are drawn in SandboxGrid._draw(), so Display MUST be behind it
	charge_tex = ImageTexture.create_from_image(charge_img)

	_setup_main_ui_containers()
	
	# FORCE START HIDDEN
	tools_panel.visible = false
	disaster_panel.visible = false
	if npc_panel: npc_panel.visible = false
	
	_register_material(19, Color(1, 0.8, 0.9), SandboxMaterial.Tags.GRAV_STATIC) # Firework Fuse

	# INITIAL HIGHLIGHT
	_update_material_highlights()
	_update_menu_highlights()
	
	# FINAL SHADER & PALETTE SYNC (Now 2048x3 for Textures)
	var palette_img = Image.create(2048, 3, false, Image.FORMAT_RGBA8)
	palette_img.fill(Color(0,0,0,0))
	for i in range(2048):
		palette_img.set_pixel(i, 0, mat_colors_1[i])
		palette_img.set_pixel(i, 1, mat_colors_2[i])
		palette_img.set_pixel(i, 2, mat_colors_3[i])
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
	_add_button("powd", 20)
	_add_button("grass", 21)
	_add_button("vine", 24)
	_add_button("cem_fresh", 25)
	_add_button("cement", 26)
	_add_button("volcan", 27)
	_add_button("ice", 70)
	
	# --- SECCIÓN PROXIMAMENTE ---
	_add_ui_header(material_grid, "coming_soon")
	_add_button("toxic_gas", 0, true)
	_add_button("void", 0, true)
	_add_button("battery", 0, true)
	_add_button("npc_act", 0, true)
	_add_button("door", 0, true)
	_add_button("flam_gas", 0, true)
	_add_button("coal_item", 0, true)
	_add_button("bacteria", 0, true)
	_add_button("cure", 0, true)
	_add_button("and_more", 0, true)
	
	# FIND the scroll vbox to add the final spacer
	var s = _get_ui_scale()
	var scroll_vbox = material_grid.get_parent()
	if scroll_vbox and scroll_vbox.name == "ScrollVBox":
		var spacer = Control.new()
		spacer.name = "FinalSpacer"
		spacer.custom_minimum_size = Vector2(0, 10.0 * s) # MINIMAL PADDING AT BOTTOM
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
		material_scroll.scroll_deadzone = 25
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
		
		# OPTIMIZATION: Use deadzone for smoother mobile scrolling
		material_scroll.scroll_deadzone = 25
		
		material_scroll.mouse_entered.connect(func(): is_mouse_over_ui = true)
		material_scroll.mouse_exited.connect(func(): is_mouse_over_ui = false)
		material_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ALWAYS Refresh Scroll Height for the current scale
	# NEW: LARGER TALL HUD with logical CAP (Fixed at 340px for stability) 
	var h = 340
	
	# UPDATE PHYSICAL BOUNDARY
	dynamic_grid_height = grid_height - ceil(float(h) / grid_scale)
	
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
	action_scroll.scroll_deadzone = 25
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
	action_vbox.custom_minimum_size = Vector2(0, 336) # FILL TOTAL HUD HEIGHT (-4px margin)
	action_vbox.add_theme_constant_override("separation", 3 * s)
	# Removed alignment center to allow expansion to fill
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
	_update_material_highlights()
	_update_menu_highlights()


func _setup_tools_ui():
	var s = _get_ui_scale()
	var ui_root = get_parent().get_node("UI")
	
	var tools_btn = Button.new()
	tools_btn.name = "ToolsBtn"
	tools_btn.custom_minimum_size = Vector2(160 * s, 58 * s) # BEEFY 58px Height for "Better Body"
	tools_btn.add_theme_font_size_override("font_size", action_btn_font_size * s)
	tools_btn.text = tr("tools")
	ui_elements["tools_btn"] = tools_btn
	tools_btn.add_theme_font_override("font", _get_safe_font())
	tools_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	tools_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	var panel_height = 490 * s
	var h = 340 # Match the Fixed Tall HUD height
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
		_play_action_sound("ui_click")
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
	
	var create_row = func(label_key: String, options: Array, callback: Callable, is_upcoming: bool = false):
		var lbl = Label.new()
		lbl.text = tr(label_key) + ": "
		lbl.add_theme_font_size_override("font_size", 14.0 * s)
		lbl.add_theme_font_override("font", _get_safe_font())
		ui_elements[label_key + "_lbl"] = lbl
		v_box.add_child(lbl)
		
		var flow = HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(flow)
		
		if is_upcoming:
			lbl.modulate = Color(0.5, 0.5, 0.5, 0.7)
			flow.modulate = Color(0.5, 0.5, 0.5, 0.7)
		
		for i in range(options.size()):
			var btn = Button.new()
			btn.text = str(options[i])
			btn.custom_minimum_size = Vector2(80.0 * s, 45.0 * s)
			btn.add_theme_font_size_override("font_size", 14.0 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			
			if is_upcoming:
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.modulate = Color(0.6, 0.6, 0.6)
			else:
				var level = i
				btn.pressed.connect(func(): 
					_play_action_sound("ui_click")
					callback.call(level)
				)
			flow.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = btn 

	# Language Row (First Tool)
	var lang_options = ["Español", "English", "Italiano", "Français", "Deutsch", "Português"]
	var lang_codes = ["es", "en", "it", "fr", "de", "pt"]
	create_row.call("lang", lang_options, func(l):
		current_language = lang_codes[l]
		_refresh_ui_text()
		_update_menu_highlights()
	)

	# UI SCALE ROW (Now 2nd)
	var scale_labels = [
		tr("size") + " 1.0", 
		tr("size") + " 1.2", 
		tr("size") + " 1.3", 
		tr("size") + " 1.5", 
		tr("size") + " 1.7", 
		tr("size") + " 2.0"
	]
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
		_update_menu_highlights()
	)
	# 1. SUPPORT CREATOR BUTTON (AD)
	var support_btn = Button.new()
	support_btn.text = tr("support")
	support_btn.custom_minimum_size = Vector2(0, 60 * s) 
	support_btn.add_theme_font_size_override("font_size", 16 * s) 
	support_btn.add_theme_font_override("font", _get_safe_font())
	
	var support_style = StyleBoxFlat.new()
	support_style.bg_color = Color(0.2, 0.4, 0.2, 1.0) # Nice Emerald Green
	support_style.border_width_left = 2; support_style.border_width_top = 2
	support_style.border_width_right = 2; support_style.border_width_bottom = 2
	support_style.border_color = Color.GOLD
	support_style.corner_radius_top_left = 8; support_style.corner_radius_top_right = 8
	support_style.corner_radius_bottom_left = 8; support_style.corner_radius_bottom_right = 8
	
	support_btn.add_theme_stylebox_override("normal", support_style)
	support_btn.add_theme_stylebox_override("hover", support_style)
	support_btn.add_theme_stylebox_override("pressed", support_style)
	support_btn.add_theme_color_override("font_color", Color.GOLD)

	support_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		if Engine.has_singleton("PoingGodotAdMob"):
			AdMobManager.show_rewarded()
		else:
			print("DEBUG: Anuncio apoyo (PC)")
	)
	ui_elements["support_btn"] = support_btn
	v_box.add_child(support_btn)

	# 2. PAUSE BUTTON
	var pause_btn = Button.new()
	pause_btn.text = tr("play") if is_paused else tr("pause")
	pause_btn.custom_minimum_size = Vector2(0, 50 * s) # SCALED
	pause_btn.add_theme_font_size_override("font_size", 16 * s) # SCALED
	pause_btn.add_theme_font_override("font", _get_safe_font())
	pause_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		
		if is_paused:
			# --- RESUMING: AD FIRST -> 3s COUNTDOWN -> RESUME ---
			var ad_shown = false
			if Engine.has_singleton("PoingGodotAdMob"):
				ad_shown = AdMobManager.check_and_show_interstitial("pause")
			
			if ad_shown:
				await AdMobManager.ad_dismissed
				
				# COUNTDOWN LOGIC
				pause_btn.disabled = true # Prevent double triggers
				for i in range(3, 0, -1):
					pause_btn.text = tr("resume_in") + str(i) + "..."
					await get_tree().create_timer(1.0).timeout
				pause_btn.disabled = false
			
			is_paused = false
			pause_btn.text = tr("pause")
		else:
			# --- PAUSING: PAUSE FIRST -> THEN SHOW AD ---
			is_paused = true
			pause_btn.text = tr("play")
			if Engine.has_singleton("PoingGodotAdMob"):
				AdMobManager.check_and_show_interstitial("pause")
		
		var players = [weather_player, quake_player, tornado_player, tsunami_player, firework_player, ascent_player, volcano_loop_player, fire_loop_player]
		for p in players:
			if is_instance_valid(p):
				p.stream_paused = is_paused
	)
	ui_elements["pause_btn"] = pause_btn
	v_box.add_child(pause_btn)

	# 3. DIRECT RESET BUTTON (Bottom of Tools)
	var reset_btn_node = Button.new() # Named local variable to avoid conflict with field
	reset_btn_node.text = tr("reset")
	reset_btn_node.custom_minimum_size = Vector2(0, 50 * s)
	reset_btn_node.add_theme_font_size_override("font_size", 16 * s)
	reset_btn_node.add_theme_font_override("font", _get_safe_font())
	reset_btn_node.pressed.connect(func():
		_play_action_sound("ui_click")
		# RESET FIRST
		_clear_all()
		# THEN AD
		if Engine.has_singleton("PoingGodotAdMob"):
			AdMobManager.check_and_show_interstitial("reset")
	)
	ui_elements["reset_btn"] = reset_btn_node
	v_box.add_child(reset_btn_node)
	
	_add_ui_header(v_box, "coming_soon")
	
	create_row.call("speed", ["x0.2", "x0.5", "x0.8", "x1", "x2", "x4"], func(_l): pass, true)
	create_row.call("eraser", [tr("eraser")], func(_l): pass, true)
	create_row.call("shapes", [
		tr("line"),
		tr("rect"),
		tr("circ"),
		tr("tria")
	], func(_l): pass, true)

func _setup_disaster_ui():
	var s = _get_ui_scale()
	var disaster_btn = Button.new()
	disaster_btn.name = "DisasterBtn"
	disaster_btn.custom_minimum_size = Vector2(160 * s, 58 * s) # BEEFY 58px Height for "Better Body"
	disaster_btn.add_theme_font_size_override("font_size", action_btn_font_size * s) 
	disaster_btn.text = tr("disasters")
	ui_elements["disaster_btn"] = disaster_btn
	disaster_btn.add_theme_font_override("font", _get_safe_font())
	disaster_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	disaster_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	
	var d_width = 350 * s
	var d_height = 490 * s
	var h = 340 # Match the Fixed Tall HUD height
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
		_play_action_sound("ui_click")
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
	
	var create_row = func(label_key: String, options: Array, callback: Callable, is_upcoming: bool = false):
		var lbl = Label.new()
		lbl.text = tr(label_key) + ": "
		lbl.add_theme_font_size_override("font_size", 14.0 * s)
		lbl.add_theme_font_override("font", _get_safe_font())
		ui_elements[label_key + "_lbl"] = lbl
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
			# Try to translate if it's a key, otherwise use as string
			btn.text = tr(osk)
			btn.custom_minimum_size = Vector2(80.0 * s, 45.0 * s)
			btn.add_theme_font_size_override("font_size", 14.0 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			
			if is_upcoming:
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.modulate = Color(0.6, 0.6, 0.6)
			else:
				var level = i
				btn.pressed.connect(func(): 
					_play_action_sound("ui_click")
					callback.call(level)
				)
			flow.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = [btn, osk]

	create_row.call("weather", ["off", "light", "med", "storm"], func(l): 
		current_weather = l
		_update_menu_highlights()
	)
	create_row.call("quake", ["off", "light", "med", "brutal"], func(l): 
		earthquake_intensity = l
		if l > 0: 
			earthquake_timer = randf_range(5.0, 7.0)
			_play_action_sound("earthquake")
		else:
			earthquake_timer = 0 # Reset para apagar sonido e intensidad
		_update_menu_highlights()
	)
	create_row.call("tornado", ["off", "light", "med", "heavy"], func(l):
		tornado_intensity = l
		if l > 0: 
			tornado_timer = 15.0; tornado_x = randf()*grid_width; tornado_target_x = randf()*grid_width
			_play_action_sound("tornado")
		else:
			tornado_timer = 0 # Apagar instantáneamente
		_update_menu_highlights()
	)
	create_row.call("tsunami", ["off", "light", "med", "storm"], func(l):
		tsunami_intensity = l
		if l > 0: 
			tsunami_timer = 15.0; tsunami_wave_x = 0.0
			_play_action_sound("tsunami")
		else:
			tsunami_timer = 0 # Apagar instantáneamente
		_update_menu_highlights()
	)
	
	_add_ui_header(v_box, "coming_soon")
	
	var int_keys = ["off", "light", "med", "heavy"]
	create_row.call("acid_rain", int_keys, func(l): acid_rain_intensity = l; _update_menu_highlights(), true)
	create_row.call("lava_rain", int_keys, func(l): lava_rain_intensity = l; _update_menu_highlights(), true)
	create_row.call("met_storm", ["off", "light", "med", "storm"], func(l): meteor_storm_intensity = l; _update_menu_highlights(), true)
	create_row.call("black_hole", ["off", "light", "med", "heavy"], func(l): black_hole_intensity = l; _update_menu_highlights(), true)
	create_row.call("sinkhole", ["off", "light", "med", "heavy"], func(l): sinkhole_intensity = l; _update_menu_highlights(), true)
	create_row.call("sand_storm", ["off", "light", "med", "storm"], func(l): sand_storm_intensity = l; _update_menu_highlights(), true)

func _refresh_ui_text():
	TranslationServer.set_locale(current_language)
	var s = _get_ui_scale()
	for key in ui_elements:
		var node_data = ui_elements[key]
		
		# Handle direct button nodes (Tools/Disasters)
		var btn_h = (336.0 - (6.0 * s)) / 3.0
		if key == "tools_btn": 
			node_data.text = tr("tools")
			node_data.custom_minimum_size = Vector2(160.0 * s, btn_h)
			node_data.add_theme_font_size_override("font_size", action_btn_font_size * s)
		elif key == "disaster_btn": 
			node_data.text = tr("disasters")
			node_data.custom_minimum_size = Vector2(160.0 * s, btn_h)
			node_data.add_theme_font_size_override("font_size", action_btn_font_size * s)
		elif key == "npc_btn": 
			node_data.text = tr("npc")
			node_data.custom_minimum_size = Vector2(160.0 * s, btn_h)
			node_data.add_theme_font_size_override("font_size", action_btn_font_size * s)
		elif key == "pause_btn": 
			node_data.text = tr("play") if is_paused else tr("pause")
			node_data.custom_minimum_size = Vector2(0, 50 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "reset_btn": 
			node_data.text = tr("reset")
			node_data.custom_minimum_size = Vector2(0, 50 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "support_btn":
			node_data.text = tr("support")
			node_data.custom_minimum_size = Vector2(0, 60 * s)
			node_data.add_theme_font_size_override("font_size", 16 * s)
		elif key == "warrior_btn":
			node_data.text = tr("warrior")
			node_data.custom_minimum_size = Vector2(120 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "archer_btn":
			node_data.text = tr("archer")
			node_data.custom_minimum_size = Vector2(120 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "miner_btn":
			node_data.text = tr("miner")
			node_data.custom_minimum_size = Vector2(120 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key == "medic_btn":
			node_data.text = tr("medic")
			node_data.custom_minimum_size = Vector2(120 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		elif key.ends_with("_btn") and not key.ends_with("_mat_btn"): # Generic NPC/Tool handler
			var pure_key = key.replace("_btn", "")
			node_data.text = tr(pure_key)
			node_data.custom_minimum_size = Vector2(100 * s, 45 * s)
			node_data.add_theme_font_size_override("font_size", 14 * s)
		
		# Handle Labels (Main labels for rows and material names)
		elif node_data is Label:
			if key.ends_with("_mat_lbl"):
				var pure_key = key.replace("_mat_lbl", "")
				node_data.text = tr(pure_key)
				node_data.add_theme_font_size_override("font_size", 18 * s) # PRECISE 18px matching creation
			elif key.ends_with("_lbl"):
				var pure_key = key.replace("_lbl", "")
				node_data.text = tr(pure_key) + ": "
				node_data.custom_minimum_size = Vector2(120 * s, 0)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key == "team_lbl":
				node_data.text = tr("team") + ": "
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif "_hdr" in key:
				var pure_key = key.split("_hdr")[0]
				node_data.text = "\n\n" + tr(pure_key) + "\n"
				node_data.add_theme_font_size_override("font_size", 20 * s)
		
		# Handle Intensity Buttons (Stored as Array [Btn, Key])
		elif node_data is Array:
			var btn = node_data[0]
			var osk = node_data[1]
			btn.text = tr(osk)
			btn.custom_minimum_size = Vector2(80 * s, 45 * s)
			btn.add_theme_font_size_override("font_size", 14 * s)
		# Handle other buttons in rows (lang, brush, ui_size)
		elif node_data is Button:
			if key.begins_with("lang_btn_") or key.begins_with("brush_btn_"):
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key.begins_with("team_btn_"):
				var idx = int(key.split("_")[-1])
				var team_keys = ["team_red", "team_blue", "team_yellow", "team_green"]
				node_data.text = tr(team_keys[idx])
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 12 * s)
			elif key.begins_with("ui_size_btn_"):
				var idx = int(key.split("_")[-1])
				var scales = ["1.0", "1.2", "1.3", "1.5", "1.7", "2.0"]
				node_data.text = tr("size") + " " + scales[idx]
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key.begins_with("shapes_btn_"):
				var idx = int(key.split("_")[-1])
				var shape_keys = ["line", "rect", "circ", "tria"]
				if idx < shape_keys.size():
					node_data.text = tr(shape_keys[idx])
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key.begins_with("speed_btn_"):
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key == "eraser_btn_0":
				node_data.text = tr("eraser")
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)
			elif key.ends_with("_btn_0"):
				var pure_key = key.replace("_btn_0", "")
				node_data.text = tr(pure_key)
				node_data.custom_minimum_size = Vector2(80 * s, 45 * s)
				node_data.add_theme_font_size_override("font_size", 14 * s)

func _add_button(key: String, mat_id: int, is_upcoming: bool = false):
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
	
	if is_upcoming:
		slot_pnl.modulate = Color(0.4, 0.4, 0.4, 0.8) # OSCURECIDO
		slot_pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE # NO CLICABLE
	
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
	icon_style.bg_color = Color.BLACK if is_upcoming else (mat_colors_1[mat_id] if mat_id >= 0 else Color(0.1, 0.1, 0.1))
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
	selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_overlay.visible = false # Managed by highlights
	
	# Center it over the icon
	selection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(selection_overlay)
	
	var btn_lbl = Label.new()
	btn_lbl.name = "MatLabel"
	btn_lbl.text = tr(key)
	btn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	btn_lbl.add_theme_font_size_override("font_size", 18 * s) # EVEN LARGER TEXT
	btn_lbl.add_theme_font_override("font", _get_safe_font())
	main_vbox.add_child(btn_lbl)
	ui_elements[key + "_mat_lbl"] = btn_lbl
	
	# CENTRALIZED INPUT (Whole slot)
	if not is_upcoming:
		slot_pnl.gui_input.connect(func(event):
			if not is_instance_valid(event) or not is_instance_valid(slot_pnl): return
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_play_action_sound("ui_click")
				selected_material = mat_id
				_update_material_highlights()
		)
	slot_pnl.set_meta("mat_id", mat_id)
	
	ui_elements[key + "_icon_pnl"] = selection_overlay # Store overlay for highlight
	ui_elements[key + "_mat_lbl"] = btn_lbl
	
	# OPTIMIZATION: Store shortcut references to avoid get_child loops
	slot_pnl.set_meta("overlay", selection_overlay)
	slot_pnl.set_meta("label", btn_lbl)
	
	material_grid.add_child(slot_pnl)
	
	main_vbox.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _add_ui_header(container, key: String):
	var s = _get_ui_scale()
	var header_pnl = Control.new()
	# Use a reasonable height and ensure it spans enough width
	header_pnl.custom_minimum_size = Vector2(250 * s, 60 * s)
	header_pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl = Label.new()
	lbl.text = "\n\n" + tr(key) + "\n"
	lbl.add_theme_font_size_override("font_size", 20 * s)
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.1)) # Gold/Yellowish
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	header_pnl.add_child(lbl)
	ui_elements[key + "_hdr_" + str(lbl.get_instance_id())] = lbl
	container.add_child(header_pnl)

# --- OPTIMIZED HIGHLIGHT SYSTEM ---

func _update_material_highlights():
	# Use static pre-configured style for high speed
	for slot in material_grid.get_children():
		if not is_instance_valid(slot): continue
		
		# SKIP HEADERS OR OTHER NON-BUTTON NODES
		if not slot.has_meta("mat_id"): continue
		
		var mat_id = slot.get_meta("mat_id", -1)
		var overlay = slot.get_meta("overlay", null)
		var label = slot.get_meta("label", null)
		
		if not overlay or not label: continue
		
		if mat_id == selected_material:
			overlay.visible = true
			# Only apply style once, don't duplicate on every click
			if not overlay.has_theme_stylebox_override("panel"):
				var sel_style = StyleBoxFlat.new()
				sel_style.draw_center = false
				# THICK WHITE INNER BORDER
				sel_style.border_width_left = 6; sel_style.border_width_top = 6
				sel_style.border_width_right = 6; sel_style.border_width_bottom = 6
				sel_style.border_color = Color.WHITE
				# THICK BLACK OUTER SHADOW (looks like a border)
				sel_style.shadow_color = Color.BLACK
				sel_style.shadow_size = 25
				sel_style.shadow_offset = Vector2(0, 0)
				# MATCH ICON CORNERS
				sel_style.corner_radius_top_left = 10; sel_style.corner_radius_top_right = 10
				sel_style.corner_radius_bottom_left = 10; sel_style.corner_radius_bottom_right = 10
				overlay.add_theme_stylebox_override("panel", sel_style)
			
			label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			overlay.visible = false
			label.remove_theme_color_override("font_color")

func _update_menu_highlights():
	# Update Tool/Disaster/NPC Highlights (Buttons)
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
					var codes = ["es", "en", "it", "fr", "de", "pt"]
					if idx < codes.size() and current_language == codes[idx]: is_active = true
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
					if selected_material == 1000: is_active = true
				elif key == "archer_btn":
					if selected_material == 1010: is_active = true
				elif key == "miner_btn":
					if selected_material == 1020: is_active = true
				elif key == "medic_btn":
					if selected_material == 1040: is_active = true
				elif key.begins_with("team_btn_"):
					var idx = int(key.split("_")[-1])
					if idx == selected_team: is_active = true
				
				if is_active:
					if not btn.has_theme_color_override("font_color"):
						btn.add_theme_color_override("font_color", Color.YELLOW)
						var highlight_style = StyleBoxFlat.new()
						highlight_style.bg_color = Color(0.3, 0.3, 0.4)
						highlight_style.border_width_bottom = 3
						highlight_style.border_color = Color.SKY_BLUE
						btn.add_theme_stylebox_override("normal", highlight_style)
				else:
					if btn.has_theme_color_override("font_color"):
						btn.remove_theme_color_override("font_color")
						btn.remove_theme_stylebox_override("normal")

func _is_any_ui_blocking() -> bool:
	# 1. Check if we are over the bottom HUD using grid math (FASTEST)
	var m_local = get_local_mouse_position()
	var gy = int(m_local.y / grid_scale)
	if gy >= dynamic_grid_height:
		return true

	# 2. Check Floating Panels (Only if they are actually visible)
	var m_pos = get_global_mouse_position()
	
	if tools_panel and tools_panel.visible and tools_panel.get_global_rect().has_point(m_pos):
		return true
	if disaster_panel and disaster_panel.visible and disaster_panel.get_global_rect().has_point(m_pos):
		return true
	if npc_panel and npc_panel.visible and npc_panel.get_global_rect().has_point(m_pos):
		return true
	
	# Fallback to signal-based flag
	if is_mouse_over_ui: return true
		
	return false


# --- SFX SYSTEM ---
func _get_sfx_stream(sfx_name: String) -> AudioStream:
	if sfx_cache.has(sfx_name):
		return sfx_cache[sfx_name]
	
	var extensions = [".ogg", ".mp3", ".wav"]
	for ext in extensions:
		var path = "res://assets/audio/sfx/" + sfx_name + ext
		if ResourceLoader.exists(path) or FileAccess.file_exists(path) or FileAccess.file_exists(path + ".import"):
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
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var is_blocking = _is_any_ui_blocking()
		
		# 1. INITIAL TOUCH PROTECTION
		if not mouse_was_pressed:
			touch_started_on_ui = is_blocking
			
			# 2. AUTOCLOSE MENUS ON WORKSPACE TAP (Only if didn't start on UI)
			if not touch_started_on_ui:
				if is_instance_valid(tools_panel) and tools_panel.visible: tools_panel.visible = false
				if is_instance_valid(disaster_panel) and disaster_panel.visible: disaster_panel.visible = false
				if is_instance_valid(npc_panel) and npc_panel.visible: npc_panel.visible = false

		# DRAW LOGIC (Only if touch session started on Sandbox AND current position is Sandbox)
		if not touch_started_on_ui and not is_blocking:
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
		else:
			# Not drawing, but we might need to stop sound if we were drawing and entered UI
			_manage_brush_sound(-1)
			
		mouse_was_pressed = true
	else:
		mouse_was_pressed = false
		touch_started_on_ui = false
		_manage_brush_sound(-1) # Stop sound when finger lifted

	# Simulation
	if not is_paused:
		_update_npc_spatial_hash()
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
	queue_redraw()

func _draw():
	var f = _get_safe_font()
	if not f: return
	var s = _get_ui_scale()
	for npc in active_npcs:
		if npc.get("current_emoji", "") != "":
			var world_pos = Vector2(float(npc.pos.x) + 1.0, float(npc.pos.y)) * float(grid_scale)
			# Pintar centrado sobre la cabeza del NPC (Offset ajustado para quedar cerca)
			draw_string(f, world_pos + Vector2(-40.0 * s, -14.0 * s), npc.current_emoji, HORIZONTAL_ALIGNMENT_CENTER, 80.0 * s, 20 * s)

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
	
	# Determine Sea Reference Level (Reference height outside the wave)
	var ref_x = int(tsunami_wave_x - radius - 10)
	if ref_x >= 0 and ref_x < grid_width:
		for gy in range(5, grid_height - 5):
			var idx = gy * grid_width + ref_x
			if (cells[idx] & 0xFF) > 0 and (material_tags_raw[cells[idx] & 0xFF] & SandboxMaterial.Tags.LIQUID):
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
		var _tid = cells[idx]
		
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

func _register_material(id: int, color1: Color, tags: int, color2 = null, color3 = null):
	mat_colors_1[id] = color1
	mat_colors_2[id] = color2 if color2 != null else color1
	mat_colors_3[id] = color3 if color3 != null else (color2 if color2 != null else color1)
	material_tags_raw[id] = tags

func _set_cell(x, y, mat_id):
	if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
		var idx = y * grid_width + x
		
		# CRITICAL PERFORMANCE OPTIMIZATION: Early Exit for Air
		if mat_id == 0:
			if cells[idx] == 0: return # Already air, no work needed
			cells[idx] = 0
			tags_array[idx] = 0
			charge_array[idx] = 0
			_activate_chunk(x, y)
			return

		var tags = material_tags_raw[mat_id]
		
		# Scalable Texturing Variant calculation
		var variant = 0
		if (tags & (SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.TEXTURE_TRIPLE)):
			var mix_prob = 0.35 # Medium default
			if (tags & SandboxMaterial.Tags.MIX_LOW): mix_prob = 0.15
			elif (tags & SandboxMaterial.Tags.MIX_HIGH): mix_prob = 0.55
			
			if randf() < mix_prob:
				variant = 1
				if (tags & SandboxMaterial.Tags.TEXTURE_TRIPLE) and randf() < 0.35:
					variant = 2
		
		# Store Mat ID in Bits 0-15 (Red/Green channels), Variant in Bits 24-31 (Alpha Channel)
		# Bits 16-23 (Blue) are kept zero for Material ID - used to flag Visual Effects (Sparks) in shader
		cells[idx] = (mat_id & 0xFFFF) | (variant << 24)
		tags_array[idx] = tags
		_activate_chunk(x, y)
		
		if (tags & SandboxMaterial.Tags.ELECTRICITY): 
			charge_array[idx] = 101
			_register_charge(idx)
		else: 
			charge_array[idx] = 0

func _activate_chunk(gx, gy):
	var cx = int(gx / CHUNK_SIZE)
	var cy = int(gy / CHUNK_SIZE)
	if cx >= 0 and cx < chunks_x and cy >= 0 and cy < chunks_y:
		var c_idx = cy * chunks_x + cx
		if next_chunks_active[c_idx] >= 60: return
		next_chunks_active[c_idx] = 60
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var ncx = cx + ox
				var ncy = cy + oy
				if ncx >= 0 and ncx < chunks_x and ncy >= 0 and ncy < chunks_y:
					next_chunks_active[ncy * chunks_x + ncx] = 60

func _get_cell(x, y):
	if x >= 0 and x < grid_width and y >= 0 and y < grid_height:
		return cells[y * grid_width + x] & 0xFFFF
	return -1

func _step_simulation():
	# Reset flags de sonidos ambientales
	is_volcano_active = false
	is_fire_active = false
	
	# PASS 0: RESET FRAME COUNTERS
	explosions_this_frame = 0
	
	# Update active chunk countdowns
	chunks_active = next_chunks_active.duplicate()
	for i in range(next_chunks_active.size()):
		if next_chunks_active[i] > 0:
			next_chunks_active[i] -= 1
	
	# Pass 1: Electricity Pulse Processing (SPARSE)
	_process_electricity()
	
	# Transition Active Charges to Next Frame
	active_charge_indices = next_charge_indices
	next_charge_indices = PackedInt32Array()
	
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
					var raw_id = cells[idx]
					var pure_id = raw_id & 0xFFFF
					if pure_id == 0: continue
					
					var tags = tags_array[idx]
					
					if pure_id == 7: # Primed Explosives (Processed in Pass 3)
						_activate_chunk(x, y) # Keep alive for timer
						continue

					if (tags & SandboxMaterial.Tags.GRAV_UP):
						_process_interactions(x, y, idx, raw_id, pure_id, tags)
						if cells[idx] == raw_id and pure_id != 28:
							_move_particle(x, y, raw_id, tags, -1)

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
					var raw_id = cells[idx]
					var pure_id = raw_id & 0xFFFF
					
					# FASTER INLINE FLOW (Avoid most calls)
					if pure_id > 0: # Process all active materials
						var tags = tags_array[idx]
						if not (tags & SandboxMaterial.Tags.GRAV_UP): 
							_process_interactions(x, y, idx, raw_id, pure_id, tags)
							if cells[idx] == raw_id and not (tags & SandboxMaterial.Tags.GRAV_STATIC):
								# GRAVITY INLINED for speed
								var should_move = true
								if (tags & SandboxMaterial.Tags.GRAV_SLOW) and randf() > 0.3:
									should_move = false
								
								if should_move:
									# Basic Move try
									var ny = y + 1
									if ny < dynamic_grid_height:
										var n_idx = ny * grid_width + x
										if (cells[n_idx] & 0xFFFF) == 0: # Down
											_swap_cells(x, y, x, ny)
										elif (tags & SandboxMaterial.Tags.LIQUID):
											# Liquis flow side-ways too
											if randf() > 0.5:
												if x < grid_width - 1 and (cells[idx + 1] & 0xFFFF) == 0: _swap_cells(x, y, x + 1, y)
												elif x > 0 and (cells[idx - 1] & 0xFFFF) == 0: _swap_cells(x, y, x - 1, y)
										elif (tags & SandboxMaterial.Tags.POWDER):
											# Powders move diagonally
											var dx = 1 if randf() > 0.5 else -1
											var nx = x + dx
											if nx >= 0 and nx < grid_width:
												var ni = ny * grid_width + nx
												if (cells[ni] & 0xFFFF) == 0: _swap_cells(x, y, nx, ny)

								pass # Interaction already processed at top
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
	for idx in active_charge_indices:
		var charge = charge_array[idx]
		if charge == 0: continue
		
		var mid = cells[idx] & 0xFFFF
		if mid == 7 or mid == 77 or mid == 71 or mid == 72:
			_register_charge(idx) # Keep timer alive
			continue
		
		if (mid == 5 or mid == 20) and charge < 101: 
			_register_charge(idx)
			continue
		
		if charge == 101:
			charge_array[idx] = 100
			_register_charge(idx)
			continue
		
		if charge == 100:
			var x = idx % grid_width
			var y = int(float(idx) / grid_width)
			var my_tags = material_tags_raw[mid]
			if (my_tags & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)):
				for ny in range(y - 1, y + 2):
					if ny < 0 or ny >= grid_height: continue
					for nx in range(x - 1, x + 2):
						if nx < 0 or nx >= grid_width: continue
						if nx == x and ny == y: continue
						var n_idx = ny * grid_width + nx
						var n_pid = cells[n_idx] & 0xFFFF
						if n_pid <= 0: continue
						var n_tags = tags_array[n_idx]
						if (n_tags & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)) and charge_array[n_idx] == 0:
							charge_array[n_idx] = 101
							_register_charge(n_idx)
							_activate_chunk(nx, ny)
		
		if (material_tags_raw[mid] & (SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.ELECTRIC_ACTIVATED)):
			charge_array[idx] -= 5
			if charge_array[idx] > 100: charge_array[idx] = 100
			if charge_array[idx] > 0:
				_register_charge(idx)
				_activate_chunk(idx % grid_width, int(float(idx) / grid_width))
		elif mid == 7: # TNT logic
			charge_array[idx] -= 5
			if charge_array[idx] > 0:
				_register_charge(idx)
				_activate_chunk(idx % grid_width, int(float(idx) / grid_width))



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
	tags_array[idx1] = material_tags_raw[m2 & 0xFFFF]
	charge_array[idx1] = c2
	
	cells[idx2] = m1
	tags_array[idx2] = material_tags_raw[m1 & 0xFFFF]
	charge_array[idx2] = c1
	
	if c1 > 0: _register_charge(idx2)
	if c2 > 0: _register_charge(idx1)
	
	# Wake up chunks
	_activate_chunk(x1, y1)
	_activate_chunk(x2, y2)

func _register_charge(idx):
	var frame = Engine.get_frames_drawn()
	if charge_queued_frame[idx] != frame:
		charge_queued_frame[idx] = frame
		next_charge_indices.append(idx)

func _process_interactions(x, y, idx, _raw_id, pure_id, tags):
	# PULSANT ELECTRICAL SOURCE
	if pure_id == 9:
		if charge_array[idx] == 0:
			charge_array[idx] = 101
			_register_charge(idx)
		
	# FIRE AND HEAT REACTIONS
	if (tags & SandboxMaterial.Tags.INCENDIARY):
		if pure_id == 3: is_fire_active = true 
		if pure_id == 3:
			if randf() < 0.1: _set_cell(x, y, 0)
		elif pure_id == 14: # Coal burnout
			is_fire_active = true
			if randf() < 0.002: 
				_set_cell(x, y, 0)
				if _get_cell(x, y - 1) == 0: _set_cell(x, y - 1, 15)
			if randf() < 0.1 and _get_cell(x, y-1) == 0:
				_set_cell(x, y - 1, 3)
		
		_check_neighbors_for_reaction(x, y, true)

	# FLAMMABLE / REACTIVE MATERIALS
	if (tags & SandboxMaterial.Tags.FLAMMABLE) or (tags & SandboxMaterial.Tags.EXPLOSIVE):
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY) or charge_array[idx] > 50:
			if pure_id == 16: # Wood
				if randf() < 0.5: 
					_set_cell(x, y, 14 if randf() < 0.5 else 3)
			elif pure_id == 4: # Petro
				if randf() < 0.1: _set_cell(x, y, 3)
			elif (tags & SandboxMaterial.Tags.EXPLOSIVE):
				var flags = 0
				if _has_tag_neighbor(x, y, SandboxMaterial.Tags.ACID):
					flags = 64
				elif charge_array[idx] > 50 or _count_neighbor_id(x, y, 9) > 0:
					flags = 128
				_prime_explosive(x, y, pure_id, flags)
			elif pure_id == 18:
				_set_cell(x, y, 19)
				charge_array[idx] = randi_range(20, 70)
				_register_charge(idx)
				_play_action_sound("fuse_burning", 0.1)
	
	if pure_id == 19: 
		charge_array[idx] -= 1
		if charge_array[idx] > 0: _register_charge(idx)
		if Engine.get_frames_drawn() % 4 == 0: _set_cell(x, y, 18)
		elif Engine.get_frames_drawn() % 4 == 2: _set_cell(x, y, 19)
		if charge_array[idx] <= 0: _launch_firework(x, y)

	elif pure_id == 7 or pure_id == 77 or pure_id == 71 or pure_id == 72: 
		var charge = charge_array[idx]
		var timer = charge & 63
		var flags = charge & 192
		var is_gunpowder = (pure_id == 71 or pure_id == 72)
		var base_id = 77 if not is_gunpowder else 72
		var prime_id = 7 if not is_gunpowder else 71
		
		timer -= 1
		if timer <= 0:
			_explode(x, y, 12 if not is_gunpowder else 8, "explosion", flags)
			return
		
		charge_array[idx] = flags | timer
		_register_charge(idx)
		if Engine.get_frames_drawn() % 10 < 5: cells[idx] = (cells[idx] & 0xFFFF0000) | prime_id
		else: cells[idx] = (cells[idx] & 0xFFFF0000) | base_id
		_activate_chunk(x, y)

	# --- CRYOGENICS ---
	if pure_id == 60:
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY):
			if randf() < 0.2: _set_cell(x, y, 2); return
		if randf() < 0.05:
			for ny in range(y - 1, y + 2):
				if ny < 0 or ny >= grid_height: continue
				for nx in range(x - 1, x + 2):
					if nx < 0 or nx >= grid_width: continue
					if nx == x and ny == y: continue
					if (cells[ny * grid_width + nx] & 0xFFFF) == 2:
						_set_cell(nx, ny, 60); return
						
	if pure_id == 70:
		for ny in range(y - 1, y + 2):
			if ny < 0 or ny >= grid_height: continue
			for nx in range(x - 1, x + 2):
				if nx < 0 or nx >= grid_width: continue
				if nx == x and ny == y: continue
				var n_idx = ny * grid_width + nx
				var n_pid = cells[n_idx] & 0xFFFF
				
				if n_pid == 11: 
					_set_cell(x, y, 17); _set_cell(nx, ny, 12); return
				elif n_pid == 3:
					_set_cell(x, y, 2) # Melt Ice -> Water
					_set_cell(nx, ny, 15) # Extinguish Fire -> Smoke
					return
				elif n_pid == 15 or n_pid == 17: # SMOKE/CLOUD (Warm Air)
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
					if (cells[ny * grid_width + nx] & 0xFFFF) == 2: # WATER
						_set_cell(nx, ny, 70) # FREEZE!
						return

	# VOLATILE INERTIA (Projectiles like Sparks)
	if (tags & SandboxMaterial.Tags.VOLATILE):
		var charge = charge_array[idx]
		var energy = charge >> 3
		var dir_idx = charge & 7
		
		if energy <= 0:
			_set_cell(x, y, 0); return
			
		# Pre-calculated coordinate arrays for 8 directions
		var dxs = [0, 1, 1, 1, 0, -1, -1, -1]
		var dys = [-1, -1, 0, 1, 1, 1, 0, -1]
		
		var dx = dxs[dir_idx]
		var dy = dys[dir_idx]
		
		var nx = x + dx; var ny = y + dy
		if nx < 0 or nx >= grid_width or ny < 0 or ny >= dynamic_grid_height:
			_set_cell(x, y, 0); return
			
		if _get_cell(nx, ny) == 0:
			# Advance with inertia
			var new_energy = energy
			if Engine.get_frames_drawn() % 2 == 0: new_energy -= 1
			charge_array[idx] = (new_energy << 3) | dir_idx
			_register_charge(idx)
			_swap_cells(x, y, nx, ny)
		else:
			# IMPACT: Turn into real liquid acid if it's an acid spark, otherwise vanish
			if pure_id == 44: _set_cell(x, y, 13)
			else: _set_cell(x, y, 0)
		return

	# ELECTRIC SEEDING (Pure Static Electricity)
	if (tags & SandboxMaterial.Tags.ELECTRICITY):
		if not (tags & (SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.VOLATILE)):
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
							# CORROSION: Destroy material and spark CORROSIVE ACID (ID 44)
							_set_cell(nx, ny, 44) 
							
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
		# 2. PLANT GROWTH (pure_id 21 - Grass)
		if pure_id == 21:
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
		elif pure_id == 1 or pure_id == 6:
			# Spread moisture more horizontally
			if current_weather > 0 or _has_id_within_oval(x, y, 2, 20, 10):
				_set_cell(x, y, 22 if pure_id == 1 else 23) # Transition to wet
		
		# 4. SPONTANEOUS GROWTH ON WET SOIL
		elif pure_id == 22 or pure_id == 23:
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
					if randf() < 0.1: _set_cell(x, y, 1 if pure_id == 22 else 6)

		# 5. VINE GROWTH (pure_id 24) - Vertical upward growth
		elif pure_id == 24:
			var h_left = charge_array[idx]
			if h_left > 0 and randf() < 0.3: # Faster growth speed
				var tid_up = _get_cell(x, y-1)
				if (tid_up == 0 or tid_up == 2):
					_set_cell(x, y-1, 24)
					charge_array[idx - grid_width] = h_left - 1 # Pass height gene (4-8)
					charge_array[idx] = 0 # Vine is now "mature"
		
	# 6. VOLCANO LOGIC (pure_id 27, 28, 29)
	if pure_id == 27: # Static block
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY) or charge_array[idx] > 50:
			_set_cell(x, y, 29) # Transform to ACTIVE BASE
			# Life duration for 3-5 shots (Approx 80-120 frames)
			charge_array[idx] = randi_range(80, 120)
	
	elif pure_id == 29: # Erupting Base
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

	elif pure_id == 28: # Ascending projectile
		is_volcano_active = true
		var current_fuel = charge_array[idx]
		for i in range(3):
			if current_fuel <= 0:
				_draw_circle(x, y, 6, 11) 
				_draw_circle(x, y, 5, 15) 
				_explode(x, y, 12, "volcan_burst")
				for _j in range(50):
					_add_spark(float(x), float(y), randf_range(-120, 120), randf_range(-150, 50), [Color.YELLOW, Color("#FFFF33"), Color.WHITE, Color.ORANGE].pick_random(), randf_range(0.4, 0.8))
				return
			var next_y = y - 1
			if next_y < 5: _set_cell(x, y, 11); _explode(x, y, 6); return
			var next_id = _get_cell(x, next_y)
			if next_id == 0 or next_id == 3 or next_id == 9 or next_id == 11 or next_id == 15:
				_swap_cells(x, y, x, next_y)
				var trail_id = 15 if randf() < 0.2 else (9 if randf() < 0.5 else 3)
				_set_cell(x, y, trail_id)
				for j in range(3):
					var lx = x + randi_range(-2, 2); var ly = y + randi_range(-1, 1)
					if _get_cell(lx, ly) == 0 or _get_cell(lx, ly) == 15: _set_cell(lx, ly, 11)
				y = next_y; idx = y * grid_width + x; current_fuel -= 1; charge_array[idx] = current_fuel
				for _j in range(12): _add_spark(float(x) + randf_range(-6, 6), float(y) + randf_range(0, 10), randf_range(-60, 60), randi_range(40, 100), [Color.YELLOW, Color("#FFFF33"), Color.WHITE, Color.ORANGE].pick_random(), randf_range(0.2, 0.5))
			else: current_fuel = 0; break
		if randf() < 0.8:
			var e_colors = [Color.YELLOW, Color.CYAN, Color.WHITE, Color("#FFFF33")]
			for _i in range(4): _add_spark(float(x) + randf_range(-3, 3), float(y + 1), randf_range(-50, 50), randf_range(20, 80), e_colors[randi() % e_colors.size()], randf_range(0.1, 0.4))
	
	# 7. FRESH CEMENT HARDENING 
	if pure_id == 25:
		if charge_array[idx] == 0: charge_array[idx] = randi_range(60, 120) 
		charge_array[idx] -= 1
		if charge_array[idx] <= 1: _set_cell(x, y, 26) 

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
	
	#Tamaño del panel NPC
	var p_width = 530 * s
	var p_height = 250 * s
	var h = 340 # Match the Fixed Tall HUD height
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
	npc_btn.add_theme_font_size_override("font_size", action_btn_font_size * s) 
	npc_btn.text = tr("npc")
	ui_elements["npc_btn"] = npc_btn
	npc_btn.add_theme_font_override("font", _get_safe_font())
	npc_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	npc_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
		_play_action_sound("ui_click")
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
		npc_lbl.text = tr("npc") + ": "
		npc_lbl.add_theme_font_size_override("font_size", 14 * s)
		v_box.add_child(npc_lbl)
		
		var npc_flow = HFlowContainer.new()
		npc_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(npc_flow)
		
		var create_npc_btn = func(key: String, id: int):
			var btn = Button.new()
			btn.text = tr(key)
			btn.custom_minimum_size = Vector2(100 * s, 45 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_material = id # Master Warrior Material
				_update_material_highlights()
				_update_menu_highlights()
			)
			ui_elements[key + "_btn"] = btn
			npc_flow.add_child(btn)
		
		create_npc_btn.call("warrior", 1000)
		create_npc_btn.call("archer", 1010)
		create_npc_btn.call("miner", 1020)
		create_npc_btn.call("medic", 1040)
		
		# Teams Row (NOW RESPONSIVE)
		var team_lbl = Label.new()
		team_lbl.text = tr("team") + ": "
		team_lbl.add_theme_font_size_override("font_size", 14 * s)
		ui_elements["team_lbl"] = team_lbl
		v_box.add_child(team_lbl)
		
		var team_flow = HFlowContainer.new()
		team_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(team_flow)
		
		var team_keys = ["team_red", "team_blue", "team_yellow", "team_green"]
		for i in range(4):
			var t_btn = Button.new()
			t_btn.text = tr(team_keys[i])
			t_btn.custom_minimum_size = Vector2(80 * s, 45 * s)
			t_btn.add_theme_font_size_override("font_size", 12 * s)
			t_btn.add_theme_font_override("font", _get_safe_font())
			var tidx = i
			t_btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_team = tidx
				_update_menu_highlights()
			)
			ui_elements["team_btn_" + str(i)] = t_btn
			team_flow.add_child(t_btn)
		
		_add_ui_header(v_box, "coming_soon")
		
		var npc_flow_fut = HFlowContainer.new()
		npc_flow_fut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		npc_flow_fut.modulate = Color(0.6, 0.6, 0.6, 0.7)
		v_box.add_child(npc_flow_fut)
		
		var create_fut_npc = func(key: String):
			var btn = Button.new()
			btn.text = tr(key)
			btn.custom_minimum_size = Vector2(100.0 * s, 45.0 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			btn.add_theme_font_size_override("font_size", 14.0 * s)
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			npc_flow_fut.add_child(btn)
			ui_elements[key + "_btn"] = btn # Support refresh
		
		create_fut_npc.call("zombie")
		create_fut_npc.call("summoner")
		create_fut_npc.call("bomber")
		create_fut_npc.call("mage")
		create_fut_npc.call("kamikaze")
		create_fut_npc.call("builder")

func _place_npc(x, y):
	var origin_x = x - 1
	var origin_y = y - 4
	
	var start_x = origin_x
	var start_y = origin_y
	
	# AUTO-REPOSITION (Protección Exclusiva Anti-Clones)
	# Busca el primer hueco libre de OTROS NPCs, ignorando la arena/tierra/paredes para permitir ahogos manuales
	var found_spot = false
	for radius in range(0, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, 2): 
				if abs(dx) == radius or abs(dy) == radius or radius == 0:
					var test_x = origin_x + dx
					var test_y = origin_y + dy
					
					var nearby = _get_nearby_npcs(test_x, test_y, 10.0)
					var overlap = false
					for other in nearby:
						if test_x < other.pos.x + 2 and test_x + 2 > other.pos.x and test_y < other.pos.y + 5 and test_y + 5 > other.pos.y:
							overlap = true
							break
					
					if not overlap:
						start_x = test_x
						start_y = test_y
						found_spot = true
						break
			if found_spot: break
		if found_spot: break
		
	if not found_spot: return # Imposible encontrar hueco incluso a 15 pixeles, abortar spawn silenciosamente
	
	var n_type = "warrior"
	if selected_material == 1010 or selected_material == 1011: n_type = "archer"
	elif selected_material == 1020 or selected_material == 1021: n_type = "miner"
	elif selected_material == 1040 or selected_material == 1041: n_type = "medic"
	
	# Register in entity list
	var new_npc = {
		"pos": Vector2i(start_x, start_y),
		"team": selected_team,
		"dir": 1 if randf() > 0.5 else -1,
		"type": n_type,
		"hp": randf_range(85.0, 115.0), # Variación en resistencia base
		"attack_cooldown": 0.0,
		"hit_flash": 0,
		"hit_type": "none",
		"dig_timer": 0.0,
		"spawn_y": start_y,
		"mine_state": "ramp",
		"state_steps": 25,
		"fall_depth": 0,
		"last_dig_time": 0,
		"miss_counter": 0,
		"vx": 0.0,
		"vy": 0.0,
		
		# -- ESTADÍSTICAS RPG ÚNICAS POR SOLDADO --
		"max_hp": 0.0, # Se calibra debajo
		"atk_dmg": randf_range(0.8, 1.25), # +-20% Variación en daño
		"knockback_mult": randf_range(0.7, 1.3), # Unidades fuertes tiran más lejos
		"cowardice": randf_range(0.15, 0.45), # Probabilidad personal de huir
		"precision": randf_range(-0.6, 0.6), # Peor/Mejor puntería con arco
		"heal_power": randf_range(15.0, 35.0), # Variación en fuerza de las curas médicas
		"is_fire_variant": randf() < 0.05,
		
		# --- SISTEMA EMOCIONAL (Pintado directo) ---
		"emoji_timer": 0.0,
		"current_emoji": "",
		"idle_emote_timer": randf_range(2.0, 5.0),
		"has_spotted_enemy": false,
		"stuck_timer": 0.0, 
		"last_pos_x": start_x 
	}
	
	new_npc["max_hp"] = new_npc["hp"]
	active_npcs.append(new_npc)
	_draw_npc_pixels(new_npc)


func _draw_npc_pixels(npc, override_mat = -1):
	var sx = npc.pos.x; var sy = npc.pos.y
	if override_mat == 0:
		for oy in range(-1, 7):
			for ox in range(-1, 3):
				var tx = sx + ox; var ty = sy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var tid = cells[ty * grid_width + tx] & 0xFFFF
					if tid > 0 and (material_tags_raw[tid] & SandboxMaterial.Tags.NPC): _set_cell(tx, ty, 0)
		return
		
	var is_dead = npc.hp <= 0; var is_flashing = npc.hit_flash > 0
	if is_flashing and not is_dead:
		sx += randi_range(-1, 1); sy += randi_range(-1, 1)
	elif is_dead:
		sy += 2; sx += 1 if (npc.dir > 0) else -1
		if (npc.hit_flash % 2 == 0): override_mat = 0
		
	# 1. Definir materiales por Clase (Dedicados para personalización)
	var m_head = 1001; var m_skin = 1003; var m_torso = 1002; var m_shoes = 1008
	var team_mat = 1004 + npc.team
	
	if npc.type == "archer":
		m_head = 1011; m_skin = 1013; m_torso = 1014; m_shoes = 1015
	elif npc.type == "miner":
		m_head = 1021; m_skin = 1022; m_torso = 1023; m_shoes = 1024
	elif npc.type == "medic":
		m_head = 1044; m_skin = 1042; m_torso = 1043; m_shoes = 1045
	
	# 2. Aplicar Overrides (Daño/Muerte)
	if override_mat != -1:
		m_head = override_mat; m_skin = override_mat; m_torso = override_mat; m_shoes = override_mat; team_mat = override_mat
	elif is_flashing:
		var f_mat = 1033; if is_dead: f_mat = 1034
		elif npc.hit_type == "acid": f_mat = 1030
		elif npc.hit_type == "fire": f_mat = 1031
		elif npc.hit_type == "explosive": f_mat = 1032
		elif npc.hit_type == "electric": f_mat = 1035
		m_head = f_mat; m_skin = f_mat; m_torso = f_mat; m_shoes = f_mat; team_mat = f_mat
		
	# 3. SET PIXELS (2x5 Grid)
	# Fila 0: Cabeza x2 (Casco cubriendo la parte superior)
	_set_cell(sx, sy, m_head); _set_cell(sx+1, sy, m_head)
	# Fila 1: Cabeza + Piel
	_set_cell(sx, sy+1, m_head); _set_cell(sx+1, sy+1, m_skin)
	# Fila 2 & 3: Torso (Mezcla de Color de Clase y Color de Equipo)
	if npc.type == "medic" and override_mat == -1 and !is_flashing:
		_set_cell(sx, sy+2, 1041); _set_cell(sx+1, sy+2, 1041)       # Torso arriba: Franja Médica (ID 1041)
		_set_cell(sx, sy+3, team_mat); _set_cell(sx+1, sy+3, team_mat) # Torso abajo: Color Equipo
	elif npc.type == "archer" and override_mat == -1 and !is_flashing:
		_set_cell(sx, sy+2, team_mat); _set_cell(sx+1, sy+2, team_mat) # Torso arriba: Equipo Completo
		_set_cell(sx, sy+3, team_mat); _set_cell(sx+1, sy+3, team_mat) # Torso abajo: Equipo Completo
	else:
		_set_cell(sx, sy+2, m_torso); _set_cell(sx+1, sy+2, team_mat) # Mezcla clase/equipo
		_set_cell(sx, sy+3, team_mat); _set_cell(sx+1, sy+3, m_torso)
	
	# Fila 4: Zapatos (Restaurados para TODOS los tipos)
	_set_cell(sx, sy+4, m_shoes); _set_cell(sx+1, sy+4, m_shoes)

func _update_npc_spatial_hash():
	for cell in npc_spatial_grid:
		cell.clear()
	for npc in active_npcs:
		var cx = clampi(int(npc.pos.x / SPATIAL_CELL_SIZE), 0, spatial_grid_w - 1)
		var cy = clampi(int(npc.pos.y / SPATIAL_CELL_SIZE), 0, spatial_grid_h - 1)
		npc_spatial_grid[cy * spatial_grid_w + cx].append(npc)

func _get_nearby_npcs(px, py, radius) -> Array:
	var results = []
	if npc_spatial_grid.is_empty(): return results
	var x_min = clampi(int((px - radius) / SPATIAL_CELL_SIZE), 0, spatial_grid_w - 1)
	var x_max = clampi(int((px + radius) / SPATIAL_CELL_SIZE), 0, spatial_grid_w - 1)
	var y_min = clampi(int((py - radius) / SPATIAL_CELL_SIZE), 0, spatial_grid_h - 1)
	var y_max = clampi(int((py + radius) / SPATIAL_CELL_SIZE), 0, spatial_grid_h - 1)
	for gy in range(y_min, y_max + 1):
		for gx in range(x_min, x_max + 1):
			results.append_array(npc_spatial_grid[gy * spatial_grid_w + gx])
	return results

func _process_npcs(delta):
	# --- VISUALES POR FRAME (Suavidad total y cero lag) ---
	# queue_redraw() se llama al final para renderizar los emojis
	
	# --- LÓGICA DE IA (20 veces por segundo para rendimiento) ---
	npc_update_timer += delta
	if npc_update_timer < 0.05: return 
	npc_update_timer = 0.0
	
	var dead_indices = []
	for i in range(active_npcs.size()):
		var npc = active_npcs[i]
		
		# Procesar timers de emojis y visibilidad (Lógica de Ciclo Emocional Optimizado)
		var emotes = []
		if npc.hp <= 0: emotes = ["💀"]
		else:
			if npc.get("is_fleeing", false): emotes.append("😭")
			if npc.get("has_spotted_enemy", false): emotes.append("❗")
			if npc.get("mine_state", "") == "saboteur": emotes.append("⭐"); emotes.append("😄")
			if !npc.get("has_spotted_enemy", false): emotes.append("👀")
		
		# Lógica de visualización
		if npc.emoji_timer > 0:
			npc.emoji_timer -= 0.05
		else:
			if emotes.size() == 1 and emotes[0] == "👀":
				var t_ms = Time.get_ticks_msec() % 3000
				npc.current_emoji = "👀" if t_ms < 1000 else ""
			elif emotes.size() > 0:
				var time_idx = int(Time.get_ticks_msec() / 1000.0) % emotes.size()
				npc.current_emoji = emotes[time_idx]
			else:
				npc.current_emoji = ""
		
		if npc.hit_flash > 0: 
			npc.hit_flash -= 1
			if npc.hit_flash == 0: npc.hit_type = "none"
		_draw_npc_pixels(npc, 0)
		_check_npc_environment_damage(npc)
		var np = npc.pos; var target = null
		if npc.hp > 0:
			if npc.type == "medic":
				var heal_cd = npc.get("attack_cooldown", 0.0)
				if heal_cd > 0: heal_cd -= 0.05
				npc["attack_cooldown"] = heal_cd
				var closest_enemy = _find_closest_enemy(npc, 180.0); var closest_ally = null; var ally_dist = 999.0
				var nearby = _get_nearby_npcs(npc.pos.x, npc.pos.y, 180.0)
				for other in nearby:
					if other.team == npc.team and other != npc and other.hp > 0 and other.type != "medic":
						var mhp = other.get("max_hp", 100.0)
						if other.hp < mhp: 
							var d = npc.pos.distance_to(other.pos)
							if d < ally_dist: ally_dist = d; closest_ally = other
				var medic_critical = npc.hp < (npc.get("max_hp", 100.0) * 0.5)
				var enemy_very_close = closest_enemy and npc.pos.distance_to(closest_enemy.pos) < 120.0
				if (medic_critical and enemy_very_close) or (enemy_very_close and not closest_ally):
					npc.dir = 1 if closest_enemy.pos.x < np.x else -1; npc["is_fleeing"] = true
				else:
					npc["is_fleeing"] = false
					if closest_ally:
						if ally_dist < 25.0:
							npc.dir = 0
							if heal_cd <= 0:
								closest_ally.hp = min(closest_ally.hp + npc.get("heal_power", 20.0), closest_ally.get("max_hp", 100.0))
								npc["attack_cooldown"] = 1.0; _play_action_sound("medic_heal")
								_set_npc_emoji(npc, "💚", 1.0) # El médico muestra que está curando
								if closest_ally.hp > closest_ally.get("max_hp", 100.0) * 0.3:
									closest_ally["morale_broken"] = false; closest_ally["is_fleeing"] = false
								_set_npc_emoji(closest_ally, "😊", 1.5)
								for _f in range(6): _add_spark(float(closest_ally.pos.x+randf_range(-3,3)),float(closest_ally.pos.y+randf_range(-5,0)),0.0,randf_range(-35.0,-15.0),Color.GREEN,0.6)
						else: npc.dir = 1 if closest_ally.pos.x > np.x else -1
					else:
						if randf() < 0.02: npc.dir = 1 if randf() > 0.5 else -1
						if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
			elif npc.type != "miner":
				target = _find_closest_enemy(npc, 250.0)
				if target and !npc.get("morale_broken", false):
					if !npc.get("has_spotted_enemy", false):
						_set_npc_emoji(npc, "❗", 1.2)
						npc["has_spotted_enemy"] = true
				elif !target:
					npc["has_spotted_enemy"] = false
					
				if npc.attack_cooldown > 0: npc.attack_cooldown -= 0.05
			var critical_hp = npc.get("max_hp", 100.0) * 0.3
			if npc.hp <= critical_hp and not npc.get("morale_broken", false):
				npc["morale_broken"] = true
				if randf() < npc.get("cowardice", 0.30):
					npc["is_fleeing"] = true
					_set_npc_emoji(npc, "😭", 3.0) 
					var start_drop_x = np.x + (1 if npc.dir == -1 else 0)
					if _get_cell(start_drop_x, np.y) == 0: _set_cell(start_drop_x, np.y, 2)
			if npc.type != "miner" and npc.type != "medic":
				if npc.get("is_fleeing", false):
					if target: npc.dir = 1 if target.pos.x < np.x else -1
					if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
					if randf() < 0.10:
						var drop_x = np.x + (1 if npc.dir == -1 else 0)
						if _get_cell(drop_x, np.y) == 0: _set_cell(drop_x, np.y, 2)
				elif !target:
					if randf() < 0.02: npc.dir = 1 if randf() > 0.5 else -1
					if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
				elif target:
					var dist_x = target.pos.x - np.x; var dx_abs = abs(dist_x); var dy_abs = abs(target.pos.y - np.y)
					if npc.type == "warrior":
						var target_below = target.pos.y > np.y + 8
						if target_below:
							if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
						else: npc.dir = 1 if dist_x > 0 else -1
						if dx_abs < 6 and dy_abs < 6:
							if npc.attack_cooldown <= 0: _attack_npc(npc, target); npc.attack_cooldown = 0.6
						if dx_abs < 4 and !target_below: npc.dir = 0 
					elif npc.type == "archer":
						var target_below = target.pos.y > np.y + 12
						if npc.miss_counter < 0:
							npc.miss_counter += 1
							if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
						else:
							if dx_abs > 120: npc.dir = 1 if dist_x > 0 else -1
							elif dx_abs < 50: npc.dir = -1 if dist_x > 0 else 1
							else:
								if target_below:
									if npc.dir == 0: npc.dir = 1 if randf() > 0.5 else -1
								else: npc.dir = 0
						if npc.attack_cooldown <= 0:
							_shoot_arrow(npc, target); npc.miss_counter += 1
							if npc.miss_counter >= 3: npc.miss_counter = -40
							npc.attack_cooldown = 1.1 if dx_abs > 50 else 1.5
			if npc.type == "miner":
				var dig_speed = 0.15 if npc.hp < 100.0 else 0.05 
				if npc.hit_flash == 5: npc.dir = -npc.dir
				npc.dig_timer += dig_speed
				if npc.dig_timer >= 0.15:
					npc.dig_timer = 0.0
					if !_can_npc_fit(np.x, np.y + 1, npc):
						if not (npc.has("mine_state") and npc.mine_state == "saboteur"): npc.state_steps -= 1
						if !(_get_cell(np.x, np.y - 4) != 0) and npc.mine_state == "gallery":
							npc.mine_state = "ramp"; npc.state_steps = 25
						if npc.state_steps <= 0:
							if npc.mine_state == "saboteur":
								_set_cell(np.x, np.y + 5, 3); npc.hp = 0; npc.hit_flash = 10
							elif npc.mine_state == "ramp": npc.mine_state = "gallery"; npc.state_steps = randi_range(60, 100)
							else: npc.mine_state = "ramp"; npc.state_steps = randi_range(15, 25)
						
						if npc.hp > 0:
							var dig_down = (npc.mine_state == "ramp")
							_miner_dig(npc, dig_down)
							var next_x = np.x + npc.dir; var next_y = np.y + (1 if dig_down else 0); var hit_wall = false
							if next_y >= dynamic_grid_height - 15:
								if npc.mine_state != "saboteur":
									npc.mine_state = "saboteur"; npc["saboteur_start_x"] = np.x; npc["saboteur_bounces"] = 0; npc.dir = 1 if randf() > 0.5 else -1
								next_y = np.y; next_x = np.x + npc.dir
							
							# PRIORITY SABOTAGE MISSION: If bounces >= 3, always explode regardless of height
							if npc.has("mine_state") and npc.mine_state == "saboteur" and npc.has("saboteur_bounces") and npc.saboteur_bounces >= 3:
								for fx in range(-2, 3):
									var f_idx = np.x + fx
									if f_idx >= 0 and f_idx < grid_width: 
										_set_cell(f_idx, np.y + 5, 3) 
										_set_cell(f_idx, np.y - 1, 3)
								npc.hp = 0; npc.hit_flash = 10
							else:
								var old_dir = npc.dir
								if next_x < 5 or next_x > grid_width - 5: hit_wall = true; npc.dir = -npc.dir
								elif _can_npc_fit(next_x, next_y, npc): np.x = next_x ; np.y = next_y
								elif !dig_down and _can_npc_fit(next_x, np.y - 1, npc): np.x = next_x ; np.y -= 1
								else: hit_wall = true; npc.dir = -npc.dir
								if hit_wall:
									if not (npc.has("mine_state") and npc.mine_state == "saboteur" and npc.has("saboteur_bounces") and npc.saboteur_bounces >= 2) and (next_x <= 5 or next_x >= grid_width - 5):
										var wall_x1 = np.x + 2 if old_dir == 1 else np.x - 1
										var wall_x2 = np.x + 3 if old_dir == 1 else np.x - 2
										for wy in range(np.y - 1, np.y + 6):
											if wy >= 0 and wy < dynamic_grid_height:
												if wall_x1 >= 0 and wall_x1 < grid_width: _set_cell(wall_x1, wy, 16)
												if wall_x2 >= 0 and wall_x2 < grid_width: _set_cell(wall_x2, wy, 16)
									if npc.has("mine_state") and npc.mine_state == "saboteur":
										if not npc.has("saboteur_bounces"): npc["saboteur_bounces"] = 0
										if npc.saboteur_bounces < 4: npc.saboteur_bounces += 1

		if not npc.has("vx"): npc["vx"] = 0.0
		if not npc.has("vy"): npc["vy"] = 0.0
		var moved_by_physics = false
		if abs(npc.vx) > 0.1 or abs(npc.vy) > 0.1:
			var steps_x = int(ceil(abs(npc.vx))); var dir_x = sign(npc.vx)
			var steps_y = int(ceil(abs(npc.vy))); var dir_y = sign(npc.vy)
			var max_steps = max(steps_x, steps_y)
			
			# FISICA DE EJES SEPARADOS: Permite deslizarse por paredes (Slide Physics)
			for j in range(max_steps):
				# Paso Horizontal (X)
				if j < steps_x:
					var next_x = np.x + int(dir_x)
					# Bloqueo por límites de pantalla
					if next_x < 0 or next_x + 1 >= grid_width:
						npc.vx = 0.0
					elif _can_npc_fit(next_x, np.y, npc):
						np.x = next_x
					else:
						npc.vx = 0.0
				
				# Paso Vertical (Y)
				if j < steps_y:
					var next_y = np.y + int(dir_y)
					if _can_npc_fit(np.x, next_y, npc):
						np.y = next_y
					else:
						npc.vy = 0.0
			if _can_npc_fit(np.x, np.y + 1, npc): # EN EL AIRE
				npc.vy += 1.0 # Gravedad
				npc.fall_depth += 1
				
				# --- CONTROL AEREO ---
				# Si el NPC tiene una dirección (dir), intentar mantener/ganar velocidad horizontal en el aire
				if npc.dir != 0:
					var air_speed_target = float(npc.dir) * 3.5
					npc.vx = lerp(npc.vx, air_speed_target, 0.15)
				
				npc.vx *= 0.99 # Rozamiento de aire leve
			else: # EN EL SUELO
				if npc.vy > 0: 
					if npc.vy >= 7.0 or npc.fall_depth >= 15: 
						npc.hp -= max(5.0, (npc.fall_depth - 10) * 1.5); npc.hit_flash = 5
					npc.vy = 0.0; npc.fall_depth = 0
				npc.vx *= 0.6 # Fricción de suelo
			
			if abs(npc.vx) < 0.2: npc.vx = 0.0
			if npc.vy > 8.0: npc.vy = 8.0
			moved_by_physics = true
		
		# --- 3. MOVIMIENTO IA (SI NO HAY FISICA ACTIVA) ---
		if not moved_by_physics:
			# 1. GRAVEDAD SOBERANA: Chequeo solo bajo los pies para evitar "colgarse" lateralmente
			var feet_y = np.y + 5
			var can_fall = true
			if feet_y >= dynamic_grid_height: can_fall = false
			else:
				for ox in range(2):
					var tid = _get_cell(np.x + ox, feet_y)
					if tid != 0 and tid != 15 and tid != 3 and tid != 17:
						if !(material_tags_raw[tid] & (SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.PLANT)):
							can_fall = false; break
			
			if can_fall:
				np.y += 1; npc.fall_depth += 1
			elif npc.type != "miner":
				if npc.fall_depth >= 12: 
					npc.hp -= (npc.fall_depth - 10) * 1.5; npc.hit_flash = 5
				if npc.fall_depth >= 3: npc.dir = -npc.dir
				npc.fall_depth = 0
				
				# Detectar si estamos atascados (sin movernos horizontalmente)
				var is_trying_to_move = (npc.dir != 0 or target != null)
				var cur_stuck = npc.get("stuck_timer", 0.0)
				if is_trying_to_move and abs(np.x - npc.get("last_pos_x", np.x)) < 0.1:
					cur_stuck += 0.05
				else:
					cur_stuck = 0.0
				npc["stuck_timer"] = cur_stuck
				npc["last_pos_x"] = np.x
				
				if npc.dir != 0:
					var moved = false
					# Asegurar límites de mapa antes de procesar
					np.x = clampi(np.x, 0, grid_width - 2)
					var front_edge = np.x + 1 if npc.dir == 1 else np.x
					var hazard_stop = false
					
					# 1. ESCANEO DE PELIGROS (Lava, Ácido, TNT)
					var danger_dist = -1; var safe_landing_dist = -1
					for dx in range(1, 15):
						var detect_x = front_edge + (npc.dir * dx)
						if detect_x < 0 or detect_x >= grid_width: break
						var is_danger = false
						for oy in range(0, 6):
							var tid = _get_cell(detect_x, np.y + oy)
							if tid > 0 and (material_tags_raw[tid] & (SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.EXPLOSIVE)): 
								is_danger = true; break
						if is_danger:
							if danger_dist == -1: danger_dist = dx
						elif danger_dist != -1 and not is_danger: 
							safe_landing_dist = dx; break
					
					if danger_dist != -1:
						if danger_dist <= 5: 
							var hazard_width = safe_landing_dist - danger_dist
							if safe_landing_dist != -1 and hazard_width <= 20: # Salto largo para lava
								if _can_npc_fit(np.x, np.y - 1, npc): npc.vy = -4.8; npc.vx = npc.dir * 3.6; moved = true
							else: 
								_set_npc_emoji(npc, "😨", 1.5)
								if target == null: npc.dir = -npc.dir; moved = true
								else: hazard_stop = true # Detenerse ante el peligro si hay target
					
					# 2. ESCANEO DE ACANTILADOS (Si no hay enemigo, no suicidarse)
					if not moved and not hazard_stop:
						var edge_x = np.x + (npc.dir * 2); var drop_depth = 0
						for dy in range(1, 15):
							if not _can_npc_fit(edge_x, np.y + dy, npc): break
							drop_depth += 1
						if drop_depth >= 12:
							var ignore_cliff = (target != null and target.pos.y > np.y and abs(target.pos.x - np.x) < 60)
							if not ignore_cliff: 
								if target == null: npc.dir = -npc.dir; moved = true
								else: hazard_stop = true # Detenerse en el borde si hay target, esperar a stuck_timer

					# 3. COLISIONES CON ALIADOS Y OBSTRUCCIONES
					if not moved and not hazard_stop:
						var tx_1 = np.x + npc.dir
						var tx_2 = np.x + (npc.dir * 2)
						var tx_test = tx_1 if (target != null or randf() < 0.5) else tx_2
						
						var nearby = _get_nearby_npcs(tx_test, np.y, 10.0)
						var bumped_ally = false
						for other in nearby:
							if other.team == npc.team and other != npc:
								if tx_test < other.pos.x + 2 and tx_test + 2 > other.pos.x and np.y < other.pos.y + 5 and np.y + 5 > other.pos.y:
									bumped_ally = true; break
						
						if bumped_ally: 
							if target == null: npc.dir = -npc.dir; moved = true
							else: # Intentar saltar sobre el aliado si estamos persiguiendo
								if _can_npc_fit(np.x, np.y - 1, npc): npc.vy = -3.5; npc.vx = npc.dir * 2.0; moved = true
						
						if not moved:
							# --- STEP-UP SISTEMA ---
							for dy in [0, -1, -2, -3]:
								if _can_npc_fit(tx_1, np.y + dy, npc):
									np.x = tx_1; np.y += dy; moved = true; break
							
							# If blocked by something taller, use a physics jump instead of teleporting
							if not moved:
								var max_jump = -12
								for dy in range(-4, max_jump - 1, -1):
									if _can_npc_fit(tx_2, np.y + dy, npc):
										# Instead of np.y += dy (teleport), we apply physics
										# This makes the "climb" look like a real jump and prevents teleport-loops
										npc.vy = -5.2; npc.vx = npc.dir * 3.4
										npc["stuck_timer"] = 0.0 # Reset as we are attempting a leap
										moved = true; break
					
					# 4. SISTEMA ANTI-ATASCO: SALTO FORZADO (Solo si no hemos avanzado)
					if not moved and target != null and npc.get("stuck_timer", 0.0) > 0.8:
						if _can_npc_fit(np.x, np.y - 1, npc):
							npc.vy = -4.5; npc.vx = npc.dir * 2.5; npc["stuck_timer"] = 0.0; moved = true
							_set_npc_emoji(npc, "🔨", 0.8)

					# 5. SI NADA FUNCIONÓ, GIRAR
					if not moved:
							if target == null or np.x <= 2 or np.x >= grid_width - 4:
								npc.dir = -npc.dir
							elif npc.get("stuck_timer", 0.0) > 2.0: # Si sigue atascado demasiado tiempo persiguiendo
								npc.dir = -npc.dir; npc["stuck_timer"] = 0.0 # Intentar buscar otra ruta
		
		npc.pos = np; _draw_npc_pixels(npc)
		if npc.hp <= 0 and npc.hit_flash <= 0:
			_set_npc_emoji(npc, "💀", 2.0)
			_draw_npc_pixels(npc, 0); _play_action_sound("npc_death")
			if npc.type == "miner" and npc.has("mine_state") and npc.mine_state == "saboteur":
				for fx in range(-2, 3):
					var f_idx = np.x + fx
					if f_idx >= 0 and f_idx < grid_width: _set_cell(f_idx, np.y + 5, 3); _set_cell(f_idx, np.y - 1, 3)
			npc.current_emoji = ""
			dead_indices.append(i)
	dead_indices.sort(); dead_indices.reverse()
	for idx in dead_indices: active_npcs.remove_at(idx)
	for npc in active_npcs: _draw_npc_pixels(npc)

func _miner_dig(npc, dig_down=false):
	if npc.hp <= 0: return
	var now = Time.get_ticks_msec()
	if now - npc.last_dig_time >= 3000: _play_action_sound("miner_dig"); npc.last_dig_time = now
	
	# RESTORED MISSING LOGIC
	var dy_offset = 1 if dig_down else 0
	var ty_start = npc.pos.y - 2 + dy_offset
	var ty_end = npc.pos.y + 5 + dy_offset
	var beam_len = 3 if dig_down else 6
	var is_saboteur = npc.has("mine_state") and npc.mine_state == "saboteur"
	var c_mat = 16 

	var tx_c = npc.pos.x + (npc.dir * 3)
	for ox in range(0, beam_len):
		var wx = tx_c + (ox * npc.dir)
		if wx < 0 or wx >= grid_width: continue
		if ty_start >= 0:
			var mountain_ahead = false
			for rx in range(0, 4):
				var r_check = wx + (rx * npc.dir)
				if r_check >= 0 and r_check < grid_width:
					var look_id = _get_cell(r_check, ty_start)
					if look_id != 0 and look_id != c_mat: mountain_ahead = true; break
			if mountain_ahead or is_saboteur:
				_set_cell(wx, ty_start, c_mat)
				if !dig_down and ty_start - 1 >= 0: _set_cell(wx, ty_start - 1, c_mat)
	var f_mat = 5 if is_saboteur else 16 # Piso TNT o Madera normal
	var tx_f = npc.pos.x - (npc.dir * 2) 
	var f_len = 6
	for ox in range(0, f_len):
		var wx = tx_f + (ox * npc.dir)
		if wx < 0 or wx >= grid_width: continue
		if ty_end < dynamic_grid_height:
			_set_cell(wx, ty_end, f_mat)
			if !dig_down and ty_end + 1 < dynamic_grid_height: _set_cell(wx, ty_end + 1, f_mat)
	for dx in range(0, 4):
		for dy in range(ty_start + 1, ty_end):
			var cx = npc.pos.x + (dx * npc.dir); var cy = dy 
			if cx < 0 or cx >= grid_width or cy < 0 or cy >= dynamic_grid_height: continue
			var tid = _get_cell(cx, cy)
			if tid == 0 or tid == 9 or tid == 12: continue
			_set_cell(cx, cy, 0)

func _shoot_arrow(npc, target):
	if npc.hp <= 0: return
	if !npc.get("morale_broken", false): _set_npc_emoji(npc, "😡", 0.8)
	_play_action_sound("archer_shoot"); var dx = float(target.pos.x - npc.pos.x); var dir = 1 if dx > 0 else -1; var aim_dy = float((target.pos.y + 2) - npc.pos.y); var speed_x = clamp(abs(dx) * 1.5, 90.0, 150.0); var vx = dir * speed_x; var t = abs(dx) / speed_x
	if t < 0.1: t = 0.1
	var arrow_gravity = 200.0; var vy = (aim_dy / t) - (0.5 * arrow_gravity * t); vy += npc.get("precision", 0.0) * 15.0; vy = clamp(vy, -280.0, 40.0)
	active_projectiles.append({ "pos": Vector2(npc.pos.x + dir*2, npc.pos.y + 1), "vel": Vector2(vx, vy), "team": npc.team, "type": "arrow", "life": 2.5, "atk_dmg": npc.get("atk_dmg", 1.0), "is_fire": npc.get("is_fire_variant", false) })

func _process_projectiles(delta):
	var to_remove = []
	for i in range(active_projectiles.size()):
		var p = active_projectiles[i]; _set_cell(int(p.pos.x), int(p.pos.y), 0)
		p.pos += p.vel * delta; p.vel.y += 200.0 * delta; p.life -= delta
		var gx = int(p.pos.x); var gy = int(p.pos.y)
		if gx < 0 or gx >= grid_width or gy < 0 or gy >= dynamic_grid_height or p.life <= 0: to_remove.append(i); continue
		var hit_npc = null
		var nearby = _get_nearby_npcs(gx, gy, 8.0)
		for other in nearby:
			if other.team != p.team:
				if gx >= other.pos.x and gx <= other.pos.x + 1 and gy >= other.pos.y and gy <= other.pos.y + 4: hit_npc = other; break
		if hit_npc:
			hit_npc.hp -= 40.0 * p.get("atk_dmg", 1.0); hit_npc.hit_flash = 4; hit_npc.hit_type = "normal"
			if p.get("is_fire", false):
				if _get_cell(gx, gy) == 0: _set_cell(gx, gy, 3)
			_play_action_sound("npc_hit")
			for _j in range(5): _add_spark(float(gx),float(gy),randf_range(-40,40),randf_range(-40,0),Color.WHITE,0.3)
			to_remove.append(i); continue
		var tid = _get_cell(gx, gy)
		if tid != 0 and tid != 15 and tid != 3 and tid != 17:
			if p.get("is_fire", false):
				var px = gx - int(sign(p.vel.x))
				if px >= 0 and px < grid_width and _get_cell(px, gy) == 0: _set_cell(px, gy, 3)
			to_remove.append(i); continue
		_set_cell(gx, gy, 1012)
	to_remove.reverse()
	for idx in to_remove: active_projectiles.remove_at(idx)

func _find_closest_enemy(me, radar_range):
	var closest = null; var min_dist = radar_range
	var nearby = _get_nearby_npcs(me.pos.x, me.pos.y, radar_range)
	for other in nearby:
		if other.team != me.team and other.hp > 0:
			var d = me.pos.distance_to(other.pos)
			if d < min_dist: min_dist = d; closest = other
	return closest

func _attack_npc(attacker, victim):
	if attacker.hp <= 0 or victim.hp <= 0: return
	if !attacker.get("morale_broken", false): _set_npc_emoji(attacker, "😡", 0.8)
	victim.hp -= (15.0 * attacker.get("atk_dmg", 1.0)); victim.hit_flash = 5; victim.hit_type = "normal"
	if attacker.get("is_fire_variant", false):
		var fx = victim.pos.x + randi_range(0, 1); var fy = victim.pos.y + randi_range(2, 4)
		if fx >= 0 and fx < grid_width and fy >= 0 and fy < dynamic_grid_height:
			if _get_cell(fx, fy) == 0: _set_cell(fx, fy, 3)
	_play_action_sound("npc_hit"); _play_action_sound("warrior_attack")
	var t_colors = [Color.RED, Color("1E90FF"), Color.YELLOW, Color.GREEN]; var bleed_color = t_colors[victim.team] if victim.team < t_colors.size() else Color.WHITE
	for _i in range(10): _add_spark(float(victim.pos.x) + randf_range(0, 2), float(victim.pos.y) + randf_range(0, 5), randf_range(-80, 80), randf_range(-120, -30), bleed_color if randf() > 0.4 else Color.WHITE, randf_range(0.3, 0.7))
	var ldir = 1 if attacker.pos.x < victim.pos.x else -1
	for d in range(3, 0, -1):
		var lx = attacker.pos.x + ldir * d; var ly = attacker.pos.y - 1
		if _can_npc_fit(lx, ly, attacker): attacker.pos.x = lx; attacker.pos.y = ly; break
	var push_dir = 1 if attacker.pos.x < victim.pos.x else -1
	if victim.type == "archer": attacker.vx = -push_dir * 3.5; attacker.vy = -4.0
	else:
		if randf() < 0.35: victim.vx = push_dir * randf_range(3.0, 5.0) * attacker.get("knockback_mult", 1.0); victim.vy = randf_range(-4.0, -8.0)

func _check_npc_environment_damage(npc) -> bool:
	if npc.hp <= 0: return false
	var took_damage = false; var p = npc.pos
	var check_points = [p, p + Vector2i(1, 2), p + Vector2i(0, 4), p + Vector2i(0, 5), p + Vector2i(1, 5), p + Vector2i(-1, 2), p + Vector2i(2, 2)]
	for pt in check_points:
		if pt.x < 0 or pt.x >= grid_width or pt.y < 0 or pt.y >= dynamic_grid_height: continue
		var tid = cells[pt.y * grid_width + pt.x] & 0xFFFF
		var t_tags = material_tags_raw[tid]
		if (t_tags & SandboxMaterial.Tags.ACID):
			npc.hp -= 3.5; npc.hit_flash = 5; npc.hit_type = "acid"; took_damage = true
			if randf() < 0.4: _add_spark(float(pt.x)+randf_range(-2,2),float(pt.y),randf_range(-10,10),randf_range(-40,-20),Color("#39FF14"),0.6)
		elif (t_tags & SandboxMaterial.Tags.INCENDIARY):
			npc.hp -= 1.2; took_damage = true; if npc.hit_type != "acid": npc.hit_flash = 5; npc.hit_type = "fire"
			if randf() < 0.3: _add_spark(float(pt.x),float(pt.y),randf_range(-15,15),randf_range(-35,-15),Color("#FF8200"),0.5)
		
		# Electricity Damage
		if charge_array[pt.y * grid_width + pt.x] > 50:
			npc.hp -= 2.5; took_damage = true; npc.hit_flash = 5; npc.hit_type = "electric"
			if randf() < 0.4: _add_spark(float(pt.x),float(pt.y),randf_range(-20,20),randf_range(-40,-10),Color.CYAN,0.4)
	var air_found = false
	for oy in range(-1, 6):
		for ox in range(-1, 3):
			if oy >= 0 and oy <= 4 and ox >= 0 and ox <= 1: continue
			var tx = npc.pos.x + ox; var ty = npc.pos.y + oy
			if tx < 0 or tx >= grid_width or ty < 0 or ty >= dynamic_grid_height: continue
			var nid = cells[ty * grid_width + tx] & 0xFFFF
			if nid == 0 or nid == 15 or nid == 17: air_found = true; break
		if air_found: break
	if !air_found: npc.hp -= 3.0; npc.hit_flash = 4; took_damage = true
	if took_damage: _play_action_sound("damage_npc", 0.4)
	return took_damage

func _set_npc_emoji(npc, emoji_text: String, duration: float = 2.0):
	if npc.current_emoji == emoji_text: return # Avoid spamming same emoji
	npc.current_emoji = emoji_text
	npc.emoji_timer = duration

func _can_npc_fit(gx, gy, moving_npc = null) -> bool:
	if gx < 0 or gx + 1 >= grid_width or gy < 0 or gy + 4 >= dynamic_grid_height: return false
	
	# Chequeo de píxeles: Ignorar Plantas y NPCs para fluidez
	for oy in range(5):
		for ox in range(2):
			var tid = _get_cell(gx + ox, gy + oy)
			if tid != 0 and tid != 15 and tid != 3 and tid != 17:
				# Si es sólido, pero es una PLANTA, permitimos el paso (los soldados las pisan/atraviesan)
				var tags = material_tags_raw[tid]
				if (tags & SandboxMaterial.Tags.PLANT): continue
				if !(tags & SandboxMaterial.Tags.NPC): return false
				
	# Chequeo de lista de NPCs: Ignorar aliados para evitar atascos de grupo
	if moving_npc != null:
		var nearby = _get_nearby_npcs(gx, gy, 10.0)
		for other in nearby:
			if other == moving_npc: continue
			# Regla de oro: Aliados no se estorban
			if other.team == moving_npc.team: continue 
			if gx < other.pos.x + 2 and gx + 2 > other.pos.x and gy < other.pos.y + 5 and gy + 5 > other.pos.y: return false
	return true

func _has_tag_neighbor(x, y, tag):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var nid = _get_cell(nx, ny)
			if nid > 0 and (material_tags_raw[nid] & tag): return true
	return false

func _has_tag_within_oval(x, y, tag, rx, ry):
	for oy in range(-ry, ry + 1, 3): 
		for ox in range(-rx, rx + 1, 3):
			if (float(ox*ox)/(rx*rx) + float(oy*oy)/(ry*ry)) <= 1.0:
				var nid = _get_cell(x + ox, y + oy)
				if nid > 0 and (material_tags_raw[nid] & tag): return true
	return false

func _has_id_within_oval(x, y, target_id, rx, ry):
	for oy in range(-ry, ry + 1, 3): 
		for ox in range(-rx, rx + 1, 3):
			if (float(ox*ox)/(rx*rx) + float(oy*oy)/(ry*ry)) <= 1.0:
				if _get_cell(x + ox, y + oy) == target_id: return true
	return false

func _consume_neighbor_tag(x, y, tag):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var nid = _get_cell(nx, ny)
			if nid > 0 and (material_tags_raw[nid] & tag): _set_cell(nx, ny, 0); return true
	return false

func _count_neighbor_id(x, y, id):
	var count = 0
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			if _get_cell(nx, ny) == id: count += 1
	return count

func _count_neighbor_id_radius(x, y, id, radius):
	var count = 0
	for ny in range(y - radius, y + radius + 1):
		for nx in range(x - radius, x + radius + 1):
			if nx == x and ny == y: continue
			if _get_cell(nx, ny) == id: count += 1
	return count

func _prime_explosive(x, y, id, ignition_flags = 0):
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height: return
	var idx = y * grid_width + x; var current_id = cells[idx] & 0xFFFF
	
	# FAILSAVE: If it's touching Acid RIGHT NOW, force Acid ignition
	if _has_tag_neighbor(x, y, SandboxMaterial.Tags.ACID):
		ignition_flags = 64
	
	# Handle already primed cells (Priority upgrade: Acid > Electric > Normal)
	if current_id == 7 or current_id == 77 or current_id == 71 or current_id == 72:
		var current_flags = charge_array[idx] & 192
		var target_flags = ignition_flags
		
		# Allow upgrading anything to ACID (64)
		if target_flags == 64 and current_flags != 64: 
			charge_array[idx] = (charge_array[idx] & 63) | 64
		# Allow upgrading NORMAL (0) to ELECTRIC (128)
		elif target_flags == 128 and current_flags == 0:
			charge_array[idx] = (charge_array[idx] & 63) | 128
		return 
	
	_set_cell(x, y, 7 if id == 5 else 71) 
	charge_array[idx] = 40 | ignition_flags

func _trigger_electric_devices(x, y):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var n_id = _get_cell(nx, ny)
			if n_id > 0 and (material_tags_raw[n_id] & SandboxMaterial.Tags.ELECTRIC_ACTIVATED): _prime_explosive(nx, ny, n_id)

func _check_neighbors_for_reaction(x, y, is_heat):
	var my_id = _get_cell(x, y)
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var n_id = _get_cell(nx, ny)
			if n_id > 0:
				var n_idx = ny * grid_width + nx; var n_tags = material_tags_raw[n_id]
				if (my_id == 11 and n_id == 2) or (my_id == 2 and n_id == 11): _set_cell(x, y, 12); _set_cell(nx, ny, 12); return
				var my_tags = tags_array[y * grid_width + x]
				if (my_tags & SandboxMaterial.Tags.ACID):
					# If neighbor is NOT empty and NOT acid and NOT anti-acid
					if n_id > 0 and n_id != 13 and !(n_tags & SandboxMaterial.Tags.ANTI_ACID):
						if randf() < 0.6: # Faster melting speed
							_set_cell(nx, ny, 0) # Dissolve neighbor
							if randf() < 0.05: _set_cell(x, y, 0)
							return
				if is_heat:
					if (n_tags & SandboxMaterial.Tags.FLAMMABLE):
						if n_id == 14: continue
						if randf() < 0.8:
							if n_id == 18: _set_cell(nx, ny, 19); charge_array[n_idx] = randi_range(20, 70)
							elif (n_tags & SandboxMaterial.Tags.BURN_COAL): _set_cell(nx, ny, 14 if randf() < 0.5 else 3)
							elif (n_tags & SandboxMaterial.Tags.BURN_SMOKE):
								if _get_cell(nx, ny - 1) == 0: _set_cell(nx, ny - 1, 15)
								if randf() < 0.1: _set_cell(nx, ny, 3)
								else: _set_cell(nx, ny, 0)
							else: _set_cell(nx, ny, 3)
					elif (n_tags & SandboxMaterial.Tags.EXPLOSIVE):
						if n_id == 27: _set_cell(nx, ny, 29); charge_array[nx + ny * grid_width] = randi_range(80, 120)
						elif n_id == 18: _set_cell(nx, ny, 19); charge_array[n_idx] = randi_range(20, 70)
						else:
							# Hierarchy: Acid (64) > Electric (128) > Heat (0)
							var f = 64 if (my_tags & SandboxMaterial.Tags.ACID) else (128 if my_id == 9 else 0)
							_prime_explosive(nx, ny, n_id, f)
				else:
					if (n_tags & SandboxMaterial.Tags.CONDUCTOR) and charge_array[n_idx] == 0: charge_array[n_idx] = 101
					elif (n_tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED):
						if n_id == 27: _set_cell(nx, ny, 29); charge_array[n_idx] = randi_range(80, 120)
						elif n_id == 18: _set_cell(nx, ny, 19); charge_array[n_idx] = randi_range(20, 70)
						else:
							var f = 64 if (my_tags & SandboxMaterial.Tags.ACID) else 128
							_prime_explosive(nx, ny, n_id, f)

var explosions_this_frame = 0
func _explode(x, y, radius, sfx_action: String = "explosion", ignition_flags = 0):
	explosions_this_frame += 1
	var is_heavy_load = explosions_this_frame > 10
	_set_cell(x, y, 0); _play_action_sound(sfx_action)
	var center = Vector2i(x, y)
	var nearby = _get_nearby_npcs(x, y, radius + 5)
	for npc in nearby:
		var dist = Vector2(npc.pos).distance_to(Vector2(center))
		if dist < radius:
			var ratio = 1.0 - (dist / radius); npc.hp -= ratio * 120.0; npc.hit_flash = 12; npc.hit_type = "explosive"
			var blast_dir = (Vector2(npc.pos) - Vector2(center)).normalized()
			if blast_dir.length() < 0.1: blast_dir = Vector2.UP
			npc.vx = blast_dir.x * ratio * 15.0; npc.vy = blast_dir.y * ratio * 15.0 - 6.0
			for _s in range(5): _add_spark(float(npc.pos.x),float(npc.pos.y),randf_range(-50,50),randf_range(-80,0),Color.DARK_GRAY,0.6)
	for ry in range(-radius, radius):
		for rx in range(-radius, radius):
			var dist_sq = rx*rx + ry*ry
			if dist_sq <= radius*radius:
				var tx = x + rx; var ty = y + ry; var t_id = _get_cell(tx, ty)
				if t_id <= 0: continue
				var t_idx = ty * grid_width + tx; var t_tags = tags_array[t_idx]
				if (t_tags & SandboxMaterial.Tags.EXPLOSIVE):
					if t_id == 27: 
						_set_cell(tx, ty, 29)
						var ci = tx + ty * grid_width
						charge_array[ci] = randi_range(80, 120)
						_register_charge(ci)
					else: _prime_explosive(tx, ty, t_id, ignition_flags)
					continue
				if (t_tags & SandboxMaterial.Tags.ANTI_EXPLOSIVE): continue
				if dist_sq < (radius * 0.4) ** 2: _set_cell(tx, ty, 0) 
				else:
					var prob = 0.15 if is_heavy_load else 0.45
					if randf() < prob: _push_particle(tx, ty, rx, ry)
	if ignition_flags & 128:
		for i in range(12 if is_heavy_load else 25):
			var dist = randi_range(2, 5); var ang = randf() * TAU; var sx = x + int(cos(ang) * dist); var sy = y + int(sin(ang) * dist)
			if sx >= 0 and sx < grid_width and sy >= 0 and sy < dynamic_grid_height:
				if _get_cell(sx, sy) == 0:
					_set_cell(sx, sy, 43); _activate_chunk(sx, sy)
					var deg = rad_to_deg(ang); if deg < 0: deg += 360
					var dir_idx = int((deg + 22.5 + 90) / 45) % 8
					var c_idx = sy * grid_width + sx
					charge_array[c_idx] = (31 << 3) | dir_idx
					_register_charge(c_idx)
	
	# 2. CORROSIVE DROPS EFFECT (If ACID BIT 64 is set)
	if ignition_flags & 64:
		var drop_count = 20 if is_heavy_load else 45
		for i in range(drop_count):
			var dist = randi_range(2, 7); var ang = randf() * TAU
			var sx = x + int(cos(ang) * dist); var sy = y + int(sin(ang) * dist)
			if sx >= 0 and sx < grid_width and sy >= 0 and sy < dynamic_grid_height:
				if _get_cell(sx, sy) == 0:
					_set_cell(sx, sy, 44) # Acid Projectile (Turns into ID 13 on hit)
					_activate_chunk(sx, sy)
					var deg = rad_to_deg(ang); if deg < 0: deg += 360
					var dir_idx = int((deg + 22.5 + 90) / 45) % 8
					charge_array[sy * grid_width + sx] = (randi_range(20, 31) << 3) | dir_idx
		
		# TOXIC SMOKE: Add clouds of corrosive gas
		for i in range(12 if is_heavy_load else 25):
			var dist = randi_range(1, radius - 2); var ang = randf() * TAU
			var sx = x + int(cos(ang) * dist); var sy = y + int(sin(ang) * dist)
			if sx >= 0 and sx < grid_width and sy >= 0 and sy < dynamic_grid_height:
				if _get_cell(sx, sy) == 0: _set_cell(sx, sy, 15)

func _push_particle(x, y, dx, dy):
	var dir_x = sign(dx); var dir_y = -1 if dy < 0 else (1 if dy > 0 else 0)
	var tx = x + dir_x * 2; var ty = y + dir_y * 2
	if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
		if _get_cell(tx, ty) == 0: _swap_cells(x, y, tx, ty)

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
	for i in range(MAX_VISUAL_SPARKS):
		var life = vs_life[i]
		if life <= 0.2: continue # Marker for active
		
		var sx = int(vs_x[i]); var sy = int(vs_y[i])
		if sx >= 0 and sx < grid_width and sy >= 0 and sy < grid_height:
			var sc = vs_color[i]; sc.a = life
			sc.b = max(0.02, sc.b) # Visual Marker
			img.set_pixel(sx, sy, sc)
			
	for fw in active_fireworks:
		var fx = int(fw.x); var fy = int(fw.y)
		if fx >= 0 and fx < grid_width and fy >= 0 and fy < grid_height:
			var fc = fw.color
			fc.b = max(0.02, fc.b) # Bypass ID lookup (Visual Marker)
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
			_add_spark(float(fw.x) + randf_range(-1.2, 1.2), float(fw.y + 1), randf_range(-10, 10), randf_range(20, 50), trail_colors[randi() % trail_colors.size()], randf_range(0.2, 0.6))
			
		# Check if reached altitude or safe boundary
		if fw.y <= fw.target_y or fw.y < 15:
			_explode_firework(int(fw.x), int(fw.y), fw.color) # Use the locked color!
			to_remove.append(i)
	
	to_remove.reverse()
	for i in to_remove:
		active_fireworks.remove_at(i)

func _add_spark(px, py, p_vx, p_vy, p_color, p_life):
	vs_x[vs_ptr] = px; vs_y[vs_ptr] = py; vs_vx[vs_ptr] = p_vx; vs_vy[vs_ptr] = p_vy
	vs_color[vs_ptr] = p_color; vs_life[vs_ptr] = p_life
	vs_ptr = (vs_ptr + 1) % MAX_VISUAL_SPARKS

func _update_visual_sparks(delta):
	for i in range(MAX_VISUAL_SPARKS):
		if vs_life[i] <= 0: continue
		vs_x[i] += vs_vx[i] * delta
		vs_y[i] += vs_vy[i] * delta
		vs_vy[i] += 30.0 * delta
		vs_life[i] -= 1.3 * delta

func _explode_firework(ex, ey, p_color):
	_play_action_sound("firework_burst")
	# Randomized explosion scale (Reduced max to 1/3 of previous)
	var size_mult = randf_range(0.4, 0.9) 
	var spark_count = int(100 * size_mult)  # High density!
	
	# Create GHOST particles (Visual only) 
	for i in range(spark_count):
		var ang = randf() * TAU
		var force = randf_range(20, 60) * size_mult # Slower, compact expansion
		_add_spark(float(ex), float(ey), cos(ang) * force, sin(ang) * force, p_color, randf_range(1.0, 1.8))

func _clear_all():
	cells.fill(0)
	charge_array.fill(0)
	tags_array.fill(0)
	surface_cache.fill(0)
	active_npcs.clear()
	active_projectiles.clear()
	vs_life.fill(0.0)
	active_charge_indices.clear()
	next_charge_indices.clear()
	charge_queued_frame.fill(-1)
	
	_reset_all_disasters() # Optimized & Scalable reset
	
	_update_texture()
	_update_material_highlights()
	_update_menu_highlights()

func _reset_all_disasters():
	current_weather = 0
	earthquake_intensity = 0; earthquake_timer = 0.0
	tornado_intensity = 0; tornado_timer = 0.0
	tsunami_intensity = 0; tsunami_timer = 0.0
	
	# Future/Upcoming Resets
	acid_rain_intensity = 0
	lava_rain_intensity = 0
	meteor_storm_intensity = 0
	black_hole_intensity = 0
	sinkhole_intensity = 0
	sand_storm_intensity = 0
	
	# Stop all looping players
	if is_instance_valid(weather_player) and weather_player.playing: weather_player.stop()
	if is_instance_valid(quake_player) and quake_player.playing: quake_player.stop()
	if is_instance_valid(tornado_player) and tornado_player.playing: tornado_player.stop()
	if is_instance_valid(tsunami_player) and tsunami_player.playing: tsunami_player.stop()
	if is_instance_valid(volcano_loop_player) and volcano_loop_player.playing: volcano_loop_player.stop()
