extends Node
class_name SandboxSaveSystem

## Módulo especializado en el Sistema de Guardado, Carga, Serialización y Compartición.
## Administra:
## 1. Serialización y deserialización del universo físico (formato .sbu y slots .dat comprimidos con ZSTD).
## 2. Generación precisa de miniaturas (thumbnails) WebP lossless de la simulación.
## 3. Caché de rotación/flip del lienzo (user://rotation_cache.dat).
## 4. Gestión de interfaz de usuario de ranuras de guardado (SavePanel), diálogos de confirmación y modales.
## 5. Exportación e importación de mapas con comprobación de versión y permisos de almacenamiento.
## 6. Integración con AdMob para acciones monetizadas (guardar, cargar, compartir, importar).
## 7. Métodos públicos para SandboxWorkshopUI: serialize_world_to_dict() y load_world_from_dict().

# Referencia a la cuadrícula principal
var grid: Node = null

# Panel visual principal de guardado
var save_panel: PanelContainer = null


func setup(p_grid: Node) -> void:
	grid = p_grid


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
	return ThemeDB.fallback_font

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

func _get_mouse_position() -> Vector2:
	if is_instance_valid(grid) and grid.has_method("get_viewport"):
		var vp = grid.get_viewport()
		if is_instance_valid(vp):
			return vp.get_mouse_position()
	var vp = get_viewport()
	if is_instance_valid(vp):
		return vp.get_mouse_position()
	return Vector2.ZERO

func _play_action_sound(sound_name: String) -> void:
	if is_instance_valid(grid) and grid.has_method("_play_action_sound"):
		grid._play_action_sound(sound_name)


# =========================================================================
# CACHÉ DE ROTACIÓN (FLIP DE EJE)
# =========================================================================

func save_rotation_cache() -> void:
	if not is_instance_valid(grid): return
	var path = "user://rotation_cache.dat"
	
	# Limpiar referencias circulares de NPCs para prevenir recursión infinita en store_var
	var clean_npcs = []
	var keys_to_nullify = ["social_target", "cached_target", "cached_closest_enemy", "cached_closest_ally", "social_partner"]
	for npc in grid.active_npcs:
		var c = {}
		for key in npc:
			if key in keys_to_nullify:
				c[key] = null
			else:
				c[key] = npc[key]
		clean_npcs.append(c)
		
	var save_dict = {
		"width": grid.grid_width,
		"height": grid.grid_height,
		"grid": grid.cells,
		"charge": grid.charge_array,
		"tags": grid.tags_array,
		"cell_paint": grid.cell_paint_colors,
		"bg_paint": grid.background_img.get_data().to_int32_array(),
		"npcs": clean_npcs,
		"npc_id_counter": grid._npc_id_counter,
		"active_logic_gates": grid.active_logic_gates,
		"active_pistons": grid.active_pistons,
		"door_registry": grid.door_registry.keys(),
		"door_close_timers": grid.door_close_timers,
		"phase_block_registry": grid.phase_block_registry.keys()
	}
	var file = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_var(save_dict, true)
		file.close()

func load_rotation_cache() -> void:
	if not is_instance_valid(grid): return
	var path = "user://rotation_cache.dat"
	if not FileAccess.file_exists(path): return
	
	var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file:
		var dict = file.get_var(true)
		file.close()
		DirAccess.remove_absolute(path)
		
		if dict:
			grid._map_grid_data(dict)
			grid._load_active_logic_gates(dict)
			grid._reconstruct_sources_from_cells(dict)


# =========================================================================
# SERIALIZACIÓN Y DESERIALIZACIÓN (CORE ENGINE)
# =========================================================================

func serialize_world_to_dict(save_name: String = "") -> Dictionary:
	if not is_instance_valid(grid): return {}
	
	var time = Time.get_datetime_dict_from_system()
	var date_str = "{0}/{1}/{2} {3}:{4}".format([time.day, time.month, time.year, time.hour, time.minute])
	var final_name = save_name if save_name != "" else "Untitled World"
	
	# Limpiar referencias circulares de NPCs
	var clean_npcs = []
	var keys_to_nullify = ["social_target", "cached_target", "cached_closest_enemy", "cached_closest_ally", "social_partner"]
	for npc in grid.active_npcs:
		var c = {}
		for key in npc:
			if key in keys_to_nullify:
				c[key] = null
			else:
				c[key] = npc[key]
		clean_npcs.append(c)

	var save_dict = {
		"name": final_name,
		"date": date_str,
		"width": grid.grid_width,
		"height": grid.grid_height,
		"grid": grid.cells,
		"charge": grid.charge_array,
		"tags": grid.tags_array,
		"cell_paint": grid.cell_paint_colors,
		"bg_paint": grid.background_img.get_data().to_int32_array(),
		"lab_data": get_cleaned_lab_data(),
		"npcs": clean_npcs,
		"ach_unlocked": grid.is_achievement_menu_unlocked,
		"door_registry": grid.door_registry.keys(),
		"door_close_timers": grid.door_close_timers,
		"phase_block_registry": grid.phase_block_registry.keys(),
		"frame_count": grid._frame_count,
		"music_tempo_frames": grid.music_tempo_frames,
		"active_logic_gates": grid.active_logic_gates,
		"active_pistons": grid.active_pistons,
		"disasters": {
			"current_weather": grid.current_weather,
			"acid_rain_intensity": grid.acid_rain_intensity,
			"earthquake_intensity": grid.earthquake_intensity,
			"earthquake_timer": grid.earthquake_timer,
			"tornado_intensity": grid.tornado_intensity,
			"tornado_timer": grid.tornado_timer,
			"tornado_x": grid.tornado_x,
			"tornado_target_x": grid.tornado_target_x,
			"tornado_ground_y": grid.tornado_ground_y,
			"tornado_element": grid.tornado_element,
			"tsunami_intensity": grid.tsunami_intensity,
			"tsunami_timer": grid.tsunami_timer,
			"tsunami_wave_x": grid.tsunami_wave_x,
			"bombardero_intensity": grid.bombardero_intensity,
			"bombardero_x": grid.bombardero_x,
			"bombardero_y": grid.bombardero_y,
			"bombardero_dir": grid.bombardero_dir,
			"bombardero_speed": grid.bombardero_speed,
			"bombardero_drop_prob": grid.bombardero_drop_prob,
			"bombardero_pending_checks": grid.bombardero_pending_checks
		}
	}
	return save_dict

