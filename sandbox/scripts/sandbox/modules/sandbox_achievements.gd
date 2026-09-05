extends Node
class_name SandboxAchievementManager

## Módulo especializado en la gestión integral del sistema de logros.
## Administra las definiciones maestras de 22 logros, persistencia en disco,
## sincronización con Google Play Games y Firebase Analytics, polling distribuido,
## secuencias cinemáticas de desbloqueo, cartel toast animado y el menú modal de trofeos.

# Referencia al nodo central de la cuadrícula
var grid: Node = null

# --- CONSTANTES DE INTEGRACIÓN Y ASSETS ---
const GOOGLE_PLAY_ACHIEVEMENTS = {
	"massive_fight": "CgkIx9-23rkFEAIQAA",
	"electrifying": "CgkIx9-23rkFEAIQAQ",
	"miner_plan": "CgkIx9-23rkFEAIQAg",
	"god": "CgkIx9-23rkFEAIQAw",
	"mad_scientist": "CgkIx9-23rkFEAIQBA",
	"paint": "CgkIx9-23rkFEAIQBQ",
	"party_rock": "CgkIx9-23rkFEAIQBg",
	"wind_master": "CgkIx9-23rkFEAIQBw",
	"compositor": "CgkIx9-23rkFEAIQCA",
	"tsunami_master": "CgkIx9-23rkFEAIQCQ",
	"retro_time": "CgkIx9-23rkFEAIQCg",
	"good_night": "CgkIx9-23rkFEAIQCw",
	"volcano_giant": "CgkIx9-23rkFEAIQDA",
	"boom": "CgkIx9-23rkFEAIQDQ",
	"special_boom": "CgkIx9-23rkFEAIQDg",
	"short_circuit": "CgkIx9-23rkFEAIQDw",
	"world_war": "CgkIx9-23rkFEAIQEA",
	"supreme_alchemist": "CgkIx9-23rkFEAIQEQ",
	"war-z": "CgkIx9-23rkFEAIQEw",
	"patient-zero": "CgkIx9-23rkFEAIQFA",
	"dancing-rain": "CgkIx9-23rkFEAIQFQ",
	"great-bomber": "CgkIx9-23rkFEAIQFg"
}

const ACHIEVEMENT_ICONS = {
	"massive_fight": "res://assets/icon_ach/ach_massive_fight.png",
	"electrifying": "res://assets/icon_ach/ach_electrifying.png",
	"miner_plan": "res://assets/icon_ach/ach_miner_plan.png",
	"god": "res://assets/icon_ach/ach_god.png",
	"mad_scientist": "res://assets/icon_ach/ach_mad_scientist.png",
	"paint": "res://assets/icon_ach/ach_pain.png",
	"party_rock": "res://assets/icon_ach/ach_party_rock.png",
	"wind_master": "res://assets/icon_ach/ach_wind_master.png",
	"compositor": "res://assets/icon_ach/ach_compositor.png",
	"tsunami_master": "res://assets/icon_ach/ach_tsunami_master.png",
	"retro_time": "res://assets/icon_ach/ach_retro_time.png",
	"good_night": "res://assets/icon_ach/ach_good_night.png",
	"volcano_giant": "res://assets/icon_ach/ach_volcano.png",
	"boom": "res://assets/icon_ach/ach_boom.png",
	"special_boom": "res://assets/icon_ach/ach_special_boom.png",
	"short_circuit": "res://assets/icon_ach/ach_short_circui.png",
	"world_war": "res://assets/icon_ach/ach_world_war.png",
	"supreme_alchemist": "res://assets/icon_ach/ach_alchemist.png",
	"war-z": "res://assets/icon_ach/ach_war-z.png",
	"patient-zero": "res://assets/icon_ach/ach_patient-zero.png",
	"dancing-rain": "res://assets/icon_ach/ach_dancing-rain.png",
	"great-bomber": "res://assets/icon_ach/ach_great-bomber.png"
}

