class_name SandboxMusicSystem
extends Node

## Módulo 6: SandboxMusicSystem
## Gestiona el sistema musical cromático, instrumentos afinados (4 pianos, batería, metrónomo),
## pool de polifonía de 32 canales en bus dedicado "MusicBus" con limitador dinámico,
## colocación e inspección de bloques melódicos (IDs 500+ y 600),
## interacción con pulsos eléctricos y animaciones de baile para NPCs.

# Referencia al nodo principal del simulador
var grid: Node = null

# Constantes del sistema musical
const MUSIC_ID_START = 500
const MUSIC_INSTRUMENTS = ["piano1", "piano2", "piano3", "piano4", "drums", "metronome"]
const MUSIC_INST_COLORS = [
	Color("#D652FF"),
	Color("#5E7FFF"),
	Color("#C0B8FF"),
	Color("#1FDDFF"),
	Color("#FFC31F"),
	Color("#E0BB87")
]
const MUSIC_NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const MUSIC_NOTES_LATIN = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]
const MUSIC_PITCHES = [1.0, 1.05946, 1.12246, 1.18921, 1.25992, 1.33483, 1.41421, 1.49831, 1.58740, 1.68179, 1.78180, 1.88775]

# Estado e instrumentos
var selected_music_instrument: int = 0
var selected_music_octave: int = 2
var selected_music_note: int = 0
var show_music_notes_popup: bool = true
var music_inspect_active: bool = false
var music_inspect_timer: float = 0.0
var pending_music_draw_pos: Vector2i = Vector2i(-1, -1)
var played_music_this_frame: Dictionary = {}
var music_block_cooldowns: Dictionary = {}
var music_tempo_frames: int = 30 # Sincronización de BPM del metrónomo (60 FPS base)

# Pool de polifonía de audio
var music_player_pool: Array[AudioStreamPlayer] = []
var music_next_idx: int = 0

# Estado del panel visual
var music_panel: PanelContainer = null
var selected_mechanism_tab: int = 0 # 0: Circuits, 1: Music


func setup(p_grid: Node) -> void:
	grid = p_grid
	init_audio_bus_and_pool()
	register_musical_materials()


# =========================================================================
# MÉTODOS AUXILIARES SEGUROS
# =========================================================================

func _get_ui_scale() -> float:
	if is_instance_valid(grid) and grid.has_method("_get_ui_scale"):
		return grid._get_ui_scale()
	return 1.0


func _get_safe_font() -> Font:
	if is_instance_valid(grid) and grid.has_method("_get_safe_font"):
		return grid._get_safe_font()
	return SandboxFontHelper.get_safe_font()


func _get_ui_root() -> CanvasLayer:
	if is_instance_valid(grid):
		if is_instance_valid(grid.ui_root):
			return grid.ui_root
		var parent = grid.get_parent()
		if is_instance_valid(parent):
			var ui = parent.get_node_or_null("UI") as CanvasLayer
			if is_instance_valid(ui):
				grid.ui_root = ui
				return ui
	return null


func _play_action_sound_safe(sound_name: String) -> void:
	if is_instance_valid(grid) and grid.has_method("_play_action_sound"):
		grid._play_action_sound(sound_name)


# =========================================================================
# GESTIÓN DEL BUS Y POOL DE POLIFONÍA
# =========================================================================

func init_audio_bus_and_pool() -> void:
	# 1. Crear bus dedicado "MusicBus" con limitador para prevenir saturación y distorsión
	var music_bus_idx = AudioServer.get_bus_index("MusicBus")
	if music_bus_idx == -1:
		music_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(music_bus_idx)
		AudioServer.set_bus_name(music_bus_idx, "MusicBus")
		var limiter = AudioEffectLimiter.new()
		limiter.ceiling_db = -0.5 # Prevenir recorte digital
		limiter.threshold_db = -2.0 # Compresión transparente en acordes masivos
		AudioServer.add_bus_effect(music_bus_idx, limiter)

	for player in music_player_pool:
		if is_instance_valid(player):
			player.queue_free()
	music_player_pool.clear()
	music_next_idx = 0

	# 2. Inicializar pool de polifonía de 32 reproductores independientes
	for i in range(32):
		var p = AudioStreamPlayer.new()
		p.bus = "MusicBus"
		add_child(p)
		music_player_pool.append(p)


func clear_frame_music() -> void:
	played_music_this_frame.clear()


# =========================================================================
# REGISTRO Y GESTIÓN DE MATERIALES MUSICALES
# =========================================================================

func register_musical_materials() -> void:
	if not is_instance_valid(grid): return
	# Registrar 5 conjuntos de instrumentos afinados (4 pianos + 1 batería)
	for inst in range(5):
		var base_color = MUSIC_INST_COLORS[inst]
		for note in range(16):
			var mat_id = MUSIC_ID_START + (inst * 16) + note
			var color = base_color
			var max_n = 15.0 if inst < 4 else 8.0 # 16 notas para piano, 9 para batería
			var factor = 0.4 + (float(note % int(max_n + 1)) / max_n) * 0.6
			color = base_color.darkened(1.0 - factor)
			
			grid._register_material(
				mat_id,
				color,
				SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.MUSIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.CONDUCTOR
			)
	
	# Registrar METRÓNOMO (ID 600) - Pulsos automáticos Neón Cyan
	grid._register_material(
		600,
		Color("#00F2FF"),
		SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.MUSIC
	)


func place_music_block(gx: int, gy: int, mat_id: int) -> void:
	if not is_instance_valid(grid): return
	# Coloca un bloque musical de 2x2 píxeles
	for oy in range(2):
		for ox in range(2):
			grid._set_cell(gx + ox, gy + oy, mat_id)