func load_world_from_dict(dict: Dictionary) -> void:
	if not is_instance_valid(grid) or not dict: return
	
	# Limpiar pila de historial para prevenir undos inválidos hacia el mundo anterior
	if is_instance_valid(grid.history_manager):
		grid.history_manager.clear_history()
		
	# 1. Limpiar estado actual de simulación
	grid._clear_all()
	
	# 2. Mapeador unificado (Restaura Grid, Cargas, Tags, Pintura y activa chunks)
	grid._map_grid_data(dict)
	
	# Mapear next_charge_indices a active_charge_indices inmediatamente para el primer frame
	grid.active_charge_indices = grid.next_charge_indices
	grid.next_charge_indices = PackedInt32Array()
	
	if dict.has("frame_count"):
		grid._frame_count = int(dict["frame_count"])
	else:
		grid._frame_count = 0
	if dict.has("music_tempo_frames"):
		grid.music_tempo_frames = int(dict["music_tempo_frames"])

	grid._load_active_logic_gates(dict)
	grid._reconstruct_sources_from_cells(dict)
	grid._simulate_logic_gates()
	
	# 3. Restaurar experimentos del Laboratorio
	if dict.has("lab_data"):
		restore_lab_data(dict["lab_data"])
		
	# 4. Restaurar Desastres
	if dict.has("disasters"):
		var d = dict["disasters"]
		grid.current_weather = d.get("current_weather", 0)
		grid.acid_rain_intensity = d.get("acid_rain_intensity", 0)
		grid.earthquake_intensity = d.get("earthquake_intensity", 0)
		grid.earthquake_timer = d.get("earthquake_timer", 0.0)
		grid.tornado_intensity = d.get("tornado_intensity", 0)
		grid.tornado_timer = d.get("tornado_timer", 0.0)
		grid.tornado_x = d.get("tornado_x", 0.0)
		grid.tornado_target_x = d.get("tornado_target_x", 0.0)
		grid.tornado_ground_y = d.get("tornado_ground_y", 0.0)
		grid.tornado_element = d.get("tornado_element", 0)
		grid.tsunami_intensity = d.get("tsunami_intensity", 0)
		grid.tsunami_timer = d.get("tsunami_timer", 0.0)
		grid.tsunami_wave_x = d.get("tsunami_wave_x", 0.0)
		grid.bombardero_intensity = d.get("bombardero_intensity", 0)
		grid.bombardero_x = d.get("bombardero_x", 0.0)
		grid.bombardero_y = d.get("bombardero_y", 12.0)
		grid.bombardero_dir = d.get("bombardero_dir", 1.0)
		grid.bombardero_speed = d.get("bombardero_speed", 0.0)
		grid.bombardero_drop_prob = d.get("bombardero_drop_prob", 0.0)
		grid.bombardero_pending_checks = d.get("bombardero_pending_checks", [])
		
		# Reiniciar sonidos si están activos
		if grid.earthquake_intensity > 0: _play_action_sound("earthquake")
		if grid.tornado_intensity > 0: _play_action_sound("tornado")
		if grid.tsunami_intensity > 0: _play_action_sound("tsunami")
		if grid.bombardero_intensity > 0:
			if not grid.bombardero_texture: grid.bombardero_texture = load("res://assets/icon_game/avion_bombardero.png")
			grid._manage_looping_player(grid.bombardero_player, "bomber_engine")
			if is_instance_valid(grid.bombardero_player): grid.bombardero_player.volume_db = -6.0
	else:
		grid.current_weather = 0; grid.acid_rain_intensity = 0
		grid.earthquake_intensity = 0; grid.earthquake_timer = 0.0
		grid.tornado_intensity = 0; grid.tornado_timer = 0.0
		grid.tsunami_intensity = 0; grid.tsunami_timer = 0.0
		grid.bombardero_intensity = 0; grid.bombardero_pending_checks.clear()
		if is_instance_valid(grid.bombardero_player) and grid.bombardero_player.playing: grid.bombardero_player.stop()
	
	grid._update_arcade_dynamic_button()
	
	if dict.has("ach_unlocked"):
		grid.is_achievement_menu_unlocked = dict["ach_unlocked"]
		grid._setup_main_ui_containers()
		
	grid._update_texture()
	grid.queue_redraw()
	if is_instance_valid(save_panel): save_panel.queue_free()

func generate_thumbnail_image() -> Image:
	if not is_instance_valid(grid): return Image.new()
	var sample_height = grid.dynamic_grid_height
	var thumb_w = grid.grid_width
	var thumb_h = sample_height
	var thumb = Image.create(thumb_w, thumb_h, false, Image.FORMAT_RGBA8)
	
	for ty in range(thumb_h):
		for tx in range(thumb_w):
			var gx = tx
			var gy = ty
			var cell_idx = gy * grid.grid_width + gx
			var raw_id = grid.cells[cell_idx]
			var mid = raw_id & 0xFFFF
			var variant = (raw_id >> 24) & 0xFF
			
			var color = Color(0, 0, 0, 0)
			
			# 1. Fondo pintado
			var bg_color = grid.background_img.get_pixel(gx, gy)
			if bg_color.a > 0: color = bg_color
			
			# 2. Elemento (paleta de materiales o color personalizado)
			if mid > 0:
				var custom_i32 = grid.cell_paint_colors[cell_idx]
				if custom_i32 != 0:
					var r = (custom_i32 & 0xFF) / 255.0
					var g = ((custom_i32 >> 8) & 0xFF) / 255.0
					var b = ((custom_i32 >> 16) & 0xFF) / 255.0
					color = Color(r, g, b, 1.0)
				else:
					var render_id = mid
					if render_id >= 10000:
						render_id = render_id % 10000
					if variant == 1:
						color = grid.mat_colors_2[render_id] if render_id < grid.mat_colors_2.size() else Color.BLACK
					elif variant == 2:
						color = grid.mat_colors_3[render_id] if render_id < grid.mat_colors_3.size() else Color.BLACK
					else:
						color = grid.mat_colors_1[render_id] if render_id < grid.mat_colors_1.size() else Color.BLACK
			
			thumb.set_pixel(tx, ty, color)
	return thumb

func save_to_slot(idx: int, custom_name: String = "") -> void:
	if not is_instance_valid(grid): return
	var path = "user://save_slot_" + str(idx) + ".dat"
	var thumb_path = "user://save_slot_" + str(idx) + ".png"
	
	AnalyticsManager.log_event("save_game", {"slot": int(idx)})
	
	var save_name = custom_name if custom_name != "" else ("Save " + str(idx))
	var save_dict = serialize_world_to_dict(save_name)
	
	var file = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_var(save_dict, true)
		file.close()
		
	var thumb = generate_thumbnail_image()
	var thumb_path_webp = thumb_path.replace(".png", ".webp")
	thumb.save_webp(thumb_path_webp, false)
	
	setup_save_ui()

