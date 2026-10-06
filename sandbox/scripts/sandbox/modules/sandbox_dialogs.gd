extends Node
class_name SandboxDialogManager

## Módulo especializado en la gestión de diálogos, popups modales, tutoriales y recordatorios.
## Administra:
## 1. Tutorial de navegación y zoom de cámara (_show_zoom_tutorial_bubble).
## 2. Diálogo de bienvenida multilingüe con espectáculo de pirotecnia (_show_welcome_message).
## 3. Diálogo de valoración con estrellas para Google Play / In-App Review (_show_rating_popup).
## 4. Tutorial guiado interactivo de 8 pasos con recortes de oscurecimiento dinámicos (_show_main_tutorial_step).
## 5. Efectos de pulso y atención en botones del HUD (_start_pulse, _stop_pulse).
## 6. Recordatorios informativos contextuales dentro de menús (_show_menu_reminder).
## 7. Burbujas explicativas de compuertas lógicas, celdas de cuadrícula, bloques de fase, cañones y pistones.
## 8. Modal especial de agradecimiento al creador con shader de borde neón giratorio (_show_thank_you_popup).
## 9. Visor modal de imágenes a pantalla completa con zoom (_show_fullscreen_image).
## 10. Burbuja flotante informativa centrada (_show_centered_bubble).

# Referencia al nodo central de la cuadrícula
var grid: Node = null

# --- VARIABLES DE ESTADO: TUTORIAL DE ZOOM ---
var is_zoom_tutorial_done: bool = false
var zoom_tutorial_bubble: PanelContainer = null

# --- VARIABLES DE ESTADO: TUTORIAL INTERACTIVO PRINCIPAL ---
var main_tutorial_step: int = 0
var main_tutorial_overlay: Control = null

# --- VARIABLES DE ESTADO: POPUP DE VALORACIÓN ---
var play_time_for_rating: float = 0.0
var rating_popup_shown: bool = false

# --- VARIABLES DE ESTADO: BURBUJAS DE MECANISMOS Y CIRCUITOS ---
var is_logic_gate_tutorial_done: bool = false
var is_grid_tutorial_done: bool = false
var logic_gate_tutorial_bubble: PanelContainer = null

var is_phase_block_tutorial_done: bool = false
var phase_block_tutorial_bubble: PanelContainer = null

var is_cannon_tutorial_done: bool = false
var cannon_tutorial_bubble: PanelContainer = null

var is_piston_tutorial_done: bool = false
var piston_tutorial_bubble: PanelContainer = null


func setup(p_grid: Node) -> void:
	grid = p_grid

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

func _play_action_sound(sound_name: String) -> void:
	if is_instance_valid(grid) and grid.has_method("_play_action_sound"):
		grid._play_action_sound(sound_name)

func _get_viewport_rect() -> Rect2:
	if is_instance_valid(grid) and grid.has_method("get_viewport_rect"):
		return grid.get_viewport_rect()
	var vp = get_viewport()
	if is_instance_valid(vp):
		return vp.get_visible_rect()
	return Rect2()

func _get_mouse_position() -> Vector2:
	if is_instance_valid(grid):
		var vp = grid.get_viewport()
		if is_instance_valid(vp):
			return vp.get_mouse_position()
	var vp = get_viewport()
	if is_instance_valid(vp):
		return vp.get_mouse_position()
	return Vector2.ZERO


# =========================================================================
# 1. TUTORIAL DE ZOOM Y PANNING
# =========================================================================

func show_zoom_tutorial_bubble() -> void:
	if is_instance_valid(zoom_tutorial_bubble):
		zoom_tutorial_bubble.queue_free()
		
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return
		
	var s = _get_ui_scale()
	var btn = grid.ui_elements.get("btn_pan") if is_instance_valid(grid) else null
	if not is_instance_valid(btn):
		return
	
	# Contenedor del panel
	var bubble = PanelContainer.new()
	zoom_tutorial_bubble = bubble
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Estilo: Estética glassmorphism coordinada con los demás tutoriales
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.12, 0.96) # Pizarra oscura semitransparente
	p_style.set_corner_radius_all(18 * s)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color(0.12, 0.32, 0.62, 0.95) # Azul real para modo paneo
	p_style.shadow_color = Color(0, 0, 0, 0.45)
	p_style.shadow_size = 10
	bubble.add_theme_stylebox_override("panel", p_style)
	
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_theme_constant_override("margin_left", int(24 * s))
	margin.add_theme_constant_override("margin_top", int(20 * s))
	margin.add_theme_constant_override("margin_right", int(24 * s))
	margin.add_theme_constant_override("margin_bottom", int(20 * s))
	bubble.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_theme_constant_override("separation", int(14 * s))
	margin.add_child(vbox)
	
	# Título
	var title_lbl = Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	title_lbl.text = tr("tut_zoom_title")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(360 * s, 0)
	title_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", int(24 * s))
	title_lbl.add_theme_color_override("font_color", Color(0.35, 0.65, 1.0, 1.0))
	vbox.add_child(title_lbl)
	
	# Paso 1: Zoom
	var step1_lbl = Label.new()
	step1_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	step1_lbl.text = tr("tut_zoom_step1")
	step1_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	step1_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step1_lbl.custom_minimum_size = Vector2(360 * s, 0)
	step1_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	step1_lbl.add_theme_font_size_override("font_size", int(20 * s))
	step1_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(step1_lbl)
	
	# Paso 2: Desplazamiento
	var step2_lbl = Label.new()
	step2_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	step2_lbl.text = tr("tut_zoom_step2")
	step2_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	step2_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step2_lbl.custom_minimum_size = Vector2(360 * s, 0)
	step2_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	step2_lbl.add_theme_font_size_override("font_size", int(20 * s))
	step2_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(step2_lbl)
	
	# Botón Entendido
	var btn_ok = Button.new()
	btn_ok.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_ok.text = tr("GOT_IT")
	btn_ok.custom_minimum_size = Vector2(170 * s, 54 * s)
	btn_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_ok.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	btn_ok.add_theme_font_size_override("font_size", int(21 * s))
	
	var btn_style_norm = StyleBoxFlat.new()
	btn_style_norm.bg_color = Color(0.12, 0.32, 0.62, 1.0)
	btn_style_norm.set_corner_radius_all(12 * s)
	
	var btn_style_hover = btn_style_norm.duplicate()
	btn_style_hover.bg_color = Color(0.18, 0.42, 0.78, 1.0)
	
	btn_ok.add_theme_stylebox_override("normal", btn_style_norm)
	btn_ok.add_theme_stylebox_override("hover", btn_style_hover)
	btn_ok.add_theme_stylebox_override("pressed", btn_style_norm)
	btn_ok.add_theme_color_override("font_color", Color.WHITE)
	
	btn_ok.pressed.connect(func():
		_play_action_sound("ui_click")
		is_zoom_tutorial_done = true
		if is_instance_valid(grid) and grid.has_method("_save_tool_settings"):
			grid._save_tool_settings()
		bubble.queue_free()
	)
	vbox.add_child(btn_ok)
	
	ui_root.add_child(bubble)
	
	# Posicionar la burbuja sobre/a la izquierda del botón de paneo
	var btn_global_rect = btn.get_global_rect()
	var screen_pos = btn_global_rect.position
	
	bubble.position = Vector2(screen_pos.x + btn_global_rect.size.x / 2.0 - 200 * s, screen_pos.y - 300 * s)
	var vp_rect = _get_viewport_rect()
	bubble.position.x = clamp(bubble.position.x, 10 * s, vp_rect.size.x - 420 * s)
	bubble.position.y = clamp(bubble.position.y, 10 * s, vp_rect.size.y - 320 * s)


