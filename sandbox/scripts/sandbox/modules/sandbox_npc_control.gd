class_name SandboxNpcControlManager
extends Node

# =========================================================================
# SandboxNpcControlManager (Módulo 10)
# =========================================================================
# Responsabilidades:
# 1. Gestionar la capa visual flotante NPCControlGUI (mando táctil / arcade).
# 2. Controlar la posesión de NPCs por parte del jugador (Hero Unit).
# 3. Procesar las entradas táctiles y analógicas del joystick virtual (Pad).
# 4. Ejecutar las acciones contextuales según la clase del NPC (guerrero,
#    zombi, tanque zombi arrojando rocas, arquero, médico, mago, minero).
# 5. Gestionar el botón dinámico central "MenuBtn" y sus etiquetas externas.
# 6. Facilitar la alternancia fluida entre el modo de construcción y el modo arcade.
# =========================================================================

var grid: Node = null

# Estado de control de NPCs
var controlled_npc = null
var is_selecting_npc_to_control: bool = false
var is_npc_mode_menu_open: bool = false
var npc_control_gui: Control = null


func setup(p_grid: Node) -> void:
	grid = p_grid


# =========================================================================
# MÉTODOS AUXILIARES DE ACCESO
# =========================================================================

func _get_ui_root() -> CanvasLayer:
	if is_instance_valid(grid):
		if "ui_root" in grid and is_instance_valid(grid.ui_root):
			return grid.ui_root
		var parent = grid.get_parent()
		if is_instance_valid(parent):
			var ui = parent.get_node_or_null("UI")
			if is_instance_valid(ui) and ui is CanvasLayer:
				return ui
	return null


func _get_main_controls() -> Control:
	var ui = _get_ui_root()
	if is_instance_valid(ui) and ui.has_node("Controls"):
		return ui.get_node("Controls")
	return null


func _get_ui_scale() -> float:
	if is_instance_valid(grid) and grid.has_method("_get_ui_scale"):
		return grid._get_ui_scale()
	return 1.0


func _get_safe_font() -> Font:
	return SandboxFontHelper.get_safe_font()


func _play_action_sound_safe(sound_name: String, pitch_range: float = 0.0, volume_offset: float = 0.0, forced_pitch: float = 1.0) -> void:
	if is_instance_valid(grid) and grid.has_method("_play_action_sound"):
		grid._play_action_sound(sound_name, pitch_range, volume_offset, forced_pitch)


func _get_rand_range(min_val: float, max_val: float) -> float:
	if is_instance_valid(grid) and grid.has_method("_get_lut_rand_range"):
		return grid._get_lut_rand_range(min_val, max_val)
	return randf_range(min_val, max_val)


# =========================================================================
# CONFIGURACIÓN Y DESPLIEGUE DEL MANDO TÁCTIL (ARCADE GUI)
# =========================================================================