func get_music_data(id: int) -> Dictionary:
	var base_id = id
	var octave = 2
	if id >= 10000:
		octave = int(id / 10000) - 1
		base_id = id % 10000
	var inst = (base_id - MUSIC_ID_START) / 16
	var note = (base_id - MUSIC_ID_START) % 16
	
	if inst < 4 and note >= 12:
		octave += 1
		if note == 12: note = 0
		elif note == 13: note = 1
		elif note == 14: note = 2
		elif note >= 15: note = 4
		
	return {"inst": inst, "note": note, "octave": octave}


func encode_music_id(inst: int, note: int, octave: int) -> int:
	var base_id = MUSIC_ID_START + (inst * 16) + note
	if octave == 2: return base_id
	return ((octave + 1) * 10000) + base_id


func is_music_mat(mat_id: int) -> bool:
	if mat_id <= 0: return false
	if mat_id == 600: return true
	var base_id = mat_id & 0xFFFF
	if base_id >= 10000:
		base_id = base_id % 10000
	if base_id == 600: return true
	if base_id >= MUSIC_ID_START and base_id < (MUSIC_ID_START + (5 * 16)):
		return true
	if not is_instance_valid(grid): return false
	var tags_id = base_id
	if grid.has_method("_get_tags_id"):
		tags_id = grid._get_tags_id(mat_id)
	var raw_tags = grid.get("material_tags_raw")
	if raw_tags != null and tags_id >= 0 and tags_id < raw_tags.size():
		if (raw_tags[tags_id] & SandboxMaterial.Tags.MUSIC):
			return true
	return false


# =========================================================================
# REPRODUCCIÓN DE NOTAS Y COREOGRAFÍA DE NPCS
# =========================================================================

func play_music_note(inst_idx: int, note_idx: int, ignore_achievement: bool = false, octave: int = 2, b_idx: int = -1) -> void:
	if b_idx != -1:
		var current_time = Time.get_ticks_msec()
		if music_block_cooldowns.has(b_idx) and current_time - music_block_cooldowns[b_idx] < 150:
			return
		music_block_cooldowns[b_idx] = current_time

	var hash_key = str(inst_idx) + "_" + str(note_idx) + "_" + str(octave)
	if played_music_this_frame.has(hash_key):
		return
	played_music_this_frame[hash_key] = true
	
	if is_instance_valid(grid) and grid.get("sim_mutex") != null:
		grid.sim_mutex.lock()
	
	# Seguimiento de logro: Compositor (Excluye el Metrónomo)
	if inst_idx != 5 and not ignore_achievement and is_instance_valid(grid):
		var is_unlocked = false
		if grid.achievement_manager and grid.achievement_manager.achievements.has("compositor"):
			is_unlocked = grid.achievement_manager.achievements["compositor"].unlocked
		elif "achievements" in grid and grid.achievements.has("compositor"):
			is_unlocked = grid.achievements["compositor"].unlocked
			
		if not is_unlocked:
			var current_sec = Time.get_ticks_msec() / 1000.0
			var last_t = grid.get("last_note_play_time") if "last_note_play_time" in grid else 0.0
			var note_cnt = grid.get("composition_note_count") if "composition_note_count" in grid else 0
			if current_sec - last_t <= 1.0:
				note_cnt += 1
				if note_cnt >= 5:
					if grid.has_method("_unlock_achievement"):
						grid._unlock_achievement("compositor")
			else:
				note_cnt = 1
			grid.set("last_note_play_time", current_sec)
			grid.set("composition_note_count", note_cnt)
	
	var s_name = MUSIC_INSTRUMENTS[inst_idx]
	var p_scale = MUSIC_PITCHES[note_idx % 12]
	
	if inst_idx < 4:
		# Pianos: Muestreo múltiple (1 archivo de muestra por octava)
		var actual_octave = octave + 1
		s_name = s_name + "_oct" + str(actual_octave)
	elif inst_idx == 4: # Batería acústica
		var drum_keys = ["drum_kick", "drum_snare", "drum_hihat", "drum_tom", "drum_tom_low", "drum_tom_high", "drum_ride", "drum_crash", "drum_sticks"]
		s_name = drum_keys[note_idx % 9]
		p_scale = 1.0
	elif inst_idx == 5: # Metrónomo
		s_name = "ui_pop"
		p_scale = 2.0
		
	var stream = null
	if is_instance_valid(grid) and grid.has_method("_get_sfx_stream"):
		stream = grid._get_sfx_stream(s_name)
		
	if stream and music_player_pool.size() > 0:
		var p = music_player_pool[music_next_idx]
		music_next_idx = (music_next_idx + 1) % music_player_pool.size()
		if is_instance_valid(p):
			p.set_deferred("stream", stream)
			p.set_deferred("pitch_scale", p_scale)
			p.set_deferred("volume_db", -5.0) # Volumen equilibrado para polifonía de acordes
			p.call_deferred("play")
			trigger_npc_dance()
			
	if is_instance_valid(grid) and grid.get("sim_mutex") != null:
		grid.sim_mutex.unlock()


func trigger_npc_dance() -> void:
	if not is_instance_valid(grid): return
	var npcs = grid.get("active_npcs")
	if not (npcs is Array): return
	for npc in npcs:
		if npc.get("hp", 0) > 0:
			var rand_val = grid._get_lut_rand() if grid.has_method("_get_lut_rand") else randf()
			if rand_val < 0.85:
				npc["dance_timer"] = 3.5 
				npc["has_spotted_enemy"] = false 
				npc["recently_celebrated"] = false # El baile musical no cuenta como victoria bélica
				npc["celebration_mode"] = 3 # 3 = Sólo bailar
				var music_emojis = ["🎵", "🕺", "💃", "🎶"]
				if grid.has_method("_set_npc_emoji"):
					grid._set_npc_emoji(npc, music_emojis[randi() % music_emojis.size()], 3.5)


