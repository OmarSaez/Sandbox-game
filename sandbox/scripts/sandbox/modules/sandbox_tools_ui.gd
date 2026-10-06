extends Node
class_name SandboxToolsPaintUI

## Módulo especializado en la gestión de interfaces de Herramientas y Pintura.
## Administra:
## 1. Panel de Herramientas (tools_panel): selector de idiomas, orientación, rejilla/grid snap,
##    radio de pincel, comunidad/workshop, accesos directos (borrador, guardado), soporte al creador (anuncios),
##    pausa con temporizador de seguridad de 3 segundos, reinicio de partida y control de volumen master.
## 2. Panel de Pintura (paint_panel): selector de modo (fondo vs elementos), paleta de colores cromática de 24 tonos,
##    selector libre RGB/HSV (ColorPicker), historial dinámico de colores recientes con borrador de pintura,
##    y control deslizante de grosor de brocha de pintura.
## 3. Persistencia de configuración de herramientas y preferencias en user://tools_settings.json.

# Referencia a la cuadrícula principal
var grid: Node = null

# --- PANELES VISUALES ---
var tools_panel: PanelContainer = null
var paint_panel: PanelContainer = null

# --- VARIABLES DE CONFIGURACIÓN Y PINTURA ---
var brush_radius: int = 2
var paint_brush_radius_idx: int = 2 # Índice para [1, 3, 5, 10, 15, 25]
var game_volume: float = 1.2
var pre_mute_volume: float = 1.0
var is_muted: bool = false
var is_unpausing: bool = false

var selected_paint_color: Color = Color.WHITE
var paint_mode: int = 0 # 0: Elements, 1: Background
var recent_paint_colors: Array[Color] = [
	Color.WHITE, Color.BLACK, Color.GRAY, Color.RED, Color.GREEN, Color.BLUE
]


func setup(p_grid: Node) -> void:
	grid = p_grid


# =========================================================================
# MÉTODOS AUXILIARES SEGUROS
# =========================================================================

func _get_ui_scale() -> float:
	if is_instance_valid(grid) and grid.has_method("_get_ui_scale"):
		return grid._get_ui_scale()
	return 1.0

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

func _get_viewport_rect() -> Rect2:
	if is_instance_valid(grid) and grid.has_method("get_viewport_rect"):
		return grid.get_viewport_rect()
	var vp = get_viewport()
	if is_instance_valid(vp):
		return vp.get_visible_rect()
	return Rect2()

func _play_action_sound(sound_name: String) -> void:
	if is_instance_valid(grid) and grid.has_method("_play_action_sound"):
		grid._play_action_sound(sound_name)

func _set_environmental_audio_paused(paused: bool) -> void:
	if not is_instance_valid(grid): return
	var player_names = [
		"weather_player", "quake_player", "tornado_player",
		"tsunami_player", "firework_player", "ascent_player",
		"volcano_loop_player", "fire_loop_player", "bombardero_player"
	]
	for p_name in player_names:
		var p = grid.get(p_name)
		if is_instance_valid(p):
			p.stream_paused = paused

func _start_pulse(btn: Control) -> void:
	if is_instance_valid(grid) and grid.has_method("_start_pulse"):
		grid._start_pulse(btn)

func _stop_pulse(btn: Control) -> void:
	if is_instance_valid(grid) and grid.has_method("_stop_pulse"):
		grid._stop_pulse(btn)

func _show_thank_you_popup(prev_paused: bool) -> void:
	if is_instance_valid(grid) and grid.has_method("_show_thank_you_popup"):
		grid._show_thank_you_popup(prev_paused)


# =========================================================================
# 1. PERSISTENCIA: GUARDADO Y CARGA DE AJUSTES (user://tools_settings.json)
# =========================================================================