# --- DICCIONARIO MAESTRO DE LOGROS ---
var achievements: Dictionary = {
	"massive_fight": {
		"id": "massive_fight",
		"title": "ach_massive_fight_title",
		"desc": "ach_massive_fight_desc",
		"unlocked": false,
		"seen": true
	},
	"electrifying": {
		"id": "electrifying",
		"title": "ach_electrifying_title",
		"desc": "ach_electrifying_desc",
		"unlocked": false,
		"seen": true
	},
	"miner_plan": {
		"id": "miner_plan",
		"title": "ach_miner_plan_title",
		"desc": "ach_miner_plan_desc",
		"unlocked": false,
		"seen": true
	},
	"god": {
		"id": "god",
		"title": "ach_god_title",
		"desc": "ach_god_desc",
		"unlocked": false,
		"seen": true
	},
	"mad_scientist": {
		"id": "mad_scientist",
		"title": "ach_mad_scientist_title",
		"desc": "ach_mad_scientist_desc",
		"unlocked": false,
		"seen": true
	},
	"paint": {
		"id": "paint",
		"title": "ach_paint_title",
		"desc": "ach_paint_desc",
		"unlocked": false,
		"seen": true
	},
	"party_rock": {
		"id": "party_rock",
		"title": "ach_party_rock_title",
		"desc": "ach_party_rock_desc",
		"unlocked": false,
		"seen": true
	},
	"wind_master": {
		"id": "wind_master",
		"title": "ach_wind_master_title",
		"desc": "ach_wind_master_desc",
		"unlocked": false,
		"seen": true,
		"discovered": []
	},
	"compositor": {
		"id": "compositor",
		"title": "ach_compositor_title",
		"desc": "ach_compositor_desc",
		"unlocked": false,
		"seen": true
	},
	"tsunami_master": {
		"id": "tsunami_master",
		"title": "ach_tsunami_master_title",
		"desc": "ach_tsunami_master_desc",
		"unlocked": false,
		"seen": true
	},
	"retro_time": {
		"id": "retro_time",
		"title": "ach_retro_time_title",
		"desc": "ach_retro_time_desc",
		"unlocked": false,
		"seen": true
	},
	"good_night": {
		"id": "good_night",
		"title": "ach_good_night_title",
		"desc": "ach_good_night_desc",
		"unlocked": false,
		"seen": true
	},
	"volcano_giant": {
		"id": "volcano_giant",
		"title": "ach_volcano_title",
		"desc": "ach_volcano_desc",
		"unlocked": false,
		"seen": true
	},
	"boom": {
		"id": "boom",
		"title": "ach_boom_title",
		"desc": "ach_boom_desc",
		"unlocked": false,
		"seen": true
	},
	"special_boom": {
		"id": "special_boom",
		"title": "ach_special_boom_title",
		"desc": "ach_special_boom_desc",
		"unlocked": false,
		"seen": true
	},
	"short_circuit": {
		"id": "short_circuit",
		"title": "ach_short_circuit_title",
		"desc": "ach_short_circuit_desc",
		"unlocked": false,
		"seen": true
	},
	"world_war": {
		"id": "world_war",
		"title": "ach_world_war_title",
		"desc": "ach_world_war_desc",
		"unlocked": false,
		"seen": true
	},
	"supreme_alchemist": {
		"id": "supreme_alchemist",
		"title": "ach_alchemist_title",
		"desc": "ach_alchemist_desc",
		"unlocked": false,
		"seen": true
	},
	"war-z": {
		"id": "war-z",
		"title": "ach_war-z_title",
		"desc": "ach_war-z_desc",
		"unlocked": false,
		"seen": true
	},
	"patient-zero": {
		"id": "patient-zero",
		"title": "ach_patient-zero_title",
		"desc": "ach_patient-zero_desc",
		"unlocked": false,
		"seen": true
	},
	"dancing-rain": {
		"id": "dancing-rain",
		"title": "ach_dancing-rain_title",
		"desc": "ach_dancing-rain_desc",
		"unlocked": false,
		"seen": true
	},
	"great-bomber": {
		"id": "great-bomber",
		"title": "ach_great-bomber_title",
		"desc": "ach_great-bomber_desc",
		"unlocked": false,
		"seen": true
	}
}

# --- VARIABLES DE ESTADO Y POLLING ---
var achievement_check_timer: float = 0.0
var achievement_sequence_step: int = -1 # -1: Idle, 0+: Grupo actual en evaluación

# Rastreo de explosiones en cadena de TNT
var _tnt_chain_count: int = 0
var _tnt_chain_flags: int = 0
var _tnt_chain_timer: float = 0.0

# Rastreo de notas musicales
var composition_note_count: int = 0
var last_note_play_time: float = 0.0

# Referencias a elementos UI
var achievement_panel: PanelContainer = null
var achievement_btn: Button = null
var achievement_pulse_tween: Tween = null
var play_games_achievements_client = null

# Estado local del menú desbloqueado (sincronizado con SandboxGrid.is_achievement_menu_unlocked)
var is_menu_unlocked: bool = false


func setup(p_grid: Node) -> void:
	grid = p_grid
	load_global_achievements()
	_setup_play_games_client()

func _setup_play_games_client() -> void:
	if OS.has_feature("android") and Engine.has_singleton("GodotPlayGameServices"):
		var gps = grid.get_node_or_null("/root/GodotPlayGameServices")
		if gps:
			var init_status = gps.initialize()
			if init_status == 0: # PlayGamesPluginError.OK
				play_games_achievements_client = PlayGamesAchievementsClient.new()
				add_child(play_games_achievements_client)
				print("Google Play Games Services client successfully setup in SandboxAchievementManager!")

## Guarda el estado global de logros en disco (user://achievements.cfg)
func save_global_achievements() -> void:
	var config = ConfigFile.new()
	config.set_value("progression", "achievements_unlocked_menu", is_menu_unlocked)
	
	var unlocked_list = []
	var seen_list = []
	for id in achievements:
		if achievements[id].unlocked:
			unlocked_list.append(id)
			if achievements[id].get("seen", false):
				seen_list.append(id)
		
		# Guardar progreso extra (como tipos de tornado descubiertos)
		if achievements[id].has("discovered"):
			config.set_value("progression", "ach_data_" + id, achievements[id].discovered)
			
	config.set_value("progression", "unlocked_ids", unlocked_list)
	config.set_value("progression", "seen_ids", seen_list)
	config.save("user://achievements.cfg")
	
	# Sincronizar flag estático en SandboxGrid si existe
	if grid and "is_achievement_menu_unlocked" in grid:
		grid.is_achievement_menu_unlocked = is_menu_unlocked
	
	# Si todo está visto, detener el pulso del botón
	if not has_unseen_achievements():
		if is_instance_valid(achievement_pulse_tween):
			achievement_pulse_tween.kill()
			achievement_pulse_tween = null
		if is_instance_valid(achievement_btn):
			achievement_btn.modulate = Color.WHITE

## Comprueba si hay logros desbloqueados que el usuario aún no ha visto
func has_unseen_achievements() -> bool:
	for id in achievements:
		if achievements[id].unlocked and not achievements[id].get("seen", false):
			return true
	return false