# =========================================================================
# INTERFAZ DE USUARIO: PANEL DUAL (CIRCUITOS Y MÚSICA)
# =========================================================================

func setup_music_ui(force_refresh: bool = false) -> void:
	if not is_instance_valid(grid): return
	grid._set_panning_mode(false)
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root): return
	
	# Cierre conmutado exclusivo si ya está abierto
	if not force_refresh and is_instance_valid(music_panel) and music_panel.visible:
		close_music_menu()
		return
		
	# Limpieza de paneles previos
	for child in ui_root.get_children():
		if child.name.begins_with("MusicMenuBlocker") or child.name.begins_with("MusicPanel") or child.name == "TO_DELETE":
			child.name = "TO_DELETE"
			child.hide()
			child.queue_free()
	grid.circuit_panel = null
	
	music_panel = PanelContainer.new()
	music_panel.name = "MusicPanel"
	ui_root.add_child(music_panel)
	
	grid.is_blocking = false
	
	var panel_style = StyleBoxFlat.new()
	if selected_mechanism_tab == 0:
		panel_style.bg_color = Color(0.06, 0.08, 0.12, 0.96) # Azul eléctrico oscuro
		panel_style.border_color = Color("#4169E1", 0.75) # Brillo real eléctrico
	else:
		panel_style.bg_color = Color(0.1, 0.07, 0.1, 0.95) # Púrpura melódico oscuro
		panel_style.border_color = Color(0.8, 0.1, 0.5, 0.6) # Brillo musical
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	music_panel.add_theme_stylebox_override("panel", panel_style)
	music_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Posicionamiento robusto idéntico al panel de herramientas
	var m_width = 530 * s
	var m_height = 655 * s
	if grid.is_inside_tree() and grid.get_viewport_rect().size.x > grid.get_viewport_rect().size.y:
		m_height = 570 * s
		
	music_panel.custom_minimum_size = Vector2(m_width, m_height)
	if grid.has_method("_align_panel_to_hud"):
		grid._align_panel_to_hud(music_panel, m_width, m_height)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.name = "OuterVBox"
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 10 * s)
	music_panel.add_child(outer_vbox)
	
	# Fila superior de pestañas (Circuitos y Música)
	var sub_tab_hbox = HBoxContainer.new()
	sub_tab_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_tab_hbox.add_theme_constant_override("separation", 8 * s)
	outer_vbox.add_child(sub_tab_hbox)
	
	for tab_idx in range(2):
		var tab_btn = Button.new()
		tab_btn.text = "⚡ " + tr("circuits_tab") if tab_idx == 0 else "🎵 " + tr("music_tab")
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.custom_minimum_size = Vector2(0, 52 * s)
		tab_btn.add_theme_font_override("font", _get_safe_font())
		tab_btn.add_theme_font_size_override("font_size", 18 * s)
		
		var t_style = StyleBoxFlat.new()
		t_style.set_corner_radius_all(10 * s)
		var base_col = Color("#4169E1") if tab_idx == 0 else Color("#9E1FFF")
		if tab_idx == selected_mechanism_tab:
			t_style.bg_color = base_col.darkened(0.2)
			t_style.border_width_bottom = 4
			t_style.border_color = Color.WHITE
		else:
			t_style.bg_color = base_col.darkened(0.7)
		tab_btn.add_theme_stylebox_override("normal", t_style)
		tab_btn.add_theme_stylebox_override("hover", t_style)
		tab_btn.add_theme_stylebox_override("pressed", t_style)
		
		var idx = tab_idx
		tab_btn.pressed.connect(func():
			_play_action_sound_safe("ui_click")
			selected_mechanism_tab = idx
			setup_music_ui(true)
		)
		sub_tab_hbox.add_child(tab_btn)
		
	# Poblar contenido según sub-pestaña seleccionada
	if selected_mechanism_tab == 0:
		_setup_circuits_tab(outer_vbox, s)
		return
		
	_setup_music_tab(outer_vbox, s)


