extends Node
class_name SandboxWorkshopUI

## Módulo especializado en la Comunidad y Taller Online (Workshop).
## Administra:
## 1. Conexión con Firebase Firestore (colecciones "community_worlds" y "cache") y Cloud Storage ("worlds/", "thumbnails/").
## 2. Pestañas de contenido: Top Semanal (con subcategorías: Histórico, Tendencias, Joyas Ocultas, Ruleta de la suerte), Recientes, Mis Descargas y Mis Mundos.
## 3. Paginación y caché local inteligente en disco (user://top_semanal_cache.json, user://recientes_cache.json, user://downloads.json, user://ruleta_state.json, user://workshop_cache.dat).
## 4. Búsqueda de mapas mediante código alfanumérico de 8 caracteres con dígito verificador hash (Base 36).
## 5. Likes locales e interactivos con sincronización perezosa (lazy sync) y buffer diferido (RTDB action buffer).
## 6. Descarga y descompresión de mundos (.sbu / .dat) con consumo de cuota diaria gratuita y anuncios recompensados AdMob.
## 7. Ejecución de mapas descargados mediante integración con SandboxSaveSystem.
## 8. Subida y edición de mapas en la nube con selección de ranura local y gestión de límite diario.

# Referencia a la cuadrícula principal
var grid: Node = null

# Panel visual principal del taller
var workshop_panel: PanelContainer = null

# Caché en memoria y referencias de interfaz
var _cached_top_semanal_doc = null
var _cached_recientes_doc = null
var top_countdown_label: Label = null
var bot_countdown_label: Label = null
var top_downloads_count_label: Label = null

# Economía y límites del taller
var free_downloads_remaining: int = 4
var pending_ad_upload: bool = false
var uploads_today: int = 0
var last_upload_day: int = 0
var liked_worlds: Array = []
var reported_worlds: Array = []


# =========================================================================
# INICIALIZACIÓN Y CONFIGURACIÓN
# =========================================================================

func setup(p_grid: Node) -> void:
	grid = p_grid
	load_workshop_economy()
	update_day_check()
	
	if has_node("/root/WorkshopManager"):
		var wm = get_node("/root/WorkshopManager")
		if wm.has_signal("google_play_auth_changed"):
			if not wm.google_play_auth_changed.is_connected(_on_auth_changed):
				wm.google_play_auth_changed.connect(_on_auth_changed)


func _process(_delta: float) -> void:
	process_countdown()


# =========================================================================
# MÉTODOS AUXILIARES SEGUROS
# =========================================================================

func _get_ui_scale() -> float:
	if is_instance_valid(grid) and grid.has_method("_get_ui_scale"):
		return grid._get_ui_scale()
	return 1.7


func _get_safe_font() -> Font:
	if is_instance_valid(grid) and grid.has_method("_get_safe_font"):
		return grid._get_safe_font()
	return SandboxFontHelper.get_safe_font()


func _get_ui_root() -> CanvasLayer:
	if is_instance_valid(grid):
		if "ui_root" in grid and is_instance_valid(grid.ui_root):
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


func _align_panel_to_hud(panel: Control, p_width: float, p_height: float) -> void:
	if is_instance_valid(grid) and grid.has_method("_align_panel_to_hud"):
		grid._align_panel_to_hud(panel, p_width, p_height)
	else:
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
		panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		panel.grow_vertical = Control.GROW_DIRECTION_END
		var h_base = grid.cached_hud_height if is_instance_valid(grid) and "cached_hud_height" in grid else 70.0
		panel.offset_left = -p_width / 2.0
		panel.offset_right = p_width / 2.0
		panel.offset_bottom = -h_base
		panel.offset_top = -h_base - p_height


func _setup_main_ui_containers() -> void:
	if is_instance_valid(grid) and grid.has_method("_setup_main_ui_containers"):
		grid._setup_main_ui_containers()
	else:
		setup_workshop_ui()


func _show_centered_bubble(text: String, color: Color = Color.WHITE) -> void:
	if is_instance_valid(grid) and grid.has_method("_show_centered_bubble"):
		grid._show_centered_bubble(text, color)
	elif is_instance_valid(grid) and "dialog_manager" in grid and is_instance_valid(grid.dialog_manager):
		grid.dialog_manager.show_centered_bubble(text, color)


func _show_processing_overlay(message: String) -> Control:
	if is_instance_valid(grid) and grid.has_method("_show_processing_overlay"):
		return grid._show_processing_overlay(message)
	elif is_instance_valid(grid) and "save_system" in grid and is_instance_valid(grid.save_system):
		return grid.save_system.show_processing_overlay(message)
	return null


func _show_confirm_dialog(title: String, message: String, on_confirm: Callable) -> void:
	if is_instance_valid(grid) and grid.has_method("_show_confirm_dialog"):
		grid._show_confirm_dialog(title, message, on_confirm)
	elif is_instance_valid(grid) and "save_system" in grid and is_instance_valid(grid.save_system):
		grid.save_system.show_confirm_dialog(title, message, on_confirm)


func _show_modal_message(title: String, message: String) -> void:
	if is_instance_valid(grid) and grid.has_method("_show_modal_message"):
		grid._show_modal_message(title, message)
	elif is_instance_valid(grid) and "save_system" in grid and is_instance_valid(grid.save_system):
		grid.save_system.show_modal_message(title, message)


func _close_all_popups() -> void:
	if is_instance_valid(grid) and grid.has_method("_close_all_popups"):
		grid._close_all_popups()


func _load_world_from_path(path: String) -> void:
	if is_instance_valid(grid) and "save_system" in grid and is_instance_valid(grid.save_system):
		grid.save_system.load_world_from_path(path)
	elif is_instance_valid(grid) and grid.has_method("_load_world_from_path"):
		grid._load_world_from_path(path)


func _get_slot_data(slot_id: int) -> Dictionary:
	if is_instance_valid(grid) and "save_system" in grid and is_instance_valid(grid.save_system):
		return grid.save_system.get_slot_data(slot_id)
	elif is_instance_valid(grid) and grid.has_method("_get_slot_data"):
		return grid._get_slot_data(slot_id)
	return {}


func _set_mouse_over_ui(val: bool) -> void:
	if is_instance_valid(grid) and "is_mouse_over_ui" in grid:
		grid.is_mouse_over_ui = val


# =========================================================================
# GESTIÓN DEL TEMPORIZADOR Y CUENTA REGRESIVA
# =========================================================================

func process_countdown() -> void:
	if is_instance_valid(top_countdown_label):
		var ui_r = _get_ui_root()
		var top_category = ui_r.get_meta("workshop_top_category", "Top Semanal") if ui_r else "Top Semanal"
		if top_category == "Ruleta":
			top_countdown_label.visible = false
			if is_instance_valid(bot_countdown_label):
				bot_countdown_label.visible = false
		else:
			top_countdown_label.visible = true
			if is_instance_valid(bot_countdown_label):
				bot_countdown_label.visible = true
				
			var is_historico = top_category == "Top Histórico"
			var left = get_next_update_unix(is_historico) - int(Time.get_unix_time_from_system())
			if left <= 0:
				left = 0
				# Invalidar caché en memoria para que el siguiente clic re-descargue
				if is_historico:
					if ui_r: ui_r.set_meta("_cached_top_historico_doc", null)
				else:
					_cached_top_semanal_doc = null
				
			var h = int(left / 3600.0)
			var m = int((left % 3600) / 60.0)
			var s = left % 60
			var text = tr("update_in") + " %02d:%02d:%02d" % [h, m, s]
			top_countdown_label.text = text
			if is_instance_valid(bot_countdown_label):
				bot_countdown_label.text = text


# =========================================================================
# ECONOMÍA Y CONTROL DE FECHAS
# =========================================================================

func load_workshop_economy() -> void:
	var cfg = ConfigFile.new()
	if cfg.load("user://workshop_economy.cfg") == OK:
		var old_free = cfg.get_value("economy", "next_download_is_free", true)
		free_downloads_remaining = cfg.get_value("economy", "free_downloads_remaining", 4 if old_free else 0)
		uploads_today = cfg.get_value("economy", "uploads_today", 0)
		last_upload_day = cfg.get_value("economy", "last_upload_day", 0)
		liked_worlds = cfg.get_value("economy", "liked_worlds", [])
		reported_worlds = cfg.get_value("economy", "reported_worlds", [])


func save_workshop_economy() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("economy", "free_downloads_remaining", free_downloads_remaining)
	cfg.set_value("economy", "uploads_today", uploads_today)
	cfg.set_value("economy", "last_upload_day", last_upload_day)
	cfg.set_value("economy", "liked_worlds", liked_worlds)
	cfg.set_value("economy", "reported_worlds", reported_worlds)
	cfg.save("user://workshop_economy.cfg")


func get_next_update_unix(is_historico: bool = false) -> int:
	var current_unix = int(Time.get_unix_time_from_system())
	var day_seconds = current_unix % 86400
	var threshold_1 = 5 * 60 # 00:05 UTC
	var threshold_2 = (12 * 3600) + (5 * 60) # 12:05 UTC
	var base_day = current_unix - day_seconds
	
	if is_historico:
		if day_seconds < threshold_1:
			return base_day + threshold_1
		else:
			return base_day + 86400 + threshold_1
	else:
		if day_seconds < threshold_1:
			return base_day + threshold_1
		elif day_seconds < threshold_2:
			return base_day + threshold_2
		else:
			return base_day + 86400 + threshold_1


func get_last_update_unix(is_historico: bool = false) -> int:
	var current_unix = int(Time.get_unix_time_from_system())
	var day_seconds = current_unix % 86400
	var threshold_1 = 5 * 60
	var threshold_2 = (12 * 3600) + (5 * 60)
	var base_day = current_unix - day_seconds
	
	if is_historico:
		if day_seconds >= threshold_1:
			return base_day + threshold_1
		else:
			return base_day - 86400 + threshold_1
	else:
		if day_seconds >= threshold_2:
			return base_day + threshold_2
		elif day_seconds >= threshold_1:
			return base_day + threshold_1
		else:
			return base_day - 86400 + threshold_2


func update_day_check() -> void:
	var current_day = Time.get_date_dict_from_system().day
	if last_upload_day != current_day:
		uploads_today = 0
		free_downloads_remaining = 4
		last_upload_day = current_day
		save_workshop_economy()


func _on_auth_changed(_is_auth: bool) -> void:
	if is_instance_valid(workshop_panel) and workshop_panel.visible:
		var ui_root = _get_ui_root()
		if ui_root and ui_root.has_meta("workshop_current_tab") and ui_root.get_meta("workshop_current_tab") == 2:
			call_deferred("_setup_main_ui_containers")


# Aliases con guion bajo para compatibilidad interna
func _load_workshop_economy() -> void: load_workshop_economy()
func _save_workshop_economy() -> void: save_workshop_economy()
func _get_next_update_unix(is_historico: bool = false) -> int: return get_next_update_unix(is_historico)
func _get_last_update_unix(is_historico: bool = false) -> int: return get_last_update_unix(is_historico)
func _update_day_check() -> void: update_day_check()


# =========================================================================
# CONSTRUCCIÓN DE LA INTERFAZ DEL TALLER (WORKSHOP UI)
# =========================================================================