func load_from_slot(idx: int) -> void:
	var path = "user://save_slot_" + str(idx) + ".dat"
	AnalyticsManager.log_event("load_game", {"slot": int(idx)})
	load_world_from_path(path)

func load_world_from_path(path: String) -> void:
	if not FileAccess.file_exists(path): return
	
	var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file:
		var dict = file.get_var(true)
		file.close()
		if dict and typeof(dict) == TYPE_DICTIONARY:
			load_world_from_dict(dict)

func get_slot_data(idx: int) -> Dictionary:
	var path = "user://save_slot_" + str(idx) + ".dat"
	var thumb_path_webp = "user://save_slot_" + str(idx) + ".webp"
	var thumb_path_jpg = "user://save_slot_" + str(idx) + ".jpg"
	var thumb_path_png = "user://save_slot_" + str(idx) + ".png"
	var final_path = ""
	
	if FileAccess.file_exists(thumb_path_webp):
		final_path = thumb_path_webp
	elif FileAccess.file_exists(thumb_path_jpg):
		final_path = thumb_path_jpg
	elif FileAccess.file_exists(thumb_path_png):
		final_path = thumb_path_png
	
	var data = {}
	if FileAccess.file_exists(path):
		var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if file:
			var dict = file.get_var(true)
			if typeof(dict) == TYPE_DICTIONARY:
				data.name = dict.get("name", "Save " + str(idx))
				data.date = dict.get("date", "Unknown")
			file.close()
			
	if final_path != "":
		var img = Image.load_from_file(final_path)
		if img:
			data.thumbnail = ImageTexture.create_from_image(img)
			
	return data

func get_cleaned_lab_data() -> Array:
	if not is_instance_valid(grid): return []
	var clean_lab = []
	for i in range(3):
		var data = grid.lab_custom_data[i]
		var entry = {
			"name": data["name"],
			"c1": data["c1"].to_html() if data["c1"] is Color else "00000000",
			"c2": data["c2"].to_html() if data["c2"] is Color else "00000000",
			"c3": data["c3"].to_html() if data["c3"] is Color else "00000000",
			"mix": data["mix"],
			"grav": data["grav"],
			"state": data["state"],
			"tags": data["tags"]
		}
		clean_lab.append(entry)
	return clean_lab

func restore_lab_data(lab_data: Array) -> void:
	if not is_instance_valid(grid): return
	for i in range(min(3, lab_data.size())):
		var data = lab_data[i]
		grid.lab_custom_data[i]["name"] = data.get("name", "Name")
		grid.lab_custom_data[i]["c1"] = Color(data.get("c1", "00000000"))
		grid.lab_custom_data[i]["c2"] = Color(data.get("c2", "00000000"))
		grid.lab_custom_data[i]["c3"] = Color(data.get("c3", "00000000"))
		grid.lab_custom_data[i]["mix"] = data.get("mix", 0)
		grid.lab_custom_data[i]["grav"] = data.get("grav", 0)
		grid.lab_custom_data[i]["state"] = data.get("state", 0)
		grid.lab_custom_data[i]["tags"] = data.get("tags", 0)
		
		grid._apply_custom_material_to_engine(i)
		
		if grid.ui_elements.has("lab_name_edits") and grid.ui_elements["lab_name_edits"].size() > i:
			grid.ui_elements["lab_name_edits"][i].text = grid.lab_custom_data[i]["name"]
	
	if is_instance_valid(grid.lab_panel):
		for i in range(3):
			grid._update_lab_preview(i)
		grid._update_lab_inspector()
	
	grid._update_custom_mats_in_material_grid()


# =========================================================================
# INTERFAZ DE USUARIO: PANEL DE GUARDADO (SavePanel)
# =========================================================================

func setup_save_ui() -> void:
	if not is_instance_valid(grid): return
	grid._close_all_popups()
	grid._set_panning_mode(false)
	
	var s = _get_ui_scale()
	var ui_layer = _get_ui_root()
	if not is_instance_valid(ui_layer): return
	
	save_panel = PanelContainer.new()
	save_panel.name = "SavePanel"
	ui_layer.add_child(save_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	panel_style.border_width_left = 3; panel_style.border_width_top = 3
	panel_style.border_width_right = 3; panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.6, 0.5, 0.2)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	save_panel.add_theme_stylebox_override("panel", panel_style)
	save_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	save_panel.mouse_entered.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = true)
	save_panel.mouse_exited.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = false)

	var m_width = 530 * s
	var is_landscape = _get_viewport_rect().size.x > _get_viewport_rect().size.y
	var base_height = 530 * s if is_landscape else 650 * s
	var m_height = min(base_height, _get_viewport_rect().size.y * 0.8)
	grid._align_panel_to_hud(save_panel, m_width, m_height)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20 * s)
	save_panel.add_child(main_vbox)
	
	var title_hbox = HBoxContainer.new()
	main_vbox.add_child(title_hbox)
	
	var title = Label.new()
	title.text = tr("save_btn_ui")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 36 * s)
	title_hbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	var grid_hbox = HBoxContainer.new()
	grid_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	grid_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_hbox)

	var slot_grid = GridContainer.new()
	slot_grid.columns = 2
	slot_grid.add_theme_constant_override("h_separation", 10 * s)
	slot_grid.add_theme_constant_override("v_separation", 15 * s)
	grid_hbox.add_child(slot_grid)
	
	for i in range(1, 11):
		add_save_slot_ui(slot_grid, i)