## Carga el estado global de logros desde disco al iniciar
func load_global_achievements() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://achievements.cfg")
	if err == OK:
		is_menu_unlocked = config.get_value("progression", "achievements_unlocked_menu", false)
		if grid and "is_achievement_menu_unlocked" in grid:
			grid.is_achievement_menu_unlocked = is_menu_unlocked
			
		var unlocked_list = config.get_value("progression", "unlocked_ids", [])
		var seen_list = config.get_value("progression", "seen_ids", [])
		for id in achievements:
			if id in unlocked_list:
				achievements[id].unlocked = true
			if id in seen_list:
				achievements[id].seen = true
			elif achievements[id].unlocked:
				achievements[id].seen = false # Desbloqueado pero no visto
			
			# Cargar datos de progreso extra
			if achievements[id].has("discovered"):
				achievements[id].discovered = config.get_value("progression", "ach_data_" + id, [])

## Actualiza temporizadores y orquesta la secuencia de evaluación escalonada
func check_achievement_conditions(delta: float) -> void:
	if not grid: return
	
	# Actualizar temporizador de cadena de TNT
	if _tnt_chain_timer > 0:
		_tnt_chain_timer -= delta
		if _tnt_chain_timer <= 0:
			_tnt_chain_timer = 0
			_tnt_chain_count = 0
			_tnt_chain_flags = 0
	
	achievement_check_timer += delta
	if achievement_check_timer >= 2.0:
		achievement_check_timer = 0.0
		achievement_sequence_step = 0 # Iniciar secuencia
	
	if achievement_sequence_step != -1:
		check_achievement_step(achievement_sequence_step)
		achievement_sequence_step += 1
		if achievement_sequence_step >= 13: # 13 grupos en total (0 a 12)
			achievement_sequence_step = -1 # Fin de secuencia

## Ejecuta la comprobación específica de un grupo escalonado de logros
func check_achievement_step(step: int) -> void:
	if not grid: return
	
	match step:
		0: # --- GRUPO 0: COMBATE E INTERACCIÓN ---
			if not achievements["massive_fight"].unlocked:
				var teams = {}
				for npc in grid.active_npcs:
					if npc.hp > 0:
						teams[npc.team] = teams.get(npc.team, 0) + 1
				var valid_teams = 0
				for t_id in teams:
					if teams[t_id] >= 10: valid_teams += 1
				if valid_teams >= 2: unlock_achievement("massive_fight")
			
			if not achievements["party_rock"].unlocked:
				var team_counts = {}
				for npc in grid.active_npcs:
					if npc.hp > 0 and npc.get("dance_timer", 0.0) > 0 and npc.get("recently_celebrated", false):
						var t = npc.team
						team_counts[t] = team_counts.get(t, 0) + 1
				for t_id in team_counts:
					if team_counts[t_id] >= 20:
						unlock_achievement("party_rock")
						break
					
			if not achievements["electrifying"].unlocked:
				for y in range(0, grid.dynamic_grid_height, 4):
					for x in range(0, grid.grid_width, 4):
						var idx = y * grid.grid_width + x
						if (grid.cells[idx] & 0xFF) == 2 and grid.charge_array[idx] > 0:
							unlock_achievement("electrifying")
							return

		1: # --- GRUPO 1: THE HEAVY SCAN (GOD MODE) ---
			if not achievements["god"].unlocked:
				var req = [1, 2, 3, 5, 6, 8, 9, 10, 11, 12, 13, 16, 4, 18, 20, 21, 24, 25, 26, 27, 70]
				var found = {}
				for y in range(0, grid.dynamic_grid_height, 4):
					for x in range(0, grid.grid_width, 4):
						var pid = grid.cells[y * grid.grid_width + x] & 0xFF
						if pid in req:
							found[pid] = true
							if found.size() >= req.size():
								unlock_achievement("god")
								return

		2: # --- GRUPO 2: ARTÍSTICO (PAINT) ---
			if not achievements["paint"].unlocked:
				var bg_colors = {}
				var el_colors = {}
				
				for y in range(0, grid.dynamic_grid_height, 4):
					for x in range(0, grid.grid_width, 4):
						var idx = y * grid.grid_width + x
						var el_c = grid.cell_paint_colors[idx]
						if el_c != 0: 
							el_colors[el_c] = true
						
						var bg_c = grid.background_img.get_pixel(x, y)
						if bg_c.a > 0.1 and (bg_c.r > 0.02 or bg_c.g > 0.02 or bg_c.b > 0.02):
							bg_colors[bg_c.to_html(false).left(6)] = true
						
						if el_colors.size() >= 4 and bg_colors.size() >= 4:
							unlock_achievement("paint")
							return

		3: # --- GRUPO 3: DESASTRES (TSUNAMI) ---
			if not achievements["tsunami_master"].unlocked and grid.tsunami_intensity > 0:
				var target_liquids = [2, 4, 11, 13] # Agua, Petróleo, Lava, Ácido
				var found = {}
				for y in range(0, grid.dynamic_grid_height, 4):
					for x in range(0, grid.grid_width, 4):
						var pid = grid.cells[y * grid.grid_width + x] & 0xFFFF
						if pid in target_liquids:
							found[pid] = true
							if found.size() >= 4:
								unlock_achievement("tsunami_master")
								return

		4: # --- GRUPO 4: PACÍFICO (DORMIR) ---
			if not achievements["good_night"].unlocked:
				var sleep_count = 0
				for npc in grid.active_npcs:
					if npc.hp > 0 and npc.get("is_lying", false) and npc.get("current_emoji", "") == "😴":
						sleep_count += 1
						if sleep_count >= 12:
							unlock_achievement("good_night")
							return

		5: # --- GRUPO 5: VOLCÁN (GIANT'S AWAKENING) ---
			if not achievements["volcano_giant"].unlocked and grid.is_volcano_active:
				var volcano_pixels = 0
				for y in range(0, grid.dynamic_grid_height, 2):
					for x in range(0, grid.grid_width, 2):
						var pid = grid.cells[y * grid.grid_width + x] & 0xFFFF
						if pid == 27 or pid == 29:
							volcano_pixels += 4 # Ponderado para muestreo 2x2
							if volcano_pixels >= 700:
								unlock_achievement("volcano_giant")
								return

		6: # --- GRUPO 6: EXPLOSIONES (BOOM & SPECIAL) ---
			if not achievements["boom"].unlocked and _tnt_chain_count >= 20:
				unlock_achievement("boom")
			
			if not achievements["special_boom"].unlocked and _tnt_chain_count >= 25:
				var has_acid = (_tnt_chain_flags & 64) > 0
				var has_elec = (_tnt_chain_flags & 128) > 0
				if has_acid and has_elec:
					unlock_achievement("special_boom")
					
		7: # --- GRUPO 7: ELECTRICIDAD (SHORT CIRCUIT) ---
			if not achievements["short_circuit"].unlocked:
				var electric_count = 0
				for npc in grid.active_npcs:
					if npc.hp > 0 and npc.get("hit_flash", 0) > 0 and npc.get("hit_type", "") == "electric":
						electric_count += 1
						if electric_count >= 10:
							unlock_achievement("short_circuit")
							return

		8: # --- GRUPO 8: SOCIAL (WORLD WAR) ---
			if not achievements["world_war"].unlocked:
				var team_counts = {0: 0, 1: 0, 2: 0, 3: 0}
				for npc in grid.active_npcs:
					if npc.hp > 0:
						team_counts[npc.team] = team_counts.get(npc.team, 0) + 1
				if team_counts[0] >= 5 and team_counts[1] >= 5 and team_counts[2] >= 5 and team_counts[3] >= 5:
					unlock_achievement("world_war")

		9: # --- GRUPO 9: LABORATORIO (SUPREME ALCHEMIST) ---
			if not achievements["supreme_alchemist"].unlocked:
				var lab_found = {}
				for y in range(0, grid.dynamic_grid_height, 4):
					for x in range(0, grid.grid_width, 4):
						var pid = grid.cells[y * grid.grid_width + x] & 0xFFFF
						if pid >= 900 and pid <= 902:
							lab_found[pid] = true
							if lab_found.size() >= 3:
								unlock_achievement("supreme_alchemist")
								return

		10: # --- GRUPO 10: WAR-Z ---
			if not achievements["war-z"].unlocked:
				var zombie_count = 0
				var zombie_tank_count = 0
				var team_counts = {0: 0, 1: 0, 2: 0, 3: 0}
				for npc in grid.active_npcs:
					if npc.hp > 0:
						if npc.type == "zombie":
							zombie_count += 1
						elif npc.type == "zombie_tank":
							zombie_tank_count += 1
						elif npc.team >= 0 and npc.team < 4:
							team_counts[npc.team] += 1
				if zombie_count >= 3 and zombie_tank_count >= 3 and team_counts[0] >= 3 and team_counts[1] >= 3 and team_counts[2] >= 3 and team_counts[3] >= 3:
					unlock_achievement("war-z")

		11: # --- GRUPO 11: DANCING RAIN ---
			if not achievements["dancing-rain"].unlocked and grid.acid_rain_intensity > 0:
				for npc in grid.active_npcs:
					if npc.hp > 0:
						unlock_achievement("dancing-rain")
						break

		12: # --- GRUPO 12: GREAT BOMBER ---
			if not achievements["great-bomber"].unlocked and grid.bombardero_intensity == 3:
				unlock_achievement("great-bomber")