func setup_npc_control_gui() -> void:
	var s = 1.25 # Escala fija unificada para el pad de movimiento y acción
	var ui_root = _get_ui_root()
	var main_controls = _get_main_controls()
	if not is_instance_valid(ui_root): return
	
	if is_instance_valid(npc_control_gui):
		if npc_control_gui.get_parent():
			npc_control_gui.get_parent().remove_child(npc_control_gui)
		npc_control_gui.queue_free()
		
	npc_control_gui = Control.new()
	npc_control_gui.name = "NPCControlGUI"
	npc_control_gui.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var cached_hud_height = grid.cached_hud_height if is_instance_valid(grid) and "cached_hud_height" in grid else 140.0
	npc_control_gui.offset_top = -cached_hud_height
	npc_control_gui.mouse_filter = Control.MOUSE_FILTER_PASS 
	
	# Visibilidad basada en estado de control + toggle de menú
	var in_control = is_instance_valid(controlled_npc)
	npc_control_gui.visible = in_control and not is_npc_mode_menu_open
	if is_instance_valid(main_controls):
		main_controls.visible = not in_control or is_npc_mode_menu_open
		
	ui_root.add_child(npc_control_gui)
	
	# Bloquear interacción con el mundo de juego debajo de la UI
	npc_control_gui.mouse_entered.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = true)
	npc_control_gui.mouse_exited.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = false)
	
	# Fondo translúcido para la barra
	var bg = Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.6)
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP # Bloquear clics al mundo
	npc_control_gui.add_child(bg)
	
	# Cerrador automático para cualquier toque en controles arcade cuando el menú está abierto
	var arcade_closer = func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and is_npc_mode_menu_open:
			toggle_npc_mode_menu(false)
	
	bg.gui_input.connect(arcade_closer)
	
	# Izquierda: Pad Virtual Circular (Estilo Arcade)
	var pad = Panel.new()
	npc_control_gui.set_meta("pad_node", pad)
	pad.custom_minimum_size = Vector2(240 * s, 240 * s)
	pad.anchor_top = 0.5; pad.anchor_bottom = 0.5
	pad.offset_left = 60 * s; pad.offset_right = 300 * s
	pad.offset_top = -120 * s; pad.offset_bottom = 120 * s
	var pad_style = StyleBoxFlat.new()
	pad_style.bg_color = Color("#141313")
	pad_style.set_corner_radius_all(120 * s)
	pad_style.border_width_left = 4 * s; pad_style.border_width_right = 4 * s
	pad_style.border_width_top = 4 * s; pad_style.border_width_bottom = 4 * s
	pad_style.border_color = Color("#222222")
	pad.add_theme_stylebox_override("panel", pad_style)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.gui_input.connect(func(event):
		if event is InputEventMouseButton:
			npc_control_gui.set_meta("is_pad_active", event.pressed)
		elif event is InputEventScreenTouch:
			npc_control_gui.set_meta("is_pad_active", event.pressed)
		arcade_closer.call(event)
	)
	npc_control_gui.set_meta("is_pad_active", false) # Estado inicial
	npc_control_gui.add_child(pad)
	
	# Cruz direccional visual dentro del pad
	var cross_color = Color("#706A6A")
	var v_bar = ColorRect.new()
	v_bar.color = cross_color
	v_bar.custom_minimum_size = Vector2(60 * s, 160 * s)
	v_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v_bar.offset_left = -30 * s; v_bar.offset_right = 30 * s
	v_bar.offset_top = -80 * s; v_bar.offset_bottom = 80 * s
	v_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v_bar)
	
	var h_bar = ColorRect.new()
	h_bar.color = cross_color
	h_bar.custom_minimum_size = Vector2(160 * s, 60 * s)
	h_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	h_bar.offset_left = -80 * s; h_bar.offset_right = 80 * s
	h_bar.offset_top = -30 * s; h_bar.offset_bottom = 30 * s
	h_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(h_bar)

	# Botones centrales apilados verticalmente
	# 1. Botón MENU (Alternar HUD de construcción)
	var menu_btn = Button.new()
	menu_btn.name = "MenuBtn"
	menu_btn.text = tr("menu")
	menu_btn.custom_minimum_size = Vector2(300 * s, 72 * s)
	menu_btn.anchor_left = 0.5; menu_btn.anchor_right = 0.5; menu_btn.anchor_top = 0.5; menu_btn.anchor_bottom = 0.5
	menu_btn.offset_left = -150 * s; menu_btn.offset_right = 150 * s
	menu_btn.offset_top = -120 * s; menu_btn.offset_bottom = -48 * s
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	menu_style.border_width_left = 8 * s; menu_style.border_width_top = 8 * s
	menu_style.border_width_right = 8 * s; menu_style.border_width_bottom = 8 * s
	menu_style.border_color = Color(0.4, 0.4, 0.4)
	menu_btn.add_theme_stylebox_override("normal", menu_style)
	menu_btn.add_theme_stylebox_override("hover", menu_style)
	menu_btn.add_theme_stylebox_override("pressed", menu_style)
	menu_btn.add_theme_font_override("font", _get_safe_font())
	menu_btn.add_theme_font_size_override("font_size", int(22 * s))
	menu_btn.pressed.connect(func():
		toggle_npc_mode_menu(!is_npc_mode_menu_open)
	)
	npc_control_gui.add_child(menu_btn)
	if is_instance_valid(grid) and "ui_elements" in grid:
		grid.ui_elements["arcade_menu_btn"] = menu_btn
	
	# 1b. Etiquetas externas debajo del botón de menú
	var arcade_labels = HBoxContainer.new()
	arcade_labels.name = "ArcadeLabels"
	arcade_labels.custom_minimum_size = Vector2(300 * s, 40 * s)
	arcade_labels.anchor_left = 0.5; arcade_labels.anchor_right = 0.5; arcade_labels.anchor_top = 0.5; arcade_labels.anchor_bottom = 0.5
	arcade_labels.offset_left = -150 * s; arcade_labels.offset_right = 150 * s
	arcade_labels.offset_top = -60 * s; arcade_labels.offset_bottom = 12 * s
	arcade_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arcade_labels.add_theme_constant_override("separation", 0)
	npc_control_gui.add_child(arcade_labels)

	# 2. Botón SALIR (Círculo rojo X)
	var exit_btn = Button.new()
	exit_btn.text = "X"
	exit_btn.custom_minimum_size = Vector2(100 * s, 100 * s)
	exit_btn.anchor_left = 0.5; exit_btn.anchor_right = 0.5; exit_btn.anchor_top = 0.5; exit_btn.anchor_bottom = 0.5
	exit_btn.offset_left = -50 * s; exit_btn.offset_right = 50 * s
	exit_btn.offset_top = 20 * s; exit_btn.offset_bottom = 120 * s
	var exit_style = StyleBoxFlat.new()
	exit_style.bg_color = Color(0.8, 0.15, 0.15, 1.0)
	exit_style.set_corner_radius_all(50 * s)
	exit_style.border_width_left = 15 * s; exit_style.border_width_right = 15 * s
	exit_style.border_width_top = 15 * s; exit_style.border_width_bottom = 15 * s
	exit_style.border_color = Color(0.4, 0.05, 0.05)
	exit_btn.add_theme_stylebox_override("normal", exit_style)
	exit_btn.add_theme_stylebox_override("hover", exit_style)
	exit_btn.add_theme_stylebox_override("pressed", exit_style)
	exit_btn.add_theme_font_override("font", _get_safe_font())
	exit_btn.add_theme_font_size_override("font_size", int(34 * s))
	exit_btn.add_theme_constant_override("outline_size", int(6 * s))
	exit_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_btn.pressed.connect(func():
		stop_controlling_npc()
	)
	npc_control_gui.add_child(exit_btn)

	# Derecha: Botón de ACCIÓN (Círculo azul)
	var action_btn = Button.new()
	action_btn.name = "ActionBtn"
	action_btn.text = tr("action")
	action_btn.custom_minimum_size = Vector2(200 * s, 200 * s)
	action_btn.anchor_left = 1.0; action_btn.anchor_right = 1.0
	action_btn.anchor_top = 0.5; action_btn.anchor_bottom = 0.5
	action_btn.offset_left = -280 * s; action_btn.offset_right = -80 * s
	action_btn.offset_top = -100 * s; action_btn.offset_bottom = 100 * s
	npc_control_gui.set_meta("action_btn", action_btn)
	var action_style = StyleBoxFlat.new()
	action_style.bg_color = Color(0.1, 0.4, 0.8, 1.0)
	action_style.set_corner_radius_all(100 * s)
	action_style.border_width_left = 18 * s; action_style.border_width_right = 18 * s
	action_style.border_width_top = 18 * s; action_style.border_width_bottom = 18 * s
	action_style.border_color = Color(0.04, 0.15, 0.4)
	action_btn.add_theme_stylebox_override("normal", action_style)
	action_btn.add_theme_font_override("font", _get_safe_font())
	action_btn.add_theme_font_size_override("font_size", int(32 * s))
	action_btn.add_theme_constant_override("outline_size", int(7 * s))
	action_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	action_btn.gui_input.connect(arcade_closer)
	action_btn.pressed.connect(func():
		trigger_controlled_npc_action()
	)
	npc_control_gui.add_child(action_btn)
	if is_instance_valid(grid) and "ui_elements" in grid:
		grid.ui_elements["arcade_action_btn"] = action_btn