func setup_workshop_ui() -> void:
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root): return
	
	if is_instance_valid(workshop_panel):
		workshop_panel.queue_free()
	
	workshop_panel = PanelContainer.new()
	workshop_panel.name = "WorkshopPanel"
	ui_root.add_child(workshop_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.98) # Dark elegant
	panel_style.border_width_left = 3; panel_style.border_width_top = 3
	panel_style.border_width_right = 3; panel_style.border_width_bottom = 3
	panel_style.border_color = Color("#48dbfb") # Mismo color que botón comunidad
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	panel_style.content_margin_left = int(15 * s)
	panel_style.content_margin_right = int(15 * s)
	panel_style.content_margin_top = int(20 * s)
	panel_style.content_margin_bottom = int(20 * s)
	workshop_panel.add_theme_stylebox_override("panel", panel_style)
	workshop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	workshop_panel.visible = ui_root.get_meta("workshop_v", false)
	var max_w = _get_viewport_rect().size.x - 40 * s
	var p_width = min(610 * s, max_w)
	_align_panel_to_hud(workshop_panel, p_width, 570 * s)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(10 * s))
	workshop_panel.add_child(main_vbox)
	
	# BARRA DE BÚSQUEDA POR CÓDIGO
	var search_hbox = HBoxContainer.new()
	search_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	search_hbox.add_theme_constant_override("separation", int(5 * s))
	main_vbox.add_child(search_hbox)
	
	var search_lbl_code = Label.new()
	search_lbl_code.text = tr("map_code")
	search_lbl_code.add_theme_font_override("font", _get_safe_font())
	search_lbl_code.add_theme_font_size_override("font_size", int(18 * s))
	search_lbl_code.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	search_hbox.add_child(search_lbl_code)
	
	var search_input_base = LineEdit.new()
	search_input_base.placeholder_text = "xxxxxxxx"
	search_input_base.max_length = 15
	search_input_base.custom_minimum_size = Vector2(180 * s, 45 * s)
	search_input_base.add_theme_font_override("font", _get_safe_font())
	search_input_base.add_theme_font_size_override("font_size", int(20 * s))
	search_input_base.alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_input_base.context_menu_enabled = false
	search_hbox.add_child(search_input_base)
	
	# Presión sostenida para pegar en móvil
	var press_timer = Timer.new()
	press_timer.wait_time = 0.6
	press_timer.one_shot = true
	search_hbox.add_child(press_timer)
	
	press_timer.timeout.connect(func():
		var cb = DisplayServer.clipboard_get()
		if cb != "":
			search_input_base.text = cb
			search_input_base.text_changed.emit(cb)
			_play_action_sound("ui_click")
	)
	
	search_input_base.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: press_timer.start()
			else: press_timer.stop()
		elif event is InputEventScreenTouch:
			if event.pressed: press_timer.start()
			else: press_timer.stop()
	)
	
	var search_lbl_dash = Label.new()
	search_lbl_dash.text = "-"
	search_lbl_dash.add_theme_font_override("font", _get_safe_font())
	search_lbl_dash.add_theme_font_size_override("font_size", int(24 * s))
	search_hbox.add_child(search_lbl_dash)
	
	var search_input_check = LineEdit.new()
	search_input_check.placeholder_text = "x"
	search_input_check.max_length = 1
	search_input_check.custom_minimum_size = Vector2(40 * s, 45 * s)
	search_input_check.add_theme_font_override("font", _get_safe_font())
	search_input_check.add_theme_font_size_override("font_size", int(20 * s))
	search_input_check.alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_hbox.add_child(search_input_check)
	
	var search_btn = Button.new()
	search_btn.text = tr("btn_buscar") if TranslationServer.get_locale() == "es" else "Search"
	search_btn.custom_minimum_size = Vector2(80 * s, 45 * s)
	search_btn.add_theme_font_override("font", _get_safe_font())
	search_btn.add_theme_font_size_override("font_size", int(16 * s))
	
	var search_btn_style = StyleBoxFlat.new()
	search_btn_style.bg_color = Color(0, 0, 0, 0)
	search_btn_style.border_width_left = 1; search_btn_style.border_width_top = 1
	search_btn_style.border_width_right = 1; search_btn_style.border_width_bottom = 1
	search_btn_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	search_btn_style.corner_radius_top_left = int(10 * s); search_btn_style.corner_radius_top_right = int(10 * s)
	search_btn_style.corner_radius_bottom_left = int(10 * s); search_btn_style.corner_radius_bottom_right = int(10 * s)
	search_btn.add_theme_stylebox_override("normal", search_btn_style)
	search_btn.add_theme_stylebox_override("hover", search_btn_style)
	search_btn.add_theme_stylebox_override("pressed", search_btn_style)
	search_hbox.add_child(search_btn)
	
	search_input_base.text_changed.connect(func(new_text: String):
		if new_text.find("-") != -1:
			var parts = new_text.split("-")
			if parts.size() >= 2:
				search_input_base.text = parts[0].strip_edges().substr(0, 8)
				search_input_check.text = parts[1].strip_edges().substr(0, 1)
				search_input_check.grab_focus()
				search_input_base.caret_column = search_input_base.text.length()
		elif new_text.length() > 8:
			search_input_base.text = new_text.substr(0, 8)
			search_input_base.caret_column = 8
	)
	
	search_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		AnalyticsManager.log_event("workshop_search", {})
		on_search_world_requested(search_input_base.text.to_lower(), search_input_check.text.to_lower())
	)
	
	# CABECERA DE PESTAÑAS (TAB HEADER)
	var tab_hbox = HBoxContainer.new()
	tab_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_hbox.add_theme_constant_override("separation", int(5 * s))
	main_vbox.add_child(tab_hbox)
	
	var top_category = ui_root.get_meta("workshop_top_category", "Top Semanal")
	
	var btn_hamburger = Button.new()
	btn_hamburger.text = "☰"
	btn_hamburger.custom_minimum_size = Vector2(45 * s, 45 * s)
	btn_hamburger.add_theme_font_override("font", _get_safe_font())
	btn_hamburger.add_theme_font_size_override("font_size", int(24 * s))
	var hamburger_style = StyleBoxFlat.new()
	hamburger_style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	hamburger_style.corner_radius_top_left = int(10 * s); hamburger_style.corner_radius_top_right = int(10 * s)
	hamburger_style.corner_radius_bottom_left = int(10 * s); hamburger_style.corner_radius_bottom_right = int(10 * s)
	hamburger_style.border_color = Color("#48dbfb")
	btn_hamburger.add_theme_stylebox_override("normal", hamburger_style)
	btn_hamburger.add_theme_stylebox_override("hover", hamburger_style)
	btn_hamburger.add_theme_stylebox_override("pressed", hamburger_style)
	tab_hbox.add_child(btn_hamburger)
	
	btn_hamburger.pressed.connect(func():
		_play_action_sound("ui_click")
		var popup = PopupMenu.new()
		popup.add_theme_font_override("font", _get_safe_font())
		popup.add_theme_font_size_override("font_size", int(32 * s))
		popup.add_item(tr("tab_top_semanal"), 0)
		popup.add_item(tr("tab_top_historico"), 1)
		popup.add_item(tr("tab_tendencias"), 2)
		popup.add_item(tr("tab_joyas_ocultas"), 3)
		popup.add_item(tr("tab_ruleta"), 4)
		
		popup.id_pressed.connect(func(id):
			if id == 0: ui_root.set_meta("workshop_top_category", "Top Semanal")
			elif id == 1: ui_root.set_meta("workshop_top_category", "Top Histórico")
			elif id == 2: ui_root.set_meta("workshop_top_category", "Tendencias")
			elif id == 3: ui_root.set_meta("workshop_top_category", "Joyas Ocultas")
			elif id == 4: ui_root.set_meta("workshop_top_category", "Ruleta")
			call_deferred("_setup_main_ui_containers")
		)
		
		btn_hamburger.add_child(popup)
		var btn_rect = btn_hamburger.get_global_rect()
		popup.popup(Rect2(btn_rect.position.x, btn_rect.position.y + btn_rect.size.y, 350 * s, 0))
	)
	
	var current_tab = ui_root.get_meta("workshop_current_tab", 0)
	var create_tab_btn = func(emoji: String, text_key: String, tab_idx: int):
		var btn = Button.new()
		btn.text = emoji + "\n" + tr(text_key)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 55 * s)
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", int(16 * s))
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var t_style = StyleBoxFlat.new()
		if tab_idx == current_tab:
			t_style.bg_color = Color(0.2, 0.5, 1.0, 1.0)
			t_style.corner_radius_top_left = int(10 * s); t_style.corner_radius_top_right = int(10 * s)
			t_style.corner_radius_bottom_left = int(10 * s); t_style.corner_radius_bottom_right = int(10 * s)
		else:
			t_style.bg_color = Color(0, 0, 0, 0)
			t_style.border_width_left = 1; t_style.border_width_top = 1
			t_style.border_width_right = 1; t_style.border_width_bottom = 1
			t_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
			t_style.corner_radius_top_left = int(10 * s); t_style.corner_radius_top_right = int(10 * s)
			t_style.corner_radius_bottom_left = int(10 * s); t_style.corner_radius_bottom_right = int(10 * s)
		
		btn.add_theme_stylebox_override("normal", t_style)
		btn.add_theme_stylebox_override("hover", t_style)
		btn.add_theme_stylebox_override("pressed", t_style)
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			if tab_idx != current_tab:
				var tab_names = ["top", "recents", "my_worlds", "my_downloads"]
				AnalyticsManager.log_event("workshop_tab_view", {"tab": tab_names[tab_idx] if tab_idx < 4 else str(tab_idx)})
			ui_root.set_meta("workshop_current_tab", tab_idx)
			call_deferred("_setup_main_ui_containers")
		)
		tab_hbox.add_child(btn)
		return btn
		
	var btn_top = create_tab_btn.call("🌟", "tab_top_semanal", 0)
	if top_category == "Top Histórico": btn_top.text = "🏛️\n" + tr("tab_top_historico")
	elif top_category == "Tendencias": btn_top.text = "🔥\n" + tr("tab_tendencias")
	elif top_category == "Joyas Ocultas": btn_top.text = "💎\n" + tr("tab_joyas_ocultas")
	elif top_category == "Ruleta": btn_top.text = "🎲\n" + tr("tab_ruleta")
	else: btn_top.text = "🌟\n" + tr("tab_top_semanal")
	
	create_tab_btn.call("🕒", "tab_recientes", 1)
	create_tab_btn.call("⬇️", "tab_mis_descargas", 3)
	var btn_mis = create_tab_btn.call("👤", "tab_mis_mundos", 2)
	
	# Rotación de texto en botón "Mis mundos"
	var rotate_timer = Timer.new()
	rotate_timer.wait_time = 3.0
	rotate_timer.autostart = true
	rotate_timer.timeout.connect(func():
		if not is_instance_valid(btn_mis): return
		var states = ["tab_mis_mundos", "tab_subir_mundo"]
		var emojis = ["👤", "➕"]
		var current_idx = btn_mis.get_meta("state_idx", 0)
		current_idx = (current_idx + 1) % states.size()
		btn_mis.set_meta("state_idx", current_idx)
		btn_mis.text = emojis[current_idx] + "\n" + tr(states[current_idx])
	)
	btn_mis.add_child(rotate_timer)
	
	# ÁREA DE CONTENIDO PRINCIPAL
	var content_panel = PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	c_style.corner_radius_top_left = int(10 * s); c_style.corner_radius_top_right = int(10 * s)
	c_style.corner_radius_bottom_left = int(10 * s); c_style.corner_radius_bottom_right = int(10 * s)
	content_panel.add_theme_stylebox_override("panel", c_style)
	main_vbox.add_child(content_panel)
	
	current_tab = ui_root.get_meta("workshop_current_tab", 0)
	var loading_lbl = Label.new()
	loading_lbl.text = "..."
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_lbl.add_theme_font_override("font", _get_safe_font())
	loading_lbl.add_theme_font_size_override("font_size", int(20 * s))
	content_panel.add_child(loading_lbl)
	
	var http = HTTPRequest.new()
	add_child(http)
	if "timeout" in http: http.timeout = 3.0
	http.request_completed.connect(func(result, _response_code, _headers, _body):
		var net = (result == HTTPRequest.RESULT_SUCCESS)
		if net == false and ui_root.get_meta("has_internet", true) == true:
			ui_root.set_meta("has_internet", false)
			setup_workshop_ui()
		elif net == true and ui_root.get_meta("has_internet", true) == false:
			ui_root.set_meta("has_internet", true)
			setup_workshop_ui()
		if is_instance_valid(http): http.queue_free()
	)
	http.request("https://clients3.google.com/generate_204")
	
	var has_internet = ui_root.get_meta("has_internet", true)
	
	if not is_instance_valid(content_panel): return
	if is_instance_valid(loading_lbl): loading_lbl.queue_free()
	
	if not has_internet and current_tab != 3:
		if is_instance_valid(search_hbox): search_hbox.visible = false
			
		var no_net_vbox = VBoxContainer.new()
		no_net_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		no_net_vbox.add_theme_constant_override("separation", int(20 * s))
		
		var net_icon = Label.new()
		net_icon.text = "🌐❌"
		net_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		net_icon.add_theme_font_override("font", _get_safe_font())
		net_icon.add_theme_font_size_override("font_size", int(80 * s))
		no_net_vbox.add_child(net_icon)
		
		var net_lbl = Label.new()
		net_lbl.text = tr("no_internet")
		net_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		net_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		net_lbl.add_theme_font_override("font", _get_safe_font())
		net_lbl.add_theme_font_size_override("font_size", int(24 * s))
		net_lbl.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		no_net_vbox.add_child(net_lbl)
		
		content_panel.add_child(no_net_vbox)
		return
			
	if current_tab == 0 or current_tab == 1 or current_tab == 3:
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content_panel.add_child(scroll)
		
		var scroll_vbox = VBoxContainer.new()
		scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_vbox.add_theme_constant_override("separation", int(30 * s))
		
		if current_tab == 0:
			top_countdown_label = Label.new()
			top_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			top_countdown_label.add_theme_font_override("font", _get_safe_font())
			top_countdown_label.add_theme_font_size_override("font_size", int(18 * s))
			top_countdown_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			scroll_vbox.add_child(top_countdown_label)
		elif current_tab == 3:
			top_downloads_count_label = Label.new()
			top_downloads_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			top_downloads_count_label.add_theme_font_override("font", _get_safe_font())
			top_downloads_count_label.add_theme_font_size_override("font_size", int(18 * s))
			top_downloads_count_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			scroll_vbox.add_child(top_downloads_count_label)
		
		var card_grid = GridContainer.new()
		card_grid.columns = 2
		card_grid.add_theme_constant_override("h_separation", int(20 * s))
		card_grid.add_theme_constant_override("v_separation", int(20 * s))
		card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		if current_tab == 1:
			var top_actions_hbox = HBoxContainer.new()
			top_actions_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			scroll_vbox.add_child(top_actions_hbox)
			
			var btn_actualizar = Button.new()
			btn_actualizar.text = "🔄 " + tr("btn_actualizar")
			btn_actualizar.custom_minimum_size = Vector2(160 * s, 45 * s)
			btn_actualizar.add_theme_font_override("font", _get_safe_font())
			btn_actualizar.add_theme_font_size_override("font_size", int(16 * s))
			var a_style = StyleBoxFlat.new()
			a_style.bg_color = Color("#2ecc71").lerp(Color.BLACK, 0.6)
			a_style.border_width_left = 2; a_style.border_width_top = 2
			a_style.border_width_right = 2; a_style.border_width_bottom = 2
			a_style.border_color = Color("#2ecc71")
			a_style.corner_radius_top_left = int(10 * s); a_style.corner_radius_top_right = int(10 * s)
			a_style.corner_radius_bottom_left = int(10 * s); a_style.corner_radius_bottom_right = int(10 * s)
			btn_actualizar.add_theme_stylebox_override("normal", a_style)
			var h_style = a_style.duplicate()
			h_style.bg_color = Color("#2ecc71").lerp(Color.BLACK, 0.4)
			btn_actualizar.add_theme_stylebox_override("hover", h_style)
			btn_actualizar.add_theme_stylebox_override("pressed", h_style)
			
			btn_actualizar.pressed.connect(func():
				_play_action_sound("ui_click")
				var current_time = Time.get_unix_time_from_system()
				var cache_time = ui_root.get_meta("workshop_recientes_cache_time", 0.0)
				
				# Cooldown de 5 minutos (300 segundos) para el botón manual
				if cache_time == 0.0 or (current_time - cache_time) >= 300:
					ui_root.set_meta("workshop_recientes_cache_time", 0.0)
					setup_workshop_ui()
				else:
					var loading = _show_processing_overlay(tr("load_worls"))
					await get_tree().create_timer(0.4).timeout
					if is_instance_valid(loading):
						loading.queue_free()
					setup_workshop_ui()
			)
			top_actions_hbox.add_child(btn_actualizar)

		scroll_vbox.add_child(card_grid)
		
		var pagination_hbox = HFlowContainer.new()
		pagination_hbox.alignment = FlowContainer.ALIGNMENT_CENTER
		pagination_hbox.add_theme_constant_override("h_separation", int(15 * s))
		pagination_hbox.add_theme_constant_override("v_separation", int(15 * s))
		scroll_vbox.add_child(pagination_hbox)
		
		if current_tab == 0:
			bot_countdown_label = Label.new()
			bot_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bot_countdown_label.add_theme_font_override("font", _get_safe_font())
			bot_countdown_label.add_theme_font_size_override("font_size", int(18 * s))
			bot_countdown_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			scroll_vbox.add_child(bot_countdown_label)
		
		var margin = MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_left", int(20 * s))
		margin.add_theme_constant_override("margin_top", int(20 * s))
		margin.add_theme_constant_override("margin_right", int(20 * s))
		margin.add_theme_constant_override("margin_bottom", int(40 * s))
		margin.add_child(scroll_vbox)
		scroll.add_child(margin)
		
		var do_fetch = func():
			var p_page = ui_root.get_meta("workshop_page_" + str(current_tab), 1)
			if card_grid.get_child_count() == 0:
				if current_tab == 0:
					call_deferred("fetch_top_async", card_grid, pagination_hbox, p_page)
				elif current_tab == 1:
					call_deferred("fetch_recientes_async", card_grid, pagination_hbox, p_page)
				elif current_tab == 3:
					call_deferred("fetch_mis_descargas_async", card_grid, pagination_hbox, p_page)
		
		if workshop_panel.visible:
			do_fetch.call()
			
		workshop_panel.visibility_changed.connect(func():
			if workshop_panel.visible: do_fetch.call()
		)

	elif current_tab == 4:
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content_panel.add_child(scroll)
		
		var scroll_vbox = VBoxContainer.new()
		scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_vbox.add_theme_constant_override("separation", int(30 * s))
		
		var card_grid = GridContainer.new()
		card_grid.columns = 2
		card_grid.add_theme_constant_override("h_separation", int(20 * s))
		card_grid.add_theme_constant_override("v_separation", int(20 * s))
		card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_vbox.add_child(card_grid)
		
		var margin = MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_left", int(20 * s))
		margin.add_theme_constant_override("margin_top", int(20 * s))
		margin.add_theme_constant_override("margin_right", int(20 * s))
		margin.add_theme_constant_override("margin_bottom", int(40 * s))
		margin.add_child(scroll_vbox)
		scroll.add_child(margin)
		
		var clean_data = ui_root.get_meta("workshop_search_result", {})
		if not clean_data.is_empty():
			var card = preload("res://scenes/main/world_card.tscn").instantiate()
			card_grid.add_child(card)
			card.setup(clean_data, 0)
			card.download_requested.connect(on_world_download_requested)
			
	elif current_tab == 2:
		var mis_mundos_vbox = VBoxContainer.new()
		mis_mundos_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mis_mundos_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mis_mundos_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		mis_mundos_vbox.add_theme_constant_override("separation", int(15 * s))
		content_panel.add_child(mis_mundos_vbox)
		
		var wm = get_node_or_null("/root/WorkshopManager")
		if wm and wm.google_play_id == "":
			mis_mundos_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			var info_label = Label.new()
			info_label.text = tr("auth_required_desc")
			info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			info_label.add_theme_font_override("font", _get_safe_font())
			info_label.add_theme_font_size_override("font_size", int(20 * s))
			mis_mundos_vbox.add_child(info_label)
			
			var btn_vincular = Button.new()
			btn_vincular.text = tr("btn_link_google_play")
			btn_vincular.custom_minimum_size = Vector2(0, 60 * s)
			btn_vincular.add_theme_font_override("font", _get_safe_font())
			btn_vincular.add_theme_font_size_override("font_size", int(22 * s))
			
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = Color("#2ecc71").lerp(Color.BLACK, 0.4)
			b_style.border_width_left = 2; b_style.border_width_top = 2
			b_style.border_width_right = 2; b_style.border_width_bottom = 2
			b_style.border_color = Color("#2ecc71")
			b_style.corner_radius_top_left = int(10 * s); b_style.corner_radius_top_right = int(10 * s)
			b_style.corner_radius_bottom_left = int(10 * s); b_style.corner_radius_bottom_right = int(10 * s)
			btn_vincular.add_theme_stylebox_override("normal", b_style)
			
			var h_style = b_style.duplicate()
			h_style.bg_color = Color("#2ecc71").lerp(Color.BLACK, 0.2)
			btn_vincular.add_theme_stylebox_override("hover", h_style)
			btn_vincular.add_theme_stylebox_override("pressed", h_style)
			
			btn_vincular.pressed.connect(func():
				_play_action_sound("ui_click")
				if OS.has_feature("editor"):
					wm.google_play_name = "ADMIN"
					wm.google_play_id = "EDITOR"
					wm.google_play_auth_changed.emit(true)
				else:
					wm.request_manual_sign_in()
			)
			mis_mundos_vbox.add_child(btn_vincular)
			return
		
		var top_buttons_hbox = HBoxContainer.new()
		top_buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		top_buttons_hbox.add_theme_constant_override("separation", int(10 * s))
		mis_mundos_vbox.add_child(top_buttons_hbox)
		
		var create_top_action_btn = func(text_key: String, btn_color: Color):
			var btn = Button.new()
			btn.text = tr(text_key)
			btn.custom_minimum_size = Vector2(0, 50 * s)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_override("font", _get_safe_font())
			btn.add_theme_font_size_override("font_size", int(18 * s))
			
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = btn_color.lerp(Color.BLACK, 0.6)
			b_style.border_width_left = 2; b_style.border_width_top = 2
			b_style.border_width_right = 2; b_style.border_width_bottom = 2
			b_style.border_color = btn_color
			b_style.corner_radius_top_left = int(10 * s); b_style.corner_radius_top_right = int(10 * s)
			b_style.corner_radius_bottom_left = int(10 * s); b_style.corner_radius_bottom_right = int(10 * s)
			btn.add_theme_stylebox_override("normal", b_style)
			
			var h_style = b_style.duplicate()
			h_style.bg_color = btn_color.lerp(Color.BLACK, 0.4)
			btn.add_theme_stylebox_override("hover", h_style)
			btn.add_theme_stylebox_override("pressed", h_style)
			
			return btn
			
		var btn_subir = create_top_action_btn.call("tab_subir_mundo", Color("#00d2d3"))
		btn_subir.pressed.connect(func():
			_play_action_sound("ui_click")
			if ui_root.has_meta("workshop_total_uploaded_worlds"):
				var total = ui_root.get_meta("workshop_total_uploaded_worlds", 0)
				if total >= 10:
					var msg = tr("msg_upload_limit_reached")
					_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", msg)
					return
					
			show_upload_world_dialog()
		)
		top_buttons_hbox.add_child(btn_subir)
		
		var btn_gestionar = create_top_action_btn.call("btn_gestionar_mundos", Color("#ff9f43"))
		btn_gestionar.pressed.connect(func():
			_play_action_sound("ui_click")
			show_world_manager_dialog()
		)
		top_buttons_hbox.add_child(btn_gestionar)
		
		var btn_actualizar = create_top_action_btn.call("btn_actualizar", Color("#2ecc71"))
		btn_actualizar.pressed.connect(func():
			_play_action_sound("ui_click")
			var current_time = Time.get_unix_time_from_system()
			var cache_time = ui_root.get_meta("workshop_mis_mundos_cache_time", 0.0)
			
			if cache_time == 0.0 or (current_time - cache_time) >= (11 * 60):
				ui_root.set_meta("workshop_mis_mundos_cache_time", 0.0)
				setup_workshop_ui()
			else:
				var loading = _show_processing_overlay(tr("load_worls"))
				await get_tree().create_timer(0.4).timeout
				if is_instance_valid(loading):
					loading.queue_free()
				setup_workshop_ui()
		)
		top_buttons_hbox.add_child(btn_actualizar)
		
		var daily_uploads_label = Label.new()
		daily_uploads_label.text = tr("daily_uploads_status").format([str(uploads_today), "5"])
		daily_uploads_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		daily_uploads_label.add_theme_font_override("font", _get_safe_font())
		daily_uploads_label.add_theme_font_size_override("font_size", int(18 * s))
		daily_uploads_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		mis_mundos_vbox.add_child(daily_uploads_label)
		
		var list_scroll = ScrollContainer.new()
		list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		mis_mundos_vbox.add_child(list_scroll)
		
		var list_margin = MarginContainer.new()
		list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_margin.add_theme_constant_override("margin_left", int(20 * s))
		list_margin.add_theme_constant_override("margin_top", int(20 * s))
		list_margin.add_theme_constant_override("margin_right", int(20 * s))
		list_margin.add_theme_constant_override("margin_bottom", int(40 * s))
		list_scroll.add_child(list_margin)
		
		var grid_and_pag_vbox = VBoxContainer.new()
		grid_and_pag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_and_pag_vbox.add_theme_constant_override("separation", int(20 * s))
		list_margin.add_child(grid_and_pag_vbox)
		
		var list_grid = GridContainer.new()
		list_grid.columns = 2
		list_grid.add_theme_constant_override("h_separation", int(20 * s))
		list_grid.add_theme_constant_override("v_separation", int(20 * s))
		list_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_and_pag_vbox.add_child(list_grid)
		
		var pagination_hbox = HFlowContainer.new()
		pagination_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		pagination_hbox.add_theme_constant_override("h_separation", int(10 * s))
		pagination_hbox.add_theme_constant_override("v_separation", int(10 * s))
		grid_and_pag_vbox.add_child(pagination_hbox)
		
		var page = ui_root.get_meta("workshop_page_2", 1)
		fetch_mis_mundos_async(list_grid, pagination_hbox, page)
		
	workshop_panel.mouse_entered.connect(func(): _set_mouse_over_ui(true))
	workshop_panel.mouse_exited.connect(func(): _set_mouse_over_ui(false))