## Desbloquea el logro 'retro_time' con retardo tras tomar control de un NPC
func unlock_retro_time_delayed() -> void:
	if not grid: return
	await get_tree().create_timer(2.0).timeout
	if grid.controlled_npc:
		grid._stop_controlling_npc()
	unlock_achievement("retro_time")

## Desbloquea un logro específico, lo persiste, notifica y sincroniza con servicios
func unlock_achievement(id: String) -> void:
	if not achievements.has(id) or achievements[id].unlocked: return
	
	achievements[id].unlocked = true
	achievements[id].seen = false # Marcar como nuevo (no visto)
	save_global_achievements()
	show_achievement_notification(id)
	
	# Registrar evento en Firebase Analytics
	AnalyticsManager.log_event("achievement_unlocked", {"id": id, "title": achievements[id].get("title", "")})
	
	# Comprobar si todos los logros fueron desbloqueados
	var all_unlocked = true
	for ach_id in achievements:
		if not achievements[ach_id].unlocked:
			all_unlocked = false
			break
			
	if all_unlocked:
		var config = ConfigFile.new()
		config.load("user://achievements.cfg")
		if not config.get_value("progression", "all_achievements_logged", false):
			AnalyticsManager.log_event("all_achievements_unlocked", {})
			config.set_value("progression", "all_achievements_logged", true)
			config.save("user://achievements.cfg")
	
	# Sincronizar con Google Play Games Services en Android
	if play_games_achievements_client and GOOGLE_PLAY_ACHIEVEMENTS.has(id):
		play_games_achievements_client.unlock_achievement(GOOGLE_PLAY_ACHIEVEMENTS[id])

## Registra el descubrimiento de un tipo de tornado elemental (para wind_master)
func record_tornado_discovery(type: int) -> void:
	if not achievements.has("wind_master"): return
	
	if typeof(achievements["wind_master"]["discovered"]) != TYPE_ARRAY:
		achievements["wind_master"]["discovered"] = []
		
	var disc = achievements["wind_master"]["discovered"]
	
	if not (int(type) in disc):
		disc.append(int(type))
		save_global_achievements()

	if disc.size() >= 4 and not achievements["wind_master"].unlocked:
		unlock_achievement("wind_master")

# ==============================================================================
# --- MÉTODOS DE INTERFAZ DE USUARIO (UI) Y NOTIFICACIONES ---
# ==============================================================================