# =========================================================================
# GESTIÓN DE POSESIÓN Y LIBERACIÓN DEL NPC
# =========================================================================

func start_controlling_npc(npc: Variant) -> void:
	if not is_instance_valid(grid) or npc == null: return
	controlled_npc = npc
	
	# Registro analítico en Firebase
	AnalyticsManager.log_event("npc_controlled", {"npc_type": controlled_npc.get("type", "unknown")})
	
	# Potenciar vida para la unidad heroica del jugador
	controlled_npc.hp = max(controlled_npc.hp, 160.0)
	controlled_npc["max_hp"] = max(controlled_npc.get("max_hp", 100.0), 160.0)
	controlled_npc.dir = 0 # Detener movimiento autónomo
	controlled_npc["is_fleeing"] = false # Quitar miedo si lo tenía
	is_selecting_npc_to_control = false
	_play_action_sound_safe("ui_click")
	
	# Actualizar interfaz de usuario
	if is_instance_valid(grid.npc_panel): grid.npc_panel.visible = false
	var main_controls = _get_main_controls()
	if is_instance_valid(main_controls):
		main_controls.visible = false
		
	if is_instance_valid(npc_control_gui):
		npc_control_gui.visible = true
		update_arcade_dynamic_button()
		
		var action_btn = npc_control_gui.find_child("ActionBtn", true, false)
		if action_btn:
			action_btn.text = tr("action")
			
	# Desbloqueo de Logro: Tiempo Retro (en segundo plano)
	var is_unlocked = false
	if grid.achievement_manager and grid.achievement_manager.achievements.has("retro_time"):
		is_unlocked = grid.achievement_manager.achievements["retro_time"].unlocked
	elif "achievements" in grid and grid.achievements.has("retro_time"):
		is_unlocked = grid.achievements["retro_time"].unlocked
		
	if not is_unlocked:
		if grid.has_method("_unlock_retro_time_delayed"):
			grid._unlock_retro_time_delayed()
		elif grid.achievement_manager:
			grid.achievement_manager.unlock_retro_time_delayed()