func build_pagination(pagination_hbox: HFlowContainer, total_items: int) -> void:
	if not is_instance_valid(pagination_hbox): return
	
	for child in pagination_hbox.get_children():
		child.queue_free()
		
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	var total_pages = ceil(float(total_items) / 10.0)
	if total_pages <= 0: total_pages = 1
	
	for i in range(total_pages):
		var page_idx = i + 1
		var p_btn = Button.new()
		p_btn.text = str(page_idx)
		p_btn.custom_minimum_size = Vector2(60 * s, 60 * s)
		
		var b_style = StyleBoxFlat.new()
		var current_tab = ui_root.get_meta("workshop_current_tab", 0) if ui_root else 0
		var current_page = ui_root.get_meta("workshop_page_" + str(current_tab), 1) if ui_root else 1
		b_style.bg_color = Color(0.25, 0.25, 0.3) if page_idx == current_page else Color(0.15, 0.15, 0.2)
		b_style.corner_radius_top_left = int(12 * s); b_style.corner_radius_top_right = int(12 * s)
		b_style.corner_radius_bottom_left = int(12 * s); b_style.corner_radius_bottom_right = int(12 * s)
		p_btn.add_theme_stylebox_override("normal", b_style)
		
		var h_style = b_style.duplicate()
		h_style.bg_color = Color(0.35, 0.35, 0.4)
		p_btn.add_theme_stylebox_override("hover", h_style)
		p_btn.add_theme_stylebox_override("pressed", h_style)
		
		p_btn.add_theme_font_override("font", _get_safe_font())
		p_btn.add_theme_font_size_override("font_size", int(20 * s))
		
		p_btn.pressed.connect(func():
			_play_action_sound("ui_click")
			if ui_root:
				var c_tab = ui_root.get_meta("workshop_current_tab", 0)
				ui_root.set_meta("workshop_page_" + str(c_tab), page_idx)
			_setup_main_ui_containers()
		)
		
		pagination_hbox.add_child(p_btn)


func show_empty_state_message(p_card_grid: GridContainer) -> void:
	var lbl = Label.new()
	lbl.text = tr("no_worlds_here")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_font_size_override("font_size", int(24 * _get_ui_scale()))
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl.custom_minimum_size = Vector2(0, 100 * _get_ui_scale())
	p_card_grid.get_parent().add_child(lbl)
	p_card_grid.get_parent().move_child(lbl, p_card_grid.get_index() + 1)


# Aliases
func _setup_workshop_ui() -> void: setup_workshop_ui()
func _build_pagination(pagination_hbox: HFlowContainer, total_items: int) -> void: build_pagination(pagination_hbox, total_items)
func _show_empty_state_message(p_card_grid: GridContainer) -> void: show_empty_state_message(p_card_grid)


# =========================================================================
# CONSULTAS ASÍNCRONAS Y DESCARGA DE CATÁLOGOS
# =========================================================================