func add_save_slot_ui(container: Control, slot_idx: int) -> void:
	var s = _get_ui_scale()
	var slot_data = get_slot_data(slot_idx)
	
	var slot_panel = PanelContainer.new()
	slot_panel.custom_minimum_size = Vector2(235 * s, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18)
	style.set_corner_radius_all(10 * s)
	style.border_width_left = 2; style.border_width_top = 2
	style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3)
	slot_panel.add_theme_stylebox_override("panel", style)
	slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	slot_panel.mouse_entered.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = true)
	slot_panel.mouse_exited.connect(func(): if is_instance_valid(grid): grid.is_mouse_over_ui = false)
	container.add_child(slot_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5 * s)
	slot_panel.add_child(vbox)
	
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var lbl_idx = Label.new()
	lbl_idx.text = "#" + str(slot_idx)
	lbl_idx.add_theme_font_size_override("font_size", 26 * s)
	header.add_child(lbl_idx)
	
	var lbl_name = Label.new()
	lbl_name.text = slot_data.name if slot_data.has("name") else tr("empty")
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_name.clip_text = true
	lbl_name.add_theme_font_size_override("font_size", 24 * s)
	header.add_child(lbl_name)
	
	var thumb_rect = TextureButton.new()
	thumb_rect.custom_minimum_size = Vector2(215 * s, 250 * s) 
	thumb_rect.ignore_texture_size = true
	thumb_rect.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	thumb_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	if slot_data.has("thumbnail"):
		thumb_rect.texture_normal = slot_data.thumbnail
	else:
		var empty_tex = GradientTexture2D.new()
		empty_tex.gradient = Gradient.new()
		empty_tex.gradient.set_color(0, Color(0.1, 0.1, 0.1))
		empty_tex.gradient.set_color(1, Color(0.1, 0.1, 0.1))
		thumb_rect.texture_normal = empty_tex
		
	thumb_rect.pressed.connect(func():
		_play_action_sound("ui_click")
		if slot_data.has("name"):
			confirm_load(slot_idx, lbl_name.text)
		else:
			confirm_save(slot_idx, lbl_name.text)
	)
	vbox.add_child(thumb_rect)
	
	var lbl_date = Label.new()
	lbl_date.text = slot_data.date if slot_data.has("date") else ""
	lbl_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_date.add_theme_font_size_override("font_size", 18 * s)
	lbl_date.modulate = Color(0.6, 0.6, 0.6)
	vbox.add_child(lbl_date)
	
	var share_hbox = HBoxContainer.new()
	vbox.add_child(share_hbox)
	
	var share_btn = Button.new()
	share_btn.text = tr("share_btn_ui")
	share_btn.custom_minimum_size = Vector2(0, 45 * s)
	share_btn.add_theme_font_size_override("font_size", 20 * s)
	share_btn.add_theme_font_override("font", _get_safe_font())
	share_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	share_btn.disabled = not slot_data.has("name")
	share_btn.pressed.connect(func(): on_share_pressed(slot_idx, lbl_name.text))
	share_hbox.add_child(share_btn)
	
	var import_btn = Button.new()
	import_btn.text = tr("import_btn_ui")
	import_btn.custom_minimum_size = Vector2(0, 45 * s)
	import_btn.add_theme_font_size_override("font_size", 20 * s)
	import_btn.add_theme_font_override("font", _get_safe_font())
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	import_btn.pressed.connect(func(): on_import_pressed(slot_idx))
	share_hbox.add_child(import_btn)

	var btn_hbox = HBoxContainer.new()
	vbox.add_child(btn_hbox)
	
	var save_btn = Button.new()
	save_btn.text = tr("save_btn_ui")
	save_btn.custom_minimum_size = Vector2(0, 45 * s)
	save_btn.add_theme_font_size_override("font_size", 20 * s)
	save_btn.add_theme_font_override("font", _get_safe_font())
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	save_btn.pressed.connect(func(): confirm_save(slot_idx, lbl_name.text))
	btn_hbox.add_child(save_btn)
	
	if slot_data.has("name"):
		var load_btn = Button.new()
		load_btn.text = tr("load")
		load_btn.custom_minimum_size = Vector2(0, 45 * s)
		load_btn.add_theme_font_size_override("font_size", 20 * s)
		load_btn.add_theme_font_override("font", _get_safe_font())
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		load_btn.pressed.connect(func(): confirm_load(slot_idx, lbl_name.text))
		btn_hbox.add_child(load_btn)

func confirm_save(idx: int, current_name: String) -> void:
	if not is_instance_valid(save_panel): return
	var s = _get_ui_scale()
	var slot_data = get_slot_data(idx)
	var has_thumb = slot_data.has("thumbnail")
	
	var dialog_container = Control.new()
	dialog_container.name = "DialogContainer"
	dialog_container.mouse_filter = Control.MOUSE_FILTER_PASS
	dialog_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_panel.add_child(dialog_container)
	
	var dialog = PanelContainer.new()
	dialog.name = "ConfirmDialog"
	dialog_container.add_child(dialog)
	
	var d_style = StyleBoxFlat.new()
	d_style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	d_style.border_width_left = 3; d_style.border_width_top = 3
	d_style.border_width_right = 3; d_style.border_width_bottom = 3
	d_style.border_color = Color("#27F527")
	d_style.corner_radius_top_left = 30
	d_style.corner_radius_top_right = 30
	d_style.corner_radius_bottom_left = 0
	d_style.corner_radius_bottom_right = 0
	dialog.add_theme_stylebox_override("panel", d_style)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 25 * s)
	margin.add_theme_constant_override("margin_bottom", 25 * s)
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25 * s)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	
	var msg = Label.new()
	msg.text = tr("save_to_slot").format([str(idx)])
	if current_name != tr("empty"):
		msg.text = tr("override_confirm").format([str(idx), current_name])
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 22 * s)
	vbox.add_child(msg)
	
	var name_edit = LineEdit.new()
	name_edit.placeholder_text = tr("enter_save_name")
	name_edit.text = current_name if current_name != tr("empty") else "Save " + str(idx)
	name_edit.custom_minimum_size = Vector2(300 * s, 50 * s)
	name_edit.add_theme_font_size_override("font_size", 20 * s)
	vbox.add_child(name_edit)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20 * s)
	vbox.add_child(hbox)
	
	var yes_btn = Button.new()
	yes_btn.text = tr("yes")
	yes_btn.custom_minimum_size = Vector2(130 * s, 60 * s)
	yes_btn.add_theme_font_size_override("font_size", 20 * s)
	var yes_style = StyleBoxFlat.new()
	yes_style.bg_color = Color(0.2, 0.6, 0.2)
	yes_style.set_corner_radius_all(10 * s)
	yes_btn.add_theme_stylebox_override("normal", yes_style)
	yes_btn.pressed.connect(func(): 
		save_to_slot(idx, name_edit.text)
		dialog_container.queue_free()
	)
	hbox.add_child(yes_btn)
	
	var no_btn = Button.new()
	no_btn.text = tr("no")
	no_btn.custom_minimum_size = Vector2(130 * s, 60 * s)
	no_btn.add_theme_font_size_override("font_size", 20 * s)
	var no_style = StyleBoxFlat.new()
	no_style.bg_color = Color(0.6, 0.2, 0.2)
	no_style.set_corner_radius_all(10 * s)
	no_btn.add_theme_stylebox_override("normal", no_style)
	no_btn.pressed.connect(func(): dialog_container.queue_free())
	hbox.add_child(no_btn)
	
	if has_thumb:
		var rect = TextureRect.new()
		rect.texture = slot_data.thumbnail
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var img_panel = PanelContainer.new()
		img_panel.clip_contents = true
		img_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		img_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var img_style = StyleBoxFlat.new()
		img_style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
		img_style.border_width_left = 2; img_style.border_width_top = 2
		img_style.border_width_right = 2; img_style.border_width_bottom = 2
		img_style.border_color = Color(0.3, 0.3, 0.3)
		img_style.set_corner_radius_all(15 * s)
		img_panel.add_theme_stylebox_override("panel", img_style)
		img_panel.add_child(rect)
		vbox.add_child(img_panel)