# =========================================================================
# 2. DIÁLOGO DE BIENVENIDA MULTILINGÜE
# =========================================================================

func show_welcome_message() -> void:
	var save_path = "user://welcome_shown.save"
	if FileAccess.file_exists(save_path):
		return
		
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string("shown")
		file.close()

	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return
		
	var overlay = ColorRect.new()
	overlay.name = "WelcomeOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	var panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320 * s
	panel.offset_top = -300 * s
	panel.offset_right = 320 * s
	panel.offset_bottom = 300 * s
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	var bw = int(4 * s)
	p_style.border_width_left = bw
	p_style.border_width_top = bw
	p_style.border_width_right = bw
	p_style.border_width_bottom = bw
	p_style.border_color = Color(0.4, 0.4, 0.5)
	p_style.corner_radius_top_left = int(20 * s)
	p_style.corner_radius_top_right = int(20 * s)
	p_style.corner_radius_bottom_left = int(20 * s)
	p_style.corner_radius_bottom_right = int(20 * s)
	p_style.shadow_color = Color(0, 0, 0, 0.5)
	p_style.shadow_size = int(10 * s)
	panel.add_theme_stylebox_override("panel", p_style)
	
	overlay.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", int(30 * s))
	margin.add_theme_constant_override("margin_bottom", int(30 * s))
	margin.add_theme_constant_override("margin_left", int(30 * s))
	margin.add_theme_constant_override("margin_right", int(30 * s))
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(25 * s))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = tr("welcome_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	title.add_theme_font_size_override("font_size", int(34 * s))
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	vbox.add_child(title)
	
	var label = Label.new()
	label.text = tr("welcome_msg").replace("\\n", "\n")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	label.add_theme_font_size_override("font_size", int(24 * s))
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)
	
	var btn = Button.new()
	btn.text = tr("welcome_close")
	btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	btn.add_theme_font_size_override("font_size", int(30 * s))
	btn.custom_minimum_size = Vector2(250 * s, 60 * s)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.6, 0.3)
	var bbw = int(2 * s)
	btn_style.border_width_left = bbw
	btn_style.border_width_top = bbw
	btn_style.border_width_right = bbw
	btn_style.border_width_bottom = bbw
	btn_style.border_color = Color(0.3, 0.8, 0.4)
	btn_style.corner_radius_top_left = int(12 * s)
	btn_style.corner_radius_top_right = int(12 * s)
	btn_style.corner_radius_bottom_left = int(12 * s)
	btn_style.corner_radius_bottom_right = int(12 * s)
	btn.add_theme_stylebox_override("normal", btn_style)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.3, 0.7, 0.4)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_stylebox_override("pressed", btn_hover)
	
	btn.pressed.connect(func():
		_play_action_sound("ui_click")
		
		# TUTORIAL: Garantizar que caiga arena al cerrar por primera vez
		if is_instance_valid(grid):
			var center = btn.global_position + (btn.size / 2.0)
			var gx = int(center.x / grid.grid_scale)
			var gy = int(center.y / grid.grid_scale)
			if grid.has_method("_draw_circle"):
				grid._draw_circle(gx, gy, 7, 1) # Material 1 (Arena)
		
		overlay.queue_free()
		
		# Spawneo de fuegos artificiales de bienvenida directos (con retraso y tandas)
		var spawn_fireworks = func():
			await get_tree().create_timer(2.0).timeout
			if not is_instance_valid(grid):
				return
				
			var left_x = int(grid.grid_width * 0.25)
			var right_x = int(grid.grid_width * 0.75)
			var base_y = int(grid.dynamic_grid_height * 0.8)
			
			for round_idx in range(3):
				for i in range(3):
					if grid.has_method("_launch_firework"):
						grid._launch_firework(left_x + randi_range(-20, 20), base_y + randi_range(-10, 10))
						grid._launch_firework(right_x + randi_range(-20, 20), base_y + randi_range(-10, 10))
					await get_tree().create_timer(0.3).timeout
				await get_tree().create_timer(1.0).timeout
			
			start_interactive_tutorial()
				
		spawn_fireworks.call()
	)


# =========================================================================
# 3. POPUP DE CALIFICACIÓN EN TIENDA (GOOGLE PLAY / IN-APP REVIEW)
# =========================================================================