## Configura el botón de logros en la barra de acciones
func setup_achievement_button(fixed_w: float, h_cat: float) -> Button:
	if not grid: return null
	
	# Aplicar ancho fijo a los botones existentes
	for child in grid.action_hbox.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(fixed_w, h_cat)
			child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			child.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Limpiar tween previo antes de reemplazar referencia
	if is_instance_valid(achievement_btn):
		if achievement_btn.has_meta("pulse_tween"):
			var old_tw = achievement_btn.get_meta("pulse_tween")
			if is_instance_valid(old_tw): old_tw.kill()
		achievement_btn.modulate = Color(1, 1, 1, 1)

	achievement_btn = grid._create_vertical_category_btn("🏆", "achievement_btn")
	achievement_btn.name = "AchievementBtn"
	achievement_btn.custom_minimum_size = Vector2(fixed_w * 2.0, h_cat)
	achievement_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	achievement_btn.visible = true
	achievement_btn.pressed.connect(setup_achievement_menu)
	
	var gold_style = StyleBoxFlat.new()
	gold_style.bg_color = Color("#D4AF37")
	gold_style.border_width_left = 2; gold_style.border_width_top = 2
	gold_style.border_width_right = 2; gold_style.border_width_bottom = 2
	gold_style.border_color = Color("#FFFACD")
	gold_style.set_corner_radius_all(0)
	gold_style.content_margin_top = 0; gold_style.content_margin_bottom = 0
	
	achievement_btn.add_theme_stylebox_override("normal", gold_style)
	achievement_btn.add_theme_stylebox_override("hover", gold_style)
	achievement_btn.add_theme_stylebox_override("pressed", gold_style)
	achievement_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	grid.action_hbox.add_child(achievement_btn)
	
	var is_menu_open = is_instance_valid(achievement_panel) and achievement_panel.visible
	if has_unseen_achievements() and not is_menu_open:
		if is_instance_valid(achievement_pulse_tween): 
			achievement_pulse_tween.kill()
		achievement_pulse_tween = achievement_btn.create_tween().set_loops()
		achievement_pulse_tween.tween_property(achievement_btn, "modulate", Color(1.3, 1.3, 1.1, 1.0), 0.8)
		achievement_pulse_tween.tween_property(achievement_btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)
	else:
		if is_instance_valid(achievement_pulse_tween): 
			achievement_pulse_tween.kill()
			achievement_pulse_tween = null
		achievement_btn.modulate = Color.WHITE
		
	return achievement_btn

## Secuencia cinemática de revelación del botón dorado 🏆 por primera vez
func trigger_achievement_reveal() -> void:
	if not grid: return
	
	var screen_w = grid.get_viewport_rect().size.x
	var s = grid._get_ui_scale()
	var h_cat = 60 * s
	var fixed_w = (screen_w - (5 * 2 * s)) / 6.0
	
	for child in grid.action_hbox.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(fixed_w, h_cat)
			child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			child.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Desbloquear y persistir
	is_menu_unlocked = true
	save_global_achievements()
	
	# Construir botón animado
	var achievement_btn_new = grid._create_vertical_category_btn("🏆", "achievement_btn")
	achievement_btn_new.name = "AchievementButton"
	achievement_btn_new.custom_minimum_size = Vector2(fixed_w * 2.0, h_cat)
	achievement_btn_new.modulate.a = 0
	achievement_btn_new.pressed.connect(setup_achievement_menu)
	achievement_btn = achievement_btn_new
	grid.action_hbox.add_child(achievement_btn_new)
	
	var gold_style = StyleBoxFlat.new()
	gold_style.bg_color = Color("#D4AF37")
	gold_style.set_corner_radius_all(0)
	achievement_btn_new.add_theme_stylebox_override("normal", gold_style)
	achievement_btn_new.add_theme_stylebox_override("hover", gold_style)
	achievement_btn_new.add_theme_stylebox_override("pressed", gold_style)
	
	# Secuencia de audio cinemático
	var p = AudioStreamPlayer.new()
	p.stream = grid._get_sfx_stream("achievement_menu_unlock")
	p.bus = "Master"
	p.volume_db = -80
	grid.get_tree().root.add_child(p)
	p.play()
	var audio_t = create_tween()
	audio_t.tween_property(p, "volume_db", 5.0, 0.4)
	audio_t.tween_interval(2.5)
	audio_t.tween_property(p, "volume_db", -80.0, 1.2)
	audio_t.finished.connect(p.queue_free)
	
	var scroll_t = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	scroll_t.tween_property(grid.action_scroll, "scroll_horizontal", 2000, 1.5)
	await scroll_t.finished
	
	# Fade-in del botón
	var fade_t = create_tween().bind_node(achievement_btn_new).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_t.tween_property(achievement_btn_new, "modulate:a", 1.0, 0.6)
	
	# Pulso de atención
	if is_instance_valid(achievement_pulse_tween): achievement_pulse_tween.kill()
	achievement_pulse_tween = create_tween().set_loops().bind_node(achievement_btn_new)
	achievement_pulse_tween.tween_property(achievement_btn_new, "modulate", Color(1.3, 1.3, 1.1, 1.0), 0.8)
	achievement_pulse_tween.tween_property(achievement_btn_new, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)
	
	await fade_t.finished