func fetch_top_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1) -> void:
	if not is_instance_valid(p_card_grid): return
	
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var top_category = ui_root.get_meta("workshop_top_category", "Top Semanal")
	var doc_name = "top_semanal"
	if top_category == "Top Histórico": doc_name = "top_historico"
	elif top_category == "Tendencias": doc_name = "tendencias_mensual"
	elif top_category == "Joyas Ocultas": doc_name = "descubrir_hoy"
	elif top_category == "Ruleta": doc_name = "ruleta"
		
	var cache_file = "user://" + doc_name + "_cache.json"
	var document = null
	
	if doc_name == "top_semanal" and _cached_top_semanal_doc != null: document = _cached_top_semanal_doc
	elif ui_root.has_meta("_cached_" + doc_name + "_doc"): document = ui_root.get_meta("_cached_" + doc_name + "_doc")
	
	if document == null:
		var is_historico = doc_name == "top_historico"
		var last_update = get_last_update_unix(is_historico)
		if FileAccess.file_exists(cache_file):
			var cf = FileAccess.open(cache_file, FileAccess.READ)
			if cf:
				var text = cf.get_as_text()
				cf.close()
				if text != "":
					var parsed = JSON.parse_string(text)
					if typeof(parsed) == TYPE_DICTIONARY and parsed.has("fetch_time"):
						if parsed["fetch_time"] >= last_update:
							document = parsed["document"]
							if doc_name == "top_semanal": _cached_top_semanal_doc = document
							else: ui_root.set_meta("_cached_" + doc_name + "_doc", document)
	
	var loading_overlay = null
	if document == null or doc_name == "ruleta":
		loading_overlay = _show_processing_overlay(tr("load_worls"))
		if document != null and doc_name == "ruleta":
			await get_tree().create_timer(0.4).timeout
	
	if document == null:
		var collection = Firebase.Firestore.collection("cache")
		var fb_doc = await collection.get_doc(doc_name)
		if fb_doc:
			document = fb_doc.document
			if doc_name == "top_semanal": _cached_top_semanal_doc = document
			else: ui_root.set_meta("_cached_" + doc_name + "_doc", document)
			
			var cf = FileAccess.open(cache_file, FileAccess.WRITE)
			if cf:
				cf.store_string(JSON.stringify({
					"fetch_time": int(Time.get_unix_time_from_system()),
					"document": document
				}))
				cf.close()
	
	if is_instance_valid(loading_overlay):
		loading_overlay.queue_free()
		
	if not is_instance_valid(p_card_grid): return
	
	if document == null:
		if ui_root.get_meta("has_internet", true) == true:
			ui_root.set_meta("has_internet", false)
			setup_workshop_ui()
			return
			
	var dict_doc = null
	if typeof(document) == TYPE_OBJECT and document is FirestoreDocument:
		dict_doc = document.document
	elif typeof(document) == TYPE_DICTIONARY:
		dict_doc = document
		
	if dict_doc and dict_doc.has("worlds"):
		var raw_worlds = dict_doc["worlds"]
		var worlds_list = []
		
		if typeof(raw_worlds) == TYPE_ARRAY:
			worlds_list = raw_worlds
		elif typeof(raw_worlds) == TYPE_DICTIONARY:
			if raw_worlds.has("arrayValue"):
				if raw_worlds["arrayValue"].has("values"):
					worlds_list = raw_worlds["arrayValue"]["values"]
			else:
				worlds_list = raw_worlds.values()
				
		var page_worlds = []
		
		if doc_name == "ruleta":
			var r_file = "user://ruleta_state.json"
			var r_state = ui_root.get_meta("ruleta_state", {})
			var needs_save = false
			
			if r_state.is_empty() and FileAccess.file_exists(r_file):
				var sf = FileAccess.open(r_file, FileAccess.READ)
				if sf:
					var text = sf.get_as_text()
					sf.close()
					if text != "":
						var parsed = JSON.parse_string(text)
						if typeof(parsed) == TYPE_DICTIONARY: r_state = parsed
						
			var last_update = get_last_update_unix(false)
			var force_shuffle = false
			
			if not r_state.has("cache_time") or r_state["cache_time"] < last_update:
				force_shuffle = true
			elif not r_state.has("shuffled_list") or typeof(r_state["shuffled_list"]) != TYPE_ARRAY:
				force_shuffle = true
				
			if force_shuffle:
				var rng = RandomNumberGenerator.new()
				rng.randomize()
				var n = worlds_list.size()
				for i in range(n - 1, 0, -1):
					var j = rng.randi() % (i + 1)
					var temp = worlds_list[i]
					worlds_list[i] = worlds_list[j]
					worlds_list[j] = temp
				
				r_state = {
					"cache_time": int(Time.get_unix_time_from_system()),
					"shuffled_list": worlds_list.duplicate(),
					"pointer": 0
				}
				needs_save = true
				
			worlds_list = r_state["shuffled_list"]
			var p = int(r_state.get("pointer", 0))
			var items_per_page = 4
			
			if page > 1:
				p += items_per_page
				if p >= worlds_list.size() and worlds_list.size() > 0:
					var rng = RandomNumberGenerator.new()
					rng.randomize()
					var n = worlds_list.size()
					for i in range(n - 1, 0, -1):
						var j = rng.randi() % (i + 1)
						var temp = worlds_list[i]
						worlds_list[i] = worlds_list[j]
						worlds_list[j] = temp
					r_state["shuffled_list"] = worlds_list.duplicate()
					p = 0
				needs_save = true
				
			page_worlds = worlds_list.slice(p, p + items_per_page)
			r_state["pointer"] = p
			ui_root.set_meta("ruleta_state", r_state)
			
			if needs_save:
				var sf = FileAccess.open(r_file, FileAccess.WRITE)
				if sf:
					sf.store_string(JSON.stringify(r_state))
					sf.close()
					
			if is_instance_valid(pagination_hbox):
				var s = _get_ui_scale()
				for c in pagination_hbox.get_children(): c.queue_free()
				var btn_tirar = Button.new()
				btn_tirar.text = "🎲 " + tr("btn_tirar_dados")
				btn_tirar.add_theme_font_override("font", _get_safe_font())
				btn_tirar.add_theme_font_size_override("font_size", int(20 * s))
				btn_tirar.custom_minimum_size = Vector2(0, 50 * s)
				btn_tirar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var b_style = StyleBoxFlat.new()
				b_style.bg_color = Color(0.15, 0.45, 0.85, 1.0)
				b_style.corner_radius_top_left = int(10 * s); b_style.corner_radius_top_right = int(10 * s)
				b_style.corner_radius_bottom_left = int(10 * s); b_style.corner_radius_bottom_right = int(10 * s)
				btn_tirar.add_theme_stylebox_override("normal", b_style)
				btn_tirar.add_theme_stylebox_override("hover", b_style)
				btn_tirar.add_theme_stylebox_override("pressed", b_style)
				btn_tirar.pressed.connect(func():
					if btn_tirar.has_meta("loading"): return
					
					var spins = ui_root.get_meta("ruleta_spins", 0)
					if spins >= 4:
						var on_cancel = func(): pass
						var on_confirm = func():
							AdMobManager.show_workshop_rewarded()
							var success = await AdMobManager.workshop_rewarded_completed
							if success:
								ui_root.set_meta("ruleta_spins", 0)
								if is_instance_valid(btn_tirar): btn_tirar.set_meta("loading", true)
								_play_action_sound("ui_click")
								var cur_t = ui_root.get_meta("workshop_current_tab", 0)
								ui_root.set_meta("workshop_page_" + str(cur_t), page + 1)
								call_deferred("_setup_main_ui_containers")
							else:
								_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_ad_failed"))
						
						show_download_ad_popup(on_confirm, on_cancel, "watch_ad_ruleta_desc")
						return
						
					ui_root.set_meta("ruleta_spins", spins + 1)
					btn_tirar.set_meta("loading", true)
					_play_action_sound("ui_click")
					var c_tab = ui_root.get_meta("workshop_current_tab", 0)
					ui_root.set_meta("workshop_page_" + str(c_tab), page + 1)
					call_deferred("_setup_main_ui_containers")
				)
				pagination_hbox.add_child(btn_tirar)
		else:
			if is_instance_valid(pagination_hbox):
				build_pagination(pagination_hbox, worlds_list.size())
			var items_per_page = 10
			var start_idx = (page - 1) * items_per_page
			if start_idx < worlds_list.size():
				page_worlds = worlds_list.slice(start_idx, start_idx + items_per_page)
				
		var idx = 0
		for w_data in page_worlds:
			var clean_data = w_data
			if typeof(w_data) == TYPE_DICTIONARY and w_data.has("mapValue"):
				clean_data = {}
				var fields = w_data["mapValue"]["fields"]
				for key in fields.keys():
					var val = fields[key]
					if val.has("stringValue"): clean_data[key] = val["stringValue"]
					elif val.has("integerValue"): clean_data[key] = int(val["integerValue"])
					elif val.has("doubleValue"): clean_data[key] = float(val["doubleValue"])
			
			var card = preload("res://scenes/main/world_card.tscn").instantiate()
			p_card_grid.add_child(card)
			card.setup(clean_data, 0)
			card.download_requested.connect(on_world_download_requested)
			idx += 1
			
		if idx == 0:
			show_empty_state_message(p_card_grid)


func fetch_recientes_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1) -> void:
	if not is_instance_valid(p_card_grid): return
	
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var current_time = int(Time.get_unix_time_from_system())
	var mem_time = ui_root.get_meta("workshop_recientes_cache_time", 0.0)
	var document = _cached_recientes_doc
	
	if document != null and (mem_time == 0.0 or (current_time - mem_time) >= 1800):
		document = null
		_cached_recientes_doc = null
	
	if document == null:
		if FileAccess.file_exists("user://recientes_cache.json"):
			var cf = FileAccess.open("user://recientes_cache.json", FileAccess.READ)
			if cf:
				var text = cf.get_as_text()
				cf.close()
				if text != "":
					var parsed = JSON.parse_string(text)
					if typeof(parsed) == TYPE_DICTIONARY and parsed.has("fetch_time"):
						var fetch_time = parsed["fetch_time"]
						if mem_time != 0.0 and (current_time - fetch_time) < 1800:
							document = parsed["document"]
							_cached_recientes_doc = document
							ui_root.set_meta("workshop_recientes_cache_time", fetch_time)
	
	var loading_overlay = null
	if document == null:
		loading_overlay = _show_processing_overlay(tr("load_worls"))
	
	if document == null:
		var collection = Firebase.Firestore.collection("cache")
		var fb_doc = await collection.get_doc("recientes")
		if fb_doc:
			document = fb_doc.document
			_cached_recientes_doc = document
			var new_time = int(Time.get_unix_time_from_system())
			ui_root.set_meta("workshop_recientes_cache_time", new_time)
			
			var cf = FileAccess.open("user://recientes_cache.json", FileAccess.WRITE)
			if cf:
				cf.store_string(JSON.stringify({
					"fetch_time": new_time,
					"document": document
				}))
				cf.close()
	
	if is_instance_valid(loading_overlay):
		loading_overlay.queue_free()
		
	if not is_instance_valid(p_card_grid): return
	
	if document == null:
		if ui_root.get_meta("has_internet", true) == true:
			ui_root.set_meta("has_internet", false)
			setup_workshop_ui()
			return
			
	var dict_doc = null
	if typeof(document) == TYPE_OBJECT and document is FirestoreDocument:
		dict_doc = document.document
	elif typeof(document) == TYPE_DICTIONARY:
		dict_doc = document
		
	if dict_doc and dict_doc.has("worlds"):
		var raw_worlds = dict_doc["worlds"]
		var worlds_list = []
		
		if typeof(raw_worlds) == TYPE_ARRAY:
			worlds_list = raw_worlds
		elif typeof(raw_worlds) == TYPE_DICTIONARY:
			if raw_worlds.has("arrayValue"):
				if raw_worlds["arrayValue"].has("values"):
					worlds_list = raw_worlds["arrayValue"]["values"]
			else:
				worlds_list = raw_worlds.values()
				
		if is_instance_valid(pagination_hbox):
			build_pagination(pagination_hbox, worlds_list.size())
				
		var start_idx = (page - 1) * 10
		var page_worlds = []
		if start_idx < worlds_list.size():
			page_worlds = worlds_list.slice(start_idx, start_idx + 10)
				
		var idx = 0
		for w_data in page_worlds:
			var clean_data = w_data
			if typeof(w_data) == TYPE_DICTIONARY and w_data.has("mapValue"):
				clean_data = {}
				var fields = w_data["mapValue"]["fields"]
				for key in fields.keys():
					var val = fields[key]
					if val.has("stringValue"): clean_data[key] = val["stringValue"]
					elif val.has("integerValue"): clean_data[key] = int(val["integerValue"])
					elif val.has("doubleValue"): clean_data[key] = float(val["doubleValue"])
			
			var card = preload("res://scenes/main/world_card.tscn").instantiate()
			p_card_grid.add_child(card)
			card.setup(clean_data, 0)
			card.download_requested.connect(on_world_download_requested)
			card.like_requested.connect(on_world_like_requested)
			card.report_requested.connect(on_world_report_requested)
			idx += 1
			
		if idx == 0:
			show_empty_state_message(p_card_grid)


func fetch_mis_mundos_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1, force_fetch: bool = false) -> void:
	if not is_instance_valid(p_card_grid): return
	
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var wm = get_node_or_null("/root/WorkshopManager")
	if not wm or wm.google_play_id == "":
		show_empty_state_message(p_card_grid)
		return
		
	load_workshop_cache()
	var current_time = Time.get_unix_time_from_system()
	var cache_time = ui_root.get_meta("workshop_mis_mundos_cache_time", 0.0)
	var cache_data = ui_root.get_meta("workshop_mis_mundos_cache", [])
	
	var document_array = []
	var need_fetch = true
	
	if not force_fetch and cache_time > 0 and (current_time - cache_time) < (30 * 60):
		need_fetch = false
		document_array = cache_data
		
	if need_fetch:
		var author_id = wm.google_play_id
		var query = FirestoreQuery.new()
		query.from("community_worlds")
		query.where("author_id", FirestoreQuery.OPERATOR.EQUAL, author_id)
		
		var raw_array = await Firebase.Firestore.query(query)
		
		if not is_instance_valid(p_card_grid): return
		
		if typeof(raw_array) == TYPE_ARRAY:
			document_array = []
			for doc in raw_array:
				var clean_data = {}
				if doc and "document" in doc:
					for key in doc.document.keys():
						var val = doc.document[key]
						if typeof(val) == TYPE_DICTIONARY:
							if val.has("stringValue"): clean_data[key] = val["stringValue"]
							elif val.has("integerValue"): clean_data[key] = int(val["integerValue"])
							elif val.has("doubleValue"): clean_data[key] = float(val["doubleValue"])
							elif val.has("booleanValue"): clean_data[key] = bool(val["booleanValue"])
						else:
							clean_data[key] = val
					clean_data["id"] = doc.doc_name
					document_array.append(clean_data)
			
			ui_root.set_meta("workshop_mis_mundos_cache", document_array)
			ui_root.set_meta("workshop_mis_mundos_cache_time", current_time)
			ui_root.set_meta("workshop_total_uploaded_worlds", document_array.size())
			save_workshop_cache()
		else:
			document_array = []
			ui_root.set_meta("workshop_mis_mundos_cache", [])
			ui_root.set_meta("workshop_mis_mundos_cache_time", current_time)
			ui_root.set_meta("workshop_total_uploaded_worlds", 0)
			save_workshop_cache()
	
	var preloaded_cards = p_card_grid.get_children()
	
	if typeof(document_array) == TYPE_ARRAY and document_array.size() > 0:
		if is_instance_valid(pagination_hbox):
			build_pagination(pagination_hbox, document_array.size())
			
		var start_idx = (page - 1) * 10
		var page_worlds = []
		if start_idx < document_array.size():
			page_worlds = document_array.slice(start_idx, start_idx + 10)
			
		var idx = 0
		for clean_data in page_worlds:
			if idx < preloaded_cards.size():
				preloaded_cards[idx].setup(clean_data, 3)
				if not preloaded_cards[idx].download_requested.is_connected(on_world_download_requested):
					preloaded_cards[idx].download_requested.connect(on_world_download_requested)
				if not preloaded_cards[idx].like_requested.is_connected(on_world_like_requested):
					preloaded_cards[idx].like_requested.connect(on_world_like_requested)
				if not preloaded_cards[idx].edit_requested.is_connected(on_world_edit_requested):
					preloaded_cards[idx].edit_requested.connect(on_world_edit_requested)
				if not preloaded_cards[idx].report_requested.is_connected(on_world_report_requested):
					preloaded_cards[idx].report_requested.connect(on_world_report_requested)
			else:
				var card = preload("res://scenes/main/world_card.tscn").instantiate()
				p_card_grid.add_child(card)
				card.setup(clean_data, 3)
				card.download_requested.connect(on_world_download_requested)
				card.like_requested.connect(on_world_like_requested)
				card.edit_requested.connect(on_world_edit_requested)
				card.report_requested.connect(on_world_report_requested)
			idx += 1
			
		for i in range(idx, preloaded_cards.size()):
			preloaded_cards[i].queue_free()
			
		if idx == 0:
			show_empty_state_message(p_card_grid)
	else:
		for card in preloaded_cards:
			card.queue_free()
		show_empty_state_message(p_card_grid)