func confirm_load(idx: int, current_name: String) -> void:
	if not is_instance_valid(save_panel): return
	var s = _get_ui_scale()
	var slot_data = get_slot_data(idx)
	var has_thumb = slot_data.has("thumbnail")
	
	var dialog_container = Control.new()
	dialog_container.name = "DialogContainer"
	dialog_container.mouse_filter = Control.MOUSE_FILTER_PASS
	dialog_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_panel.add_child(dialog_container)
	
	var dialog = PanelContainer.new()
	dialog.name = "ConfirmLoadDialog"
	dialog_container.add_child(dialog)
	
	var d_style = StyleBoxFlat.new()
	d_style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	d_style.border_width_left = 3; d_style.border_width_top = 3
	d_style.border_width_right = 3; d_style.border_width_bottom = 3
	d_style.border_color = Color("#278EF5")
	d_style.corner_radius_top_left = 30
	d_style.corner_radius_top_right = 30
	d_style.corner_radius_bottom_left = 0
	d_style.corner_radius_bottom_right = 0
	dialog.add_theme_stylebox_override("panel", d_style)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 25 * s)
	margin.add_theme_constant_override("margin_bottom", 25 * s)
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25 * s)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	
	var msg = Label.new()
	msg.text = tr("load_confirm").format([current_name])
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 22 * s)
	vbox.add_child(msg)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20 * s)
	vbox.add_child(hbox)
	
	var yes_btn = Button.new()
	yes_btn.text = tr("yes")
	yes_btn.custom_minimum_size = Vector2(130 * s, 60 * s)
	yes_btn.add_theme_font_size_override("font_size", 20 * s)
	var yes_style = StyleBoxFlat.new()
	yes_style.bg_color = Color(0.2, 0.6, 0.2)
	yes_style.set_corner_radius_all(10 * s)
	yes_btn.add_theme_stylebox_override("normal", yes_style)
	yes_btn.pressed.connect(func(): 
		dialog_container.queue_free()
		execute_monetized_action("load", func():
			load_from_slot(idx)
		)
	)
	hbox.add_child(yes_btn)
	
	var no_btn = Button.new()
	no_btn.text = tr("no")
	no_btn.custom_minimum_size = Vector2(130 * s, 60 * s)
	no_btn.add_theme_font_size_override("font_size", 20 * s)
	var no_style = StyleBoxFlat.new()
	no_style.bg_color = Color(0.6, 0.2, 0.2)
	no_style.set_corner_radius_all(10 * s)
	no_btn.add_theme_stylebox_override("normal", no_style)
	no_btn.pressed.connect(func(): dialog_container.queue_free())
	hbox.add_child(no_btn)
	
	if has_thumb:
		var rect = TextureRect.new()
		rect.texture = slot_data.thumbnail
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var img_panel = PanelContainer.new()
		img_panel.clip_contents = true
		img_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		img_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var img_style = StyleBoxFlat.new()
		img_style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
		img_style.border_width_left = 2; img_style.border_width_top = 2
		img_style.border_width_right = 2; img_style.border_width_bottom = 2
		img_style.border_color = Color(0.3, 0.3, 0.3)
		img_style.set_corner_radius_all(15 * s)
		img_panel.add_theme_stylebox_override("panel", img_style)
		img_panel.add_child(rect)
		vbox.add_child(img_panel)


# =========================================================================
# UTILIDADES, MODALES Y PERMISOS
# =========================================================================

func sanitize_filename(filename: String) -> String:
	var invalid_chars = ["/", "\\", "?", "*", ":", "|", "\"", "<", ">"]
	var result = filename
	for c in invalid_chars:
		result = result.replace(c, "_")
	return result.strip_edges()

func is_version_newer(imported_ver: String, current_ver: String) -> bool:
	var imp_parts = imported_ver.split(".")
	var curr_parts = current_ver.split(".")
	var max_parts = max(imp_parts.size(), curr_parts.size())
	for i in range(max_parts):
		var imp_val = 0
		if i < imp_parts.size():
			imp_val = int(imp_parts[i])
		var curr_val = 0
		if i < curr_parts.size():
			curr_val = int(curr_parts[i])
		if imp_val > curr_val:
			return true
		elif imp_val < curr_val:
			return false
	return false

func show_confirm_dialog(title_text: String, message_text: String, on_confirm: Callable) -> void:
	var s = _get_ui_scale()
	var root = _get_ui_root()
	if not is_instance_valid(root): return
		
	var blocker = Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			blocker.queue_free()
	)
	
	var bubble = PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	p_style.set_corner_radius_all(18 * s)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color(0.8, 0.6, 0.2)
	p_style.shadow_color = Color(0, 0, 0, 0.6)
	p_style.shadow_size = 15
	bubble.add_theme_stylebox_override("panel", p_style)
	
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_top", 16 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	margin.add_theme_constant_override("margin_bottom", 16 * s)
	bubble.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_theme_constant_override("separation", 15 * s)
	margin.add_child(vbox)
	
	var lbl_title = Label.new()
	lbl_title.text = title_text
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 24 * s)
	lbl_title.add_theme_font_override("font", _get_safe_font())
	lbl_title.add_theme_color_override("font_color", Color("#f1c40f"))
	vbox.add_child(lbl_title)
	
	var lbl_msg = Label.new()
	lbl_msg.text = message_text
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_msg.custom_minimum_size = Vector2(320 * s, 0)
	lbl_msg.add_theme_font_size_override("font_size", 20 * s)
	lbl_msg.add_theme_font_override("font", _get_safe_font())
	vbox.add_child(lbl_msg)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20 * s)
	vbox.add_child(hbox)
	
	var yes_btn = Button.new()
	yes_btn.text = tr("yes") if tr("yes") != "yes" else "Yes"
	yes_btn.custom_minimum_size = Vector2(120 * s, 46 * s)
	yes_btn.add_theme_font_size_override("font_size", 18 * s)
	yes_btn.add_theme_font_override("font", _get_safe_font())
	var yes_style = StyleBoxFlat.new()
	yes_style.bg_color = Color("#27ae60")
	yes_style.set_corner_radius_all(10 * s)
	yes_btn.add_theme_stylebox_override("normal", yes_style)
	yes_btn.add_theme_stylebox_override("hover", yes_style)
	yes_btn.add_theme_stylebox_override("pressed", yes_style)
	yes_btn.pressed.connect(func():
		blocker.queue_free()
		on_confirm.call()
	)
	hbox.add_child(yes_btn)
	
	var no_btn = Button.new()
	no_btn.text = tr("no") if tr("no") != "no" else "No"
	no_btn.custom_minimum_size = Vector2(120 * s, 46 * s)
	no_btn.add_theme_font_size_override("font_size", 18 * s)
	no_btn.add_theme_font_override("font", _get_safe_font())
	var no_style = StyleBoxFlat.new()
	no_style.bg_color = Color("#c0392b")
	no_style.set_corner_radius_all(10 * s)
	no_btn.add_theme_stylebox_override("normal", no_style)
	no_btn.add_theme_stylebox_override("hover", no_style)
	no_btn.add_theme_stylebox_override("pressed", no_style)
	no_btn.pressed.connect(func():
		blocker.queue_free()
	)
	hbox.add_child(no_btn)
	
	blocker.add_child(bubble)
	root.add_child(blocker)
	
	var screen_pos = _get_mouse_position()
	await get_tree().process_frame
	
	if is_instance_valid(bubble):
		var bubble_size = bubble.size
		var margin_y = 20 * s
		
		var target_y = screen_pos.y - bubble_size.y - margin_y
		if target_y < 30 * s:
			target_y = screen_pos.y + 40 * s
			
		bubble.position.x = screen_pos.x - bubble_size.x / 2
		bubble.position.y = target_y
		
		var screen_size = _get_viewport_rect().size
		bubble.position.x = clamp(bubble.position.x, 10 * s, screen_size.x - bubble_size.x - 10 * s)
		bubble.position.y = clamp(bubble.position.y, 10 * s, screen_size.y - bubble_size.y - 10 * s)