func save_tool_settings() -> void:
	if not is_instance_valid(grid): return
	var settings = {
		"brush_radius": brush_radius,
		"paint_brush_radius_idx": paint_brush_radius_idx,
		"game_volume": game_volume,
		"is_muted": is_muted,
		"current_language": grid.current_language,
		"show_music_notes_popup": grid.show_music_notes_popup if "show_music_notes_popup" in grid else false,
		"is_logic_gate_tutorial_done": grid.is_logic_gate_tutorial_done,
		"is_grid_tutorial_done": grid.is_grid_tutorial_done,
		"is_phase_block_tutorial_done": grid.is_phase_block_tutorial_done,
		"is_zoom_tutorial_done": grid.is_zoom_tutorial_done,
		"is_cannon_tutorial_done": grid.is_cannon_tutorial_done,
		"is_piston_tutorial_done": grid.is_piston_tutorial_done
	}
	var f = FileAccess.open("user://tools_settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func load_tool_settings() -> void:
	if not is_instance_valid(grid): return
	if FileAccess.file_exists("user://tools_settings.json"):
		var f = FileAccess.open("user://tools_settings.json", FileAccess.READ)
		if f:
			var dict = JSON.parse_string(f.get_as_text())
			if typeof(dict) == TYPE_DICTIONARY:
				if dict.has("brush_radius"): brush_radius = int(dict["brush_radius"])
				if dict.has("paint_brush_radius_idx"): paint_brush_radius_idx = int(dict["paint_brush_radius_idx"])
				if dict.has("game_volume"):
					game_volume = float(dict["game_volume"])
					update_game_volume(game_volume)
				if dict.has("is_muted"): is_muted = bool(dict["is_muted"])
				if dict.has("current_language"):
					grid.current_language = str(dict["current_language"])
					TranslationServer.set_locale(grid.current_language)
				if dict.has("show_music_notes_popup") and "show_music_notes_popup" in grid:
					grid.show_music_notes_popup = bool(dict["show_music_notes_popup"])
				if dict.has("is_logic_gate_tutorial_done"):
					grid.is_logic_gate_tutorial_done = bool(dict["is_logic_gate_tutorial_done"])
				if dict.has("is_grid_tutorial_done"):
					grid.is_grid_tutorial_done = bool(dict["is_grid_tutorial_done"])
				if dict.has("is_phase_block_tutorial_done"):
					grid.is_phase_block_tutorial_done = bool(dict["is_phase_block_tutorial_done"])
				if dict.has("is_zoom_tutorial_done"):
					grid.is_zoom_tutorial_done = bool(dict["is_zoom_tutorial_done"])
				if dict.has("is_cannon_tutorial_done"):
					grid.is_cannon_tutorial_done = bool(dict["is_cannon_tutorial_done"])
				if dict.has("is_piston_tutorial_done"):
					grid.is_piston_tutorial_done = bool(dict["is_piston_tutorial_done"])

func update_game_volume(value: float) -> void:
	var db = linear_to_db(value) + 12.0
	AudioServer.set_bus_volume_db(0, db)
	AudioServer.set_bus_mute(0, value <= 0)


# =========================================================================
# 2. PANEL DE HERRAMIENTAS (tools_panel)
# =========================================================================

func setup_tools_ui() -> void:
	if not is_instance_valid(grid): return
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root): return

	var tools_btn = grid._create_vertical_category_btn("🛠️", "tools")
	tools_btn.name = "ToolsBtn"
	grid.ui_elements["tools_btn"] = tools_btn
	tools_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	tools_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	tools_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# --- ACCIONES RÁPIDAS (PAN, GUARDAR, DESHACER, REHACER) ---
	var qa_grid = GridContainer.new()
	qa_grid.columns = 2
	qa_grid.name = "QuickActionsGrid"
	grid.ui_elements["quick_actions_grid"] = qa_grid
	qa_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qa_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	qa_grid.custom_minimum_size = Vector2(150 * s, 0)
	qa_grid.add_theme_constant_override("h_separation", 0)
	qa_grid.add_theme_constant_override("v_separation", 0)

	var qa_style = StyleBoxFlat.new()
	qa_style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	qa_style.border_width_left = 1; qa_style.border_width_top = 1
	qa_style.border_width_right = 1; qa_style.border_width_bottom = 1
	qa_style.border_color = Color(0.4, 0.4, 0.5)

	var create_qa_btn = func(icon: String) -> Button:
		var btn = Button.new()
		btn.text = icon
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
		btn.add_theme_font_size_override("font_size", int(26 * s))
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.add_theme_stylebox_override("normal", qa_style)
		btn.add_theme_stylebox_override("hover", qa_style)
		btn.add_theme_stylebox_override("pressed", qa_style)
		qa_grid.add_child(btn)
		return btn

	var btn_pan = create_qa_btn.call("🔍")
	var btn_save = create_qa_btn.call("💾")
	var btn_undo = create_qa_btn.call("↩️")
	var btn_redo = create_qa_btn.call("↪️")

	grid.ui_elements["btn_pan"] = btn_pan
	grid.ui_elements["btn_undo"] = btn_undo
	grid.ui_elements["btn_redo"] = btn_redo
	grid._set_panning_mode(grid.is_panning_mode)
	grid._update_zoom_ui()

	btn_pan.pressed.connect(func():
		if btn_pan.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		grid._set_panning_mode(!grid.is_panning_mode)
	)
	btn_save.pressed.connect(func():
		if btn_save.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		if is_instance_valid(grid.save_panel): grid.save_panel.queue_free()
		else: grid._setup_save_ui()
	)
	btn_undo.pressed.connect(func():
		if btn_undo.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		grid.undo_history()
	)
	btn_redo.pressed.connect(func():
		if btn_redo.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		grid.redo_history()
	)

	grid._update_undo_redo_ui()

	grid._setup_long_press_tooltip(btn_pan, "tooltip_zoom")
	grid._setup_long_press_tooltip(btn_save, "tooltip_save")
	grid._setup_long_press_tooltip(btn_undo, "tooltip_undo")
	grid._setup_long_press_tooltip(btn_redo, "tooltip_redo")

	if is_instance_valid(grid.action_vbox):
		grid.action_vbox.add_child(qa_grid)
	if is_instance_valid(grid.action_hbox):
		grid.action_hbox.add_child(tools_btn)

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.4, 0.5)
	tools_btn.add_theme_stylebox_override("normal", btn_style)
	tools_btn.add_theme_stylebox_override("hover", btn_style)
	tools_btn.add_theme_stylebox_override("pressed", btn_style)
	tools_btn.set_meta("base_style", btn_style)

	# --- CREAR PANEL PRINCIPAL DE HERRAMIENTAS ---
	if is_instance_valid(tools_panel):
		tools_panel.queue_free()

	tools_panel = PanelContainer.new()
	tools_panel.name = "ToolsPanel"
	ui_root.add_child(tools_panel)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	panel_style.border_width_left = 3; panel_style.border_width_top = 3
	panel_style.border_width_right = 3; panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.4, 0.4, 0.5)
	panel_style.corner_radius_top_left = int(30 * s); panel_style.corner_radius_top_right = int(30 * s)
	tools_panel.add_theme_stylebox_override("panel", panel_style)
	tools_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	tools_panel.visible = ui_root.get_meta("tools_v", false)
	grid._align_panel_to_hud(tools_panel, 530 * s, 570 * s)

	var scroll = ScrollContainer.new()
	scroll.name = "ToolsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 25
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(10 * s))
	tools_panel.add_child(main_vbox)

	var title = Label.new()
	title.text = tr("tools")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	title.add_theme_font_size_override("font_size", int(34 * s))
	grid.ui_elements["tools_panel_title"] = title
	main_vbox.add_child(title)

	tools_btn.pressed.connect(on_tools_btn_pressed)
	main_vbox.add_child(scroll)

	tools_panel.mouse_entered.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = true)
	tools_panel.mouse_exited.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = false)

	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", int(15 * s))
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)

	var create_row = func(label_key: String, options: Array, callback: Callable, is_upcoming: bool = false):
		var lbl = Label.new()
		lbl.text = tr(label_key) + ":"
		lbl.add_theme_font_size_override("font_size", int(22.0 * s))
		lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
		grid.ui_elements[label_key + "_lbl"] = lbl
		v_box.add_child(lbl)

		var row_margin = MarginContainer.new()
		row_margin.add_theme_constant_override("margin_left", int(2 * s))
		row_margin.add_theme_constant_override("margin_right", int(2 * s))
		v_box.add_child(row_margin)

		var flow = HBoxContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", int(6 * s))
		row_margin.add_child(flow)

		if is_upcoming:
			lbl.modulate = Color(0.5, 0.5, 0.5, 0.7)
			flow.modulate = Color(0.5, 0.5, 0.5, 0.7)

		for i in range(options.size()):
			var btn = Button.new()
			btn.text = str(options[i])
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 45.0 * s)
			btn.add_theme_font_size_override("font_size", int(20.0 * s))
			btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
			btn.mouse_filter = Control.MOUSE_FILTER_PASS

			var b_style = StyleBoxFlat.new()
			b_style.bg_color = Color(0.12, 0.12, 0.15, 0.8)
			b_style.border_width_left = 1; b_style.border_width_top = 1
			b_style.border_width_right = 1; b_style.border_width_bottom = 1
			b_style.border_color = Color(0.3, 0.3, 0.4)
			b_style.set_corner_radius_all(int(10 * s))
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
					_play_action_sound("ui_click")
					if grid.is_selecting_npc_to_control or is_instance_valid(grid.controlled_npc):
						grid._stop_controlling_npc()
					callback.call(level)
				)
			flow.add_child(btn)
			grid.ui_elements[label_key + "_btn_" + str(i)] = btn

	# Fila 1: Idioma
	var lang_options = ["Español", "English", "Italiano", "Français", "Deutsch", "Português"]
	var lang_codes = ["es", "en", "it", "fr", "de", "pt"]
	create_row.call("lang", lang_options, func(l):
		grid.current_language = lang_codes[l]
		TranslationServer.set_locale(grid.current_language)
		save_tool_settings()
		grid.call_deferred("_setup_main_ui_containers")
	)

	# Fila 2: Orientación
	var orient_options = [tr("ORIENT_AUTO"), tr("ORIENT_PORTRAIT"), tr("ORIENT_LANDSCAPE")]
	create_row.call("orient", orient_options, func(l):
		var f = FileAccess.open("user://orientation.save", FileAccess.WRITE)
		if f:
			f.store_string(str(l))
			f.close()

		grid.current_orientation_setting = l
		grid._update_menu_highlights()

		if OS.has_feature("mobile"):
			if l == 1: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
			elif l == 2: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
			else: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	)

	# Fila 3: Ajuste de cuadrícula / Grid Snap
	var grid_options = [tr("active"), tr("inactive")]
	create_row.call("GRID_SNAP_LBL", grid_options, func(l):
		grid.force_grid_visible = (l == 0)
		save_tool_settings()
		grid._update_menu_highlights()
		grid.queue_redraw()
	)

	# Fila 4: Tamaño del pincel de dibujo
	var brush_sizes = [0, 1, 2, 5, 7, 12]
	var brush_labels = ["1", "3", "5", "10", "15", "25"]
	create_row.call("brush", brush_labels, func(l):
		brush_radius = brush_sizes[l]
		save_tool_settings()
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)

	# Título de funciones
	var func_lbl = Label.new()
	func_lbl.text = tr("func")
	func_lbl.add_theme_font_size_override("font_size", int(22 * s))
	func_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	func_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	v_box.add_child(func_lbl)
	grid.ui_elements["func_lbl"] = func_lbl

	# Botón Comunidad / Taller Online
	var community_btn = Button.new()
	community_btn.text = "🌐 " + tr("btn_comunidad")
	community_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	community_btn.custom_minimum_size = Vector2(0, 60 * s)
	community_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	community_btn.add_theme_font_size_override("font_size", int(21 * s))
	community_btn.mouse_filter = Control.MOUSE_FILTER_PASS

	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	c_style.border_width_left = 2; c_style.border_width_top = 2
	c_style.border_width_right = 2; c_style.border_width_bottom = 2
	c_style.border_color = Color("#48dbfb").lerp(Color.BLACK, 0.3)
	c_style.set_corner_radius_all(int(12 * s))
	community_btn.add_theme_stylebox_override("normal", c_style)

	var c_hover = c_style.duplicate()
	c_hover.bg_color = Color("#48dbfb").lerp(Color.BLACK, 0.7)
	c_hover.border_color = Color("#48dbfb")
	community_btn.add_theme_stylebox_override("hover", c_hover)
	community_btn.add_theme_stylebox_override("pressed", c_hover)

	community_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		_stop_pulse(community_btn)

		grid.is_daily_workshop_pulse_ready = false
		var today_str = str(Time.get_date_dict_from_system().day)
		var f = FileAccess.open("user://workshop_daily_pulse.save", FileAccess.WRITE)
		if f:
			f.store_string(today_str)
			f.close()

		var save_path = "user://workshop_discovery_shown.save"
		if not FileAccess.file_exists(save_path):
			var file = FileAccess.open(save_path, FileAccess.WRITE)
			if file:
				file.store_string("shown")
				file.close()

		if grid.ui_elements.has("workshop_discovery_bubble"):
			var b = grid.ui_elements["workshop_discovery_bubble"]
			if is_instance_valid(b):
				b.queue_free()
			grid.ui_elements.erase("workshop_discovery_bubble")

		grid._toggle_category_panel(grid.workshop_panel)
	)
	v_box.add_child(community_btn)
	grid.ui_elements["btn_comunidad"] = community_btn

	var rotate_timer = Timer.new()
	rotate_timer.wait_time = 3.0
	rotate_timer.autostart = true
	rotate_timer.timeout.connect(func():
		if not is_instance_valid(community_btn): return
		var states = ["btn_comunidad", "btn_top_semanal", "btn_recien_subidos"]
		var current_idx = community_btn.get_meta("state_idx", 0)
		current_idx = (current_idx + 1) % states.size()
		community_btn.set_meta("state_idx", current_idx)
		community_btn.text = "🌐 " + tr(states[current_idx])
	)
	community_btn.add_child(rotate_timer)

	var c_spacer = Control.new()
	c_spacer.custom_minimum_size = Vector2(0, 10 * s)
	v_box.add_child(c_spacer)

	# Fila de acciones (Borrador y Guardar)
	var action_row = GridContainer.new()
	action_row.columns = 2
	action_row.add_theme_constant_override("h_separation", int(10 * s))
	action_row.add_theme_constant_override("v_separation", int(10 * s))
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_box.add_child(action_row)

	var create_action_btn = func(text_key: String, accent_color: Color, callback: Callable) -> Button:
		var btn = Button.new()
		btn.text = tr(text_key)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60 * s)
		btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
		btn.add_theme_font_size_override("font_size", int(21 * s))
		btn.mouse_filter = Control.MOUSE_FILTER_PASS

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
		style.border_width_left = 2; style.border_width_top = 2
		style.border_width_right = 2; style.border_width_bottom = 2
		style.border_color = accent_color.lerp(Color.BLACK, 0.3)
		style.set_corner_radius_all(int(12 * s))
		btn.add_theme_stylebox_override("normal", style)
		btn.set_meta("base_style", style)

		var hover = style.duplicate()
		hover.bg_color = accent_color.lerp(Color.BLACK, 0.7)
		hover.border_color = accent_color
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)

		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			callback.call()
		)
		action_row.add_child(btn)
		grid.ui_elements[text_key + "_btn"] = btn
		return btn

	create_action_btn.call("eraser_tool", Color("#ff6b6b"), func():
		grid.selected_material = 0
		brush_radius = 3
		save_tool_settings()
		grid._update_material_highlights()
		grid._update_menu_highlights()
		grid._on_arcade_selection_made(true)
	)
	create_action_btn.call("save_btn_ui", Color("#feca57"), func():
		if is_instance_valid(grid.save_panel):
			grid.save_panel.queue_free()
		else:
			grid._setup_save_ui()
	)

	# Botón Apoyar al Creador (Anuncio recompensado)
	var support_btn = Button.new()
	support_btn.text = tr("support")
	support_btn.custom_minimum_size = Vector2(0, 60 * s)
	support_btn.add_theme_font_size_override("font_size", int(24 * s))
	support_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())

	var support_style = StyleBoxFlat.new()
	support_style.bg_color = Color(0.1, 0.35, 0.2, 0.9)
	support_style.border_width_left = 2; support_style.border_width_top = 2
	support_style.border_width_right = 2; support_style.border_width_bottom = 2
	support_style.border_color = Color(0.3, 0.6, 0.4)
	support_style.set_corner_radius_all(int(12 * s))

	support_btn.add_theme_stylebox_override("normal", support_style)
	support_btn.add_theme_stylebox_override("hover", support_style)
	support_btn.add_theme_stylebox_override("pressed", support_style)
	support_btn.add_theme_color_override("font_color", Color.GOLD)
	support_btn.mouse_filter = Control.MOUSE_FILTER_PASS

	support_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		AnalyticsManager.log_event("support_creator_clicked", {})

		var prev_paused = grid.is_paused
		if not grid.is_paused:
			grid.is_paused = true
			var p_btn = grid.ui_elements.get("pause_btn")
			if is_instance_valid(p_btn):
				p_btn.text = tr("play")
			_set_environmental_audio_paused(true)

		if Engine.has_singleton("PoingGodotAdMob"):
			var on_ad_dismissed_callable = func():
				AnalyticsManager.log_event("support_creator_completed", {})
				_show_thank_you_popup(prev_paused)

			AdMobManager.ad_dismissed.connect(on_ad_dismissed_callable, CONNECT_ONE_SHOT)
			var ad_shown = await AdMobManager.show_rewarded()
			if not ad_shown:
				if AdMobManager.ad_dismissed.is_connected(on_ad_dismissed_callable):
					AdMobManager.ad_dismissed.disconnect(on_ad_dismissed_callable)
				if not prev_paused:
					grid.is_paused = false
					var p_btn = grid.ui_elements.get("pause_btn")
					if is_instance_valid(p_btn):
						p_btn.text = tr("pause")
					_set_environmental_audio_paused(false)
		else:
			var tree = get_tree()
			if not tree and is_instance_valid(grid): tree = grid.get_tree()
			if tree:
				await tree.create_timer(1.0).timeout
			AnalyticsManager.log_event("support_creator_completed", {})
			_show_thank_you_popup(prev_paused)
	)
	grid.ui_elements["support_btn"] = support_btn
	v_box.add_child(support_btn)

	# Botón de Pausa con cuenta regresiva de seguridad
	var pause_btn = Button.new()
	pause_btn.text = tr("play") if grid.is_paused else tr("pause")
	pause_btn.custom_minimum_size = Vector2(0, 50 * s)
	pause_btn.add_theme_font_size_override("font_size", int(24 * s))
	pause_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())

	var pause_style = StyleBoxFlat.new()
	pause_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	pause_style.border_width_left = 2; pause_style.border_width_top = 2
	pause_style.border_width_right = 2; pause_style.border_width_bottom = 2
	pause_style.border_color = Color(0.25, 0.5, 0.8)
	pause_style.set_corner_radius_all(int(12 * s))

	pause_btn.add_theme_stylebox_override("normal", pause_style)
	pause_btn.add_theme_stylebox_override("hover", pause_style)
	pause_btn.add_theme_stylebox_override("pressed", pause_style)
	pause_btn.add_theme_color_override("font_color", Color.WHITE)
	pause_btn.mouse_filter = Control.MOUSE_FILTER_PASS

	pause_btn.pressed.connect(func():
		_play_action_sound("ui_click")

		if grid.is_paused:
			if is_unpausing:
				is_unpausing = false
				pause_btn.text = tr("play")
				return

			is_unpausing = true
			var ad_shown = false
			if Engine.has_singleton("PoingGodotAdMob"):
				ad_shown = AdMobManager.check_and_show_interstitial("pause")

			if ad_shown:
				await AdMobManager.ad_dismissed

			if not is_unpausing: return

			for i in range(3, 0, -1):
				pause_btn.text = tr("resume_in") + str(i) + "..."
				var tree = get_tree()
				if not tree and is_instance_valid(grid): tree = grid.get_tree()
				if tree:
					await tree.create_timer(1.0).timeout
				if not is_unpausing: return

			is_unpausing = false
			grid.is_paused = false
			pause_btn.text = tr("pause")
		else:
			grid.is_paused = true
			is_unpausing = false
			pause_btn.text = tr("play")
			if Engine.has_singleton("PoingGodotAdMob"):
				AdMobManager.check_and_show_interstitial("pause")

		_set_environmental_audio_paused(grid.is_paused)
	)
	grid.ui_elements["pause_btn"] = pause_btn

	var pause_margin = MarginContainer.new()
	pause_margin.add_theme_constant_override("margin_left", int(32 * s))
	pause_margin.add_theme_constant_override("margin_right", int(32 * s))
	pause_margin.add_theme_constant_override("margin_top", int(4 * s))
	pause_margin.add_theme_constant_override("margin_bottom", int(4 * s))
	v_box.add_child(pause_margin)
	pause_margin.add_child(pause_btn)

	# Botón Reiniciar Cuadrícula
	var reset_btn_node = Button.new()
	reset_btn_node.text = tr("reset")
	reset_btn_node.custom_minimum_size = Vector2(0, 50 * s)
	reset_btn_node.add_theme_font_size_override("font_size", int(24 * s))
	reset_btn_node.add_theme_font_override("font", SandboxFontHelper.get_safe_font())

	var reset_style = StyleBoxFlat.new()
	reset_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	reset_style.border_width_left = 2; reset_style.border_width_top = 2
	reset_style.border_width_right = 2; reset_style.border_width_bottom = 2
	reset_style.border_color = Color(0.8, 0.35, 0.35)
	reset_style.set_corner_radius_all(int(12 * s))

	reset_btn_node.add_theme_stylebox_override("normal", reset_style)
	reset_btn_node.add_theme_stylebox_override("hover", reset_style)
	reset_btn_node.add_theme_stylebox_override("pressed", reset_style)
	reset_btn_node.add_theme_color_override("font_color", Color.WHITE)
	reset_btn_node.mouse_filter = Control.MOUSE_FILTER_PASS

	reset_btn_node.pressed.connect(func():
		_play_action_sound("ui_click")
		grid._clear_all()
		if Engine.has_singleton("PoingGodotAdMob"):
			AdMobManager.check_and_show_interstitial("reset")
	)
	grid.ui_elements["reset_btn"] = reset_btn_node

	var reset_margin = MarginContainer.new()
	reset_margin.add_theme_constant_override("margin_left", int(32 * s))
	reset_margin.add_theme_constant_override("margin_right", int(32 * s))
	reset_margin.add_theme_constant_override("margin_top", int(4 * s))
	reset_margin.add_theme_constant_override("margin_bottom", int(4 * s))
	v_box.add_child(reset_margin)
	reset_margin.add_child(reset_btn_node)

	# Control de Volumen Master
	var vol_lbl = Label.new()
	vol_lbl.text = tr("volumen")
	vol_lbl.add_theme_font_size_override("font_size", int(22 * s))
	vol_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	vol_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	v_box.add_child(vol_lbl)

	var vol_hbox = HBoxContainer.new()
	vol_hbox.add_theme_constant_override("separation", int(15 * s))
	v_box.add_child(vol_hbox)

	var vol_slider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.5
	vol_slider.step = 0.01
	vol_slider.value = game_volume
	vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_slider.custom_minimum_size = Vector2(0, 50 * s)
	vol_hbox.add_child(vol_slider)

	var mute_btn = Button.new()
	mute_btn.custom_minimum_size = Vector2(60 * s, 60 * s)
	mute_btn.add_theme_font_size_override("font_size", int(30 * s))
	mute_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	vol_hbox.add_child(mute_btn)

	var update_mute_icon = func(val: float):
		if val == 0: mute_btn.text = "🔇"
		elif val <= 0.5: mute_btn.text = "🔈"
		elif val <= 1.0: mute_btn.text = "🔉"
		else: mute_btn.text = "🔊"

	update_mute_icon.call(game_volume)

	vol_slider.value_changed.connect(func(val: float):
		game_volume = val
		if val > 0:
			is_muted = false
			pre_mute_volume = val
		else:
			is_muted = true
		update_game_volume(val)
		update_mute_icon.call(val)
		save_tool_settings()
	)

	mute_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		if is_muted:
			is_muted = false
			game_volume = pre_mute_volume if pre_mute_volume > 0 else 1.0
		else:
			is_muted = true
			pre_mute_volume = game_volume
			game_volume = 0.0

		vol_slider.value = game_volume
		update_game_volume(game_volume)
		update_mute_icon.call(game_volume)
		save_tool_settings()
	)

	# Botón de Privacidad / GDPR en plataformas móviles
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		var privacy_btn = Button.new()
		privacy_btn.text = tr("privacy_settings")
		privacy_btn.custom_minimum_size = Vector2(0, 50 * s)
		privacy_btn.add_theme_font_size_override("font_size", int(24 * s))
		privacy_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())

		var privacy_style = StyleBoxFlat.new()
		privacy_style.bg_color = Color(0.15, 0.4, 0.75, 0.9)
		privacy_style.border_width_left = 2; privacy_style.border_width_top = 2
		privacy_style.border_width_right = 2; privacy_style.border_width_bottom = 2
		privacy_style.border_color = Color(0.3, 0.6, 0.9)
		privacy_style.set_corner_radius_all(int(12 * s))

		privacy_btn.add_theme_stylebox_override("normal", privacy_style)
		privacy_btn.add_theme_stylebox_override("hover", privacy_style)
		privacy_btn.add_theme_stylebox_override("pressed", privacy_style)
		privacy_btn.add_theme_color_override("font_color", Color.WHITE)
		privacy_btn.mouse_filter = Control.MOUSE_FILTER_PASS

		privacy_btn.pressed.connect(func():
			_play_action_sound("ui_click")
			if Engine.has_singleton("PoingGodotAdMob"):
				AdMobManager.show_consent_options()
		)

		var btn_margin = MarginContainer.new()
		btn_margin.add_theme_constant_override("margin_left", int(24 * s))
		btn_margin.add_theme_constant_override("margin_right", int(24 * s))
		btn_margin.add_theme_constant_override("margin_top", int(8 * s))
		btn_margin.add_theme_constant_override("margin_bottom", int(8 * s))
		v_box.add_child(btn_margin)
		btn_margin.add_child(privacy_btn)

		btn_margin.visible = AdMobManager.is_privacy_button_required()
		AdMobManager.consent_info_updated.connect(func():
			if is_instance_valid(btn_margin):
				btn_margin.visible = AdMobManager.is_privacy_button_required()
		)

	grid._add_ui_header(v_box, "coming_soon")

	create_row.call("speed", ["x0.2", "x0.5", "x0.8", "x1", "x2", "x4"], func(_l): pass, true)
	create_row.call("shapes", [
		tr("line"),
		tr("rect"),
		tr("circ"),
		tr("tria")
	], func(_l): pass, true)

	var current_ver = str(ProjectSettings.get_setting("application/config/version", "1.2.0"))
	var version_lbl = Label.new()
	version_lbl.text = "Version-game: " + current_ver
	version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	version_lbl.add_theme_font_size_override("font_size", int(16 * s))
	version_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))

	var ver_margin = MarginContainer.new()
	ver_margin.add_theme_constant_override("margin_top", int(15 * s))
	ver_margin.add_theme_constant_override("margin_bottom", int(20 * s))
	ver_margin.add_child(version_lbl)
	v_box.add_child(ver_margin)