func update_local_recientes_cache(world_id: String, delete: bool, new_data: Dictionary = {}) -> void:
	var document = _cached_recientes_doc
	var ui_root = _get_ui_root()
	
	if document == null:
		if FileAccess.file_exists("user://recientes_cache.json"):
			var cf = FileAccess.open("user://recientes_cache.json", FileAccess.READ)
			if cf:
				var text = cf.get_as_text()
				cf.close()
				if text != "":
					var parsed = JSON.parse_string(text)
					if typeof(parsed) == TYPE_DICTIONARY and parsed.has("document"):
						document = parsed["document"]
						
	var dict_doc = null
	if typeof(document) == TYPE_OBJECT and document is FirestoreDocument:
		dict_doc = document.document
	elif typeof(document) == TYPE_DICTIONARY:
		dict_doc = document
		
	if dict_doc and dict_doc.has("worlds"):
		var raw_worlds = dict_doc["worlds"]
		var worlds_list = []
		if typeof(raw_worlds) == TYPE_ARRAY:
			worlds_list = raw_worlds
		elif typeof(raw_worlds) == TYPE_DICTIONARY and raw_worlds.has("arrayValue") and raw_worlds["arrayValue"].has("values"):
			worlds_list = raw_worlds["arrayValue"]["values"]
			
		var modified = false
		for i in range(worlds_list.size() - 1, -1, -1):
			var w_data = worlds_list[i]
			var check_id = ""
			
			if typeof(w_data) == TYPE_DICTIONARY and w_data.has("mapValue"):
				var fields = w_data["mapValue"]["fields"]
				if fields.has("id") and fields["id"].has("stringValue"):
					check_id = fields["id"]["stringValue"]
			elif typeof(w_data) == TYPE_DICTIONARY and w_data.has("id"):
				check_id = w_data["id"]
				
			if check_id == world_id:
				if delete:
					worlds_list.remove_at(i)
					modified = true
				else:
					if typeof(w_data) == TYPE_DICTIONARY and w_data.has("mapValue"):
						var fields = w_data["mapValue"]["fields"]
						if new_data.has("title"):
							if not fields.has("title"): fields["title"] = {}
							fields["title"]["stringValue"] = new_data["title"]
						if new_data.has("category"):
							if not fields.has("category"): fields["category"] = {}
							fields["category"]["integerValue"] = str(new_data["category"])
						modified = true
					elif typeof(w_data) == TYPE_DICTIONARY:
						if new_data.has("title"): w_data["title"] = new_data["title"]
						if new_data.has("category"): w_data["category"] = new_data["category"]
						modified = true
				break
				
		if modified:
			_cached_recientes_doc = dict_doc
			var mem_time = ui_root.get_meta("workshop_recientes_cache_time", int(Time.get_unix_time_from_system())) if ui_root else int(Time.get_unix_time_from_system())
			var cf = FileAccess.open("user://recientes_cache.json", FileAccess.WRITE)
			if cf:
				cf.store_string(JSON.stringify({
					"fetch_time": mem_time,
					"document": dict_doc
				}))
				cf.close()


func fetch_mis_descargas_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1) -> void:
	if not is_instance_valid(p_card_grid): return
	var downloads = []
	if FileAccess.file_exists("user://downloads.json"):
		var f = FileAccess.open("user://downloads.json", FileAccess.READ)
		var dict = JSON.parse_string(f.get_as_text())
		if typeof(dict) == TYPE_ARRAY: downloads = dict
		
	if is_instance_valid(top_downloads_count_label):
		top_downloads_count_label.text = tr("downloaded_maps_count").format([str(downloads.size())])
		
	build_pagination(pagination_hbox, downloads.size())
	
	for i in range(p_card_grid.get_child_count()):
		p_card_grid.get_child(i).queue_free()
		
	var start_idx = (page - 1) * 10
	var end_idx = start_idx + 10
	if start_idx < 0: start_idx = 0
	
	var displayed = 0
	for i in range(start_idx, min(end_idx, downloads.size())):
		var w_data = downloads[i]
		
		# Reparación de datos corruptos
		var needs_save = false
		for k in w_data.keys():
			if typeof(w_data[k]) == TYPE_DICTIONARY:
				if w_data[k].has("stringValue"): w_data[k] = w_data[k]["stringValue"]; needs_save = true
				elif w_data[k].has("integerValue"): w_data[k] = int(w_data[k]["integerValue"]); needs_save = true
				elif w_data[k].has("doubleValue"): w_data[k] = float(w_data[k]["doubleValue"]); needs_save = true
				elif w_data[k].has("booleanValue"): w_data[k] = w_data[k]["booleanValue"]; needs_save = true
		if needs_save:
			var fw = FileAccess.open("user://downloads.json", FileAccess.WRITE)
			if fw: fw.store_string(JSON.stringify(downloads))
			
		var card = preload("res://scenes/main/world_card.tscn").instantiate()
		p_card_grid.add_child(card)
		
		var current_time = int(Time.get_unix_time_from_system())
		var last_sync = w_data.get("last_sync_time", 0)
		if current_time - last_sync > 604800: # 7 dias
			trigger_lazy_sync(w_data, card)
			
		card.setup(w_data, 2)
		if liked_worlds.has(str(w_data.get("id", w_data.get("world_id", "")))):
			card.set_liked_state(true)
			
		card.play_requested.connect(on_world_play_requested)
		card.delete_requested.connect(on_world_delete_downloaded)
		card.like_requested.connect(on_world_like_requested)
		card.unlike_requested.connect(on_world_unlike_requested)
		card.report_requested.connect(on_world_report_requested)
		displayed += 1
		
	if displayed == 0:
		show_empty_state_message(p_card_grid)


func trigger_lazy_sync(w_data: Dictionary, card: Control) -> void:
	var world_id = str(w_data.get("id", w_data.get("world_id", "")))
	if world_id == "": return
	
	var doc = await Firebase.Firestore.collection("community_worlds").get_doc(world_id)
	if doc and doc.document:
		var raw = doc.document
		
		var l_val = raw.get("likes", {})
		if typeof(l_val) == TYPE_DICTIONARY and l_val.has("integerValue"): w_data["likes"] = int(l_val["integerValue"])
		
		var d_val = raw.get("downloads", {})
		if typeof(d_val) == TYPE_DICTIONARY and d_val.has("integerValue"): w_data["downloads"] = int(d_val["integerValue"])
		
		w_data["last_sync_time"] = int(Time.get_unix_time_from_system())
		
		if is_instance_valid(card) and card.has_method("setup"):
			card.world_data["likes"] = w_data.get("likes", 0)
			card.world_data["downloads"] = w_data.get("downloads", 0)
			if is_instance_valid(card.get("likes_label")):
				card.likes_label.text = "👍 " + str(w_data.get("likes", 0))
			if is_instance_valid(card.get("downloads_label")):
				card.downloads_label.text = "⬇️ " + str(w_data.get("downloads", 0))
				
		if FileAccess.file_exists("user://downloads.json"):
			var f = FileAccess.open("user://downloads.json", FileAccess.READ)
			var text = f.get_as_text()
			f.close()
			if text != "":
				var downloads = JSON.parse_string(text)
				if typeof(downloads) == TYPE_ARRAY:
					var modified = false
					for i in range(downloads.size()):
						var w = downloads[i]
						if typeof(w) == TYPE_DICTIONARY and str(w.get("id", w.get("world_id", ""))) == world_id:
							downloads[i] = w_data
							modified = true
							break
					if modified:
						var fw = FileAccess.open("user://downloads.json", FileAccess.WRITE)
						if fw: fw.store_string(JSON.stringify(downloads))


# Aliases
func _fetch_top_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1) -> void: fetch_top_async(p_card_grid, pagination_hbox, page)
func _fetch_recientes_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1) -> void: fetch_recientes_async(p_card_grid, pagination_hbox, page)
func _fetch_mis_mundos_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1, force_fetch: bool = false) -> void: fetch_mis_mundos_async(p_card_grid, pagination_hbox, page, force_fetch)
func _update_local_recientes_cache(world_id: String, delete: bool, new_data: Dictionary = {}) -> void: update_local_recientes_cache(world_id, delete, new_data)
func _fetch_mis_descargas_async(p_card_grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1) -> void: fetch_mis_descargas_async(p_card_grid, pagination_hbox, page)
func _trigger_lazy_sync(w_data: Dictionary, card: Control) -> void: trigger_lazy_sync(w_data, card)


# =========================================================================
# SISTEMA DE CÓDIGO Y BÚSQUEDA
# =========================================================================

func get_char_value(c: String) -> int:
	var ascii = c.unicode_at(0)
	if ascii >= 48 and ascii <= 57: return ascii - 48
	if ascii >= 97 and ascii <= 122: return ascii - 97 + 10
	return 0


func get_value_char(val: int) -> String:
	if val >= 0 and val <= 9: return String.chr(val + 48)
	if val >= 10 and val <= 35: return String.chr(val - 10 + 97)
	return "0"


func verify_map_code(base_code: String, check_char: String) -> bool:
	if base_code.length() != 8 or check_char.length() != 1: return false
	var sum = 0
	for i in range(8): sum += get_char_value(base_code[i]) * (i + 1)
	return get_value_char(sum % 36) == check_char


func on_search_world_requested(base_code: String, check_char: String) -> void:
	if base_code.strip_edges() == "" or check_char.strip_edges() == "":
		_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_enter_full_code"))
		return
		
	if not verify_map_code(base_code, check_char):
		_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_invalid_map_code"))
		return
		
	var full_code = base_code + "-" + check_char
	var loading_overlay = _show_processing_overlay(tr("msg_searching_map"))
	
	var doc = await Firebase.Firestore.collection("community_worlds").get_doc(full_code)
	if is_instance_valid(loading_overlay): loading_overlay.queue_free()
	
	if not doc or (typeof(doc) == TYPE_OBJECT and not "document" in doc) or (typeof(doc) == TYPE_DICTIONARY and doc.has("error")):
		_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_map_not_found") + " " + full_code)
		return
		
	var dict_doc = doc.document
	var clean_data = {}
	for key in dict_doc.keys():
		var val = dict_doc[key]
		if typeof(val) == TYPE_DICTIONARY:
			if val.has("stringValue"): clean_data[key] = val["stringValue"]
			elif val.has("integerValue"): clean_data[key] = int(val["integerValue"])
			elif val.has("doubleValue"): clean_data[key] = float(val["doubleValue"])
			else: clean_data[key] = val
		else:
			clean_data[key] = val
			
	var ui_root = _get_ui_root()
	if ui_root:
		ui_root.set_meta("workshop_search_result", clean_data)
		ui_root.set_meta("workshop_current_tab", 4)
	call_deferred("_setup_main_ui_containers")


# Aliases
func _get_char_value(c: String) -> int: return get_char_value(c)
func _get_value_char(val: int) -> String: return get_value_char(val)
func _verify_map_code(base_code: String, check_char: String) -> bool: return verify_map_code(base_code, check_char)
func _on_search_world_requested(base_code: String, check_char: String) -> void: on_search_world_requested(base_code, check_char)


# =========================================================================
# ACCIONES SOCIALES Y DESCARGAS
# =========================================================================

func on_world_like_requested(world_data: Dictionary) -> void:
	var world_id = str(world_data.get("id", ""))
	if world_id == "" or liked_worlds.has(world_id): return
		
	liked_worlds.append(world_id)
	save_workshop_economy()
	
	var action_data = {
		"world_id": world_id,
		"type": "like",
		"timestamp": int(Time.get_unix_time_from_system())
	}
	push_to_action_buffer(action_data)
	
	var new_likes = int(world_data.get("likes", 0)) + 1
	world_data["likes"] = new_likes
	
	var ui_root = _get_ui_root()
	if ui_root:
		var all_cards = ui_root.find_children("*", "PanelContainer", true, false)
		for card in all_cards:
			if card.has_method("setup") and card.get("world_data") != null:
				if str(card.world_data.get("id", card.world_data.get("world_id", ""))) == world_id:
					card.world_data["likes"] = new_likes
					if card.has_method("set_liked_state"):
						card.set_liked_state(true)
					if is_instance_valid(card.get("likes_label")):
						card.likes_label.text = "👍 " + str(new_likes)
	update_local_download_likes(world_id, new_likes)


func on_world_unlike_requested(world_data: Dictionary) -> void:
	var world_id = str(world_data.get("id", ""))
	if world_id == "" or not liked_worlds.has(world_id): return
		
	liked_worlds.erase(world_id)
	save_workshop_economy()
	
	var action_data = {
		"world_id": world_id,
		"type": "unlike",
		"timestamp": int(Time.get_unix_time_from_system())
	}
	push_to_action_buffer(action_data)
	
	var new_likes = max(0, int(world_data.get("likes", 0)) - 1)
	world_data["likes"] = new_likes
	
	var ui_root = _get_ui_root()
	if ui_root:
		var all_cards = ui_root.find_children("*", "PanelContainer", true, false)
		for card in all_cards:
			if card.has_method("setup") and card.get("world_data") != null:
				if str(card.world_data.get("id", card.world_data.get("world_id", ""))) == world_id:
					card.world_data["likes"] = new_likes
					if card.has_method("set_liked_state"):
						card.set_liked_state(false)
					if is_instance_valid(card.get("likes_label")):
						card.likes_label.text = "👍 " + str(new_likes)
	update_local_download_likes(world_id, new_likes)


func update_local_download_likes(world_id: String, new_likes: int) -> void:
	if FileAccess.file_exists("user://downloads.json"):
		var f = FileAccess.open("user://downloads.json", FileAccess.READ)
		var text = f.get_as_text()
		f.close()
		if text != "":
			var downloads = JSON.parse_string(text)
			if typeof(downloads) == TYPE_ARRAY:
				var modified = false
				for w in downloads:
					if typeof(w) == TYPE_DICTIONARY and str(w.get("id", w.get("world_id", ""))) == world_id:
						w["likes"] = new_likes
						modified = true
						break
				if modified:
					var fw = FileAccess.open("user://downloads.json", FileAccess.WRITE)
					if fw: fw.store_string(JSON.stringify(downloads))


func on_world_report_requested(world_data: Dictionary) -> void:
	var world_id = str(world_data.get("id", ""))
	if world_id == "": return
	
	if reported_worlds.has(world_id):
		_show_modal_message(tr("notice_title"), tr("already_reported_msg"))
		return
		
	_show_confirm_dialog(tr("confirm_report_world_title"), tr("confirm_report_world_msg"), func():
		reported_worlds.append(world_id)
		save_workshop_economy()
		
		var action_data = {
			"world_id": world_id,
			"type": "report",
			"timestamp": int(Time.get_unix_time_from_system())
		}
		push_to_action_buffer(action_data)
		_show_modal_message(tr("report_sent_title"), tr("report_sent_msg"))
	)


func on_world_play_requested(world_data: Dictionary) -> void:
	_close_all_popups()
	var path = "user://download_world_" + str(world_data.get("id", "")) + ".dat"
	var loading = _show_processing_overlay(tr("load_worls") if TranslationServer.get_locale() == "es" else "Loading...")
	await get_tree().create_timer(0.1).timeout
	_load_world_from_path(path)
	if is_instance_valid(loading): loading.queue_free()