func show_modal_message(title_text: String, message_text: String) -> void:
	var s = _get_ui_scale()
	var dialog_container = Control.new()
	dialog_container.name = "MessageDialogContainer"
	dialog_container.mouse_filter = Control.MOUSE_FILTER_PASS
	dialog_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	if is_instance_valid(save_panel) and save_panel.visible:
		save_panel.add_child(dialog_container)
	elif is_instance_valid(grid) and "workshop_panel" in grid and is_instance_valid(grid.workshop_panel) and grid.workshop_panel.visible:
		grid.workshop_panel.add_child(dialog_container)
	elif is_instance_valid(_get_ui_root()):
		_get_ui_root().add_child(dialog_container)
	else:
		add_child(dialog_container)
	
	var dialog = PanelContainer.new()
	dialog_container.add_child(dialog)
	
	var d_style = StyleBoxFlat.new()
	d_style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	d_style.border_width_left = 3; d_style.border_width_top = 3
	d_style.border_width_right = 3; d_style.border_width_bottom = 3
	d_style.border_color = Color(0.6, 0.5, 0.2)
	d_style.corner_radius_top_left = 30
	d_style.corner_radius_top_right = 30
	dialog.add_theme_stylebox_override("panel", d_style)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 40 * s)
	margin.add_theme_constant_override("margin_bottom", 40 * s)
	margin.add_theme_constant_override("margin_left", 30 * s)
	margin.add_theme_constant_override("margin_right", 30 * s)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25 * s)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	var lbl_title = Label.new()
	lbl_title.text = title_text
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 28 * s)
	lbl_title.add_theme_font_override("font", _get_safe_font())
	vbox.add_child(lbl_title)
	
	var lbl_msg = Label.new()
	lbl_msg.text = message_text
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_msg.add_theme_font_size_override("font_size", 22 * s)
	vbox.add_child(lbl_msg)
	
	var ok_btn = Button.new()
	ok_btn.text = tr("GOT_IT") if tr("GOT_IT") != "GOT_IT" else "OK"
	ok_btn.custom_minimum_size = Vector2(150 * s, 50 * s)
	ok_btn.add_theme_font_size_override("font_size", 20 * s)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.6, 0.2)
	btn_style.set_corner_radius_all(10 * s)
	ok_btn.add_theme_stylebox_override("normal", btn_style)
	ok_btn.pressed.connect(func(): dialog_container.queue_free())
	vbox.add_child(ok_btn)

func check_and_request_storage_permission(on_granted: Callable) -> void:
	if OS.get_name() != "Android":
		on_granted.call()
		return
		
	var permissions = OS.get_granted_permissions()
	var has_read = "android.permission.READ_EXTERNAL_STORAGE" in permissions
	var has_write = "android.permission.WRITE_EXTERNAL_STORAGE" in permissions
	
	if has_read and has_write:
		on_granted.call()
		return
		
	var s = _get_ui_scale()
	var dialog_container = Control.new()
	dialog_container.name = "PermissionExplanationContainer"
	dialog_container.mouse_filter = Control.MOUSE_FILTER_PASS
	dialog_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if is_instance_valid(save_panel):
		save_panel.add_child(dialog_container)
	elif is_instance_valid(_get_ui_root()):
		_get_ui_root().add_child(dialog_container)
	else:
		add_child(dialog_container)
	
	var dialog = PanelContainer.new()
	dialog_container.add_child(dialog)
	
	var d_style = StyleBoxFlat.new()
	d_style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	d_style.border_width_left = 3; d_style.border_width_top = 3
	d_style.border_width_right = 3; d_style.border_width_bottom = 3
	d_style.border_color = Color(0.6, 0.5, 0.2)
	d_style.corner_radius_top_left = 30
	d_style.corner_radius_top_right = 30
	dialog.add_theme_stylebox_override("panel", d_style)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 40 * s)
	margin.add_theme_constant_override("margin_bottom", 40 * s)
	margin.add_theme_constant_override("margin_left", 30 * s)
	margin.add_theme_constant_override("margin_right", 30 * s)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25 * s)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	var lbl_title = Label.new()
	lbl_title.text = tr("permission_title")
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 28 * s)
	lbl_title.add_theme_font_override("font", _get_safe_font())
	vbox.add_child(lbl_title)
	
	var lbl_msg = Label.new()
	lbl_msg.text = tr("permission_desc")
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_msg.add_theme_font_size_override("font_size", 22 * s)
	vbox.add_child(lbl_msg)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20 * s)
	vbox.add_child(hbox)
	
	var yes_btn = Button.new()
	yes_btn.text = tr("permission_grant")
	yes_btn.custom_minimum_size = Vector2(150 * s, 50 * s)
	yes_btn.add_theme_font_size_override("font_size", 20 * s)
	var yes_style = StyleBoxFlat.new()
	yes_style.bg_color = Color(0.2, 0.6, 0.2)
	yes_style.set_corner_radius_all(10 * s)
	yes_btn.add_theme_stylebox_override("normal", yes_style)
	yes_btn.pressed.connect(func():
		dialog_container.queue_free()
		OS.request_permissions()
		show_modal_message(
			tr("permission_title"),
			tr("permission_retry_msg")
		)
	)
	hbox.add_child(yes_btn)
	
	var no_btn = Button.new()
	no_btn.text = tr("no")
	no_btn.custom_minimum_size = Vector2(150 * s, 50 * s)
	no_btn.add_theme_font_size_override("font_size", 20 * s)
	var no_style = StyleBoxFlat.new()
	no_style.bg_color = Color(0.6, 0.2, 0.2)
	no_style.set_corner_radius_all(10 * s)
	no_btn.add_theme_stylebox_override("normal", no_style)
	no_btn.pressed.connect(func(): dialog_container.queue_free())
	hbox.add_child(no_btn)