func on_tools_btn_pressed() -> void:
	if not is_instance_valid(grid): return
	grid._toggle_category_panel(tools_panel)
	if is_instance_valid(tools_panel) and tools_panel.visible:
		grid._show_menu_reminder("tools", tools_panel.get_child(0), "TUTORIAL_STEP_2")

		if grid.get("is_workshop_discovery_ready") == true:
			grid._trigger_workshop_discovery()
		elif grid.get("is_daily_workshop_pulse_ready") == true:
			if grid.ui_elements.has("tools_btn"):
				_stop_pulse(grid.ui_elements["tools_btn"])
			if grid.ui_elements.has("btn_comunidad"):
				_start_pulse(grid.ui_elements["btn_comunidad"])

	if grid.get("lab_tutorial_step") == 6:
		grid._update_lab_tutorial_highlight()


# =========================================================================
# 3. PANEL DE PINTURA (paint_panel)
# =========================================================================

func setup_paint_ui() -> void:
	if not is_instance_valid(grid): return
	grid._set_panning_mode(false)
	var s = _get_ui_scale()

	var paint_btn = grid._create_vertical_category_btn("🎨", "paint")
	paint_btn.name = "PaintBtn"
	grid.ui_elements["paint_btn"] = paint_btn
	paint_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	paint_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	paint_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if is_instance_valid(grid.action_hbox):
		grid.action_hbox.add_child(paint_btn)

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.2, 0.15, 1.0)
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.6, 0.6, 0.3)
	paint_btn.add_theme_stylebox_override("normal", btn_style)
	paint_btn.add_theme_stylebox_override("hover", btn_style)
	paint_btn.add_theme_stylebox_override("pressed", btn_style)
	paint_btn.set_meta("base_style", btn_style)

	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root): return

	if is_instance_valid(paint_panel):
		paint_panel.queue_free()

	paint_panel = PanelContainer.new()
	paint_panel.name = "PaintPanel"
	ui_root.add_child(paint_panel)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.05, 0.95)
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.6, 0.3)
	panel_style.corner_radius_top_left = int(30 * s); panel_style.corner_radius_top_right = int(30 * s)
	paint_panel.add_theme_stylebox_override("panel", panel_style)

	var p_width = 540 * s
	var p_height = 680 * s
	if is_inside_tree() and _get_viewport_rect().size.x > _get_viewport_rect().size.y:
		p_height = 570 * s

	grid._align_panel_to_hud(paint_panel, p_width, p_height)
	paint_panel.visible = ui_root.get_meta("paint_v", false)

	paint_btn.pressed.connect(func():
		grid._toggle_category_panel(paint_panel)
		if is_instance_valid(paint_panel) and paint_panel.visible:
			var inner_vbox = paint_panel.find_child("PaintVBox", true, false)
			if inner_vbox:
				grid._show_menu_reminder("paint", inner_vbox, "TUTORIAL_STEP_6")
			grid.selected_material = -1
			grid._update_material_highlights()
			update_paint_recent_ui()
	)

	paint_panel.mouse_entered.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = true)
	paint_panel.mouse_exited.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = false)

	var scroll = ScrollContainer.new()
	scroll.name = "PaintScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 25
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	paint_panel.add_child(scroll)

	var main_vbox = VBoxContainer.new()
	main_vbox.name = "PaintVBox"
	main_vbox.add_theme_constant_override("separation", int(15 * s))
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main_vbox)

	var title = Label.new()
	title.text = tr("paint")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	title.add_theme_font_size_override("font_size", int(34 * s))
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	main_vbox.add_child(title)

	var mode_margin = MarginContainer.new()
	mode_margin.add_theme_constant_override("margin_left", int(15 * s))
	mode_margin.add_theme_constant_override("margin_right", int(15 * s))
	main_vbox.add_child(mode_margin)

	var mode_hbox = HBoxContainer.new()
	mode_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_hbox.add_theme_constant_override("separation", int(20 * s))
	mode_margin.add_child(mode_hbox)

	var create_mode_btn = func(text_key: String, mode_idx: int) -> Button:
		var btn = Button.new()
		btn.text = tr(text_key)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 50 * s)
		btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
		btn.add_theme_font_size_override("font_size", int(22 * s))
		btn.mouse_filter = Control.MOUSE_FILTER_PASS

		var st_n = StyleBoxFlat.new()
		st_n.bg_color = Color(0.12, 0.12, 0.15, 0.8)
		st_n.border_width_left = 1; st_n.border_width_top = 1
		st_n.border_width_right = 1; st_n.border_width_bottom = 1
		st_n.border_color = Color(0.3, 0.3, 0.4)
		st_n.set_corner_radius_all(int(12 * s))
		btn.add_theme_stylebox_override("normal", st_n)

		var st_p = StyleBoxFlat.new()
		st_p.bg_color = Color(0.2, 0.5, 1.0)
		st_p.set_corner_radius_all(int(12 * s))
		st_p.border_width_bottom = int(4 * s)
		st_p.border_color = Color(0.5, 0.8, 1.0)
		btn.add_theme_stylebox_override("pressed", st_p)
		btn.add_theme_stylebox_override("hover", st_p)

		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			paint_mode = mode_idx
			for b in mode_hbox.get_children():
				if b != btn: b.button_pressed = false
			btn.button_pressed = true
		)

		btn.button_pressed = (paint_mode == mode_idx)
		mode_hbox.add_child(btn)
		return btn

	create_mode_btn.call("paint_elements", 0)
	create_mode_btn.call("paint_background", 1)

	var color_grid = GridContainer.new()
	color_grid.columns = 6
	color_grid.add_theme_constant_override("h_separation", int(10 * s))
	color_grid.add_theme_constant_override("v_separation", int(10 * s))
	color_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(color_grid)

	var base_colors = [
		Color("#ffffff"), Color("#616161"), Color("#000000"), Color("#FF0000"), Color("#FF4C00"), Color("#FF8800"),
		Color("#FFE900"), Color("#E1FF00"), Color("#A5FF00"), Color("#55FF00"), Color("#00FF61"), Color("#00FFC3"),
		Color("#00EEFF"), Color("#00BFFF"), Color("#0083FF"), Color("#005DFF"), Color("#003cffff"), Color("#4c00ffff"),
		Color("#A900FF"), Color("#DD00FF"), Color("#FF00C3"), Color("#FF0083"), Color("#FF79A1"), Color("#FFA579")
	]

	for c in base_colors:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(70 * s, 70 * s)
		var st = StyleBoxFlat.new()
		st.bg_color = c
		st.set_corner_radius_all(int(10 * s))
		btn.add_theme_stylebox_override("normal", st)
		btn.add_theme_stylebox_override("hover", st)
		btn.add_theme_stylebox_override("pressed", st)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS

		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			selected_paint_color = c
			update_paint_slider_grabber()
			add_recent_paint_color(c)
		)
		color_grid.add_child(btn)

	var custom_hbox = HBoxContainer.new()
	custom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(custom_hbox)

	var custom_cp = ColorPickerButton.new()
	custom_cp.text = "Color Personalizado"
	custom_cp.custom_minimum_size = Vector2(300 * s, 50 * s)
	custom_cp.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	custom_cp.add_theme_font_size_override("font_size", int(20 * s))
	custom_cp.mouse_filter = Control.MOUSE_FILTER_PASS
	custom_cp.color_changed.connect(func(c: Color):
		selected_paint_color = c
		update_paint_slider_grabber()
	)
	custom_cp.popup_closed.connect(func():
		add_recent_paint_color(custom_cp.color)
	)
	custom_hbox.add_child(custom_cp)

	var recent_hbox = HBoxContainer.new()
	recent_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	recent_hbox.add_theme_constant_override("separation", int(15 * s))
	main_vbox.add_child(recent_hbox)
	grid.ui_elements["paint_recent_colors"] = recent_hbox
	update_paint_recent_ui()

	var slider_vbox = VBoxContainer.new()
	slider_vbox.add_theme_constant_override("separation", int(5 * s))
	main_vbox.add_child(slider_vbox)

	var slider_label = Label.new()
	slider_label.text = tr("brush")
	slider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slider_label.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	slider_label.add_theme_font_size_override("font_size", int(20 * s))
	slider_vbox.add_child(slider_label)

	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 5
	slider.step = 1
	slider.value = paint_brush_radius_idx
	slider.custom_minimum_size = Vector2(400 * s, 40 * s)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var slider_style = StyleBoxFlat.new()
	slider_style.bg_color = Color(0.3, 0.3, 0.3)
	slider_style.content_margin_top = int(8 * s)
	slider_style.content_margin_bottom = int(8 * s)
	slider_style.set_corner_radius_all(int(8 * s))
	slider.add_theme_stylebox_override("slider", slider_style)

	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = selected_paint_color
	grabber_style.border_width_left = 2; grabber_style.border_width_top = 2
	grabber_style.border_width_right = 2; grabber_style.border_width_bottom = 2
	grabber_style.border_color = Color.BLACK
	grabber_style.set_corner_radius_all(int(15 * s))
	grabber_style.expand_margin_left = int(10 * s); grabber_style.expand_margin_right = int(10 * s)
	grabber_style.expand_margin_top = int(10 * s); grabber_style.expand_margin_bottom = int(10 * s)

	grid.ui_elements["paint_grabber_style"] = grabber_style
	slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())

	slider.value_changed.connect(func(v: float):
		_play_action_sound("ui_click")
		paint_brush_radius_idx = int(v)
		var _sizes = [1, 3, 5, 10, 15, 25]
		slider_label.text = tr("brush") + ": " + str(_sizes[paint_brush_radius_idx])
		save_tool_settings()
	)
	slider_vbox.add_child(slider)

	var sizes = [1, 3, 5, 10, 15, 25]
	slider_label.text = tr("brush") + ": " + str(sizes[paint_brush_radius_idx])