func show_download_ad_popup(on_confirm: Callable, on_cancel: Callable, custom_text: String = "watch_ad_download_desc") -> void:
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.85)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	var center = CenterContainer.new()
	overlay.add_child(center)
	
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(400 * s, 250 * s)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.16, 1.0)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color("#fbc531")
	p_style.corner_radius_top_left = int(15 * s); p_style.corner_radius_top_right = int(15 * s)
	p_style.corner_radius_bottom_left = int(15 * s); p_style.corner_radius_bottom_right = int(15 * s)
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(25 * s))
	margin.add_theme_constant_override("margin_right", int(25 * s))
	margin.add_theme_constant_override("margin_top", int(25 * s))
	margin.add_theme_constant_override("margin_bottom", int(25 * s))
	popup.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(20 * s))
	margin.add_child(vbox)
	
	var label = Label.new()
	label.text = tr(custom_text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", _get_safe_font())
	label.add_theme_font_size_override("font_size", int(22 * s))
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(label)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", int(20 * s))
	vbox.add_child(hbox)
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("btn_cancel")
	btn_cancel.custom_minimum_size = Vector2(120 * s, 50 * s)
	btn_cancel.add_theme_font_override("font", _get_safe_font())
	btn_cancel.add_theme_font_size_override("font_size", int(18 * s))
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.3, 0.3, 0.35)
	cancel_style.corner_radius_top_left = int(8 * s); cancel_style.corner_radius_top_right = int(8 * s)
	cancel_style.corner_radius_bottom_left = int(8 * s); cancel_style.corner_radius_bottom_right = int(8 * s)
	btn_cancel.add_theme_stylebox_override("normal", cancel_style)
	btn_cancel.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
		on_cancel.call()
	)
	hbox.add_child(btn_cancel)
	
	var btn_ad = Button.new()
	btn_ad.text = tr("watch_ad_download")
	btn_ad.custom_minimum_size = Vector2(200 * s, 50 * s)
	btn_ad.add_theme_font_override("font", _get_safe_font())
	btn_ad.add_theme_font_size_override("font_size", int(18 * s))
	btn_ad.add_theme_color_override("font_color", Color.BLACK)
	var ad_style = StyleBoxFlat.new()
	ad_style.bg_color = Color("#fbc531")
	ad_style.corner_radius_top_left = int(8 * s); ad_style.corner_radius_top_right = int(8 * s)
	ad_style.corner_radius_bottom_left = int(8 * s); ad_style.corner_radius_bottom_right = int(8 * s)
	btn_ad.add_theme_stylebox_override("normal", ad_style)
	var h_ad = ad_style.duplicate()
	h_ad.bg_color = Color("#f5f6fa")
	btn_ad.add_theme_stylebox_override("hover", h_ad)
	btn_ad.add_theme_stylebox_override("pressed", h_ad)
	btn_ad.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
		on_confirm.call()
	)
	hbox.add_child(btn_ad)


func on_world_download_requested(world_data: Dictionary) -> void:
	var world_id = str(world_data.get("id", ""))
	var is_already_downloaded = false
	var download_history = []
	if FileAccess.file_exists("user://download_history.json"):
		var dh_file = FileAccess.open("user://download_history.json", FileAccess.READ)
		if dh_file:
			var txt = dh_file.get_as_text()
			dh_file.close()
			if txt != "":
				var parsed = JSON.parse_string(txt)
				if typeof(parsed) == TYPE_ARRAY:
					download_history = parsed
					if world_id in download_history:
						is_already_downloaded = true
	
	var proceed_download = func():
		var loading_overlay = _show_processing_overlay(tr("card_play_download"))
		
		var doc = await Firebase.Firestore.collection("community_worlds").get_doc(world_id)
		if not doc or not doc.document.has("sbu_url"):
			if is_instance_valid(loading_overlay): loading_overlay.queue_free()
			_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_download_file_not_found"))
			return
			
		var sbu_url = ""
		var sbu_field = doc.document["sbu_url"]
		if typeof(sbu_field) == TYPE_DICTIONARY and sbu_field.has("stringValue"):
			sbu_url = sbu_field["stringValue"]
		else:
			sbu_url = str(sbu_field)
			
		var http_request = HTTPRequest.new()
		add_child(http_request)
		
		var err = http_request.request(sbu_url)
		if err != OK:
			if is_instance_valid(loading_overlay): loading_overlay.queue_free()
			_show_modal_message("Error", "Error al solicitar descarga.")
			http_request.queue_free()
			return
			
		var result_arr = await http_request.request_completed
		var result = result_arr[0]
		var response_code = result_arr[1]
		var body = result_arr[3]
		
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var save_path = "user://download_world_" + world_id + ".dat"
			var f = FileAccess.open(save_path, FileAccess.WRITE)
			if f:
				f.store_buffer(body)
				f.close()
				
				var downloads = []
				if FileAccess.file_exists("user://downloads.json"):
					var df = FileAccess.open("user://downloads.json", FileAccess.READ)
					var text = df.get_as_text()
					if text != "":
						var dt = JSON.parse_string(text)
						if typeof(dt) == TYPE_ARRAY: downloads = dt
					
				var new_downloads = []
				for item in downloads:
					if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) != world_id:
						new_downloads.append(item)
						
				var final_world_data = world_data.duplicate()
				final_world_data["last_sync_time"] = int(Time.get_unix_time_from_system())
				new_downloads.insert(0, final_world_data)
				
				var df_write = FileAccess.open("user://downloads.json", FileAccess.WRITE)
				if df_write: df_write.store_string(JSON.stringify(new_downloads))
				
				if is_instance_valid(loading_overlay): loading_overlay.queue_free()
				_show_modal_message(tr("tab_mis_descargas"), tr("msg_download_success").format([world_data.get("title", "Mundo")]))
				var ui_r = _get_ui_root()
				if ui_r:
					ui_r.set_meta("workshop_current_tab", 3)
					ui_r.set_meta("workshop_page_3", 1)
				call_deferred("_setup_main_ui_containers")
				
				if not is_already_downloaded:
					download_history.append(world_id)
					var dh_write = FileAccess.open("user://download_history.json", FileAccess.WRITE)
					if dh_write: dh_write.store_string(JSON.stringify(download_history))
					
					var action_data = {
						"world_id": world_id,
						"type": "download",
						"timestamp": int(Time.get_unix_time_from_system())
					}
					push_to_action_buffer(action_data)
			else:
				if is_instance_valid(loading_overlay): loading_overlay.queue_free()
				_show_modal_message("Error", "No se pudo guardar el archivo localmente.")
		else:
			if is_instance_valid(loading_overlay): loading_overlay.queue_free()
			_show_modal_message("Error", "Error al descargar el mundo. HTTP " + str(response_code))
		
		http_request.queue_free()
	
	var start_download_process = func():
		if is_already_downloaded:
			AnalyticsManager.log_event("workshop_download", {"type": "redownload"})
			proceed_download.call()
		elif free_downloads_remaining > 0:
			AnalyticsManager.log_event("workshop_download", {"type": "free"})
			free_downloads_remaining -= 1
			save_workshop_economy()
			proceed_download.call()
		else:
			var on_cancel = func():
				print("Descarga cancelada (Anuncio rechazado)")
				
			var on_confirm = func():
				AdMobManager.show_workshop_rewarded()
				var success = await AdMobManager.workshop_rewarded_completed
				if success:
					AnalyticsManager.log_event("workshop_download", {"type": "ad"})
					free_downloads_remaining = 3
					save_workshop_economy()
					proceed_download.call()
				else:
					_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_ad_failed"))
					
			show_download_ad_popup(on_confirm, on_cancel)

	var save_path_check = "user://download_world_" + world_id + ".dat"
	if FileAccess.file_exists(save_path_check):
		_show_confirm_dialog(tr("confirm_update_title"), tr("confirm_update_msg"), func():
			start_download_process.call()
		)
	else:
		start_download_process.call()


func on_world_delete_downloaded(world_data: Dictionary) -> void:
	_show_confirm_dialog(tr("confirm_delete_download_title"), tr("confirm_delete_download_msg"), func():
		var world_id = str(world_data.get("id", ""))
		var downloads = []
		if FileAccess.file_exists("user://downloads.json"):
			var f = FileAccess.open("user://downloads.json", FileAccess.READ)
			var text = f.get_as_text()
			if text != "":
				var dict = JSON.parse_string(text)
				if typeof(dict) == TYPE_ARRAY: downloads = dict
				
		var new_downloads = []
		for item in downloads:
			if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) != world_id:
				new_downloads.append(item)
				
		var fw = FileAccess.open("user://downloads.json", FileAccess.WRITE)
		if fw: fw.store_string(JSON.stringify(new_downloads))
		
		var save_path = "user://download_world_" + world_id + ".dat"
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
			
		call_deferred("_setup_main_ui_containers")
	)


func push_to_action_buffer(action_data: Dictionary) -> void:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(func(_result, _response_code, _headers, _body):
		http_request.queue_free()
	)
	var url = "https://sandbox-ultra-5c7d5-default-rtdb.firebaseio.com/action_buffer.json"
	var body = JSON.stringify(action_data)
	var headers = ["Content-Type: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_POST, body)


# Aliases
func _on_world_like_requested(world_data: Dictionary) -> void: on_world_like_requested(world_data)
func _on_world_unlike_requested(world_data: Dictionary) -> void: on_world_unlike_requested(world_data)
func _update_local_download_likes(world_id: String, new_likes: int) -> void: update_local_download_likes(world_id, new_likes)
func _on_world_report_requested(world_data: Dictionary) -> void: on_world_report_requested(world_data)
func _on_world_play_requested(world_data: Dictionary) -> void: on_world_play_requested(world_data)
func _show_download_ad_popup(on_confirm: Callable, on_cancel: Callable, custom_text: String = "watch_ad_download_desc") -> void: show_download_ad_popup(on_confirm, on_cancel, custom_text)
func _on_world_download_requested(world_data: Dictionary) -> void: on_world_download_requested(world_data)
func _on_world_delete_downloaded(world_data: Dictionary) -> void: on_world_delete_downloaded(world_data)
func _push_to_action_buffer(action_data: Dictionary) -> void: push_to_action_buffer(action_data)


# =========================================================================
# SUBIDA, GESTIÓN Y EDICIÓN DE MAPAS
# =========================================================================

func show_upload_slot_selector(on_selected: Callable) -> void:
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.9)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	_set_mouse_over_ui(true)
	overlay.tree_exiting.connect(func(): _set_mouse_over_ui(false))
	
	var center = CenterContainer.new()
	overlay.add_child(center)
	
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	panel_style.border_width_left = 3; panel_style.border_width_top = 3
	panel_style.border_width_right = 3; panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.6, 0.5, 0.2)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	panel_style.corner_radius_bottom_left = 30; panel_style.corner_radius_bottom_right = 30
	panel.add_theme_stylebox_override("panel", panel_style)
	
	var is_landscape = _get_viewport_rect().size.x > _get_viewport_rect().size.y
	var base_height = 530 * s if is_landscape else 750 * s
	var m_height = min(base_height, _get_viewport_rect().size.y * 0.95)
	panel.custom_minimum_size = Vector2(530 * s, m_height)
	center.add_child(panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(20 * s))
	panel.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("upload_slot_label")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", int(36 * s))
	main_vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	var grid_hbox = HBoxContainer.new()
	grid_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	grid_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_hbox)

	var slot_grid = GridContainer.new()
	slot_grid.columns = 2
	slot_grid.add_theme_constant_override("h_separation", int(10 * s))
	slot_grid.add_theme_constant_override("v_separation", int(15 * s))
	grid_hbox.add_child(slot_grid)
	
	for i in range(1, 11):
		var slot_data = _get_slot_data(i)
		
		var slot_panel = PanelContainer.new()
		slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		slot_panel.custom_minimum_size = Vector2(235 * s, 0)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.18)
		style.set_corner_radius_all(int(10 * s))
		style.border_width_left = 2; style.border_width_top = 2
		style.border_width_right = 2; style.border_width_bottom = 2
		style.border_color = Color(0.3, 0.3, 0.3)
		slot_panel.add_theme_stylebox_override("panel", style)
		slot_grid.add_child(slot_panel)
		
		var vbox = VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_theme_constant_override("separation", int(5 * s))
		slot_panel.add_child(vbox)
		
		var header = HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(header)
		
		var lbl_idx = Label.new()
		lbl_idx.mouse_filter = Control.MOUSE_FILTER_PASS
		lbl_idx.text = "#" + str(i)
		lbl_idx.add_theme_font_size_override("font_size", int(26 * s))
		header.add_child(lbl_idx)
		
		var lbl_name = Label.new()
		lbl_name.mouse_filter = Control.MOUSE_FILTER_PASS
		lbl_name.text = slot_data.name if slot_data.has("name") else tr("empty")
		lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_name.clip_text = true
		lbl_name.add_theme_font_size_override("font_size", int(24 * s))
		header.add_child(lbl_name)
		
		var thumb_rect = TextureRect.new()
		thumb_rect.mouse_filter = Control.MOUSE_FILTER_PASS
		thumb_rect.custom_minimum_size = Vector2(215 * s, 150 * s) 
		thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if slot_data.has("thumbnail"):
			thumb_rect.texture = slot_data.thumbnail
		else:
			var empty_tex = GradientTexture2D.new()
			empty_tex.gradient = Gradient.new()
			empty_tex.gradient.set_color(0, Color(0.1, 0.1, 0.1))
			empty_tex.gradient.set_color(1, Color(0.1, 0.1, 0.1))
			thumb_rect.texture = empty_tex
		vbox.add_child(thumb_rect)
		
		var btn_select = Button.new()
		btn_select.text = tr("btn_select_slot")
		btn_select.custom_minimum_size = Vector2(0, 50 * s)
		btn_select.add_theme_font_override("font", _get_safe_font())
		btn_select.add_theme_font_size_override("font_size", int(20 * s))
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = Color("#00d2d3").lerp(Color.BLACK, 0.5)
		b_style.set_corner_radius_all(int(8 * s))
		btn_select.add_theme_stylebox_override("normal", b_style)
		var h_style = b_style.duplicate()
		h_style.bg_color = Color("#00d2d3").lerp(Color.BLACK, 0.3)
		btn_select.add_theme_stylebox_override("hover", h_style)
		btn_select.add_theme_stylebox_override("pressed", h_style)
		vbox.add_child(btn_select)
		
		var slot_id = i
		btn_select.pressed.connect(func():
			_play_action_sound("ui_click")
			overlay.queue_free()
			on_selected.call(slot_id)
		)
		
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10 * s)
	main_vbox.add_child(spacer)
		
	var btn_close = Button.new()
	btn_close.text = tr("btn_cancel")
	btn_close.custom_minimum_size = Vector2(200 * s, 50 * s)
	btn_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_close.add_theme_font_override("font", _get_safe_font())
	btn_close.add_theme_font_size_override("font_size", int(20 * s))
	main_vbox.add_child(btn_close)
	btn_close.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
	)