func show_processing_overlay(text: String) -> Control:
	var s = _get_ui_scale()
	var canvas = _get_ui_root()
	if not canvas:
		canvas = get_tree().root.find_child("UI", true, false)
	if not canvas:
		canvas = save_panel
		if not canvas:
			return null
			
	var overlay = PanelContainer.new()
	overlay.name = "ProcessingOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.65)
	overlay.add_theme_stylebox_override("panel", bg_style)
	
	var center = CenterContainer.new()
	overlay.add_child(center)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500 * s, 250 * s)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.98)
	style.corner_radius_top_left = 24 * s
	style.corner_radius_top_right = 24 * s
	style.corner_radius_bottom_left = 24 * s
	style.corner_radius_bottom_right = 24 * s
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 20 * s
	style.shadow_offset = Vector2(0, 10 * s)
	style.border_width_left = 3 * s
	style.border_width_top = 3 * s
	style.border_width_right = 3 * s
	style.border_width_bottom = 3 * s
	style.border_color = Color(0.6, 0.5, 0.2)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30 * s)
	margin.add_theme_constant_override("margin_top", 30 * s)
	margin.add_theme_constant_override("margin_right", 30 * s)
	margin.add_theme_constant_override("margin_bottom", 30 * s)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20 * s)
	margin.add_child(vbox)
	
	var spinner = Control.new()
	spinner.custom_minimum_size = Vector2(160 * s, 80 * s)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spinner.set_script(load("res://scripts/loading_spinner.gd"))
	vbox.add_child(spinner)
	
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 24 * s)
	label.add_theme_font_override("font", _get_safe_font())
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(label)
	
	canvas.add_child(overlay)
	return overlay

func execute_monetized_action(button_type: String, action_callable: Callable) -> void:
	var overlay = show_processing_overlay(tr("processing_creation"))
	
	var is_free = AdMobManager.check_and_consume_free_use(button_type)
	if is_free:
		await get_tree().create_timer(2.0).timeout
	else:
		if AdMobManager.is_interstitial_loaded():
			AdMobManager.show_interstitial()
			await AdMobManager.ad_dismissed
		else:
			AdMobManager.preload_interstitial()
			var success = await AdMobManager.interstitial_ad_loaded
			if success:
				AdMobManager.show_interstitial()
				await AdMobManager.ad_dismissed
				
	if is_instance_valid(overlay):
		overlay.queue_free()
		
	action_callable.call()