func process_rating_timer(delta: float) -> void:
	if rating_popup_shown or not is_instance_valid(grid):
		return
	# Mostrar solo tras 15 minutos de la segunda sesión en adelante
	if grid._current_session_count >= 2:
		play_time_for_rating += delta
		if play_time_for_rating >= 900.0:
			var current_time = Time.get_unix_time_from_system()
			if current_time - AdMobManager.last_ad_interaction_time >= 180.0:
				rating_popup_shown = true
				call_deferred("show_rating_popup")

func show_rating_popup() -> void:
	var s = _get_ui_scale()
	var screen_size = _get_viewport_rect().size
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return
	
	# Capa atenuada completa
	var overlay = Control.new()
	overlay.name = "RatingPopupOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	
	# Panel principal
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.1, 0.1, 0.18, 0.97)
	p_style.set_border_width_all(int(3 * s))
	p_style.border_color = Color(0.95, 0.75, 0.2)
	p_style.set_corner_radius_all(int(20 * s))
	panel.add_theme_stylebox_override("panel", p_style)
	overlay.add_child(panel)
	
	var marg = MarginContainer.new()
	var m_val = int(25 * s)
	marg.add_theme_constant_override("margin_top", m_val)
	marg.add_theme_constant_override("margin_bottom", m_val)
	marg.add_theme_constant_override("margin_left", m_val)
	marg.add_theme_constant_override("margin_right", m_val)
	panel.add_child(marg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(15 * s))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	marg.add_child(vbox)
	
	# Encabezado con 5 estrellas
	var star_lbl = Label.new()
	star_lbl.text = "⭐⭐⭐⭐⭐"
	star_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	star_lbl.add_theme_font_size_override("font_size", int(32 * s))
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(star_lbl)
	
	# Título
	var title_lbl = Label.new()
	title_lbl.text = tr("RATING_TITLE")
	title_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", int(26 * s))
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(280 * s, 0)
	vbox.add_child(title_lbl)
	
	# Subtítulo
	var sub_lbl = Label.new()
	sub_lbl.text = tr("RATING_SUBTITLE")
	sub_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	sub_lbl.add_theme_font_size_override("font_size", int(20 * s))
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.custom_minimum_size = Vector2(280 * s, 0)
	vbox.add_child(sub_lbl)
	
	# Botones de acción
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", int(20 * s))
	vbox.add_child(btn_hbox)
	
	# Botón Calificar (verde)
	var rate_btn = Button.new()
	rate_btn.text = tr("RATING_RATE_BTN")
	rate_btn.custom_minimum_size = Vector2(140 * s, 55 * s)
	rate_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	rate_btn.add_theme_font_size_override("font_size", int(22 * s))
	var rate_style = StyleBoxFlat.new()
	rate_style.bg_color = Color(0.2, 0.65, 0.3)
	rate_style.set_corner_radius_all(12 * s)
	rate_btn.add_theme_stylebox_override("normal", rate_style)
	rate_btn.add_theme_stylebox_override("hover", rate_style)
	rate_btn.add_theme_stylebox_override("pressed", rate_style)
	
	rate_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		var f = FileAccess.open("user://rating_popup_shown.save", FileAccess.WRITE)
		if f:
			f.store_string("shown")
			f.close()
		
		if Engine.has_singleton("InappReviewPlugin"):
			var InappReviewScript = preload("res://addons/InappReviewPlugin/InappReview.gd")
			var inapp_review = InappReviewScript.new()
			add_child(inapp_review)
			
			inapp_review.review_info_generated.connect(func():
				inapp_review.launch_review_flow()
			)
			inapp_review.review_info_generation_failed.connect(func():
				OS.shell_open("https://play.google.com/store/apps/details?id=com.sandbox.elexstudio")
				inapp_review.queue_free()
			)
			inapp_review.review_flow_launched.connect(func():
				inapp_review.queue_free()
			)
			inapp_review.review_flow_launch_failed.connect(func():
				OS.shell_open("https://play.google.com/store/apps/details?id=com.sandbox.elexstudio")
				inapp_review.queue_free()
			)
			inapp_review.generate_review_info()
		else:
			OS.shell_open("https://play.google.com/store/apps/details?id=com.sandbox.elexstudio")
			
		overlay.queue_free()
	)
	btn_hbox.add_child(rate_btn)
	
	# Botón Más tarde (gris sutil)
	var later_btn = Button.new()
	later_btn.text = tr("RATING_LATER_BTN")
	later_btn.custom_minimum_size = Vector2(140 * s, 55 * s)
	later_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	later_btn.add_theme_font_size_override("font_size", int(22 * s))
	var later_style = StyleBoxFlat.new()
	later_style.bg_color = Color(0.35, 0.35, 0.4)
	later_style.set_corner_radius_all(12 * s)
	later_btn.add_theme_stylebox_override("normal", later_style)
	later_btn.add_theme_stylebox_override("hover", later_style)
	later_btn.add_theme_stylebox_override("pressed", later_style)
	
	later_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		var f = FileAccess.open("user://rating_popup_shown.save", FileAccess.WRITE)
		if f:
			f.store_string("shown")
			f.close()
		overlay.queue_free()
	)
	btn_hbox.add_child(later_btn)
	
	# Centrar el panel en pantalla
	await get_tree().process_frame
	if is_instance_valid(panel):
		var p_size = panel.get_combined_minimum_size()
		panel.position = (screen_size - p_size) / 2.0


# =========================================================================
# 4. TUTORIAL INTERACTIVO PASO A PASO
# =========================================================================

func start_interactive_tutorial() -> void:
	var save_path = "user://main_tutorial_shown.save"
	if FileAccess.file_exists(save_path):
		return
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string("shown")
		file.close()

	main_tutorial_step = 0
	show_main_tutorial_step()