func show_world_manager_dialog() -> void:
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var cache_data = ui_root.get_meta("workshop_mis_mundos_cache", [])
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.8)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	_set_mouse_over_ui(true)
	overlay.tree_exiting.connect(func(): _set_mouse_over_ui(false))
	
	var center = CenterContainer.new()
	overlay.add_child(center)
	
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(450 * s, 600 * s)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.16, 1.0)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color("#ff9f43")
	p_style.corner_radius_top_left = int(20 * s); p_style.corner_radius_top_right = int(20 * s)
	p_style.corner_radius_bottom_left = int(20 * s); p_style.corner_radius_bottom_right = int(20 * s)
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(20 * s))
	margin.add_theme_constant_override("margin_bottom", int(20 * s))
	popup.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(15 * s))
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("world_manager_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", int(28 * s))
	title.add_theme_color_override("font_color", Color("#ff9f43"))
	main_vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400 * s)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", int(10 * s))
	scroll.add_child(list_vbox)
	
	if cache_data.size() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = tr("msg_no_worlds_uploaded")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_override("font", _get_safe_font())
		empty_lbl.add_theme_font_size_override("font_size", int(18 * s))
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		list_vbox.add_child(empty_lbl)
	else:
		for doc in cache_data:
			var row = HBoxContainer.new()
			var title_lbl = Label.new()
			title_lbl.text = str(doc.get("title", "Mundo"))
			title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_lbl.clip_text = true
			title_lbl.add_theme_font_override("font", _get_safe_font())
			title_lbl.add_theme_font_size_override("font_size", int(20 * s))
			row.add_child(title_lbl)
			
			var btn_mod = Button.new()
			btn_mod.text = "✏️"
			btn_mod.add_theme_font_override("font", _get_safe_font())
			btn_mod.add_theme_font_size_override("font_size", int(28 * s))
			btn_mod.custom_minimum_size = Vector2(50 * s, 50 * s)
			row.add_child(btn_mod)
			btn_mod.pressed.connect(func():
				_play_action_sound("ui_click")
				overlay.queue_free()
				show_edit_world_dialog(doc)
			)
			
			var btn_del = Button.new()
			btn_del.text = "🗑️"
			btn_del.add_theme_font_override("font", _get_safe_font())
			btn_del.add_theme_font_size_override("font_size", int(28 * s))
			btn_del.custom_minimum_size = Vector2(50 * s, 50 * s)
			row.add_child(btn_del)
			var doc_id = doc.get("id", "")
			var doc_title = doc.get("title", "")
			btn_del.pressed.connect(func():
				_play_action_sound("ui_click")
				_show_confirm_dialog(tr("confirm_delete_world_title"), tr("confirm_delete_world_msg"), func():
					overlay.queue_free()
					delete_world_from_workshop(doc_id, doc_title)
				)
			)
			
			list_vbox.add_child(row)
			
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer)
	
	var btn_close = Button.new()
	btn_close.text = tr("btn_close_word")
	btn_close.custom_minimum_size = Vector2(200 * s, 50 * s)
	btn_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_close.add_theme_font_override("font", _get_safe_font())
	btn_close.add_theme_font_size_override("font_size", int(20 * s))
	main_vbox.add_child(btn_close)
	btn_close.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
	)


func delete_world_from_workshop(world_id: String, world_title: String) -> void:
	var loading_overlay = _show_processing_overlay(tr("msg_deleting"))
	var ui_root = _get_ui_root()
	
	var firestore_col = Firebase.Firestore.collection("community_worlds")
	var doc = await firestore_col.get_doc(world_id)
	if typeof(doc) == TYPE_OBJECT:
		await firestore_col.delete(doc)
		
	var sbu_ref = Firebase.Storage.ref("worlds/" + world_id + ".sbu")
	await sbu_ref.delete()
	var thumb_ref = Firebase.Storage.ref("thumbnails/" + world_id + ".webp")
	await thumb_ref.delete()
	
	if is_instance_valid(loading_overlay):
		loading_overlay.queue_free()
		
	AnalyticsManager.log_event("workshop_delete_world", {})
	
	if ui_root:
		var cache = ui_root.get_meta("workshop_mis_mundos_cache", [])
		for i in range(cache.size() - 1, -1, -1):
			if cache[i].get("id", "") == world_id:
				cache.remove_at(i)
		ui_root.set_meta("workshop_mis_mundos_cache", cache)
		ui_root.set_meta("workshop_total_uploaded_worlds", cache.size())
	save_workshop_cache()
	
	update_local_recientes_cache(world_id, true)
	setup_workshop_ui()
	_show_centered_bubble("El mundo '" + world_title + "' ha sido eliminado.", Color("#ff7675"))


func load_workshop_cache() -> void:
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	if not ui_root.has_meta("workshop_mis_mundos_cache"):
		if FileAccess.file_exists("user://workshop_cache.dat"):
			var file = FileAccess.open("user://workshop_cache.dat", FileAccess.READ)
			if file:
				var data = file.get_var()
				if typeof(data) == TYPE_DICTIONARY and data.has("time") and data.has("data"):
					ui_root.set_meta("workshop_mis_mundos_cache_time", data.time)
					ui_root.set_meta("workshop_mis_mundos_cache", data.data)
					ui_root.set_meta("workshop_total_uploaded_worlds", data.data.size())
					return
		ui_root.set_meta("workshop_mis_mundos_cache_time", 0.0)
		ui_root.set_meta("workshop_mis_mundos_cache", [])


func save_workshop_cache() -> void:
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var file = FileAccess.open("user://workshop_cache.dat", FileAccess.WRITE)
	if file:
		var data = {
			"time": ui_root.get_meta("workshop_mis_mundos_cache_time", 0.0),
			"data": ui_root.get_meta("workshop_mis_mundos_cache", [])
		}
		file.store_var(data)


func on_world_edit_requested(world_data: Dictionary) -> void:
	show_edit_world_dialog(world_data)


func show_edit_world_dialog(world_data: Dictionary) -> void:
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var selected_overwrite_slot_id = [-1]
	var world_id = world_data.get("id", "")
	var old_title = world_data.get("title", "")
	var old_category = world_data.get("category", 0)
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.8)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	_set_mouse_over_ui(true)
	overlay.tree_exiting.connect(func(): _set_mouse_over_ui(false))
	
	var center = MarginContainer.new()
	overlay.add_child(center)
	
	var popup = PanelContainer.new()
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	popup.custom_minimum_size = Vector2(450 * s, 600 * s)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.16, 1.0)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color("#ff9f43")
	p_style.corner_radius_top_left = int(20 * s); p_style.corner_radius_top_right = int(20 * s)
	p_style.corner_radius_bottom_left = int(20 * s); p_style.corner_radius_bottom_right = int(20 * s)
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(20 * s))
	margin.add_theme_constant_override("margin_bottom", int(20 * s))
	popup.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(15 * s))
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("edit_world_dialog_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", int(28 * s))
	title.add_theme_color_override("font_color", Color("#ff9f43"))
	main_vbox.add_child(title)
	
	var thumb_bg = PanelContainer.new()
	thumb_bg.custom_minimum_size = Vector2(300 * s, 150 * s)
	thumb_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 1)
	bg_style.border_width_left = 2; bg_style.border_width_top = 2
	bg_style.border_width_right = 2; bg_style.border_width_bottom = 2
	bg_style.border_color = Color("#555555")
	thumb_bg.add_theme_stylebox_override("panel", bg_style)
	main_vbox.add_child(thumb_bg)
	
	var thumb_rect = TextureRect.new()
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb_bg.add_child(thumb_rect)
	
	if world_id != "":
		var cache_file = "user://thumb_cache_" + str(world_id) + ".bin"
		if FileAccess.file_exists(cache_file):
			var f = FileAccess.open(cache_file, FileAccess.READ)
			if f:
				var body = f.get_buffer(f.get_length())
				f.close()
				var cache_img = Image.new()
				if cache_img.load_webp_from_buffer(body) == OK or cache_img.load_png_from_buffer(body) == OK or cache_img.load_jpg_from_buffer(body) == OK:
					thumb_rect.texture = ImageTexture.create_from_image(cache_img)
	
	var create_label = func(text_key: String):
		var lbl = Label.new()
		lbl.text = tr(text_key)
		lbl.add_theme_font_override("font", _get_safe_font())
		lbl.add_theme_font_size_override("font_size", int(18 * s))
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		return lbl
		
	var lbl_file = create_label.call("map_file_label")
	lbl_file.text = tr("map_file_label")
	main_vbox.add_child(lbl_file)
	
	var slot_hbox = HBoxContainer.new()
	slot_hbox.add_theme_constant_override("separation", int(10 * s))
	main_vbox.add_child(slot_hbox)
	
	var btn_choose_slot = Button.new()
	btn_choose_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_choose_slot.text = tr("keep_online_file")
	btn_choose_slot.add_theme_font_override("font", _get_safe_font())
	btn_choose_slot.add_theme_font_size_override("font_size", int(20 * s))
	btn_choose_slot.custom_minimum_size = Vector2(0, 45 * s)
	
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.15, 0.15, 0.2)
	c_style.border_width_left = 2; c_style.border_width_top = 2
	c_style.border_width_right = 2; c_style.border_width_bottom = 2
	c_style.border_color = Color(0.4, 0.4, 0.5)
	c_style.set_corner_radius_all(int(10 * s))
	btn_choose_slot.add_theme_stylebox_override("normal", c_style)
	
	var hc_style = c_style.duplicate()
	hc_style.bg_color = Color(0.25, 0.25, 0.3)
	btn_choose_slot.add_theme_stylebox_override("hover", hc_style)
	btn_choose_slot.add_theme_stylebox_override("pressed", hc_style)
	slot_hbox.add_child(btn_choose_slot)
	
	var btn_clear_slot = Button.new()
	btn_clear_slot.text = "✖"
	btn_clear_slot.visible = false
	btn_clear_slot.custom_minimum_size = Vector2(45 * s, 45 * s)
	btn_clear_slot.add_theme_font_override("font", _get_safe_font())
	btn_clear_slot.add_theme_font_size_override("font_size", int(20 * s))
	var cls_style = c_style.duplicate()
	cls_style.bg_color = Color(0.8, 0.2, 0.2)
	btn_clear_slot.add_theme_stylebox_override("normal", cls_style)
	btn_clear_slot.add_theme_stylebox_override("hover", cls_style)
	slot_hbox.add_child(btn_clear_slot)
	
	var name_label_hbox = HBoxContainer.new()
	main_vbox.add_child(name_label_hbox)
	
	var name_lbl = create_label.call("upload_name_label")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label_hbox.add_child(name_lbl)
	
	var char_count_lbl = Label.new()
	char_count_lbl.add_theme_font_override("font", _get_safe_font())
	char_count_lbl.add_theme_font_size_override("font_size", int(16 * s))
	char_count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	char_count_lbl.text = str(old_title.length()) + "/30"
	name_label_hbox.add_child(char_count_lbl)
	
	var name_input = LineEdit.new()
	name_input.add_theme_font_override("font", _get_safe_font())
	name_input.add_theme_font_size_override("font_size", int(20 * s))
	name_input.custom_minimum_size = Vector2(0, 45 * s)
	name_input.max_length = 30
	name_input.text = old_title
	main_vbox.add_child(name_input)
	
	name_input.focus_entered.connect(func():
		var kb_height = DisplayServer.virtual_keyboard_get_height()
		if kb_height == 0: kb_height = 300 * s
		center.add_theme_constant_override("margin_bottom", int(kb_height))
	)
	name_input.focus_exited.connect(func():
		center.add_theme_constant_override("margin_bottom", 0)
	)
	
	name_input.text_changed.connect(func(new_text: String):
		char_count_lbl.text = str(new_text.length()) + "/30"
	)
	
	main_vbox.add_child(create_label.call("upload_category_label"))
	var cat_opt = OptionButton.new()
	cat_opt.add_theme_font_override("font", _get_safe_font())
	cat_opt.add_theme_font_size_override("font_size", int(20 * s))
	cat_opt.custom_minimum_size = Vector2(0, 40 * s)
	main_vbox.add_child(cat_opt)
	
	var categories = ["cat_none", "cat_circuits", "cat_npcs", "cat_art", "cat_music"]
	for cat in categories:
		cat_opt.add_item(tr(cat))
	cat_opt.selected = old_category
		
	var cat_popup = cat_opt.get_popup()
	cat_popup.add_theme_font_override("font", _get_safe_font())
	cat_popup.add_theme_font_size_override("font_size", int(22 * s))
	
	var btn_hbox = HBoxContainer.new()
	var btn_confirm = Button.new()
	var conf_style = StyleBoxFlat.new()
	var h_conf = StyleBoxFlat.new()
	
	var reset_preview = func():
		selected_overwrite_slot_id[0] = -1
		btn_choose_slot.text = tr("keep_online_file")
		c_style.border_color = Color(0.4, 0.4, 0.5)
		btn_clear_slot.visible = false
		
		btn_confirm.text = tr("confirm_save_changes_title")
		conf_style.bg_color = Color("#ff9f43")
		btn_confirm.add_theme_color_override("font_color", Color.WHITE)
		h_conf.bg_color = Color("#ffb142")
		
		if world_id != "":
			var cache_file = "user://thumb_cache_" + str(world_id) + ".bin"
			if FileAccess.file_exists(cache_file):
				var f = FileAccess.open(cache_file, FileAccess.READ)
				if f:
					var body = f.get_buffer(f.get_length())
					f.close()
					var cache_img = Image.new()
					if cache_img.load_webp_from_buffer(body) == OK or cache_img.load_png_from_buffer(body) == OK or cache_img.load_jpg_from_buffer(body) == OK:
						thumb_rect.texture = ImageTexture.create_from_image(cache_img)
	
	btn_clear_slot.pressed.connect(func():
		_play_action_sound("ui_click")
		reset_preview.call()
	)
	
	var update_preview = func(slot_id: int):
		selected_overwrite_slot_id[0] = slot_id
		var data = _get_slot_data(slot_id)
		
		if data.has("thumbnail"): thumb_rect.texture = data.thumbnail
		else: thumb_rect.texture = null
		
		btn_choose_slot.text = tr("replace_using_slot") + str(slot_id)
		c_style.border_color = Color("#ff9f43")
		btn_clear_slot.visible = true
		
		if uploads_today >= 3 and not pending_ad_upload:
			btn_confirm.text = tr("btn_upload_ad")
			conf_style.bg_color = Color("#fbc531")
			btn_confirm.add_theme_color_override("font_color", Color.BLACK)
			h_conf.bg_color = Color("#f5f6fa")
			
	btn_choose_slot.pressed.connect(func():
		_play_action_sound("ui_click")
		if uploads_today >= 5:
			_show_centered_bubble(tr("msg_edit_limit_reached"), Color(0.8, 0.2, 0.2))
			return
		show_upload_slot_selector(update_preview)
	)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer)
	
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", int(15 * s))
	main_vbox.add_child(btn_hbox)
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("btn_cancel")
	btn_cancel.custom_minimum_size = Vector2(130 * s, 50 * s)
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cancel.add_theme_font_override("font", _get_safe_font())
	btn_cancel.add_theme_font_size_override("font_size", int(18 * s))
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.2, 0.2, 0.25)
	cancel_style.corner_radius_top_left = int(10 * s); cancel_style.corner_radius_top_right = int(10 * s)
	cancel_style.corner_radius_bottom_left = int(10 * s); cancel_style.corner_radius_bottom_right = int(10 * s)
	btn_cancel.add_theme_stylebox_override("normal", cancel_style)
	btn_cancel.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
	)
	btn_hbox.add_child(btn_cancel)
	
	btn_confirm.text = tr("confirm_save_changes_title")
	btn_confirm.custom_minimum_size = Vector2(220 * s, 50 * s)
	btn_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_confirm.add_theme_font_override("font", _get_safe_font())
	btn_confirm.add_theme_font_size_override("font_size", int(18 * s))
	conf_style.bg_color = Color("#ff9f43")
	conf_style.corner_radius_top_left = int(10 * s); conf_style.corner_radius_top_right = int(10 * s)
	conf_style.corner_radius_bottom_left = int(10 * s); conf_style.corner_radius_bottom_right = int(10 * s)
	btn_confirm.add_theme_stylebox_override("normal", conf_style)
	h_conf = conf_style.duplicate()
	h_conf.bg_color = Color("#ffb142")
	btn_confirm.add_theme_stylebox_override("hover", h_conf)
	btn_hbox.add_child(btn_confirm)
	
	btn_confirm.pressed.connect(func():
		if name_input.text.strip_edges() == "": return
		_play_action_sound("ui_click")
		
		var chosen_name = name_input.text
		var chosen_cat = cat_opt.selected
		var overwrite_slot = selected_overwrite_slot_id[0]
		
		if chosen_name == old_title and chosen_cat == old_category and overwrite_slot == -1:
			overlay.queue_free()
			return
			
		var proceed_edit = func():
			var loading_overlay = _show_processing_overlay(tr("msg_saving_changes"))
			
			var on_done = func(success: bool, msg: String, doc_data: Dictionary = {}):
				if is_instance_valid(loading_overlay):
					loading_overlay.queue_free()
					
				if success:
					if overwrite_slot != -1:
						uploads_today += 1
						pending_ad_upload = false
						save_workshop_economy()
						
						var type_str = "ad" if (uploads_today - 1) >= 3 else "free"
						AnalyticsManager.log_event("workshop_upload", {
							"type": type_str,
							"slot": uploads_today,
							"is_update": true
						})
						
					var cache = ui_root.get_meta("workshop_mis_mundos_cache", [])
					for i in range(cache.size()):
						if cache[i].get("id") == world_id or cache[i].get("world_id") == world_id:
							cache[i] = doc_data
							break
					ui_root.set_meta("workshop_mis_mundos_cache", cache)
					save_workshop_cache()
					
					update_local_recientes_cache(world_id, false, {"title": chosen_name, "category": chosen_cat})
					setup_workshop_ui()
					
					if is_instance_valid(overlay): overlay.queue_free()
					_show_centered_bubble(tr("msg_changes_saved_success"), Color("#00cec9"))
				else:
					_show_centered_bubble("Error: " + msg, Color(0.8, 0.2, 0.2))
					
			if not WorkshopManager.update_completed.is_connected(on_done):
				WorkshopManager.update_completed.connect(on_done, CONNECT_ONE_SHOT)
			
			WorkshopManager.update_world(world_id, world_data, chosen_name, chosen_cat, overwrite_slot)
		
		var on_confirmed = func():
			if overwrite_slot != -1 and uploads_today >= 3 and not pending_ad_upload:
				AdMobManager.show_workshop_rewarded()
				var success = await AdMobManager.workshop_rewarded_completed
				if success:
					pending_ad_upload = true
					proceed_edit.call()
				else:
					_show_centered_bubble(tr("msg_error") + ": " + tr("msg_ad_failed") if TranslationServer.get_locale() == "es" else "Error: " + tr("msg_ad_failed"), Color(0.8, 0.2, 0.2))
			else:
				proceed_edit.call()
			
		_show_confirm_dialog(tr("confirm_save_changes_title"), tr("confirm_save_changes_msg"), on_confirmed)
	)


