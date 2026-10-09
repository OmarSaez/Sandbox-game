class_name SandboxLabUI
extends Node

## Módulo 3: SandboxLabUI
## Gestiona la interfaz del Laboratorio de Materiales Experimentales (IDs 900, 901, 902).
## Permite diseñar materiales personalizados (estados físicos, gravedades, reacciones y colores),
## sincroniza la textura de 2048x3 (palette_tex) para los shaders y gestiona el desbloqueo temporal por AdMob.

# Referencia al nodo principal
var grid: Node = null

# Estado del panel visual
var lab_panel: PanelContainer = null
var lab_selected_slot: int = 0
var lab_custom_data = [
	{"c1": Color(0, 0, 0, 0), "c2": Color(0, 0, 0, 0), "c3": Color(0, 0, 0, 0), "mix": 1, "grav": 1, "state": 3, "tags": {}, "name": ""},
	{"c1": Color(0, 0, 0, 0), "c2": Color(0, 0, 0, 0), "c3": Color(0, 0, 0, 0), "mix": 1, "grav": 1, "state": 3, "tags": {}, "name": ""},
	{"c1": Color(0, 0, 0, 0), "c2": Color(0, 0, 0, 0), "c3": Color(0, 0, 0, 0), "mix": 1, "grav": 1, "state": 3, "tags": {}, "name": ""}
]

# Control de desbloqueo y economía AdMob
var is_lab_unlocked: bool = false
var lab_unlock_expiry_unix: int = 0

# Tutorial interactivo del laboratorio
var is_lab_tutorial_done: bool = false
var lab_tutorial_step: int = 0 # 0: None, 1: Slots, 2: Colors, 3: Gravity, 4: State, 5: Tags, 6: HUD slot
var tutorial_rects: Array[Control] = []


func setup(p_grid: Node) -> void:
	grid = p_grid
	connect_admob_signals()


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


func _get_lut_rand() -> float:
	if is_instance_valid(grid) and grid.has_method("_get_lut_rand"):
		return grid._get_lut_rand()
	return randf()


func _unlock_achievement(id: String) -> void:
	if is_instance_valid(grid) and grid.has_method("_unlock_achievement"):
		grid._unlock_achievement(id)
	elif is_instance_valid(grid) and "achievement_manager" in grid and is_instance_valid(grid.achievement_manager):
		grid.achievement_manager.unlock_achievement(id)


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


func _toggle_category_panel(target_panel: Control) -> void:
	if is_instance_valid(grid) and grid.has_method("_toggle_category_panel"):
		grid._toggle_category_panel(target_panel)


# =========================================================================
# GESTIÓN DE SEÑALES ADMOB
# =========================================================================

func connect_admob_signals() -> void:
	var admob = get_node_or_null("/root/AdMobManager")
	if is_instance_valid(admob) and admob.has_signal("lab_unlocked"):
		if not admob.lab_unlocked.is_connected(on_admob_lab_unlocked):
			admob.lab_unlocked.connect(on_admob_lab_unlocked)


func on_admob_lab_unlocked() -> void:
	_play_action_sound("ui_click")
	var now = int(Time.get_unix_time_from_system())
	lab_unlock_expiry_unix = now + (12 * 3600)
	set_lab_unlocked(true)
	save_lab_state()
	
	# TUTORIAL CAUGHT: Si acaban de desbloquear y el panel está abierto, iniciar tutorial
	if not is_lab_tutorial_done and is_instance_valid(lab_panel) and lab_panel.visible:
		lab_tutorial_step = 1
		lab_custom_data[0]["grav"] = -1
		lab_custom_data[0]["state"] = -1
		update_lab_inspector()
		update_lab_tutorial_highlight()


# =========================================================================
# CONSTRUCCIÓN DE LA INTERFAZ DE USUARIO (LabPanel)
# =========================================================================