func on_share_pressed(slot_idx: int, slot_name: String) -> void:
	check_and_request_storage_permission(func():
		execute_monetized_action("share", func():
			var path = "user://save_slot_" + str(slot_idx) + ".dat"
			var thumb_path_webp = "user://save_slot_" + str(slot_idx) + ".webp"
			var thumb_path_jpg = "user://save_slot_" + str(slot_idx) + ".jpg"
			var thumb_path_png = "user://save_slot_" + str(slot_idx) + ".png"
			
			if not FileAccess.file_exists(path):
				return
				
			var data_dict = {}
			var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
			if file:
				data_dict = file.get_var(true)
				file.close()
				
			if not data_dict:
				show_modal_message(
					tr("share_btn_ui"),
					tr("export_fail")
				)
				return
				
			var sbu_dict = {
				"version": 2,
				"game_version": str(ProjectSettings.get_setting("application/config/version", "1.2.0")),
				"name": slot_name,
				"grid_data": data_dict
			}
			
			var final_thumb_path = ""
			if FileAccess.file_exists(thumb_path_webp):
				final_thumb_path = thumb_path_webp
			elif FileAccess.file_exists(thumb_path_jpg):
				final_thumb_path = thumb_path_jpg
			elif FileAccess.file_exists(thumb_path_png):
				final_thumb_path = thumb_path_png
			
			if final_thumb_path != "":
				var thumb_bytes = FileAccess.get_file_as_bytes(final_thumb_path)
				if thumb_bytes and thumb_bytes.size() > 0:
					sbu_dict["thumbnail_bytes"] = thumb_bytes
					
			var downloads_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
			if not DirAccess.dir_exists_absolute(downloads_dir):
				downloads_dir = "user://"
				
			var clean_name = sanitize_filename(slot_name)
			var export_filename = clean_name + ".sbu"
			var export_path = downloads_dir.path_join(export_filename)
			
			var sbu_file = FileAccess.open_compressed(export_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
			if sbu_file:
				sbu_file.store_var(sbu_dict, true)
				sbu_file.close()
				AnalyticsManager.log_event("world_exported", {})
				show_modal_message(
					tr("share_btn_ui"),
					tr("export_success").format([export_filename])
				)
			else:
				show_modal_message(
					tr("share_btn_ui"),
					tr("export_fail")
				)
		)
	)

func on_import_pressed(slot_idx: int) -> void:
	check_and_request_storage_permission(func():
		var downloads_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		var sbu_files = []
		if DirAccess.dir_exists_absolute(downloads_dir):
			var dir = DirAccess.open(downloads_dir)
			if dir:
				dir.list_dir_begin()
				var file_name = dir.get_next()
				while file_name != "":
					if not dir.current_is_dir() and file_name.ends_with(".sbu"):
						sbu_files.append(file_name)
					file_name = dir.get_next()
				dir.list_dir_end()
				
		if sbu_files.size() == 0:
			show_modal_message(
				tr("import_btn_ui"),
				tr("import_no_files")
			)
			return
			
		var s = _get_ui_scale()
		var dialog_container = Control.new()
		dialog_container.name = "ImportDialogContainer"
		dialog_container.mouse_filter = Control.MOUSE_FILTER_PASS
		dialog_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dialog_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if is_instance_valid(save_panel):
			save_panel.add_child(dialog_container)
		elif is_instance_valid(_get_ui_root()):
			_get_ui_root().add_child(dialog_container)
		else:
			add_child(dialog_container)
		
		var dialog = PanelContainer.new()
		dialog_container.add_child(dialog)
		
		var d_style = StyleBoxFlat.new()
		d_style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
		d_style.border_width_left = 3; d_style.border_width_top = 3
		d_style.border_width_right = 3; d_style.border_width_bottom = 3
		d_style.border_color = Color(0.6, 0.5, 0.2)
		d_style.corner_radius_top_left = 30
		d_style.corner_radius_top_right = 30
		dialog.add_theme_stylebox_override("panel", d_style)
		dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_top", 30 * s)
		margin.add_theme_constant_override("margin_bottom", 30 * s)
		margin.add_theme_constant_override("margin_left", 20 * s)
		margin.add_theme_constant_override("margin_right", 20 * s)
		dialog.add_child(margin)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 20 * s)
		margin.add_child(vbox)
		
		var lbl_title = Label.new()
		lbl_title.text = tr("import_select_title")
		lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_title.add_theme_font_size_override("font_size", 28 * s)
		lbl_title.add_theme_font_override("font", _get_safe_font())
		vbox.add_child(lbl_title)
		
		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(scroll)
		
		var list_vbox = VBoxContainer.new()
		list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_vbox.add_theme_constant_override("separation", 10 * s)
		scroll.add_child(list_vbox)
		
		for file_name in sbu_files:
			var btn = Button.new()
			btn.text = file_name.left(file_name.length() - 4)
			btn.custom_minimum_size = Vector2(0, 50 * s)
			btn.add_theme_font_size_override("font_size", 22 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			
			var btn_style = StyleBoxFlat.new()
			btn_style.bg_color = Color(0.18, 0.18, 0.22)
			btn_style.set_corner_radius_all(10 * s)
			btn.add_theme_stylebox_override("normal", btn_style)
			
			btn.pressed.connect(func():
				dialog_container.queue_free()
				execute_monetized_action("import", func():
					import_sbu_file(downloads_dir.path_join(file_name), slot_idx)
				)
			)
			list_vbox.add_child(btn)
			
		var cancel_btn = Button.new()
		cancel_btn.text = tr("no")
		cancel_btn.custom_minimum_size = Vector2(0, 50 * s)
		cancel_btn.add_theme_font_size_override("font_size", 22 * s)
		cancel_btn.add_theme_font_override("font", _get_safe_font())
		var cancel_style = StyleBoxFlat.new()
		cancel_style.bg_color = Color(0.6, 0.2, 0.2)
		cancel_style.set_corner_radius_all(10 * s)
		cancel_btn.add_theme_stylebox_override("normal", cancel_style)
		cancel_btn.pressed.connect(func(): dialog_container.queue_free())
		vbox.add_child(cancel_btn)
	)

func import_sbu_file(file_path: String, slot_idx: int) -> void:
	var sbu_file = FileAccess.open_compressed(file_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if not sbu_file:
		show_modal_message(
			tr("import_btn_ui"),
			tr("import_fail")
		)
		return
		
	var sbu_dict = sbu_file.get_var(true)
	sbu_file.close()
	
	if not sbu_dict or not sbu_dict.has("grid_data"):
		show_modal_message(
			tr("import_btn_ui"),
			tr("import_fail")
		)
		return
		
	var current_ver = str(ProjectSettings.get_setting("application/config/version", "1.2.0"))
	var imported_ver = str(sbu_dict.get("game_version", ""))
	
	if imported_ver != "" and is_version_newer(imported_ver, current_ver):
		var msg = tr("import_newer_version_warning").format([imported_ver, current_ver])
		show_confirm_dialog(
			tr("import_btn_ui"),
			msg,
			func():
				execute_import_data(sbu_dict, file_path, slot_idx)
		)
	else:
		execute_import_data(sbu_dict, file_path, slot_idx)

func execute_import_data(sbu_dict: Dictionary, file_path: String, slot_idx: int) -> void:
	var target_dat_path = "user://save_slot_" + str(slot_idx) + ".dat"
	var target_png_path = "user://save_slot_" + str(slot_idx) + ".png"
	
	var data_dict = sbu_dict["grid_data"]
	
	var dat_file = FileAccess.open_compressed(target_dat_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if dat_file:
		dat_file.store_var(data_dict, true)
		dat_file.close()
	else:
		show_modal_message(
			tr("import_btn_ui"),
			tr("import_fail")
		)
		return
		
	if sbu_dict.has("thumbnail_bytes"):
		var thumb_bytes = sbu_dict["thumbnail_bytes"]
		if thumb_bytes and thumb_bytes.size() > 0:
			var is_jpg = (thumb_bytes.size() > 2 and thumb_bytes[0] == 0xFF and thumb_bytes[1] == 0xD8)
			var is_webp = (thumb_bytes.size() > 12 and thumb_bytes[8] == 0x57 and thumb_bytes[9] == 0x45 and thumb_bytes[10] == 0x42 and thumb_bytes[11] == 0x50)
			
			var ext = ".png"
			if is_jpg: ext = ".jpg"
			elif is_webp: ext = ".webp"
			
			var target_thumb_path = "user://save_slot_" + str(slot_idx) + ext
			
			# Limpiar cualquier miniatura vieja antes de guardar la nueva
			var path_png = "user://save_slot_" + str(slot_idx) + ".png"
			var path_jpg = "user://save_slot_" + str(slot_idx) + ".jpg"
			var path_webp = "user://save_slot_" + str(slot_idx) + ".webp"
			if FileAccess.file_exists(path_png): DirAccess.remove_absolute(path_png)
			if FileAccess.file_exists(path_jpg): DirAccess.remove_absolute(path_jpg)
			if FileAccess.file_exists(path_webp): DirAccess.remove_absolute(path_webp)
				
			var file_write = FileAccess.open(target_thumb_path, FileAccess.WRITE)
			if file_write:
				file_write.store_buffer(thumb_bytes)
				file_write.close()
	else:
		var target_jpg_path = "user://save_slot_" + str(slot_idx) + ".jpg"
		var target_webp_path = "user://save_slot_" + str(slot_idx) + ".webp"
		if FileAccess.file_exists(target_png_path):
			DirAccess.remove_absolute(target_png_path)
		if FileAccess.file_exists(target_jpg_path):
			DirAccess.remove_absolute(target_jpg_path)
		if FileAccess.file_exists(target_webp_path):
			DirAccess.remove_absolute(target_webp_path)
			
	AnalyticsManager.log_event("world_imported", {})
	show_modal_message(
		tr("import_btn_ui"),
		tr("import_success").format([file_path.get_file().left(file_path.get_file().length() - 4)])
	)
	setup_save_ui()