func add_recent_paint_color(c: Color) -> void:
	if recent_paint_colors.has(c):
		recent_paint_colors.erase(c)
	recent_paint_colors.insert(0, c)
	if recent_paint_colors.size() > 6:
		recent_paint_colors.pop_back()
	update_paint_recent_ui()


func update_paint_recent_ui() -> void:
	if not is_instance_valid(grid): return
	var s = _get_ui_scale()
	var hbox = grid.ui_elements.get("paint_recent_colors")
	if not is_instance_valid(hbox): return

	for child in hbox.get_children():
		child.queue_free()

	for i in range(6):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(60 * s, 60 * s)
		var st = StyleBoxFlat.new()
		st.set_corner_radius_all(int(30 * s))

		if i < 5:
			var c = recent_paint_colors[i] if i < recent_paint_colors.size() else Color.WHITE
			st.bg_color = c
			if c.to_html() == selected_paint_color.to_html() and selected_paint_color.a > 0:
				st.border_width_left = int(8 * s); st.border_width_top = int(8 * s)
				st.border_width_right = int(8 * s); st.border_width_bottom = int(8 * s)
				st.border_color = Color(0.2, 0.6, 1.0)

			btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_paint_color = c
				update_paint_slider_grabber()
				update_paint_recent_ui()
			)
		else:
			btn.text = "🧼"
			btn.add_theme_font_size_override("font_size", int(30 * s))
			st.bg_color = Color(0.1, 0.1, 0.12)
			if selected_paint_color.a == 0:
				st.border_width_left = int(8 * s); st.border_width_top = int(8 * s)
				st.border_width_right = int(8 * s); st.border_width_bottom = int(8 * s)
				st.border_color = Color(0.2, 0.6, 1.0)

			btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_paint_color = Color(0, 0, 0, 0)
				update_paint_slider_grabber()
				update_paint_recent_ui()
			)

		btn.add_theme_stylebox_override("normal", st)
		btn.add_theme_stylebox_override("hover", st)
		btn.add_theme_stylebox_override("pressed", st)
		hbox.add_child(btn)


func update_paint_slider_grabber() -> void:
	if not is_instance_valid(grid): return
	var st = grid.ui_elements.get("paint_grabber_style")
	if st is StyleBoxFlat:
		st.bg_color = selected_paint_color
	update_paint_recent_ui()