## Muestra la notificación toast animada al desbloquear un logro
func show_achievement_notification(id: String) -> void:
	if not grid: return
	
	var s = grid._get_ui_scale()
	var viewport_w = grid.get_viewport_rect().size.x
	
	var a = achievements[id]
	var title = a.title
	
	# 1. Asegurar que el menú esté visible
	if not is_menu_unlocked:
		await trigger_achievement_reveal()
		await get_tree().create_timer(1.0).timeout
	else:
		var scroll_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		scroll_tween.tween_property(grid.action_scroll, "scroll_horizontal", 2000, 1.0)
		await scroll_tween.finished
	
	# 2. Dimensiones y capa superior
	var icon_size = 75 * s
	var origin_pos = Vector2(viewport_w - 100 * s, grid.get_viewport_rect().size.y - 40 * s)
	if is_instance_valid(achievement_btn):
		origin_pos = achievement_btn.global_position + achievement_btn.size / 2.0
		var is_menu_open = is_instance_valid(achievement_panel) and achievement_panel.visible
		if not is_menu_open:
			if is_instance_valid(achievement_pulse_tween): achievement_pulse_tween.kill()
			achievement_pulse_tween = achievement_btn.create_tween().set_loops()
			achievement_pulse_tween.tween_property(achievement_btn, "modulate", Color(1.3, 1.3, 1.1, 1.0), 0.8)
			achievement_pulse_tween.tween_property(achievement_btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)
	
	var toast_layer = CanvasLayer.new()
	toast_layer.layer = 100
	grid.ui_root.add_child(toast_layer)
	
	# 3. Construcción del Toast UI
	var icon_container = Control.new()
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(icon_container)
	
	var icon_tex = TextureRect.new()
	if ACHIEVEMENT_ICONS.has(id):
		icon_tex.texture = load(ACHIEVEMENT_ICONS[id])
	else:
		icon_tex.texture = load("res://assets/icon_game/icono_google_sandbox.png")
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_tex.position = -icon_tex.custom_minimum_size / 2.0
	icon_container.add_child(icon_tex)
	
	var origin_x_right = origin_pos.x + icon_size / 2.0
	var margin = viewport_w - origin_x_right
	var final_w = viewport_w - 2.0 * margin
	var target_x = margin
	
	var mask = Control.new()
	mask.clip_contents = true
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(mask)
	toast_layer.move_child(mask, 0)
	
	var static_content = Control.new()
	static_content.size = Vector2(final_w, icon_size)
	mask.add_child(static_content)
	
	var bg = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.95)
	style.border_width_left = 3 * s; style.border_width_top = 3 * s
	style.border_width_right = 3 * s; style.border_width_bottom = 3 * s
	style.border_color = Color("#D4AF37")
	bg.add_theme_stylebox_override("panel", style)
	bg.size = static_content.size
	static_content.add_child(bg)
	
	var label = Label.new()
	label.text = tr(title).to_upper()
	label.add_theme_font_size_override("font_size", 24 * s)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(final_w - icon_size, icon_size)
	label.position = Vector2(icon_size, 0)
	static_content.add_child(label)
	
	var target_y = origin_pos.y - 150 * s
	icon_container.global_position = origin_pos
	icon_container.scale = Vector2.ZERO
	icon_container.modulate.a = 0
	mask.visible = false
	mask.size = Vector2(0, icon_size)
	mask.global_position = Vector2(origin_x_right, target_y - icon_size / 2.0)
	
	# 4. Secuencia de Animación
	var t1 = create_tween().bind_node(toast_layer).set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t1.tween_property(icon_container, "scale", Vector2.ONE, 0.5)
	t1.tween_property(icon_container, "modulate:a", 1.0, 0.3)
	t1.tween_property(icon_container, "global_position:y", target_y, 0.6)
	grid._play_achievement_unlock_sfx(false)
	await t1.finished
	
	await get_tree().create_timer(0.2).timeout
	mask.visible = true
	
	var t2 = create_tween().bind_node(toast_layer).set_parallel(true).set_trans(Tween.TRANS_EXPO)
	t2.tween_property(icon_container, "global_position:x", target_x + icon_size / 2.0, 1.0)
	t2.tween_property(mask, "global_position:x", target_x, 1.0)
	t2.tween_property(mask, "size:x", final_w, 1.0)
	t2.tween_property(static_content, "position:x", 0, 1.0).from(final_w)
	await t2.finished
	
	# Mantener en pantalla para legibilidad
	await get_tree().create_timer(1.5).timeout
	
	var t3 = create_tween().bind_node(toast_layer).set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t3.tween_property(icon_container, "global_position:y", grid.get_viewport_rect().size.y + 200 * s, 0.8)
	t3.tween_property(mask, "global_position:y", grid.get_viewport_rect().size.y + 200 * s, 0.8)
	t3.tween_property(icon_container, "modulate:a", 0.0, 0.5)
	t3.tween_property(mask, "modulate:a", 0.0, 0.5)
	await t3.finished
	
	if is_instance_valid(toast_layer):
		toast_layer.queue_free()