func show_main_tutorial_step() -> void:
	var steps = [
		{"target": "quick_actions_grid", "text": tr("TUTORIAL_STEP_8")},
		{"target": "material_scroll", "text": tr("TUTORIAL_STEP_1")},
		{"target": "tools_btn", "text": tr("TUTORIAL_STEP_2")},
		{"target": "lab_btn", "text": tr("TUTORIAL_STEP_3")},
		{"target": "disaster_btn", "text": tr("TUTORIAL_STEP_4")},
		{"target": "npc_btn", "text": tr("TUTORIAL_STEP_5")},
		{"target": "paint_btn", "text": tr("TUTORIAL_STEP_6")},
		{"target": "music_btn", "text": tr("TUTORIAL_STEP_7")}
	]
	
	if main_tutorial_step >= steps.size():
		if is_instance_valid(main_tutorial_overlay):
			main_tutorial_overlay.queue_free()
			main_tutorial_overlay = null
		return
		
	var step_data = steps[main_tutorial_step]
	var target_key = step_data["target"]
	var target_node: Control = null
	
	if is_instance_valid(grid):
		if target_key == "material_scroll":
			target_node = grid.material_scroll
		elif grid.ui_elements.has(target_key):
			target_node = grid.ui_elements.get(target_key)
			
		# Búsqueda de rescate en el árbol de controles principales
		if not is_instance_valid(target_node) and is_instance_valid(grid.main_controls):
			target_node = grid.main_controls.find_child(target_key, true, false)
			if not target_node:
				var search_name = target_key.capitalize().replace("_", "").replace(" ", "")
				target_node = grid.main_controls.find_child(search_name, true, false)

	if not is_instance_valid(target_node) or not target_node.is_inside_tree() or not target_node.is_visible_in_tree():
		main_tutorial_step += 1
		call_deferred("show_main_tutorial_step")
		return
		
	var s = _get_ui_scale()
	var rect = target_node.get_global_rect()
	var screen_size = _get_viewport_rect().size
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return
	
	if not is_instance_valid(main_tutorial_overlay):
		main_tutorial_overlay = Control.new()
		main_tutorial_overlay.name = "MainTutorialOverlay"
		main_tutorial_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main_tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		ui_root.add_child(main_tutorial_overlay)
	else:
		for c in main_tutorial_overlay.get_children():
			c.queue_free()
	
	# Función para crear rectángulos de oscurecimiento
	var create_dim = func(pos, sz):
		var r = ColorRect.new()
		r.color = Color(0, 0, 0, 0.8)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.position = pos
		r.size = sz
		main_tutorial_overlay.add_child(r)
		
	var padding = 5 * s
	var c_rect = rect.grow(padding).intersection(_get_viewport_rect())
	
	create_dim.call(Vector2(0, 0), Vector2(screen_size.x, c_rect.position.y))
	create_dim.call(Vector2(0, c_rect.end.y), Vector2(screen_size.x, screen_size.y - c_rect.end.y))
	create_dim.call(Vector2(0, c_rect.position.y), Vector2(c_rect.position.x, c_rect.size.y))
	create_dim.call(Vector2(c_rect.end.x, c_rect.position.y), Vector2(screen_size.x - c_rect.end.x, c_rect.size.y))
	
	var highlight_border = ReferenceRect.new()
	highlight_border.position = c_rect.position
	highlight_border.size = c_rect.size
	highlight_border.border_color = Color(0.4, 1.0, 0.4)
	highlight_border.border_width = 4 * s
	highlight_border.editor_only = false
	main_tutorial_overlay.add_child(highlight_border)
	
	var tw = create_tween().set_loops().bind_node(highlight_border)
	tw.tween_property(highlight_border, "border_color", Color(0.4, 1.0, 0.4, 0.2), 0.6)
	tw.tween_property(highlight_border, "border_color", Color(0.4, 1.0, 0.4, 1.0), 0.6)
	
	# Panel del paso tutorial
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	p_style.set_border_width_all(int(3 * s))
	p_style.border_color = Color(0.3, 0.8, 0.4)
	p_style.set_corner_radius_all(int(15 * s))
	panel.add_theme_stylebox_override("panel", p_style)
	main_tutorial_overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(15 * s))
	var marg = MarginContainer.new()
	var m_val = int(20 * s)
	marg.add_theme_constant_override("margin_top", m_val)
	marg.add_theme_constant_override("margin_bottom", m_val)
	marg.add_theme_constant_override("margin_left", m_val)
	marg.add_theme_constant_override("margin_right", m_val)
	marg.add_child(vbox)
	panel.add_child(marg)
	
	var count_lbl = Label.new()
	count_lbl.text = str(main_tutorial_step + 1) + "/" + str(steps.size())
	count_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	count_lbl.add_theme_font_size_override("font_size", int(18 * s))
	count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(count_lbl)
	
	var lbl = Label.new()
	lbl.text = step_data["text"]
	lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	lbl.add_theme_font_size_override("font_size", int(24 * s))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(300 * s, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", int(20 * s))
	vbox.add_child(btn_hbox)
	
	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(120 * s, 50 * s)
	ok_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	ok_btn.add_theme_font_size_override("font_size", int(24 * s))
	var ok_style = StyleBoxFlat.new()
	ok_style.bg_color = Color(0.2, 0.6, 0.3)
	ok_style.set_corner_radius_all(int(10 * s))
	ok_btn.add_theme_stylebox_override("normal", ok_style)
	ok_btn.add_theme_stylebox_override("hover", ok_style)
	ok_btn.add_theme_stylebox_override("pressed", ok_style)
	
	ok_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		ok_btn.disabled = true
		main_tutorial_step += 1
		call_deferred("show_main_tutorial_step")
	)
	btn_hbox.add_child(ok_btn)
	
	var skip_btn = Button.new()
	skip_btn.text = tr("skip_tutorial")
	skip_btn.custom_minimum_size = Vector2(150 * s, 50 * s)
	skip_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	skip_btn.add_theme_font_size_override("font_size", int(24 * s))
	var skip_style = StyleBoxFlat.new()
	skip_style.bg_color = Color(0.7, 0.2, 0.2)
	skip_style.set_corner_radius_all(int(10 * s))
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	skip_btn.add_theme_stylebox_override("hover", skip_style)
	skip_btn.add_theme_stylebox_override("pressed", skip_style)
	
	skip_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		skip_btn.disabled = true
		main_tutorial_step = steps.size()
		call_deferred("show_main_tutorial_step")
	)
	btn_hbox.add_child(skip_btn)
	
	# Posicionamiento dinámico adaptado a la posición del elemento objetivo
	var p_size = panel.get_combined_minimum_size()
	panel.position.x = (screen_size.x - p_size.x) / 2.0
	
	if target_key == "material_scroll":
		panel.position.y = rect.position.y - p_size.y - 50 * s
	elif rect.position.y > screen_size.y * 0.5:
		panel.position.y = rect.position.y - p_size.y - 40 * s
	else:
		panel.position.y = rect.end.y + 40 * s

	panel.position.y = clamp(panel.position.y, 20 * s, screen_size.y - p_size.y - 20 * s)
	panel.position.x = clamp(panel.position.x, 10 * s, screen_size.x - p_size.x - 10 * s)