func setup_lab_ui() -> void:
	if not is_instance_valid(grid): return
	var s = _get_ui_scale()
	var ui_root = _get_ui_root()
	if not is_instance_valid(ui_root): return

	var lab_btn = grid._create_vertical_category_btn("🧪", "lab")
	lab_btn.name = "LabBtn"
	grid.ui_elements["lab_btn"] = lab_btn
	lab_btn.add_theme_font_override("font", _get_safe_font())
	lab_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	lab_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.action_hbox.add_child(lab_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.18, 0.15, 0.22, 1.0)
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.3, 0.5)
	lab_btn.add_theme_stylebox_override("normal", btn_style)
	lab_btn.add_theme_stylebox_override("hover", btn_style)
	lab_btn.add_theme_stylebox_override("pressed", btn_style)
	lab_btn.set_meta("base_style", btn_style)
	
	lab_panel = PanelContainer.new()
	lab_panel.name = "LabPanel"
	ui_root.add_child(lab_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.12, 0.2, 0.95)
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.3, 0.5)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	lab_panel.add_theme_stylebox_override("panel", panel_style)
	
	lab_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_align_panel_to_hud(lab_panel, 530 * s, 650 * s)
	lab_panel.visible = ui_root.get_meta("lab_v", false)
	
	for child in lab_panel.get_children(): 
		if is_instance_valid(child): child.free()
		
	var scroll = ScrollContainer.new()
	scroll.name = "LabScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 25
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.ui_elements["lab_scroll"] = scroll
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	lab_panel.add_child(main_vbox)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_theme_constant_override("separation", 20 * s)
	main_vbox.add_child(top_hbox)
	
	var title_lbl = Label.new()
	title_lbl.text = tr("lab")
	title_lbl.add_theme_font_override("font", _get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", 34 * s)
	grid.ui_elements["lab_panel_title"] = title_lbl
	top_hbox.add_child(title_lbl)
	
	var time_lbl = Label.new()
	time_lbl.text = "Tiempo: 12:00:00"
	time_lbl.add_theme_font_override("font", _get_safe_font())
	time_lbl.add_theme_font_size_override("font_size", 20 * s)
	time_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	grid.ui_elements["lab_time_lbl"] = time_lbl
	top_hbox.add_child(time_lbl)
	
	main_vbox.add_child(scroll)
	
	# BLOQUEADOR DE ANUNCIOS (OVERLAY)
	var lab_overlay = PanelContainer.new()
	var lab_overlay_style = StyleBoxFlat.new()
	lab_overlay_style.bg_color = Color(0.05, 0.05, 0.08, 0.90) # Oscuro
	lab_overlay_style.corner_radius_top_left = 12 * s
	lab_overlay_style.corner_radius_top_right = 12 * s
	lab_overlay_style.corner_radius_bottom_left = 12 * s
	lab_overlay_style.corner_radius_bottom_right = 12 * s
	lab_overlay.add_theme_stylebox_override("panel", lab_overlay_style)
	lab_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var overlay_vbox = VBoxContainer.new()
	overlay_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_vbox.add_theme_constant_override("separation", 35 * s)
	lab_overlay.add_child(overlay_vbox)
	
	var title_overlay = Label.new()
	title_overlay.text = tr("lab_overlay_title")
	title_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_overlay.add_theme_font_override("font", _get_safe_font())
	title_overlay.add_theme_font_size_override("font_size", 34 * s)
	title_overlay.add_theme_color_override("font_color", Color.YELLOW)
	grid.ui_elements["lab_overlay_title"] = title_overlay
	
	var desc_overlay = Label.new()
	desc_overlay.text = tr("lab_overlay_desc")
	desc_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_overlay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_overlay.add_theme_font_override("font", _get_safe_font())
	desc_overlay.add_theme_font_size_override("font_size", 25 * s)
	desc_overlay.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	grid.ui_elements["lab_overlay_desc"] = desc_overlay
	
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 25 * s)
	text_vbox.add_child(title_overlay)
	text_vbox.add_child(desc_overlay)
	
	var m_cont = MarginContainer.new()
	m_cont.add_theme_constant_override("margin_left", 30 * s)
	m_cont.add_theme_constant_override("margin_right", 30 * s)
	m_cont.add_child(text_vbox)
	overlay_vbox.add_child(m_cont)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 30 * s)
	overlay_vbox.add_child(btn_hbox)
	
	var no_btn = Button.new()
	no_btn.text = tr("not_now")
	no_btn.custom_minimum_size = Vector2(200 * s, 60 * s)
	no_btn.add_theme_font_override("font", _get_safe_font())
	no_btn.add_theme_font_size_override("font_size", 22 * s)
	no_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.ui_elements["not_now_btn"] = no_btn
	var no_st = StyleBoxFlat.new()
	no_st.bg_color = Color(0.2, 0.2, 0.25)
	no_st.corner_radius_top_left = 12 * s; no_st.corner_radius_top_right = 12 * s
	no_st.corner_radius_bottom_left = 12 * s; no_st.corner_radius_bottom_right = 12 * s
	no_btn.add_theme_stylebox_override("normal", no_st)
	no_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		if is_instance_valid(lab_panel) and lab_panel.visible: lab_panel.visible = false
	)
	btn_hbox.add_child(no_btn)
	
	var ad_btn = Button.new()
	ad_btn.text = tr("watch_ad")
	ad_btn.custom_minimum_size = Vector2(220 * s, 60 * s)
	ad_btn.add_theme_font_override("font", _get_safe_font())
	ad_btn.add_theme_font_size_override("font_size", 22 * s)
	ad_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.ui_elements["watch_ad_btn"] = ad_btn
	var ad_st = StyleBoxFlat.new()
	ad_st.bg_color = Color(0.1, 0.5, 0.2)
	ad_st.corner_radius_top_left = 12 * s; ad_st.corner_radius_top_right = 12 * s
	ad_st.corner_radius_bottom_left = 12 * s; ad_st.corner_radius_bottom_right = 12 * s
	ad_btn.add_theme_stylebox_override("normal", ad_st)
	ad_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		var admob_node = get_node_or_null("/root/AdMobManager")
		if is_instance_valid(admob_node) and admob_node.has_method("show_lab_rewarded"):
			await admob_node.show_lab_rewarded()
	)
	btn_hbox.add_child(ad_btn)
	
	grid.ui_elements["lab_overlay"] = lab_overlay
	lab_panel.add_child(lab_overlay)
	
	# Sincronizar visibilidad inicial del bloqueo
	lab_overlay.visible = !is_lab_unlocked
	
	lab_btn.pressed.connect(func(): 
		_toggle_category_panel(lab_panel)
		if is_instance_valid(lab_panel) and lab_panel.visible:
			if not is_lab_tutorial_done and is_lab_unlocked:
				lab_tutorial_step = 1
				lab_custom_data[0]["grav"] = -1
				lab_custom_data[0]["state"] = -1
				update_lab_inspector()
				update_lab_tutorial_highlight()
		else:
			if lab_tutorial_step == 5: lab_tutorial_step = 6
			else: lab_tutorial_step = 0
			update_lab_tutorial_highlight()
	)
	
	lab_panel.mouse_entered.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = true)
	lab_panel.mouse_exited.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = false)
	
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	var slots_hbox = HBoxContainer.new()
	slots_hbox.name = "LabSlotsHBox"
	slots_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_hbox.add_theme_constant_override("separation", 60 * s)
	v_box.add_child(slots_hbox)
	grid.ui_elements["lab_slots_hbox"] = slots_hbox
	
	grid.ui_elements["lab_slot_borders"] = []
	grid.ui_elements["lab_name_edits"] = []
	for i in range(3):
		var slot_vbox = VBoxContainer.new()
		slots_hbox.add_child(slot_vbox)
		
		var block_rect = TextureRect.new()
		block_rect.custom_minimum_size = Vector2(80 * s, 80 * s)
		block_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		block_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lab_custom_data[i]["node"] = block_rect
		
		var pnl = PanelContainer.new()
		var out_st = StyleBoxFlat.new()
		out_st.bg_color = Color(0, 0, 0, 1)
		out_st.border_width_left = 6; out_st.border_width_top = 6
		out_st.border_width_right = 6; out_st.border_width_bottom = 6
		out_st.border_color = Color(0.4, 0.4, 0.5)
		pnl.add_theme_stylebox_override("panel", out_st)
		
		var btn = Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(80 * s, 80 * s)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var stack = MarginContainer.new()
		stack.add_child(block_rect)
		stack.add_child(btn)
		
		pnl.add_child(stack)
		slot_vbox.add_child(pnl)
		grid.ui_elements["lab_slot_borders"].append(pnl)
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			lab_selected_slot = i
			if lab_tutorial_step == 1:
				lab_custom_data[i]["grav"] = -1
				lab_custom_data[i]["state"] = -1
			update_lab_inspector()
		)
		
		var name_edit = LineEdit.new()
		name_edit.placeholder_text = tr("LAB_NAME")
		name_edit.text = lab_custom_data[i]["name"]
		name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_edit.custom_minimum_size = Vector2(80 * s, 30 * s)
		name_edit.add_theme_font_override("font", _get_safe_font())
		name_edit.add_theme_font_size_override("font_size", 18 * s)
		name_edit.mouse_filter = Control.MOUSE_FILTER_PASS
		name_edit.text_changed.connect(func(new_text): 
			lab_custom_data[i]["name"] = new_text
			update_custom_mats_in_material_grid()
		)
		name_edit.focus_entered.connect(func():
			if lab_selected_slot != i:
				lab_selected_slot = i
				if lab_tutorial_step == 1:
					lab_custom_data[i]["grav"] = -1
					lab_custom_data[i]["state"] = -1
				update_lab_inspector()
		)
		name_edit.text_submitted.connect(func(_t):
			if lab_tutorial_step == 1:
				lab_tutorial_step = 2
				update_lab_tutorial_highlight()
		)
		name_edit.focus_exited.connect(func():
			if lab_tutorial_step == 1 and lab_custom_data[i]["name"].length() > 1:
				lab_tutorial_step = 2
				update_lab_tutorial_highlight()
		)
		slot_vbox.add_child(name_edit)
		grid.ui_elements["lab_name_edits"].append(name_edit)
	
	var make_h_line = func():
		var cr = ColorRect.new(); cr.custom_minimum_size = Vector2(0, 2 * s)
		cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cr.color = Color(0.4, 0.4, 0.5, 0.8)
		return cr
	var make_v_line = func():
		var cr = ColorRect.new(); cr.custom_minimum_size = Vector2(2 * s, 0)
		cr.size_flags_vertical = Control.SIZE_EXPAND_FILL; cr.color = Color(0.4, 0.4, 0.5, 0.8)
		return cr
		
	var sep1 = make_h_line.call()
	v_box.add_child(sep1)
	
	var columns_hbox = HBoxContainer.new()
	columns_hbox.add_theme_constant_override("separation", 15 * s)
	columns_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	v_box.add_child(columns_hbox)
	
	var col_color = VBoxContainer.new()
	var col_grav = VBoxContainer.new()
	var col_est = VBoxContainer.new()
	
	for col in [col_color, col_grav, col_est]:
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var col_color_title = Label.new()
	col_color_title.text = tr("LAB_COLOR")
	col_color_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_color.add_child(col_color_title)

	var col_grav_title = Label.new()
	col_grav_title.text = tr("LAB_GRAVITY")
	col_grav_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_grav.add_child(col_grav_title)
	
	var col_est_title = Label.new()
	col_est_title.text = tr("LAB_STATE")
	col_est_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col_est.add_child(col_est_title)

	columns_hbox.add_child(col_color)
	columns_hbox.add_child(make_v_line.call())
	columns_hbox.add_child(col_grav)
	columns_hbox.add_child(make_v_line.call())
	columns_hbox.add_child(col_est)
	
	grid.ui_elements["lab_col_color"] = col_color
	grid.ui_elements["lab_col_grav"] = col_grav
	grid.ui_elements["lab_col_est"] = col_est
	
	for l in [col_color_title, col_grav_title, col_est_title]:
		l.add_theme_font_override("font", _get_safe_font())
		l.add_theme_font_size_override("font_size", 20 * s)
		l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	
	grid.ui_elements["lab_col_pickers"] = []
	grid.ui_elements["lab_col_trash"] = []
	
	for i in range(3):
		var hb = HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 8 * s)
		col_color.add_child(hb)
		
		var num_lbl = Label.new()
		num_lbl.text = str(i + 1)
		num_lbl.add_theme_font_override("font", _get_safe_font())
		num_lbl.add_theme_font_size_override("font_size", 18 * s)
		num_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		hb.add_child(num_lbl)
		
		var cp = ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(40 * s, 40 * s)
		cp.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var null_overlay = Label.new()
		null_overlay.text = "/"
		null_overlay.add_theme_font_override("font", _get_safe_font())
		null_overlay.add_theme_font_size_override("font_size", 28 * s)
		null_overlay.add_theme_color_override("font_color", Color.RED)
		null_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		null_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		null_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		null_overlay.name = "NullOverlay"
		cp.add_child(null_overlay)
		cp.color_changed.connect(func(c):
			var prop = "c" + str(i + 1)
			lab_custom_data[lab_selected_slot][prop] = c
			update_lab_preview(lab_selected_slot)
			update_lab_inspector()
		)
		cp.get_popup().popup_hide.connect(func():
			if lab_tutorial_step == 2:
				var data = lab_custom_data[lab_selected_slot]
				if data["c1"].a > 0.0 or data["c2"].a > 0.0 or data["c3"].a > 0.0:
					lab_tutorial_step = 3
					update_lab_tutorial_highlight()
		)
		hb.add_child(cp)
		grid.ui_elements["lab_col_pickers"].append(cp)
		
		var trash = Button.new()
		trash.text = "🗑️"
		trash.add_theme_font_override("font", _get_safe_font())
		trash.add_theme_font_size_override("font_size", 20 * s)
		trash.custom_minimum_size = Vector2(25 * s, 30 * s)
		trash.mouse_filter = Control.MOUSE_FILTER_PASS
		trash.pressed.connect(func():
			_play_action_sound("ui_click")
			var prop = "c" + str(i + 1)
			lab_custom_data[lab_selected_slot][prop] = Color(0, 0, 0, 0)
			update_lab_preview(lab_selected_slot)
			
			if lab_tutorial_step > 2:
				var data = lab_custom_data[lab_selected_slot]
				if data["c1"].a == 0.0 and data["c2"].a == 0.0 and data["c3"].a == 0.0:
					lab_tutorial_step = 2
					update_lab_tutorial_highlight()
			
			update_lab_inspector()
		)
		hb.add_child(trash)
		grid.ui_elements["lab_col_trash"].append(trash)
	
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10 * s
	col_color.add_child(spacer)
		
	var tex_lbl = Label.new()
	tex_lbl.text = tr("LAB_TEXTURE")
	tex_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tex_lbl.add_theme_font_size_override("font_size", 16 * s)
	col_color.add_child(tex_lbl)
	
	var mix_slider = HSlider.new()
	mix_slider.mouse_filter = Control.MOUSE_FILTER_PASS
	mix_slider.min_value = 0
	mix_slider.max_value = 2
	mix_slider.step = 1
	mix_slider.tick_count = 3
	mix_slider.value_changed.connect(func(v):
		lab_custom_data[lab_selected_slot]["mix"] = v
		update_lab_preview(lab_selected_slot)
	)
	col_color.add_child(mix_slider)
	grid.ui_elements["lab_mix_slider"] = mix_slider
		
	grid.ui_elements["lab_grav_buttons"] = []
	var grav_options = ["GRAV_SLOW", "GRAV_NORMAL", "GRAV_UP", "GRAV_STATIC"]
	for j in range(grav_options.size()):
		var btn = Button.new()
		btn.text = tr(grav_options[j])
		btn.toggle_mode = true
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 22 * s)
		var st_n = StyleBoxFlat.new()
		st_n.bg_color = Color(0.15, 0.15, 0.2)
		st_n.border_width_left = 1; st_n.border_width_right = 1; st_n.border_width_top = 1; st_n.border_width_bottom = 1
		st_n.border_color = Color(0.3, 0.3, 0.4)
		st_n.corner_radius_top_left = 6 * s; st_n.corner_radius_top_right = 6 * s
		st_n.corner_radius_bottom_left = 6 * s; st_n.corner_radius_bottom_right = 6 * s
		st_n.content_margin_top = 6 * s; st_n.content_margin_bottom = 6 * s
		btn.add_theme_stylebox_override("normal", st_n)
		var st_p = StyleBoxFlat.new()
		st_p.bg_color = Color(0.2, 0.5, 1.0)
		st_p.corner_radius_top_left = 6 * s; st_p.corner_radius_top_right = 6 * s
		st_p.corner_radius_bottom_left = 6 * s; st_p.corner_radius_bottom_right = 6 * s
		st_p.content_margin_top = 6 * s; st_p.content_margin_bottom = 6 * s
		btn.add_theme_stylebox_override("pressed", st_p)
		btn.toggled.connect(func(pressed):
			if pressed:
				_play_action_sound("ui_click")
				lab_custom_data[lab_selected_slot]["grav"] = j
				update_lab_inspector()
				if lab_tutorial_step == 3:
					lab_tutorial_step = 4
					update_lab_tutorial_highlight()
		)
		col_grav.add_child(btn)
		grid.ui_elements["lab_grav_buttons"].append(btn)
		
	grid.ui_elements["lab_est_buttons"] = []
	var est_options = ["STATE_GAS", "STATE_LIQUID", "STATE_POWDER", "STATE_SOLID"]
	for j in range(est_options.size()):
		var btn = Button.new()
		btn.text = tr(est_options[j])
		btn.toggle_mode = true
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 22 * s)
		var st_n = StyleBoxFlat.new()
		st_n.bg_color = Color(0.15, 0.15, 0.2)
		st_n.border_width_left = 1; st_n.border_width_right = 1; st_n.border_width_top = 1; st_n.border_width_bottom = 1
		st_n.border_color = Color(0.3, 0.3, 0.4)
		st_n.corner_radius_top_left = 6 * s; st_n.corner_radius_top_right = 6 * s
		st_n.corner_radius_bottom_left = 6 * s; st_n.corner_radius_bottom_right = 6 * s
		st_n.content_margin_top = 6 * s; st_n.content_margin_bottom = 6 * s
		btn.add_theme_stylebox_override("normal", st_n)
		var st_p = StyleBoxFlat.new()
		st_p.bg_color = Color(0.2, 0.5, 1.0)
		st_p.corner_radius_top_left = 6 * s; st_p.corner_radius_top_right = 6 * s
		st_p.corner_radius_bottom_left = 6 * s; st_p.corner_radius_bottom_right = 6 * s
		st_p.content_margin_top = 6 * s; st_p.content_margin_bottom = 6 * s
		btn.add_theme_stylebox_override("pressed", st_p)
		btn.toggled.connect(func(pressed):
			if pressed:
				_play_action_sound("ui_click")
				lab_custom_data[lab_selected_slot]["state"] = j
				update_lab_inspector()
				if lab_tutorial_step == 4:
					lab_tutorial_step = 5
					update_lab_tutorial_highlight()
		)
		col_est.add_child(btn)
		grid.ui_elements["lab_est_buttons"].append(btn)
	
	var tags_sep = make_h_line.call()
	v_box.add_child(tags_sep)
	
	var car_title = Label.new()
	car_title.text = tr("LAB_CHARACTERISTICS")
	car_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_title.add_theme_font_override("font", _get_safe_font())
	car_title.add_theme_font_size_override("font_size", 20 * s)
	v_box.add_child(car_title)
	grid.ui_elements["lab_car_title"] = car_title
	
	var tags_main_vbox = VBoxContainer.new()
	v_box.add_child(tags_main_vbox)
	grid.ui_elements["lab_tags_vbox"] = tags_main_vbox
	
	# --- SECCIÓN DE CARACTERÍSTICAS DINÁMICA ---
	var tag_sections = [
		{
			"id": "interaction",
			"name": tr("interaction_tags"),
			"tags": ["FLAMMABLE", "INCENDIARY", "EXPLOSIVE", "ANTI_EXPLOSIVE", "VIRUS", "INVINCIBLE", "VORTEX", "REPEL"]
		},
		{
			"id": "exp_special",
			"name": tr("exp_special"),
			"parent": "EXPLOSIVE",
			"tags": ["EXP_ELECTRIC", "EXP_ACID", "EXP_WATER", "EXP_LAVA", "EXP_NPC", "EXP_LIFE", "EXP_GAS", "EXP_QUAKE", "EXP_PINATA"]
		},
		{
			"id": "exp_npc_team",
			"name": tr("exp_npc_team"),
			"parent": "EXP_NPC",
			"radio": true,
			"tags": ["EXP_TEAM_RED", "EXP_TEAM_BLUE", "EXP_TEAM_GREEN", "EXP_TEAM_YELLOW", "EXP_TEAM_MIXED"]
		},
		{
			"id": "combustion",
			"name": tr("combustion"),
			"parent": "FLAMMABLE",
			"radio": true,
			"tags": ["BURN_SMOKE", "BURN_COAL"]
		},
		{
			"id": "electricity",
			"name": tr("electricity"),
			"tags": ["ELECTRICITY", "CONDUCTOR", "ELECTRIC_ACTIVATED", "RADIOACTIVE"]
		},
		{
			"id": "corrosion",
			"name": tr("corrosion"),
			"tags": ["ACID", "ANTI_ACID"]
		}
	]
	
	grid.ui_elements["lab_tag_buttons"] = {}
	grid.ui_elements["lab_tag_sections"] = {}
	
	for section in tag_sections:
		var sec_vbox = VBoxContainer.new()
		grid.ui_elements["lab_tag_sections"][section["id"]] = sec_vbox
		tags_main_vbox.add_child(sec_vbox)
		
		var cat_lbl = Label.new()
		cat_lbl.text = section["name"]
		cat_lbl.add_theme_font_override("font", _get_safe_font())
		cat_lbl.add_theme_font_size_override("font_size", 22 * s)
		cat_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		sec_vbox.add_child(cat_lbl)
		
		var flow = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10 * s)
		flow.add_theme_constant_override("v_separation", 10 * s)
		sec_vbox.add_child(flow)
		
		for tag in section["tags"]:
			var tb = Button.new()
			tb.text = tag
			tb.toggle_mode = true
			tb.add_theme_font_override("font", _get_safe_font())
			tb.add_theme_font_size_override("font_size", 20 * s)
			tb.mouse_filter = Control.MOUSE_FILTER_PASS
			
			var st_n = StyleBoxFlat.new()
			st_n.bg_color = Color(0.15, 0.15, 0.22)
			st_n.border_width_left = 2; st_n.border_width_top = 2; st_n.border_width_right = 2; st_n.border_width_bottom = 2
			st_n.border_color = Color(0.3, 0.3, 0.4)
			st_n.corner_radius_top_left = 12 * s; st_n.corner_radius_top_right = 12 * s
			st_n.corner_radius_bottom_left = 12 * s; st_n.corner_radius_bottom_right = 12 * s
			st_n.content_margin_left = 16 * s; st_n.content_margin_right = 16 * s
			st_n.content_margin_top = 10 * s; st_n.content_margin_bottom = 10 * s
			tb.add_theme_stylebox_override("normal", st_n)
			
			var st_p = StyleBoxFlat.new()
			st_p.bg_color = Color(0.2, 0.55, 0.3)
			st_p.border_width_left = 2; st_p.border_width_top = 2; st_p.border_width_right = 2; st_p.border_width_bottom = 2
			st_p.border_color = Color(0.3, 0.8, 0.5)
			st_p.corner_radius_top_left = 12 * s; st_p.corner_radius_top_right = 12 * s
			st_p.corner_radius_bottom_left = 12 * s; st_p.corner_radius_bottom_right = 12 * s
			st_p.content_margin_left = 16 * s; st_p.content_margin_right = 16 * s
			st_p.content_margin_top = 10 * s; st_p.content_margin_bottom = 10 * s
			tb.add_theme_stylebox_override("pressed", st_p)
			
			tb.toggled.connect(func(pressed):
				_play_action_sound("ui_click")
				var current_data = lab_custom_data[lab_selected_slot]
				
				if pressed:
					if section.get("radio", false):
						for other_tag in section["tags"]:
							if other_tag != tag: current_data["tags"].erase(other_tag)
					current_data["tags"][tag] = true
				else:
					current_data["tags"].erase(tag)
				
				update_lab_inspector()
				if lab_tutorial_step == 5:
					if is_instance_valid(lab_panel): lab_panel.visible = false
					lab_tutorial_step = 6
					update_lab_tutorial_highlight()
			)
			flow.add_child(tb)
			grid.ui_elements["lab_tag_buttons"][tag] = tb


