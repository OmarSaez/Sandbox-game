func _trigger_achievement_reveal():
	if is_achievement_menu_unlocked: return
	
	is_achievement_menu_unlocked = true
	_save_global_achievements()
	
	var s = _get_ui_scale()
	
	# 1. Action Buttons
	var achievement_btn = Button.new()
	achievement_btn.name = "AchievementButton"
	achievement_btn.custom_minimum_size = Vector2(100 * s, 45 * s)
	achievement_btn.modulate.a = 0
	achievement_btn.focus_mode = Control.FOCUS_NONE
	
	var gold_style = StyleBoxFlat.new()
	gold_style.bg_color = Color("#D4AF37")
	gold_style.set_corner_radius_all(0)
	
	achievement_btn.add_theme_stylebox_override("normal", gold_style)
	achievement_btn.add_theme_stylebox_override("hover", gold_style)
	achievement_btn.add_theme_stylebox_override("pressed", gold_style)
	action_hbox.add_child(achievement_btn)
	
	# 5. Animation
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(action_scroll, "scroll_horizontal", 2000, 1.5)
	
	var fade_tween = create_tween().bind_node(achievement_btn).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_interval(0.6)
	fade_tween.tween_property(achievement_btn, "modulate:a", 1.0, 0.8)
	
	fade_tween.tween_callback(func():
		var pulse = create_tween().set_loops().bind_node(achievement_btn)
		pulse.tween_property(achievement_btn, "modulate", Color(1.3, 1.3, 1.1, 1.0), 0.8)
		pulse.tween_property(achievement_btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)
	)
	
	_play_action_sound("ui_pop")

func _show_achievement_notification(title: String):
	var s = _get_ui_scale()
	var viewport_w = get_viewport_rect().size.x
	
	# 1. PRE-SEQUENCE
	if not is_achievement_menu_unlocked:
		_trigger_achievement_reveal()
		await get_tree().create_timer(1.2).timeout
	else:
		var scroll_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		scroll_tween.tween_property(action_scroll, "scroll_horizontal", 2000, 1.0)
		await scroll_tween.finished
	
	# 2. ORIGIN & SIZE
	var icon_size = 75 * s
	var origin_pos = Vector2(viewport_w - 100 * s, get_viewport_rect().size.y - 40 * s)
	if is_instance_valid(achievement_btn):
		origin_pos = achievement_btn.global_position + achievement_btn.size / 2.0
	
	var toast_layer = CanvasLayer.new()
	toast_layer.layer = 100
	ui_root.add_child(toast_layer)
	
	# --- 3. ICON ---
	var icon_container = Control.new()
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(icon_container)
	
	var icon_tex = TextureRect.new()
	icon_tex.texture = load("res://assets/icon_game/icono_google_sandbox.png")
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_tex.position = -icon_tex.custom_minimum_size / 2.0
	icon_container.add_child(icon_tex)
	
	# --- 4. MASK & STATIC CONTENT ---
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
	style.set_corner_radius_all(0)
	style.border_width_left = 3 * s; style.border_width_top = 3 * s
	style.border_width_right = 3 * s; style.border_width_bottom = 3 * s
	style.border_color = Color("#D4AF37")
	bg.add_theme_stylebox_override("panel", style)
	bg.size = static_content.size
	static_content.add_child(bg)
	
	var label = Label.new()
	label.text = title.to_upper()
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
	mask.global_position = Vector2(origin_x_right, target_y - icon_size/2.0)
	
	# --- 5. ANIMATION ---
	var t = create_tween().set_parallel(false).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Step 1: Pop Icon
	t.parallel().tween_property(icon_container, "scale", Vector2.ONE, 0.5)
	t.parallel().tween_property(icon_container, "modulate:a", 1.0, 0.3)
	t.parallel().tween_property(icon_container, "global_position:y", target_y, 0.6)
	_play_action_sound("ui_pop")
	
	t.tween_interval(0.2)
	t.tween_callback(func(): mask.visible = true)
	
	# Step 2: Unroll
	t.set_parallel(true).set_trans(Tween.TRANS_EXPO)
	t.tween_property(icon_container, "global_position:x", target_x + icon_size/2.0, 1.0)
	t.tween_property(mask, "global_position:x", target_x, 1.0)
	t.tween_property(mask, "size:x", final_w, 1.0)
	t.tween_property(static_content, "position:x", 0, 1.0).from(final_w)
	
	# Step 3: THE HOLD (Now fixed)
	t.set_parallel(false) # Disable parallel for the wait!
	t.set_trans(Tween.TRANS_SINE)
	t.tween_interval(8.0) # Wait 8 seconds fully extended
	
	# Step 4: Exit
	t.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(icon_container, "global_position:y", get_viewport_rect().size.y + 200 * s, 0.8)
	t.tween_property(mask, "global_position:y", get_viewport_rect().size.y + 200 * s, 0.8)
	t.tween_property(icon_container, "modulate:a", 0.0, 0.5)
	t.tween_property(mask, "modulate:a", 0.0, 0.5)
	t.tween_callback(toast_layer.queue_free)

func _save_global_achievements():