func try_select_npc_at(gx: int, gy: int) -> bool:
	if not is_instance_valid(grid): return false
	var nearby = grid._get_nearby_npcs(gx, gy, 12.0)
	if nearby.size() > 0:
		start_controlling_npc(nearby[0])
		return true
	return false


func stop_controlling_npc(keep_menus_open: bool = false) -> void:
	_play_action_sound_safe("ui_click")
	controlled_npc = null
	is_selecting_npc_to_control = false
	is_npc_mode_menu_open = false
	
	if is_instance_valid(npc_control_gui):
		npc_control_gui.visible = false
		
	var main_controls = _get_main_controls()
	if is_instance_valid(main_controls):
		main_controls.visible = true
		var cached_hud_height = grid.cached_hud_height if is_instance_valid(grid) and "cached_hud_height" in grid else 140.0
		main_controls.offset_top = -cached_hud_height
		main_controls.offset_bottom = 0
		
	if not keep_menus_open and is_instance_valid(grid):
		if is_instance_valid(grid.tools_panel): grid.tools_panel.visible = false
		if is_instance_valid(grid.disaster_panel): grid.disaster_panel.visible = false
		if is_instance_valid(grid.npc_panel): grid.npc_panel.visible = false
		
	if is_instance_valid(grid):
		grid.is_mouse_over_ui = false
		if grid.has_method("_update_menu_highlights"):
			grid._update_menu_highlights()
			
	update_arcade_dynamic_button()


func toggle_npc_mode_menu(p_show: bool) -> void:
	var ui_root = _get_ui_root()
	var main_controls = _get_main_controls()
	if not is_instance_valid(main_controls) or not is_instance_valid(ui_root): return
	_play_action_sound_safe("ui_click")
	is_npc_mode_menu_open = p_show
	
	# Alternar visibilidad: Menú de construcción vs HUD Arcade
	main_controls.visible = p_show
	if is_instance_valid(npc_control_gui):
		npc_control_gui.visible = !p_show
		
	if !p_show:
		if is_instance_valid(grid):
			if is_instance_valid(grid.tools_panel): grid.tools_panel.visible = false
			if is_instance_valid(grid.disaster_panel): grid.disaster_panel.visible = false
			if is_instance_valid(grid.npc_panel): grid.npc_panel.visible = false
			grid.touch_started_on_ui = true
			
		var blocker = ui_root.get_node_or_null("ArcadeMenuBlocker")
		if blocker: blocker.queue_free()
	else:
		var blocker = ui_root.get_node_or_null("ArcadeMenuBlocker")
		if not blocker:
			blocker = Control.new()
			blocker.name = "ArcadeMenuBlocker"
			blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			blocker.mouse_filter = Control.MOUSE_FILTER_STOP
			ui_root.add_child(blocker)
			ui_root.move_child(blocker, 0)
			blocker.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					toggle_npc_mode_menu(false)
			)


# =========================================================================
# PROCESAMIENTO DE FÍSICAS E INPUTS DEL PERSONAJE CONTROLADO
# =========================================================================