# =========================================================================
# 5. EFECTOS DE PULSO Y ATENCIÓN VISUAL
# =========================================================================

func start_pulse(btn: Control) -> void:
	if not is_instance_valid(btn):
		return
	stop_pulse(btn)
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(btn, "self_modulate", Color(1.8, 1.8, 0.6), 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	btn.set_meta("pulse_tween", tween)

func stop_pulse(btn: Control) -> void:
	if not is_instance_valid(btn):
		return
	if btn.has_meta("pulse_tween"):
		var tween = btn.get_meta("pulse_tween")
		if is_instance_valid(tween):
			tween.kill()
		btn.remove_meta("pulse_tween")
	btn.self_modulate = Color.WHITE


# =========================================================================
# 6. RECORDATORIOS DENTRO DE MENÚS (TIPS FLOTANTES)
# =========================================================================

func show_menu_reminder(menu_id: String, parent_vbox: VBoxContainer, text_key: String) -> void:
	var save_path = "user://reminder_seen_" + menu_id + ".save"
	if FileAccess.file_exists(save_path):
		return
		
	if not is_instance_valid(parent_vbox) or parent_vbox.has_node("MenuReminder"):
		return

	var s = _get_ui_scale()
	var pnl = PanelContainer.new()
	pnl.name = "MenuReminder"
	
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.3, 0.5, 0.95)
	st.border_width_left = 2; st.border_width_top = 2
	st.border_width_right = 2; st.border_width_bottom = 2
	st.border_color = Color(0.3, 0.6, 1.0)
	st.set_corner_radius_all(int(15 * s))
	pnl.add_theme_stylebox_override("panel", st)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(15 * s))
	margin.add_theme_constant_override("margin_bottom", int(15 * s))
	pnl.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(10 * s))
	margin.add_child(vbox)
	
	var tip_lbl = Label.new()
	tip_lbl.text = "💡 INFO"
	tip_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	tip_lbl.add_theme_font_size_override("font_size", int(18 * s))
	tip_lbl.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(tip_lbl)
	
	var lbl = Label.new()
	lbl.text = tr(text_key)
	lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	lbl.add_theme_font_size_override("font_size", int(21 * s))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.text = tr("GOT_IT")
	btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	btn.add_theme_font_size_override("font_size", int(22 * s))
	btn.custom_minimum_size = Vector2(150 * s, 45 * s)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var bst = StyleBoxFlat.new()
	bst.bg_color = Color(0.2, 0.6, 0.3)
	bst.set_corner_radius_all(int(10 * s))
	btn.add_theme_stylebox_override("normal", bst)
	
	btn.pressed.connect(func():
		_play_action_sound("ui_click")
		var file = FileAccess.open(save_path, FileAccess.WRITE)
		if file:
			file.store_string("seen")
			file.close()
		pnl.queue_free()
	)
	vbox.add_child(btn)
	
	parent_vbox.add_child(pnl)
	parent_vbox.move_child(pnl, 1)


# =========================================================================
# 7. BURBUJAS TUTORIALES DE CIRCUITOS, COMPUERTAS, CAÑONES Y PISTONES
# =========================================================================

func check_logic_gate_tutorial(grid_pos: Vector2i) -> void:
	if not is_logic_gate_tutorial_done:
		show_logic_gate_tutorial_bubble(grid_pos)

func show_logic_gate_tutorial_bubble(grid_pos: Vector2i) -> void:
	logic_gate_tutorial_bubble = show_unified_tutorial_bubble(
		grid_pos,
		"tut_logic_gate",
		func():
			is_logic_gate_tutorial_done = true
			if is_instance_valid(grid) and grid.has_method("_save_tool_settings"):
				grid._save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		200.0
	)

func show_grid_tutorial_bubble() -> void:
	var bubble = show_unified_tutorial_bubble(
		Vector2i.ZERO,
		"tut_grid",
		func(): pass,
		Color(0.25, 0.45, 0.85, 0.95),
		200.0
	)
	if is_instance_valid(bubble):
		var s = _get_ui_scale()
		var screen_size = _get_viewport_rect().size
		bubble.position = Vector2(screen_size.x / 2.0 - (160 * s), screen_size.y / 2.0 - (100 * s))

func check_phase_block_tutorial(grid_pos: Vector2i) -> void:
	if not is_phase_block_tutorial_done:
		show_phase_block_tutorial_bubble(grid_pos)

func show_phase_block_tutorial_bubble(grid_pos: Vector2i) -> void:
	phase_block_tutorial_bubble = show_unified_tutorial_bubble(
		grid_pos,
		"tut_phase_block",
		func():
			is_phase_block_tutorial_done = true
			if is_instance_valid(grid) and grid.has_method("_save_tool_settings"):
				grid._save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		230.0
	)

func show_cannon_tutorial_bubble(grid_pos: Vector2i) -> void:
	cannon_tutorial_bubble = show_unified_tutorial_bubble(
		grid_pos,
		"tut_cannon",
		func():
			is_cannon_tutorial_done = true
			if is_instance_valid(grid) and grid.has_method("_save_tool_settings"):
				grid._save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		330.0
	)

func show_piston_tutorial_bubble(grid_pos: Vector2i) -> void:
	piston_tutorial_bubble = show_unified_tutorial_bubble(
		grid_pos,
		"tut_piston",
		func():
			is_piston_tutorial_done = true
			if is_instance_valid(grid) and grid.has_method("_save_tool_settings"):
				grid._save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		230.0
	)