func _setup_circuits_tab(outer_vbox: VBoxContainer, s: float) -> void:
	var circuit_panel = PanelContainer.new()
	circuit_panel.name = "CircuitPanel"
	circuit_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	circuit_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	circuit_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	circuit_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	outer_vbox.add_child(circuit_panel)
	grid.circuit_panel = circuit_panel
	
	var circ_scroll = ScrollContainer.new()
	circ_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	circ_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	circ_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	circuit_panel.add_child(circ_scroll)
	
	var circ_vbox = VBoxContainer.new()
	circ_vbox.add_theme_constant_override("separation", 15 * s)
	circ_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	circ_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	circ_scroll.add_child(circ_vbox)
	
	if grid.dialog_manager and grid.dialog_manager.has_method("show_menu_reminder"):
		grid.dialog_manager.show_menu_reminder("circuits", circ_vbox, "REMINDER_CIRCUITS")
	elif grid.has_method("_show_menu_reminder"):
		grid._show_menu_reminder("circuits", circ_vbox, "REMINDER_CIRCUITS")
	
	var title = Label.new()
	title.text = tr("circuits_tab")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 34 * s)
	circ_vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "Crea automatizaciones usando electricidad" if OS.get_locale_language() == "es" else "Create automation using electricity"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_override("font", _get_safe_font())
	desc.add_theme_font_size_override("font_size", 18 * s)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	circ_vbox.add_child(desc)
	
	var circ_grid = GridContainer.new()
	circ_grid.columns = 2
	circ_grid.add_theme_constant_override("h_separation", 12 * s)
	circ_grid.add_theme_constant_override("v_separation", 12 * s)
	circ_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	circ_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	circ_vbox.add_child(circ_grid)
	
	var circuit_items = ["metal", "tnt", "npc_act", "door", "phase_block", "battery", "led", "not", "and", "or", "nand", "nor", "xor", "xnor", "piston", "piston_ins", "cannon", "pipe", "pipe_x2"]
	var circuit_emojis = ["🔩", "🧨", "🔌", "🚪", "🌀", "🔋", "💡", "🔀", "🔀", "🔀", "🔀", "🔀", "🔀", "🔀", "⚙️", "🚫", "💣", "🔵", "🔵"]
	
	for i in range(circuit_items.size()):
		var item_key = circuit_items[i]
		var btn = Button.new()
		var btn_text = tr(item_key)
		if item_key == "piston_ins": btn_text = "Pist. Aislado"
		btn.text = circuit_emojis[i] + " " + btn_text
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 18 * s)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = Color("#4169E1").darkened(0.65)
		b_style.set_corner_radius_all(10 * s)
		btn.add_theme_stylebox_override("normal", b_style)
		btn.add_theme_stylebox_override("hover", b_style)
		btn.add_theme_stylebox_override("pressed", b_style)
		
		var container: Control = btn
		if item_key == "piston" or item_key == "piston_ins":
			var hbox = HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 4 * s)
			hbox.mouse_filter = Control.MOUSE_FILTER_PASS
			hbox.custom_minimum_size = Vector2(210 * s, 70 * s)
			
			btn.custom_minimum_size = Vector2(146 * s, 70 * s)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(btn)
			
			var val_btn = Button.new()
			val_btn.name = "PistonLengthBtn"
			val_btn.text = str(grid.selected_piston_length)
			val_btn.custom_minimum_size = Vector2(60 * s, 70 * s)
			val_btn.add_theme_font_override("font", _get_safe_font())
			val_btn.add_theme_font_size_override("font_size", 18 * s)
			val_btn.mouse_filter = Control.MOUSE_FILTER_PASS
			
			var v_style = StyleBoxFlat.new()
			v_style.bg_color = Color("#4169E1").darkened(0.5)
			v_style.set_corner_radius_all(10 * s)
			val_btn.add_theme_stylebox_override("normal", v_style)
			val_btn.add_theme_stylebox_override("hover", v_style)
			val_btn.add_theme_stylebox_override("pressed", v_style)
			
			val_btn.pressed.connect(func():
				_play_action_sound_safe("ui_click")
				var vals = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 35, 40]
				
				var popup = PopupPanel.new()
				var p_style = StyleBoxFlat.new()
				p_style.bg_color = Color("#2A2A35")
				p_style.set_corner_radius_all(15 * s)
				popup.add_theme_stylebox_override("panel", p_style)
				
				var vbox = VBoxContainer.new()
				vbox.add_theme_constant_override("separation", 20 * s)
				
				var title_lbl = Label.new()
				title_lbl.text = tr("PISTON_LENGTH")
				title_lbl.add_theme_font_override("font", _get_safe_font())
				title_lbl.add_theme_font_size_override("font_size", 32 * s)
				title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				vbox.add_child(title_lbl)
				
				var p_grid = GridContainer.new()
				p_grid.columns = 3
				p_grid.add_theme_constant_override("h_separation", 15 * s)
				p_grid.add_theme_constant_override("v_separation", 15 * s)
				
				for val in vals:
					var opt_btn = Button.new()
					opt_btn.text = str(val)
					opt_btn.custom_minimum_size = Vector2(90 * s, 90 * s)
					opt_btn.add_theme_font_override("font", _get_safe_font())
					opt_btn.add_theme_font_size_override("font_size", 36 * s)
					
					var opt_style = StyleBoxFlat.new()
					if is_instance_valid(grid) and val == grid.selected_piston_length:
						opt_style.bg_color = Color("#32CD32").darkened(0.2)
					else:
						opt_style.bg_color = Color("#4169E1").darkened(0.5)
					opt_style.set_corner_radius_all(12 * s)
					
					var hover_style = opt_style.duplicate()
					hover_style.bg_color = opt_style.bg_color.lightened(0.2)
					var pressed_style = opt_style.duplicate()
					pressed_style.bg_color = opt_style.bg_color.darkened(0.2)
					
					opt_btn.add_theme_stylebox_override("normal", opt_style)
					opt_btn.add_theme_stylebox_override("hover", hover_style)
					opt_btn.add_theme_stylebox_override("pressed", pressed_style)
					
					opt_btn.pressed.connect(func():
						_play_action_sound_safe("ui_click")
						if is_instance_valid(grid):
							grid.selected_piston_length = val
						val_btn.text = str(val)
						popup.hide()
					)
					p_grid.add_child(opt_btn)
				
				vbox.add_child(p_grid)
					
				var margin = MarginContainer.new()
				margin.add_theme_constant_override("margin_top", 20 * s)
				margin.add_theme_constant_override("margin_bottom", 20 * s)
				margin.add_theme_constant_override("margin_left", 20 * s)
				margin.add_theme_constant_override("margin_right", 20 * s)
				margin.add_child(vbox)
				
				popup.add_child(margin)
				get_tree().current_scene.add_child(popup)
				popup.popup_hide.connect(func(): popup.queue_free())
				
				var btn_rect = val_btn.get_global_rect()
				popup.popup(Rect2(btn_rect.position.x - (120 * s), btn_rect.position.y - (450 * s), 0, 0))
			)
			
			hbox.add_child(val_btn)
			container = hbox
		elif item_key == "led":
			var hbox = HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 4 * s)
			hbox.mouse_filter = Control.MOUSE_FILTER_PASS
			hbox.custom_minimum_size = Vector2(210 * s, 70 * s)
			
			btn.custom_minimum_size = Vector2(146 * s, 70 * s)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(btn)
			
			var color_btn = Button.new()
			color_btn.name = "LEDColorBtn"
			var led_emojis = ["🔴", "🔵", "🟢", "🟡", "⚪", "💗", "💠", "🌈"]
			var current_led_idx = grid.selected_led_color if is_instance_valid(grid) else 0
			color_btn.text = led_emojis[clampi(current_led_idx, 0, led_emojis.size() - 1)]
			color_btn.custom_minimum_size = Vector2(60 * s, 70 * s)
			color_btn.add_theme_font_override("font", _get_safe_font())
			color_btn.add_theme_font_size_override("font_size", 22 * s)
			color_btn.mouse_filter = Control.MOUSE_FILTER_PASS
			
			var v_style = StyleBoxFlat.new()
			v_style.bg_color = Color("#4169E1").darkened(0.5)
			v_style.set_corner_radius_all(10 * s)
			color_btn.add_theme_stylebox_override("normal", v_style)
			color_btn.add_theme_stylebox_override("hover", v_style)
			color_btn.add_theme_stylebox_override("pressed", v_style)
			
			color_btn.pressed.connect(func():
				_play_action_sound_safe("ui_click")
				if is_instance_valid(grid) and grid.has_method("_open_led_color_panel"):
					grid._open_led_color_panel(color_btn)
			)
			
			hbox.add_child(color_btn)
			container = hbox
		else:
			btn.custom_minimum_size = Vector2(210 * s, 70 * s)
		
		btn.pressed.connect(func():
			_play_action_sound_safe("ui_click")
			if not is_instance_valid(grid): return
			if item_key == "metal":
				grid.selected_material = 8
				grid.selected_circuit_tool = ""
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "tnt":
				grid.selected_material = 5
				grid.selected_circuit_tool = ""
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "battery":
				grid.selected_material = 88
				grid.selected_circuit_tool = ""
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "led":
				grid.selected_material = 89
				grid.selected_circuit_tool = ""
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "npc_act":
				grid.selected_material = 90
				grid.selected_circuit_tool = ""
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "door":
				grid.selected_material = 91
				grid.selected_circuit_tool = ""
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "phase_block":
				grid.selected_material = 92
				grid.selected_circuit_tool = ""
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "piston":
				grid.selected_material = 93
				grid.selected_circuit_tool = "piston"
				grid.is_piston_insulated = false
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "piston_ins":
				grid.selected_material = 93
				grid.selected_circuit_tool = "piston"
				grid.is_piston_insulated = true
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "cannon":
				grid.selected_material = 95
				grid.selected_circuit_tool = "cannon"
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "pipe":
				grid.selected_material = 96
				grid.selected_circuit_tool = "pipe"
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key == "pipe_x2":
				grid.selected_material = 97
				grid.selected_circuit_tool = "pipe_x2"
				grid.is_mechanism_mode_active = true
				close_music_menu()
			elif item_key in ["not", "and", "or", "nand", "nor", "xor", "xnor"]:
				grid.selected_material = -2
				grid.selected_circuit_tool = item_key
				grid.is_mechanism_mode_active = true
				close_music_menu()
		)
		circ_grid.add_child(container)