func handle_controlled_npc_input(delta: float) -> void:
	if not controlled_npc or not is_instance_valid(npc_control_gui) or not npc_control_gui.visible: return
	
	# Detectar muerte del personaje
	if controlled_npc.hp <= 0:
		stop_controlling_npc()
		return
		
	var s = _get_ui_scale()
	var pad = npc_control_gui.get_meta("pad_node")
	var action_btn = npc_control_gui.get_meta("action_btn")
	
	# Detectar si está en el suelo
	var is_on_ground = !grid._can_npc_fit(controlled_npc.pos.x, controlled_npc.pos.y + 1, controlled_npc) if is_instance_valid(grid) else true
	
	# --- MOVIMIENTO VIRTUAL (PAD) ---
	var move_dir = 0
	var want_jump = false
	var want_down = false
	var pad_active = npc_control_gui.get_meta("is_pad_active") if npc_control_gui.has_meta("is_pad_active") else false
	
	if pad_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var m_pos = grid.get_viewport().get_mouse_position() if is_instance_valid(grid) else Vector2.ZERO
		if is_instance_valid(pad):
			var pad_center = pad.get_global_rect().get_center()
			# Horizontal
			if m_pos.x < pad_center.x - (25 * s): move_dir = -1
			elif m_pos.x > pad_center.x + (25 * s): move_dir = 1
			# Vertical
			if m_pos.y < pad_center.y - (40 * s): want_jump = true
			elif m_pos.y > pad_center.y + (40 * s): want_down = true
	elif not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		npc_control_gui.set_meta("is_pad_active", false) # Seguridad al soltar
		
	# Inercia y aceleración
	var target_vel = float(move_dir) * 2.1
	var accel = 0.5 if is_on_ground else 0.15
	controlled_npc.vx = lerp(controlled_npc.vx, target_vel, accel)
	
	if move_dir != 0:
		controlled_npc.dir = move_dir
		controlled_npc["last_dir"] = move_dir
		
		# --- EXCAVACIÓN ESPECIAL DEL MINERO ---
		if controlled_npc.type == "miner" and is_instance_valid(grid):
			var tx = controlled_npc.pos.x + move_dir
			var blocked = !grid._can_npc_fit(tx, controlled_npc.pos.y, controlled_npc)
			
			if want_down or blocked:
				var dig_timer = controlled_npc.get("manual_dig_timer", 0.0)
				dig_timer += delta
				if dig_timer >= 0.14:
					dig_timer = 0.0
					grid._miner_dig(controlled_npc, want_down)
					
					var next_x = controlled_npc.pos.x + move_dir
					var next_y = controlled_npc.pos.y + (1 if want_down else 0)
					if grid._can_npc_fit(next_x, next_y, controlled_npc):
						grid._draw_npc_pixels(controlled_npc, 0)
						controlled_npc.pos = Vector2i(next_x, next_y)
						controlled_npc.vx = 0.0
						controlled_npc.vy = 0.0
				controlled_npc["manual_dig_timer"] = dig_timer
	else:
		controlled_npc.dir = 0
		
	# --- SALTO ---
	if want_jump and is_on_ground:
		controlled_npc.vy = -5.5
		_play_action_sound_safe("ui_click")
		
	# --- BOTÓN DE ACCIÓN ---
	if is_instance_valid(action_btn) and action_btn.is_pressed() and controlled_npc.attack_cooldown <= 0:
		trigger_controlled_npc_action()


# =========================================================================
# ACCIONES CONTEXTUALES SEGÚN CLASE DEL NPC
# =========================================================================