func show_upload_world_dialog() -> void:
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not ui_root: return
	
	var selected_upload_slot_id = [1]
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.8)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	_set_mouse_over_ui(true)
	overlay.tree_exiting.connect(func(): _set_mouse_over_ui(false))
	
	var center = MarginContainer.new()
	overlay.add_child(center)
	
	var popup = PanelContainer.new()
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	popup.custom_minimum_size = Vector2(450 * s, 600 * s)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.16, 1.0)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color("#00d2d3")
	p_style.corner_radius_top_left = int(20 * s); p_style.corner_radius_top_right = int(20 * s)
	p_style.corner_radius_bottom_left = int(20 * s); p_style.corner_radius_bottom_right = int(20 * s)
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(20 * s))
	margin.add_theme_constant_override("margin_bottom", int(20 * s))
	popup.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(15 * s))
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("upload_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", int(28 * s))
	title.add_theme_color_override("font_color", Color("#00d2d3"))
	main_vbox.add_child(title)
	
	var thumb_bg = PanelContainer.new()
	thumb_bg.custom_minimum_size = Vector2(300 * s, 150 * s)
	thumb_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 1)
	bg_style.border_width_left = 2; bg_style.border_width_top = 2
	bg_style.border_width_right = 2; bg_style.border_width_bottom = 2
	bg_style.border_color = Color("#555555")
	thumb_bg.add_theme_stylebox_override("panel", bg_style)
	main_vbox.add_child(thumb_bg)
	
	var thumb_rect = TextureRect.new()
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb_bg.add_child(thumb_rect)
	
	var create_label = func(text_key: String):
		var lbl = Label.new()
		lbl.text = tr(text_key)
		lbl.add_theme_font_override("font", _get_safe_font())
		lbl.add_theme_font_size_override("font_size", int(18 * s))
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		return lbl
		
	main_vbox.add_child(create_label.call("upload_slot_label"))
	var btn_choose_slot = Button.new()
	btn_choose_slot.text = tr("btn_select_slot")
	btn_choose_slot.add_theme_font_override("font", _get_safe_font())
	btn_choose_slot.add_theme_font_size_override("font_size", int(20 * s))
	btn_choose_slot.custom_minimum_size = Vector2(0, 45 * s)
	
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.15, 0.15, 0.2)
	c_style.border_width_left = 2; c_style.border_width_top = 2
	c_style.border_width_right = 2; c_style.border_width_bottom = 2
	c_style.border_color = Color(0.4, 0.4, 0.5)
	c_style.set_corner_radius_all(int(10 * s))
	btn_choose_slot.add_theme_stylebox_override("normal", c_style)
	
	var hc_style = c_style.duplicate()
	hc_style.bg_color = Color(0.25, 0.25, 0.3)
	btn_choose_slot.add_theme_stylebox_override("hover", hc_style)
	btn_choose_slot.add_theme_stylebox_override("pressed", hc_style)
	main_vbox.add_child(btn_choose_slot)
	
	var name_label_hbox = HBoxContainer.new()
	main_vbox.add_child(name_label_hbox)
	
	var name_lbl = create_label.call("upload_name_label")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label_hbox.add_child(name_lbl)
	
	var char_count_lbl = Label.new()
	char_count_lbl.add_theme_font_override("font", _get_safe_font())
	char_count_lbl.add_theme_font_size_override("font_size", int(16 * s))
	char_count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	char_count_lbl.text = "0/30"
	name_label_hbox.add_child(char_count_lbl)
	
	var name_input = LineEdit.new()
	name_input.add_theme_font_override("font", _get_safe_font())
	name_input.add_theme_font_size_override("font_size", int(20 * s))
	name_input.custom_minimum_size = Vector2(0, 45 * s)
	name_input.max_length = 30
	main_vbox.add_child(name_input)
	
	name_input.focus_entered.connect(func():
		var kb_height = DisplayServer.virtual_keyboard_get_height()
		if kb_height == 0: kb_height = 300 * s
		center.add_theme_constant_override("margin_bottom", int(kb_height))
	)
	name_input.focus_exited.connect(func():
		center.add_theme_constant_override("margin_bottom", 0)
	)
	
	name_input.text_changed.connect(func(new_text: String):
		char_count_lbl.text = str(new_text.length()) + "/30"
	)
	
	main_vbox.add_child(create_label.call("upload_category_label"))
	var cat_opt = OptionButton.new()
	cat_opt.add_theme_font_override("font", _get_safe_font())
	cat_opt.add_theme_font_size_override("font_size", int(20 * s))
	cat_opt.custom_minimum_size = Vector2(0, 40 * s)
	main_vbox.add_child(cat_opt)
	
	var categories = ["cat_none", "cat_circuits", "cat_npcs", "cat_art", "cat_music"]
	for cat in categories:
		cat_opt.add_item(tr(cat))
		
	var cat_popup = cat_opt.get_popup()
	cat_popup.add_theme_font_override("font", _get_safe_font())
	cat_popup.add_theme_font_size_override("font_size", int(22 * s))
	
	var update_preview = func(slot_id: int):
		selected_upload_slot_id[0] = slot_id
		var data = _get_slot_data(slot_id)
		
		if data.has("thumbnail"): thumb_rect.texture = data.thumbnail
		else: thumb_rect.texture = null
		
		if data.has("name"): 
			name_input.text = data.name
			btn_choose_slot.text = data.name
		else: 
			name_input.text = ""
			btn_choose_slot.text = "Slot " + str(slot_id) + " (" + tr("empty") + ")"
			
		char_count_lbl.text = str(name_input.text.length()) + "/30"
			
	btn_choose_slot.pressed.connect(func():
		_play_action_sound("ui_click")
		show_upload_slot_selector(update_preview)
	)
	
	var first_avail = 0
	for i in range(1, 11):
		if _get_slot_data(i).has("name"):
			first_avail = i
			break
	if first_avail > 0:
		update_preview.call(first_avail)
	else:
		update_preview.call(1)
		
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", int(15 * s))
	main_vbox.add_child(btn_hbox)
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("btn_cancel")
	btn_cancel.custom_minimum_size = Vector2(130 * s, 50 * s)
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cancel.add_theme_font_override("font", _get_safe_font())
	btn_cancel.add_theme_font_size_override("font_size", int(18 * s))
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.2, 0.2, 0.25)
	cancel_style.corner_radius_top_left = int(10 * s); cancel_style.corner_radius_top_right = int(10 * s)
	cancel_style.corner_radius_bottom_left = int(10 * s); cancel_style.corner_radius_bottom_right = int(10 * s)
	btn_cancel.add_theme_stylebox_override("normal", cancel_style)
	btn_cancel.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
	)
	btn_hbox.add_child(btn_cancel)
	
	var btn_confirm = Button.new()
	btn_confirm.text = tr("btn_upload_confirm")
	btn_confirm.custom_minimum_size = Vector2(220 * s, 50 * s)
	btn_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_confirm.add_theme_font_override("font", _get_safe_font())
	btn_confirm.add_theme_font_size_override("font_size", int(18 * s))
	var conf_style = StyleBoxFlat.new()
	conf_style.bg_color = Color("#00b894")
	conf_style.corner_radius_top_left = int(10 * s); conf_style.corner_radius_top_right = int(10 * s)
	conf_style.corner_radius_bottom_left = int(10 * s); conf_style.corner_radius_bottom_right = int(10 * s)
	btn_confirm.add_theme_stylebox_override("normal", conf_style)
	var h_conf = conf_style.duplicate()
	h_conf.bg_color = Color("#55efc4")
	btn_confirm.add_theme_stylebox_override("hover", h_conf)
	if uploads_today >= 5:
		btn_confirm.disabled = true
		btn_confirm.text = tr("upload_limit_reached")
		conf_style.bg_color = Color(0.4, 0.4, 0.4)
	elif uploads_today >= 3 and not pending_ad_upload:
		btn_confirm.text = tr("btn_upload_ad")
		conf_style.bg_color = Color("#fbc531")
		btn_confirm.add_theme_color_override("font_color", Color.BLACK)
		h_conf.bg_color = Color("#f5f6fa")
		
	btn_confirm.pressed.connect(func():
		var chosen_name = name_input.text.strip_edges()
		if chosen_name == "": return
		_play_action_sound("ui_click")
		
		var slot_id = selected_upload_slot_id[0]
		var cat_id = cat_opt.selected
		
		var proceed_upload = func():
			var loading_overlay = _show_processing_overlay(tr("uploading_world"))
			var start_time = Time.get_ticks_msec()
			
			var on_done = func(success: bool, msg: String, doc_data: Dictionary = {}):
				var elapsed = Time.get_ticks_msec() - start_time
				if elapsed < 2000:
					await get_tree().create_timer((2000 - elapsed) / 1000.0).timeout
					
				if is_instance_valid(loading_overlay):
					loading_overlay.queue_free()
					
				if success:
					uploads_today += 1
					pending_ad_upload = false
					save_workshop_economy()
					
					var type_str = "ad" if (uploads_today - 1) >= 3 else "free"
					AnalyticsManager.log_event("workshop_upload", {
						"type": type_str,
						"slot": uploads_today
					})
					
					var cache = ui_root.get_meta("workshop_mis_mundos_cache", [])
					cache.insert(0, doc_data)
					ui_root.set_meta("workshop_mis_mundos_cache", cache)
					ui_root.set_meta("workshop_total_uploaded_worlds", cache.size())
					save_workshop_cache()
					
					setup_workshop_ui()
					
					if is_instance_valid(overlay): overlay.queue_free()
					_show_centered_bubble(tr("upload_success").replace("'{0}'", "\"" + chosen_name + "\"").replace("{0}", "\"" + chosen_name + "\""), Color("#00cec9"))
				else:
					_show_centered_bubble("Error: " + msg, Color(0.8, 0.2, 0.2))
					
			if not WorkshopManager.upload_completed.is_connected(on_done):
				WorkshopManager.upload_completed.connect(on_done, CONNECT_ONE_SHOT)
			
			WorkshopManager.upload_world(slot_id, chosen_name, cat_id)
			
		var on_confirmed = func():
			if uploads_today >= 3 and not pending_ad_upload:
				AdMobManager.show_workshop_rewarded()
				var success = await AdMobManager.workshop_rewarded_completed
				if success:
					pending_ad_upload = true
					proceed_upload.call()
				else:
					_show_centered_bubble(tr("msg_error") + ": " + tr("msg_ad_failed") if TranslationServer.get_locale() == "es" else "Error: " + tr("msg_ad_failed"), Color(0.8, 0.2, 0.2))
			else:
				proceed_upload.call()
				
		_show_confirm_dialog(tr("confirm_upload_world_title"), tr("confirm_upload_world_msg"), on_confirmed)
	)
	btn_hbox.add_child(btn_confirm)


# Aliases
func _show_upload_slot_selector(on_selected: Callable) -> void: show_upload_slot_selector(on_selected)
func _show_world_manager_dialog() -> void: show_world_manager_dialog()
func _delete_world_from_workshop(world_id: String, world_title: String) -> void: delete_world_from_workshop(world_id, world_title)
func _load_workshop_cache() -> void: load_workshop_cache()
func _save_workshop_cache() -> void: save_workshop_cache()
func _on_world_edit_requested(world_data: Dictionary) -> void: on_world_edit_requested(world_data)
func _show_edit_world_dialog(world_data: Dictionary) -> void: show_edit_world_dialog(world_data)
func _show_upload_world_dialog() -> void: show_upload_world_dialog()