func _setup_music_tab(outer_vbox: VBoxContainer, s: float) -> void:
	var is_music_selected = is_music_mat(grid.selected_material if is_instance_valid(grid) else -1)
	var scroll = ScrollContainer.new()
	scroll.name = "MusicScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(scroll)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15 * s)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main_vbox)
	
	if grid.dialog_manager and grid.dialog_manager.has_method("show_menu_reminder"):
		grid.dialog_manager.show_menu_reminder("music", main_vbox, "REMINDER_MUSIC")
	elif grid.has_method("_show_menu_reminder"):
		grid._show_menu_reminder("music", main_vbox, "REMINDER_MUSIC")
	
	var title = Label.new()
	title.text = tr("music_tab")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 34 * s)
	main_vbox.add_child(title)
	
	# 1. Selector de instrumentos en cuadrícula de 3 columnas (2 filas)
	var inst_grid = GridContainer.new()
	inst_grid.columns = 3
	inst_grid.add_theme_constant_override("h_separation", 10 * s)
	inst_grid.add_theme_constant_override("v_separation", 10 * s)
	inst_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(inst_grid)
	
	for i in range(MUSIC_INSTRUMENTS.size()):
		var btn = Button.new()
		btn.text = tr(MUSIC_INSTRUMENTS[i])
		if i == 4: btn.add_theme_color_override("font_color", Color.BLACK)
		btn.custom_minimum_size = Vector2(160 * s, 60 * s)
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 18 * s)
		
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = MUSIC_INST_COLORS[i].darkened(0.6)
		b_style.set_corner_radius_all(10 * s)
		if is_music_selected and i == selected_music_instrument:
			b_style.border_width_bottom = 5
			b_style.border_color = Color.WHITE
			b_style.bg_color = MUSIC_INST_COLORS[i].darkened(0.2)
		btn.add_theme_stylebox_override("normal", b_style)
		btn.add_theme_stylebox_override("hover", b_style)
		btn.add_theme_stylebox_override("pressed", b_style)
		
		var idx = i
		btn.pressed.connect(func():
			_play_action_sound_safe("ui_click")
			selected_music_instrument = idx
			if idx == 5: # METRÓNOMO
				if is_instance_valid(grid):
					grid.selected_material = 600
			else:
				if is_instance_valid(grid):
					grid.selected_material = encode_music_id(idx, selected_music_note, selected_music_octave)
				play_music_note(selected_music_instrument, selected_music_note, true, selected_music_octave)
			setup_music_ui(true)
		)
		inst_grid.add_child(btn)
	
	# 2. Contenido según instrumento seleccionado
	if selected_music_instrument == 5:
		_setup_metronome_view(main_vbox, s)
	else:
		_setup_notes_view(main_vbox, s, is_music_selected)