func trigger_controlled_npc_action() -> void:
	if not controlled_npc or not is_instance_valid(grid): return
	
	# Activar siempre el temporizador del sprite de acción para el personaje controlado por el jugador
	controlled_npc["action_timer"] = 0.4
	
	match controlled_npc.type:
		"warrior":
			var target = grid._find_closest_enemy(controlled_npc, 30.0)
			if target:
				grid._attack_npc(controlled_npc, target)
				controlled_npc.attack_cooldown = 0.6
			else:
				_play_action_sound_safe("warrior_attack")
				if grid.has_method("_set_npc_emoji"):
					grid._set_npc_emoji(controlled_npc, "⚔️", 0.4)
				controlled_npc.attack_cooldown = 0.4
				
		"zombie":
			var target = grid._find_closest_enemy(controlled_npc, 30.0)
			if target:
				grid._attack_npc(controlled_npc, target)
				controlled_npc.attack_cooldown = 0.8
			else:
				var p_scale = 0.65 + float((controlled_npc.id * 23) % 40) / 40.0 * 0.40
				_play_action_sound_safe("zombie_attack", 0.08, 0.0, p_scale)
				if grid.has_method("_set_npc_emoji"):
					grid._set_npc_emoji(controlled_npc, "🧟", 0.4)
				controlled_npc.attack_cooldown = 0.5
				
		"zombie_tank":
			var target = grid._find_closest_enemy(controlled_npc, 30.0)
			if target and controlled_npc.pos.distance_to(target.pos) < 20.0:
				grid._attack_npc(controlled_npc, target)
				controlled_npc.attack_cooldown = 1.0
			else:
				var face_dir = controlled_npc.get("last_dir", 1)
				var found_x = -1; var found_y = -1; var found_mat = 2
				for dy in range(-4, 7):
					for dx in range(-5, 6):
						var tx = controlled_npc.pos.x + dx; var ty = controlled_npc.pos.y + dy
						if tx >= 0 and tx < grid.grid_width and ty >= 0 and ty < grid.dynamic_grid_height:
							var tid = grid._get_cell(tx, ty)
							if tid > 0 and tid != 1 and not (grid.material_tags_raw[grid._get_tags_id(tid)] & SandboxMaterial.Tags.NPC):
								found_x = tx; found_y = ty; found_mat = tid; break
					if found_x != -1: break
					
				if found_x != -1:
					grid._set_cell(found_x, found_y, 0)
					for _s in range(5):
						grid._add_spark(float(found_x), float(found_y), _get_rand_range(-30, 30), _get_rand_range(-50, -10), grid.mat_colors_1[found_mat] if found_mat < grid.mat_colors_1.size() else Color.GRAY, 0.4)
						
				var aim_target = find_controlled_aim_target(controlled_npc, face_dir, 150.0)
				var vx = face_dir * 120.0
				var vy = -80.0
				if aim_target:
					var target_x = float(aim_target.pos.x)
					var target_y = float(aim_target.pos.y)
					var dir = 1 if (target_x - controlled_npc.pos.x) > 0 else -1
					controlled_npc["last_dir"] = dir
					controlled_npc.dir = dir
					face_dir = dir
					target_x += _get_rand_range(-10.0, 10.0)
					target_y += _get_rand_range(-6.0, 6.0)
					var dist_x = abs(target_x - controlled_npc.pos.x)
					if dist_x < 2.0: dist_x = 2.0
					var time_to_target = dist_x / 120.0
					time_to_target = clamp(time_to_target, 0.4, 2.5)
					vx = dir * dist_x / time_to_target
					vy = (target_y - controlled_npc.pos.y) / time_to_target - (0.5 * 200.0 * time_to_target)
				
				grid.active_projectiles.append({
					"pos": Vector2(controlled_npc.pos.x + face_dir * 3, controlled_npc.pos.y + 1),
					"vel": Vector2(vx, vy),
					"team": controlled_npc.team,
					"type": "thrown_rock",
					"life": 3.0,
					"block_material": found_mat,
					"atk_dmg": 1.5
				})
				
				var p_scale = 0.65 + float((controlled_npc.id * 23) % 40) / 40.0 * 0.40
				_play_action_sound_safe("zombie_tank_throw", 0.08, 0.0, p_scale)
				if grid.has_method("_set_npc_emoji"):
					grid._set_npc_emoji(controlled_npc, "🪨", 1.2)
				controlled_npc.attack_cooldown = 2.0
				
		"dinosaurio":
			var target = grid._find_closest_enemy(controlled_npc, 35.0)
			if target:
				grid._attack_npc(controlled_npc, target)
				controlled_npc.attack_cooldown = 1.0
			else:
				_play_action_sound_safe("zombie_tank_melee")
				if grid.has_method("_set_npc_emoji"):
					grid._set_npc_emoji(controlled_npc, "🦖", 0.5)
				controlled_npc.attack_cooldown = 0.6
				
		"archer":
			var face_dir = controlled_npc.get("last_dir", 1)
			var target = find_controlled_aim_target(controlled_npc, face_dir, 160.0)
			if target:
				var target_dir = 1 if (target.pos.x - controlled_npc.pos.x) > 0 else -1
				controlled_npc["last_dir"] = target_dir
				controlled_npc.dir = target_dir
				grid._shoot_arrow(controlled_npc, target)
			else:
				var dummy_target = {"pos": Vector2i(controlled_npc.pos.x + face_dir * 100, controlled_npc.pos.y)}
				grid._shoot_arrow(controlled_npc, dummy_target)
			if grid.has_method("_set_npc_emoji"):
				grid._set_npc_emoji(controlled_npc, "🏹", 0.5)
			controlled_npc.attack_cooldown = 1.0
			
		"medic":
			var nearby = grid._get_nearby_npcs(controlled_npc.pos.x, controlled_npc.pos.y, 60.0)
			var healed_somebody = false
			var has_z = grid._has_active_zombies()
			for other in nearby:
				if grid._is_ally(controlled_npc, other, has_z) and other != controlled_npc and other.hp > 0:
					var mhp = other.get("max_hp", 100.0)
					if other.hp < mhp:
						other.hp = min(other.hp + controlled_npc.get("heal_power", 25.0), mhp)
						healed_somebody = true
						if grid.has_method("_set_npc_emoji"):
							grid._set_npc_emoji(other, "😊", 1.0)
						for _f in range(4):
							grid._add_spark(float(other.pos.x), float(other.pos.y - 2), 0.0, -20.0, Color.GREEN, 0.5)
			
			_play_action_sound_safe("medic_heal")
			if grid.has_method("_set_npc_emoji"):
				grid._set_npc_emoji(controlled_npc, "💚", 0.8)
			controlled_npc.attack_cooldown = 0.8
				
		"mage":
			var face_dir = controlled_npc.get("last_dir", 1)
			var target = find_controlled_aim_target(controlled_npc, face_dir, 150.0)
			if target:
				var target_dir = 1 if (target.pos.x - controlled_npc.pos.x) > 0 else -1
				controlled_npc["last_dir"] = target_dir
				controlled_npc.dir = target_dir
				grid._shoot_fireball(controlled_npc, target)
			else:
				var dummy_target = {"pos": Vector2i(controlled_npc.pos.x + face_dir * 90, controlled_npc.pos.y)}
				grid._shoot_fireball(controlled_npc, dummy_target)
			if grid.has_method("_set_npc_emoji"):
				grid._set_npc_emoji(controlled_npc, "🔥", 0.6)
			controlled_npc.attack_cooldown = 1.5
			
		"miner":
			var face_dir = controlled_npc.get("last_dir", 1)
			var tx = controlled_npc.pos.x + (face_dir * 3)
			var ty = controlled_npc.pos.y + 2
			if tx >= 1 and tx < grid.grid_width - 1 and ty >= 1 and ty < grid.dynamic_grid_height - 1:
				grid._set_cell(tx, ty, 5) # 5 = TNT
				grid._set_cell(tx + 1, ty, 5)
				grid._set_cell(tx, ty + 1, 5)
				grid._set_cell(tx + 1, ty + 1, 5)
				_play_action_sound_safe("npc_place")
			else:
				_play_action_sound_safe("miner_dig")
			if grid.has_method("_set_npc_emoji"):
				grid._set_npc_emoji(controlled_npc, "⚒️", 0.5)
			controlled_npc.attack_cooldown = 1.5