func show_unified_tutorial_bubble(_grid_pos: Vector2i, text_key: String, on_got_it: Callable, border_color: Color, bubble_h_unscaled: float) -> PanelContainer:
	if is_instance_valid(logic_gate_tutorial_bubble):
		logic_gate_tutorial_bubble.queue_free()
	if is_instance_valid(phase_block_tutorial_bubble):
		phase_block_tutorial_bubble.queue_free()

	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return null
		
	var s = _get_ui_scale()
	var bubble = PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	p_style.set_corner_radius_all(int(18 * s))
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = border_color
	p_style.shadow_color = Color(0, 0, 0, 0.45)
	p_style.shadow_size = 10
	bubble.add_theme_stylebox_override("panel", p_style)
	
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(16 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_bottom", int(16 * s))
	bubble.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_theme_constant_override("separation", int(10 * s))
	margin.add_child(vbox)
	
	var lbl = Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.text = tr(text_key)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(280 * s, 0)
	lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	lbl.add_theme_font_size_override("font_size", int(20 * s))
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.text = tr("GOT_IT")
	btn.custom_minimum_size = Vector2(130 * s, 46 * s)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	btn.add_theme_font_size_override("font_size", int(18 * s))
	
	var btn_style_norm = StyleBoxFlat.new()
	btn_style_norm.bg_color = border_color
	btn_style_norm.set_corner_radius_all(int(10 * s))
	
	var btn_style_hover = btn_style_norm.duplicate()
	btn_style_hover.bg_color = border_color.lightened(0.15)
	
	btn.add_theme_stylebox_override("normal", btn_style_norm)
	btn.add_theme_stylebox_override("hover", btn_style_hover)
	btn.add_theme_stylebox_override("pressed", btn_style_norm)
	btn.add_theme_color_override("font_color", Color.WHITE)
	
	btn.pressed.connect(func():
		_play_action_sound("ui_click")
		on_got_it.call()
		bubble.queue_free()
	)
	vbox.add_child(btn)
	
	ui_root.add_child(bubble)
	
	var screen_pos = _get_mouse_position()
	var bubble_w = 320 * s
	var bubble_h = bubble_h_unscaled * s
	var margin_y = 20 * s
	
	var target_y = screen_pos.y - bubble_h - margin_y
	if target_y < 30 * s:
		target_y = screen_pos.y + 40 * s
		
	bubble.position.x = screen_pos.x - bubble_w / 2.0
	bubble.position.y = target_y
	
	var screen_size = _get_viewport_rect().size
	bubble.position.x = clamp(bubble.position.x, 10 * s, screen_size.x - bubble_w - 10 * s)
	bubble.position.y = clamp(bubble.position.y, 10 * s, screen_size.y - bubble_h - 10 * s)
	
	return bubble


# =========================================================================
# 8. DIÁLOGO ESPECIAL DE AGRADECIMIENTO CON SHADER NEÓN
# =========================================================================

func show_thank_you_popup(prev_paused: bool) -> void:
	var s = _get_ui_scale()
	var screen_size = _get_viewport_rect().size
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return
	
	var overlay = Control.new()
	overlay.name = "ThankYouPopupOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	
	var panel = PanelContainer.new()
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	bg_style.set_corner_radius_all(int(24 * s))
	bg_style.shadow_size = 0
	panel.add_theme_stylebox_override("panel", bg_style)
	
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)
	
	# Panel de resplandor neón con shader rotativo
	var glow_panel = Panel.new()
	glow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	p_style.set_border_width_all(int(6 * s))
	p_style.border_color = Color(1.0, 1.0, 1.0, 1.0)
	p_style.set_corner_radius_all(int(24 * s))
	p_style.draw_center = false
	
	p_style.shadow_color = Color(1.0, 1.0, 1.0, 1.0)
	p_style.shadow_size = int(72 * s)
	p_style.shadow_offset = Vector2.ZERO
	glow_panel.add_theme_stylebox_override("panel", p_style)
	
	var neon_shader = Shader.new()
	neon_shader.code = """shader_type canvas_item;
uniform float time_speed = 1.0;
void fragment() {
	vec2 center = vec2(0.5, 0.5);
	vec2 dir = UV - center;
	float angle = atan(dir.y, dir.x);
	float hue = (angle / 6.2831853) + TIME * time_speed;
	hue = fract(hue);
	
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(vec3(hue) + K.xyz) * 6.0 - K.www);
	vec3 rgb = clamp(p - K.xxx, 0.0, 1.0);
	
	float core_factor = clamp((COLOR.a - 0.7) / 0.3, 0.0, 1.0);
	vec3 neon_color = mix(rgb, vec3(1.0), core_factor * 0.55);
	
	float alpha = pow(COLOR.a, 2.2);
	COLOR = vec4(neon_color, alpha * 0.95);
}"""
	var neon_mat = ShaderMaterial.new()
	neon_mat.shader = neon_shader
	neon_mat.set_shader_parameter("time_speed", 0.06)
	glow_panel.material = neon_mat
	panel.add_child(glow_panel)
	
	var marg = MarginContainer.new()
	var m_val = int(25 * s)
	marg.add_theme_constant_override("margin_top", m_val)
	marg.add_theme_constant_override("margin_bottom", m_val)
	marg.add_theme_constant_override("margin_left", m_val)
	marg.add_theme_constant_override("margin_right", m_val)
	panel.add_child(marg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(15 * s))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	marg.add_child(vbox)
	
	var images = [
		"res://assets/Gracias/Editando_Primer_Trailer.jpg",
		"res://assets/Gracias/Foto_Agradecimiento.jpg",
		"res://assets/Gracias/Primera_Interfaz.jpg",
		"res://assets/Gracias/Primera_Prueba_musical.jpg",
		"res://assets/Gracias/Primera_vez_en_Google_Play.jpg",
		"res://assets/Gracias/Primeros_Logros.jpg"
	]
	
	var messages_es = [
		"¡Mil gracias! Al ver este anuncio, me ayudas directamente a pagar el servidor y seguir dedicándole tiempo a mejorar Sandbox Ultra. Eres parte de este sueño. ❤️",
		"Cada anuncio que decides ver voluntariamente es un impulso enorme para este proyecto. Gracias por valorar mi trabajo. ¡Gracias jugador! 🎮",
		"¡Gracias por el apoyo! No solo estás viendo un anuncio, estás ayudando a que Sandbox Ultra sea cada vez más grande. ¡Es genial tenerte en esta aventura, gracias! ✨",
		"De verdad, gracias. Sé que los anuncios pueden ser molestos, pero que elijas ver este voluntariamente significa mucho para mí. ¡Gracias por creer en este proyecto! 🚀",
		"¡Gracias! Gracias a este apoyo, podré traer más elementos, experimentos, caos y nuevas funciones pronto. Eres el motor detrás de las actualizaciones. 🙌",
		"Gracias por el apoyo. Tu granito de arena hace posible que siga desarrollando este juego con toda la energía. ¡Disfruta el juego! ❤️"
	]
	
	var messages_en = [
		"A thousand thanks! By watching this ad, you directly help me pay for the server and continue dedicating time to improve Sandbox Ultra. You are part of this dream. ❤️",
		"Every ad you decide to watch voluntarily is a huge boost for this project. Thank you for valuing my work. Thank you, player! 🎮",
		"Thanks for the support! You're not just watching an ad, you're helping Sandbox Ultra grow bigger and bigger. It's great to have you on this adventure, thank you! ✨",
		"Thank you, truly. I know ads can be annoying, but you choosing to watch this voluntarily means a lot to me. Thank you for believing in this project! 🚀",
		"Thank you! Thanks to this support, I will be able to bring more elements, experiments, chaos, and new features soon. You are the engine behind the updates. 🙌",
		"Thank you for the support. Your contribution makes it possible for me to keep developing this game with all my energy. Enjoy the game! ❤️"
	]
	
	var support_config = ConfigFile.new()
	var load_err = support_config.load("user://creator_support.cfg")
	
	var remaining_images = []
	var remaining_messages = []
	
	if load_err == OK:
		var saved_images = support_config.get_value("creator_support", "remaining_images", [])
		var saved_messages = support_config.get_value("creator_support", "remaining_messages", [])
		for val in saved_images:
			remaining_images.append(int(val))
		for val in saved_messages:
			remaining_messages.append(int(val))
			
	if remaining_images.size() == 0:
		remaining_images = [0, 1, 2, 3, 4, 5]
		remaining_images.shuffle()
	if remaining_messages.size() == 0:
		remaining_messages = [0, 1, 2, 3, 4, 5]
		remaining_messages.shuffle()
		
	var img_idx = remaining_images.pop_back()
	var msg_idx = remaining_messages.pop_back()
	
	support_config.set_value("creator_support", "remaining_images", remaining_images)
	support_config.set_value("creator_support", "remaining_messages", remaining_messages)
	support_config.save("user://creator_support.cfg")
	
	var img_path = images[img_idx]
	var texture: Texture2D = null
	var aspect_ratio = 1.0
	
	var loaded_tex = load(img_path)
	if loaded_tex:
		var raw_img = loaded_tex.get_image()
		if raw_img:
			if not img_path.ends_with("Primera_Interfaz.jpg") and raw_img.get_width() > raw_img.get_height():
				raw_img.rotate_90(0)
			aspect_ratio = float(raw_img.get_width()) / float(raw_img.get_height())
			texture = ImageTexture.create_from_image(raw_img)
		else:
			texture = loaded_tex
			aspect_ratio = float(loaded_tex.get_width()) / float(loaded_tex.get_height())
		
	var is_portrait = screen_size.y > screen_size.x
	var max_img_h = 0.0
	if is_portrait:
		max_img_h = 320.0 * s if aspect_ratio < 1.0 else 200.0 * s
	else:
		max_img_h = 180.0 * s if aspect_ratio < 1.0 else 140.0 * s
			
	panel.custom_minimum_size = Vector2(min(screen_size.x * 0.9, 450 * s), 0)
	
	var title_lbl = Label.new()
	title_lbl.text = tr("THANKS_TITLE")
	title_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", int(26 * s))
	title_lbl.add_theme_color_override("font_color", Color("#D4AF37"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(min(screen_size.x * 0.8, 380 * s), 0)
	vbox.add_child(title_lbl)
	
	var aspect_container = AspectRatioContainer.new()
	aspect_container.ratio = aspect_ratio
	aspect_container.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect_container.custom_minimum_size = Vector2(max_img_h * aspect_ratio, max_img_h)
	aspect_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(aspect_container)
	
	var tex_rect = TextureRect.new()
	tex_rect.texture = texture
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	aspect_container.add_child(tex_rect)
	
	tex_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	tex_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tex_rect.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_play_action_sound("ui_click")
			show_fullscreen_image(texture, aspect_ratio)
	)
	
	var img_keys = [
		"THANKS_IMG_TRAILER",
		"THANKS_IMG_PHOTO",
		"THANKS_IMG_INTERFACE",
		"THANKS_IMG_MUSIC",
		"THANKS_IMG_GOOGLE_PLAY",
		"THANKS_IMG_ACHIEVEMENTS"
	]
	
	var caption_lbl = Label.new()
	caption_lbl.text = tr(img_keys[img_idx])
	caption_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	caption_lbl.add_theme_font_size_override("font_size", int(17 * s))
	caption_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	caption_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_lbl.custom_minimum_size = Vector2(min(screen_size.x * 0.8, 380 * s), 0)
	vbox.add_child(caption_lbl)
	
	var legend_lbl = Label.new()
	var is_es = true
	if is_instance_valid(grid) and "current_language" in grid:
		is_es = grid.current_language.begins_with("es")
	elif TranslationServer.get_locale().begins_with("es"):
		is_es = true
	else:
		is_es = false
		
	var selected_messages = messages_es if is_es else messages_en
	legend_lbl.text = selected_messages[msg_idx]
	legend_lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	legend_lbl.add_theme_font_size_override("font_size", int(21 * s))
	legend_lbl.add_theme_color_override("font_color", Color("#D4AF37"))
	legend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_lbl.custom_minimum_size = Vector2(min(screen_size.x * 0.8, 400 * s), 0)
	vbox.add_child(legend_lbl)
	
	var back_btn = Button.new()
	back_btn.text = tr("Volver a Sandbox Ultra")
	back_btn.custom_minimum_size = Vector2(200 * s, 50 * s)
	back_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	back_btn.add_theme_font_size_override("font_size", int(22 * s))
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.45, 0.22, 0.9)
	btn_style.border_width_left = 2; btn_style.border_width_top = 2
	btn_style.border_width_right = 2; btn_style.border_width_bottom = 2
	btn_style.border_color = Color(0.3, 0.7, 0.4)
	btn_style.corner_radius_top_left = int(12 * s); btn_style.corner_radius_top_right = int(12 * s)
	btn_style.corner_radius_bottom_left = int(12 * s); btn_style.corner_radius_bottom_right = int(12 * s)
	
	back_btn.add_theme_stylebox_override("normal", btn_style)
	back_btn.add_theme_stylebox_override("hover", btn_style)
	back_btn.add_theme_stylebox_override("pressed", btn_style)
	back_btn.add_theme_color_override("font_color", Color.WHITE)
	
	back_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
		
		if is_instance_valid(grid):
			grid.is_paused = prev_paused
			var p_btn = grid.ui_elements.get("pause_btn") if "ui_elements" in grid else null
			if is_instance_valid(p_btn):
				p_btn.text = tr("play") if grid.is_paused else tr("pause")
				
			var players = [
				grid.get("weather_player"), grid.get("quake_player"), grid.get("tornado_player"),
				grid.get("tsunami_player"), grid.get("firework_player"), grid.get("ascent_player"),
				grid.get("volcano_loop_player"), grid.get("fire_loop_player"), grid.get("bombardero_player")
			]
			for p in players:
				if is_instance_valid(p) and p is AudioStreamPlayer:
					p.stream_paused = grid.is_paused
	)
	vbox.add_child(back_btn)