func _setup_metronome_view(main_vbox: VBoxContainer, s: float) -> void:
	var metro_vbox = VBoxContainer.new()
	metro_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	metro_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(metro_vbox)
	
	var bpm_val = int(3600.0 / float(max(1, music_tempo_frames)))
	
	var bpm_edit = LineEdit.new()
	bpm_edit.text = str(bpm_val)
	bpm_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	bpm_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	bpm_edit.context_menu_enabled = false
	bpm_edit.add_theme_font_override("font", _get_safe_font())
	bpm_edit.add_theme_font_size_override("font_size", 54 * s)
	
	var edit_style = StyleBoxFlat.new()
	edit_style.bg_color = Color(0, 0, 0, 0.2)
	edit_style.set_corner_radius_all(10 * s)
	bpm_edit.add_theme_stylebox_override("normal", edit_style)
	bpm_edit.add_theme_stylebox_override("focus", edit_style)
	metro_vbox.add_child(bpm_edit)
	
	var bpm_slider = HSlider.new()
	bpm_slider.min_value = 1
	bpm_slider.max_value = 240
	bpm_slider.value = bpm_val
	bpm_slider.custom_minimum_size = Vector2(400 * s, 60 * s)
	bpm_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	bpm_slider.value_changed.connect(func(val):
		music_tempo_frames = int(3600.0 / float(val))
		bpm_edit.text = str(int(val))
	)
	
	bpm_edit.text_changed.connect(func(new_text):
		var filtered = ""
		for c in new_text:
			if c in "0123456789": filtered += c
		if filtered != new_text:
			bpm_edit.text = filtered
			bpm_edit.caret_column = filtered.length()
		
		if filtered.length() > 0:
			var val = clampi(int(filtered), 1, 240)
			music_tempo_frames = int(3600.0 / float(val))
			bpm_slider.value = val
	)
	
	metro_vbox.add_child(bpm_slider)
	
	var info = Label.new()
	info.text = tr("metronome_info")
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_override("font", _get_safe_font())
	info.add_theme_font_size_override("font_size", 22 * s)
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	metro_vbox.add_child(info)