func find_controlled_aim_target(me, face_dir: int, radar_range: float):
	if not is_instance_valid(grid) or me == null: return null
	var closest = null; var min_dist_sq = radar_range * radar_range
	var nearby = grid._get_nearby_npcs(me.pos.x, me.pos.y, radar_range)
	var has_zombies = grid._has_active_zombies()
	for other in nearby:
		if other.hp > 0 and other != me:
			var is_enemy = not grid._is_ally(me, other, has_zombies)
			if is_enemy:
				var dx = other.pos.x - me.pos.x
				if dx * face_dir >= -8:
					var d_sq = me.pos.distance_squared_to(other.pos)
					if d_sq < min_dist_sq:
						min_dist_sq = d_sq
						closest = other
	return closest


# =========================================================================
# BOTÓN DINÁMICO CENTRAL DE LA INTERFAZ ARCADE
# =========================================================================

func on_arcade_selection_made(is_team_change: bool = false) -> void:
	if is_instance_valid(npc_control_gui):
		if not is_team_change and is_npc_mode_menu_open:
			toggle_npc_mode_menu(false)
		update_arcade_dynamic_button()


func update_arcade_dynamic_button() -> void:
	if not is_instance_valid(npc_control_gui): return
	var menu_btn = npc_control_gui.find_child("MenuBtn", true, false)
	if not is_instance_valid(menu_btn): return
	var s = 1.1 # Escala fija unificada con el Arcade UI
	
	for child in menu_btn.get_children(): 
		if is_instance_valid(child): child.queue_free()
	
	menu_btn.text = tr("menu")
	menu_btn.modulate = Color.WHITE
	
	var active_name = ""
	var active_val = ""
	var active_color = Color.WHITE
	var is_disaster = false
	
	var intensity_labels = ["off", "light", "med", "heavy", "violent"]
	
	var current_weather = grid.current_weather if "current_weather" in grid else 0
	var acid_rain_intensity = grid.acid_rain_intensity if "acid_rain_intensity" in grid else 0
	var earthquake_intensity = grid.earthquake_intensity if "earthquake_intensity" in grid else 0
	var tornado_intensity = grid.tornado_intensity if "tornado_intensity" in grid else 0
	var tsunami_intensity = grid.tsunami_intensity if "tsunami_intensity" in grid else 0
	var bombardero_intensity = grid.bombardero_intensity if "bombardero_intensity" in grid else 0
	var selected_material = grid.selected_material if "selected_material" in grid else 0
	var selected_team = grid.selected_team if "selected_team" in grid else 0
	var brush_radius = grid.brush_radius if "brush_radius" in grid else 1
	
	# 1. Comprobar Desastres (Prioridad)
	if current_weather > 0:
		active_name = tr("weather"); active_val = tr(intensity_labels[current_weather]); active_color = Color.SKY_BLUE; is_disaster = true
	elif acid_rain_intensity > 0:
		active_name = tr("acid_rain"); active_val = tr(intensity_labels[acid_rain_intensity]); active_color = Color("#7ae267"); is_disaster = true
	elif earthquake_intensity > 0:
		active_name = tr("quake"); active_val = tr(intensity_labels[earthquake_intensity]); active_color = Color.GOLD; is_disaster = true
	elif tornado_intensity > 0:
		active_name = tr("tornado"); active_val = tr(intensity_labels[tornado_intensity]); active_color = Color.GRAY; is_disaster = true
	elif tsunami_intensity > 0:
		active_name = tr("tsunami"); active_val = tr(intensity_labels[tsunami_intensity]); active_color = Color.ROYAL_BLUE; is_disaster = true
	elif bombardero_intensity > 0:
		active_name = tr("bomber"); active_val = tr(intensity_labels[bombardero_intensity]); active_color = Color.INDIAN_RED; is_disaster = true
	# 2. Comprobar NPCs
	elif selected_material >= 1000:
		if selected_material == 1000 or selected_material == 1001: active_name = tr("warrior")
		elif selected_material == 1010 or selected_material == 1011: active_name = tr("archer")
		elif selected_material == 1020 or selected_material == 1021: active_name = tr("miner")
		elif selected_material == 1040 or selected_material == 1041: active_name = tr("medic")
		elif selected_material == 1070 or selected_material == 1071: active_name = tr("mage")
		elif selected_material == 1050 or selected_material == 1051: active_name = tr("zombie")
		elif selected_material == 1060 or selected_material == 1061: active_name = tr("zombie_tank")
		elif selected_material == 1090 or selected_material == 1091: active_name = tr("dinosaurio")
		
		if selected_material == 1050 or selected_material == 1051 or selected_material == 1060 or selected_material == 1061 or selected_material == 1090 or selected_material == 1091:
			active_color = Color("#4E822E") if (selected_material == 1060 or selected_material == 1061 or selected_material == 1090 or selected_material == 1091) else Color("#5D9C36")
			active_val = tr("factionless")
		else:
			var t_colors = [Color.RED, Color.CORNFLOWER_BLUE, Color.GOLD, Color.GREEN]
			active_color = t_colors[selected_team] if selected_team < 4 else Color.WHITE
			active_val = "T." + str(selected_team + 1)
	# 3. Comprobar Material normal
	elif selected_material > 0:
		if "mat_id_to_key" in grid and grid.mat_id_to_key.has(selected_material):
			active_name = tr(grid.mat_id_to_key[selected_material])
		else:
			active_name = "Mat." + str(selected_material)
		active_val = "S." + str(brush_radius)
		if "mat_colors_1" in grid and selected_material < grid.mat_colors_1.size():
			active_color = grid.mat_colors_1[selected_material]
	
	if active_name != "":
		menu_btn.text = ""
		
		var hbox = HBoxContainer.new()
		hbox.name = "DynamicContent"
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("separation", 0)
		menu_btn.add_child(hbox)
		
		# Lateral Izquierdo
		var left_side = CenterContainer.new()
		left_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(left_side)
		
		if is_disaster:
			var name_lbl = Label.new()
			name_lbl.text = active_name
			name_lbl.add_theme_font_override("font", _get_safe_font())
			name_lbl.add_theme_font_size_override("font_size", int(22 * s))
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_side.add_child(name_lbl)
		else:
			var color_box = ColorRect.new()
			color_box.custom_minimum_size = Vector2(50 * s, 30 * s)
			color_box.color = active_color
			color_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_side.add_child(color_box)
		
		# Separador
		var div = ColorRect.new()
		div.custom_minimum_size = Vector2(4 * s, 0)
		div.color = Color(1, 1, 1, 0.2)
		div.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(div)
		
		# Lateral Derecho
		var right_side = CenterContainer.new()
		right_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(right_side)
		
		var val_lbl = Label.new()
		val_lbl.text = active_val
		val_lbl.add_theme_font_override("font", _get_safe_font())
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		if is_disaster:
			val_lbl.add_theme_font_size_override("font_size", int(28 * s))
			val_lbl.add_theme_color_override("font_color", Color.WHITE)
		else:
			var brush_sizes = [0, 1, 2, 5, 7, 12]
			var brush_labels = ["1", "3", "5", "10", "15", "25"]
			var brush_idx = brush_sizes.find(brush_radius)
			var display_val = brush_labels[brush_idx] if brush_idx != -1 else str(brush_radius)
			val_lbl.text = "🖌️:" + display_val
			val_lbl.add_theme_font_size_override("font_size", int(28 * s))
			val_lbl.add_theme_color_override("font_color", Color.YELLOW)
		
		right_side.add_child(val_lbl)
		
		# Etiquetas externas (debajo del botón de menú)
		var ext_labels = npc_control_gui.get_node_or_null("ArcadeLabels")
		if ext_labels:
			for child in ext_labels.get_children(): child.queue_free()
			
			if not is_disaster:
				var name_lbl = Label.new()
				name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				name_lbl.text = active_name
				name_lbl.add_theme_font_override("font", _get_safe_font())
				name_lbl.add_theme_font_size_override("font_size", int(30 * s))
				name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ext_labels.add_child(name_lbl)
	else:
		var ext_labels = npc_control_gui.get_node_or_null("ArcadeLabels")
		if ext_labels:
			for child in ext_labels.get_children(): child.queue_free()
