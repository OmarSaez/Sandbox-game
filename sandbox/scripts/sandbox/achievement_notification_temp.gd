func _show_achievement_notification(title: String):
	var s = _get_ui_scale()
	
	# 1. PRE-SEQUENCE: Scroll to button
	if not is_achievement_menu_unlocked:
		_trigger_achievement_reveal()
		await get_tree().create_timer(1.2).timeout
	else:
		var scroll_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		scroll_tween.tween_property(action_scroll, "scroll_horizontal", 2000, 1.0)
		await scroll_tween.finished
	
	# 2. ORIGIN & TARGET CALCULATIONS
	var origin_pos = Vector2(get_viewport_rect().size.x - 80 * s, get_viewport_rect().size.y - 40 * s)
	if is_instance_valid(achievement_btn):
		origin_pos = achievement_btn.global_position + achievement_btn.size / 2.0
	
	var toast_layer = CanvasLayer.new()
	toast_layer.layer = 100
	ui_root.add_child(toast_layer)
	
	# --- 3. THE ICON (Leading Edge) ---
	var icon_container = Control.new()
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(icon_container)
	
	var icon_tex = TextureRect.new()
	icon_tex.texture = load("res://assets/icon_game/icono_google_sandbox.png")
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.custom_minimum_size = Vector2(50 * s, 50 * s)
	icon_tex.position = -icon_tex.custom_minimum_size / 2.0
	icon_container.add_child(icon_tex)
	
	# --- 4. THE MASK & STATIC CONTENT ---
	# Calculate final width
	var label_measure = Label.new()
	label_measure.text = title.to_upper()
	label_measure.add_theme_font_size_override("font_size", 16 * s)
	var final_w = label_measure.get_minimum_size().x + 85 * s
	label_measure.queue_free()
	
	var mask = Control.new()
	mask.clip_contents = true
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(mask)
	toast_layer.move_child(mask, 0) # Behind icon
	
	# This container stays STILL relative to the screen (revealed by the mask)
	var static_content = Control.new()
	static_content.size = Vector2(final_w, 50 * s)
	mask.add_child(static_content)
	
	var bg = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.95)
	style.set_corner_radius_all(0)
	style.border_width_left = 2; style.border_width_top = 2
	style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color("#D4AF37")
	bg.add_theme_stylebox_override("panel", style)
	bg.size = static_content.size
	static_content.add_child(bg)
	
	var label = Label.new()
	label.text = title.to_upper()
	label.add_theme_font_size_override("font_size", 16 * s)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(65 * s, 15 * s)
	static_content.add_child(label)
	
	# Initial Positions
	var target_y = origin_pos.y - 120 * s
	var origin_x_right = origin_pos.x + 25 * s
	
	icon_container.global_position = origin_pos
	icon_container.scale = Vector2.ZERO
	icon_container.modulate.a = 0
	
	mask.visible = false
	mask.size = Vector2(0, 50 * s)
	mask.global_position = Vector2(origin_x_right, target_y - 25 * s)
	
	# --- 5. ANIMATION CORE ---
	var t = create_tween().set_parallel(false).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# PHASE 1: Pop Icon
	_play_action_sound("ui_pop")
	t.parallel().tween_property(icon_container, "scale", Vector2.ONE, 0.5)
	t.parallel().tween_property(icon_container, "modulate:a", 1.0, 0.3)
	t.parallel().tween_property(icon_container, "global_position:y", target_y, 0.6)
	
	t.tween_interval(0.2)
	
	# PHASE 2: The "Window" Reveal
	t.tween_callback(func(): mask.visible = true)
	t.set_parallel(true).set_trans(Tween.TRANS_EXPO)
	
	# Icon slides left
	t.tween_property(icon_container, "global_position:x", origin_x_right - final_w + 25 * s, 0.8)
	
	# Mask expands left
	t.tween_property(mask, "global_position:x", origin_x_right - final_w, 0.8)
	t.tween_property(mask, "size:x", final_w, 0.8)
	
	# COMPENSATE: static_content looks immobile by counter-moving locally
	t.tween_property(static_content, "position:x", 0, 0.8).from(final_w)
	
	# PHASE 3: Exit
	t.set_parallel(false).set_trans(Tween.TRANS_SINE)
	t.tween_interval(2.5)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(icon_container, "global_position:y", get_viewport_rect().size.y + 100 * s, 0.6)
	t.parallel().tween_property(mask, "global_position:y", get_viewport_rect().size.y + 100 * s, 0.6)
	t.parallel().tween_property(icon_container, "modulate:a", 0.0, 0.4)
	t.parallel().tween_property(mask, "modulate:a", 0.0, 0.4)
	t.tween_callback(toast_layer.queue_free)

func _save_global_achievements():