func _setup_notes_view(main_vbox: VBoxContainer, s: float, is_music_selected: bool) -> void:
	var note_grid = GridContainer.new()
	var n_count = 12 if selected_music_instrument < 4 else 9
	note_grid.columns = 4 if selected_music_instrument < 4 else 3
	note_grid.add_theme_constant_override("h_separation", 8 * s)
	note_grid.add_theme_constant_override("v_separation", 8 * s)
	note_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(note_grid)
	
	var drum_names = ["drum_kick", "drum_snare", "drum_hihat", "drum_tom", "drum_tom_low", "drum_tom_high", "drum_ride", "drum_crash", "drum_sticks"]
	for i in range(n_count):
		var btn = Button.new()
		var b_size = 105 * s if selected_music_instrument < 4 else 140 * s
		btn.custom_minimum_size = Vector2(b_size, b_size)
		btn.add_theme_font_override("font", _get_safe_font())
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		if selected_music_instrument < 4:
			btn.text = "" 
			var v = VBoxContainer.new()
			v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			btn.add_child(v)
			
			var l1 = Label.new()
			l1.text = MUSIC_NOTES[i]
			l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l1.add_theme_font_override("font", _get_safe_font())
			l1.add_theme_font_size_override("font_size", 32 * s)
			v.add_child(l1)
			
			var l2 = Label.new()
			l2.text = MUSIC_NOTES_LATIN[i]
			l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l2.add_theme_font_override("font", _get_safe_font())
			l2.add_theme_font_size_override("font_size", 20 * s)
			l2.modulate = Color(1, 1, 1, 0.8)
			v.add_child(l2)
		else:
			btn.text = tr(drum_names[i])
			btn.add_theme_font_size_override("font_size", 20 * s if selected_music_instrument == 4 else 32 * s)
			if selected_music_instrument == 4:
				btn.add_theme_color_override("font_color", Color.BLACK)
		
		var base_color = MUSIC_INST_COLORS[selected_music_instrument]
		var max_n = float(n_count - 1)
		var factor = 0.4 + (float(i) / max_n) * 0.6
		var n_color = base_color.darkened(1.0 - factor)
		
		var n_style = StyleBoxFlat.new()
		n_style.bg_color = n_color
		n_style.set_corner_radius_all(12 * s)
		if is_music_selected and i == selected_music_note:
			n_style.border_width_left = 4; n_style.border_width_top = 4
			n_style.border_width_right = 4; n_style.border_width_bottom = 4
			n_style.border_color = Color.WHITE
		btn.add_theme_stylebox_override("normal", n_style)
		
		var nid = i
		btn.pressed.connect(func():
			selected_music_note = nid
			if is_instance_valid(grid):
				grid.selected_material = encode_music_id(selected_music_instrument, nid, selected_music_octave)
			play_music_note(selected_music_instrument, nid, true, selected_music_octave)
			setup_music_ui(true)
		)
		note_grid.add_child(btn)
		
	# Selector de octavas (sólo para los 4 pianos afinados)
	if selected_music_instrument < 4:
		var oct_hbox = HBoxContainer.new()
		oct_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		oct_hbox.add_theme_constant_override("separation", 15 * s)
		
		var m_margin = MarginContainer.new()
		m_margin.add_theme_constant_override("margin_top", 15 * s)
		m_margin.add_child(oct_hbox)
		main_vbox.add_child(m_margin)
		
		var oct_lbl = Label.new()
		oct_lbl.text = tr("octave_selection")
		oct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		oct_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		oct_lbl.add_theme_font_override("font", _get_safe_font())
		oct_lbl.add_theme_font_size_override("font_size", 22 * s)
		oct_hbox.add_child(oct_lbl)
		
		var oct_names = ["1ra", "2da", "3ra", "4ta", "5ta"]
		for i in range(oct_names.size()):
			var btn = Button.new()
			btn.text = oct_names[i]
			btn.add_theme_font_override("font", _get_safe_font())
			btn.add_theme_font_size_override("font_size", 20 * s)
			btn.custom_minimum_size = Vector2(65 * s, 50 * s)
			
			var base_color = MUSIC_INST_COLORS[selected_music_instrument]
			var max_o = 4.0
			var factor = 0.4 + (float(i) / max_o) * 0.6
			var o_color = base_color.darkened(1.0 - factor)
			
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = o_color
			b_style.set_corner_radius_all(8 * s)
			
			if is_music_selected and i == selected_music_octave:
				b_style.border_width_left = 3; b_style.border_width_top = 3
				b_style.border_width_right = 3; b_style.border_width_bottom = 3
				b_style.border_color = Color.WHITE
			
			btn.add_theme_stylebox_override("normal", b_style)
			btn.add_theme_stylebox_override("hover", b_style)
			btn.add_theme_stylebox_override("pressed", b_style)
			
			var o_idx = i
			btn.pressed.connect(func():
				selected_music_octave = o_idx
				if is_instance_valid(grid):
					grid.selected_material = encode_music_id(selected_music_instrument, selected_music_note, selected_music_octave)
				_play_action_sound_safe("ui_click")
				setup_music_ui(true)
			)
			oct_hbox.add_child(btn)
			
		# Conmutador para ver notas al pulsar
		var t_margin = MarginContainer.new()
		t_margin.add_theme_constant_override("margin_top", 10 * s)
		main_vbox.add_child(t_margin)
		
		var toggle_hbox = HBoxContainer.new()
		toggle_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		t_margin.add_child(toggle_hbox)
		
		var t_lbl = Label.new()
		t_lbl.text = tr("show_music_notes_popup")
		t_lbl.add_theme_font_override("font", _get_safe_font())
		t_lbl.add_theme_font_size_override("font_size", 20 * s)
		toggle_hbox.add_child(t_lbl)
		
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(10 * s, 0)
		toggle_hbox.add_child(spacer)
		
		var t_btn = Button.new()
		t_btn.text = tr("active") if show_music_notes_popup else tr("inactive")
		t_btn.add_theme_font_override("font", _get_safe_font())
		t_btn.add_theme_font_size_override("font_size", 20 * s)
		t_btn.custom_minimum_size = Vector2(120 * s, 40 * s)
		
		var t_style = StyleBoxFlat.new()
		t_style.bg_color = Color(0.2, 0.6, 0.3) if show_music_notes_popup else Color(0.6, 0.2, 0.2)
		t_style.set_corner_radius_all(8 * s)
		t_btn.add_theme_stylebox_override("normal", t_style)
		t_btn.add_theme_stylebox_override("hover", t_style)
		t_btn.add_theme_stylebox_override("pressed", t_style)
		
		t_btn.pressed.connect(func():
			show_music_notes_popup = not show_music_notes_popup
			_play_action_sound_safe("ui_click")
			if is_instance_valid(grid):
				if grid.tools_ui and grid.tools_ui.has_method("save_tool_settings"):
					grid.tools_ui.save_tool_settings()
				elif grid.has_method("_save_tool_settings"):
					grid._save_tool_settings()
			setup_music_ui(true)
		)
		toggle_hbox.add_child(t_btn)


func close_music_menu() -> void:
	if is_instance_valid(grid):
		grid.is_blocking = false
	var ui_root = _get_ui_root()
	if is_instance_valid(ui_root):
		for child in ui_root.get_children():
			if child.name.begins_with("MusicMenuBlocker") or child.name.begins_with("MusicPanel") or child.name == "TO_DELETE":
				child.queue_free()
	if is_instance_valid(grid):
		grid.circuit_panel = null
	music_panel = null
	
	if is_instance_valid(grid):
		if grid.has_method("_update_material_highlights"):
			grid._update_material_highlights()
		if grid.has_method("_update_menu_highlights"):
			grid._update_menu_highlights()
		if grid.has_method("_on_arcade_selection_made"):
			grid._on_arcade_selection_made(false)