## Despliega o cierra el menú modal de logros
func setup_achievement_menu() -> void:
	if not grid: return
	grid._play_action_sound("ui_click")
	
	# Detener pulso del botón
	if is_instance_valid(achievement_pulse_tween):
		achievement_pulse_tween.kill()
		achievement_pulse_tween = null
	
	if is_instance_valid(achievement_btn):
		var kill_tw = create_tween()
		kill_tw.tween_property(achievement_btn, "modulate", Color(1, 1, 1, 1), 0.1)
		achievement_btn.modulate = Color(1, 1, 1, 1)

	var s = grid._get_ui_scale()
	
	# Toggle: si ya está abierto, cerrarlo
	if is_instance_valid(achievement_panel) and achievement_panel.visible:
		achievement_panel.visible = false
		grid._update_menu_highlights()
		return
		
	# Marcar todos los logros como vistos
	var changed = false
	for id in achievements:
		if achievements[id].unlocked and not achievements[id].get("seen", false):
			achievements[id].seen = true
			changed = true
	if changed:
		save_global_achievements()
		
	grid._toggle_category_panel(null) # Cerrar otros paneles abiertos
	
	# Crear panel si no existe aún
	if not is_instance_valid(achievement_panel):
		achievement_panel = PanelContainer.new()
		grid.ui_root.add_child(achievement_panel)
		achievement_panel.mouse_entered.connect(func(): grid.is_mouse_over_ui = true)
		achievement_panel.mouse_exited.connect(func(): grid.is_mouse_over_ui = false)
		
		var p_style = StyleBoxFlat.new()
		p_style.bg_color = Color(0.12, 0.12, 0.14, 0.98)
		p_style.corner_radius_top_left = 20 * s
		p_style.corner_radius_top_right = 20 * s
		p_style.corner_radius_bottom_left = 0
		p_style.corner_radius_bottom_right = 0
		p_style.set_border_width_all(4 * s)
		p_style.border_color = Color(0.35, 0.35, 0.4)
		achievement_panel.add_theme_stylebox_override("panel", p_style)
		
		grid._align_panel_to_hud(achievement_panel, 600 * s, 500 * s)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", int(35 * s))
		margin.add_theme_constant_override("margin_right", int(35 * s))
		margin.add_theme_constant_override("margin_top", int(20 * s))
		margin.add_theme_constant_override("margin_bottom", int(20 * s))
		achievement_panel.add_child(margin)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 15 * s)
		margin.add_child(vbox)
		
		# Cabecera
		var title = Label.new()
		title.name = "AchievementMenuTitle"
		title.text = tr("achievement_menu_title")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
		title.add_theme_font_size_override("font_size", 32 * s)
		title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		vbox.add_child(title)
		
		var scroll = ScrollContainer.new()
		scroll.name = "AchieveScroll"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(scroll)
		
		var item_vbox = VBoxContainer.new()
		item_vbox.name = "AchieveList"
		item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_vbox.add_theme_constant_override("separation", 10 * s)
		scroll.add_child(item_vbox)

	# Mostrar panel y refrescar lista reutilizando nodos para evitar stutter
	achievement_panel.visible = true
	
	var menu_title = achievement_panel.find_child("AchievementMenuTitle", true, false)
	if is_instance_valid(menu_title):
		menu_title.text = tr("achievement_menu_title")

	var list = achievement_panel.find_child("AchieveList", true, false)
	var existing_items = list.get_children()
	var idx = 0
	for id in achievements:
		var a = achievements[id]
		var item: PanelContainer
		
		if idx < existing_items.size():
			item = existing_items[idx]
		else:
			item = PanelContainer.new()
			item.custom_minimum_size.y = 100 * s
			item.mouse_filter = Control.MOUSE_FILTER_PASS
			item.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
					if event.pressed:
						item.set_meta("press_pos", event.global_position)
					else:
						var start_pos = item.get_meta("press_pos", event.global_position)
						var dist = start_pos.distance_to(event.global_position)
						if dist < 12 * s:
							var ach_id = item.get_meta("achievement_id", "")
							if ach_id != "":
								on_achievement_item_clicked(ach_id)
			)
			list.add_child(item)
			
			var i_margin = MarginContainer.new()
			var im_val = int(12 * s)
			i_margin.add_theme_constant_override("margin_left", int(20 * s))
			i_margin.add_theme_constant_override("margin_right", im_val)
			i_margin.add_theme_constant_override("margin_top", im_val)
			i_margin.add_theme_constant_override("margin_bottom", im_val)
			item.add_child(i_margin)
			
			var i_hbox = HBoxContainer.new()
			i_hbox.add_theme_constant_override("separation", 22 * s)
			i_margin.add_child(i_hbox)
			
			var icon_container = Control.new()
			icon_container.name = "IconContainer"
			icon_container.custom_minimum_size = Vector2(75 * s, 75 * s)
			i_hbox.add_child(icon_container)
			
			var new_icon_tex = TextureRect.new()
			new_icon_tex.name = "IconTexture"
			new_icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			new_icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			new_icon_tex.size = Vector2(75 * s, 75 * s)
			icon_container.add_child(new_icon_tex)
			
			var new_lock_label = Label.new()
			new_lock_label.name = "LockLabel"
			new_lock_label.text = "🔒"
			new_lock_label.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
			new_lock_label.add_theme_font_size_override("font_size", 24 * s)
			new_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			new_lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			new_lock_label.size = Vector2(75 * s, 75 * s)
			icon_container.add_child(new_lock_label)
			
			var text_vbox = VBoxContainer.new()
			text_vbox.name = "TextVBox"
			text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			text_vbox.add_theme_constant_override("separation", 2 * s)
			i_hbox.add_child(text_vbox)
			
			var new_title = Label.new()
			new_title.name = "Title"
			new_title.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
			text_vbox.add_child(new_title)
			
			var new_desc = Label.new()
			new_desc.name = "Desc"
			new_desc.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
			text_vbox.add_child(new_desc)
		
		# Actualizar estado visual
		item.set_meta("achievement_id", id)
		var icon_tex = item.find_child("IconTexture", true, false)
		var lock_label = item.find_child("LockLabel", true, false)
		var a_title = item.find_child("Title", true, false)
		var a_desc = item.find_child("Desc", true, false)
		
		if icon_tex and ACHIEVEMENT_ICONS.has(id):
			icon_tex.texture = load(ACHIEVEMENT_ICONS[id])
			if a.unlocked:
				icon_tex.modulate = Color.WHITE
				if lock_label: lock_label.visible = false
			else:
				icon_tex.modulate = Color(0.08, 0.08, 0.08, 0.85)
				if lock_label: lock_label.visible = true
		
		a_title.text = tr(a.title)
		a_title.add_theme_font_size_override("font_size", 22 * s)
		
		var i_style = StyleBoxFlat.new()
		i_style.set_corner_radius_all(12 * s)
		
		if a.unlocked:
			i_style.bg_color = Color(0.85, 0.65, 0.2, 0.15)
			i_style.set_border_width_all(2 * s)
			i_style.border_color = Color(0.9, 0.75, 0.3, 0.8)
			a_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
			a_title.modulate.a = 1.0
			
			a_desc.text = tr(a.desc)
			a_desc.visible = true
			a_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			a_desc.add_theme_font_size_override("font_size", 16 * s)
			a_desc.modulate = Color(1, 0.95, 0.8, 0.9)
		else:
			i_style.bg_color = Color(0.18, 0.18, 0.2, 0.6)
			i_style.set_border_width_all(1 * s)
			i_style.border_color = Color(0.3, 0.3, 0.35, 0.4)
			a_title.remove_theme_color_override("font_color")
			a_title.modulate.a = 0.4
			
			var hint_key = a.desc.replace("_desc", "_hint")
			a_desc.text = tr(hint_key)
			a_desc.visible = true
			a_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			a_desc.add_theme_font_size_override("font_size", 16 * s)
			a_desc.modulate = Color(0.55, 0.55, 0.6, 0.65)
			
		item.add_theme_stylebox_override("panel", i_style)
		idx += 1

	grid._update_menu_highlights()