# =========================================================================
# 9. VISOR DE IMÁGENES A PANTALLA COMPLETA
# =========================================================================

func show_fullscreen_image(tex: Texture2D, ratio: float) -> void:
	var s = _get_ui_scale()
	var v_size = _get_viewport_rect().size
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return
	
	var zoom_overlay = Control.new()
	zoom_overlay.name = "ZoomOverlay"
	zoom_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(zoom_overlay)
	
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom_overlay.add_child(bg)
	
	var center_vbox = VBoxContainer.new()
	center_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.add_theme_constant_override("separation", int(20 * s))
	zoom_overlay.add_child(center_vbox)
	
	var max_w = v_size.x * 0.95
	var max_h = v_size.y * 0.8
	
	var fit_w = max_w
	var fit_h = fit_w / ratio
	if fit_h > max_h:
		fit_h = max_h
		fit_w = fit_h * ratio
		
	var aspect_container = AspectRatioContainer.new()
	aspect_container.ratio = ratio
	aspect_container.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect_container.custom_minimum_size = Vector2(fit_w, fit_h)
	aspect_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_vbox.add_child(aspect_container)
	
	var tex_rect = TextureRect.new()
	tex_rect.texture = tex
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	aspect_container.add_child(tex_rect)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(60 * s, 60 * s)
	close_btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	close_btn.add_theme_font_size_override("font_size", int(28 * s))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var x_style = StyleBoxFlat.new()
	x_style.bg_color = Color(0.25, 0.25, 0.3, 0.85)
	x_style.border_width_left = int(2 * s); x_style.border_width_top = int(2 * s)
	x_style.border_width_right = int(2 * s); x_style.border_width_bottom = int(2 * s)
	x_style.border_color = Color(0.83, 0.69, 0.22)
	x_style.set_corner_radius_all(int(30 * s))
	
	close_btn.add_theme_stylebox_override("normal", x_style)
	close_btn.add_theme_stylebox_override("hover", x_style)
	close_btn.add_theme_stylebox_override("pressed", x_style)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	
	close_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		zoom_overlay.queue_free()
	)
	center_vbox.add_child(close_btn)
	
	zoom_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_play_action_sound("ui_click")
			zoom_overlay.queue_free()
	)