func setup_music_button() -> Button:
	if not is_instance_valid(grid): return null
	var btn: Button = null
	if grid.has_method("_create_vertical_category_btn"):
		btn = grid._create_vertical_category_btn("⚙️", "music")
	else:
		btn = Button.new()
		btn.text = "⚙️"
	btn.name = "MusicBtn"
	grid.ui_elements["music_btn"] = btn
	
	var m_style = StyleBoxFlat.new()
	m_style.bg_color = Color("#9E1FFF").darkened(0.6)
	m_style.border_width_left = 1; m_style.border_width_top = 1
	m_style.border_width_right = 1; m_style.border_width_bottom = 1
	m_style.border_color = Color(0.4, 0.4, 0.5)
	m_style.set_corner_radius_all(0)
	
	btn.add_theme_stylebox_override("normal", m_style)
	btn.add_theme_stylebox_override("hover", m_style)
	btn.add_theme_stylebox_override("pressed", m_style)
	btn.add_theme_stylebox_override("focus", m_style)
	btn.set_meta("base_style", m_style)
	
	btn.pressed.connect(func():
		_play_action_sound_safe("ui_click")
		var was_open = is_instance_valid(music_panel) and music_panel.visible
		if is_instance_valid(grid):
			grid.is_paint_tool_active = false
			if grid.has_method("_close_all_popups"):
				grid._close_all_popups()
		if not was_open:
			setup_music_ui()
		if is_instance_valid(grid) and grid.has_method("_update_menu_highlights"):
			grid._update_menu_highlights()
	)
	
	if is_instance_valid(grid.action_hbox):
		grid.action_hbox.add_child(btn)
	grid.ui_elements["music_btn"] = btn
	return btn


func is_music_active() -> bool:
	if is_instance_valid(music_panel) and music_panel.visible:
		return true
	if is_instance_valid(grid) and grid.get("is_mechanism_mode_active"):
		return true
	return is_music_mat(grid.selected_material if is_instance_valid(grid) else 0)


# =========================================================================
# GESTIÓN DEL POPUP FLOTANTE DE NOTAS EN PANTALLA
# =========================================================================

func update_music_note_popup() -> void:
	if not is_instance_valid(grid): return
	var ui_root = _get_ui_root()
	var show_pop = false
	if show_music_notes_popup and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not grid.get("is_panning_mode") and not grid.get("touch_started_on_ui"):
		show_pop = true
		if music_inspect_active and music_inspect_timer < 0.6:
			show_pop = false
			
	if show_pop:
		var m_pos = grid.get_local_mouse_position()
		var g_scale = grid.get("grid_scale")
		var raw_gx = int(m_pos.x / g_scale)
		var raw_gy = int(m_pos.y / g_scale)
		var snap = 4
		var gx = int(floor(float(raw_gx) / snap) * snap) + 1
		var gy = int(floor(float(raw_gy) / snap) * snap) + 1
		
		var gw = grid.get("grid_width")
		var gh = grid.get("grid_height")
		if gx >= 0 and gx < gw and gy >= 0 and gy < gh:
			var cell_id = grid._get_cell(gx, gy)
			if is_music_mat(cell_id):
				var m_data = get_music_data(cell_id)
				var pop = null
				if is_instance_valid(ui_root): pop = ui_root.get_node_or_null("MusicNotePopup")
				if not pop and is_instance_valid(ui_root):
					pop = Label.new()
					pop.name = "MusicNotePopup"
					var style = StyleBoxFlat.new()
					style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
					style.set_corner_radius_all(12)
					style.content_margin_left = 20; style.content_margin_right = 20
					style.content_margin_top = 12; style.content_margin_bottom = 12
					style.border_width_left = 3; style.border_width_top = 3
					style.border_width_right = 3; style.border_width_bottom = 3
					style.border_color = Color(0.8, 0.2, 0.8, 0.8)
					pop.add_theme_stylebox_override("normal", style)
					pop.add_theme_font_override("font", _get_safe_font())
					pop.add_theme_font_size_override("font_size", int(32 * _get_ui_scale()))
					pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					ui_root.add_child(pop)
				
				if pop:
					pop.visible = true
					if cell_id == 600:
						pop.text = tr("metronome") if TranslationServer.get_locale() == "es" else "Metronome"
					elif m_data.inst == 4:
						var drum_keys = ["drum_kick", "drum_snare", "drum_hihat", "drum_tom", "drum_tom_low", "drum_tom_high", "drum_ride", "drum_crash", "drum_sticks"]
						if m_data.note < drum_keys.size():
							pop.text = tr(drum_keys[m_data.note])
						else:
							pop.text = "?"
					else:
						var note_names = ["C - Do", "C# - Do#", "D - Re", "D# - Re#", "E - Mi", "F - Fa", "F# - Fa#", "G - Sol", "G# - Sol#", "A - La", "A# - La#", "B - Si"]
						var octave_names = ["1ra", "2da", "3ra", "4ta", "5ta"]
						var n_str = note_names[m_data.note] if m_data.note < note_names.size() else "?"
						var o_str = octave_names[m_data.octave] if m_data.octave < octave_names.size() else "?"
						pop.text = o_str + " " + tr("octave") + "\n" + n_str
					
					var screen_pos = grid.get_viewport().get_mouse_position()
					var vp_size = grid.get_viewport_rect().size
					var p_size = pop.size
					if p_size.x == 0: p_size = pop.get_minimum_size()
					
					var target_y = screen_pos.y - p_size.y - 100 * _get_ui_scale()
					var target_x = screen_pos.x - p_size.x / 2.0
					
					if target_y < 10:
						target_y = max(10, screen_pos.y - p_size.y - 40 * _get_ui_scale())
						if screen_pos.x < vp_size.x / 2.0:
							target_x = screen_pos.x + 80 * _get_ui_scale()
						else:
							target_x = screen_pos.x - p_size.x - 80 * _get_ui_scale()
							
					target_x = clamp(target_x, 10, vp_size.x - p_size.x - 10)
					pop.position = Vector2(target_x, target_y)
			else:
				if is_instance_valid(ui_root):
					var pop = ui_root.get_node_or_null("MusicNotePopup")
					if pop: pop.visible = false
	else:
		if is_instance_valid(ui_root):
			var pop = ui_root.get_node_or_null("MusicNotePopup")
			if pop: pop.visible = false