## Muestra la ventana modal emergente con detalles ampliados del logro
func on_achievement_item_clicked(ach_id: String) -> void:
	if not grid: return
	if not achievements.has(ach_id) or not achievements[ach_id].unlocked:
		return
	
	grid._play_action_sound("ui_click")
	var s = grid._get_ui_scale()
	var screen_size = grid.get_viewport_rect().size
	
	# Overlay de pantalla completa
	var overlay = Control.new()
	overlay.name = "AchievementDetailPopup"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.ui_root.add_child(overlay)
	
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	
	# Cerrar al tocar el fondo oscuro
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			grid._play_action_sound("ui_click")
			overlay.queue_free()
	)
	
	# Panel de detalle
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.1, 0.1, 0.15, 0.96)
	p_style.set_border_width_all(int(4 * s))
	p_style.border_color = Color("#D4AF37")
	p_style.set_corner_radius_all(20 * s)
	panel.add_theme_stylebox_override("panel", p_style)
	overlay.add_child(panel)
	
	var marg = MarginContainer.new()
	var m_val = int(30 * s)
	marg.add_theme_constant_override("margin_top", m_val)
	marg.add_theme_constant_override("margin_bottom", m_val + int(20 * s))
	marg.add_theme_constant_override("margin_left", m_val)
	marg.add_theme_constant_override("margin_right", m_val)
	panel.add_child(marg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(18 * s))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	marg.add_child(vbox)
	
	var a = achievements[ach_id]
	
	# 1. Icono grande
	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(180 * s, 180 * s)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ACHIEVEMENT_ICONS.has(ach_id):
		icon_rect.texture = load(ACHIEVEMENT_ICONS[ach_id])
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon_rect)
	
	# 2. Título (Dorado)
	var title_lbl = Label.new()
	title_lbl.text = tr(a.title)
	title_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", int(26 * s))
	title_lbl.add_theme_color_override("font_color", Color("#D4AF37"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(320 * s, 0)
	vbox.add_child(title_lbl)
	
	# 3. Pista (Gris)
	var hint_lbl = Label.new()
	var hint_key = a.desc.replace("_desc", "_hint")
	hint_lbl.text = tr(hint_key)
	hint_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	hint_lbl.add_theme_font_size_override("font_size", int(18 * s))
	hint_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.custom_minimum_size = Vector2(320 * s, 0)
	vbox.add_child(hint_lbl)
	
	# 4. Descripción completa (Dorado)
	var desc_lbl = Label.new()
	desc_lbl.text = tr(a.desc)
	desc_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	desc_lbl.add_theme_font_size_override("font_size", int(22 * s))
	desc_lbl.add_theme_color_override("font_color", Color("#D4AF37"))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(320 * s, 0)
	vbox.add_child(desc_lbl)
	
	# Botón OK de cierre
	var close_btn = Button.new()
	close_btn.text = "OK"
	close_btn.custom_minimum_size = Vector2(120 * s, 50 * s)
	close_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	close_btn.add_theme_font_size_override("font_size", int(22 * s))
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	btn_style.set_border_width_all(int(2 * s))
	btn_style.border_color = Color("#D4AF37")
	btn_style.set_corner_radius_all(10 * s)
	close_btn.add_theme_stylebox_override("normal", btn_style)
	close_btn.add_theme_stylebox_override("hover", btn_style)
	close_btn.add_theme_stylebox_override("pressed", btn_style)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func():
		grid._play_action_sound("ui_click")
		overlay.queue_free()
	)
	vbox.add_child(close_btn)
	
	# Etiqueta de posición (Esquina inferior derecha)
	var keys = achievements.keys()
	var total = keys.size()
	var pos = keys.find(ach_id) + 1
	
	var corner_margin = MarginContainer.new()
	corner_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	corner_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner_margin.add_theme_constant_override("margin_right", int(15 * s))
	corner_margin.add_theme_constant_override("margin_bottom", int(10 * s))
	panel.add_child(corner_margin)
	
	var pos_lbl = Label.new()
	pos_lbl.text = tr("ACHIEVEMENT_POSITION_FORMAT").format([pos, total])
	pos_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	pos_lbl.add_theme_font_size_override("font_size", int(14 * s))
	pos_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	pos_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	pos_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	corner_margin.add_child(pos_lbl)
	
	# Centrar en pantalla
	await get_tree().process_frame
	var p_size = panel.get_combined_minimum_size()
	panel.position = (screen_size - p_size) / 2.0