# =========================================================================
# TUTORIAL DESTACADO (HIGHLIGHT CUTOUT)
# =========================================================================

func update_lab_tutorial_highlight() -> void:
	for r in tutorial_rects:
		if is_instance_valid(r): r.queue_free()
	tutorial_rects.clear()
	
	if lab_tutorial_step == 0: return
	if not is_instance_valid(grid): return
	
	var target: Control = null
	match lab_tutorial_step:
		1: 
			var name_edits = grid.ui_elements.get("lab_name_edits", [])
			if name_edits.size() > lab_selected_slot:
				target = name_edits[lab_selected_slot]
			else:
				target = grid.ui_elements.get("lab_slots_hbox")
		2: target = grid.ui_elements.get("lab_col_color")
		3: target = grid.ui_elements.get("lab_col_grav")
		4: target = grid.ui_elements.get("lab_col_est")
		5: target = grid.ui_elements.get("lab_tags_vbox")
		6: 
			var hud_slots = grid.ui_elements.get("lab_custom_slots_hud", [])
			if hud_slots.size() > lab_selected_slot:
				target = hud_slots[lab_selected_slot]
			else:
				target = grid.ui_elements.get("lab_first_custom_slot")
	
	if not is_instance_valid(target): return
	
	if lab_tutorial_step == 6 and (not is_instance_valid(grid.tools_panel) or not grid.tools_panel.visible):
		if grid.has_method("_on_tools_btn_pressed"):
			grid._on_tools_btn_pressed()
	
	# Esperar un frame de proceso para sincronización GPU/layout
	await get_tree().process_frame
	if not is_instance_valid(target) or not target.is_inside_tree(): return
	
	var parent: Node = _get_ui_root()
	if not is_instance_valid(parent): return
	var tr_rect = target.get_global_rect()
	
	if lab_tutorial_step >= 1 and lab_tutorial_step <= 5 and is_instance_valid(lab_panel):
		if grid.ui_elements.has("lab_scroll") and is_instance_valid(grid.ui_elements["lab_scroll"]):
			grid.ui_elements["lab_scroll"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	elif grid.ui_elements.has("lab_scroll") and is_instance_valid(grid.ui_elements["lab_scroll"]):
		grid.ui_elements["lab_scroll"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		
	var screen_size = _get_viewport_rect().size
	var margin = 8 * _get_ui_scale()
	if lab_tutorial_step == 5: margin = 4 * _get_ui_scale()
	var cutout = tr_rect.grow(margin)
	
	if lab_tutorial_step >= 1 and lab_tutorial_step <= 5:
		var clip_rect = lab_panel.get_global_rect()
		if grid.ui_elements.has("lab_scroll") and is_instance_valid(grid.ui_elements["lab_scroll"]):
			clip_rect = grid.ui_elements["lab_scroll"].get_global_rect()
		cutout = cutout.intersection(clip_rect)
	
	var create_dim = func():
		var r = ColorRect.new()
		r.color = Color(0, 0, 0, 0.85)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		parent.add_child(r)
		tutorial_rects.append(r)
		return r
		
	# Area Top
	var top = create_dim.call()
	top.set_begin(Vector2(0, 0))
	top.set_end(Vector2(screen_size.x, cutout.position.y))
	
	# Area Bottom
	var bot = create_dim.call()
	bot.set_begin(Vector2(0, cutout.end.y))
	bot.set_end(Vector2(screen_size.x, screen_size.y))
	
	# Area Left
	var left = create_dim.call()
	left.set_begin(Vector2(0, cutout.position.y))
	left.set_end(Vector2(cutout.position.x, cutout.end.y))
	
	# Area Right
	var right = create_dim.call()
	right.set_begin(Vector2(cutout.end.x, cutout.position.y))
	right.set_end(Vector2(screen_size.x, cutout.end.y))

	# Icono animado del paso 1
	if lab_tutorial_step == 1:
		var s = _get_ui_scale()
		var icon = Label.new()
		icon.text = "✏️"
		icon.add_theme_font_size_override("font_size", 40 * s)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(cutout.position.x + cutout.size.x / 2.0 - 20 * s, cutout.position.y - 50 * s)
		parent.add_child(icon)
		tutorial_rects.append(icon)
		
		var tw = icon.create_tween()
		tw.tween_property(icon, "position:y", icon.position.y - 10 * s, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(icon, "position:y", icon.position.y, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.set_loops()


# =========================================================================
# PERSISTENCIA DEL ESTADO DEL LABORATORIO (user://lab_state.json)
# =========================================================================

func save_lab_state() -> void:
	var clean_data = []
	for d in lab_custom_data:
		var c = d.duplicate()
		c.erase("node")
		c["c1"] = c["c1"].to_html() if c["c1"] is Color else "00000000"
		c["c2"] = c["c2"].to_html() if c["c2"] is Color else "00000000"
		c["c3"] = c["c3"].to_html() if c["c3"] is Color else "00000000"
		clean_data.append(c)

	var save = {
		"expiry": lab_unlock_expiry_unix,
		"data": clean_data,
		"tutorial_done": is_lab_tutorial_done
	}
	var file = FileAccess.open("user://lab_state.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save))
		file.close()


func load_lab_state() -> void:
	if OS.has_feature("editor"):
		is_lab_unlocked = true
		lab_unlock_expiry_unix = int(Time.get_unix_time_from_system()) + 86400

	if FileAccess.file_exists("user://lab_state.json"):
		var file = FileAccess.open("user://lab_state.json", FileAccess.READ)
		if file:
			var json_str = file.get_as_text()
			file.close()
			
			var save = JSON.parse_string(json_str)
			if typeof(save) == TYPE_DICTIONARY:
				if not OS.has_feature("editor"):
					lab_unlock_expiry_unix = int(save.get("expiry", 0))
				is_lab_tutorial_done = save.get("tutorial_done", false)
				
				if save.has("data"):
					var loaded_data = save["data"]
					for i in range(min(loaded_data.size(), 3)):
						var d = loaded_data[i]
						for k in d.keys():
							if k == "c1" or k == "c2" or k == "c3":
								lab_custom_data[i][k] = Color(d[k])
							elif k != "node":
								lab_custom_data[i][k] = d[k]
	
	var now = int(Time.get_unix_time_from_system())
	if OS.has_feature("editor") or now < lab_unlock_expiry_unix:
		set_lab_unlocked(true)
	else:
		set_lab_unlocked(false)
		
	# Reaplicar definiciones al motor
	for i in range(3):
		apply_custom_material_to_engine(i)
	sync_palette_to_shader()


func set_lab_unlocked(unlocked: bool) -> void:
	is_lab_unlocked = unlocked
	if is_instance_valid(grid) and grid.ui_elements.has("lab_overlay") and is_instance_valid(grid.ui_elements["lab_overlay"]):
		grid.ui_elements["lab_overlay"].visible = !unlocked
	update_custom_mats_in_material_grid()


# =========================================================================
# MATERIAL GRID & SHADER SINCRONIZACIÓN
# =========================================================================

func update_custom_mats_in_material_grid() -> void:
	if not is_instance_valid(grid) or not is_instance_valid(grid.main_controls): return
	var mat_grid_node = grid.main_controls.find_child("MaterialGrid", true, false)
	if not is_instance_valid(mat_grid_node): return
	
	for c in mat_grid_node.get_children():
		if c.has_meta("is_custom"):
			mat_grid_node.remove_child(c)
			c.queue_free()
			
	if not is_lab_unlocked: 
		return
		
	var s = _get_ui_scale()
	var insert_idx = 0
	
	for i in range(3):
		var data = lab_custom_data[i]
		var has_color = data["c1"].a > 0.0 or data["c2"].a > 0.0 or data["c3"].a > 0.0
		if not has_color: continue
			
		var slot_pnl = PanelContainer.new()
		var slot_style = StyleBoxEmpty.new()
		slot_pnl.add_theme_stylebox_override("panel", slot_style)
		slot_pnl.mouse_filter = Control.MOUSE_FILTER_STOP
		slot_pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_pnl.custom_minimum_size = Vector2(110 * s, 85 * s) 
		slot_pnl.set_meta("is_custom", true)
		
		var main_vbox = VBoxContainer.new()
		main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		main_vbox.add_theme_constant_override("separation", 2 * s)
		main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		slot_pnl.add_child(main_vbox)
		
		var stack = Control.new()
		stack.custom_minimum_size = Vector2(90 * s, 46 * s)
		stack.mouse_filter = Control.MOUSE_FILTER_PASS
		main_vbox.add_child(stack)
		
		var icon_panel = PanelContainer.new()
		icon_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_panel.clip_children = Control.CLIP_CHILDREN_AND_DRAW
		
		var st = StyleBoxFlat.new()
		st.bg_color = data["c1"] if data["c1"].a > 0.0 else Color(0.1, 0.1, 0.1)
		var radius = int(8 * s)
		st.corner_radius_top_left = radius; st.corner_radius_top_right = radius
		st.corner_radius_bottom_left = radius; st.corner_radius_bottom_right = radius
		icon_panel.add_theme_stylebox_override("panel", st)
		
		if is_instance_valid(data.get("node")) and data["node"].texture:
			var tex_rect = TextureRect.new()
			tex_rect.texture = data["node"].texture
			tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon_panel.add_child(tex_rect)
			
		icon_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		stack.add_child(icon_panel)
		
		var selection_overlay = PanelContainer.new()
		selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selection_overlay.visible = false
		selection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(selection_overlay)
		
		var btn_lbl = Label.new()
		btn_lbl.name = "MatLabel"
		btn_lbl.text = (data["name"] if data["name"] != "" else "Mat " + str(i + 1))
		btn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		btn_lbl.add_theme_font_size_override("font_size", 18 * s)
		btn_lbl.add_theme_font_override("font", _get_safe_font())
		main_vbox.add_child(btn_lbl)
		
		var mat_id = 900 + i
		slot_pnl.gui_input.connect(func(event):
			if not is_instance_valid(event) or not is_instance_valid(slot_pnl): return
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_play_action_sound("ui_click")
				if is_instance_valid(grid):
					grid.selected_material = mat_id
					grid.is_paint_tool_active = false
					grid.is_mechanism_mode_active = false
					grid._update_material_highlights()
					grid._update_menu_highlights()
				
				if lab_tutorial_step == 6:
					is_lab_tutorial_done = true
					lab_tutorial_step = 0
					update_lab_tutorial_highlight()
					save_lab_state()
					_unlock_achievement("mad_scientist")
					
					if is_instance_valid(grid) and is_instance_valid(grid.tools_panel) and grid.tools_panel.visible:
						if grid.has_method("_on_tools_btn_pressed"):
							grid._on_tools_btn_pressed()
		)
		
		slot_pnl.set_meta("mat_id", mat_id)
		slot_pnl.set_meta("overlay", selection_overlay)
		slot_pnl.set_meta("label", btn_lbl)
		
		mat_grid_node.add_child(slot_pnl)
		mat_grid_node.move_child(slot_pnl, insert_idx)
		
		if not grid.ui_elements.has("lab_custom_slots_hud"): grid.ui_elements["lab_custom_slots_hud"] = [null, null, null]
		grid.ui_elements["lab_custom_slots_hud"][i] = slot_pnl
		
		if i == 0: grid.ui_elements["lab_first_custom_slot"] = slot_pnl
		insert_idx += 1
		
	if is_instance_valid(grid) and grid.has_method("_update_material_highlights"):
		grid._update_material_highlights()


func sync_palette_to_shader() -> void:
	if not is_instance_valid(grid): return
	var palette_img = Image.create(2048, 3, false, Image.FORMAT_RGBA8)
	palette_img.fill(Color(0, 0, 0, 0))
	for i in range(2048):
		palette_img.set_pixel(i, 0, grid.mat_colors_1[i])
		palette_img.set_pixel(i, 1, grid.mat_colors_2[i])
		palette_img.set_pixel(i, 2, grid.mat_colors_3[i])
	var palette_tex = ImageTexture.create_from_image(palette_img)
	if is_instance_valid(grid.texture_rect) and grid.texture_rect.material:
		grid.texture_rect.material.set_shader_parameter("palette_tex", palette_tex)


func apply_custom_material_to_engine(i: int) -> void:
	if i < 0 or i >= lab_custom_data.size(): return
	var data = lab_custom_data[i]
	var mat_id = 900 + i
	var tags_mask = 0
	
	if data["state"] == 0: tags_mask |= SandboxMaterial.Tags.GAS
	elif data["state"] == 1: tags_mask |= SandboxMaterial.Tags.LIQUID
	elif data["state"] == 2: tags_mask |= SandboxMaterial.Tags.POWDER
	elif data["state"] == 3: tags_mask |= SandboxMaterial.Tags.SOLID
	
	if data["grav"] == 0: tags_mask |= SandboxMaterial.Tags.GRAV_SLOW
	elif data["grav"] == 1: tags_mask |= SandboxMaterial.Tags.GRAV_NORMAL
	elif data["grav"] == 2: tags_mask |= SandboxMaterial.Tags.GRAV_UP
	elif data["grav"] == 3: tags_mask |= SandboxMaterial.Tags.GRAV_STATIC
	
	for tag_name in data["tags"]:
		if tag_name in SandboxMaterial.Tags:
			tags_mask |= SandboxMaterial.Tags[tag_name]
			
	var has_c2 = data["c2"].a > 0.0
	var has_c3 = data["c3"].a > 0.0
	
	if has_c2 and has_c3: tags_mask |= SandboxMaterial.Tags.TEXTURE_TRIPLE
	elif has_c2: tags_mask |= SandboxMaterial.Tags.TEXTURE_DOUBLE
		
	if data["mix"] == 0: tags_mask |= SandboxMaterial.Tags.MIX_LOW
	elif data["mix"] == 1: tags_mask |= SandboxMaterial.Tags.MIX_MEDIUM
	elif data["mix"] == 2: tags_mask |= SandboxMaterial.Tags.MIX_HIGH
	
	var c1 = data["c1"] if data["c1"].a > 0.0 else Color(1, 0, 1, 1)
	
	if is_instance_valid(grid) and grid.has_method("_register_material"):
		grid._register_material(mat_id, c1, tags_mask, data["c2"], data["c3"])


func update_lab_inspector() -> void:
	if not is_instance_valid(grid) or not grid.ui_elements.has("lab_col_pickers"): return
	
	var data = lab_custom_data[lab_selected_slot]
	
	# Actualizar bordes de slots
	if grid.ui_elements.has("lab_slot_borders"):
		for i in range(3):
			var pnl = grid.ui_elements["lab_slot_borders"][i]
			var st = pnl.get_theme_stylebox("panel")
			if i == lab_selected_slot:
				st.border_color = Color(0.2, 0.5, 1.0)
			else:
				st.border_color = Color(0.4, 0.4, 0.5)
				
	# Actualizar botones de gravedad
	if grid.ui_elements.has("lab_grav_buttons"):
		for j in range(4):
			var btn = grid.ui_elements["lab_grav_buttons"][j]
			btn.set_block_signals(true)
			btn.button_pressed = (data["grav"] == j)
			btn.set_block_signals(false)
			
	# Actualizar botones de estado
	if grid.ui_elements.has("lab_est_buttons"):
		for j in range(4):
			var btn = grid.ui_elements["lab_est_buttons"][j]
			btn.set_block_signals(true)
			btn.button_pressed = (data["state"] == j)
			btn.set_block_signals(false)
				
	# Actualizar etiquetas de tags y secciones dependientes
	if grid.ui_elements.has("lab_tag_buttons"):
		var current_tags = data["tags"]
		for tag in grid.ui_elements["lab_tag_buttons"]:
			var tb = grid.ui_elements["lab_tag_buttons"][tag]
			tb.set_block_signals(true)
			tb.button_pressed = current_tags.has(tag)
			tb.set_block_signals(false)
		
		if grid.ui_elements.has("lab_tag_sections"):
			var sections_node = grid.ui_elements["lab_tag_sections"]
			if sections_node.has("combustion"):
				var is_flammable = current_tags.has("FLAMMABLE")
				sections_node["combustion"].visible = is_flammable
				if not is_flammable:
					current_tags.erase("BURN_SMOKE")
					current_tags.erase("BURN_COAL")
					current_tags.erase("BURN_NONE")
			
			if sections_node.has("exp_special"):
				var is_explosive = current_tags.has("EXPLOSIVE")
				sections_node["exp_special"].visible = is_explosive
				if not is_explosive:
					current_tags.erase("EXP_ELECTRIC")
					current_tags.erase("EXP_ACID")
					current_tags.erase("EXP_WATER")
					current_tags.erase("EXP_LAVA")
					current_tags.erase("EXP_NPC")
					current_tags.erase("EXP_LIFE")
			
			if sections_node.has("exp_npc_team"):
				var is_npc_exp = current_tags.has("EXP_NPC")
				sections_node["exp_npc_team"].visible = is_npc_exp
				if not is_npc_exp:
					current_tags.erase("EXP_TEAM_RED")
					current_tags.erase("EXP_TEAM_BLUE")
					current_tags.erase("EXP_TEAM_GREEN")
					current_tags.erase("EXP_TEAM_YELLOW")
					current_tags.erase("EXP_TEAM_MIXED")
			
	for i in range(3):
		apply_custom_material_to_engine(i)
	sync_palette_to_shader()
		
	save_lab_state()
	update_custom_mats_in_material_grid()
	
	for i in range(3):
		var cp = grid.ui_elements["lab_col_pickers"][i]
		var tr_btn = grid.ui_elements["lab_col_trash"][i]
		var prop = "c" + str(i + 1)
		
		var is_null = data[prop].a == 0.0
		
		if is_null:
			cp.color = Color(0.2, 0.2, 0.2, 1.0)
			if cp.has_node("NullOverlay"): cp.get_node("NullOverlay").visible = true
			tr_btn.modulate = Color(1, 1, 1, 0)
			tr_btn.disabled = true
		else:
			cp.color = data[prop]
			if cp.has_node("NullOverlay"): cp.get_node("NullOverlay").visible = false
			tr_btn.modulate = Color(1, 1, 1, 1)
			tr_btn.disabled = false
			
		if i == 2 and data["c2"].a == 0.0:
			cp.disabled = true
			cp.color = Color(0.2, 0.2, 0.2)
		else:
			cp.disabled = false
			
	if grid.ui_elements.has("lab_mix_slider"):
		var mix_slider = grid.ui_elements["lab_mix_slider"]
		mix_slider.set_block_signals(true)
		mix_slider.value = data["mix"]
		mix_slider.set_block_signals(false)


func update_lab_preview(idx: int) -> void:
	if idx < 0 or idx >= lab_custom_data.size(): return
	var data = lab_custom_data[idx]
	if not data.has("node") or not is_instance_valid(data["node"]): return
	
	var tex_rect = data["node"]
	var s = _get_ui_scale()
	var tw = 128
	var th = 128
	
	var pixel_size = max(1, int(6 * s))
	var blocks_x = ceil(tw / float(pixel_size))
	var blocks_y = ceil(th / float(pixel_size))
	
	var preview_img = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	var c1 = data["c1"]
	var c2 = data["c2"]
	var c3 = data["c3"]
	
	var has_c2 = c2.a > 0.0
	var has_c3 = c3.a > 0.0
	var mix_val = data["mix"] 
	var mix_factor = 0.1
	if mix_val == 1: mix_factor = 0.25
	elif mix_val == 2: mix_factor = 0.44
	
	for y_block in range(blocks_y):
		for x_block in range(blocks_x):
			var val = _get_lut_rand()
			var p_color = c1
			
			if has_c2 and has_c3:
				if val < mix_factor: p_color = c2
				elif val < mix_factor * 2.0: p_color = c3
			elif has_c2:
				if val < mix_factor: p_color = c2
				
			var start_x = x_block * pixel_size
			var start_y = y_block * pixel_size
			for dy in range(pixel_size):
				if start_y + dy >= th: break
				for dx in range(pixel_size):
					if start_x + dx >= tw: break
					preview_img.set_pixel(start_x + dx, start_y + dy, p_color)
			
	var tex = ImageTexture.create_from_image(preview_img)
	tex_rect.texture = tex
	tex_rect.stretch_mode = TextureRect.STRETCH_TILE


# =========================================================================
# PROCESAMIENTO PERIÓDICO (CUENTA REGRESIVA Y PULSO TUTORIAL)
# =========================================================================

func process_lab(_delta: float) -> void:
	if not is_instance_valid(grid): return
	var ui_elements = grid.ui_elements
	
	if is_instance_valid(lab_panel) and lab_panel.visible:
		var now = int(Time.get_unix_time_from_system())
		var left = lab_unlock_expiry_unix - now
		if ui_elements.has("lab_time_lbl") and is_instance_valid(ui_elements["lab_time_lbl"]):
			if left > 0:
				ui_elements["lab_time_lbl"].text = "Tiempo: %02d:%02d:%02d" % [int(left / 3600.0), int((left % 3600) / 60.0), left % 60]
			else:
				ui_elements["lab_time_lbl"].text = "Bloqueado"

		if ui_elements.has("lab_overlay") and is_instance_valid(ui_elements["lab_overlay"]):
			var overlay = ui_elements["lab_overlay"]
			if left > 0:
				if overlay.visible: 
					overlay.visible = false
					if not is_lab_unlocked: set_lab_unlocked(true)
			else:
				if not overlay.visible:
					overlay.visible = true
					if is_lab_unlocked: set_lab_unlocked(false)

	# Pulso visual en edición de nombre durante el paso 1 del tutorial
	if lab_tutorial_step == 1 and ui_elements.has("lab_name_edits"):
		var edits = ui_elements["lab_name_edits"]
		var active_idx = lab_selected_slot
		if edits.size() > active_idx and is_instance_valid(edits[active_idx]):
			var main_edit = edits[active_idx]
			main_edit.pivot_offset = main_edit.size / 2
			var scale_val = 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.004)
			main_edit.scale = Vector2(scale_val, scale_val)
			
			for j in range(edits.size()):
				if j != active_idx and is_instance_valid(edits[j]): edits[j].scale = Vector2.ONE
	elif ui_elements.has("lab_name_edits"):
		for edit in ui_elements["lab_name_edits"]:
			if is_instance_valid(edit) and edit.scale != Vector2.ONE: edit.scale = Vector2.ONE
	
	if ui_elements.has("lab_slots_hbox"):
		if is_instance_valid(ui_elements["lab_slots_hbox"]): ui_elements["lab_slots_hbox"].modulate.a = 1.0


# =========================================================================
# SERIALIZACIÓN / RESTAURACIÓN PARA GUARDADO (SandboxSaveSystem)
# =========================================================================

func get_cleaned_lab_data() -> Array:
	var clean_lab = []
	for i in range(3):
		var data = lab_custom_data[i]
		var entry = {
			"name": data.get("name", ""),
			"c1": data["c1"].to_html() if data.get("c1") is Color else "00000000",
			"c2": data["c2"].to_html() if data.get("c2") is Color else "00000000",
			"c3": data["c3"].to_html() if data.get("c3") is Color else "00000000",
			"mix": data.get("mix", 0),
			"grav": data.get("grav", 0),
			"state": data.get("state", 0),
			"tags": data.get("tags", {})
		}
		clean_lab.append(entry)
	return clean_lab


func restore_lab_data(lab_data: Array) -> void:
	for i in range(min(3, lab_data.size())):
		var data = lab_data[i]
		lab_custom_data[i]["name"] = data.get("name", "Name")
		lab_custom_data[i]["c1"] = Color(data.get("c1", "00000000"))
		lab_custom_data[i]["c2"] = Color(data.get("c2", "00000000"))
		lab_custom_data[i]["c3"] = Color(data.get("c3", "00000000"))
		lab_custom_data[i]["mix"] = data.get("mix", 0)
		lab_custom_data[i]["grav"] = data.get("grav", 0)
		lab_custom_data[i]["state"] = data.get("state", 0)
		lab_custom_data[i]["tags"] = data.get("tags", {})
		
		apply_custom_material_to_engine(i)
		
		if is_instance_valid(grid) and grid.ui_elements.has("lab_name_edits") and grid.ui_elements["lab_name_edits"].size() > i:
			if is_instance_valid(grid.ui_elements["lab_name_edits"][i]):
				grid.ui_elements["lab_name_edits"][i].text = lab_custom_data[i]["name"]
	
	sync_palette_to_shader()
	
	if is_instance_valid(lab_panel):
		for i in range(3):
			update_lab_preview(i)
		update_lab_inspector()
	
	update_custom_mats_in_material_grid()