# =========================================================================
# 10. BURBUJA FLOTANTE INFORMATIVA CENTRADA
# =========================================================================

func show_centered_bubble(msg: String, border_color: Color) -> void:
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root):
		return
		
	var bubble = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	p_style.set_corner_radius_all(int(18 * s))
	p_style.border_width_left = int(3 * s)
	p_style.border_width_top = int(3 * s)
	p_style.border_width_right = int(3 * s)
	p_style.border_width_bottom = int(3 * s)
	p_style.border_color = border_color
	p_style.shadow_color = Color(0, 0, 0, 0.45)
	p_style.shadow_size = 10
	bubble.add_theme_stylebox_override("panel", p_style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(16 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_bottom", int(16 * s))
	bubble.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(15 * s))
	margin.add_child(vbox)
	
	var lbl = Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(280 * s, 0)
	lbl.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	lbl.add_theme_font_size_override("font_size", int(20 * s))
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.text = tr("GOT_IT")
	btn.custom_minimum_size = Vector2(130 * s, 46 * s)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", SandboxFontHelper.get_safe_font())
	btn.add_theme_font_size_override("font_size", int(18 * s))
	var btn_style_norm = StyleBoxFlat.new()
	btn_style_norm.bg_color = border_color
	btn_style_norm.set_corner_radius_all(int(10 * s))
	var btn_style_hover = btn_style_norm.duplicate()
	btn_style_hover.bg_color = border_color.lightened(0.15)
	btn.add_theme_stylebox_override("normal", btn_style_norm)
	btn.add_theme_stylebox_override("hover", btn_style_hover)
	btn.add_theme_stylebox_override("pressed", btn_style_norm)
	btn.add_theme_color_override("font_color", Color.WHITE)
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(bubble)
	
	btn.pressed.connect(func():
		_play_action_sound("ui_click")
		center.queue_free()
	)
	vbox.add_child(btn)
	ui_root.add_child(center)
