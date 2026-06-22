extends SandboxGridNode
class_name SandboxGrid

# Grid config
@export var grid_scale: int = 8
var grid_width: int
var grid_height: int
var dynamic_grid_height: int # Logic floor (at HUD top)

# --- CUSTOM NPC COLORS (Editable in Inspector) ---
@export_group("NPC Visuals")
@export var npc_color_acid: Color = Color("#7ae267ff")  # Neon Green
@export var npc_color_fire: Color = Color("#FF4500")  # Orange-Red
@export var npc_color_exp: Color = Color("#FFFFFF")   # White
@export var npc_color_hit: Color = Color("#db2525ff")   # Normal Hit Red
@export var npc_color_death: Color = Color("#5c0000ff") # Dark Agony Red


# Simulation Data
var cells: PackedInt32Array
var tags_array: PackedInt64Array
var color_buffer: PackedByteArray 
var charge_array: PackedInt32Array # Track electric pulses and explosion flags
var charge_visual_buffer: PackedByteArray # 8-bit buffer for GPU rendering

# GPU Rendering Data (Primary: ID Texture | Secondary: Charge Texture)
var charge_tex: ImageTexture 
var background_img: Image
var background_tex: ImageTexture
var background_dirty: bool = false
var element_paint_img: Image
var element_paint_tex: ImageTexture
var element_paint_dirty: bool = false
var charge_dirty: bool = false
var cell_paint_colors: PackedInt32Array # Stores per-pixel custom color (ABGR32)
var charge_img: Image

# Simulation Chunking
const CHUNK_SIZE = 16
const MAX_PIXELS_PER_FRAME = 300000 
const BASE_FRAME_RATE = 60
const LIQUID_SPREAD_LIMIT = 5
const UPDATE_CHUNK_SIZE = 16
const UPDATE_CHUNK_SIZE_SQ = 256
const SIMULATION_STEP = 1.0 / 60.0

const EXP_VOLCANO = 1048576

# UI AND RENDERING
var g_scale: float = 8.0
var chunks_active: PackedByteArray 
var next_chunks_active: PackedByteArray
var chunks_x: int
var chunks_y: int

# Pre-calculated visual data
var material_colors_bytes = PackedByteArray() # RGBA bytes for each material

# Material data mapping
var mat_colors_1 = PackedColorArray()
var mat_colors_2 = PackedColorArray()
var mat_colors_3 = PackedColorArray()
var material_tags_raw = PackedInt64Array() 
var selected_material: int = 1
var current_weather: int = 0 
var is_paused: bool = false
var is_unpausing: bool = false
# UI State
var is_mouse_over_ui: bool = false
var brush_radius: int = 2 
var current_language: String = "es" # Controlled by TranslationServer
var ui_scale_level: int = 4 # Fixed at 1.7x (index 4 of the old scales array)
var sim_camera: Camera2D
var view_zoom: float = 1.0
var is_panning_mode: bool = false
var active_touches = {}
var pinch_last_dist: float = 0.0
var cam_min_x: int = 0
var cam_max_x: int = 9999
var cam_min_y: int = 0
var cam_max_y: int = 9999

var _cached_top_semanal_doc = null
var _cached_recientes_doc = null
var top_countdown_label: Label = null
var bot_countdown_label: Label = null
var top_downloads_count_label: Label = null

var free_downloads_remaining: int = 1
var uploads_today: int = 0
var last_upload_day: int = 0
var liked_worlds: Array = []
var reported_worlds: Array = []

func _load_workshop_economy():
	var cfg = ConfigFile.new()
	if cfg.load("user://workshop_economy.cfg") == OK:
		var old_free = cfg.get_value("economy", "next_download_is_free", true)
		free_downloads_remaining = cfg.get_value("economy", "free_downloads_remaining", 1 if old_free else 0)
		uploads_today = cfg.get_value("economy", "uploads_today", 0)
		last_upload_day = cfg.get_value("economy", "last_upload_day", 0)
		liked_worlds = cfg.get_value("economy", "liked_worlds", [])
		reported_worlds = cfg.get_value("economy", "reported_worlds", [])

func _save_workshop_economy():
	var cfg = ConfigFile.new()
	cfg.set_value("economy", "free_downloads_remaining", free_downloads_remaining)
	cfg.set_value("economy", "uploads_today", uploads_today)
	cfg.set_value("economy", "last_upload_day", last_upload_day)
	cfg.set_value("economy", "liked_worlds", liked_worlds)
	cfg.set_value("economy", "reported_worlds", reported_worlds)
	cfg.save("user://workshop_economy.cfg")

func _get_next_update_unix(is_historico: bool = false) -> int:
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

func _get_last_update_unix(is_historico: bool = false) -> int:
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

func _update_day_check():
	var current_day = Time.get_date_dict_from_system().day
	if last_upload_day != current_day:
		uploads_today = 0
		free_downloads_remaining = 1
		last_upload_day = current_day
		_save_workshop_economy()

func _update_zoom_ui():
	if not ui_elements.has("btn_pan") or not is_instance_valid(ui_elements["btn_pan"]):
		return
	var btn = ui_elements["btn_pan"]
	var s = _get_ui_scale()
	
	var vbox = btn.get_node_or_null("ZoomVBox")
	if not vbox:
		vbox = VBoxContainer.new()
		vbox.name = "ZoomVBox"
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(vbox)
		
		# Set comfortable spacing between the magnifier icon and the percentage text
		vbox.add_theme_constant_override("separation", int(2 * s))
		
		@warning_ignore("confusable_local_declaration")
		var lbl_icon = Label.new()
		lbl_icon.name = "IconLabel"
		lbl_icon.text = "🔍"
		lbl_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl_icon.add_theme_font_override("font", _get_safe_font())
		vbox.add_child(lbl_icon)
		
		@warning_ignore("confusable_local_declaration")
		var lbl_pct = Label.new()
		lbl_pct.name = "PctLabel"
		lbl_pct.text = ""
		lbl_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl_pct.add_theme_font_override("font", _get_safe_font())
		vbox.add_child(lbl_pct)
		
	var lbl_icon = vbox.get_node("IconLabel")
	var lbl_pct = vbox.get_node("PctLabel")
	
	btn.text = "" # Keep main button text empty to prevent double drawing
	
	if view_zoom <= 1.01:
		lbl_pct.visible = false
		lbl_icon.add_theme_font_size_override("font_size", 26 * s)
	else:
		var pct = int(round(view_zoom * 100.0))
		lbl_pct.text = "%d%%" % pct
		lbl_pct.visible = true
		
		# High-contrast bold styling with white text on dark background
		lbl_pct.add_theme_font_size_override("font_size", 18 * s)
		lbl_pct.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0)) # Pure white text
		
		var outline_color = Color(0.04, 0.12, 0.28, 1.0) if is_panning_mode else Color(0.05, 0.05, 0.08, 1.0)
		lbl_pct.add_theme_color_override("font_outline_color", outline_color)
		lbl_pct.add_theme_constant_override("outline_size", int(4 * s)) # Thick outline for simulated bolding
		
		lbl_icon.add_theme_font_size_override("font_size", 22 * s)

func _zoom_camera(delta_zoom: float):
	view_zoom = clamp(view_zoom + delta_zoom, 1.0, 4.0)
	if is_instance_valid(sim_camera):
		sim_camera.zoom = Vector2(view_zoom, view_zoom)
		_clamp_camera_position()
	_update_zoom_ui()

func _set_panning_mode(active: bool):
	is_panning_mode = active
	if not active:
		active_touches.clear()
		pinch_last_dist = 0.0
		if is_instance_valid(zoom_tutorial_bubble):
			zoom_tutorial_bubble.queue_free()
		
	if ui_elements.has("btn_pan") and is_instance_valid(ui_elements["btn_pan"]):
		var qa_style = StyleBoxFlat.new()
		qa_style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
		qa_style.border_width_left = 1; qa_style.border_width_top = 1
		qa_style.border_width_right = 1; qa_style.border_width_bottom = 1
		qa_style.border_color = Color(0.4, 0.4, 0.5)

		var qa_style_active = qa_style.duplicate()
		qa_style_active.bg_color = Color(0.12, 0.32, 0.62, 1.0) # Premium dark royal blue
		
		var style = qa_style_active if is_panning_mode else qa_style
		var btn = ui_elements["btn_pan"]
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		_update_zoom_ui()
		
	if active and not is_zoom_tutorial_done:
		call_deferred("_show_zoom_tutorial_bubble")

func _clamp_camera_position():
	if not is_instance_valid(sim_camera): return
	var vp = get_viewport_rect().size
	if view_zoom <= 1.0:
		sim_camera.position = vp / 2.0
		return
		
	var map_w = grid_width * grid_scale
	var map_h = grid_height * grid_scale
	var half_cam_w = (vp.x / view_zoom) / 2.0
	var half_cam_h = (vp.y / view_zoom) / 2.0
	
	var new_pos = sim_camera.position
	new_pos.x = clamp(new_pos.x, half_cam_w, max(half_cam_w, map_w - half_cam_w))
	new_pos.y = clamp(new_pos.y, half_cam_h, max(half_cam_h, map_h - half_cam_h))
	sim_camera.position = new_pos

func _show_zoom_tutorial_bubble():
	if is_instance_valid(zoom_tutorial_bubble):
		zoom_tutorial_bubble.queue_free()
		
	if not is_instance_valid(ui_root):
		ui_root = get_parent().get_node_or_null("UI")
		if not ui_root: return
		
	var s = _get_ui_scale()
	var btn = ui_elements.get("btn_pan")
	if not is_instance_valid(btn): return
	
	# Create panel container
	var bubble = PanelContainer.new()
	zoom_tutorial_bubble = bubble
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Styling: Glassmorphism look matching the other tutorials
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.12, 0.96) # Dark slate semi-transparent
	p_style.set_corner_radius_all(18 * s)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color(0.12, 0.32, 0.62, 0.95) # Royal blue matching active panning mode
	p_style.shadow_color = Color(0, 0, 0, 0.45)
	p_style.shadow_size = 10
	bubble.add_theme_stylebox_override("panel", p_style)
	
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_theme_constant_override("margin_left", 24 * s)
	margin.add_theme_constant_override("margin_top", 20 * s)
	margin.add_theme_constant_override("margin_right", 24 * s)
	margin.add_theme_constant_override("margin_bottom", 20 * s)
	bubble.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_theme_constant_override("separation", 14 * s)
	margin.add_child(vbox)
	
	# Title
	var title_lbl = Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	title_lbl.text = tr("tut_zoom_title")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(360 * s, 0)
	title_lbl.add_theme_font_override("font", _get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", 24 * s)
	title_lbl.add_theme_color_override("font_color", Color(0.35, 0.65, 1.0, 1.0)) # Sky blue accent
	vbox.add_child(title_lbl)
	
	# Step 1: Zoom
	var step1_lbl = Label.new()
	step1_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	step1_lbl.text = tr("tut_zoom_step1")
	step1_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	step1_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step1_lbl.custom_minimum_size = Vector2(360 * s, 0)
	step1_lbl.add_theme_font_override("font", _get_safe_font())
	step1_lbl.add_theme_font_size_override("font_size", 20 * s)
	step1_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(step1_lbl)
	
	# Step 2: Move
	var step2_lbl = Label.new()
	step2_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	step2_lbl.text = tr("tut_zoom_step2")
	step2_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	step2_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step2_lbl.custom_minimum_size = Vector2(360 * s, 0)
	step2_lbl.add_theme_font_override("font", _get_safe_font())
	step2_lbl.add_theme_font_size_override("font_size", 20 * s)
	step2_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(step2_lbl)
	
	# Button Ok
	var btn_ok = Button.new()
	btn_ok.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_ok.text = tr("GOT_IT")
	btn_ok.custom_minimum_size = Vector2(170 * s, 54 * s)
	btn_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_ok.add_theme_font_override("font", _get_safe_font())
	btn_ok.add_theme_font_size_override("font_size", 21 * s)
	
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
		_save_tool_settings()
		bubble.queue_free()
	)
	vbox.add_child(btn_ok)
	
	ui_root.add_child(bubble)
	
	# Position bubble above/left of the pan button
	var btn_global_rect = btn.get_global_rect()
	var screen_pos = btn_global_rect.position
	
	# Position above the button, centered horizontally relative to the button
	bubble.position = Vector2(screen_pos.x + btn_global_rect.size.x/2 - 200 * s, screen_pos.y - 300 * s)
	bubble.position.x = clamp(bubble.position.x, 10 * s, get_viewport_rect().size.x - 420 * s)
	bubble.position.y = clamp(bubble.position.y, 10 * s, get_viewport_rect().size.y - 320 * s)

func _setup_long_press_tooltip(btn: Button, translation_key: String):
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.5
	btn.add_child(timer)
	
	btn.button_down.connect(func():
		btn.set_meta("long_pressed", false)
		timer.start()
	)
	
	var cleanup = func():
		timer.stop()
		if is_instance_valid(active_tooltip_panel):
			active_tooltip_panel.queue_free()
			active_tooltip_panel = null
		btn.call_deferred("set_meta", "long_pressed", false)
			
	btn.button_up.connect(cleanup)
	btn.mouse_exited.connect(cleanup)
	
	timer.timeout.connect(func():
		if not btn.is_pressed(): return
		btn.set_meta("long_pressed", true)
		_show_button_tooltip(btn, translation_key)
	)

func _show_button_tooltip(btn: Button, translation_key: String):
	if is_instance_valid(active_tooltip_panel):
		active_tooltip_panel.queue_free()
		
	if not is_instance_valid(ui_root):
		ui_root = get_parent().get_node_or_null("UI")
		if not ui_root: return
		
	var s = _get_ui_scale()
	
	var bubble = PanelContainer.new()
	active_tooltip_panel = bubble
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	p_style.set_corner_radius_all(10 * s)
	p_style.border_width_left = 2; p_style.border_width_top = 2
	p_style.border_width_right = 2; p_style.border_width_bottom = 2
	p_style.border_color = Color(0.35, 0.65, 1.0, 0.95)
	p_style.shadow_color = Color(0, 0, 0, 0.35)
	p_style.shadow_size = 6
	bubble.add_theme_stylebox_override("panel", p_style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14 * s)
	margin.add_theme_constant_override("margin_top", 8 * s)
	margin.add_theme_constant_override("margin_right", 14 * s)
	margin.add_theme_constant_override("margin_bottom", 8 * s)
	bubble.add_child(margin)
	
	var lbl = Label.new()
	lbl.text = tr(translation_key)
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_font_size_override("font_size", 20 * s)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(lbl)
	
	ui_root.add_child(bubble)
	
	# Wait 1 frame for size calculation
	await get_tree().process_frame
	if not is_instance_valid(bubble) or not is_instance_valid(btn): return
	
	var btn_rect = btn.get_global_rect()
	bubble.position = Vector2(
		btn_rect.position.x + btn_rect.size.x / 2.0 - bubble.size.x / 2.0,
		btn_rect.position.y - bubble.size.y - 12 * s
	)
	
	bubble.position.x = clamp(bubble.position.x, 10 * s, get_viewport_rect().size.x - bubble.size.x - 10 * s)
	bubble.position.y = clamp(bubble.position.y, 10 * s, get_viewport_rect().size.y - bubble.size.y - 10 * s)

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		# Mouse Wheel Zoom (PC)
		if is_panning_mode:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_zoom_camera(0.15)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_zoom_camera(-0.15)
				get_viewport().set_input_as_handled()
			
	elif event is InputEventScreenTouch:
		if is_panning_mode:
			var is_over_ui = _is_position_over_ui(event.position)
			if event.pressed:
				if not is_over_ui:
					active_touches[event.index] = event.position
			else:
				active_touches.erase(event.index)
				
			if active_touches.size() == 2:
				# Start pinch
				var keys = active_touches.keys()
				pinch_last_dist = active_touches[keys[0]].distance_to(active_touches[keys[1]])
			else:
				pinch_last_dist = 0.0
				
			if not is_over_ui:
				get_viewport().set_input_as_handled()
				
	elif event is InputEventScreenDrag:
		if is_panning_mode:
			var is_over_ui = _is_position_over_ui(event.position)
			if active_touches.has(event.index):
				active_touches[event.index] = event.position
				
			if active_touches.size() == 2:
				# 2-finger pinch zoom
				var keys = active_touches.keys()
				var pos1 = active_touches[keys[0]]
				var pos2 = active_touches[keys[1]]
				var current_dist = pos1.distance_to(pos2)
				
				if pinch_last_dist > 0.0:
					var ratio = current_dist / pinch_last_dist
					var target_zoom = clamp(view_zoom * ratio, 1.0, 4.0)
					if target_zoom != view_zoom:
						view_zoom = target_zoom
						if is_instance_valid(sim_camera):
							sim_camera.zoom = Vector2(view_zoom, view_zoom)
							_clamp_camera_position()
						_update_zoom_ui()
				pinch_last_dist = current_dist
				if not is_over_ui:
					get_viewport().set_input_as_handled()
			elif active_touches.size() == 1 and not is_over_ui:
				# 1-finger pan
				if is_instance_valid(sim_camera):
					sim_camera.position -= event.relative / view_zoom
					_clamp_camera_position()
				get_viewport().set_input_as_handled()
				
	elif event is InputEventMouseMotion:
		if is_panning_mode and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var is_over_ui = _is_any_ui_blocking()
			if not is_over_ui and not touch_started_on_ui:
				if is_instance_valid(sim_camera):
					sim_camera.position -= event.relative / view_zoom
					_clamp_camera_position()
				get_viewport().set_input_as_handled()

func _get_ui_scale() -> float:
	var base_scale = 1.7
	
	if is_inside_tree():
		var vp_size = get_viewport_rect().size
		if vp_size.x > vp_size.y:
			return base_scale * 1.30 # Multiplicador de escala en modo horizontal (Total ~2.2x)
			
	return base_scale

var ui_elements = {} # To track nodes for re-labeling
var tools_panel: PanelContainer
var workshop_panel: PanelContainer
var lab_panel: PanelContainer
var lab_selected_slot: int = 0
var lab_custom_data = [
	{"c1": Color(0, 0, 0, 0), "c2": Color(0, 0, 0, 0), "c3": Color(0, 0, 0, 0), "mix": 1, "grav": 1, "state": 3, "tags": {}, "name": ""},
	{"c1": Color(0, 0, 0, 0), "c2": Color(0, 0, 0, 0), "c3": Color(0, 0, 0, 0), "mix": 1, "grav": 1, "state": 3, "tags": {}, "name": ""},
	{"c1": Color(0, 0, 0, 0), "c2": Color(0, 0, 0, 0), "c3": Color(0, 0, 0, 0), "mix": 1, "grav": 1, "state": 3, "tags": {}, "name": ""}
]
var is_lab_unlocked: bool = false
var lab_unlock_expiry_unix: int = 0
var disaster_panel: PanelContainer
var npc_panel: PanelContainer
var achievement_panel: PanelContainer
var paint_panel: PanelContainer
var selected_team: int = 0 
var mat_id_to_key = {} # ID -> Translation Key
var controlled_npc = null
var is_selecting_npc_to_control: bool = false
var npc_control_gui: Control
var main_controls: Control
var ui_root: CanvasLayer
var mouse_was_pressed: bool = false
var music_tempo_frames: int = 30
var is_blocking: bool = false
var force_grid_visible: bool = false

# History / Undo System
var history_buffer = [] # Array of PackedInt32Array
var history_max_steps: int = 6 # Store 6 snapshots to allow 5 undo steps
var history_current_index: int = -1

var is_grid_ready: bool = false # Guard against async _ready running early loops
var current_is_landscape: bool = false # Tracks axis state to auto-reload on flip
var current_orientation_setting: int = 0 # 0: Auto, 1: Portrait, 2: Landscape

# Save / Load System
var save_panel: PanelContainer
var save_slots_data = {} # slot_index -> { "name": string, "date": string, "thumbnail": ImageTexture }

# --- MUSIC SYSTEM (NEW) ---
var selected_music_instrument: int = 0
var selected_music_octave: int = 2
var show_music_notes_popup: bool = true
var music_inspect_active: bool = false
var music_inspect_timer: float = 0.0
var pending_music_draw_pos: Vector2i = Vector2i(-1, -1)
var played_music_this_frame = {}
var music_block_cooldowns = {}
var selected_music_note: int = 0
var music_player_pool: Array[AudioStreamPlayer] = []
var music_next_idx: int = 0
var music_panel: PanelContainer
var selected_mechanism_tab: int = 0 # 0: Circuits, 1: Music
var circuit_panel: PanelContainer
var cannon_settings_panel: PanelContainer
var is_mechanism_mode_active: bool = false
var selected_circuit_tool: String = "wire"

var is_hollowing_pipe: bool = false
var active_logic_gates: Array = []
var active_pistons: Array = []
var selected_piston_length: int = 10
var is_piston_insulated: bool = false
var selected_led_color: int = 0 # 0=Red, 1=Blue, 2=Green, 3=Yellow, 4=White, 5=Pink, 6=Celeste, 7=Rainbow
var active_pipes: Array = []
var active_pipes_x2: Array = []
var prev_pipe_gx: int = -1
var prev_pipe_gy: int = -1
var active_cannons: Array = []
var current_drawing_pipe_path: Array = []
var active_battery_indices = {} # Set of cell indices containing battery blocks
var active_electricity_source_indices = {} # Set of cell indices containing electricity
var door_registry = {} # Set of cell indices where NPC Door (91) is placed
var door_close_timers = {} # cell_idx -> float close delay timer
var is_npc_door_updating: bool = false
var is_pipe_dirty: bool = false
var phase_block_registry = {} # Set of cell indices where Phase Block (92) is placed
var is_phase_block_updating: bool = false
var is_phase_block_tutorial_done: bool = false
var phase_block_tutorial_bubble: PanelContainer = null
var is_logic_gate_tutorial_done: bool = false
var is_grid_tutorial_done: bool = false
var logic_gate_tutorial_bubble: PanelContainer = null
var is_zoom_tutorial_done: bool = false
var zoom_tutorial_bubble: PanelContainer = null
var is_cannon_tutorial_done: bool = false
var cannon_tutorial_bubble: PanelContainer = null
var is_piston_tutorial_done: bool = false
var piston_tutorial_bubble: PanelContainer = null
var led_color_panel: PanelContainer = null
const CANNON_POWER_MIN = 0.4
const CANNON_POWER_MED = 0.7
const CANNON_POWER_MAX = 1.25
var active_tooltip_panel: PanelContainer = null
var draw_start_gx: int = 0
var draw_start_gy: int = 0
var prev_snapped_gx: int = 0
var prev_snapped_gy: int = 0
const MUSIC_ID_START = 500
const MUSIC_INSTRUMENTS = ["piano1", "piano2", "piano3", "piano4", "drums", "metronome"]
const MUSIC_INST_COLORS = [
	Color("#D652FF"), # Purple
	Color("#5E7FFF"), # Blue
	Color("#C0B8FF"), # Cyan
	Color("#1FDDFF"), # Space Piano (Violet)
	Color("#FFC31F"), # Yellow
	Color("#E0BB87")  # Neon Cyan
]
const MUSIC_NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const MUSIC_NOTES_LATIN = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]
const MUSIC_PITCHES = [1.0, 1.05946, 1.12246, 1.18921, 1.25992, 1.33483, 1.41421, 1.49831, 1.58740, 1.68179, 1.78180, 1.88775]

# --- PAINT SYSTEM ---
var selected_paint_color: Color = Color.WHITE
var paint_mode: int = 0 # 0: Elements, 1: Background
var recent_paint_colors: Array[Color] = [Color.WHITE, Color.BLACK, Color.GRAY, Color.RED, Color.GREEN, Color.BLUE]
var paint_brush_radius_idx: int = 2 # Index for [1, 3, 5, 10, 15, 25]
var is_paint_tool_active: bool = false

@export var custom_emoji_font: Font 

var _combined_font: FontVariation 

func _get_safe_font() -> Font:
	if not _combined_font:
		_combined_font = FontVariation.new()
		
		# 1. FUENTE BASE (Texto estándar)
		var base_font = SystemFont.new()
		base_font.font_names = PackedStringArray(["sans-serif", "arial"])
		_combined_font.base_font = base_font
		
		# 2. FUENTE DE ICONOS (La que tú elijas en el Inspector)
		var emoji_f: Font = custom_emoji_font
		
		# Si no has puesto nada en el inspector, intenta buscar la carpeta por defecto
		if not emoji_f:
			var paths = [
				"res://assets/fonts/Twemoji.Mozilla.ttf",
				"res://assets/fonts/Twemoji.ttf",
				"res://assets/fonts/NotoColorEmoji.ttf",
				"res://assets/fonts/FluentEmoji.ttf"
			]
			for p in paths:
				if ResourceLoader.exists(p):
					emoji_f = load(p)
					break
		
		# 3. ÚLTIMO RECURSO: Sistema
		if not emoji_f:
			emoji_f = SystemFont.new()
			emoji_f.font_names = PackedStringArray(["Emoji", "ColorEmoji", "Noto Color Emoji"])
			emoji_f.multichannel_signed_distance_field = false
			
		if emoji_f:
			_combined_font.set_fallbacks([emoji_f])
			
	return _combined_font
var touch_started_on_ui: bool = false # NEW: Track if the touch session began over UI
var sim_mutex := Mutex.new() # Protects global arrays from parallel threads
var active_npcs = [] # Array of dicts: { "pos": Vector2i, "team": int, "dir": int, "type": string, "hp": float, etc }
var _cached_has_zombies: bool = false
var _world_peace_timer = 0.0 # Track global inactivity for sleeping NPCs
const SPATIAL_CELL_SIZE = 32
var npc_spatial_grid = [] 
var spatial_grid_w = 0
var spatial_grid_h = 0
var active_projectiles = [] # { pos: Vector2, vel: Vector2, team: int, type: string }
var npc_update_timer: float = 0.0
var sfx_pool: Array[AudioStreamPlayer] = []
var next_sfx_idx: int = 0
var brush_player: AudioStreamPlayer # Dedicated for looping placement
var weather_player: AudioStreamPlayer # Dedicated for rain/storm loop
var quake_player: AudioStreamPlayer
var tornado_player: AudioStreamPlayer
var tsunami_player: AudioStreamPlayer
var firework_player: AudioStreamPlayer # Dedicated for rocket fuse
var ascent_player: AudioStreamPlayer   # Dedicated for rocket flying up
var volcano_loop_player: AudioStreamPlayer # Dedicated for volcano bubbling loop
var fire_loop_player: AudioStreamPlayer    # Dedicated for global crackling/burning
const SFX_POOL_SIZE = 32
var action_btn_font_size: int = 16 # Unified size for main ActionButtons (Shrunk for space)

# Mapeo: ID del Material -> Nombre del archivo (SONIDO EN BUCLE / LOOP) MP3
# Estos sonidos se repiten mientras mantienes el pincel presionado.
var material_sfx = {
	1: "sand",      # Arena
	2: "water",     # Agua
	3: "fire",      # Fuego
	4: "oil",       # Petróleo
	5: "tnt",       # TNT
	6: "earth",     # Tierra
	30: "stone",    # Piedra
	8: "metal",     # Metal
	9: "elec",      # Electricidad
	10: "gravel",   # Grava
	11: "lava",     # Lava
	12: "obsidian", # Obsidiana
	13: "acid",     # Ácido
	14: "coal",     # Carbón / Brazas (pincel)
	16: "wood",     # Madera
	18: "fireworks",# Cohetes (pincel)
	19: "fuse",      # Cohete encendido (subida)
	20: "sand",     # Pólvora (Gunpowder)
	21: "grass",    # Pasto
	24: "vine",     # Liana
	25: "cem_fresh",# Cemento fresco
	26: "cement",   # Cemento sólido
	27: "volcan_brush", # Pincel del volcán
	29: "volcan_active", # Base activa (burbujeo)
	70: "ice"       # Hielo
}

# Mapeo: Nombre de Acción -> Nombre del archivo (UNA SOLA VEZ / ONE-SHOT) WAV
# Estos sonidos suenan una sola vez cuando ocurre el evento.
var action_sfx = {
	"npc_hit": "hit",             # Cuando un NPC recibe daño normal (armas)
	"damage_npc": "damage_npc",   # Daño de entorno (fuego, ácido, explosivo, asfixia)
	"npc_death": "death",         # Cuando un NPC muere
	"npc_place": "spawn",         # Al colocar un NPC en el mapa
	"explosion": "explode",       # Detonación de TNT o Volcán
	"lightning": "lightning",     # Impacto de rayo (clima)
	"lightning_user": "lightning_user", # Rayo manual del usuario (volumen reducido)
	"earthquake": "quake",        # Inicio de Terremoto
	"tornado": "tornado",         # Inicio de Tornado
	"tsunami": "tsunami",         # Inicio de Tsunami
	"bomb_drop": "bomb_drop",     # Sonido de bomba cayendo
	"bomber_engine": "bomber_engine", # Sonido de motor de avión
	"ui_click": "click",          # Al pulsar botones de la interfaz
	"warrior_attack": "sword_swing", # Ataque de Guerrero
	"archer_shoot": "bow_shoot",     # Disparo de Arquero
	"miner_dig": "pickaxe_hit",      # Minero picando tierra
	"medic_heal": "medic_heal",      # SONIDO DEL MÉDICO
	"zombie_attack": "zombie_attack", # Ataque y gruñido de Zombie
	"zombie_tank_throw": "zombie_tank_attack", # Lanzar bloque (audio actual)
	"zombie_tank_melee": "zombie_tank_melee", # Ataque melee de cerca (audio nuevo)
	"mage_shoot": "rocket_launch", # Disparo de Mago
	"mage_rescue": "mage_rescue", # Sonido de Mago rescatando aliado
	
	# Sonidos Continuos de Clima / Desastres (LOOP EN TIEMPO REAL) MP3
	"weather_1": "rain_light",
	"weather_2": "rain_med",
	"weather_3": "rain_storm",
	"quake_loop": "quake_loop",
	"tornado_loop": "tornado_loop",
	"firework_launch": "rocket_launch",
	"firework_ascent": "rocket_launch_ascent",
	"firework_burst": "firework_explode", # Sonido de explosión de colores en el aire
	"fuse_burning": "fuse",
	
	# --- SISTEMA SIMPLIFICADO DEL VOLCÁN ---
	"volcan_brush": "volcan",          # (PINCEL) Sonido al dibujar
	"volcan_active": "volcan_bubbles", # (LOOP) Burbujeo constante cuando el volcán funciona
	"volcan_burst": "volcan_explode",   # (ONE-SHOT) Pequeños estallidos de lava
	"burn_loop": "fire_crackle",        # (LOOP) Sonido de cosas quemándose (fuego, lava, carbón)
	"achievement_menu_unlock": "achievement_menu_unlock",
	"achievement_unlock": "achievement_unlock"
}

var last_action_times = {} # Para controlar la saturación de sonidos
var is_volcano_active = false 
var is_fire_active = false 
var is_npc_mode_menu_open: bool = false
var is_lab_tutorial_done: bool = false
var lab_tutorial_step: int = 0 # 0: None, 1: Slots, 2: Colors, 3: Gravity, 4: State, 5: Tags
var tutorial_rects: Array[Control] = []
var _frame_count = 0
var _npc_id_counter = 0
var active_metronome_indices = {} # Using Dictionary as a Set [index] -> true

const NPC_PROFILES = {
	"warrior": {
		"can_socialize": true,
		"can_sleep": true,
		"can_celebrate": true,
		"can_flee": true,
		"can_panic_disaster": true,
		"attack_sound": "warrior_attack",
		"hit_emoji": "⚔️"
	},
	"archer": {
		"can_socialize": true,
		"can_sleep": true,
		"can_celebrate": true,
		"can_flee": true,
		"can_panic_disaster": true,
		"attack_sound": "archer_shoot",
		"hit_emoji": "🏹"
	},
	"miner": {
		"can_socialize": true,
		"can_sleep": true,
		"can_celebrate": true,
		"can_flee": true,
		"can_panic_disaster": true,
		"attack_sound": "miner_dig",
		"hit_emoji": "⚒️"
	},
	"medic": {
		"can_socialize": true,
		"can_sleep": true,
		"can_celebrate": true,
		"can_flee": true,
		"can_panic_disaster": true,
		"attack_sound": "medic_heal",
		"hit_emoji": "💚"
	},
	"zombie": {
		"can_socialize": false,
		"can_sleep": false,
		"can_celebrate": false,
		"can_flee": false,
		"can_panic_disaster": false,
		"attack_sound": "zombie_attack",
		"hit_emoji": "🧟"
	},
	"zombie_tank": {
		"can_socialize": false,
		"can_sleep": false,
		"can_celebrate": false,
		"can_flee": false,
		"can_panic_disaster": false,
		"attack_sound": "zombie_tank_melee",
		"hit_emoji": "🧟"
	}
}

var sfx_cache = {} # Cache for loaded AudioStreams

# Localization system (Standard tr() calls)

# Earthquake settings
var earthquake_intensity: int = 0
var earthquake_timer: float = 0.0

# Tornado settings
var tornado_intensity: int = 0
var tornado_timer: float = 0.0
var tornado_x: float = 0.0
var tornado_target_x: float = 0.0
var tornado_ground_y: float = 0.0
var tornado_visual: ColorRect # Dedicated visual node for the triangle look
var tornado_element: int = 0 # 0: Dust, 1: Fire, 2: Acid, 3: Electric
var tornado_element_timer: float = 0.0
var tornado_absorb_fire: float = 0.0
var tornado_absorb_acid: float = 0.0
var tornado_absorb_elec: float = 0.0

# Tsunami settings
var tsunami_intensity: int = 0
var tsunami_timer: float = 0.0
var tsunami_wave_x: float = 0.0
var surface_cache = PackedInt32Array()

# Bomber settings
var bombardero_intensity: int = 0
var bombardero_x: float = 0.0
var bombardero_y: float = 12.0
var bombardero_dir: float = 1.0
var bombardero_speed: float = 0.0
var bombardero_drop_prob: float = 0.0
var bombardero_pending_checks: Array = []
var bombardero_player: AudioStreamPlayer
var bombardero_texture: Texture2D

# Future Disaster settings (Scalability)
# Future Disaster settings (Scalability)
var acid_rain_intensity: int = 0
var lava_rain_intensity: int = 0
var meteor_storm_intensity: int = 0
var black_hole_intensity: int = 0
var sinkhole_intensity: int = 0
var sand_storm_intensity: int = 0

# Fireworks tracking
var active_fireworks = [] 
# Optimization #3: High-Performance Particle Pool (Packed Data)
const MAX_VISUAL_SPARKS = 1500
var vs_x := PackedFloat32Array()
var vs_y := PackedFloat32Array()
var vs_vx := PackedFloat32Array()
var vs_vy := PackedFloat32Array()
var vs_color := PackedColorArray()
var vs_life := PackedFloat32Array()
var vs_ptr := 0

# Optimization #5: Random & Trig Look-Up Table (LUT)
const LUT_SIZE = 4096 # Larger for better variety
var random_lut := PackedFloat32Array()
var cos_lut := PackedFloat32Array()
var sin_lut := PackedFloat32Array()
var _lut_state := PackedInt32Array([0])
var _ai_tick_count: int = 0

func _get_lut_rand() -> float:
	_lut_state[0] = (_lut_state[0] + 1) & 4095
	return random_lut[_lut_state[0]]

func _get_lut_rand_range(from: float, to: float) -> float:
	return from + (to - from) * _get_lut_rand()

# Optimization #4: Sparse Electricity/Charge System
var active_charge_indices := PackedInt32Array()
var next_charge_indices := PackedInt32Array()
var charge_queued_frame := PackedInt32Array()
var powered_frame := PackedInt32Array()

# Display
@onready var texture_rect: TextureRect = $Display
var img: Image
var _img_history: Array = [] # Retains old images for 3 frames to avoid Android RenderThread crashes

# VOLUME SYSTEM
var game_volume: float = 1.2
var pre_mute_volume: float = 1.0
var is_muted: bool = false
var achievement_pulse_tween: Tween = null

# OPTIMIZATION TABLES
var oval_lookup_10x5: PackedInt32Array = []
var oval_lookup_20x10: PackedInt32Array = []
var oval_lookup_16x8: PackedInt32Array = []
var neighbor_offsets: PackedInt32Array = []

# INTERACTIVE TAGS MASK
const TAGS_INTERACTIVE = SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.FLAMMABLE | \
	SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.CONDUCTOR | \
	SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.PLANT | \
	SandboxMaterial.Tags.VIRUS | SandboxMaterial.Tags.RADIOACTIVE | SandboxMaterial.Tags.VORTEX | \
	SandboxMaterial.Tags.REPEL | SandboxMaterial.Tags.VOLATILE | SandboxMaterial.Tags.FERTILE | \
	SandboxMaterial.Tags.MUSIC

func _save_tool_settings():
	var settings = {
		"brush_radius": brush_radius,
		"paint_brush_radius_idx": paint_brush_radius_idx,
		"game_volume": game_volume,
		"is_muted": is_muted,
		"current_language": current_language,
		"show_music_notes_popup": show_music_notes_popup,
		"is_logic_gate_tutorial_done": is_logic_gate_tutorial_done,
		"is_grid_tutorial_done": is_grid_tutorial_done,
		"is_phase_block_tutorial_done": is_phase_block_tutorial_done,
		"is_zoom_tutorial_done": is_zoom_tutorial_done,
		"is_cannon_tutorial_done": is_cannon_tutorial_done,
		"is_piston_tutorial_done": is_piston_tutorial_done
	}
	var f = FileAccess.open("user://tools_settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func _load_tool_settings():
	if FileAccess.file_exists("user://tools_settings.json"):
		var f = FileAccess.open("user://tools_settings.json", FileAccess.READ)
		if f:
			var dict = JSON.parse_string(f.get_as_text())
			if typeof(dict) == TYPE_DICTIONARY:
				if dict.has("brush_radius"): brush_radius = dict["brush_radius"]
				if dict.has("paint_brush_radius_idx"): paint_brush_radius_idx = dict["paint_brush_radius_idx"]
				if dict.has("game_volume"): 
					game_volume = dict["game_volume"]
					_update_game_volume(game_volume)
				if dict.has("is_muted"): is_muted = dict["is_muted"]
				if dict.has("current_language"): 
					current_language = dict["current_language"]
					TranslationServer.set_locale(current_language)
				if dict.has("show_music_notes_popup"): show_music_notes_popup = dict["show_music_notes_popup"]
				if dict.has("is_logic_gate_tutorial_done"):
					is_logic_gate_tutorial_done = dict["is_logic_gate_tutorial_done"]
				if dict.has("is_grid_tutorial_done"):
					is_grid_tutorial_done = dict["is_grid_tutorial_done"]
				if dict.has("is_phase_block_tutorial_done"):
					is_phase_block_tutorial_done = dict["is_phase_block_tutorial_done"]
				if dict.has("is_zoom_tutorial_done"):
					is_zoom_tutorial_done = dict["is_zoom_tutorial_done"]
				if dict.has("is_cannon_tutorial_done"):
					is_cannon_tutorial_done = dict["is_cannon_tutorial_done"]
				if dict.has("is_piston_tutorial_done"):
					is_piston_tutorial_done = dict["is_piston_tutorial_done"]

func _on_auth_changed(_is_auth: bool):
	if is_instance_valid(workshop_panel) and workshop_panel.visible:
		if ui_root and ui_root.has_meta("workshop_current_tab") and ui_root.get_meta("workshop_current_tab") == 2:
			call_deferred("_setup_main_ui_containers")

func _ready():
	_load_workshop_economy()
	_update_day_check()
	
	if has_node("/root/WorkshopManager"):
		var wm = get_node("/root/WorkshopManager")
		if wm.has_signal("google_play_auth_changed"):
			if not wm.google_play_auth_changed.is_connected(_on_auth_changed):
				wm.google_play_auth_changed.connect(_on_auth_changed)
	
	# Session count tracking for rating and analytics
	var app_config = ConfigFile.new()
	app_config.load("user://achievements.cfg")
	_current_session_count = app_config.get_value("app", "session_count", 0)
	_current_session_count += 1
	app_config.set_value("app", "session_count", _current_session_count)
	app_config.save("user://achievements.cfg")

	_load_global_achievements() # Load global state once at startup
	
	if FileAccess.file_exists("user://rating_popup_shown.save"):
		rating_popup_shown = true



	# Initialize Google Play Game Services on Android
	if OS.has_feature("android") and Engine.has_singleton("GodotPlayGameServices"):
		var gps = get_node_or_null("/root/GodotPlayGameServices")
		if gps:
			var init_status = gps.initialize()
			if init_status == 0: # PlayGamesPluginError.OK
				play_games_achievements_client = PlayGamesAchievementsClient.new()
				add_child(play_games_achievements_client)
				print("Google Play Games Services client successfully setup!")
			
	Engine.max_fps = 60 # Cierra la puerta al stutter en pantallas 120Hz/LTPO
	is_grid_ready = false # Safeguard during async _ready
	
	# --- ORIENTATION INITIALIZATION ---
	if FileAccess.file_exists("user://orientation.save"):
		var orient_val = FileAccess.open("user://orientation.save", FileAccess.READ).get_as_text()
		current_orientation_setting = int(orient_val)
		if OS.has_feature("mobile"):
			if current_orientation_setting == 1:
				DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
			elif current_orientation_setting == 2:
				DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
			else:
				DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
		# Await OS resize event so the grid is built with the correct proportions
		await get_tree().create_timer(0.2).timeout
	else:
		# Force Auto by default if no setting exists
		current_orientation_setting = 0
		if OS.has_feature("mobile"):
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
		await get_tree().create_timer(0.2).timeout

	# Setup auto-reload on axis flip
	var vp_size = get_viewport_rect().size
	current_is_landscape = vp_size.x > vp_size.y
	if not get_tree().get_root().size_changed.is_connected(_on_window_resized):
		get_tree().get_root().size_changed.connect(_on_window_resized)

	# --- FIX BACKGROUND CANVAS SIZE ---
	var bg_node = get_parent().get_node_or_null("Background")
	if bg_node:
		bg_node.custom_minimum_size = Vector2(5000, 5000)
		bg_node.size = Vector2(5000, 5000)
		bg_node.position = Vector2(-1000, -1000)

	_precalculate_optimization_tables()
	
	
	# 0. GLOBAL VISUAL STABILITY (Fixes grey margins on Tablets/Modern Devices)
	RenderingServer.set_default_clear_color(Color(0.04, 0.04, 0.04, 1.0))
	
	# AUTO-DETECT LANGUAGE
	var os_lang = TranslationServer.get_locale().split("_")[0]
	var supported = ["es", "en", "it", "fr", "de", "pt"]
	if supported.has(os_lang):
		TranslationServer.set_locale(os_lang)
	else:
		TranslationServer.set_locale("en") # Fallback
	current_language = TranslationServer.get_locale()
	_load_tool_settings()
	_update_game_volume(game_volume) # Force apply default on first run
	# 1. OPTIMIZATION: Use clear color instead of a full ColorRect to avoid overdraw (30% less GPU load)
	RenderingServer.set_default_clear_color(Color(0.08, 0.08, 0.1, 1.0))
	
	# Init Particle Pool
	vs_x.resize(MAX_VISUAL_SPARKS); vs_y.resize(MAX_VISUAL_SPARKS)
	vs_vx.resize(MAX_VISUAL_SPARKS); vs_vy.resize(MAX_VISUAL_SPARKS)
	vs_color.resize(MAX_VISUAL_SPARKS); vs_life.resize(MAX_VISUAL_SPARKS)
	vs_life.fill(0.0)
	
	# Optimization: Pre-generate Random & Trig LUT
	random_lut.resize(LUT_SIZE)
	cos_lut.resize(LUT_SIZE)
	sin_lut.resize(LUT_SIZE)
	for i in range(LUT_SIZE):
		var r = randf()
		random_lut[i] = r
		cos_lut[i] = cos(r * TAU)
		sin_lut[i] = sin(r * TAU)
	
	# Skip GlobalBG move child as it's removed
	
	# --- SIMULATION CAMERA ---
	sim_camera = Camera2D.new()
	sim_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	sim_camera.position = vp_size / 2.0
	add_child(sim_camera)
	sim_camera.make_current()
	
	# Setup SFX Pool
	for i in range(SFX_POOL_SIZE):
		var asp = AudioStreamPlayer.new()
		asp.bus = "Master" # You can create a "SFX" bus later
		add_child(asp)
		sfx_pool.append(asp)
	
	# Dedicated Brush Player
	brush_player = AudioStreamPlayer.new()
	brush_player.bus = "Master"
	add_child(brush_player)
	
	# Environmental Players
	weather_player = AudioStreamPlayer.new(); add_child(weather_player)
	quake_player = AudioStreamPlayer.new(); add_child(quake_player)
	tornado_player = AudioStreamPlayer.new(); add_child(tornado_player)
	tsunami_player = AudioStreamPlayer.new(); add_child(tsunami_player)
	firework_player = AudioStreamPlayer.new(); add_child(firework_player)
	ascent_player = AudioStreamPlayer.new(); add_child(ascent_player)
	volcano_loop_player = AudioStreamPlayer.new(); add_child(volcano_loop_player)
	fire_loop_player = AudioStreamPlayer.new(); add_child(fire_loop_player)
	
	# Bomber Audio & Texture
	bombardero_player = AudioStreamPlayer.new(); add_child(bombardero_player)
	bombardero_texture = load("res://assets/icon_game/avion_bombardero.png")
	
	# Initialize material arrays to a safe size for all IDs (including music 500+)
	mat_colors_1.resize(1024); mat_colors_1.fill(Color.BLACK)
	mat_colors_2.resize(1024); mat_colors_2.fill(Color.BLACK)
	mat_colors_3.resize(1024); mat_colors_3.fill(Color.BLACK)
	material_tags_raw.resize(1024); material_tags_raw.fill(0)
	
	# --- AUDIO POOL INITIALIZATION ---
	# 1. Create a dedicated Music Bus with a Limiter to prevent saturation
	var music_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(music_bus_idx)
	AudioServer.set_bus_name(music_bus_idx, "MusicBus")
	var limiter = AudioEffectLimiter.new()
	AudioServer.add_bus_effect(music_bus_idx, limiter)
	
	music_player_pool.clear()
	for i in range(32): # 32-note polyphony
		var p = AudioStreamPlayer.new()
		p.bus = "MusicBus" # Assign to our protected bus
		add_child(p)
		music_player_pool.append(p)
	
	_register_musical_materials()
	
	# Calculate grid size (Smart Height: Exactly above the UI)
	var viewport_size = get_viewport_rect().size
	
	grid_width = floor(viewport_size.x / grid_scale)
	grid_height = floor(viewport_size.y / grid_scale)
	dynamic_grid_height = grid_height # Full initial
	
	charge_queued_frame.resize(grid_width * grid_height)
	charge_queued_frame.fill(-1)
	powered_frame.resize(grid_width * grid_height)
	powered_frame.fill(-1)
	
	# Update Display node size to match the grid exactly
	$Display.custom_minimum_size = Vector2(grid_width * grid_scale, grid_height * grid_scale)
	$Display.size = $Display.custom_minimum_size
	
	# Init arrays
	cells.resize(grid_width * grid_height)
	tags_array.resize(grid_width * grid_height)
	charge_array.resize(grid_width * grid_height)
	cell_paint_colors.resize(grid_width * grid_height)
	cell_paint_colors.fill(0)
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	color_buffer.resize(grid_width * grid_height * 4)
	
	# --- TORNADO VISUAL NODE ---
	tornado_visual = ColorRect.new()
	tornado_visual.visible = false
	tornado_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tornado_visual)
	
	var t_mat = ShaderMaterial.new()
	t_mat.shader = load("res://scripts/sandbox/tornado_visual.gdshader")
	tornado_visual.material = t_mat
	surface_cache.resize(grid_width)
	
	material_colors_bytes.resize(2048 * 4)
	material_colors_bytes.fill(0)
	
	chunks_x = ceil(float(grid_width) / CHUNK_SIZE)
	chunks_y = ceil(float(grid_height) / CHUNK_SIZE)
	chunks_active.resize(chunks_x * chunks_y)
	chunks_active.fill(0) 
	next_chunks_active.resize(chunks_x * chunks_y)
	next_chunks_active.fill(0)
	
	tags_array.resize(grid_width * grid_height)
	charge_array.resize(grid_width * grid_height)
	
	# GPU Image Buffers
	img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8) # Main ID Texture
	charge_img = Image.create(grid_width, grid_height, false, Image.FORMAT_L8) # Charge (Grayscale)
	charge_visual_buffer.resize(grid_width * grid_height)
	charge_visual_buffer.fill(0)
	
	background_img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	background_img.fill(Color(0, 0, 0, 0)) # Start transparent
	background_tex = ImageTexture.create_from_image(background_img)
	
	element_paint_img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	element_paint_img.fill(Color(0, 0, 0, 0)) # Transparent = Original material colors
	element_paint_tex = ImageTexture.create_from_image(element_paint_img)
	
	mat_colors_1.resize(2048)
	mat_colors_2.resize(2048)
	mat_colors_3.resize(2048)
	material_tags_raw.resize(2048)
	
	# === SPATIAL HASH SETUP ===
	spatial_grid_w = ceil(float(grid_width) / SPATIAL_CELL_SIZE)
	spatial_grid_h = ceil(float(grid_height) / SPATIAL_CELL_SIZE)
	npc_spatial_grid.resize(spatial_grid_w * spatial_grid_h)
	for i in range(npc_spatial_grid.size()):
		npc_spatial_grid[i] = []
		
	# Setup materials (0-255)
	_register_material(0, Color(0, 0, 0, 0), SandboxMaterial.Tags.NONE)
	
	# Initial clear of visual buffer
	charge_visual_buffer.fill(0)
	
	# --- RAW MATERIALS (0-20) ---
	# 1: Arena
	_register_material(1, Color("FFF9C4"), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("FDEB7A")) # Arena
	# 2: Agua
	_register_material(2, Color("80D0FF"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.CONDUCTOR) # Agua
	# 3: Fuego
	_register_material(3, Color("EBB400"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_MEDIUM, Color("FF4500")) # Fuego
	# 4: Petroleo
	_register_material(4, Color("041200"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.BURN_SMOKE) # Petroleo
	# 5: TNT
	_register_material(5, Color("E30000"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.EXP_ELECTRIC | SandboxMaterial.Tags.GRAV_STATIC) # TNT + Chispas
	# 6: Tierra
	_register_material(6, Color("#66380C"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#4D2A09")) # Tierra
	# 30: Piedra
	_register_material(30, Color("#8A8A8A"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.TEXTURE_DOUBLE, Color("#AFAFAF")) # Piedra
	
	# 8: Metal
	_register_material(8, Color("E3E3E3"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.GRAV_STATIC) # Metal
	# 9: Electricidad
	_register_material(9, Color("FFF300"), SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC) # Electricidad
	# 10: Rocas
	_register_material(10, Color("4D4D4D"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#292929")) # Rocas
	# 11: Lava
	_register_material(11, Color("FF4000"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.TEXTURE_TRIPLE | SandboxMaterial.Tags.MIX_MEDIUM, Color("FF7A00"), Color("2A0000")) # Lava
	# 12: Obsidiana
	_register_material(12, Color("0E0017"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_ACID | SandboxMaterial.Tags.ANTI_EXPLOSIVE | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#59008F")) # Obsidiana
	# 13: Acido
	_register_material(13, Color("#39FF14"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.ANTI_ACID  | SandboxMaterial.Tags.TEXTURE_TRIPLE | SandboxMaterial.Tags.MIX_LOW, Color("B7FC49"), Color("F2FF00")) # Acido
	
	# 14: Carbon
	_register_material(14, Color("#1A1110"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#3D1A10")) # Carbon
	# 15: Humo
	_register_material(15, Color("454545ff"), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.BURN_NONE) # Humo
	# 16: Madera
	_register_material(16, Color("#3E2609"), SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.BURN_COAL | SandboxMaterial.Tags.SOLID) # Madera
	# 17: Vapor/Nube
	_register_material(17, Color("8C8C8C"), SandboxMaterial.Tags.GAS | SandboxMaterial.Tags.GRAV_UP) # Nube/Vapor
	# 18: Mecha / Fuegos artificiales
	_register_material(18, Color("FF7D7D"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.ANTI_EXPLOSIVE) # Mecha / Fuegos artificiales
	# 19: Destello
	_register_material(19, Color(1, 0.8, 0.9), SandboxMaterial.Tags.GRAV_STATIC) # Destello Visual
	# 20: Polvora
	_register_material(20, Color("#6B6A66"), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Polvora
	
	# --- LOGIC GATES (81-87) ---
	_register_material(81, Color("#B3AF00"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # NOT
	_register_material(82, Color("#279CF5"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # AND
	_register_material(83, Color("#F52727"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # OR
	_register_material(84, Color("#204669"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # NAND
	_register_material(85, Color("#610101"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # NOR
	_register_material(86, Color("#0CAD19"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # XOR
	_register_material(87, Color("#264F2C"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # XNOR
	_register_material(88, Color("#FF9800"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC) # Battery
	_register_material(89, Color("#551111"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # LED
	_register_material(90, Color("#C254FF"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # NPC Activator
	_register_material(91, Color("#B25A38"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # NPC Door
	_register_material(92, Color("#00F0FF"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Phase Block
	_register_material(93, Color("#466282"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR) # Piston Base
	_register_material(94, Color("#8CAEC4"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR) # Piston Head/Shaft
	_register_material(193, Color("#466282"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Insulated Piston Base
	_register_material(194, Color("#A185FF"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC) # Insulated Piston Head/Shaft
	_register_material(95, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 0
	_register_material(195, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 45
	_register_material(295, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 90
	_register_material(395, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 135
	_register_material(495, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 180
	_register_material(595, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 225
	_register_material(695, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 270
	_register_material(795, Color("#2B2E33"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED) # Cannon Base 315
	_register_material(96, Color("#0265A6"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC) # Pipe
	_register_material(97, Color("#014D80"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC) # Pipe X2
	
	
	# --- BIOLOGICALS (21-24) ---
	# 21: Pasto
	_register_material(21, Color("#4CAF50"), SandboxMaterial.Tags.PLANT | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.BURN_COAL | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_MEDIUM, Color("#388E3C")) # Pasto
	# 24: Enredadera
	_register_material(24, Color("#3E5E2A"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.PLANT | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.BURN_COAL | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_MEDIUM, Color("#2E4A1F")) # Enredadera / Tallo
	# FLORES (31-34)
	var flower_tags = SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.PLANT | SandboxMaterial.Tags.FLAMMABLE | SandboxMaterial.Tags.BURN_COAL
	_register_material(31, Color("#FF66CC"), flower_tags) # Pink Flower
	_register_material(32, Color("#FF1A1A"), flower_tags) # Red Flower
	_register_material(33, Color("#FFEA00"), flower_tags) # Yellow Flower
	_register_material(34, Color("#9B30FF"), flower_tags) # Violet Flower
	
	# Setup Fertility
	material_tags_raw[1] |= SandboxMaterial.Tags.FERTILE
	material_tags_raw[6] |= SandboxMaterial.Tags.FERTILE
	
	# 22: Arena Mojada
	_register_material(22, Color("#C2B280").darkened(0.2), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.FERTILE) # Arena Mojada
	# 23: Tierra Mojada
	_register_material(23, Color("#8B4513").darkened(0.2), SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.GRAV_SLOW | SandboxMaterial.Tags.FERTILE | SandboxMaterial.Tags.BURN_COAL) # Tierra Mojada
	
	# --- STATES AND VFX ---
	# 7: TNT Flash (Blanco)
	_register_material(7, Color.WHITE, SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.EXPLOSIVE) # TNT Flashing (Normal)
	# 77: TNT Flash (Rojo)
	_register_material(77, Color("FF0000"), SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE | SandboxMaterial.Tags.EXPLOSIVE) # TNT Flashing (Red)
	# 43: Chispa
	_register_material(43, Color("#FFFF00"), SandboxMaterial.Tags.ELECTRICITY | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.VOLATILE | SandboxMaterial.Tags.GRAV_STATIC) # Chispa Amarilla
	# 44: Proyectil Acido
	_register_material(44, Color("#39FF14"), SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.VOLATILE | SandboxMaterial.Tags.GRAV_STATIC) # Proyectil Acido
	
	# --- CONSTRUCTION ---
	# 25: Cemento Fresco
	_register_material(25, Color("#d3c1a9ff"), SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GRAV_NORMAL | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#757570")) 
	# 26: Cemento Solido
	_register_material(26, Color("#C2B280"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#A6986A")) # Cemento Solido
	# 27: Volcan Bloque
	_register_material(27, Color("#FF5F1F"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.EXPLOSIVE | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#D84315")) # Volcan Bloque
	# 28: Proyectil Volcan
	_register_material(28, Color("#FFFF00"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_UP | SandboxMaterial.Tags.ANTI_EXPLOSIVE) # Proyectil Volcan
	# 29: Base de Volcan
	_register_material(29, Color("#FF4500"), SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.ANTI_EXPLOSIVE | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_MEDIUM, Color("#D84315")) # Base de Volcan Activa

	# --- NPC SYSTEM: GUERRERO (1000-1009) ---
	_register_material(1000, Color("1b977cff"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1001, Color("717E80"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza
	_register_material(1002, Color("1F1F1F"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso
	_register_material(1003, Color("FFE2BD"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel
	_register_material(1008, Color("717E80"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos
	
	# EQUIPOS (1004-1007)
	_register_material(1004, Color("E00000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Rojo
	_register_material(1005, Color("008EE6"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Azul
	_register_material(1006, Color("FFD000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Amarillo
	_register_material(1007, Color("00E317"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Verde
	
	# --- NPC SYSTEM: WIZARD/MAGO (1070-1077) ---
	_register_material(1070, Color("A83938"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Mago Master
	_register_material(1071, Color("F2F2F2"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Mago Barba
	_register_material(1072, Color("FFD8B3"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Mago Piel
	_register_material(1074, Color("A83938"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Túnica Roja
	_register_material(1075, Color("384BA8"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Túnica Azul
	_register_material(1076, Color("C79B1E"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Túnica Amarilla
	_register_material(1077, Color("74A838"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Túnica Verde

	
	# --- NPC SYSTEM: ARQUERO (1010-1019) ---
	_register_material(1010, Color("#228B22"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1011, Color("9C5B00"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza (Tela)
	_register_material(1012, Color("D46E00"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC) # Flecha
	_register_material(1013, Color("FFBC78"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel Arquero
	_register_material(1014, Color("9D00FF"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso Arquero
	_register_material(1015, Color("#594E61"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos Arquero
	
	# --- NPC SYSTEM: MINERO (1020-1029) ---
	_register_material(1020, Color("#555555"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1021, Color("#FFFB00"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Casco (Luz)
	_register_material(1022, Color("7D522D"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel Minero
	_register_material(1023, Color("#FF8D00"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso Minero
	_register_material(1024, Color("#000000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos Minero

	# --- NPC SYSTEM: MÉDICO (1040-1049) ---
	_register_material(1040, Color("#EEEEEE"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master/Uniforme
	_register_material(1041, Color("#7A0000"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cruz Roja
	_register_material(1042, Color("FFA691"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Piel Médico
	_register_material(1043, Color("#EEEEEE"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso Médico
	_register_material(1044, Color("#FFFFFF"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza Médica
	_register_material(1045, Color("#DEDEDE"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Zapatos Médico
	
	# --- NPC SYSTEM: ZOMBIE (1050-1054) ---
	_register_material(1050, Color("#4A7C2A"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1051, Color("#5D9C36"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza/Piel
	_register_material(1052, Color("#4B245C"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Polera morada oscura
	_register_material(1053, Color("#717E80"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Pantalón gris
	_register_material(1054, Color("#5D9C36"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Pies verdes (descalzo)
	
	# --- NPC SYSTEM: ZOMBIE TANK (1060-1064) ---
	_register_material(1060, Color("#365C1F"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Master
	_register_material(1061, Color("#4E822E"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Cabeza/Piel
	_register_material(1062, Color("#361B43"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Torso morado muy oscuro
	_register_material(1063, Color("#555F61"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Pantalón gris oscuro
	_register_material(1064, Color("#4E822E"), SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC) # Pies descalzos
	
	# --- SISTEMA DE DAÑO Y HIT (1030-1035) ---
	_register_material(1030, npc_color_acid, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1031, npc_color_fire, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1032, npc_color_exp, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1033, npc_color_hit, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1034, npc_color_death, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)
	_register_material(1035, Color.CYAN, SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.GRAV_STATIC)

	# --- CRYOGENIC SYSTEM (70-72) ---
	_register_material(70, Color("#bbe0fcff"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.MIX_LOW, Color("#99CFFF"))
	_register_material(71, Color.WHITE, SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.EXPLOSIVE)
	_register_material(72, Color("#CCFF00"), SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.EXPLOSIVE)

	# UI AND TEXTURE SETUP (Must happen AFTER materials are registered)
	texture_rect.texture = ImageTexture.create_from_image(img)
	texture_rect.anchor_right = 1.0
	texture_rect.anchor_bottom = 1.0
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.show_behind_parent = true # Emojis are drawn in SandboxGrid._draw(), so Display MUST be behind it
	charge_tex = ImageTexture.create_from_image(charge_img)

	# Initialize UI
	_setup_main_ui_containers()
	_load_lab_state() # LOAD LAB AFTER UI AND ARRAYS ARE READY
	
	# FORCE START HIDDEN
	tools_panel.visible = false
	disaster_panel.visible = false
	if npc_panel: npc_panel.visible = false
	
	# Connect Lab unlock global signal
	if AdMobManager.has_signal("lab_unlocked"):
		AdMobManager.lab_unlocked.connect(func():
			_play_action_sound("ui_click")
			var now = int(Time.get_unix_time_from_system())
			lab_unlock_expiry_unix = now + (12 * 3600)
			_set_lab_unlocked(true)
			_save_lab_state()
			
			# TUTORIAL CAUGHT: If they just unlocked it and it's open, start tutorial
			if not is_lab_tutorial_done and is_instance_valid(lab_panel) and lab_panel.visible:
				lab_tutorial_step = 1
				lab_custom_data[0]["grav"] = -1
				lab_custom_data[0]["state"] = -1
				_update_lab_inspector()
				_update_lab_tutorial_highlight()
		)
	
	
	# Connect Lab unlock global signal
	
	_register_material(19, Color(1, 0.8, 0.9), SandboxMaterial.Tags.GRAV_STATIC) # Firework Fuse

	# INITIAL HIGHLIGHT
	_update_material_highlights()
	_update_menu_highlights()
	
	# FINAL SHADER & PALETTE SYNC (Now 2048x3 for Textures)
	var palette_img = Image.create(2048, 3, false, Image.FORMAT_RGBA8)
	palette_img.fill(Color(0,0,0,0))
	for i in range(2048):
		palette_img.set_pixel(i, 0, mat_colors_1[i])
		palette_img.set_pixel(i, 1, mat_colors_2[i])
		palette_img.set_pixel(i, 2, mat_colors_3[i])
	var palette_tex = ImageTexture.create_from_image(palette_img)
	
	var shader = load("res://scripts/sandbox/sandbox_render.gdshader")
	var s_mat = ShaderMaterial.new()
	s_mat.shader = shader
	s_mat.set_shader_parameter("palette_tex", palette_tex)
	s_mat.set_shader_parameter("charge_tex", charge_tex) # Dedicated link
	s_mat.set_shader_parameter("background_tex", background_tex)
	s_mat.set_shader_parameter("element_color_tex", element_paint_tex)
	texture_rect.material = s_mat
	
	_load_rotation_cache() # Restore grid exactly as it was if we just flipped axis
	
	save_history_state() # Initialize first history step
	
	is_grid_ready = true # Allow _process and _draw to start now!
	
	# Smooth fade-in after rotation/startup to hide native scene loading
	var curtain_layer = get_parent().get_node_or_null("LoadCurtainLayer")
	if curtain_layer:
		var curtain = curtain_layer.get_node("Curtain")
		var tw = create_tween()
		tw.tween_property(curtain, "modulate:a", 0.0, 0.4)
		tw.tween_callback(curtain_layer.queue_free)
	
	_show_welcome_message()
	
	# Workshop discovery logic (Wait 7 minutes)
	if not FileAccess.file_exists("user://workshop_discovery_shown.save"):
		get_tree().create_timer(420.0).timeout.connect(func():
			if not FileAccess.file_exists("user://workshop_discovery_shown.save") and ui_elements.has("tools_btn"):
				# Ensure tools panel isn't already open
				if not (is_instance_valid(tools_panel) and tools_panel.visible):
					_start_pulse(ui_elements["tools_btn"])
		)

func _show_welcome_message():
	var save_path = "user://welcome_shown.save"
	if FileAccess.file_exists(save_path):
		return
		
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string("shown")
		file.close()

	var s = _get_ui_scale()
	ui_root = get_parent().get_node_or_null("UI")
	if not ui_root:
		return
		
	var overlay = ColorRect.new()
	overlay.name = "WelcomeOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	# Bloquear clics mientras está el panel
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
	p_style.corner_radius_top_left = 20 * s
	p_style.corner_radius_top_right = 20 * s
	p_style.corner_radius_bottom_left = 20 * s
	p_style.corner_radius_bottom_right = 20 * s
	p_style.shadow_color = Color(0, 0, 0, 0.5)
	p_style.shadow_size = 10 * s
	panel.add_theme_stylebox_override("panel", p_style)
	
	overlay.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 30 * s)
	margin.add_theme_constant_override("margin_bottom", 30 * s)
	margin.add_theme_constant_override("margin_left", 30 * s)
	margin.add_theme_constant_override("margin_right", 30 * s)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25 * s)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = tr("welcome_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 34 * s)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	vbox.add_child(title)
	
	var label = Label.new()
	label.text = tr("welcome_msg").replace("\\n", "\n")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _get_safe_font())
	label.add_theme_font_size_override("font_size", 24 * s)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)
	
	var btn = Button.new()
	btn.text = tr("welcome_close")
	btn.add_theme_font_override("font", _get_safe_font())
	btn.add_theme_font_size_override("font_size", 30 * s)
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
	btn_style.corner_radius_top_left = 12 * s
	btn_style.corner_radius_top_right = 12 * s
	btn_style.corner_radius_bottom_left = 12 * s
	btn_style.corner_radius_bottom_right = 12 * s
	btn.add_theme_stylebox_override("normal", btn_style)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.3, 0.7, 0.4)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_stylebox_override("pressed", btn_hover)
	
	btn.pressed.connect(func():
		if has_method("_play_action_sound"):
			call("_play_action_sound", "ui_click")
		
		# TUTORIAL: Garantizar que caiga arena al cerrar por primera vez
		# Esto asegura que el usuario vea el efecto incluso en dispositivos lentos.
		var center = btn.global_position + (btn.size / 2.0)
		var gx = int(center.x / grid_scale)
		var gy = int(center.y / grid_scale)
		_draw_circle(gx, gy, 7, 1) # Forzar material 1 (Arena)
		
		overlay.queue_free()
		
		# Spawneo de fuegos artificiales de bienvenida directos (con retraso y tandas)
		var spawn_fireworks = func():
			# 1. Esperar 2 segundos como pidió el usuario
			await get_tree().create_timer(2.0).timeout
			
			var left_x = int(grid_width * 0.25)
			var right_x = int(grid_width * 0.75)
			var base_y = int(dynamic_grid_height * 0.8)
			
			# 2. 3 tandas de 6 fuegos
			for round_idx in range(3):
				for i in range(3):
					_launch_firework(left_x + randi_range(-20, 20), base_y + randi_range(-10, 10))
					_launch_firework(right_x + randi_range(-20, 20), base_y + randi_range(-10, 10))
					await get_tree().create_timer(0.3).timeout
				# Pequeña pausa entre tandas para que se sienta espectacular
				# Pequeña pausa entre tandas para que se sienta espectacular
				await get_tree().create_timer(1.0).timeout
			
			# AQUI EMPIEZA EL TUTORIAL SECUENCIAL
			_start_interactive_tutorial()
				
		spawn_fireworks.call()
	)

var main_tutorial_step = 0
var main_tutorial_overlay: Control = null

var play_time_for_rating: float = 0.0
var rating_popup_shown: bool = false
var _current_session_count: int = 1

func _show_rating_popup():
	var s = _get_ui_scale()
	var screen_size = get_viewport_rect().size
	
	# Full-screen dim overlay
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
	
	# Panel
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.1, 0.1, 0.18, 0.97)
	p_style.set_border_width_all(int(3 * s))
	p_style.border_color = Color(0.95, 0.75, 0.2)
	p_style.set_corner_radius_all(20 * s)
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
	
	# Star emoji header
	var star_lbl = Label.new()
	star_lbl.text = "⭐⭐⭐⭐⭐"
	star_lbl.add_theme_font_override("font", _get_safe_font())
	star_lbl.add_theme_font_size_override("font_size", int(32 * s))
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(star_lbl)
	
	# Title
	var title_lbl = Label.new()
	title_lbl.text = tr("RATING_TITLE")
	title_lbl.add_theme_font_override("font", _get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", int(26 * s))
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(280 * s, 0)
	vbox.add_child(title_lbl)
	
	# Subtitle
	var sub_lbl = Label.new()
	sub_lbl.text = tr("RATING_SUBTITLE")
	sub_lbl.add_theme_font_override("font", _get_safe_font())
	sub_lbl.add_theme_font_size_override("font_size", int(20 * s))
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.custom_minimum_size = Vector2(280 * s, 0)
	vbox.add_child(sub_lbl)
	
	# Buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", int(20 * s))
	vbox.add_child(btn_hbox)
	
	# "Rate" button (green)
	var rate_btn = Button.new()
	rate_btn.text = tr("RATING_RATE_BTN")
	rate_btn.custom_minimum_size = Vector2(140 * s, 55 * s)
	rate_btn.add_theme_font_override("font", _get_safe_font())
	rate_btn.add_theme_font_size_override("font_size", int(22 * s))
	var rate_style = StyleBoxFlat.new()
	rate_style.bg_color = Color(0.2, 0.65, 0.3)
	rate_style.set_corner_radius_all(12 * s)
	rate_btn.add_theme_stylebox_override("normal", rate_style)
	rate_btn.add_theme_stylebox_override("hover", rate_style)
	rate_btn.add_theme_stylebox_override("pressed", rate_style)
	
	rate_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		# Persist so it never shows again
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
			# Open Google Play Store page
			OS.shell_open("https://play.google.com/store/apps/details?id=com.sandbox.elexstudio")
			
		overlay.queue_free()
	)
	btn_hbox.add_child(rate_btn)
	
	# "Not now" button (subtle gray)
	var later_btn = Button.new()
	later_btn.text = tr("RATING_LATER_BTN")
	later_btn.custom_minimum_size = Vector2(140 * s, 55 * s)
	later_btn.add_theme_font_override("font", _get_safe_font())
	later_btn.add_theme_font_size_override("font_size", int(22 * s))
	var later_style = StyleBoxFlat.new()
	later_style.bg_color = Color(0.35, 0.35, 0.4)
	later_style.set_corner_radius_all(12 * s)
	later_btn.add_theme_stylebox_override("normal", later_style)
	later_btn.add_theme_stylebox_override("hover", later_style)
	later_btn.add_theme_stylebox_override("pressed", later_style)
	
	later_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		# Persist so it never shows again
		var f = FileAccess.open("user://rating_popup_shown.save", FileAccess.WRITE)
		if f:
			f.store_string("shown")
			f.close()
		overlay.queue_free()
	)
	btn_hbox.add_child(later_btn)
	
	# Center panel on screen
	await get_tree().process_frame
	var p_size = panel.get_combined_minimum_size()
	panel.position = (screen_size - p_size) / 2.0

func _start_interactive_tutorial():
	# Si ya lo vio, no lo volvemos a mostrar
	var save_path = "user://main_tutorial_shown.save"
	if FileAccess.file_exists(save_path):
		return
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string("shown")
		file.close()

	main_tutorial_step = 0
	_show_main_tutorial_step()

func _show_main_tutorial_step():
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
	var target_node = null
	
	if target_key == "material_scroll":
		target_node = material_scroll
	else:
		target_node = ui_elements.get(target_key)
		
	# Safe Fallback Search
	if not is_instance_valid(target_node) and is_instance_valid(main_controls):
		target_node = main_controls.find_child(target_key, true, false)
		if not target_node:
			var search_name = target_key.capitalize().replace("_", "").replace(" ", "")
			target_node = main_controls.find_child(search_name, true, false)

	# If node still invalid, skip step safely
	if not is_instance_valid(target_node) or not target_node.is_inside_tree() or not target_node.is_visible_in_tree():
		main_tutorial_step += 1
		call_deferred("_show_main_tutorial_step")
		return
		
	var s = _get_ui_scale()
	var rect = target_node.get_global_rect()
	var screen_size = get_viewport_rect().size
	
	# PERSISTENT OVERLAY LOGIC (No more flickering)
	if not is_instance_valid(main_tutorial_overlay):
		main_tutorial_overlay = Control.new()
		main_tutorial_overlay.name = "MainTutorialOverlay"
		main_tutorial_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		main_tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		ui_root.add_child(main_tutorial_overlay)
	else:
		# Immediate clear of old step visuals, but keeping the overlay node alive
		for c in main_tutorial_overlay.get_children():
			c.queue_free()
	
	# Drawing Dimming Rects
	var create_dim = func(pos, sz):
		var r = ColorRect.new()
		r.color = Color(0, 0, 0, 0.8)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.position = pos
		r.size = sz
		main_tutorial_overlay.add_child(r)
		
	var padding = 5 * s
	var c_rect = rect.grow(padding).intersection(get_viewport_rect())
	
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
	
	# Tutorial Panel
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	p_style.set_border_width_all(int(3 * s))
	p_style.border_color = Color(0.3, 0.8, 0.4)
	p_style.set_corner_radius_all(15 * s)
	panel.add_theme_stylebox_override("panel", p_style)
	main_tutorial_overlay.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15 * s)
	var marg = MarginContainer.new()
	# Correct margin properties for Godot 4
	var m_val = int(20 * s)
	marg.add_theme_constant_override("margin_top", m_val)
	marg.add_theme_constant_override("margin_bottom", m_val)
	marg.add_theme_constant_override("margin_left", m_val)
	marg.add_theme_constant_override("margin_right", m_val)
	marg.add_child(vbox)
	panel.add_child(marg)
	
	var count_lbl = Label.new()
	count_lbl.text = str(main_tutorial_step + 1) + "/" + str(steps.size())
	count_lbl.add_theme_font_override("font", _get_safe_font())
	count_lbl.add_theme_font_size_override("font_size", 18 * s)
	count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(count_lbl)
	
	var lbl = Label.new()
	lbl.text = step_data["text"]
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_font_size_override("font_size", 24 * s)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(300 * s, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 20 * s)
	vbox.add_child(btn_hbox)
	
	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(120 * s, 50 * s)
	ok_btn.add_theme_font_override("font", _get_safe_font())
	ok_btn.add_theme_font_size_override("font_size", 24 * s)
	var ok_style = StyleBoxFlat.new()
	ok_style.bg_color = Color(0.2, 0.6, 0.3)
	ok_style.set_corner_radius_all(10 * s)
	ok_btn.add_theme_stylebox_override("normal", ok_style)
	ok_btn.add_theme_stylebox_override("hover", ok_style)
	ok_btn.add_theme_stylebox_override("pressed", ok_style)
	
	ok_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		ok_btn.disabled = true
		main_tutorial_step += 1
		call_deferred("_show_main_tutorial_step")
	)
	btn_hbox.add_child(ok_btn)
	
	var skip_btn = Button.new()
	skip_btn.text = tr("skip_tutorial")
	skip_btn.custom_minimum_size = Vector2(150 * s, 50 * s)
	skip_btn.add_theme_font_override("font", _get_safe_font())
	skip_btn.add_theme_font_size_override("font_size", 24 * s)
	var skip_style = StyleBoxFlat.new()
	skip_style.bg_color = Color(0.7, 0.2, 0.2)
	skip_style.set_corner_radius_all(10 * s)
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	skip_btn.add_theme_stylebox_override("hover", skip_style)
	skip_btn.add_theme_stylebox_override("pressed", skip_style)
	
	skip_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		skip_btn.disabled = true
		main_tutorial_step = steps.size()
		call_deferred("_show_main_tutorial_step")
	)
	btn_hbox.add_child(skip_btn)
	
	# DYNAMIC POSITIONING (Closer to target)
	var p_size = panel.get_combined_minimum_size()
	panel.position.x = (screen_size.x - p_size.x) / 2.0
	
	if target_key == "material_scroll":
		# Step 1: Specific placement for the material list
		panel.position.y = rect.position.y - p_size.y - 50 * s
	elif rect.position.y > screen_size.y * 0.5:
		# Target is on bottom half, show panel just ABOVE it
		panel.position.y = rect.position.y - p_size.y - 40 * s
	else:
		# Target is on top half, show panel just BELOW it
		panel.position.y = rect.end.y + 40 * s

	# Final safety clamp to keep panel on screen
	panel.position.y = clamp(panel.position.y, 20 * s, screen_size.y - p_size.y - 20 * s)
	panel.position.x = clamp(panel.position.x, 10 * s, screen_size.x - p_size.x - 10 * s)


func _start_pulse(btn: Control):
	_stop_pulse(btn) # Ensure no duplicate tweens
	var tween = create_tween()
	tween.set_loops()
	# Creates a very distinct yellow glowing effect
	tween.tween_property(btn, "self_modulate", Color(1.8, 1.8, 0.6), 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(btn, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	btn.set_meta("pulse_tween", tween)

func _stop_pulse(btn: Control):
	if btn.has_meta("pulse_tween"):
		var tween = btn.get_meta("pulse_tween")
		if is_instance_valid(tween):
			tween.kill()
		btn.remove_meta("pulse_tween")
	btn.self_modulate = Color.WHITE

func _show_menu_reminder(menu_id: String, parent_vbox: VBoxContainer, text_key: String):
	var save_path = "user://reminder_seen_" + menu_id + ".save"
	if FileAccess.file_exists(save_path):
		return
		
	# Si ya hay un recordatorio activo en este vbox, no duplicar
	if parent_vbox.has_node("MenuReminder"):
		return

	var s = _get_ui_scale()
	var pnl = PanelContainer.new()
	pnl.name = "MenuReminder"
	
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.3, 0.5, 0.95) # Azul informativo premium
	st.border_width_left = 2; st.border_width_top = 2
	st.border_width_right = 2; st.border_width_bottom = 2
	st.border_color = Color(0.3, 0.6, 1.0)
	st.set_corner_radius_all(15 * s)
	pnl.add_theme_stylebox_override("panel", st)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	margin.add_theme_constant_override("margin_top", 15 * s)
	margin.add_theme_constant_override("margin_bottom", 15 * s)
	pnl.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10 * s)
	margin.add_child(vbox)
	
	var tip_lbl = Label.new()
	tip_lbl.text = "💡 INFO"
	tip_lbl.add_theme_font_override("font", _get_safe_font())
	tip_lbl.add_theme_font_size_override("font_size", 18 * s)
	tip_lbl.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(tip_lbl)
	
	var lbl = Label.new()
	lbl.text = tr(text_key)
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_font_size_override("font_size", 21 * s)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.text = tr("GOT_IT")
	btn.add_theme_font_override("font", _get_safe_font())
	btn.add_theme_font_size_override("font_size", 22 * s)
	btn.custom_minimum_size = Vector2(150 * s, 45 * s)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var bst = StyleBoxFlat.new()
	bst.bg_color = Color(0.2, 0.6, 0.3)
	bst.set_corner_radius_all(10 * s)
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
	
	# Insertar debajo del título (asumimos que el título es el hijo 0)
	parent_vbox.add_child(pnl)
	parent_vbox.move_child(pnl, 1)


func _setup_materials_within_grid():
	var has_standard = false
	if material_grid.get_child_count() > 0:
		for c in material_grid.get_children():
			if not c.has_meta("is_custom"):
				has_standard = true
				break
	if has_standard: return # Already setup standard elements physically?
	
	# Setup all material buttons (Unified)
	_add_button("sand", 1)
	_add_button("water", 2)
	_add_button("fire", 3)
	_add_button("tnt", 5)
	_add_button("earth", 6)
	_add_button("stone", 30)
	_add_button("metal", 8)
	_add_button("elec", 9)
	_add_button("gravel", 10)
	_add_button("lava", 11)
	_add_button("obisid", 12)
	_add_button("acid", 13)
	_add_button("wood", 16)
	_add_button("petro", 4)
	_add_button("fireworks", 18)
	_add_button("powd", 20)
	_add_button("grass", 21)
	_add_button("vine", 24)
	_add_button("cem_fresh", 25)
	_add_button("cement", 26)
	_add_button("volcan", 27)
	_add_button("ice", 70)
	_add_button("lightning_tool", -3)
	
	# --- SECCIÓN PROXIMAMENTE ---
	_add_ui_header(material_grid, "coming_soon")
	_add_button("toxic_gas", 0, true)
	_add_button("void", 0, true)
	_add_button("flam_gas", 0, true)
	_add_button("coal_item", 0, true)
	_add_button("bacteria", 0, true)
	_add_button("cure", 0, true)
	_add_button("and_more", 0, true)
	
	# FIND the scroll vbox to add the final spacer
	var s = _get_ui_scale()
	var scroll_vbox = material_grid.get_parent()
	if scroll_vbox and scroll_vbox.name == "ScrollVBox":
		var spacer = Control.new()
		spacer.name = "FinalSpacer"
		spacer.custom_minimum_size = Vector2(0, 10.0 * s) # MINIMAL PADDING AT BOTTOM
		scroll_vbox.add_child(spacer)


func _setup_ui():
	_setup_tools_ui() # Tools on top
	_setup_npc_ui() # NPCs in the middle
	_setup_disaster_ui() # Disasters below

var material_grid: HFlowContainer
var action_hbox: HBoxContainer
var action_scroll: ScrollContainer
var achievement_btn: Button
static var is_achievement_menu_unlocked: bool = false
var action_vbox: VBoxContainer

var material_scroll: ScrollContainer
var cached_hud_height: float = 362.0 # Performance optimization: Cached for panel alignment

var play_games_achievements_client = null

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

# --- ACHIEVEMENT SYSTEM DATA ---
var achievements = {
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
var achievement_check_timer: float = 0.0
var achievement_sequence_step: int = -1 # -1: Idle, 0+: Current group frame

# TNT Chain Tracking
var _tnt_chain_count: int = 0
var _tnt_chain_flags: int = 0
var _tnt_chain_timer: float = 0.0
var _tnt_buckets_this_frame: Dictionary = {}

# Music Achievement Tracking
var composition_note_count: int = 0
var last_note_play_time: float = 0.0

func _save_global_achievements():
	var config = ConfigFile.new()
	config.set_value("progression", "achievements_unlocked_menu", is_achievement_menu_unlocked)
	
	var unlocked_list = []
	var seen_list = []
	for id in achievements:
		if achievements[id].unlocked:
			unlocked_list.append(id)
			if achievements[id].get("seen", false):
				seen_list.append(id)
		
		# Save extra progress data (like discovered types)
		if achievements[id].has("discovered"):
			config.set_value("progression", "ach_data_" + id, achievements[id].discovered)
			
	config.set_value("progression", "unlocked_ids", unlocked_list)
	config.set_value("progression", "seen_ids", seen_list)
	config.save("user://achievements.cfg")
	
	# After saving, if everything is seen, kill pulse just in case
	if not _has_unseen_achievements():
		if is_instance_valid(achievement_pulse_tween):
			achievement_pulse_tween.kill()
			achievement_pulse_tween = null
		if is_instance_valid(achievement_btn):
			achievement_btn.modulate = Color.WHITE

func _has_unseen_achievements() -> bool:
	for id in achievements:
		if achievements[id].unlocked and not achievements[id].get("seen", false):
			return true
	return false

func _load_global_achievements():
	var config = ConfigFile.new()
	var err = config.load("user://achievements.cfg")
	if err == OK:
		is_achievement_menu_unlocked = config.get_value("progression", "achievements_unlocked_menu", false)
		var unlocked_list = config.get_value("progression", "unlocked_ids", [])
		var seen_list = config.get_value("progression", "seen_ids", [])
		for id in achievements:
			if id in unlocked_list:
				achievements[id].unlocked = true
			if id in seen_list:
				achievements[id].seen = true
			elif achievements[id].unlocked:
				achievements[id].seen = false # Was unlocked but never seen
			
			# Load extra progress data if exists
			if achievements[id].has("discovered"):
				achievements[id].discovered = config.get_value("progression", "ach_data_" + id, [])
		

func _check_achievement_conditions(delta):
	# --- ACHIEVEMENT POLLING SEQUENCE ---
	achievement_check_timer += delta
	
	# Update TNT chain timer
	if _tnt_chain_timer > 0:
		_tnt_chain_timer -= delta
		if _tnt_chain_timer <= 0:
			_tnt_chain_timer = 0
			_tnt_chain_count = 0
			_tnt_chain_flags = 0
	
	if achievement_check_timer >= 2.0:
		achievement_check_timer = 0.0
		achievement_sequence_step = 0 # Start sequence
	
	if achievement_sequence_step != -1:
		_check_achievement_step(achievement_sequence_step)
		achievement_sequence_step += 1
		if achievement_sequence_step >= 13: # 13 groups total (0-12)
			achievement_sequence_step = -1 # End sequence
	
func _check_achievement_step(step: int):
	match step:
		0: # --- GROUP 0: COMBAT & INTERACTION ---
			if not achievements["massive_fight"].unlocked:
				var teams = {}
				for npc in active_npcs:
					if npc.hp > 0:
						teams[npc.team] = teams.get(npc.team, 0) + 1
				var valid_teams = 0
				for t_id in teams:
					if teams[t_id] >= 10: valid_teams += 1
				if valid_teams >= 2: _unlock_achievement("massive_fight")
			
			# 3. PARTY ROCK (Celebrating NPCs - Victory only, same team)
			if not achievements["party_rock"].unlocked:
				var team_counts = {}
				for npc in active_npcs:
					if npc.hp > 0 and npc.get("dance_timer", 0.0) > 0 and npc.get("recently_celebrated", false):
						var t = npc.team
						team_counts[t] = team_counts.get(t, 0) + 1
				for t_id in team_counts:
					if team_counts[t_id] >= 20:
						_unlock_achievement("party_rock")
						break
					
			if not achievements["electrifying"].unlocked:
				for y in range(0, dynamic_grid_height, 4):
					for x in range(0, grid_width, 4):
						var idx = y * grid_width + x
						if (cells[idx] & 0xFF) == 2 and charge_array[idx] > 0:
							_unlock_achievement("electrifying")
							return 

		1: # --- GROUP 1: THE HEAVY SCAN (GOD MODE) ---
			if not achievements["god"].unlocked:
				var req = [1, 2, 3, 5, 6, 8, 9, 10, 11, 12, 13, 16, 4, 18, 20, 21, 24, 25, 26, 27, 70]
				var found = {}
				for y in range(0, dynamic_grid_height, 4):
					for x in range(0, grid_width, 4):
						var pid = cells[y * grid_width + x] & 0xFF
						if pid in req:
							found[pid] = true
							if found.size() >= req.size():
								_unlock_achievement("god")
								return

		2: # --- GROUP 2: ARTISTIC (PAINT) ---
			if not achievements["paint"].unlocked:
				var bg_colors = {}
				var el_colors = {}
				
				# Sensitive 4x4 sampling to detect thin lines
				for y in range(0, dynamic_grid_height, 4):
					for x in range(0, grid_width, 4):
						var idx = y * grid_width + x
						# 1. Check Element Paint (ABGR32)
						var el_c = cell_paint_colors[idx]
						if el_c != 0: 
							el_colors[el_c] = true
						
						# 2. Check Background Paint (Ignore near-black/transparent)
						var bg_c = background_img.get_pixel(x, y)
						if bg_c.a > 0.1 and (bg_c.r > 0.02 or bg_c.g > 0.02 or bg_c.b > 0.02):
							# We use a rounded hex to avoid counting microscopic variations
							bg_colors[bg_c.to_html(false).left(6)] = true
						
						if el_colors.size() >= 4 and bg_colors.size() >= 4:
							_unlock_achievement("paint")
							return
		3: # --- GROUP 3: DISASTERS (TSUNAMI) ---
			if not achievements["tsunami_master"].unlocked and tsunami_intensity > 0:
				var target_liquids = [2, 4, 11, 13] # Water, Petro, Lava, Acid
				var found = {}
				for y in range(0, dynamic_grid_height, 4):
					for x in range(0, grid_width, 4):
						var pid = cells[y * grid_width + x] & 0xFFFF
						if pid in target_liquids:
							found[pid] = true
							if found.size() >= 4:
								_unlock_achievement("tsunami_master")
								return
		4: # --- GROUP 4: PEACEFUL (SLEEP) ---
			if not achievements["good_night"].unlocked:
				var sleep_count = 0
				for npc in active_npcs:
					if npc.hp > 0 and npc.get("is_lying", false) and npc.get("current_emoji", "") == "😴":
						sleep_count += 1
						if sleep_count >= 12:
							_unlock_achievement("good_night")
							return
		5: # --- GROUP 5: VOLCANO (GIANT'S AWAKENING) ---
			if not achievements["volcano_giant"].unlocked and is_volcano_active:
				var volcano_pixels = 0
				for y in range(0, dynamic_grid_height, 2):
					for x in range(0, grid_width, 2):
						var pid = cells[y * grid_width + x] & 0xFFFF
						if pid == 27 or pid == 29:
							volcano_pixels += 4 # Weighted for 2x2 sampling
							if volcano_pixels >= 700:
								_unlock_achievement("volcano_giant")
								return
		6: # --- GROUP 6: EXPLOSIONS (BOOM & SPECIAL) ---
			if not achievements["boom"].unlocked and _tnt_chain_count >= 20:
				_unlock_achievement("boom")
			
			if not achievements["special_boom"].unlocked and _tnt_chain_count >= 25:
				var has_acid = (_tnt_chain_flags & 64) > 0
				var has_elec = (_tnt_chain_flags & 128) > 0
				if has_acid and has_elec:
					_unlock_achievement("special_boom")
					
		7: # --- GROUP 7: ELECTRICITY (SHORT CIRCUIT) ---
			if not achievements["short_circuit"].unlocked:
				var electric_count = 0
				for npc in active_npcs:
					if npc.hp > 0 and npc.get("hit_flash", 0) > 0 and npc.get("hit_type", "") == "electric":
						electric_count += 1
						if electric_count >= 10:
							_unlock_achievement("short_circuit")
							return
		8: # --- GROUP 8: SOCIAL (WORLD WAR) ---
			if not achievements["world_war"].unlocked:
				var team_counts = {0:0, 1:0, 2:0, 3:0}
				for npc in active_npcs:
					if npc.hp > 0:
						team_counts[npc.team] = team_counts.get(npc.team, 0) + 1
				if team_counts[0] >= 5 and team_counts[1] >= 5 and team_counts[2] >= 5 and team_counts[3] >= 5:
					_unlock_achievement("world_war")
		9: # --- GROUP 9: LABORATORY (SUPREME ALCHEMIST) ---
			if not achievements["supreme_alchemist"].unlocked:
				var lab_found = {}
				for y in range(0, dynamic_grid_height, 4): # More sensitive scan
					for x in range(0, grid_width, 4):
						var pid = cells[y * grid_width + x] & 0xFFFF
						if pid >= 900 and pid <= 902:
							lab_found[pid] = true
							if lab_found.size() >= 3:
								_unlock_achievement("supreme_alchemist")
								return
		10: # --- GROUP 10: WAR-Z ---
			if not achievements["war-z"].unlocked:
				var zombie_count = 0
				var zombie_tank_count = 0
				var team_counts = {0: 0, 1: 0, 2: 0, 3: 0}
				for npc in active_npcs:
					if npc.hp > 0:
						if npc.type == "zombie":
							zombie_count += 1
						elif npc.type == "zombie_tank":
							zombie_tank_count += 1
						elif npc.team >= 0 and npc.team < 4:
							team_counts[npc.team] += 1
				if zombie_count >= 3 and zombie_tank_count >= 3 and team_counts[0] >= 3 and team_counts[1] >= 3 and team_counts[2] >= 3 and team_counts[3] >= 3:
					_unlock_achievement("war-z")
		11: # --- GROUP 11: DANCING RAIN ---
			if not achievements["dancing-rain"].unlocked and acid_rain_intensity > 0:
				for npc in active_npcs:
					if npc.hp > 0:
						_unlock_achievement("dancing-rain")
						break
		12: # --- GROUP 12: GREAT BOMBER ---
			if not achievements["great-bomber"].unlocked and bombardero_intensity == 3:
				_unlock_achievement("great-bomber")

func _unlock_retro_time_delayed():
	# Esperar 2 segundos para que el usuario vea el mando y se mueva
	await get_tree().create_timer(2.0).timeout
	if controlled_npc:
		_stop_controlling_npc()
	_unlock_achievement("retro_time")

func _unlock_achievement(id: String):
	if not achievements.has(id) or achievements[id].unlocked: return
	
	achievements[id].unlocked = true
	achievements[id].seen = false # Mark as NEW (unseen)
	_save_global_achievements()
	_show_achievement_notification(id)
	
	# Log to Firebase Analytics
	AnalyticsManager.log_event("achievement_unlocked", {"id": id, "title": achievements[id].get("title", "")})
	
	# Check if all achievements are unlocked
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
	
	# Sync unlock with Google Play Games Services if available on Android
	if play_games_achievements_client and GOOGLE_PLAY_ACHIEVEMENTS.has(id):
		play_games_achievements_client.unlock_achievement(GOOGLE_PLAY_ACHIEVEMENTS[id])

func _record_tornado_discovery(type: int):
	if not achievements.has("wind_master"): return
	
	if typeof(achievements["wind_master"]["discovered"]) != TYPE_ARRAY:
		achievements["wind_master"]["discovered"] = []
		
	var disc = achievements["wind_master"]["discovered"]
	
	if not (int(type) in disc):
		disc.append(int(type))
		_save_global_achievements()

	if disc.size() >= 4 and not achievements["wind_master"].unlocked:
		_unlock_achievement("wind_master")

# (Debug HUD removed)

func _setup_main_ui_containers():
	var s = _get_ui_scale()
	ui_root = get_parent().get_node("UI")
	main_controls = ui_root.get_node("Controls")
	
	var tools_v = is_instance_valid(tools_panel) and tools_panel.visible
	var lab_v = is_instance_valid(lab_panel) and lab_panel.visible
	var disaster_v = is_instance_valid(disaster_panel) and disaster_panel.visible
	var npc_v = is_instance_valid(npc_panel) and npc_panel.visible
	
	# 2. PURGE OLD UI CLONES & ACTION NODES
	ui_elements.clear()
	for child in ui_root.get_children():
		if child.name.begins_with("ToolsPanel") or child.name.begins_with("LabPanel") or child.name.begins_with("DisasterPanel") or child.name.begins_with("NPCPanel") or child.name.begins_with("PaintPanel"):
			child.get_parent().remove_child(child)
			child.queue_free()
			
	for child in main_controls.get_children():
		if child.name == "ActionScroll" or child.name.begins_with("ActionButtons") or child.name == "QuickActionsZone" or child.name == "CategoryScroll":
			child.get_parent().remove_child(child)
			child.queue_free()
			
	
	# 2. FIND MaterialGrid (Wherever it is)
	if not material_grid:
		material_grid = main_controls.find_child("MaterialGrid", true, false)
	
	if not material_grid: return
		
	# 3. FIND OR WRAP in Scroll
	var existing_scroll = main_controls.find_child("MaterialScroll", true, false)
	var scroll_vbox: VBoxContainer
	
	if existing_scroll:
		material_scroll = existing_scroll
		material_scroll.scroll_deadzone = 25
		scroll_vbox = material_scroll.find_child("ScrollVBox", true, false)
	else:
		# FIRST TIME WRAPPING
		var parent = material_grid.get_parent()
		var idx = material_grid.get_index()
		
		# CLONE original layout
		var orig_anchors = [material_grid.anchor_left, material_grid.anchor_top, material_grid.anchor_right, material_grid.anchor_bottom]
		var orig_offsets = [material_grid.offset_left, material_grid.offset_top, material_grid.offset_right, material_grid.offset_bottom]
		
		parent.remove_child(material_grid)
		
		material_scroll = ScrollContainer.new()
		material_scroll.name = "MaterialScroll"
		material_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		material_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		material_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# NEW: Use a VBox inside scroll to force vertical padding
		scroll_vbox = VBoxContainer.new()
		scroll_vbox.name = "ScrollVBox"
		scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# APPLY CLONED LAYOUT
		material_scroll.anchor_left = orig_anchors[0]
		material_scroll.anchor_top = orig_anchors[1]
		material_scroll.anchor_right = orig_anchors[2]
		material_scroll.anchor_bottom = orig_anchors[3]
		material_scroll.offset_left = orig_offsets[0]
		material_scroll.offset_top = orig_offsets[1]
		material_scroll.offset_right = orig_offsets[2]
		material_scroll.offset_bottom = orig_offsets[3]

		parent.add_child(material_scroll)
		parent.move_child(material_scroll, idx)
		material_scroll.add_child(scroll_vbox)
		scroll_vbox.add_child(material_grid)
		
		# OPTIMIZATION: Use deadzone for smoother mobile scrolling
		material_scroll.scroll_deadzone = 25
		
		material_scroll.mouse_entered.connect(func(): is_mouse_over_ui = true)
		material_scroll.mouse_exited.connect(func(): is_mouse_over_ui = false)
		material_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ALWAYS Refresh Scroll Height for the current scale
	# NEW: LARGER TALL HUD with logical CAP (Increased to 352px for mobile clearance) 
	var h = 392
	var h_cat = 60 * s # Slightly reduced height to fit 51px buttons
	cached_hud_height = float(h) # Cache for smart panel alignment
	
	# UPDATE PHYSICAL BOUNDARY
	var is_landscape = get_viewport_rect().size.x > get_viewport_rect().size.y
	var qa_width = 160 * s
	if is_landscape:
		qa_width = 320 * s # Double width in landscape for better ergonomics
	
	dynamic_grid_height = grid_height - ceil(float(h) / grid_scale)
	
	material_scroll.custom_minimum_size = Vector2(0, h - h_cat)
	material_scroll.anchor_top = 1.0
	material_scroll.anchor_bottom = 1.0
	material_scroll.anchor_left = 0
	material_scroll.anchor_right = 1.0
	
	material_scroll.offset_top = -h + h_cat
	material_scroll.offset_bottom = 0
	material_scroll.offset_left = 0
	material_scroll.offset_right = -qa_width - (5 * s) # Space for ActionButtons (dynamic)

	# 3.5 FRESH CATEGORY BAR (Smart Horizontal Row with Scroll)
	action_scroll = ScrollContainer.new()
	action_scroll.name = "ActionScroll"
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	action_scroll.get_h_scroll_bar().visible = false
	action_scroll.get_h_scroll_bar().modulate.a = 0
	main_controls.add_child(action_scroll)
	
	action_scroll.anchor_top = 1.0
	action_scroll.anchor_bottom = 1.0
	action_scroll.anchor_left = 0
	action_scroll.anchor_right = 1.0
	action_scroll.offset_top = -h
	action_scroll.offset_bottom = -h + h_cat
	action_scroll.offset_left = 0
	action_scroll.offset_right = 0
	
	action_hbox = HBoxContainer.new()
	action_hbox.name = "ActionButtons"
	action_scroll.add_child(action_hbox)
	
	# DYNAMIC STATE: If not unlocked, expand to fill screen (Static look)
	if not is_achievement_menu_unlocked:
		action_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		action_hbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		
	action_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_hbox.add_theme_constant_override("separation", 2 * s)

	# -------------------------
	



	# PUSH GAME VIEW (TextureRect) ABOVE HUD
	if not is_instance_valid(texture_rect): 
		texture_rect = get_node_or_null("/root/SandboxMain/TextureRect")
		
	if texture_rect:
		texture_rect.anchor_top = 0
		texture_rect.anchor_bottom = 1.0
		texture_rect.offset_bottom = -h # Align exactly with top of the tall HUD
		texture_rect.offset_top = 0

	# 4. UNIVERSAL HUD FOOTER BACKGROUND (Adaptive Background for any device)
	var footer_bg = main_controls.find_child("HUD_Footer_BG", true, false)
	if is_instance_valid(footer_bg): 
		footer_bg.get_parent().remove_child(footer_bg)
		footer_bg.queue_free()
		
	footer_bg = PanelContainer.new()
	footer_bg.name = "HUD_Footer_BG"
	var foot_style = StyleBoxFlat.new()
	foot_style.bg_color = Color(0.06, 0.057, 0.07, 1.0) # Near black for maximum contrast
	footer_bg.add_theme_stylebox_override("panel", foot_style)
	main_controls.add_child(footer_bg)
	main_controls.move_child(footer_bg, 0) # ALWAYS BEHIND MATERIAL/ACTION
	
	footer_bg.anchor_top = 1.0
	footer_bg.anchor_bottom = 1.0
	footer_bg.anchor_left = 0
	footer_bg.anchor_right = 1.0
	footer_bg.offset_top = -h
	footer_bg.offset_bottom = 0
	footer_bg.offset_left = 0
	footer_bg.offset_right = 0
	footer_bg.mouse_filter = Control.MOUSE_FILTER_STOP # Block game world clicks

	# 5. FRESH ACTION ZONE REBUILD
	# Vertical Area on the right (Quick Actions)
	action_vbox = VBoxContainer.new()
	action_vbox.name = "QuickActionsZone"
	main_controls.add_child(action_vbox)
		
	# PIN to HUD Floor
	action_vbox.anchor_bottom = 1.0
	action_vbox.anchor_top = 1.0
	action_vbox.anchor_left = 1.0
	action_vbox.anchor_right = 1.0
	
	action_vbox.offset_bottom = 0
	action_vbox.offset_top = -h + h_cat
	action_vbox.offset_left = -qa_width
	action_vbox.offset_right = 0
	
	action_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_vbox.add_theme_constant_override("separation", 0)
	action_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# CLEAN MATERIAL GRID
	if material_grid:
		for child in material_grid.get_children(): 
			if is_instance_valid(child): 
				child.get_parent().remove_child(child)
				child.queue_free()
		material_grid.add_theme_constant_override("h_separation", 6 * s)
		material_grid.add_theme_constant_override("v_separation", 4 * s)

	# 5. CONSTRUCT ALL SUB-UI
	ui_root.set_meta("tools_v", tools_v)
	var workshop_v = is_instance_valid(workshop_panel) and workshop_panel.visible
	ui_root.set_meta("workshop_v", workshop_v)
	ui_root.set_meta("lab_v", lab_v)
	ui_root.set_meta("disaster_v", disaster_v)
	ui_root.set_meta("npc_v", npc_v)
	ui_root.set_meta("paint_v", is_instance_valid(paint_panel) and paint_panel.visible)
	
	_setup_tools_ui()
	_setup_workshop_ui()
	_setup_lab_ui()
	_setup_disaster_ui()
	_setup_npc_panel_node()
	_setup_npc_ui()         
	_setup_paint_ui()
	_setup_npc_control_gui() # Fresh build of the control overlay
	
	for i in range(3):
		_update_lab_preview(i)
	_update_lab_inspector()
	
	_setup_materials_within_grid()
	_setup_music_button() # Add the piano button to the action column
	_update_material_highlights()
	_update_menu_highlights()


	# --- HIDDEN ACHIEVEMENT BUTTON (ALWAYS AT THE END / RIGHT) ---
	if is_achievement_menu_unlocked:
		# Calculate dynamic fixed width based on screen to ensure original buttons fill the view
		var screen_w = get_viewport_rect().size.x
		var fixed_w = (screen_w - (5 * 2 * s)) / 6.0 # 6 buttons + separations
		
		# Apply fixed width to all existing buttons
		for child in action_hbox.get_children():
			if child is Button:
				child.custom_minimum_size = Vector2(fixed_w, h_cat)
				child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				child.size_flags_vertical = Control.SIZE_EXPAND_FILL

		# Kill any existing pulse tween before replacing the reference
		if is_instance_valid(achievement_btn):
			if achievement_btn.has_meta("pulse_tween"):
				var old_tw = achievement_btn.get_meta("pulse_tween")
				if is_instance_valid(old_tw): old_tw.kill()
			achievement_btn.modulate = Color(1,1,1,1)

		achievement_btn = _create_vertical_category_btn("🏆", "achievement_btn")
		achievement_btn.name = "AchievementBtn"
		achievement_btn.custom_minimum_size = Vector2(fixed_w * 2.0, h_cat)
		achievement_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		achievement_btn.visible = true
		achievement_btn.pressed.connect(_setup_achievement_menu)
		
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
		
		action_hbox.add_child(achievement_btn)
		
		var is_menu_open = is_instance_valid(achievement_panel) and achievement_panel.visible
		if _has_unseen_achievements() and not is_menu_open:
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


# Helper for intelligent panel positioning above the HUD
func _align_panel_to_hud(panel: Control, p_width: float, p_height: float):
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_END
	
	# Optimized: Uses cached value updated only on UI rebuilds/orientation changes
	var h_base = cached_hud_height
	
	var bottom_gap = h_base # Stick directly to the edge
	
	panel.offset_left = -p_width / 2
	panel.offset_right = p_width / 2
	panel.offset_bottom = -bottom_gap
	panel.offset_top = -bottom_gap - p_height

func _create_vertical_category_btn(emoji: String, text_key: String) -> Button:
	var s = _get_ui_scale()
	var btn = Button.new()
	# ADAPTIVE WIDTH: Initially expand to fill screen, then freeze when scrolling is needed
	if not is_achievement_menu_unlocked:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		# Minimum width is handled dynamically in _rebuild_ui to ensure screen fill
		btn.custom_minimum_size = Vector2(80 * s, 0) 
	
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 0 # Let the parent HBox dictate height
	btn.mouse_filter = Control.MOUSE_FILTER_PASS

	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1 * s)
	btn.add_child(vbox)
	
	var emoji_lbl = Label.new()
	emoji_lbl.text = emoji
	emoji_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji_lbl.add_theme_font_size_override("font_size", 28 * s)
	emoji_lbl.add_theme_font_override("font", _get_safe_font())
	vbox.add_child(emoji_lbl)
	
	var text_lbl = Label.new()
	text_lbl.text = tr(text_key)
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_lbl.add_theme_font_size_override("font_size", 16 * s)
	text_lbl.add_theme_font_override("font", _get_safe_font())
	vbox.add_child(text_lbl)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.4, 0.5)
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_stylebox_override("hover", btn_style)
	btn.add_theme_stylebox_override("pressed", btn_style)
	btn.set_meta("base_style", btn_style)
	
	return btn

func _setup_tools_ui():
	var s = _get_ui_scale()
	ui_root = get_parent().get_node("UI")
	
	var tools_btn = _create_vertical_category_btn("🛠️", "tools")
	tools_btn.name = "ToolsBtn"
	ui_elements["tools_btn"] = tools_btn
	tools_btn.add_theme_font_override("font", _get_safe_font())
	tools_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	tools_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# --- QUICK ACTIONS GRID ---
	var qa_grid = GridContainer.new()
	qa_grid.columns = 2
	qa_grid.name = "QuickActionsGrid"
	ui_elements["quick_actions_grid"] = qa_grid
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

	var qa_style_active = qa_style.duplicate()
	qa_style_active.bg_color = Color(0.3, 0.5, 0.8, 1.0) # Highlight active Pan Mode
	
	var create_qa_btn = func(icon: String):
		var btn = Button.new()
		btn.text = icon
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 26 * s) # Bigger buttons
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
	
	ui_elements["btn_pan"] = btn_pan
	ui_elements["btn_undo"] = btn_undo
	ui_elements["btn_redo"] = btn_redo
	_set_panning_mode(is_panning_mode)
	_update_zoom_ui()
	
	btn_pan.pressed.connect(func(): 
		if btn_pan.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		_set_panning_mode(!is_panning_mode)
	)
	btn_save.pressed.connect(func(): 
		if btn_save.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		if is_instance_valid(save_panel): save_panel.queue_free()
		else: _setup_save_ui()
	)
	btn_undo.pressed.connect(func():
		if btn_undo.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		undo_history()
	)
	btn_redo.pressed.connect(func():
		if btn_redo.get_meta("long_pressed", false): return
		_play_action_sound("ui_click")
		redo_history()
	)
	
	_setup_long_press_tooltip(btn_pan, "tooltip_zoom")
	_setup_long_press_tooltip(btn_save, "tooltip_save")
	_setup_long_press_tooltip(btn_undo, "tooltip_undo")
	_setup_long_press_tooltip(btn_redo, "tooltip_redo")
	
	action_vbox.add_child(qa_grid)
	# -------------------------
	
	action_hbox.add_child(tools_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.2, 0.25, 1.0) # SOLID dark blue-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.4, 0.5)
	btn_style.corner_radius_top_left = 0; btn_style.corner_radius_top_right = 0
	btn_style.corner_radius_bottom_left = 0; btn_style.corner_radius_bottom_right = 0
	tools_btn.add_theme_stylebox_override("normal", btn_style)
	tools_btn.add_theme_stylebox_override("hover", btn_style)
	tools_btn.add_theme_stylebox_override("pressed", btn_style)

	
	# CREATE FRESH PANEL WITH STYLE
	tools_panel = PanelContainer.new()
	tools_panel.name = "ToolsPanel"
	ui_root.add_child(tools_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.98) # Original "Tools" blue-grey personality
	panel_style.border_width_left = 3; panel_style.border_width_top = 3
	panel_style.border_width_right = 3; panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.4, 0.4, 0.5) # Original border blue-grey
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	tools_panel.add_theme_stylebox_override("panel", panel_style)
	tools_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	tools_btn.set_meta("base_style", btn_style)
	
	# RESTORE STATE
	tools_panel.visible = ui_root.get_meta("tools_v", false)
	
	_align_panel_to_hud(tools_panel, 530 * s, 570 * s)
	
	# DYNAMIC BOX (NOW INSIDE SCROLL)
	var scroll = ScrollContainer.new()
	scroll.name = "ToolsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 25
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	tools_panel.add_child(main_vbox)
	
	# Title
	var title = Label.new()
	title.text = tr("tools")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 34 * s)
	ui_elements["tools_panel_title"] = title
	main_vbox.add_child(title)
	
	tools_btn.pressed.connect(_on_tools_btn_pressed)
	
	main_vbox.add_child(scroll)
	
	tools_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	tools_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	

	# DYNAMIC BOX (NOW INSIDE SCROLL)
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	var create_row = func(label_key: String, options: Array, callback: Callable, is_upcoming: bool = false):
		var lbl = Label.new()
		lbl.text = tr(label_key) + ":"
		lbl.add_theme_font_size_override("font_size", 22.0 * s)
		lbl.add_theme_font_override("font", _get_safe_font())
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
		ui_elements[label_key + "_lbl"] = lbl
		v_box.add_child(lbl)
		
		# ROW CONTAINER WITH 2PX MARGINS
		var row_margin = MarginContainer.new()
		row_margin.add_theme_constant_override("margin_left", 2 * s)
		row_margin.add_theme_constant_override("margin_right", 2 * s)
		v_box.add_child(row_margin)
		
		# Use HBoxContainer for perfect equal distribution (fills side-to-side)
		var flow = HBoxContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 6 * s)
		row_margin.add_child(flow)
		
		if is_upcoming:
			lbl.modulate = Color(0.5, 0.5, 0.5, 0.7)
			flow.modulate = Color(0.5, 0.5, 0.5, 0.7)
		
		for i in range(options.size()):
			var btn = Button.new()
			btn.text = str(options[i])
			# AUTO-FILL: This makes all buttons share the row width equally
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 45.0 * s)
			btn.add_theme_font_size_override("font_size", 20.0 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			
			# PREMIUM BASE STYLE
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = Color(0.12, 0.12, 0.15, 0.8)
			b_style.border_width_left = 1; b_style.border_width_top = 1
			b_style.border_width_right = 1; b_style.border_width_bottom = 1
			b_style.border_color = Color(0.3, 0.3, 0.4)
			b_style.set_corner_radius_all(10 * s)
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
					if is_selecting_npc_to_control or is_instance_valid(controlled_npc): _stop_controlling_npc()
					callback.call(level)
				)
			flow.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = btn 

	# Language Row (First Tool)
	var lang_options = ["Español", "English", "Italiano", "Français", "Deutsch", "Português"]
	var lang_codes = ["es", "en", "it", "fr", "de", "pt"]
	create_row.call("lang", lang_options, func(l):
		current_language = lang_codes[l]
		TranslationServer.set_locale(current_language)
		_save_tool_settings()
		# Rebuilding the UI is the most robust way to ensure all "premium" formatting
		# and spacing is preserved identically across different languages.
		call_deferred("_setup_main_ui_containers")
	)

	# ORIENTATION ROW
	var orient_options = [tr("ORIENT_AUTO"), tr("ORIENT_PORTRAIT"), tr("ORIENT_LANDSCAPE")]
	create_row.call("orient", orient_options, func(l):
		var f = FileAccess.open("user://orientation.save", FileAccess.WRITE)
		f.store_string(str(l))
		f.close()
		
		current_orientation_setting = l
		_update_menu_highlights()
		
		if OS.has_feature("mobile"):
			if l == 1: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
			elif l == 2: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
			else: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	)

	# GRID SNAP ROW
	var grid_options = [tr("active"), tr("inactive")]
	create_row.call("GRID_SNAP_LBL", grid_options, func(l):
		force_grid_visible = (l == 0)
		_save_tool_settings()
		_update_menu_highlights()
		queue_redraw()
	)


	# BRUSH SIZE ROW (Now 3rd)
	var brush_sizes = [0, 1, 2, 5, 7, 12]
	var brush_labels = ["1", "3", "5", "10", "15", "25"]
	create_row.call("brush", brush_labels, func(l): 
		brush_radius = brush_sizes[l]
		_save_tool_settings()
		_update_menu_highlights()
		_on_arcade_selection_made(true) # Real-time update for Arcade HUD (don't close menu)
	)

	
	# ACTION ROW (Undo, Redo, Eraser, Save)
	var func_lbl = Label.new()
	func_lbl.text = tr("func")
	func_lbl.add_theme_font_size_override("font_size", 22 * s)
	func_lbl.add_theme_font_override("font", _get_safe_font())
	func_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0)) # Soft blue
	v_box.add_child(func_lbl)
	ui_elements["func_lbl"] = func_lbl

	var community_btn = Button.new()
	community_btn.text = "🌐 " + tr("btn_comunidad")
	community_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	community_btn.custom_minimum_size = Vector2(0, 60 * s)
	community_btn.add_theme_font_override("font", _get_safe_font())
	community_btn.add_theme_font_size_override("font_size", 21 * s)
	community_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	c_style.border_width_left = 2; c_style.border_width_top = 2
	c_style.border_width_right = 2; c_style.border_width_bottom = 2
	c_style.border_color = Color("#48dbfb").lerp(Color.BLACK, 0.3)
	c_style.corner_radius_top_left = 12 * s
	c_style.corner_radius_top_right = 12 * s
	c_style.corner_radius_bottom_left = 12 * s
	c_style.corner_radius_bottom_right = 12 * s
	community_btn.add_theme_stylebox_override("normal", c_style)
	
	var c_hover = c_style.duplicate()
	c_hover.bg_color = Color("#48dbfb").lerp(Color.BLACK, 0.7)
	c_hover.border_color = Color("#48dbfb")
	community_btn.add_theme_stylebox_override("hover", c_hover)
	community_btn.add_theme_stylebox_override("pressed", c_hover)
	
	community_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		_stop_pulse(community_btn)
		
		var save_path = "user://workshop_discovery_shown.save"
		if not FileAccess.file_exists(save_path):
			var file = FileAccess.open(save_path, FileAccess.WRITE)
			if file:
				file.store_string("shown")
				file.close()
				
		if ui_elements.has("workshop_discovery_bubble"):
			var b = ui_elements["workshop_discovery_bubble"]
			if is_instance_valid(b):
				b.queue_free()
			ui_elements.erase("workshop_discovery_bubble")
				
		_toggle_category_panel(workshop_panel)
	)
	v_box.add_child(community_btn)
	ui_elements["btn_comunidad"] = community_btn
	
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

	var action_row = GridContainer.new()
	action_row.columns = 2
	action_row.add_theme_constant_override("h_separation", 10 * s)
	action_row.add_theme_constant_override("v_separation", 10 * s)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_box.add_child(action_row)

	var create_action_btn = func(text_key: String, accent_color: Color, callback: Callable):
		var btn = Button.new()
		btn.text = tr(text_key)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60 * s)
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 21 * s)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		# PREMIUM STYLE
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
		style.border_width_left = 2; style.border_width_top = 2
		style.border_width_right = 2; style.border_width_bottom = 2
		style.border_color = accent_color.lerp(Color.BLACK, 0.3) # Subtle darkened accent
		style.corner_radius_top_left = 12 * s
		style.corner_radius_top_right = 12 * s
		style.corner_radius_bottom_left = 12 * s
		style.corner_radius_bottom_right = 12 * s
		btn.add_theme_stylebox_override("normal", style)
		btn.set_meta("base_style", style)
		
		var hover = style.duplicate()
		hover.bg_color = accent_color.lerp(Color.BLACK, 0.7) # Dark tint on hover
		hover.border_color = accent_color # Brighter border on hover
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			callback.call()
		)
		action_row.add_child(btn)
		ui_elements[text_key + "_btn"] = btn # Register for highlights
		return btn

	create_action_btn.call("eraser_tool", Color("#ff6b6b"), func(): 
		selected_material = 0
		brush_radius = 3 
		_save_tool_settings()
		_update_material_highlights()
		_update_menu_highlights()
		_on_arcade_selection_made(true)
	)
	create_action_btn.call("save_btn_ui", Color("#feca57"), func(): 
		if is_instance_valid(save_panel):
			save_panel.queue_free()
		else:
			_setup_save_ui()
	)

	# 1. SUPPORT CREATOR BUTTON (AD)
	var support_btn = Button.new()
	support_btn.text = tr("support")
	support_btn.custom_minimum_size = Vector2(0, 60 * s) 
	support_btn.add_theme_font_size_override("font_size", 24 * s) 
	support_btn.add_theme_font_override("font", _get_safe_font())
	
	var support_style = StyleBoxFlat.new()
	support_style.bg_color = Color(0.1, 0.35, 0.2, 0.9) # Elegant dark emerald
	support_style.border_width_left = 2; support_style.border_width_top = 2
	support_style.border_width_right = 2; support_style.border_width_bottom = 2
	support_style.border_color = Color(0.3, 0.6, 0.4)
	support_style.corner_radius_top_left = 12 * s; support_style.corner_radius_top_right = 12 * s
	support_style.corner_radius_bottom_left = 12 * s; support_style.corner_radius_bottom_right = 12 * s
	
	support_btn.add_theme_stylebox_override("normal", support_style)
	support_btn.add_theme_stylebox_override("hover", support_style)
	support_btn.add_theme_stylebox_override("pressed", support_style)
	support_btn.add_theme_color_override("font_color", Color.GOLD)
	support_btn.mouse_filter = Control.MOUSE_FILTER_PASS

	support_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		
		# Log to Firebase Analytics
		AnalyticsManager.log_event("support_creator_clicked", {})
		
		# Guardar el estado de pausa original
		var prev_paused = is_paused
		
		# Pausar el juego si no está pausado
		if not is_paused:
			is_paused = true
			var p_btn = ui_elements.get("pause_btn")
			if is_instance_valid(p_btn):
				p_btn.text = tr("play")
			
			var players = [weather_player, quake_player, tornado_player, tsunami_player, firework_player, ascent_player, volcano_loop_player, fire_loop_player, bombardero_player]
			for p in players:
				if is_instance_valid(p):
					p.stream_paused = true
		
		if Engine.has_singleton("PoingGodotAdMob"):
			# Conectarse a ad_dismissed como ONE_SHOT para abrir el popup de agradecimiento cuando vuelva
			var on_ad_dismissed_callable = func():
				AnalyticsManager.log_event("support_creator_completed", {})
				_show_thank_you_popup(prev_paused)
			
			AdMobManager.ad_dismissed.connect(on_ad_dismissed_callable, CONNECT_ONE_SHOT)
			
			var ad_shown = await AdMobManager.show_rewarded()
			if not ad_shown:
				# Si el anuncio no se pudo mostrar (no cargó, etc.), desconectamos y restauramos la pausa previa
				if AdMobManager.ad_dismissed.is_connected(on_ad_dismissed_callable):
					AdMobManager.ad_dismissed.disconnect(on_ad_dismissed_callable)
				
				# Restaurar pausa previa si no estaba pausado
				if not prev_paused:
					is_paused = false
					var p_btn = ui_elements.get("pause_btn")
					if is_instance_valid(p_btn):
						p_btn.text = tr("pause")
					
					var players = [weather_player, quake_player, tornado_player, tsunami_player, firework_player, ascent_player, volcano_loop_player, fire_loop_player, bombardero_player]
					for p in players:
						if is_instance_valid(p):
							p.stream_paused = false
		else:
			print("DEBUG: Anuncio apoyo (PC)")
			# En PC simulamos la vuelta del anuncio tras 1.0 segundos
			await get_tree().create_timer(1.0).timeout
			AnalyticsManager.log_event("support_creator_completed", {})
			_show_thank_you_popup(prev_paused)
	)
	ui_elements["support_btn"] = support_btn
	v_box.add_child(support_btn)

	# 2. PAUSE BUTTON
	var pause_btn = Button.new()
	pause_btn.text = tr("play") if is_paused else tr("pause")
	pause_btn.custom_minimum_size = Vector2(0, 50 * s) # SCALED
	pause_btn.add_theme_font_size_override("font_size", 24 * s) # SCALED
	pause_btn.add_theme_font_override("font", _get_safe_font())
	
	var pause_style = StyleBoxFlat.new()
	pause_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	pause_style.border_width_left = 2; pause_style.border_width_top = 2
	pause_style.border_width_right = 2; pause_style.border_width_bottom = 2
	pause_style.border_color = Color(0.25, 0.5, 0.8) # Blue border for control
	pause_style.corner_radius_top_left = 12 * s; pause_style.corner_radius_top_right = 12 * s
	pause_style.corner_radius_bottom_left = 12 * s; pause_style.corner_radius_bottom_right = 12 * s
	
	pause_btn.add_theme_stylebox_override("normal", pause_style)
	pause_btn.add_theme_stylebox_override("hover", pause_style)
	pause_btn.add_theme_stylebox_override("pressed", pause_style)
	pause_btn.add_theme_color_override("font_color", Color.WHITE)
	pause_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	pause_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		
		if is_paused:
			if is_unpausing:
				# --- CANCEL COUNTDOWN ---
				is_unpausing = false
				pause_btn.text = tr("play")
				return
				
			# --- START RESUMING WITH COUNTDOWN ---
			is_unpausing = true
			
			var ad_shown = false
			if Engine.has_singleton("PoingGodotAdMob"):
				ad_shown = AdMobManager.check_and_show_interstitial("pause")
			
			if ad_shown:
				await AdMobManager.ad_dismissed
				
			# If unpausing was cancelled while ad was showing, abort
			if not is_unpausing: return
			
			# ALWAYS DO COUNTDOWN
			for i in range(3, 0, -1):
				pause_btn.text = tr("resume_in") + str(i) + "..."
				await get_tree().create_timer(1.0).timeout
				if not is_unpausing: return # Abort if cancelled during countdown
				
			# FINISH RESUMING
			is_unpausing = false
			is_paused = false
			pause_btn.text = tr("pause")
		else:
			# --- PAUSING ---
			is_paused = true
			is_unpausing = false
			pause_btn.text = tr("play")
			if Engine.has_singleton("PoingGodotAdMob"):
				AdMobManager.check_and_show_interstitial("pause")
		
		var players = [weather_player, quake_player, tornado_player, tsunami_player, firework_player, ascent_player, volcano_loop_player, fire_loop_player, bombardero_player]
		for p in players:
			if is_instance_valid(p):
				p.stream_paused = is_paused
	)
	ui_elements["pause_btn"] = pause_btn
	
	# Wrap pause button in a MarginContainer to add lateral spacing
	var pause_margin = MarginContainer.new()
	pause_margin.add_theme_constant_override("margin_left", 32 * s)
	pause_margin.add_theme_constant_override("margin_right", 32 * s)
	pause_margin.add_theme_constant_override("margin_top", 4 * s)
	pause_margin.add_theme_constant_override("margin_bottom", 4 * s)
	v_box.add_child(pause_margin)
	pause_margin.add_child(pause_btn)

	# 3. DIRECT RESET BUTTON (Bottom of Tools)
	var reset_btn_node = Button.new() # Named local variable to avoid conflict with field
	reset_btn_node.text = tr("reset")
	reset_btn_node.custom_minimum_size = Vector2(0, 50 * s)
	reset_btn_node.add_theme_font_size_override("font_size", 24 * s)
	reset_btn_node.add_theme_font_override("font", _get_safe_font())
	
	var reset_style = StyleBoxFlat.new()
	reset_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	reset_style.border_width_left = 2; reset_style.border_width_top = 2
	reset_style.border_width_right = 2; reset_style.border_width_bottom = 2
	reset_style.border_color = Color(0.8, 0.35, 0.35) # Reddish border for reset
	reset_style.corner_radius_top_left = 12 * s; reset_style.corner_radius_top_right = 12 * s
	reset_style.corner_radius_bottom_left = 12 * s; reset_style.corner_radius_bottom_right = 12 * s
	
	reset_btn_node.add_theme_stylebox_override("normal", reset_style)
	reset_btn_node.add_theme_stylebox_override("hover", reset_style)
	reset_btn_node.add_theme_stylebox_override("pressed", reset_style)
	reset_btn_node.add_theme_color_override("font_color", Color.WHITE)
	reset_btn_node.mouse_filter = Control.MOUSE_FILTER_PASS
	
	reset_btn_node.pressed.connect(func():
		_play_action_sound("ui_click")
		# RESET FIRST
		_clear_all()
		# THEN AD
		if Engine.has_singleton("PoingGodotAdMob"):
			AdMobManager.check_and_show_interstitial("reset")
	)
	ui_elements["reset_btn"] = reset_btn_node
	
	# Wrap reset button in a MarginContainer to add lateral spacing
	var reset_margin = MarginContainer.new()
	reset_margin.add_theme_constant_override("margin_left", 32 * s)
	reset_margin.add_theme_constant_override("margin_right", 32 * s)
	reset_margin.add_theme_constant_override("margin_top", 4 * s)
	reset_margin.add_theme_constant_override("margin_bottom", 4 * s)
	v_box.add_child(reset_margin)
	reset_margin.add_child(reset_btn_node)
	
	# 4. VOLUME CONTROL ROW
	var vol_lbl = Label.new()
	vol_lbl.text = tr("volumen")
	vol_lbl.add_theme_font_size_override("font_size", 22 * s)
	vol_lbl.add_theme_font_override("font", _get_safe_font())
	vol_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	v_box.add_child(vol_lbl)
	
	var vol_hbox = HBoxContainer.new()
	vol_hbox.add_theme_constant_override("separation", 15 * s)
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
	mute_btn.add_theme_font_size_override("font_size", 30 * s)
	mute_btn.add_theme_font_override("font", _get_safe_font())
	vol_hbox.add_child(mute_btn)
	
	var update_mute_icon = func(val):
		if val == 0: mute_btn.text = "🔇"
		elif val <= 0.5: mute_btn.text = "🔈"
		elif val <= 1.0: mute_btn.text = "🔉"
		else: mute_btn.text = "🔊"
	
	update_mute_icon.call(game_volume)
	
	vol_slider.value_changed.connect(func(val):
		game_volume = val
		if val > 0: 
			is_muted = false
			pre_mute_volume = val
		else:
			is_muted = true
		_update_game_volume(val)
		update_mute_icon.call(val)
		_save_tool_settings()
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
		_update_game_volume(game_volume)
		update_mute_icon.call(game_volume)
		_save_tool_settings()
	)

	# 5. PRIVACY / GDPR CONSENT BUTTON (Only for mobile)
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		var privacy_btn = Button.new()
		privacy_btn.text = tr("privacy_settings")
		privacy_btn.custom_minimum_size = Vector2(0, 50 * s)
		privacy_btn.add_theme_font_size_override("font_size", 24 * s)
		privacy_btn.add_theme_font_override("font", _get_safe_font())
		
		var privacy_style = StyleBoxFlat.new()
		privacy_style.bg_color = Color(0.15, 0.4, 0.75, 0.9) # Elegant informative blue
		privacy_style.border_width_left = 2; privacy_style.border_width_top = 2
		privacy_style.border_width_right = 2; privacy_style.border_width_bottom = 2
		privacy_style.border_color = Color(0.3, 0.6, 0.9)
		privacy_style.corner_radius_top_left = 12 * s; privacy_style.corner_radius_top_right = 12 * s
		privacy_style.corner_radius_bottom_left = 12 * s; privacy_style.corner_radius_bottom_right = 12 * s
		
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
		
		# Wrap in a MarginContainer to detach it from the left/right boundaries of the tools panel
		var btn_margin = MarginContainer.new()
		btn_margin.add_theme_constant_override("margin_left", 24 * s)
		btn_margin.add_theme_constant_override("margin_right", 24 * s)
		btn_margin.add_theme_constant_override("margin_top", 8 * s)
		btn_margin.add_theme_constant_override("margin_bottom", 8 * s)
		v_box.add_child(btn_margin)
		btn_margin.add_child(privacy_btn)
		
		# Set initial visibility (only show if privacy options are actually required/available)
		btn_margin.visible = AdMobManager.is_privacy_button_required()
		
		# Connect to dynamic updates of the consent information
		AdMobManager.consent_info_updated.connect(func():
			if is_instance_valid(btn_margin):
				btn_margin.visible = AdMobManager.is_privacy_button_required()
		)

	_add_ui_header(v_box, "coming_soon")
	
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
	version_lbl.add_theme_font_override("font", _get_safe_font())
	version_lbl.add_theme_font_size_override("font_size", 16 * s)
	version_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	
	var ver_margin = MarginContainer.new()
	ver_margin.add_theme_constant_override("margin_top", 15 * s)
	ver_margin.add_theme_constant_override("margin_bottom", 20 * s)
	ver_margin.add_child(version_lbl)
	v_box.add_child(ver_margin)

func _update_game_volume(value: float):
	# Convert linear 0.0 - 1.5 to dB. Master is bus index 0.
	# Boosted by +12dB to compensate for extremely low base recordings
	var db = linear_to_db(value) + 12.0
	AudioServer.set_bus_volume_db(0, db)
	# Mute completely if 0 to save processing
	AudioServer.set_bus_mute(0, value <= 0)

func _setup_workshop_ui():
	var s = _get_ui_scale()
	ui_root = get_parent().get_node("UI")
	
	if is_instance_valid(workshop_panel):
		workshop_panel.queue_free()
	
	workshop_panel = PanelContainer.new()
	workshop_panel.name = "WorkshopPanel"
	ui_root.add_child(workshop_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.98) # Dark elegant
	panel_style.border_width_left = 3; panel_style.border_width_top = 3
	panel_style.border_width_right = 3; panel_style.border_width_bottom = 3
	panel_style.border_color = Color("#48dbfb") # Same as community button
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	panel_style.content_margin_left = 15 * s
	panel_style.content_margin_right = 15 * s
	panel_style.content_margin_top = 20 * s
	panel_style.content_margin_bottom = 20 * s
	workshop_panel.add_theme_stylebox_override("panel", panel_style)
	workshop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	workshop_panel.visible = ui_root.get_meta("workshop_v", false)
	var max_w = get_viewport_rect().size.x - 40 * s
	var p_width = min(610 * s, max_w)
	_align_panel_to_hud(workshop_panel, p_width, 570 * s)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	workshop_panel.add_child(main_vbox)
	
	# SEARCH BAR
	var search_hbox = HBoxContainer.new()
	search_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	search_hbox.add_theme_constant_override("separation", 5 * s)
	main_vbox.add_child(search_hbox)
	
	var search_lbl_code = Label.new()
	search_lbl_code.text = tr("map_code")
	search_lbl_code.add_theme_font_override("font", _get_safe_font())
	search_lbl_code.add_theme_font_size_override("font_size", 18 * s)
	search_lbl_code.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	search_hbox.add_child(search_lbl_code)
	
	var search_input_base = LineEdit.new()
	search_input_base.placeholder_text = "xxxxxxxx"
	search_input_base.max_length = 15
	search_input_base.custom_minimum_size = Vector2(180 * s, 45 * s)
	search_input_base.add_theme_font_override("font", _get_safe_font())
	search_input_base.add_theme_font_size_override("font_size", 20 * s)
	search_input_base.alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_input_base.context_menu_enabled = false # Evitamos conflicto con el menu por defecto si lo hubiera
	search_hbox.add_child(search_input_base)
	
	# --- LONG PRESS TO PASTE HACK FOR MOBILE ---
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
	# -------------------------------------------
	
	var search_lbl_dash = Label.new()
	search_lbl_dash.text = "-"
	search_lbl_dash.add_theme_font_override("font", _get_safe_font())
	search_lbl_dash.add_theme_font_size_override("font_size", 24 * s)
	search_hbox.add_child(search_lbl_dash)
	
	var search_input_check = LineEdit.new()
	search_input_check.placeholder_text = "x"
	search_input_check.max_length = 1
	search_input_check.custom_minimum_size = Vector2(40 * s, 45 * s)
	search_input_check.add_theme_font_override("font", _get_safe_font())
	search_input_check.add_theme_font_size_override("font_size", 20 * s)
	search_input_check.alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_hbox.add_child(search_input_check)
	
	var search_btn = Button.new()
	search_btn.text = tr("btn_buscar") if TranslationServer.get_locale() == "es" else "Search"
	search_btn.custom_minimum_size = Vector2(80 * s, 45 * s)
	search_btn.add_theme_font_override("font", _get_safe_font())
	search_btn.add_theme_font_size_override("font_size", 16 * s)
	
	var search_btn_style = StyleBoxFlat.new()
	search_btn_style.bg_color = Color(0, 0, 0, 0)
	search_btn_style.border_width_left = 1; search_btn_style.border_width_top = 1
	search_btn_style.border_width_right = 1; search_btn_style.border_width_bottom = 1
	search_btn_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	search_btn_style.corner_radius_top_left = 10 * s; search_btn_style.corner_radius_top_right = 10 * s
	search_btn_style.corner_radius_bottom_left = 10 * s; search_btn_style.corner_radius_bottom_right = 10 * s
	search_btn.add_theme_stylebox_override("normal", search_btn_style)
	search_btn.add_theme_stylebox_override("hover", search_btn_style)
	search_btn.add_theme_stylebox_override("pressed", search_btn_style)
	
	search_hbox.add_child(search_btn)
	
	# Auto format on paste or overtyping
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
		_on_search_world_requested(search_input_base.text.to_lower(), search_input_check.text.to_lower())
	)
	
	# TAB HEADER
	var tab_hbox = HBoxContainer.new()
	tab_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_hbox.add_theme_constant_override("separation", 5 * s)
	main_vbox.add_child(tab_hbox)
	
	var top_category = ui_root.get_meta("workshop_top_category", "Top Semanal")
	
	var btn_hamburger = Button.new()
	btn_hamburger.text = "☰"
	btn_hamburger.custom_minimum_size = Vector2(45 * s, 45 * s)
	btn_hamburger.add_theme_font_override("font", _get_safe_font())
	btn_hamburger.add_theme_font_size_override("font_size", 24 * s)
	var hamburger_style = StyleBoxFlat.new()
	hamburger_style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	hamburger_style.corner_radius_top_left = 10 * s; hamburger_style.corner_radius_top_right = 10 * s
	hamburger_style.corner_radius_bottom_left = 10 * s; hamburger_style.corner_radius_bottom_right = 10 * s
	hamburger_style.border_color = Color("#48dbfb")
	btn_hamburger.add_theme_stylebox_override("normal", hamburger_style)
	btn_hamburger.add_theme_stylebox_override("hover", hamburger_style)
	btn_hamburger.add_theme_stylebox_override("pressed", hamburger_style)
	tab_hbox.add_child(btn_hamburger)
	
	btn_hamburger.pressed.connect(func():
		_play_action_sound("ui_click")
		var popup = PopupMenu.new()
		popup.add_theme_font_override("font", _get_safe_font())
		popup.add_theme_font_size_override("font_size", 20 * s)
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
		popup.popup(Rect2(btn_rect.position.x, btn_rect.position.y + btn_rect.size.y, 250, 0))
	)
	
	var current_tab = ui_root.get_meta("workshop_current_tab", 0)
	var create_tab_btn = func(emoji: String, text_key: String, tab_idx: int):
		var btn = Button.new()
		btn.text = emoji + "\n" + tr(text_key)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 55 * s)
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 16 * s) # slightly smaller for fitting 3
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var t_style = StyleBoxFlat.new()
		if tab_idx == current_tab:
			t_style.bg_color = Color(0.2, 0.5, 1.0, 1.0)
			t_style.corner_radius_top_left = 10 * s; t_style.corner_radius_top_right = 10 * s
			t_style.corner_radius_bottom_left = 10 * s; t_style.corner_radius_bottom_right = 10 * s
		else:
			t_style.bg_color = Color(0, 0, 0, 0)
			t_style.border_width_left = 1; t_style.border_width_top = 1
			t_style.border_width_right = 1; t_style.border_width_bottom = 1
			t_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
			t_style.corner_radius_top_left = 10 * s; t_style.corner_radius_top_right = 10 * s
			t_style.corner_radius_bottom_left = 10 * s; t_style.corner_radius_bottom_right = 10 * s
		
		btn.add_theme_stylebox_override("normal", t_style)
		btn.add_theme_stylebox_override("hover", t_style)
		btn.add_theme_stylebox_override("pressed", t_style)
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			if tab_idx != current_tab:
				var tab_names = ["top", "recents", "my_worlds", "my_downloads"]
				AnalyticsManager.log_event("workshop_tab_view", {"tab": tab_names[tab_idx] if tab_idx < 4 else str(tab_idx)})
			ui_root.set_meta("workshop_current_tab", tab_idx)
			call_deferred("_setup_main_ui_containers") # Rebuild to show active tab
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
	
	# Rotate text on "Mis mundos"
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
	
	# CONTENT AREA
	var content_panel = PanelContainer.new()
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	c_style.corner_radius_top_left = 10 * s; c_style.corner_radius_top_right = 10 * s
	c_style.corner_radius_bottom_left = 10 * s; c_style.corner_radius_bottom_right = 10 * s
	content_panel.add_theme_stylebox_override("panel", c_style)
	main_vbox.add_child(content_panel)
	
	current_tab = ui_root.get_meta("workshop_current_tab", 0)
	var loading_lbl = Label.new()
	loading_lbl.text = "..."
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_lbl.add_theme_font_override("font", _get_safe_font())
	loading_lbl.add_theme_font_size_override("font_size", 20 * s)
	content_panel.add_child(loading_lbl)
	
	var http = HTTPRequest.new()
	add_child(http)
	if "timeout" in http: http.timeout = 3.0
	http.request_completed.connect(func(result, _response_code, _headers, _body):
		var net = (result == HTTPRequest.RESULT_SUCCESS)
		if net == false and ui_root.get_meta("has_internet", true) == true:
			ui_root.set_meta("has_internet", false)
			_setup_workshop_ui()
		elif net == true and ui_root.get_meta("has_internet", true) == false:
			ui_root.set_meta("has_internet", true)
			_setup_workshop_ui()
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
		no_net_vbox.add_theme_constant_override("separation", 20 * s)
		
		var net_icon = Label.new()
		net_icon.text = "🌐❌"
		net_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		net_icon.add_theme_font_override("font", _get_safe_font())
		net_icon.add_theme_font_size_override("font_size", 80 * s)
		no_net_vbox.add_child(net_icon)
		
		var net_lbl = Label.new()
		net_lbl.text = tr("no_internet")
		net_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		net_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		net_lbl.add_theme_font_override("font", _get_safe_font())
		net_lbl.add_theme_font_size_override("font_size", 24 * s)
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
		scroll_vbox.add_theme_constant_override("separation", 30 * s)
		
		if current_tab == 0:
			top_countdown_label = Label.new()
			top_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			top_countdown_label.add_theme_font_override("font", _get_safe_font())
			top_countdown_label.add_theme_font_size_override("font_size", 18 * s)
			top_countdown_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			scroll_vbox.add_child(top_countdown_label)
		elif current_tab == 3:
			top_downloads_count_label = Label.new()
			top_downloads_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			top_downloads_count_label.add_theme_font_override("font", _get_safe_font())
			top_downloads_count_label.add_theme_font_size_override("font_size", 18 * s)
			top_downloads_count_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			scroll_vbox.add_child(top_downloads_count_label)
		
		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 20 * s)
		grid.add_theme_constant_override("v_separation", 20 * s)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		if current_tab == 1:
			var top_actions_hbox = HBoxContainer.new()
			top_actions_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			scroll_vbox.add_child(top_actions_hbox)
			
			var btn_actualizar = Button.new()
			btn_actualizar.text = "🔄 " + tr("btn_actualizar")
			btn_actualizar.custom_minimum_size = Vector2(160 * s, 45 * s)
			btn_actualizar.add_theme_font_override("font", _get_safe_font())
			btn_actualizar.add_theme_font_size_override("font_size", 16 * s)
			var a_style = StyleBoxFlat.new()
			a_style.bg_color = Color("#2ecc71").lerp(Color.BLACK, 0.6)
			a_style.border_width_left = 2; a_style.border_width_top = 2
			a_style.border_width_right = 2; a_style.border_width_bottom = 2
			a_style.border_color = Color("#2ecc71")
			a_style.corner_radius_top_left = 10 * s; a_style.corner_radius_top_right = 10 * s
			a_style.corner_radius_bottom_left = 10 * s; a_style.corner_radius_bottom_right = 10 * s
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
					_setup_workshop_ui()
				else:
					# Fake loading for "smart cache" feel
					var loading = _show_processing_overlay(tr("load_worls"))
					await get_tree().create_timer(0.4).timeout
					if is_instance_valid(loading):
						loading.queue_free()
					_setup_workshop_ui()
			)
			top_actions_hbox.add_child(btn_actualizar)

		scroll_vbox.add_child(grid)
		
		var pagination_hbox = HFlowContainer.new()
		pagination_hbox.alignment = FlowContainer.ALIGNMENT_CENTER
		pagination_hbox.add_theme_constant_override("h_separation", 15 * s)
		pagination_hbox.add_theme_constant_override("v_separation", 15 * s)
		scroll_vbox.add_child(pagination_hbox)
		
		if current_tab == 0:
			bot_countdown_label = Label.new()
			bot_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bot_countdown_label.add_theme_font_override("font", _get_safe_font())
			bot_countdown_label.add_theme_font_size_override("font_size", 18 * s)
			bot_countdown_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			scroll_vbox.add_child(bot_countdown_label)
		
		var margin = MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_left", 20 * s)
		margin.add_theme_constant_override("margin_top", 20 * s)
		margin.add_theme_constant_override("margin_right", 20 * s)
		margin.add_theme_constant_override("margin_bottom", 40 * s) # Extra margin at bottom
		margin.add_child(scroll_vbox)
		scroll.add_child(margin)
		
		var do_fetch = func():
			var p_page = ui_root.get_meta("workshop_page_" + str(current_tab), 1)
			if grid.get_child_count() == 0:
				if current_tab == 0:
					call_deferred("_fetch_top_async", grid, pagination_hbox, p_page)
				elif current_tab == 1:
					call_deferred("_fetch_recientes_async", grid, pagination_hbox, p_page)
				elif current_tab == 3:
					call_deferred("_fetch_mis_descargas_async", grid, pagination_hbox, p_page)
		
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
		scroll_vbox.add_theme_constant_override("separation", 30 * s)
		
		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 20 * s)
		grid.add_theme_constant_override("v_separation", 20 * s)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_vbox.add_child(grid)
		
		var margin = MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_left", 20 * s)
		margin.add_theme_constant_override("margin_top", 20 * s)
		margin.add_theme_constant_override("margin_right", 20 * s)
		margin.add_theme_constant_override("margin_bottom", 40 * s)
		margin.add_child(scroll_vbox)
		scroll.add_child(margin)
		
		var clean_data = ui_root.get_meta("workshop_search_result", {})
		if not clean_data.is_empty():
			var card = preload("res://scenes/main/world_card.tscn").instantiate()
			grid.add_child(card)
			card.setup(clean_data, 0)
			card.download_requested.connect(_on_world_download_requested)
			
	elif current_tab == 2:
		var mis_mundos_vbox = VBoxContainer.new()
		mis_mundos_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mis_mundos_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Change alignment to BEGIN so buttons stay at top
		mis_mundos_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		mis_mundos_vbox.add_theme_constant_override("separation", 15 * s)
		content_panel.add_child(mis_mundos_vbox)
		
		var wm = get_node_or_null("/root/WorkshopManager")
		if wm and wm.google_play_id == "":
			mis_mundos_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			var info_label = Label.new()
			info_label.text = tr("auth_required_desc")
			info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			info_label.add_theme_font_override("font", _get_safe_font())
			info_label.add_theme_font_size_override("font_size", 20 * s)
			mis_mundos_vbox.add_child(info_label)
			
			var btn_vincular = Button.new()
			btn_vincular.text = tr("btn_link_google_play")
			btn_vincular.custom_minimum_size = Vector2(0, 60 * s)
			btn_vincular.add_theme_font_override("font", _get_safe_font())
			btn_vincular.add_theme_font_size_override("font_size", 22 * s)
			
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = Color("#2ecc71").lerp(Color.BLACK, 0.4)
			b_style.border_width_left = 2; b_style.border_width_top = 2
			b_style.border_width_right = 2; b_style.border_width_bottom = 2
			b_style.border_color = Color("#2ecc71")
			b_style.corner_radius_top_left = 10 * s; b_style.corner_radius_top_right = 10 * s
			b_style.corner_radius_bottom_left = 10 * s; b_style.corner_radius_bottom_right = 10 * s
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
		top_buttons_hbox.add_theme_constant_override("separation", 10 * s)
		mis_mundos_vbox.add_child(top_buttons_hbox)
		
		var create_top_action_btn = func(text_key: String, btn_color: Color):
			var btn = Button.new()
			btn.text = tr(text_key)
			btn.custom_minimum_size = Vector2(0, 50 * s)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_override("font", _get_safe_font())
			btn.add_theme_font_size_override("font_size", 18 * s)
			
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = btn_color.lerp(Color.BLACK, 0.6)
			b_style.border_width_left = 2; b_style.border_width_top = 2
			b_style.border_width_right = 2; b_style.border_width_bottom = 2
			b_style.border_color = btn_color
			b_style.corner_radius_top_left = 10 * s; b_style.corner_radius_top_right = 10 * s
			b_style.corner_radius_bottom_left = 10 * s; b_style.corner_radius_bottom_right = 10 * s
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
					
			_show_upload_world_dialog()
		)
		top_buttons_hbox.add_child(btn_subir)
		
		var btn_gestionar = create_top_action_btn.call("btn_gestionar_mundos", Color("#ff9f43"))
		btn_gestionar.pressed.connect(func():
			_play_action_sound("ui_click")
			_show_world_manager_dialog()
		)
		top_buttons_hbox.add_child(btn_gestionar)
		
		var btn_actualizar = create_top_action_btn.call("btn_actualizar", Color("#2ecc71"))
		btn_actualizar.pressed.connect(func():
			_play_action_sound("ui_click")
			var current_time = Time.get_unix_time_from_system()
			var cache_time = ui_root.get_meta("workshop_mis_mundos_cache_time", 0.0)
			
			if cache_time == 0.0 or (current_time - cache_time) >= (11 * 60):
				ui_root.set_meta("workshop_mis_mundos_cache_time", 0.0)
				_setup_workshop_ui()
			else:
				var loading = _show_processing_overlay(tr("load_worls"))
				await get_tree().create_timer(0.4).timeout
				if is_instance_valid(loading):
					loading.queue_free()
				_setup_workshop_ui()
		)
		top_buttons_hbox.add_child(btn_actualizar)
		
		var daily_uploads_label = Label.new()
		daily_uploads_label.text = tr("daily_uploads_status").format([str(uploads_today), "5"])
		daily_uploads_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		daily_uploads_label.add_theme_font_override("font", _get_safe_font())
		daily_uploads_label.add_theme_font_size_override("font_size", 18 * s)
		daily_uploads_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		mis_mundos_vbox.add_child(daily_uploads_label)
		var list_scroll = ScrollContainer.new()
		list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		mis_mundos_vbox.add_child(list_scroll)
		
		var list_margin = MarginContainer.new()
		list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_margin.add_theme_constant_override("margin_left", 20 * s)
		list_margin.add_theme_constant_override("margin_top", 20 * s)
		list_margin.add_theme_constant_override("margin_right", 20 * s)
		list_margin.add_theme_constant_override("margin_bottom", 40 * s)
		list_scroll.add_child(list_margin)
		
		var grid_and_pag_vbox = VBoxContainer.new()
		grid_and_pag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_and_pag_vbox.add_theme_constant_override("separation", 20 * s)
		list_margin.add_child(grid_and_pag_vbox)
		
		var list_grid = GridContainer.new()
		list_grid.columns = 2
		list_grid.add_theme_constant_override("h_separation", 20 * s)
		list_grid.add_theme_constant_override("v_separation", 20 * s)
		list_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_and_pag_vbox.add_child(list_grid)
		
		var pagination_hbox = HFlowContainer.new()
		pagination_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		pagination_hbox.add_theme_constant_override("h_separation", 10 * s)
		pagination_hbox.add_theme_constant_override("v_separation", 10 * s)
		grid_and_pag_vbox.add_child(pagination_hbox)
		
		var page = ui_root.get_meta("workshop_page_2", 1)
		_fetch_mis_mundos_async(list_grid, pagination_hbox, page)
		
	workshop_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	workshop_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _build_pagination(pagination_hbox: HFlowContainer, total_items: int):
	if not is_instance_valid(pagination_hbox): return
	
	for child in pagination_hbox.get_children():
		child.queue_free()
		
	var s = _get_ui_scale()
	var total_pages = ceil(float(total_items) / 10.0)
	if total_pages <= 0: total_pages = 1
	
	for i in range(total_pages):
		var page_idx = i + 1
		var p_btn = Button.new()
		p_btn.text = str(page_idx)
		p_btn.custom_minimum_size = Vector2(60 * s, 60 * s)
		
		var b_style = StyleBoxFlat.new()
		var current_tab = ui_root.get_meta("workshop_current_tab", 0)
		var current_page = ui_root.get_meta("workshop_page_" + str(current_tab), 1)
		b_style.bg_color = Color(0.25, 0.25, 0.3) if page_idx == current_page else Color(0.15, 0.15, 0.2)
		b_style.corner_radius_top_left = 12 * s; b_style.corner_radius_top_right = 12 * s
		b_style.corner_radius_bottom_left = 12 * s; b_style.corner_radius_bottom_right = 12 * s
		p_btn.add_theme_stylebox_override("normal", b_style)
		
		var h_style = b_style.duplicate()
		h_style.bg_color = Color(0.35, 0.35, 0.4)
		p_btn.add_theme_stylebox_override("hover", h_style)
		p_btn.add_theme_stylebox_override("pressed", h_style)
		
		p_btn.add_theme_font_override("font", _get_safe_font())
		p_btn.add_theme_font_size_override("font_size", 20 * s)
		
		p_btn.pressed.connect(func():
			_play_action_sound("ui_click")
			var c_tab = ui_root.get_meta("workshop_current_tab", 0)
			ui_root.set_meta("workshop_page_" + str(c_tab), page_idx)
			_setup_main_ui_containers() # Re-render con nueva página
		)
		
		pagination_hbox.add_child(p_btn)

func _fetch_top_async(grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1):
	if not is_instance_valid(grid): return
	
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
		# Check disk cache first
		var is_historico = doc_name == "top_historico"
		var last_update = _get_last_update_unix(is_historico)
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
			
			# Save to disk cache
			var cf = FileAccess.open(cache_file, FileAccess.WRITE)
			if cf:
				cf.store_string(JSON.stringify({
					"fetch_time": int(Time.get_unix_time_from_system()),
					"document": document
				}))
				cf.close()
	
	if is_instance_valid(loading_overlay):
		loading_overlay.queue_free()
		
	if not is_instance_valid(grid): return
	
	if document == null:
		if ui_root.get_meta("has_internet", true) == true:
			ui_root.set_meta("has_internet", false)
			_setup_workshop_ui()
			return
			
	var dict_doc = null
	if typeof(document) == TYPE_OBJECT and document is FirestoreDocument:
		dict_doc = document.document
	elif typeof(document) == TYPE_DICTIONARY:
		dict_doc = document
		
	if dict_doc and dict_doc.has("worlds"):
		var raw_worlds = dict_doc["worlds"]
		var worlds_list = []
		
		# Manejar todas las posibles formas en que Godot Firebase parsea el array
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
						
			var last_update = _get_last_update_unix(false)
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
			
			# Si le dio al botón de actualizar, avanzamos el pointer
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
				btn_tirar.add_theme_font_size_override("font_size", 20 * s)
				btn_tirar.custom_minimum_size = Vector2(0, 50 * s)
				btn_tirar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var b_style = StyleBoxFlat.new()
				b_style.bg_color = Color(0.15, 0.45, 0.85, 1.0)
				b_style.corner_radius_top_left = 10 * s; b_style.corner_radius_top_right = 10 * s
				b_style.corner_radius_bottom_left = 10 * s; b_style.corner_radius_bottom_right = 10 * s
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
						
						_show_download_ad_popup(on_confirm, on_cancel, "watch_ad_ruleta_desc")
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
				_build_pagination(pagination_hbox, worlds_list.size())
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
			grid.add_child(card)
			card.setup(clean_data, 0)
			card.download_requested.connect(_on_world_download_requested)
			idx += 1
			
		if idx == 0:
			_show_empty_state_message(grid)

func _get_char_value(c: String) -> int:
	var ascii = c.unicode_at(0)
	if ascii >= 48 and ascii <= 57: return ascii - 48
	if ascii >= 97 and ascii <= 122: return ascii - 97 + 10
	return 0

func _get_value_char(val: int) -> String:
	if val >= 0 and val <= 9: return String.chr(val + 48)
	if val >= 10 and val <= 35: return String.chr(val - 10 + 97)
	return "0"

func _verify_map_code(base_code: String, check_char: String) -> bool:
	if base_code.length() != 8 or check_char.length() != 1: return false
	var sum = 0
	for i in range(8): sum += _get_char_value(base_code[i]) * (i + 1)
	return _get_value_char(sum % 36) == check_char

func _on_search_world_requested(base_code: String, check_char: String):
	if base_code.strip_edges() == "" or check_char.strip_edges() == "":
		_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_enter_full_code"))
		return
		
	if not _verify_map_code(base_code, check_char):
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
			
	ui_root.set_meta("workshop_search_result", clean_data)
	ui_root.set_meta("workshop_current_tab", 4)
	call_deferred("_setup_main_ui_containers")

func _fetch_recientes_async(grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1):
	if not is_instance_valid(grid): return
	
	var current_time = int(Time.get_unix_time_from_system())
	var mem_time = ui_root.get_meta("workshop_recientes_cache_time", 0.0)
	
	var document = _cached_recientes_doc
	
	# Auto-refresh de 30 minutos o forzado por el botón (0.0)
	if document != null and (mem_time == 0.0 or (current_time - mem_time) >= 1800):
		document = null
		_cached_recientes_doc = null
	
	if document == null:
		# Check disk cache first con vencimiento de 30 minutos
		if FileAccess.file_exists("user://recientes_cache.json"):
			var cf = FileAccess.open("user://recientes_cache.json", FileAccess.READ)
			if cf:
				var text = cf.get_as_text()
				cf.close()
				if text != "":
					var parsed = JSON.parse_string(text)
					if typeof(parsed) == TYPE_DICTIONARY and parsed.has("fetch_time"):
						var fetch_time = parsed["fetch_time"]
						if mem_time != 0.0 and (current_time - fetch_time) < 1800: # 30 mins
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
		
	if not is_instance_valid(grid): return
	
	if document == null:
		if ui_root.get_meta("has_internet", true) == true:
			ui_root.set_meta("has_internet", false)
			_setup_workshop_ui()
			return
			
	var dict_doc = null
	if typeof(document) == TYPE_OBJECT and document is FirestoreDocument:
		dict_doc = document.document
	elif typeof(document) == TYPE_DICTIONARY:
		dict_doc = document
		
	if dict_doc and dict_doc.has("worlds"):
		var raw_worlds = dict_doc["worlds"]
		var worlds_list = []
		
		# Manejar todas las posibles formas en que Godot Firebase parsea el array
		if typeof(raw_worlds) == TYPE_ARRAY:
			worlds_list = raw_worlds
		elif typeof(raw_worlds) == TYPE_DICTIONARY:
			if raw_worlds.has("arrayValue"):
				if raw_worlds["arrayValue"].has("values"):
					worlds_list = raw_worlds["arrayValue"]["values"]
			else:
				worlds_list = raw_worlds.values()
				
		if is_instance_valid(pagination_hbox):
			_build_pagination(pagination_hbox, worlds_list.size())
				
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
			grid.add_child(card)
			card.setup(clean_data, 0)
			card.download_requested.connect(_on_world_download_requested)
			card.like_requested.connect(_on_world_like_requested)
			card.report_requested.connect(_on_world_report_requested)
			idx += 1
			
		if idx == 0:
			_show_empty_state_message(grid)

func _fetch_mis_mundos_async(grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1, force_fetch: bool = false):
	if not is_instance_valid(grid): return
	
	var wm = get_node_or_null("/root/WorkshopManager")
	if not wm or wm.google_play_id == "":
		_show_empty_state_message(grid)
		return
		
	_load_workshop_cache()
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
		
		if not is_instance_valid(grid): return
		
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
			_save_workshop_cache()
		else:
			document_array = []
			ui_root.set_meta("workshop_mis_mundos_cache", [])
			ui_root.set_meta("workshop_mis_mundos_cache_time", current_time)
			ui_root.set_meta("workshop_total_uploaded_worlds", 0)
			_save_workshop_cache()
	
	var preloaded_cards = grid.get_children()
	
	if typeof(document_array) == TYPE_ARRAY and document_array.size() > 0:
		if is_instance_valid(pagination_hbox):
			_build_pagination(pagination_hbox, document_array.size())
			
		var start_idx = (page - 1) * 10
		var page_worlds = []
		if start_idx < document_array.size():
			page_worlds = document_array.slice(start_idx, start_idx + 10)
			
		var idx = 0
		for clean_data in page_worlds:
			if idx < preloaded_cards.size():
				preloaded_cards[idx].setup(clean_data, 3)
				if not preloaded_cards[idx].download_requested.is_connected(_on_world_download_requested):
					preloaded_cards[idx].download_requested.connect(_on_world_download_requested)
				if not preloaded_cards[idx].like_requested.is_connected(_on_world_like_requested):
					preloaded_cards[idx].like_requested.connect(_on_world_like_requested)
				if not preloaded_cards[idx].edit_requested.is_connected(_on_world_edit_requested):
					preloaded_cards[idx].edit_requested.connect(_on_world_edit_requested)
				if not preloaded_cards[idx].report_requested.is_connected(_on_world_report_requested):
					preloaded_cards[idx].report_requested.connect(_on_world_report_requested)
			else:
				var card = preload("res://scenes/main/world_card.tscn").instantiate()
				grid.add_child(card)
				card.setup(clean_data, 3)
				card.download_requested.connect(_on_world_download_requested)
				card.like_requested.connect(_on_world_like_requested)
				card.edit_requested.connect(_on_world_edit_requested)
				card.report_requested.connect(_on_world_report_requested)
			idx += 1
			
		for i in range(idx, preloaded_cards.size()):
			preloaded_cards[i].queue_free()
			
		if idx == 0:
			_show_empty_state_message(grid)
	else:
		for card in preloaded_cards:
			card.queue_free()
		_show_empty_state_message(grid)

func _update_local_recientes_cache(world_id: String, delete: bool, new_data: Dictionary = {}):
	var document = _cached_recientes_doc
	
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
					# Update
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
			var mem_time = ui_root.get_meta("workshop_recientes_cache_time", int(Time.get_unix_time_from_system()))
			var cf = FileAccess.open("user://recientes_cache.json", FileAccess.WRITE)
			if cf:
				cf.store_string(JSON.stringify({
					"fetch_time": mem_time,
					"document": dict_doc
				}))
				cf.close()

func _fetch_mis_descargas_async(grid: GridContainer, pagination_hbox: HFlowContainer, page: int = 1):
	if not is_instance_valid(grid): return
	var downloads = []
	if FileAccess.file_exists("user://downloads.json"):
		var f = FileAccess.open("user://downloads.json", FileAccess.READ)
		var dict = JSON.parse_string(f.get_as_text())
		if typeof(dict) == TYPE_ARRAY: downloads = dict
		
	if is_instance_valid(top_downloads_count_label):
		top_downloads_count_label.text = tr("downloaded_maps_count").format([str(downloads.size())])
		
	_build_pagination(pagination_hbox, downloads.size())
	
	for i in range(grid.get_child_count()):
		grid.get_child(i).queue_free()
		
	var start_idx = (page - 1) * 10
	var end_idx = start_idx + 10
	if start_idx < 0: start_idx = 0
	
	var displayed = 0
	for i in range(start_idx, min(end_idx, downloads.size())):
		var w_data = downloads[i]
		
		# Emergency fix for corrupted data
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
		grid.add_child(card)
		
		var current_time = int(Time.get_unix_time_from_system())
		var last_sync = w_data.get("last_sync_time", 0)
		if current_time - last_sync > 604800: # 7 dias
			_trigger_lazy_sync(w_data, card)
			
		card.setup(w_data, 2) # CardMode.DOWNLOADED
		if liked_worlds.has(str(w_data.get("id", w_data.get("world_id", "")))):
			card.set_liked_state(true)
			
		card.play_requested.connect(_on_world_play_requested)
		card.delete_requested.connect(_on_world_delete_downloaded)
		card.like_requested.connect(_on_world_like_requested)
		card.unlike_requested.connect(_on_world_unlike_requested)
		card.report_requested.connect(_on_world_report_requested)
		displayed += 1
		
	if displayed == 0:
		_show_empty_state_message(grid)

func _trigger_lazy_sync(w_data: Dictionary, card: Control):
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
		
		# Modificar visualmente si la tarjeta sigue activa
		if is_instance_valid(card) and card.has_method("setup"):
			card.world_data["likes"] = w_data.get("likes", 0)
			card.world_data["downloads"] = w_data.get("downloads", 0)
			if is_instance_valid(card.get("likes_label")):
				card.likes_label.text = "👍 " + str(w_data.get("likes", 0))
			if is_instance_valid(card.get("downloads_label")):
				card.downloads_label.text = "⬇️ " + str(w_data.get("downloads", 0))
				
		# Actualizar el JSON
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

func _show_empty_state_message(grid: GridContainer):
	var lbl = Label.new()
	lbl.text = tr("no_worlds_here")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_font_size_override("font_size", int(24 * _get_ui_scale()))
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl.custom_minimum_size = Vector2(0, 100 * _get_ui_scale())
	grid.get_parent().add_child(lbl)
	grid.get_parent().move_child(lbl, grid.get_index() + 1)

func _on_world_delete_downloaded(world_data: Dictionary):
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

func _on_world_like_requested(world_data: Dictionary):
	var world_id = str(world_data.get("id", ""))
	if world_id == "" or liked_worlds.has(world_id): return
		
	liked_worlds.append(world_id)
	_save_workshop_economy()
	
	var action_data = {
		"world_id": world_id,
		"type": "like",
		"timestamp": int(Time.get_unix_time_from_system())
	}
	_push_to_action_buffer(action_data)
	
	# Actualizar UI local optimísticamente para feedback instantáneo
	var new_likes = int(world_data.get("likes", 0)) + 1
	world_data["likes"] = new_likes
	
	var all_cards = ui_root.find_children("*", "PanelContainer", true, false)
	for card in all_cards:
		if card.has_method("setup") and card.get("world_data") != null:
			if str(card.world_data.get("id", card.world_data.get("world_id", ""))) == world_id:
				card.world_data["likes"] = new_likes
				if card.has_method("set_liked_state"):
					card.set_liked_state(true)
				if is_instance_valid(card.get("likes_label")):
					card.likes_label.text = "👍 " + str(new_likes)
	_update_local_download_likes(world_id, new_likes)

func _on_world_unlike_requested(world_data: Dictionary):
	var world_id = str(world_data.get("id", ""))
	if world_id == "" or not liked_worlds.has(world_id): return
		
	liked_worlds.erase(world_id)
	_save_workshop_economy()
	
	var action_data = {
		"world_id": world_id,
		"type": "unlike",
		"timestamp": int(Time.get_unix_time_from_system())
	}
	_push_to_action_buffer(action_data)
	
	# Actualizar UI local optimísticamente
	var new_likes = max(0, int(world_data.get("likes", 0)) - 1)
	world_data["likes"] = new_likes
	
	var all_cards = ui_root.find_children("*", "PanelContainer", true, false)
	for card in all_cards:
		if card.has_method("setup") and card.get("world_data") != null:
			if str(card.world_data.get("id", card.world_data.get("world_id", ""))) == world_id:
				card.world_data["likes"] = new_likes
				if card.has_method("set_liked_state"):
					card.set_liked_state(false)
				if is_instance_valid(card.get("likes_label")):
					card.likes_label.text = "👍 " + str(new_likes)
	_update_local_download_likes(world_id, new_likes)

func _update_local_download_likes(world_id: String, new_likes: int):
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

func _on_world_report_requested(world_data: Dictionary):
	var world_id = str(world_data.get("id", ""))
	if world_id == "": return
	
	if reported_worlds.has(world_id):
		_show_modal_message(tr("notice_title"), tr("already_reported_msg"))
		return
		
	_show_confirm_dialog(tr("confirm_report_world_title"), tr("confirm_report_world_msg"), func():
		reported_worlds.append(world_id)
		_save_workshop_economy()
		
		var action_data = {
			"world_id": world_id,
			"type": "report",
			"timestamp": int(Time.get_unix_time_from_system())
		}
		_push_to_action_buffer(action_data)
		_show_modal_message(tr("report_sent_title"), tr("report_sent_msg"))
	)

func _on_world_play_requested(world_data: Dictionary):
	_close_all_popups()
	var path = "user://download_world_" + str(world_data.get("id", "")) + ".dat"
	var loading = _show_processing_overlay(tr("load_worls") if TranslationServer.get_locale() == "es" else "Loading...")
	await get_tree().create_timer(0.1).timeout
	_load_world_from_path(path)
	if is_instance_valid(loading): loading.queue_free()

func _show_download_ad_popup(on_confirm: Callable, on_cancel: Callable, custom_text: String = "watch_ad_download_desc"):
	var s = _get_ui_scale()
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
	p_style.corner_radius_top_left = 15 * s; p_style.corner_radius_top_right = 15 * s
	p_style.corner_radius_bottom_left = 15 * s; p_style.corner_radius_bottom_right = 15 * s
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25 * s)
	margin.add_theme_constant_override("margin_right", 25 * s)
	margin.add_theme_constant_override("margin_top", 25 * s)
	margin.add_theme_constant_override("margin_bottom", 25 * s)
	popup.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20 * s)
	margin.add_child(vbox)
	
	var label = Label.new()
	label.text = tr(custom_text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", _get_safe_font())
	label.add_theme_font_size_override("font_size", 22 * s)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(label)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20 * s)
	vbox.add_child(hbox)
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("btn_cancel")
	btn_cancel.custom_minimum_size = Vector2(120 * s, 50 * s)
	btn_cancel.add_theme_font_override("font", _get_safe_font())
	btn_cancel.add_theme_font_size_override("font_size", 18 * s)
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.3, 0.3, 0.35)
	cancel_style.corner_radius_top_left = 8 * s; cancel_style.corner_radius_top_right = 8 * s
	cancel_style.corner_radius_bottom_left = 8 * s; cancel_style.corner_radius_bottom_right = 8 * s
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
	btn_ad.add_theme_font_size_override("font_size", 18 * s)
	btn_ad.add_theme_color_override("font_color", Color.BLACK)
	var ad_style = StyleBoxFlat.new()
	ad_style.bg_color = Color("#fbc531")
	ad_style.corner_radius_top_left = 8 * s; ad_style.corner_radius_top_right = 8 * s
	ad_style.corner_radius_bottom_left = 8 * s; ad_style.corner_radius_bottom_right = 8 * s
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

func _on_world_download_requested(world_data: Dictionary):
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
				
				# Update downloads.json
				var downloads = []
				if FileAccess.file_exists("user://downloads.json"):
					var df = FileAccess.open("user://downloads.json", FileAccess.READ)
					var text = df.get_as_text()
					if text != "":
						var dt = JSON.parse_string(text)
						if typeof(dt) == TYPE_ARRAY: downloads = dt
					
				# Remove old if exists
				var new_downloads = []
				for item in downloads:
					if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) != world_id:
						new_downloads.append(item)
						
				var final_world_data = world_data.duplicate()
				final_world_data["last_sync_time"] = int(Time.get_unix_time_from_system())
				new_downloads.insert(0, final_world_data) # Insert at front
				
				var df_write = FileAccess.open("user://downloads.json", FileAccess.WRITE)
				if df_write: df_write.store_string(JSON.stringify(new_downloads))
				
				if is_instance_valid(loading_overlay): loading_overlay.queue_free()
				_show_modal_message(tr("tab_mis_descargas"), tr("msg_download_success").format([world_data.get("title", "Mundo")]))
				ui_root.set_meta("workshop_current_tab", 3)
				ui_root.set_meta("workshop_page_3", 1)
				call_deferred("_setup_main_ui_containers")
				
				# Registrar descarga en el Buffer de RTDB para que el servidor lo procese en lote
				if not is_already_downloaded:
					download_history.append(world_id)
					var dh_write = FileAccess.open("user://download_history.json", FileAccess.WRITE)
					if dh_write: dh_write.store_string(JSON.stringify(download_history))
					
					var action_data = {
						"world_id": world_id,
						"type": "download",
						"timestamp": int(Time.get_unix_time_from_system())
					}
					_push_to_action_buffer(action_data)
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
			proceed_download.call() # Skip ad for already downloaded worlds
		elif free_downloads_remaining > 0:
			AnalyticsManager.log_event("workshop_download", {"type": "free"})
			free_downloads_remaining -= 1
			_save_workshop_economy()
			proceed_download.call()
		else:
			var on_cancel = func():
				print("Descarga cancelada (Anuncio rechazado)")
				
			var on_confirm = func():
				AdMobManager.show_workshop_rewarded()
				var success = await AdMobManager.workshop_rewarded_completed
				if success:
					AnalyticsManager.log_event("workshop_download", {"type": "ad"})
					free_downloads_remaining = 2
					_save_workshop_economy()
					proceed_download.call()
				else:
					_show_modal_message(tr("msg_error") if TranslationServer.get_locale() == "es" else "Error", tr("msg_ad_failed"))
					
			_show_download_ad_popup(on_confirm, on_cancel)

	var save_path_check = "user://download_world_" + world_id + ".dat"
	if FileAccess.file_exists(save_path_check):
		_show_confirm_dialog(tr("confirm_update_title"), tr("confirm_update_msg"), func():
			start_download_process.call()
		)
	else:
		start_download_process.call()

func _push_to_action_buffer(action_data: Dictionary):
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(func(_result, _response_code, _headers, _body):
		http_request.queue_free()
	)
	var url = "https://sandbox-ultra-5c7d5-default-rtdb.firebaseio.com/action_buffer.json"
	var body = JSON.stringify(action_data)
	var headers = ["Content-Type: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_POST, body)

func _show_upload_slot_selector(on_selected: Callable):
	var s = _get_ui_scale()
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.9)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	is_mouse_over_ui = true
	overlay.tree_exiting.connect(func(): is_mouse_over_ui = false)
	
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
	
	var is_landscape = get_viewport_rect().size.x > get_viewport_rect().size.y
	var base_height = 530 * s if is_landscape else 750 * s
	var m_height = min(base_height, get_viewport_rect().size.y * 0.95)
	panel.custom_minimum_size = Vector2(530 * s, m_height)
	center.add_child(panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20 * s)
	panel.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("upload_slot_label")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 36 * s)
	main_vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	var grid_hbox = HBoxContainer.new()
	grid_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	grid_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_hbox)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10 * s)
	grid.add_theme_constant_override("v_separation", 15 * s)
	grid_hbox.add_child(grid)
	
	for i in range(1, 11):
		var slot_data = _get_slot_data(i)
		
		var slot_panel = PanelContainer.new()
		slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		slot_panel.custom_minimum_size = Vector2(235 * s, 0)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.18)
		style.set_corner_radius_all(10 * s)
		style.border_width_left = 2; style.border_width_top = 2
		style.border_width_right = 2; style.border_width_bottom = 2
		style.border_color = Color(0.3, 0.3, 0.3)
		slot_panel.add_theme_stylebox_override("panel", style)
		grid.add_child(slot_panel)
		
		var vbox = VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_theme_constant_override("separation", 5 * s)
		slot_panel.add_child(vbox)
		
		var header = HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(header)
		
		var lbl_idx = Label.new()
		lbl_idx.mouse_filter = Control.MOUSE_FILTER_PASS
		lbl_idx.text = "#" + str(i)
		lbl_idx.add_theme_font_size_override("font_size", 26 * s)
		header.add_child(lbl_idx)
		
		var lbl_name = Label.new()
		lbl_name.mouse_filter = Control.MOUSE_FILTER_PASS
		lbl_name.text = slot_data.name if slot_data.has("name") else tr("empty")
		lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_name.clip_text = true
		lbl_name.add_theme_font_size_override("font_size", 24 * s)
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
		btn_select.add_theme_font_size_override("font_size", 20 * s)
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = Color("#00d2d3").lerp(Color.BLACK, 0.5)
		b_style.set_corner_radius_all(8 * s)
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
	btn_close.add_theme_font_size_override("font_size", 20 * s)
	main_vbox.add_child(btn_close)
	btn_close.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
	)

func _show_world_manager_dialog():
	var s = _get_ui_scale()
	var cache_data = ui_root.get_meta("workshop_mis_mundos_cache", [])
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.8)
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	is_mouse_over_ui = true
	overlay.tree_exiting.connect(func(): is_mouse_over_ui = false)
	
	var center = CenterContainer.new()
	overlay.add_child(center)
	
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(450 * s, 600 * s)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.12, 0.12, 0.16, 1.0)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = Color("#ff9f43")
	p_style.corner_radius_top_left = 20 * s; p_style.corner_radius_top_right = 20 * s
	p_style.corner_radius_bottom_left = 20 * s; p_style.corner_radius_bottom_right = 20 * s
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	margin.add_theme_constant_override("margin_top", 20 * s)
	margin.add_theme_constant_override("margin_bottom", 20 * s)
	popup.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15 * s)
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("world_manager_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 28 * s)
	title.add_theme_color_override("font_color", Color("#ff9f43"))
	main_vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400 * s)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 10 * s)
	scroll.add_child(list_vbox)
	
	if cache_data.size() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = tr("msg_no_worlds_uploaded")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_override("font", _get_safe_font())
		empty_lbl.add_theme_font_size_override("font_size", 18 * s)
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
			title_lbl.add_theme_font_size_override("font_size", 20 * s)
			row.add_child(title_lbl)
			
			var btn_mod = Button.new()
			btn_mod.text = "✏️"
			btn_mod.custom_minimum_size = Vector2(40 * s, 40 * s)
			row.add_child(btn_mod)
			btn_mod.pressed.connect(func():
				_play_action_sound("ui_click")
				overlay.queue_free()
				_show_edit_world_dialog(doc)
			)
			
			var btn_del = Button.new()
			btn_del.text = "🗑️"
			btn_del.custom_minimum_size = Vector2(40 * s, 40 * s)
			row.add_child(btn_del)
			var doc_id = doc.get("id", "")
			var doc_title = doc.get("title", "")
			btn_del.pressed.connect(func():
				_play_action_sound("ui_click")
				_show_confirm_dialog(tr("confirm_delete_world_title"), tr("confirm_delete_world_msg"), func():
					overlay.queue_free()
					_delete_world_from_workshop(doc_id, doc_title)
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
	btn_close.add_theme_font_size_override("font_size", 20 * s)
	main_vbox.add_child(btn_close)
	btn_close.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
	)

func _delete_world_from_workshop(world_id: String, world_title: String):
	var loading_overlay = _show_processing_overlay(tr("msg_deleting"))
	
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
		
	_show_centered_bubble("El mundo '" + world_title + "' ha sido eliminado.", Color("#ff7675"))
	AnalyticsManager.log_event("workshop_delete_world", {})
	
	var cache = ui_root.get_meta("workshop_mis_mundos_cache", [])
	for i in range(cache.size() - 1, -1, -1):
		if cache[i].get("id", "") == world_id:
			cache.remove_at(i)
	ui_root.set_meta("workshop_mis_mundos_cache", cache)
	ui_root.set_meta("workshop_total_uploaded_worlds", cache.size())
	_save_workshop_cache()
	
	_update_local_recientes_cache(world_id, true)
	
	_setup_workshop_ui()

func _load_workshop_cache():
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

func _save_workshop_cache():
	var file = FileAccess.open("user://workshop_cache.dat", FileAccess.WRITE)
	if file:
		var data = {
			"time": ui_root.get_meta("workshop_mis_mundos_cache_time", 0.0),
			"data": ui_root.get_meta("workshop_mis_mundos_cache", [])
		}
		file.store_var(data)

func _on_world_edit_requested(world_data: Dictionary):
	_show_edit_world_dialog(world_data)

func _show_edit_world_dialog(world_data: Dictionary):
	var s = _get_ui_scale()
	var selected_overwrite_slot_id = [-1]
	var world_id = world_data.get("id", "")
	var old_title = world_data.get("title", "")
	var old_category = world_data.get("category", 0)
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.8) # Dim background
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	is_mouse_over_ui = true
	overlay.tree_exiting.connect(func(): is_mouse_over_ui = false)
	
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
	p_style.corner_radius_top_left = 20 * s; p_style.corner_radius_top_right = 20 * s
	p_style.corner_radius_bottom_left = 20 * s; p_style.corner_radius_bottom_right = 20 * s
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	margin.add_theme_constant_override("margin_top", 20 * s)
	margin.add_theme_constant_override("margin_bottom", 20 * s)
	popup.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15 * s)
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("edit_world_dialog_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 28 * s)
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
		lbl.add_theme_font_size_override("font_size", 18 * s)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		return lbl
		
	var lbl_file = create_label.call("map_file_label")
	lbl_file.text = tr("map_file_label")
	main_vbox.add_child(lbl_file)
	
	var slot_hbox = HBoxContainer.new()
	slot_hbox.add_theme_constant_override("separation", 10 * s)
	main_vbox.add_child(slot_hbox)
	
	var btn_choose_slot = Button.new()
	btn_choose_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_choose_slot.text = tr("keep_online_file")
	btn_choose_slot.add_theme_font_override("font", _get_safe_font())
	btn_choose_slot.add_theme_font_size_override("font_size", 20 * s)
	btn_choose_slot.custom_minimum_size = Vector2(0, 45 * s)
	
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.15, 0.15, 0.2)
	c_style.border_width_left = 2; c_style.border_width_top = 2
	c_style.border_width_right = 2; c_style.border_width_bottom = 2
	c_style.border_color = Color(0.4, 0.4, 0.5)
	c_style.set_corner_radius_all(10 * s)
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
	btn_clear_slot.add_theme_font_size_override("font_size", 20 * s)
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
	char_count_lbl.add_theme_font_size_override("font_size", 16 * s)
	char_count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	char_count_lbl.text = str(old_title.length()) + "/30"
	name_label_hbox.add_child(char_count_lbl)
	
	var name_input = LineEdit.new()
	name_input.add_theme_font_override("font", _get_safe_font())
	name_input.add_theme_font_size_override("font_size", 20 * s)
	name_input.custom_minimum_size = Vector2(0, 45 * s)
	name_input.max_length = 30
	name_input.text = old_title
	main_vbox.add_child(name_input)
	
	name_input.focus_entered.connect(func():
		var kb_height = DisplayServer.virtual_keyboard_get_height()
		if kb_height == 0: kb_height = 300 * s
		center.add_theme_constant_override("margin_bottom", kb_height)
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
	cat_opt.add_theme_font_size_override("font_size", 20 * s)
	cat_opt.custom_minimum_size = Vector2(0, 40 * s)
	main_vbox.add_child(cat_opt)
	
	var categories = ["cat_none", "cat_circuits", "cat_npcs", "cat_art", "cat_music"]
	for cat in categories:
		cat_opt.add_item(tr(cat))
	cat_opt.selected = old_category
		
	var cat_popup = cat_opt.get_popup()
	cat_popup.add_theme_font_override("font", _get_safe_font())
	cat_popup.add_theme_font_size_override("font_size", 22 * s)
	
	var btn_hbox = HBoxContainer.new()
	var btn_confirm = Button.new()
	var conf_style = StyleBoxFlat.new()
	var h_conf = StyleBoxFlat.new()
	
	var reset_preview = func():
		selected_overwrite_slot_id[0] = -1
		btn_choose_slot.text = tr("keep_online_file")
		c_style.border_color = Color(0.4, 0.4, 0.5)
		btn_clear_slot.visible = false
		
		# Reset button
		btn_confirm.text = tr("confirm_save_changes_title")
		conf_style.bg_color = Color("#ff9f43")
		btn_confirm.add_theme_color_override("font_color", Color.WHITE)
		h_conf.bg_color = Color("#ffb142")
		
		# Reset thumbnail to original online cache if exists
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
		
		if uploads_today >= 3:
			btn_confirm.text = tr("btn_upload_ad")
			conf_style.bg_color = Color("#fbc531")
			btn_confirm.add_theme_color_override("font_color", Color.BLACK)
			h_conf.bg_color = Color("#f5f6fa")
			
	btn_choose_slot.pressed.connect(func():
		_play_action_sound("ui_click")
		if uploads_today >= 5:
			_show_centered_bubble(tr("msg_edit_limit_reached"), Color(0.8, 0.2, 0.2))
			return
		_show_upload_slot_selector(update_preview)
	)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer)
	
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 15 * s)
	main_vbox.add_child(btn_hbox)
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("btn_cancel")
	btn_cancel.custom_minimum_size = Vector2(130 * s, 50 * s)
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cancel.add_theme_font_override("font", _get_safe_font())
	btn_cancel.add_theme_font_size_override("font_size", 18 * s)
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.2, 0.2, 0.25)
	cancel_style.corner_radius_top_left = 10 * s; cancel_style.corner_radius_top_right = 10 * s
	cancel_style.corner_radius_bottom_left = 10 * s; cancel_style.corner_radius_bottom_right = 10 * s
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
	btn_confirm.add_theme_font_size_override("font_size", 18 * s)
	conf_style.bg_color = Color("#ff9f43")
	conf_style.corner_radius_top_left = 10 * s; conf_style.corner_radius_top_right = 10 * s
	conf_style.corner_radius_bottom_left = 10 * s; conf_style.corner_radius_bottom_right = 10 * s
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
						_save_workshop_economy()
						
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
					_save_workshop_cache()
					
					_update_local_recientes_cache(world_id, false, {"title": chosen_name, "category": chosen_cat})
					
					_setup_workshop_ui()
					
					if is_instance_valid(overlay): overlay.queue_free()
					_show_centered_bubble(tr("msg_changes_saved_success"), Color("#00cec9"))
				else:
					_show_centered_bubble("Error: " + msg, Color(0.8, 0.2, 0.2))
					
			if not WorkshopManager.update_completed.is_connected(on_done):
				WorkshopManager.update_completed.connect(on_done, CONNECT_ONE_SHOT)
			
			WorkshopManager.update_world(world_id, world_data, chosen_name, chosen_cat, overwrite_slot)
		
		var on_confirmed = func():
			if overwrite_slot != -1 and uploads_today >= 3:
				AdMobManager.show_workshop_rewarded()
				var success = await AdMobManager.workshop_rewarded_completed
				if success:
					proceed_edit.call()
				else:
					_show_centered_bubble(tr("msg_error") + ": " + tr("msg_ad_failed") if TranslationServer.get_locale() == "es" else "Error: " + tr("msg_ad_failed"), Color(0.8, 0.2, 0.2))
			else:
				proceed_edit.call()
			
		_show_confirm_dialog(tr("confirm_save_changes_title"), tr("confirm_save_changes_msg"), on_confirmed)
	)

func _show_upload_world_dialog():
	var s = _get_ui_scale()
	var selected_upload_slot_id = [1]
	
	# We will read data dynamically using _get_slot_data
	
	var overlay = PanelContainer.new()
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.8) # Dim background
	overlay.add_theme_stylebox_override("panel", overlay_style)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	is_mouse_over_ui = true
	overlay.tree_exiting.connect(func(): is_mouse_over_ui = false)
	
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
	p_style.corner_radius_top_left = 20 * s; p_style.corner_radius_top_right = 20 * s
	p_style.corner_radius_bottom_left = 20 * s; p_style.corner_radius_bottom_right = 20 * s
	popup.add_theme_stylebox_override("panel", p_style)
	center.add_child(popup)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	margin.add_theme_constant_override("margin_top", 20 * s)
	margin.add_theme_constant_override("margin_bottom", 20 * s)
	popup.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15 * s)
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("upload_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 28 * s)
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
		lbl.add_theme_font_size_override("font_size", 18 * s)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		return lbl
		
	main_vbox.add_child(create_label.call("upload_slot_label"))
	var btn_choose_slot = Button.new()
	btn_choose_slot.text = tr("btn_select_slot")
	btn_choose_slot.add_theme_font_override("font", _get_safe_font())
	btn_choose_slot.add_theme_font_size_override("font_size", 20 * s)
	btn_choose_slot.custom_minimum_size = Vector2(0, 45 * s)
	
	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0.15, 0.15, 0.2)
	c_style.border_width_left = 2; c_style.border_width_top = 2
	c_style.border_width_right = 2; c_style.border_width_bottom = 2
	c_style.border_color = Color(0.4, 0.4, 0.5)
	c_style.set_corner_radius_all(10 * s)
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
	char_count_lbl.add_theme_font_size_override("font_size", 16 * s)
	char_count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	char_count_lbl.text = "0/30"
	name_label_hbox.add_child(char_count_lbl)
	
	var name_input = LineEdit.new()
	name_input.add_theme_font_override("font", _get_safe_font())
	name_input.add_theme_font_size_override("font_size", 20 * s)
	name_input.custom_minimum_size = Vector2(0, 45 * s)
	name_input.max_length = 30
	main_vbox.add_child(name_input)
	
	name_input.focus_entered.connect(func():
		var kb_height = DisplayServer.virtual_keyboard_get_height()
		if kb_height == 0: kb_height = 300 * s
		center.add_theme_constant_override("margin_bottom", kb_height)
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
	cat_opt.add_theme_font_size_override("font_size", 20 * s)
	cat_opt.custom_minimum_size = Vector2(0, 40 * s)
	main_vbox.add_child(cat_opt)
	
	# Populate Category Options
	var categories = ["cat_none", "cat_circuits", "cat_npcs", "cat_art", "cat_music"]
	for cat in categories:
		cat_opt.add_item(tr(cat))
		
	var cat_popup = cat_opt.get_popup()
	cat_popup.add_theme_font_override("font", _get_safe_font())
	cat_popup.add_theme_font_size_override("font_size", 22 * s)
	
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
		_show_upload_slot_selector(update_preview)
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
		
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 15 * s)
	main_vbox.add_child(btn_hbox)
	
	var btn_cancel = Button.new()
	btn_cancel.text = tr("btn_cancel")
	btn_cancel.custom_minimum_size = Vector2(130 * s, 50 * s)
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cancel.add_theme_font_override("font", _get_safe_font())
	btn_cancel.add_theme_font_size_override("font_size", 18 * s)
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.2, 0.2, 0.25)
	cancel_style.corner_radius_top_left = 10 * s; cancel_style.corner_radius_top_right = 10 * s
	cancel_style.corner_radius_bottom_left = 10 * s; cancel_style.corner_radius_bottom_right = 10 * s
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
	btn_confirm.add_theme_font_size_override("font_size", 18 * s)
	var conf_style = StyleBoxFlat.new()
	conf_style.bg_color = Color("#00b894")
	conf_style.corner_radius_top_left = 10 * s; conf_style.corner_radius_top_right = 10 * s
	conf_style.corner_radius_bottom_left = 10 * s; conf_style.corner_radius_bottom_right = 10 * s
	btn_confirm.add_theme_stylebox_override("normal", conf_style)
	var h_conf = conf_style.duplicate()
	h_conf.bg_color = Color("#55efc4")
	btn_confirm.add_theme_stylebox_override("hover", h_conf)
	if uploads_today >= 5:
		btn_confirm.disabled = true
		btn_confirm.text = tr("upload_limit_reached")
		conf_style.bg_color = Color(0.4, 0.4, 0.4)
	elif uploads_today >= 3:
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
					_save_workshop_economy()
					
					var type_str = "ad" if (uploads_today - 1) >= 3 else "free"
					AnalyticsManager.log_event("workshop_upload", {
						"type": type_str,
						"slot": uploads_today
					})
					
					var cache = ui_root.get_meta("workshop_mis_mundos_cache", [])
					cache.insert(0, doc_data) # Add to top
					ui_root.set_meta("workshop_mis_mundos_cache", cache)
					ui_root.set_meta("workshop_total_uploaded_worlds", cache.size())
					_save_workshop_cache()
					
					_setup_workshop_ui()
					
					if is_instance_valid(overlay): overlay.queue_free()
					_show_centered_bubble(tr("upload_success").replace("'{0}'", "\"" + chosen_name + "\"").replace("{0}", "\"" + chosen_name + "\""), Color("#00cec9"))
				else:
					_show_centered_bubble("Error: " + msg, Color(0.8, 0.2, 0.2))
					
			if not WorkshopManager.upload_completed.is_connected(on_done):
				WorkshopManager.upload_completed.connect(on_done, CONNECT_ONE_SHOT)
			
			WorkshopManager.upload_world(slot_id, chosen_name, cat_id)
			
		var on_confirmed = func():
			if uploads_today >= 3:
				AdMobManager.show_workshop_rewarded()
				var success = await AdMobManager.workshop_rewarded_completed
				if success:
					proceed_upload.call()
				else:
					_show_centered_bubble(tr("msg_error") + ": " + tr("msg_ad_failed") if TranslationServer.get_locale() == "es" else "Error: " + tr("msg_ad_failed"), Color(0.8, 0.2, 0.2))
			else:
				proceed_upload.call()
				
		_show_confirm_dialog(tr("confirm_upload_world_title"), tr("confirm_upload_world_msg"), on_confirmed)
	)
	btn_hbox.add_child(btn_confirm)

func _setup_lab_ui():
	var s = _get_ui_scale()
	var lab_btn = _create_vertical_category_btn("🧪", "lab")
	lab_btn.name = "LabBtn"
	ui_elements["lab_btn"] = lab_btn
	lab_btn.add_theme_font_override("font", _get_safe_font())
	lab_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	lab_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_hbox.add_child(lab_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.18, 0.15, 0.22, 1.0)
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.3, 0.5)
	lab_btn.add_theme_stylebox_override("normal", btn_style)
	lab_btn.add_theme_stylebox_override("hover", btn_style)
	lab_btn.add_theme_stylebox_override("pressed", btn_style)
	lab_btn.set_meta("base_style", btn_style)
	
	ui_root = get_parent().get_node("UI")
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
	ui_elements["lab_scroll"] = scroll
	
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
	ui_elements["lab_panel_title"] = title_lbl
	top_hbox.add_child(title_lbl)
	
	var time_lbl = Label.new()
	time_lbl.text = "Tiempo: 12:00:00"
	time_lbl.add_theme_font_override("font", _get_safe_font())
	time_lbl.add_theme_font_size_override("font_size", 20 * s)
	time_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	ui_elements["lab_time_lbl"] = time_lbl
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
	title_overlay.add_theme_font_size_override("font_size", 34 * s) # Slightly smaller to prevent decentering
	title_overlay.add_theme_color_override("font_color", Color.YELLOW)
	ui_elements["lab_overlay_title"] = title_overlay
	
	var desc_overlay = Label.new()
	desc_overlay.text = tr("lab_overlay_desc")
	desc_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_overlay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_overlay.add_theme_font_override("font", _get_safe_font())
	desc_overlay.add_theme_font_size_override("font_size", 25 * s) # Much more readable and centered
	desc_overlay.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	ui_elements["lab_overlay_desc"] = desc_overlay
	
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
	ui_elements["not_now_btn"] = no_btn
	var no_st = StyleBoxFlat.new()
	no_st.bg_color = Color(0.2, 0.2, 0.25)
	no_st.corner_radius_top_left = 12*s; no_st.corner_radius_top_right = 12*s; no_st.corner_radius_bottom_left = 12*s; no_st.corner_radius_bottom_right = 12*s
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
	ui_elements["watch_ad_btn"] = ad_btn
	var ad_st = StyleBoxFlat.new()
	ad_st.bg_color = Color(0.1, 0.5, 0.2)
	ad_st.corner_radius_top_left = 12*s; ad_st.corner_radius_top_right = 12*s; ad_st.corner_radius_bottom_left = 12*s; ad_st.corner_radius_bottom_right = 12*s
	ad_btn.add_theme_stylebox_override("normal", ad_st)
	ad_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		await AdMobManager.show_lab_rewarded()
	)
	btn_hbox.add_child(ad_btn)
	
	ui_elements["lab_overlay"] = lab_overlay
	lab_panel.add_child(lab_overlay)
	
	# SYNC INITIAL VISIBILITY
	lab_overlay.visible = !is_lab_unlocked
	
	lab_btn.pressed.connect(func(): 
		_toggle_category_panel(lab_panel)
		if is_instance_valid(lab_panel) and lab_panel.visible:
			if not is_lab_tutorial_done and is_lab_unlocked:
				lab_tutorial_step = 1
				lab_custom_data[0]["grav"] = -1
				lab_custom_data[0]["state"] = -1
				_update_lab_inspector()
				_update_lab_tutorial_highlight()
		else:
			if lab_tutorial_step == 5: lab_tutorial_step = 6
			else: lab_tutorial_step = 0
			_update_lab_tutorial_highlight()
	)
	
	lab_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	lab_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	var slots_hbox = HBoxContainer.new()
	slots_hbox.name = "LabSlotsHBox"
	slots_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_hbox.add_theme_constant_override("separation", 60 * s)
	v_box.add_child(slots_hbox)
	ui_elements["lab_slots_hbox"] = slots_hbox
	
	ui_elements["lab_slot_borders"] = []
	ui_elements["lab_name_edits"] = []
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
		out_st.bg_color = Color(0,0,0,1)
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
		ui_elements["lab_slot_borders"].append(pnl)
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			lab_selected_slot = i
			if lab_tutorial_step == 1:
				# TUTORIAL DYNAMIC RESET: Adapt to whichever slot the user chooses
				lab_custom_data[i]["grav"] = -1
				lab_custom_data[i]["state"] = -1
			_update_lab_inspector()
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
			_update_custom_mats_in_material_grid() # Correct function to refresh HUD
		)
		name_edit.focus_entered.connect(func():
			if lab_selected_slot != i:
				lab_selected_slot = i
				if lab_tutorial_step == 1:
					# TUTORIAL SYNC: If they focus/type in another slot, reset it for tutorial focus
					lab_custom_data[i]["grav"] = -1
					lab_custom_data[i]["state"] = -1
				_update_lab_inspector()
		)
		name_edit.text_submitted.connect(func(_t):
			if lab_tutorial_step == 1:
				lab_tutorial_step = 2
				_update_lab_tutorial_highlight()
		)
		name_edit.focus_exited.connect(func():
			if lab_tutorial_step == 1 and lab_custom_data[i]["name"].length() > 1:
				lab_tutorial_step = 2
				_update_lab_tutorial_highlight()
		)
		slot_vbox.add_child(name_edit)
		ui_elements["lab_name_edits"].append(name_edit)
	
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
	
	ui_elements["lab_col_color"] = col_color
	ui_elements["lab_col_grav"] = col_grav
	ui_elements["lab_col_est"] = col_est
	
	for l in [col_color_title, col_grav_title, col_est_title]:
		l.add_theme_font_override("font", _get_safe_font())
		l.add_theme_font_size_override("font_size", 20 * s)
		l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	
	ui_elements["lab_col_pickers"] = []
	ui_elements["lab_col_trash"] = []
	
	for i in range(3):
		var hb = HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 8 * s)
		col_color.add_child(hb)
		
		var num_lbl = Label.new()
		num_lbl.text = str(i+1)
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
			var prop = "c" + str(i+1)
			lab_custom_data[lab_selected_slot][prop] = c
			_update_lab_preview(lab_selected_slot)
			_update_lab_inspector()
		)
		cp.get_popup().popup_hide.connect(func():
			if lab_tutorial_step == 2:
				var data = lab_custom_data[lab_selected_slot]
				# Only advance if the user actually picked a color (Alpha > 0)
				if data["c1"].a > 0.0 or data["c2"].a > 0.0 or data["c3"].a > 0.0:
					lab_tutorial_step = 3
					_update_lab_tutorial_highlight()
		)
		hb.add_child(cp)
		ui_elements["lab_col_pickers"].append(cp)
		
		var trash = Button.new()
		trash.text = "🗑️"
		trash.add_theme_font_override("font", _get_safe_font())
		trash.add_theme_font_size_override("font_size", 20 * s)
		trash.custom_minimum_size = Vector2(25 * s, 30 * s)
		trash.mouse_filter = Control.MOUSE_FILTER_PASS
		trash.pressed.connect(func():
			_play_action_sound("ui_click")
			var prop = "c" + str(i+1)
			lab_custom_data[lab_selected_slot][prop] = Color(0,0,0,0) # Empty indication
			_update_lab_preview(lab_selected_slot)
			
			# TUTORIAL BACK-STEP: If they delete all colors, force them back to Step 2
			if lab_tutorial_step > 2:
				var data = lab_custom_data[lab_selected_slot]
				if data["c1"].a == 0.0 and data["c2"].a == 0.0 and data["c3"].a == 0.0:
					lab_tutorial_step = 2
					_update_lab_tutorial_highlight()
			
			_update_lab_inspector()
		)
		hb.add_child(trash)
		ui_elements["lab_col_trash"].append(trash)
	
	# Spacer for texture
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
		_update_lab_preview(lab_selected_slot)
	)
	col_color.add_child(mix_slider)
	ui_elements["lab_mix_slider"] = mix_slider
		
	ui_elements["lab_grav_buttons"] = []
	var grav_options = ["GRAV_SLOW", "GRAV_NORMAL", "GRAV_UP", "GRAV_STATIC"]
	for j in range(grav_options.size()):
		var btn = Button.new(); btn.text = tr(grav_options[j]); btn.toggle_mode = true; btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 22 * s)
		var st_n = StyleBoxFlat.new(); st_n.bg_color = Color(0.15,0.15,0.2)
		st_n.border_width_left=1; st_n.border_width_right=1; st_n.border_width_top=1; st_n.border_width_bottom=1
		st_n.border_color = Color(0.3, 0.3, 0.4)
		st_n.corner_radius_top_left=6*s; st_n.corner_radius_top_right=6*s; st_n.corner_radius_bottom_left=6*s; st_n.corner_radius_bottom_right=6*s
		st_n.content_margin_top=6*s; st_n.content_margin_bottom=6*s
		btn.add_theme_stylebox_override("normal", st_n)
		var st_p = StyleBoxFlat.new(); st_p.bg_color = Color(0.2,0.5,1.0)
		st_p.corner_radius_top_left=6*s; st_p.corner_radius_top_right=6*s; st_p.corner_radius_bottom_left=6*s; st_p.corner_radius_bottom_right=6*s
		st_p.content_margin_top=6*s; st_p.content_margin_bottom=6*s
		btn.add_theme_stylebox_override("pressed", st_p)
		btn.toggled.connect(func(pressed):
			if pressed:
				_play_action_sound("ui_click")
				lab_custom_data[lab_selected_slot]["grav"] = j
				_update_lab_inspector()
				if lab_tutorial_step == 3:
					lab_tutorial_step = 4
					_update_lab_tutorial_highlight()
		)
		col_grav.add_child(btn)
		ui_elements["lab_grav_buttons"].append(btn)
		
	ui_elements["lab_est_buttons"] = []
	var est_options = ["STATE_GAS", "STATE_LIQUID", "STATE_POWDER", "STATE_SOLID"]
	for j in range(est_options.size()):
		var btn = Button.new(); btn.text = tr(est_options[j]); btn.toggle_mode = true; btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 22 * s)
		var st_n = StyleBoxFlat.new(); st_n.bg_color = Color(0.15,0.15,0.2)
		st_n.border_width_left=1; st_n.border_width_right=1; st_n.border_width_top=1; st_n.border_width_bottom=1
		st_n.border_color = Color(0.3, 0.3, 0.4)
		st_n.corner_radius_top_left=6*s; st_n.corner_radius_top_right=6*s; st_n.corner_radius_bottom_left=6*s; st_n.corner_radius_bottom_right=6*s
		st_n.content_margin_top=6*s; st_n.content_margin_bottom=6*s
		btn.add_theme_stylebox_override("normal", st_n)
		var st_p = StyleBoxFlat.new(); st_p.bg_color = Color(0.2,0.5,1.0)
		st_p.corner_radius_top_left=6*s; st_p.corner_radius_top_right=6*s; st_p.corner_radius_bottom_left=6*s; st_p.corner_radius_bottom_right=6*s
		st_p.content_margin_top=6*s; st_p.content_margin_bottom=6*s
		btn.add_theme_stylebox_override("pressed", st_p)
		btn.toggled.connect(func(pressed):
			if pressed:
				_play_action_sound("ui_click")
				lab_custom_data[lab_selected_slot]["state"] = j
				_update_lab_inspector()
				if lab_tutorial_step == 4:
					lab_tutorial_step = 5
					_update_lab_tutorial_highlight()
		)
		col_est.add_child(btn)
		ui_elements["lab_est_buttons"].append(btn)
	
	var tags_sep = make_h_line.call()
	v_box.add_child(tags_sep)
	
	var car_title = Label.new()
	car_title.text = tr("LAB_CHARACTERISTICS")
	car_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_title.add_theme_font_override("font", _get_safe_font())
	car_title.add_theme_font_size_override("font_size", 20 * s)
	v_box.add_child(car_title)
	ui_elements["lab_car_title"] = car_title
	
	var tags_main_vbox = VBoxContainer.new()
	v_box.add_child(tags_main_vbox)
	ui_elements["lab_tags_vbox"] = tags_main_vbox
	
	# --- SECCIÓN DE CARACTERÍSTICAS DINÁMICA ---
	var tag_sections = [
		{
			"id": "interaction",
			"name": tr("interaction_tags"), # "🛠️ Etiquetas de Interacción"
			"tags": ["FLAMMABLE", "INCENDIARY", "EXPLOSIVE", "ANTI_EXPLOSIVE", "VIRUS", "INVINCIBLE", "VORTEX", "REPEL"]
		},
		{
			"id": "exp_special",
			"name": tr("exp_special"),     # "Explosiones Especiales"
			"parent": "EXPLOSIVE",
			"tags": ["EXP_ELECTRIC", "EXP_ACID", "EXP_WATER", "EXP_LAVA", "EXP_NPC", "EXP_LIFE", "EXP_GAS", "EXP_QUAKE", "EXP_PINATA"]
		},
		{
			"id": "exp_npc_team",
			"name": tr("exp_npc_team"),    # "Equipo de la Explosión"
			"parent": "EXP_NPC",           # Solo aparece si se activa explosión de NPCs
			"radio": true,                 # Solo se puede elegir uno
			"tags": ["EXP_TEAM_RED", "EXP_TEAM_BLUE", "EXP_TEAM_GREEN", "EXP_TEAM_YELLOW", "EXP_TEAM_MIXED"]
		},
		{
			"id": "combustion",
			"name": tr("combustion"),       # "Combustión"
			"parent": "FLAMMABLE",          # Solo aparece si esta etiqueta está activa
			"radio": true,                  # Solo se puede elegir una
			"tags": ["BURN_SMOKE", "BURN_COAL"]
		},
		{
			"id": "electricity",
			"name": tr("electricity"),     # "Electricidad"
			"tags": ["ELECTRICITY", "CONDUCTOR", "ELECTRIC_ACTIVATED", "RADIOACTIVE"]
		},
		{
			"id": "corrosion",
			"name": tr("corrosion"),       # "Corrosión"
			"tags": ["ACID", "ANTI_ACID"]
		}
	]
	
	ui_elements["lab_tag_buttons"] = {}
	ui_elements["lab_tag_sections"] = {} # Para ocultar/mostrar secciones enteras
	
	for section in tag_sections:
		var sec_vbox = VBoxContainer.new()
		ui_elements["lab_tag_sections"][section["id"]] = sec_vbox
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
			st_n.border_width_left=2; st_n.border_width_top=2; st_n.border_width_right=2; st_n.border_width_bottom=2
			st_n.border_color = Color(0.3, 0.3, 0.4)
			st_n.corner_radius_top_left=12*s; st_n.corner_radius_top_right=12*s; st_n.corner_radius_bottom_left=12*s; st_n.corner_radius_bottom_right=12*s
			st_n.content_margin_left=16*s; st_n.content_margin_right=16*s; st_n.content_margin_top=10*s; st_n.content_margin_bottom=10*s
			tb.add_theme_stylebox_override("normal", st_n)
			
			var st_p = StyleBoxFlat.new()
			st_p.bg_color = Color(0.2, 0.55, 0.3)
			st_p.border_width_left=2; st_p.border_width_top=2; st_p.border_width_right=2; st_p.border_width_bottom=2
			st_p.border_color = Color(0.3, 0.8, 0.5)
			st_p.corner_radius_top_left=12*s; st_p.corner_radius_top_right=12*s; st_p.corner_radius_bottom_left=12*s; st_p.corner_radius_bottom_right=12*s
			st_p.content_margin_left=16*s; st_p.content_margin_right=16*s; st_p.content_margin_top=10*s; st_p.content_margin_bottom=10*s
			tb.add_theme_stylebox_override("pressed", st_p)
			
			tb.toggled.connect(func(pressed):
				_play_action_sound("ui_click")
				var current_data = lab_custom_data[lab_selected_slot]
				
				if pressed:
					# Si es una sección Radio (Combustión), apagar las otras del mismo grupo
					if section.get("radio", false):
						for other_tag in section["tags"]:
							if other_tag != tag: current_data["tags"].erase(other_tag)
					
					current_data["tags"][tag] = true
				else:
					current_data["tags"].erase(tag)
				
				_update_lab_inspector()
				if lab_tutorial_step == 5:
					# Finish Lab part and move to HUD highlight
					if is_instance_valid(lab_panel): lab_panel.visible = false
					lab_tutorial_step = 6
					_update_lab_tutorial_highlight()
			)
			flow.add_child(tb)
			ui_elements["lab_tag_buttons"][tag] = tb

# (Diagnostic functions removed)

func _toggle_category_panel(target_panel: Control):
	_play_action_sound("ui_click")
	var was_visible = is_instance_valid(target_panel) and target_panel.visible
	
	is_mechanism_mode_active = false
	_close_all_popups()
	
	if target_panel != paint_panel:
		is_paint_tool_active = false
	
	# TOGGLE TARGET
	if is_instance_valid(target_panel):
		target_panel.visible = !was_visible
		if target_panel == paint_panel and target_panel.visible:
			is_paint_tool_active = true
	
	_update_menu_highlights()
	
	var any_visible = false
	if is_instance_valid(tools_panel) and tools_panel.visible: any_visible = true
	if is_instance_valid(workshop_panel) and workshop_panel.visible: any_visible = true
	if is_instance_valid(disaster_panel) and disaster_panel.visible: any_visible = true
	if is_instance_valid(npc_panel) and npc_panel.visible: any_visible = true
	if is_instance_valid(paint_panel) and paint_panel.visible: any_visible = true
	if is_instance_valid(achievement_panel) and achievement_panel.visible: any_visible = true
	if is_instance_valid(lab_panel) and lab_panel.visible: any_visible = true
	if is_instance_valid(save_panel) and save_panel.visible: any_visible = true
	
	if not any_visible and force_grid_visible and not is_grid_tutorial_done:
		_show_grid_tutorial_bubble()
		is_grid_tutorial_done = true
		_save_tool_settings()

func _on_tools_btn_pressed():
	_toggle_category_panel(tools_panel)
	if is_instance_valid(tools_panel) and tools_panel.visible:
		_show_menu_reminder("tools", tools_panel.get_child(0), "TUTORIAL_STEP_2")
		
		# Workshop discovery logic
		if not FileAccess.file_exists("user://workshop_discovery_shown.save") and ui_elements.has("tools_btn"):
			_stop_pulse(ui_elements["tools_btn"])
			if ui_elements.has("btn_comunidad"):
				_start_pulse(ui_elements["btn_comunidad"])
			
			var scroll = tools_panel.find_child("ToolsScroll", true, false)
			if scroll and ui_elements.has("btn_comunidad"):
				var btn_com = ui_elements["btn_comunidad"]
				
				# First scroll to it
				get_tree().process_frame.connect(func():
					scroll.ensure_control_visible(btn_com)
					
					# Then wait another frame so layout is updated
					get_tree().process_frame.connect(func():
						var bubble = _show_unified_tutorial_bubble(Vector2i.ZERO, "msg_workshop_discovery", func():
							# The user clicked "Got it"
							var save_path = "user://workshop_discovery_shown.save"
							if not FileAccess.file_exists(save_path):
								var file = FileAccess.open(save_path, FileAccess.WRITE)
								if file:
									file.store_string("shown")
									file.close()
						, Color(0.1, 0.4, 0.8, 0.95), 180.0)
						
						if is_instance_valid(bubble):
							ui_elements["workshop_discovery_bubble"] = bubble
							var s = _get_ui_scale()
							var btn_rect = btn_com.get_global_rect()
							bubble.position.x = btn_rect.position.x + btn_rect.size.x / 2.0 - bubble.size.x / 2.0
							bubble.position.y = btn_rect.position.y - bubble.size.y - 15 * s
							
							var screen_size = get_viewport_rect().size
							bubble.position.x = clamp(bubble.position.x, 10 * s, screen_size.x - bubble.size.x - 10 * s)
							bubble.position.y = clamp(bubble.position.y, 10 * s, screen_size.y - bubble.size.y - 10 * s)
					, CONNECT_ONE_SHOT)
				, CONNECT_ONE_SHOT)
	
	# Update tutorial highlight if we just opened/closed tools
	if lab_tutorial_step == 6:
		_update_lab_tutorial_highlight()

func _update_lab_tutorial_highlight():
	# 1. Clean old rects
	for r in tutorial_rects:
		if is_instance_valid(r): r.queue_free()
	tutorial_rects.clear()
	
	if lab_tutorial_step == 0: return
	
	# 2. Find the target
	var target: Control = null
	match lab_tutorial_step:
		1: 
			var name_edits = ui_elements.get("lab_name_edits", [])
			if name_edits.size() > lab_selected_slot:
				target = name_edits[lab_selected_slot]
			else:
				target = ui_elements.get("lab_slots_hbox")
		2: target = ui_elements.get("lab_col_color")
		3: target = ui_elements.get("lab_col_grav")
		4: target = ui_elements.get("lab_col_est")
		5: target = ui_elements.get("lab_tags_vbox")
		6: 
			var hud_slots = ui_elements.get("lab_custom_slots_hud", [])
			if hud_slots.size() > lab_selected_slot:
				target = hud_slots[lab_selected_slot]
			else:
				target = ui_elements.get("lab_first_custom_slot")
	
	if not is_instance_valid(target): return
	
	# Skip if Step 6 but tools panel is not visible
	if lab_tutorial_step == 6 and (not is_instance_valid(tools_panel) or not tools_panel.visible):
		_on_tools_btn_pressed()
	
	# 3. WAIT FOR GPU/LAYOUT SYNC (Crucial for correct global_rect calculation)
	await get_tree().process_frame
	if not is_instance_valid(target) or not target.is_inside_tree(): return
	
	var parent: Node = ui_root
	var tr_rect = target.get_global_rect()
	
	# CLIPPING: Ensure the highlight doesn't spill outside the Laboratory Panel (Steps 1-5)
	if lab_tutorial_step >= 1 and lab_tutorial_step <= 5 and is_instance_valid(lab_panel):
		if ui_elements.has("lab_scroll"):
			ui_elements["lab_scroll"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	elif ui_elements.has("lab_scroll"):
		ui_elements["lab_scroll"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		
	var screen_size = get_viewport_rect().size
	
	# 4. Expand and Clip the cutout for ultra-precise visuals
	var margin = 8 * _get_ui_scale()
	if lab_tutorial_step == 5: margin = 4 * _get_ui_scale() # Tighter for tags
	var cutout = tr_rect.grow(margin)
	
	# Final CLIP: Keep the "hole" strictly inside the viewable area (prevent spilling into HUD)
	if lab_tutorial_step >= 1 and lab_tutorial_step <= 5:
		var clip_rect = lab_panel.get_global_rect()
		if ui_elements.has("lab_scroll") and is_instance_valid(ui_elements["lab_scroll"]):
			clip_rect = ui_elements["lab_scroll"].get_global_rect()
		cutout = cutout.intersection(clip_rect)
	
	var create_dim = func():
		var r = ColorRect.new()
		r.color = Color(0, 0, 0, 0.85) # Ultra-dark for maximum focus
		r.mouse_filter = Control.MOUSE_FILTER_STOP # Block input everywhere else
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
	
	# Area Left (Middle)
	var left = create_dim.call()
	left.set_begin(Vector2(0, cutout.position.y))
	left.set_end(Vector2(cutout.position.x, cutout.end.y))
	
	# Area Right (Middle)
	var right = create_dim.call()
	right.set_begin(Vector2(cutout.end.x, cutout.position.y))
	right.set_end(Vector2(screen_size.x, cutout.end.y))

	# VISUAL HINT FOR STEP 1 (Type Name)
	if lab_tutorial_step == 1:
		var s = _get_ui_scale()
		var icon = Label.new()
		icon.text = "✏️"
		icon.add_theme_font_size_override("font_size", 40 * s)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Place icon directly above the highlighted name box
		icon.position = Vector2(cutout.position.x + cutout.size.x / 2.0 - 20 * s, cutout.position.y - 50 * s)
		parent.add_child(icon)
		tutorial_rects.append(icon)
		
		var tw = icon.create_tween()
		tw.tween_property(icon, "position:y", icon.position.y - 10 * s, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(icon, "position:y", icon.position.y, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.set_loops() # Infinite loop safely managed by icon lifecycle

func _save_lab_state():
	var clean_data = []
	for d in lab_custom_data:
		var c = d.duplicate()
		c.erase("node")
		# Convert colors to HTML for JSON safety
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

func _on_window_resized():
	var vp_size = get_viewport_rect().size
	var new_is_landscape = vp_size.x > vp_size.y
	if new_is_landscape != current_is_landscape:
		# Orientation axis flipped (Portrait <-> Landscape), reload scene!
		# Remove the signal to avoid loops during reload
		if get_tree().get_root().size_changed.is_connected(_on_window_resized):
			get_tree().get_root().size_changed.disconnect(_on_window_resized)
		
		# Immediately obscure the screen to hide ugly OS stretching
		var overlay = ColorRect.new()
		overlay.color = Color.BLACK
		overlay.z_index = 4096 # Topmost
		overlay.custom_minimum_size = Vector2(10000, 10000)
		overlay.size = Vector2(10000, 10000)
		overlay.position = Vector2(-5000, -5000)
		add_child(overlay)
		
		# Let the black screen render for one frame before freezing to load
		await get_tree().process_frame
		
		# Preservation mechanism: save the map before OS resizes Godot
		_save_lab_state()
		_save_rotation_cache()
		
		get_tree().reload_current_scene()

func _save_rotation_cache():
	var path = "user://rotation_cache.dat"
	
	# CLEAN CIRCULAR REFERENCES BEFORE SAVING
	# NPCs often point to each other (social_target, cached_target), which causes infinite recursion in store_var
	var clean_npcs = []
	var keys_to_nullify = ["social_target", "cached_target", "cached_closest_enemy", "cached_closest_ally", "social_partner"]
	for npc in active_npcs:
		var c = {}
		for key in npc:
			if key in keys_to_nullify:
				c[key] = null
			else:
				c[key] = npc[key]
		clean_npcs.append(c)
		
	var save_dict = {
		"width": grid_width,
		"height": grid_height,
		"grid": cells,
		"charge": charge_array,
		"tags": tags_array,
		"cell_paint": cell_paint_colors,
		"bg_paint": background_img.get_data().to_int32_array(),
		"npcs": clean_npcs,
		"npc_id_counter": _npc_id_counter,
		"active_logic_gates": active_logic_gates,
		"active_pistons": active_pistons,
		"door_registry": door_registry.keys(),
		"door_close_timers": door_close_timers,
		"phase_block_registry": phase_block_registry.keys()
	}
	var file = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_var(save_dict, true)
		file.close()

func _map_grid_data(dict: Dictionary):
	if dict.has("npc_id_counter"):
		_npc_id_counter = dict["npc_id_counter"]
		
	if dict.has("width") and dict.has("height"):
		var old_w = int(dict["width"])
		var old_h = int(dict["height"])
		var y_offset = old_h - grid_height
		y_offset = int(floor(float(y_offset) / 4.0)) * 4
		var x_offset = int((old_w - grid_width) / 2.0)
		x_offset = int(floor(float(x_offset) / 4.0)) * 4
		
		var _old_cells = dict["grid"]
		var _old_charge = dict["charge"]
		var _old_tags = dict["tags"]
		var _old_paint = dict["cell_paint"]
		
		var cpp_state = {
			"cells": cells,
			"tags_array": tags_array,
			"charge_array": charge_array,
			"cell_paint_colors": cell_paint_colors,
			"charge_visual_buffer": charge_visual_buffer,
			"chunks_active": chunks_active,
			"chunks_x": chunks_x,
			"chunks_y": chunks_y
		}
		
		cpp_state = map_grid_data(cpp_state, dict, grid_width, grid_height)
		
		cells = cpp_state["cells"]
		tags_array = cpp_state["tags_array"]
		charge_array = cpp_state["charge_array"]
		cell_paint_colors = cpp_state["cell_paint_colors"]
		charge_visual_buffer = cpp_state["charge_visual_buffer"]
		chunks_active = cpp_state["chunks_active"]
		
		var out_next = cpp_state["next_charge_indices"]
		if out_next.size() > 0:
			next_charge_indices.append_array(out_next)
			charge_dirty = true
			
		var out_metro = cpp_state["active_metronome_indices"]
		for idx in out_metro:
			active_metronome_indices[idx] = true
		
		if dict.has("bg_paint"):
			var bg_data = dict["bg_paint"]
			var b_array = PackedInt32Array()
			b_array.resize(bg_data.size())
			for i in range(bg_data.size()): b_array[i] = int(bg_data[i])
			var old_bg_img = Image.create_from_data(old_w, old_h, false, Image.FORMAT_RGBA8, b_array.to_byte_array())
			
			for new_y in range(grid_height):
				var old_y = new_y + y_offset
				if old_y < 0 or old_y >= old_h: continue
				for new_x in range(grid_width):
					var old_x = new_x + x_offset
					if old_x < 0 or old_x >= old_w: continue
					var color = old_bg_img.get_pixel(old_x, old_y)
					if color.a > 0.0:
						background_img.set_pixel(new_x, new_y, color)
			
			background_tex.update(background_img)
			
		if dict.has("npcs"):
			active_npcs.clear()
			var old_npcs = dict["npcs"]
			for npc in old_npcs:
				var new_x = npc["pos"].x - x_offset
				var new_y = npc["pos"].y - y_offset
				if new_x >= 0 and new_x < grid_width and new_y >= 0 and new_y < grid_height:
					var new_npc = npc.duplicate()
					new_npc["pos"] = Vector2i(new_x, new_y)
					
					# FIX: Also translate last render and logic positions to avoid "ghost" pixels and AI freeze
					# The offset direction must match the inverse of the cell mapping (new = old - offset)
					if new_npc.has("last_render_x"): new_npc["last_render_x"] -= x_offset
					if new_npc.has("last_render_y"): new_npc["last_render_y"] -= y_offset
					if new_npc.has("spawn_y"): new_npc["spawn_y"] -= y_offset
					if new_npc.has("last_pos_x"): new_npc["last_pos_x"] -= x_offset
					
					# Clear references to old NPCs (as they belong to the previous scene)
					new_npc["social_target"] = null
					new_npc["social_timer"] = 0.0
					new_npc["cached_target"] = null
					new_npc["cached_closest_enemy"] = null
					new_npc["cached_closest_ally"] = null
					
					new_npc["stuck_timer"] = 0.0 # Force re-think
					if not new_npc.has("invul_timer"):
						new_npc["invul_timer"] = 0.0
					active_npcs.append(new_npc)
	
	background_dirty = true
	element_paint_dirty = true # Force update of the custom paint texture after reload

func _load_rotation_cache():
	var path = "user://rotation_cache.dat"
	if not FileAccess.file_exists(path): return
	
	var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file:
		var dict = file.get_var(true)
		file.close()
		DirAccess.remove_absolute(path)
		
		if dict:
			_map_grid_data(dict)
			_load_active_logic_gates(dict)
			_reconstruct_sources_from_cells(dict)

func _load_lab_state():
	# PC/EDITOR SKIP: Always unlock and skip logs for smoother testing
	if OS.has_feature("editor"):
		_set_lab_unlocked(true)
		lab_unlock_expiry_unix = int(Time.get_unix_time_from_system()) + 86400
		return

	if FileAccess.file_exists("user://lab_state.json"):
		var file = FileAccess.open("user://lab_state.json", FileAccess.READ)
		var json_str = file.get_as_text()
		file.close()
		
		var save = JSON.parse_string(json_str)
		if typeof(save) == TYPE_DICTIONARY:
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
	if now < lab_unlock_expiry_unix:
		_set_lab_unlocked(true)
	else:
		_set_lab_unlocked(false)
		
	# CRITICAL: Re-apply loaded definitions to the engine arrays
	for i in range(3):
		_apply_custom_material_to_engine(i)
	_sync_palette_to_shader()

func _set_lab_unlocked(unlocked: bool):
	is_lab_unlocked = unlocked
	if ui_elements.has("lab_overlay") and is_instance_valid(ui_elements["lab_overlay"]):
		ui_elements["lab_overlay"].visible = !unlocked
	_update_custom_mats_in_material_grid()

func _update_custom_mats_in_material_grid():
	if not is_instance_valid(main_controls): return
	var mat_grid_node = main_controls.find_child("MaterialGrid", true, false)
	if not is_instance_valid(mat_grid_node): return
	
	# Clean up old custom generated items
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
		slot_pnl.mouse_filter = Control.MOUSE_FILTER_STOP # STOP to reliably detect gui_input
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
		icon_panel.clip_children = Control.CLIP_CHILDREN_AND_DRAW # 2 (CLIP_CHILDREN_AND_DRAW) - Masks child TextureRect by StyleBox rounded corners!
		
		var st = StyleBoxFlat.new()
		st.bg_color = data["c1"] if data["c1"].a > 0.0 else Color(0.1, 0.1, 0.1)
		var radius = int(8 * s)
		st.corner_radius_top_left = radius; st.corner_radius_top_right = radius
		st.corner_radius_bottom_left = radius; st.corner_radius_bottom_right = radius
		icon_panel.add_theme_stylebox_override("panel", st)
		
		if is_instance_valid(data["node"]) and data["node"].texture:
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
		btn_lbl.text = (data["name"] if data["name"] != "" else "Mat "+str(i+1))
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
				selected_material = mat_id
				is_paint_tool_active = false
				is_mechanism_mode_active = false
				_update_material_highlights()
				_update_menu_highlights()
				
				# TUTORIAL COMPLETION: If the user selects their first custom element
				if lab_tutorial_step == 6:
					is_lab_tutorial_done = true
					lab_tutorial_step = 0
					_update_lab_tutorial_highlight()
					_save_lab_state()
					_unlock_achievement("mad_scientist")
					
					# CLEANUP: Close tools if it was opened by tutorial and reset any remaining pulses
					if is_instance_valid(tools_panel) and tools_panel.visible:
						_on_tools_btn_pressed() # Close menu to give "libertad total"
		)
		
		slot_pnl.set_meta("mat_id", mat_id)
		slot_pnl.set_meta("overlay", selection_overlay)
		slot_pnl.set_meta("label", btn_lbl)
		
		mat_grid_node.add_child(slot_pnl)
		mat_grid_node.move_child(slot_pnl, insert_idx)
		
		# For tutorial Step 6 highlight tracking
		if not ui_elements.has("lab_custom_slots_hud"): ui_elements["lab_custom_slots_hud"] = [null, null, null]
		ui_elements["lab_custom_slots_hud"][i] = slot_pnl
		
		if i == 0: ui_elements["lab_first_custom_slot"] = slot_pnl
		insert_idx += 1
		
	_update_material_highlights()

func _sync_palette_to_shader():
	var palette_img = Image.create(2048, 3, false, Image.FORMAT_RGBA8)
	palette_img.fill(Color(0,0,0,0))
	for i in range(2048):
		palette_img.set_pixel(i, 0, mat_colors_1[i])
		palette_img.set_pixel(i, 1, mat_colors_2[i])
		palette_img.set_pixel(i, 2, mat_colors_3[i])
	var palette_tex = ImageTexture.create_from_image(palette_img)
	if is_instance_valid(texture_rect) and texture_rect.material:
		texture_rect.material.set_shader_parameter("palette_tex", palette_tex)

func _apply_custom_material_to_engine(i: int):
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
	
	var c1 = data["c1"] if data["c1"].a > 0.0 else Color(1,0,1,1)
	
	if has_method("_register_material"): # Safety check because we are hooking deep!
		_register_material(mat_id, c1, tags_mask, data["c2"], data["c3"])

func _update_lab_inspector():
	if not ui_elements.has("lab_col_pickers"): return
	
	var data = lab_custom_data[lab_selected_slot]
	
	# Update borders
	if ui_elements.has("lab_slot_borders"):
		for i in range(3):
			var pnl = ui_elements["lab_slot_borders"][i]
			var st = pnl.get_theme_stylebox("panel")
			if i == lab_selected_slot:
				st.border_color = Color(0.2, 0.5, 1.0) # Highlight selected
			else:
				st.border_color = Color(0.4, 0.4, 0.5) # Default
				
	# Update Grav buttons
	if ui_elements.has("lab_grav_buttons"):
		for j in range(4):
			var btn = ui_elements["lab_grav_buttons"][j]
			btn.set_block_signals(true)
			btn.button_pressed = (data["grav"] == j)
			btn.set_block_signals(false)
			
	# Update Est buttons
	if ui_elements.has("lab_est_buttons"):
		for j in range(4):
			var btn = ui_elements["lab_est_buttons"][j]
			btn.set_block_signals(true)
			btn.button_pressed = (data["state"] == j)
			btn.set_block_signals(false)
				
	# Update tag toggle buttons visibly and handle conditional sections
	if ui_elements.has("lab_tag_buttons"):
		var current_tags = data["tags"]
		for tag in ui_elements["lab_tag_buttons"]:
			var tb = ui_elements["lab_tag_buttons"][tag]
			tb.set_block_signals(true)
			tb.button_pressed = current_tags.has(tag)
			tb.set_block_signals(false)
		
		# Dinámicamente ocultar/mostrar secciones basadas en dependencias (ej: Combustión solo si FLAMMABLE)
		if ui_elements.has("lab_tag_sections"):
			var sections_node = ui_elements["lab_tag_sections"]
			if sections_node.has("combustion"):
				var is_flammable = current_tags.has("FLAMMABLE")
				sections_node["combustion"].visible = is_flammable
				# Si deja de ser inflamable, limpiar automáticamente las etiquetas de combustión
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
		_apply_custom_material_to_engine(i)
	_sync_palette_to_shader()
		
	_save_lab_state()
	
	_update_custom_mats_in_material_grid()
	
	for i in range(3):
		var cp = ui_elements["lab_col_pickers"][i]
		var tr_btn = ui_elements["lab_col_trash"][i]
		var prop = "c" + str(i+1)
		
		var is_null = data[prop].a == 0.0
		
		if is_null:
			cp.color = Color(0.2, 0.2, 0.2, 1.0)
			if cp.has_node("NullOverlay"): cp.get_node("NullOverlay").visible = true
			tr_btn.modulate = Color(1, 1, 1, 0) # Make fully transparent but keep layout space
			tr_btn.disabled = true
		else:
			cp.color = data[prop]
			if cp.has_node("NullOverlay"): cp.get_node("NullOverlay").visible = false
			tr_btn.modulate = Color(1, 1, 1, 1) # Full visibility
			tr_btn.disabled = false
			
		if i == 2 and data["c2"].a == 0.0:
			cp.disabled = true
			cp.color = Color(0.2,0.2,0.2)
		else:
			cp.disabled = false
			
	if ui_elements.has("lab_mix_slider"):
		var mix_slider = ui_elements["lab_mix_slider"]
		mix_slider.set_block_signals(true)
		mix_slider.value = data["mix"]
		mix_slider.set_block_signals(false)

func _update_lab_preview(idx: int):
	var data = lab_custom_data[idx]
	if not data["node"]: return
	
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

func _setup_disaster_ui():
	_set_panning_mode(false)
	var s = _get_ui_scale()
	var disaster_btn = _create_vertical_category_btn("🌪️", "disasters")
	disaster_btn.name = "DisasterBtn"
	ui_elements["disaster_btn"] = disaster_btn
	disaster_btn.add_theme_font_override("font", _get_safe_font())
	disaster_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	disaster_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_hbox.add_child(disaster_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.2, 0.2, 1.0) # SOLID dark red-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.5, 0.4, 0.4)
	btn_style.corner_radius_top_left = 0; btn_style.corner_radius_top_right = 0
	btn_style.corner_radius_bottom_left = 0; btn_style.corner_radius_bottom_right = 0
	disaster_btn.add_theme_stylebox_override("normal", btn_style)
	disaster_btn.add_theme_stylebox_override("hover", btn_style)
	disaster_btn.add_theme_stylebox_override("pressed", btn_style)
	disaster_btn.set_meta("base_style", btn_style)
	
	# CREATE FRESH PANEL WITH STYLE
	ui_root = get_parent().get_node("UI")
	disaster_panel = PanelContainer.new()
	disaster_panel.name = "DisasterPanel"
	ui_root.add_child(disaster_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.1, 0.1, 0.95) # Near opaque dark red-grey
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.5, 0.4, 0.4)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	disaster_panel.add_theme_stylebox_override("panel", panel_style)
	
	disaster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	_align_panel_to_hud(disaster_panel, 370 * s, 490 * s)
	# RESTORE STATE
	disaster_panel.visible = ui_root.get_meta("disaster_v", false)
	
	for child in disaster_panel.get_children(): 
		if is_instance_valid(child): child.free() # CLEAR OLD PANEL IMMEDIATELY
		
	var scroll = ScrollContainer.new()
	scroll.name = "DisasterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# DISASTER PANEL NEEDS A VBOX FOR THE TITLE
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	disaster_panel.add_child(main_vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = tr("disasters")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", _get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", 34 * s)
	ui_elements["disaster_panel_title"] = title_lbl
	main_vbox.add_child(title_lbl)
	
	main_vbox.add_child(scroll)
	
	disaster_btn.pressed.connect(func(): 
		_toggle_category_panel(disaster_panel)
		if is_instance_valid(disaster_panel) and disaster_panel.visible:
			_show_menu_reminder("disaster", disaster_panel.get_child(0), "TUTORIAL_STEP_4")
	)
	
	disaster_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	disaster_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	var v_box = VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 15 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	var create_row = func(label_key: String, options: Array, callback: Callable, is_upcoming: bool = false):
		var lbl = Label.new()
		lbl.text = tr(label_key) + ": "
		lbl.add_theme_font_size_override("font_size", 22.0 * s)
		lbl.add_theme_font_override("font", _get_safe_font())
		ui_elements[label_key + "_lbl"] = lbl
		v_box.add_child(lbl)
		
		var flow = HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(flow)
		
		if is_upcoming:
			lbl.modulate = Color(0.5, 0.5, 0.5, 0.7)
			flow.modulate = Color(0.5, 0.5, 0.5, 0.7)
		
		for i in range(options.size()):
			var osk = options[i]
			var btn = Button.new()
			btn.text = tr(osk)
			btn.custom_minimum_size = Vector2(80.0 * s, 45.0 * s)
			btn.add_theme_font_size_override("font_size", 20.0 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			
			# PREMIUM BASE STYLE
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = Color(0.12, 0.12, 0.15, 0.8)
			b_style.border_width_left = 1; b_style.border_width_top = 1
			b_style.border_width_right = 1; b_style.border_width_bottom = 1
			b_style.border_color = Color(0.3, 0.3, 0.4)
			b_style.corner_radius_top_left = 10 * s; b_style.corner_radius_top_right = 10 * s
			b_style.corner_radius_bottom_left = 10 * s; b_style.corner_radius_bottom_right = 10 * s
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
					_on_arcade_selection_made(false)
					callback.call(level)
				)
			flow.add_child(btn)
			ui_elements[label_key + "_btn_" + str(i)] = [btn, osk]

	create_row.call("weather", ["off", "light", "med", "storm"], func(l): 
		current_weather = l
		_update_menu_highlights()
		_on_arcade_selection_made(true)
	)
	var int_keys = ["off", "light", "med", "heavy"]
	create_row.call("acid_rain", int_keys, func(l): 
		acid_rain_intensity = l
		_update_menu_highlights()
		_on_arcade_selection_made(true)
	)
	create_row.call("quake", ["off", "light", "med", "brutal"], func(l): 
		earthquake_intensity = l
		if l > 0: 
			earthquake_timer = _get_lut_rand_range(5.0, 7.0)
			_play_action_sound("earthquake")
			_toggle_category_panel(disaster_panel)
		else:
			earthquake_timer = 0 # Reset para apagar sonido e intensidad
		_update_menu_highlights()
		_on_arcade_selection_made(true)
	)
	create_row.call("tornado", ["off", "light", "med", "heavy"], func(l):
		tornado_intensity = l
		if l > 0: 
			tornado_timer = 15.0; tornado_x = _get_lut_rand()*grid_width; tornado_target_x = _get_lut_rand()*grid_width
			tornado_ground_y = 0.0 # Start from the sky for landing animation
			tornado_element = 0 # Default normal
			_record_tornado_discovery(0) # Record normal type immediately
			_play_action_sound("tornado")
			_toggle_category_panel(disaster_panel)
		else:
			tornado_timer = 0 # Apagar instantáneamente
		_update_menu_highlights()
		_on_arcade_selection_made(true)
	)
	create_row.call("tsunami", ["off", "light", "med", "storm"], func(l):
		tsunami_intensity = l
		if l > 0: 
			tsunami_timer = 15.0; tsunami_wave_x = 0.0
			_play_action_sound("tsunami")
			_toggle_category_panel(disaster_panel)
		else:
			tsunami_timer = 0 # Apagar instantáneamente
		_update_menu_highlights()
		_on_arcade_selection_made(true)
	)
	
	create_row.call("bomber", ["off", "light", "med", "heavy"], func(l):
		bombardero_intensity = l
		if l > 0:
			_start_bombardero()
			_toggle_category_panel(disaster_panel)
		else:
			_stop_bombardero()
		_update_menu_highlights()
		_on_arcade_selection_made(true)
	)
	
	_add_ui_header(v_box, "coming_soon")
	
	create_row.call("lava_rain", int_keys, func(l): lava_rain_intensity = l; _update_menu_highlights(), true)
	create_row.call("met_storm", ["off", "light", "med", "storm"], func(l): meteor_storm_intensity = l; _update_menu_highlights(), true)
	create_row.call("black_hole", ["off", "light", "med", "heavy"], func(l): black_hole_intensity = l; _update_menu_highlights(), true)
	create_row.call("sinkhole", ["off", "light", "med", "heavy"], func(l): sinkhole_intensity = l; _update_menu_highlights(), true)
	create_row.call("sand_storm", ["off", "light", "med", "storm"], func(l): sand_storm_intensity = l; _update_menu_highlights(), true)

func _close_all_popups():
	if is_instance_valid(tools_panel): tools_panel.visible = false
	if is_instance_valid(workshop_panel): workshop_panel.visible = false
	if is_instance_valid(disaster_panel): disaster_panel.visible = false
	if is_instance_valid(npc_panel): npc_panel.visible = false
	if is_instance_valid(paint_panel): paint_panel.visible = false
	if is_instance_valid(achievement_panel): achievement_panel.visible = false
	if is_instance_valid(lab_panel): lab_panel.visible = false
	
	ui_root.set_meta("workshop_v", false)
	ui_root.set_meta("tools_v", false)
	ui_root.set_meta("lab_v", false)
	ui_root.set_meta("disaster_v", false)
	ui_root.set_meta("npc_v", false)
	ui_root.set_meta("paint_v", false)
	
	if is_instance_valid(save_panel): save_panel.queue_free()
	_close_music_menu()

func _refresh_ui_text():
	# This function is now mostly legacy as we prefer rebuilding the UI
	# to preserve complex layouts and premium formatting perfectly.
	TranslationServer.set_locale(current_language)
	# (Individual element refreshes removed in favor of _setup_main_ui_containers)

func _generate_material_texture(mat_id: int) -> ImageTexture:
	if mat_id < 0 or mat_id >= material_tags_raw.size(): return null
	
	var tags = material_tags_raw[_get_tags_id(mat_id)]
	var has_double = (tags & SandboxMaterial.Tags.TEXTURE_DOUBLE) != 0
	var has_triple = (tags & SandboxMaterial.Tags.TEXTURE_TRIPLE) != 0
	
	if not has_double and not has_triple: return null
	
	var c1 = mat_colors_1[mat_id] if mat_id < mat_colors_1.size() else Color.BLACK
	var c2 = mat_colors_2[mat_id] if mat_id < mat_colors_2.size() else c1
	var c3 = mat_colors_3[mat_id] if mat_id < mat_colors_3.size() else c2
	
	var mix_factor = 0.25
	if (tags & SandboxMaterial.Tags.MIX_LOW) != 0: mix_factor = 0.1
	elif (tags & SandboxMaterial.Tags.MIX_MEDIUM) != 0: mix_factor = 0.25
	elif (tags & SandboxMaterial.Tags.MIX_HIGH) != 0: mix_factor = 0.44
	
	var s = _get_ui_scale()
	var pixel_size = max(1, int(6 * s)) # 6 is a great chunky size
	
	var tex_w = 128
	var tex_h = 128
	
	var gen_img = Image.create(tex_w, tex_h, false, Image.FORMAT_RGBA8)
	
	var blocks_x = ceil(tex_w / float(pixel_size))
	var blocks_y = ceil(tex_h / float(pixel_size))
	
	for y_block in range(blocks_y):
		for x_block in range(blocks_x):
			var val = _get_lut_rand()
			var p_color = c1
			
			if has_triple:
				if val < mix_factor: p_color = c2
				elif val < mix_factor * 2.0: p_color = c3
			elif has_double:
				if val < mix_factor: p_color = c2
				
			var start_x = x_block * pixel_size
			var start_y = y_block * pixel_size
			for dy in range(pixel_size):
				if start_y + dy >= tex_h: break
				for dx in range(pixel_size):
					if start_x + dx >= tex_w: break
					gen_img.set_pixel(start_x + dx, start_y + dy, p_color)
			
	return ImageTexture.create_from_image(gen_img)

func _add_button(key: String, mat_id: int, is_upcoming: bool = false):
	var s = _get_ui_scale()
	if not is_upcoming:
		mat_id_to_key[mat_id] = key
		
	# The master container for the whole slot (Clickable area)
	var slot_pnl = PanelContainer.new()
	var slot_style = StyleBoxEmpty.new() # Invisible but stops mouse
	slot_pnl.add_theme_stylebox_override("panel", slot_style)
	slot_pnl.mouse_filter = Control.MOUSE_FILTER_PASS # PASS: ALLOW SCROLL ON DRAG (MOBILE)
	slot_pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL # LIQUID FILL (JUSTIFY)
	slot_pnl.custom_minimum_size = Vector2(110 * s, 85 * s) 
	
	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 2 * s) # COMPACT SPACE
	main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS # Pass to slot_pnl
	slot_pnl.add_child(main_vbox)
	
	if is_upcoming:
		slot_pnl.modulate = Color(0.4, 0.4, 0.4, 0.8) # OSCURECIDO
		slot_pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE # NO CLICABLE
	
	# The Stack Container (Icon base + Selection overlays)
	var stack = Control.new()
	var icon_w = 90 * s
	var icon_h = 46 * s
	stack.custom_minimum_size = Vector2(icon_w, icon_h)
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	main_vbox.add_child(stack)
	
	# 1. ICON LAYER (Always visible material color)
	var icon_panel = PanelContainer.new()
	var icon_style = StyleBoxFlat.new()
	var final_color = Color.BLACK
	if not is_upcoming:
		if mat_id == MUSIC_ID_START:
			final_color = Color("#A61266")
		elif mat_id == 600:
			final_color = Color("#FFD700")
		elif mat_id == -3: # Lightning tool
			final_color = Color("#FFE600")
		elif mat_id >= 0:
			final_color = mat_colors_1[mat_id]
		else:
			final_color = Color(0.1, 0.1, 0.1)
	icon_style.bg_color = final_color
	var radius = int(8 * s)
	icon_style.corner_radius_top_left = radius
	icon_style.corner_radius_top_right = radius
	icon_style.corner_radius_bottom_left = radius
	icon_style.corner_radius_bottom_right = radius
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	icon_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Apply mask so texture doesn't spill over rounded corners
	icon_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	stack.add_child(icon_panel)
	
	# GENERATE PROCEDURAL TEXTURE
	var tex = _generate_material_texture(mat_id)
	if tex != null:
		var tex_rect = TextureRect.new()
		tex_rect.texture = tex
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_TILE
		tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_panel.add_child(tex_rect)
	
	# 2. SELECTION OVERLAY (Only visible when selected)
	var selection_overlay = PanelContainer.new()
	selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_overlay.visible = false # Managed by highlights
	
	# Center it over the icon
	selection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(selection_overlay)
	
	var btn_lbl = Label.new()
	btn_lbl.name = "MatLabel"
	btn_lbl.text = tr(key)
	btn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	btn_lbl.add_theme_font_size_override("font_size", 18 * s) # EVEN LARGER TEXT
	btn_lbl.add_theme_font_override("font", _get_safe_font())
	main_vbox.add_child(btn_lbl)
	ui_elements[key + "_mat_lbl"] = btn_lbl
	
	# CENTRALIZED INPUT (Whole slot - MOUSE DOWN TRUMPS SCROLL DELAY)
	if not is_upcoming:
		slot_pnl.gui_input.connect(func(event):
			if not is_instance_valid(event) or not is_instance_valid(slot_pnl): return
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_play_action_sound("ui_click")
				selected_material = mat_id
				is_paint_tool_active = false
				is_mechanism_mode_active = false
				
				# TUTORIAL END: If we selected a custom material (900+)
				if mat_id >= 900 and not is_lab_tutorial_done:
					is_lab_tutorial_done = true
					lab_tutorial_step = 0
					_update_lab_tutorial_highlight()
					_save_lab_state()
				
				_update_material_highlights()
				_update_menu_highlights()
				_close_all_popups()
				
				# Music is no longer in MaterialGrid, so this part can be simplified/removed for MaterialGrid
				# But specifically if we ever call it from elsewhere:
				pass
				# FORCE SWAP BACK TO ARCADE CONTROLS
				if is_npc_mode_menu_open or is_instance_valid(controlled_npc):
					_on_arcade_selection_made(false)
		)
	
	slot_pnl.set_meta("mat_id", mat_id)
	
	ui_elements[key + "_icon_pnl"] = selection_overlay # Store overlay for highlight
	ui_elements[key + "_mat_lbl"] = btn_lbl
	
	# OPTIMIZATION: Store shortcut references to avoid get_child loops
	slot_pnl.set_meta("overlay", selection_overlay)
	slot_pnl.set_meta("label", btn_lbl)
	
	material_grid.add_child(slot_pnl)
	
	main_vbox.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _add_ui_header(container, key: String):
	var s = _get_ui_scale()
	var header_pnl = Control.new()
	# Increased height slightly to avoid overlaps but removed \n\n to avoid the giant gap
	header_pnl.custom_minimum_size = Vector2(250 * s, 80 * s)
	header_pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl = Label.new()
	lbl.text = tr(key)
	lbl.add_theme_font_size_override("font_size", 28 * s)
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.1)) # Gold/Yellowish
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Remove anchors that might cause overflow issues, use size flags
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	header_pnl.add_child(lbl)
	ui_elements[key + "_hdr_" + str(lbl.get_instance_id())] = lbl
	container.add_child(header_pnl)

# --- OPTIMIZED HIGHLIGHT SYSTEM ---

func _update_material_highlights():
	if selected_material != -2 and selected_circuit_tool != "piston" and selected_circuit_tool != "cannon":
		selected_circuit_tool = ""
	if selected_material != 8 and selected_material != 5 and selected_circuit_tool == "":
		is_mechanism_mode_active = false
	_set_panning_mode(false)
	# PRE-CACHE SELECTION STYLE
	var sel_style = StyleBoxFlat.new()
	sel_style.draw_center = false
	sel_style.border_width_left = 6; sel_style.border_width_top = 6
	sel_style.border_width_right = 6; sel_style.border_width_bottom = 6
	sel_style.border_color = Color.WHITE
	# REMOVED SHADOW FOR PERFORMANCE (Shadows on 100+ buttons lag older GPUs)
	sel_style.corner_radius_top_left = 10; sel_style.corner_radius_top_right = 10
	sel_style.corner_radius_bottom_left = 10; sel_style.corner_radius_bottom_right = 10

	for slot in material_grid.get_children():
		if not is_instance_valid(slot) or not slot.has_meta("mat_id"): continue
		
		var mat_id = slot.get_meta("mat_id", -1)
		var overlay = slot.get_meta("overlay", null)
		var label = slot.get_meta("label", null)
		if not overlay or not label: continue
		
		var is_selected = (mat_id == selected_material)
		if mat_id == MUSIC_ID_START:
			var m_data = _get_music_data(selected_material)
			if m_data.inst >= 0 and m_data.inst < 4 and m_data.note >= 0 and m_data.note < 16:
				is_selected = true
			
		# SMART UPDATE: Only modify if state changed
		if slot.get_meta("is_highlighted", false) != is_selected:
			slot.set_meta("is_highlighted", is_selected)
			overlay.visible = is_selected
			if is_selected:
				overlay.add_theme_stylebox_override("panel", sel_style)
				label.add_theme_color_override("font_color", Color.YELLOW)
			else:
				label.remove_theme_color_override("font_color")

func _update_menu_highlights():
	var s = _get_ui_scale()
	
	var cat_menus = {
		"tools_btn": tools_panel,
		"lab_btn": lab_panel,
		"disaster_btn": disaster_panel,
		"npc_btn": npc_panel,
		"paint_btn": paint_panel,
		"music_btn": music_panel
	}
	
	# PRE-CACHE THE PREMIUM HIGHLIGHT STYLE (Blue background for panel buttons)
	var h_style = StyleBoxFlat.new()
	h_style.bg_color = Color(0.2, 0.5, 1.0) # Lab Blue
	h_style.set_corner_radius_all(10 * s)
	h_style.border_width_bottom = 4 * s
	h_style.border_color = Color(0.5, 0.8, 1.0) # Light blue accent

	for key in ui_elements:
		if not key.contains("_btn"): continue
		var node_data = ui_elements[key]
		var btn = node_data[0] if node_data is Array else node_data
		
		if is_instance_valid(btn) and btn is Button:
			var is_active = false
			
			# 1. CATEGORY BUTTONS LOGIC (White Border)
			if key in cat_menus:
				var panel = cat_menus[key]
				if key == "music_btn":
					is_active = is_instance_valid(music_panel) and music_panel.visible
				else:
					is_active = is_instance_valid(panel) and panel.visible
				
				if btn.get_meta("is_currently_active", false) != is_active:
					btn.set_meta("is_currently_active", is_active)
					if is_active:
						var b_style = btn.get_meta("base_style") if btn.has_meta("base_style") else btn.get_theme_stylebox("normal")
						var active_cat_style = b_style.duplicate()
						active_cat_style.border_width_left = 2; active_cat_style.border_width_top = 2
						active_cat_style.border_width_right = 2; active_cat_style.border_width_bottom = 2
						active_cat_style.border_color = Color.WHITE
						btn.add_theme_stylebox_override("normal", active_cat_style)
						btn.add_theme_stylebox_override("hover", active_cat_style)
						btn.add_theme_stylebox_override("pressed", active_cat_style)
					else:
						if btn.has_meta("base_style"):
							var b_style = btn.get_meta("base_style")
							btn.add_theme_stylebox_override("normal", b_style)
							btn.add_theme_stylebox_override("hover", b_style)
							btn.add_theme_stylebox_override("pressed", b_style)
				continue

			# 2. NORMAL PANEL BUTTONS LOGIC (Blue Background)
			if key.begins_with("brush_btn_"):
				var idx = int(key.split("_")[-1])
				var brush_sizes = [0, 1, 2, 5, 7, 12]
				if idx < brush_sizes.size() and brush_sizes[idx] == brush_radius: is_active = true
			elif key.begins_with("lang_btn_"):
				var idx = int(key.split("_")[-1])
				var codes = ["es", "en", "it", "fr", "de", "pt"]
				if idx < codes.size() and current_language == codes[idx]: is_active = true
			elif key.begins_with("orient_btn_"):
				var idx = int(key.split("_")[-1])
				if idx == current_orientation_setting: is_active = true
			elif key.begins_with("ui_size_btn_"):
				var idx = int(key.split("_")[-1])
				if idx == ui_scale_level: is_active = true
			elif key.begins_with("GRID_SNAP_LBL_btn_"):
				var idx = int(key.split("_")[-1])
				if (idx == 0 and force_grid_visible) or (idx == 1 and not force_grid_visible): is_active = true
			elif key.begins_with("weather_btn_"):
				if int(key.split("_")[-1]) == current_weather and not is_selecting_npc_to_control: is_active = true
			elif key.begins_with("acid_rain_btn_"):
				if int(key.split("_")[-1]) == acid_rain_intensity and not is_selecting_npc_to_control: is_active = true
			elif key.begins_with("quake_btn_"):
				if int(key.split("_")[-1]) == earthquake_intensity and not is_selecting_npc_to_control: is_active = true
			elif key.begins_with("tornado_btn_"):
				if int(key.split("_")[-1]) == tornado_intensity and not is_selecting_npc_to_control: is_active = true
			elif key.begins_with("tsunami_btn_"):
				if int(key.split("_")[-1]) == tsunami_intensity and not is_selecting_npc_to_control: is_active = true
			elif key.begins_with("bomber_btn_"):
				if int(key.split("_")[-1]) == bombardero_intensity and not is_selecting_npc_to_control: is_active = true
			elif key == "warrior_btn":
				if selected_material == 1000 and not is_selecting_npc_to_control: is_active = true
			elif key == "archer_btn":
				if selected_material == 1010 and not is_selecting_npc_to_control: is_active = true
			elif key == "miner_btn":
				if selected_material == 1020 and not is_selecting_npc_to_control: is_active = true
			elif key == "medic_btn":
				if selected_material == 1040 and not is_selecting_npc_to_control: is_active = true
			elif key == "mage_btn":
				if selected_material == 1070 and not is_selecting_npc_to_control: is_active = true
			elif key.begins_with("team_btn_"):
				var idx = int(key.split("_")[-1])
				if idx == selected_team: is_active = true
			elif key == "eraser_tool_btn":
				if selected_material == 0: is_active = true
			elif key == "save_btn_ui_btn":
				if is_instance_valid(save_panel): is_active = true
			elif key == "control_active_btn":
				is_active = is_selecting_npc_to_control or is_instance_valid(controlled_npc)
				btn.text = tr("selecting_npc") if is_selecting_npc_to_control else tr("active")
			elif key == "control_disabled_btn":
				is_active = not is_selecting_npc_to_control and not is_instance_valid(controlled_npc)
			elif key == "zombie_btn":
				if selected_material == 1050 and not is_selecting_npc_to_control: is_active = true
			elif key == "zombie_tank_btn":
				if selected_material == 1060 and not is_selecting_npc_to_control: is_active = true
			
			if btn.get_meta("is_currently_active", false) != is_active:
				btn.set_meta("is_currently_active", is_active)
				if is_active:
					btn.add_theme_stylebox_override("normal", h_style)
					btn.add_theme_stylebox_override("hover", h_style)
					btn.add_theme_stylebox_override("pressed", h_style)
					btn.add_theme_color_override("font_color", Color.WHITE)
				else:
					if btn.has_meta("base_style"):
						var b_style = btn.get_meta("base_style")
						btn.add_theme_stylebox_override("normal", b_style)
						btn.add_theme_stylebox_override("hover", b_style)
						btn.add_theme_stylebox_override("pressed", b_style)
					else:
						btn.remove_theme_stylebox_override("normal")
						btn.remove_theme_stylebox_override("hover")
						btn.remove_theme_stylebox_override("pressed")
					btn.remove_theme_color_override("font_color")
	
	# Ocultar o mostrar el selector de equipo según si el NPC seleccionado es neutral (Sin bando)
	var is_neutral_npc = (selected_material == 1050 or selected_material == 1060)
	if ui_elements.has("team_lbl") and is_instance_valid(ui_elements["team_lbl"]):
		ui_elements["team_lbl"].visible = not is_neutral_npc
	if ui_elements.has("team_flow") and is_instance_valid(ui_elements["team_flow"]):
		ui_elements["team_flow"].visible = not is_neutral_npc

func _is_position_over_ui(pos: Vector2) -> bool:
	if is_blocking: return true
	if is_npc_mode_menu_open: return true
	
	if is_instance_valid(material_scroll) and material_scroll.get_global_rect().has_point(pos):
		return true
	if is_instance_valid(action_hbox) and action_hbox.get_global_rect().has_point(pos):
		return true
	if is_instance_valid(action_vbox) and action_vbox.get_global_rect().has_point(pos):
		return true

	for panel in [tools_panel, lab_panel, disaster_panel, npc_panel, paint_panel, music_panel, save_panel, achievement_panel, logic_gate_tutorial_bubble, zoom_tutorial_bubble, active_tooltip_panel, cannon_settings_panel, phase_block_tutorial_bubble, cannon_tutorial_bubble, piston_tutorial_bubble, led_color_panel]:
		if is_instance_valid(panel) and panel.visible and panel.get_global_rect().has_point(pos):
			return true
	return false

func _is_any_ui_blocking() -> bool:
	if is_blocking: return true # GLOBAL MODAL BLOCKER
	if is_mouse_over_ui: return true
	if is_npc_mode_menu_open: return true # GLOBAL PROTECTOR: Block all workspace edits while arcade menu is up
	
	if is_instance_valid(phase_block_tutorial_bubble): return true
	if is_instance_valid(logic_gate_tutorial_bubble): return true
	if is_instance_valid(zoom_tutorial_bubble): return true
	if is_instance_valid(cannon_tutorial_bubble): return true
	if is_instance_valid(piston_tutorial_bubble): return true
	if is_instance_valid(led_color_panel): return true
	
	# 1. SMART HUD BLOCKING (Precise Rect Check)
	# Use Viewport coordinates (Pixels) for UI intersection to avoid zoom interference.
	var m_pos = get_viewport().get_mouse_position()
	
	if is_instance_valid(material_scroll) and material_scroll.get_global_rect().has_point(m_pos):
		return true
	if is_instance_valid(action_hbox) and action_hbox.get_global_rect().has_point(m_pos):
		return true
	if is_instance_valid(action_vbox) and action_vbox.get_global_rect().has_point(m_pos):
		return true

	# 2. Check Floating Panels (Global Rect Point)
	
	if tools_panel and tools_panel.visible and tools_panel.get_global_rect().has_point(m_pos):
		return true
	if workshop_panel and workshop_panel.visible and workshop_panel.get_global_rect().has_point(m_pos):
		return true
	if lab_panel and lab_panel.visible and lab_panel.get_global_rect().has_point(m_pos):
		return true
	if disaster_panel and disaster_panel.visible and disaster_panel.get_global_rect().has_point(m_pos):
		return true
	if npc_panel and npc_panel.visible and npc_panel.get_global_rect().has_point(m_pos):
		return true
	if paint_panel and paint_panel.visible and paint_panel.get_global_rect().has_point(m_pos):
		return true
	
	if music_panel and music_panel.visible and music_panel.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(save_panel) and save_panel.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(cannon_settings_panel) and cannon_settings_panel.visible and cannon_settings_panel.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(achievement_panel) and achievement_panel.visible and achievement_panel.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(logic_gate_tutorial_bubble) and logic_gate_tutorial_bubble.visible and logic_gate_tutorial_bubble.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(zoom_tutorial_bubble) and zoom_tutorial_bubble.visible and zoom_tutorial_bubble.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(cannon_tutorial_bubble) and cannon_tutorial_bubble.visible and cannon_tutorial_bubble.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(piston_tutorial_bubble) and piston_tutorial_bubble.visible and piston_tutorial_bubble.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(led_color_panel) and led_color_panel.visible and led_color_panel.get_global_rect().has_point(m_pos):
		return true
		
	if is_instance_valid(active_tooltip_panel) and active_tooltip_panel.visible and active_tooltip_panel.get_global_rect().has_point(m_pos):
		return true
		
	return false


# --- SFX SYSTEM ---
func _get_sfx_stream(sfx_name: String) -> AudioStream:
	if sfx_cache.has(sfx_name):
		return sfx_cache[sfx_name]
	
	var extensions = [".ogg", ".mp3", ".wav"]
	for ext in extensions:
		var path = "res://assets/audio/sfx/" + sfx_name + ext
		if ResourceLoader.exists(path) or FileAccess.file_exists(path) or FileAccess.file_exists(path + ".import"):
			var stream = load(path)
			# Ensure it loops if it's a placement sound (Logic handled in _manage_brush_sound)
			sfx_cache[sfx_name] = stream
			return stream
	return null

func _play_sfx(sfx_name: String, volume_boost: float = 0.0, pitch_scale: float = 1.0):
	if sfx_name == "": return
	
	var stream = _get_sfx_stream(sfx_name)
	if not stream: return

	# Force loop OFF for general one-shots from pool
	if "loop" in stream: stream.loop = false 

	sim_mutex.lock()
	# Play using next available player in pool
	var player = sfx_pool[next_sfx_idx]
	next_sfx_idx = (next_sfx_idx + 1) % SFX_POOL_SIZE
	sim_mutex.unlock()
	
	# DEFER to main thread atomically using a helper to prevent threading issues and order race conditions
	call_deferred("_play_sfx_main_thread", player, stream, volume_boost, pitch_scale)

func _play_sfx_main_thread(player: AudioStreamPlayer, stream: AudioStream, volume_boost: float, pitch_scale: float):
	if is_instance_valid(player) and stream != null:
		player.volume_db = volume_boost
		player.pitch_scale = pitch_scale
		player.stream = stream
		player.play()

func _manage_brush_sound(id: int):
	# Si no hay ID, es un NPC o está sobre la UI -> DETENER SONIDO
	if id == -1 or (material_tags_raw[_get_tags_id(id)] & SandboxMaterial.Tags.NPC):
		if brush_player.playing: brush_player.stop()
		return
	
	if material_sfx.has(id):
		_manage_looping_player(brush_player, material_sfx[id])
	else:
		if brush_player.playing: brush_player.stop()

func _manage_looping_player(player: AudioStreamPlayer, key: String):
	# Resolve filename from action_sfx dictionary if it exists
	var sfx_name = key
	if action_sfx.has(key):
		sfx_name = action_sfx[key]
		
	var stream = _get_sfx_stream(sfx_name)
	if stream:
		# Asegurar que el LOOP esté activado
		if "loop" in stream: stream.loop = true
		if "loop_mode" in stream: stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		
		if player.stream != stream:
			player.stream = stream
			player.play()
		elif not player.playing:
			player.play()
	else:
		if player.playing: player.stop()

func _play_material_sound(id: int):
	if material_sfx.has(id):
		_play_sfx(material_sfx[id])

func _play_achievement_unlock_sfx(is_menu_unlock: bool = false):
	if is_menu_unlock:
		_play_sfx("achievement_menu_unlock", 5.0)
	else:
		_play_sfx("achievement_unlock", 5.0)

func _play_action_sound(action: String, min_interval: float = 0.08, volume_boost: float = 0.0, pitch_scale: float = 1.0):
	if action_sfx.has(action):
		# Sistema de seguridad contra saturación: 
		# No permite que la MISMA acción suene repetidamente en menos de min_interval segundos
		var now = Time.get_ticks_msec() / 1000.0
		if last_action_times.has(action):
			if now - last_action_times[action] < min_interval:
				return
		
		last_action_times[action] = now
		_play_sfx(action_sfx[action], volume_boost, pitch_scale)

func _process(delta):
	played_music_this_frame.clear()
	
	if is_instance_valid(top_countdown_label):
		var is_historico = ui_root.get_meta("workshop_top_category", "Top Semanal") == "Top Histórico"
		var left = _get_next_update_unix(is_historico) - int(Time.get_unix_time_from_system())
		if left <= 0:
			left = 0
			# Invalidate memory cache so next tab click re-fetches
			if is_historico:
				ui_root.set_meta("_cached_top_historico_doc", null)
			else:
				_cached_top_semanal_doc = null
			
		var h = int(left / 3600.0)
		var m = int((left % 3600) / 60.0)
		var s = left % 60
		var text = tr("update_in") + " %02d:%02d:%02d" % [h, m, s]
		top_countdown_label.text = text
		if is_instance_valid(bot_countdown_label):
			bot_countdown_label.text = text

	if not is_grid_ready: return
	
	# Animate Rainbow LED Button color in LED selection panel
	if is_instance_valid(led_color_panel):
		for child in led_color_panel.find_children("", "Button", true, false):
			if child.has_meta("is_rainbow_btn"):
				var colors = [
					Color(1.0, 0.1, 0.1),
					Color(0.15, 0.45, 1.0),
					Color(0.15, 1.0, 0.15),
					Color(1.0, 0.85, 0.05),
					Color(1.0, 1.0, 1.0),
					Color(1.0, 0.25, 0.75),
					Color(0.2, 0.8, 1.0)
				]
				var c_idx = int(Engine.get_frames_drawn() / 15.0) % colors.size()
				var b_style = child.get_theme_stylebox("normal").duplicate()
				b_style.bg_color = colors[c_idx]
				child.add_theme_stylebox_override("normal", b_style)
				child.add_theme_stylebox_override("hover", b_style)
				child.add_theme_stylebox_override("pressed", b_style)
				break
	
	# Update cached zombie state once per frame for O(1) performance in nested loops
	_cached_has_zombies = false
	for npc in active_npcs:
		if npc.hp > 0 and (npc.type == "zombie" or npc.type == "zombie_tank"):
			_cached_has_zombies = true
			break
			
	_tnt_buckets_this_frame.clear()
	_frame_count += 1
	_check_achievement_conditions(delta)
	# (Debug HUD removed)
	
	# --- Rating popup timer ---
	if not rating_popup_shown:
		# Show only after 15 minutes of the second session (or later)
		if _current_session_count >= 2:
			play_time_for_rating += delta
			if play_time_for_rating >= 900.0:
				var current_time = Time.get_unix_time_from_system()
				# Wait at least 3 minutes since the last ad interaction
				if current_time - AdMobManager.last_ad_interaction_time >= 180.0:
					rating_popup_shown = true
					call_deferred("_show_rating_popup")
	
	# Update camera bounds for virtual physical walls
	if is_instance_valid(sim_camera) and view_zoom > 1.0:
		var vp = get_viewport_rect().size
		var cam_pos = sim_camera.position
		var half_w = (vp.x / view_zoom) / 2.0
		var half_h = (vp.y / view_zoom) / 2.0
		
		# Offset bottom bound by the HUD height so physics drops right at the user's visible edge
		var hud_h_px = (grid_height - dynamic_grid_height) * grid_scale
		var visible_half_h_bottom = (vp.y / 2.0 - hud_h_px) / view_zoom
		
		cam_min_x = max(0, int((cam_pos.x - half_w) / grid_scale))
		cam_max_x = min(grid_width, int((cam_pos.x + half_w) / grid_scale))
		cam_min_y = max(0, int((cam_pos.y - half_h) / grid_scale))
		cam_max_y = min(dynamic_grid_height, int((cam_pos.y + visible_half_h_bottom) / grid_scale))
	else:
		cam_min_x = 0; cam_max_x = grid_width
		cam_min_y = 0; cam_max_y = dynamic_grid_height
		
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
					if not is_lab_unlocked: _set_lab_unlocked(true)
			else:
				if not overlay.visible:
					overlay.visible = true
					if is_lab_unlocked: _set_lab_unlocked(false)

	# LABORATORY TUTORIAL PULSE (Step 1 - Scaling Focus)
	if lab_tutorial_step == 1 and ui_elements.has("lab_name_edits"):
		var edits = ui_elements["lab_name_edits"]
		var active_idx = lab_selected_slot
		if edits.size() > active_idx and is_instance_valid(edits[active_idx]):
			var main_edit = edits[active_idx]
			main_edit.pivot_offset = main_edit.size / 2
			var scale_val = 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.004)
			main_edit.scale = Vector2(scale_val, scale_val)
			
			# Reset others
			for j in range(edits.size()):
				if j != active_idx and is_instance_valid(edits[j]): edits[j].scale = Vector2.ONE
	elif ui_elements.has("lab_name_edits"):
		for edit in ui_elements["lab_name_edits"]:
			if is_instance_valid(edit) and edit.scale != Vector2.ONE: edit.scale = Vector2.ONE
	
	if ui_elements.has("lab_slots_hbox"):
		if is_instance_valid(ui_elements["lab_slots_hbox"]): ui_elements["lab_slots_hbox"].modulate.a = 1.0

	# Increment SFX timer and reset every 1 second
	explosions_sfx_timer += delta
	if explosions_sfx_timer >= 1.0:
		explosions_sfx_timer = 0.0
		explosions_sfx_budget = 0
	
	# Explosion Budgeting Reset & Queue Processing
	explosions_this_frame = 0
	if _explosion_queue.size() > 0:
		# Process up to 50% of the budget from the queue each frame
		var q_limit = int(MAX_EXPLOSIONS_PER_FRAME * 0.5)
		for i in range(min(q_limit, _explosion_queue.size())):
			var e = _explosion_queue.pop_front()
			_explode(e[0], e[1], e[2], e[3], e[4], true) # Bypass check
	
	# Handle input with robust UI blocking
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var is_over_ui = _is_any_ui_blocking()
		if not is_over_ui and not is_panning_mode:
			_world_peace_timer = 0.0 # Wake up NPCs only when player interacts with the world
		
		# --- PANNING MODE LOGIC ---
		if is_panning_mode and not touch_started_on_ui and not is_over_ui:
			mouse_was_pressed = true
		
		# 1. INITIAL TOUCH PROTECTION
		if not mouse_was_pressed:
			touch_started_on_ui = touch_started_on_ui or is_over_ui
			
			# HISTORY REMOVED FROM MOUSE DOWN TO PREVENT UNDO BUG
			
			# NPC CONTROL SELECTION
			if is_selecting_npc_to_control and not touch_started_on_ui:
				var m_pos = get_local_mouse_position()
				var gx = int(m_pos.x / grid_scale)
				var gy = int(m_pos.y / grid_scale)
				var nearby = _get_nearby_npcs(gx, gy, 12.0)
				if nearby.size() > 0:
					controlled_npc = nearby[0]
					
					# Log to Firebase Analytics
					AnalyticsManager.log_event("npc_controlled", {"npc_type": controlled_npc.get("type", "unknown")})
					
					# Boost HP for player control (Hero unit)
					controlled_npc.hp = max(controlled_npc.hp, 160.0)
					controlled_npc["max_hp"] = max(controlled_npc.get("max_hp", 100.0), 160.0)
					controlled_npc.dir = 0 # Detener movimiento autónomo
					controlled_npc["is_fleeing"] = false # Quitar miedo si lo tenía
					is_selecting_npc_to_control = false
					_play_action_sound("ui_click")
					
					# Update UI
					if is_instance_valid(npc_panel): npc_panel.visible = false
					ui_root = get_parent().get_node("UI")
					main_controls = ui_root.get_node("Controls")
					main_controls.visible = false
					
					if is_instance_valid(npc_control_gui):
						npc_control_gui.visible = true
						_update_arcade_dynamic_button()
						
						var action_btn = npc_control_gui.find_child("ActionBtn", true, false)
						if action_btn:
							action_btn.text = tr("action") # Siempre "ACCIÓN" (Genérico)
						
					# LOGRO: Tiempo Retro - Ejecutar en segundo plano para no bloquear la entrada
					if not achievements["retro_time"].unlocked:
						_unlock_retro_time_delayed()
					
					mouse_was_pressed = true
					touch_started_on_ui = true # BLOCK drawing for the rest of this touch session
					return # Stop processing
			
			# 2. AUTOCLOSE MENUS ON WORKSPACE TAP (Only if didn't start on UI and NOT over UI)
			if not touch_started_on_ui and not is_over_ui:
				if is_instance_valid(tools_panel) and tools_panel.visible: tools_panel.visible = false
				if is_instance_valid(workshop_panel) and workshop_panel.visible: workshop_panel.visible = false
				if is_instance_valid(lab_panel) and lab_panel.visible: lab_panel.visible = false
				if is_instance_valid(disaster_panel) and disaster_panel.visible: disaster_panel.visible = false
				if is_instance_valid(npc_panel) and npc_panel.visible: npc_panel.visible = false
				if is_instance_valid(music_panel) and music_panel.visible: _close_music_menu()
				if is_instance_valid(achievement_panel) and achievement_panel.visible: achievement_panel.visible = false
				if is_instance_valid(save_panel): save_panel.queue_free()
				if is_instance_valid(cannon_settings_panel): cannon_settings_panel.queue_free()
				
				if force_grid_visible and not is_grid_tutorial_done:
					_show_grid_tutorial_bubble()
					is_grid_tutorial_done = true
					_save_tool_settings()

		# DRAW LOGIC (Only if touch session started on Sandbox, current position is Sandbox, and NOT in selection mode)
		# 4. DRAWING & TOOLS BLOCK (If controlling an NPC or selecting one)
		if is_instance_valid(controlled_npc) or is_selecting_npc_to_control:
			_manage_brush_sound(-1)
			return
			
		if not is_panning_mode and not touch_started_on_ui and not is_over_ui:
			var m_pos = get_local_mouse_position()
			var gx = int(m_pos.x / grid_scale)
			var gy = int(m_pos.y / grid_scale)
			
			var is_mechanism = (is_mechanism_mode_active and (selected_material == 8 or selected_material == 5)) or (selected_material == 93 or selected_material == 95 or selected_material == 96 or selected_material == 97)
			
			var is_npc = selected_material >= 0 and _get_tags_id(selected_material) < material_tags_raw.size() and (material_tags_raw[_get_tags_id(selected_material)] & SandboxMaterial.Tags.NPC)
			var is_music = _is_music_mat(selected_material)
			var is_logic_gate = is_mechanism_mode_active and (selected_circuit_tool == "not" or selected_circuit_tool == "and" or selected_circuit_tool == "or" or selected_circuit_tool == "nand" or selected_circuit_tool == "nor" or selected_circuit_tool == "xor" or selected_circuit_tool == "xnor")
			
			var should_act_like_mechanism = is_mechanism or (force_grid_visible and not is_npc and not is_music and not is_paint_tool_active and selected_material != -3 and not is_logic_gate)
			
			if force_grid_visible and not is_mechanism:
				var snap_base = 4
				gx = int(floor(float(gx) / snap_base) * snap_base)
				gy = int(floor(float(gy) / snap_base) * snap_base)
			
			if should_act_like_mechanism:
				# snap exactly to grid cells boundaries
				var snap = 8 if selected_material == 97 else 4
				if is_mechanism: # Only force specific snap if it's naturally a mechanism
					gx = int(floor(float(gx) / snap) * snap)
					gy = int(floor(float(gy) / snap) * snap)
				
				if not mouse_was_pressed:
					prev_snapped_gx = gx
					prev_snapped_gy = gy
					if selected_material == 93:
						_place_piston(gx, gy)
					elif selected_material == 95:
						_place_cannon(gx, gy)
					elif selected_material == 96:
						_place_pipe(gx, gy)
					elif selected_material == 97:
						_place_pipe_x2(gx, gy)
					else:
						_place_circuit_block(gx, gy, selected_material)
				else:
					# Draw continuous cell staircase from prev_snapped to current gx, gy
					if gx != prev_snapped_gx or gy != prev_snapped_gy:
						var cx = int(prev_snapped_gx / float(snap))
						var cy = int(prev_snapped_gy / float(snap))
						var target_cx = int(gx / float(snap))
						var target_cy = int(gy / float(snap))
						
						while cx != target_cx or cy != target_cy:
							var dcx = target_cx - cx
							var dcy = target_cy - cy
							if abs(dcx) >= abs(dcy):
								cx += 1 if dcx > 0 else -1
							else:
								cy += 1 if dcy > 0 else -1
							if selected_material == 93:
								_place_piston(cx * snap, cy * snap)
							elif selected_material == 95:
								_place_cannon(cx * snap, cy * snap)
							elif selected_material == 96:
								_place_pipe(cx * snap, cy * snap)
							elif selected_material == 97:
								_place_pipe_x2(cx * snap, cy * snap)
							else:
								_place_circuit_block(cx * snap, cy * snap, selected_material)
						
						prev_snapped_gx = gx
						prev_snapped_gy = gy
				_manage_brush_sound(-1)
			elif is_paint_tool_active:
				if not mouse_was_pressed and is_instance_valid(paint_panel) and paint_panel.visible:
					paint_panel.visible = false
				
				if paint_mode == 1: # Pintar fondo
					var p_diameters = [1, 3, 5, 10, 15, 25]
					_paint_background_circle(gx, gy, p_diameters[paint_brush_radius_idx], selected_paint_color)
				else:
					# Pintar elementos
					var p_diameters = [1, 3, 5, 10, 15, 25]
					_paint_elements_circle(gx, gy, p_diameters[paint_brush_radius_idx], selected_paint_color)
			elif is_npc:
				if not mouse_was_pressed:
					_place_npc(gx, gy)
					_play_action_sound("npc_place")
				_manage_brush_sound(-1) # Stop brush if switching to NPC
			elif is_logic_gate:
				if not mouse_was_pressed:
					var snap = 4
					gx = int(floor(float(gx) / snap) * snap)
					gy = int(floor(float(gy) / snap) * snap)
					
					var cx = int(gx / float(snap))
					var cy = int(gy / float(snap))
					
					var clicked_gate = null
					for gate in active_logic_gates:
						var g_pos = gate["grid_pos"]
						if cx >= g_pos.x and cx < g_pos.x + 3 and cy >= g_pos.y and cy < g_pos.y + 3:
							clicked_gate = gate
							break
					
					if clicked_gate != null:
						# Erase with old type
						_draw_logic_gate_shape(clicked_gate["grid_pos"], clicked_gate["orientation"], true, clicked_gate["type"])
						clicked_gate["orientation"] = (clicked_gate["orientation"] + 1) % 4
						clicked_gate["type"] = selected_circuit_tool
						# Draw with new type
						_draw_logic_gate_shape(clicked_gate["grid_pos"], clicked_gate["orientation"], false, clicked_gate["type"])
						_play_action_sound("ui_click")
						_check_logic_gate_tutorial(clicked_gate["grid_pos"])
					else:
						var gate_pos = Vector2i(cx - 1, cy - 1)
						var new_gate = { "grid_pos": gate_pos, "orientation": 0, "type": selected_circuit_tool }
						active_logic_gates.append(new_gate)
						_draw_logic_gate_shape(gate_pos, 0, false, selected_circuit_tool)
						_play_action_sound("ui_click")
						_check_logic_gate_tutorial(gate_pos)
				_manage_brush_sound(-1)
			elif _is_music_mat(selected_material):
				if not mouse_was_pressed:
					# RHYTHM SNAP: Align to 4x4 grid for perfect tempo (32 real pixels at scale 8)
					var snap = 4
					gx = int(floor(float(gx) / snap) * snap) + 1
					gy = int(floor(float(gy) / snap) * snap) + 1
					
					var cell_id = _get_cell(gx, gy)
					if show_music_notes_popup and _is_music_mat(cell_id):
						music_inspect_active = true
						music_inspect_timer = 0.0
						pending_music_draw_pos = Vector2i(gx, gy)
					else:
						music_inspect_active = false
						_place_music_block(gx, gy, selected_material)
						
						# 4. MUSIC: Trigger note on pulse/heat
						if _is_music_mat(selected_material):
							if selected_material == 600:
								_play_music_note(5, 0, true)
							else:
								var m_data = _get_music_data(selected_material)
								_play_music_note(m_data.inst, m_data.note, true, m_data.octave)
				
				if music_inspect_active:
					music_inspect_timer += delta
					
				_manage_brush_sound(-1)
			elif selected_material == -3:
				if not mouse_was_pressed:
					_strike_lightning_at(gx)
				_manage_brush_sound(-1)
			else:
				_manage_brush_sound(selected_material)
				_draw_circle(gx, gy, brush_radius, selected_material)
		else:
			# Not drawing, but we might need to stop sound if we were drawing and entered UI
			_manage_brush_sound(-1)
			
		mouse_was_pressed = true
	else:
		if mouse_was_pressed:
			# CAPTURE HISTORY ON RELEASE (POST-ACTION)
			if not touch_started_on_ui and not is_selecting_npc_to_control:
				# --- MUSIC SHORT TAP LOGIC ---
				if music_inspect_active and pending_music_draw_pos != Vector2i(-1, -1):
					if music_inspect_timer < 0.6:
						var gx = pending_music_draw_pos.x
						var gy = pending_music_draw_pos.y
						_place_music_block(gx, gy, selected_material)
						if _is_music_mat(selected_material):
							if selected_material == 600:
								_play_music_note(5, 0, true)
							else:
								var m_data = _get_music_data(selected_material)
								_play_music_note(m_data.inst, m_data.note, true, m_data.octave)
				
				save_history_state()
			
		mouse_was_pressed = false
		touch_started_on_ui = false
		music_inspect_active = false
		pending_music_draw_pos = Vector2i(-1, -1)
		_manage_brush_sound(-1) # Stop sound when finger lifted

	if is_pipe_dirty:
		_reconstruct_sources_from_cells()
		is_pipe_dirty = false

	# --- MUSIC NOTES POPUP ---
	var show_pop = false
	if show_music_notes_popup and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_panning_mode and not touch_started_on_ui:
		show_pop = true
		if music_inspect_active and music_inspect_timer < 0.6:
			show_pop = false
			
	if show_pop:
		var m_pos = get_local_mouse_position()
		var raw_gx = int(m_pos.x / grid_scale)
		var raw_gy = int(m_pos.y / grid_scale)
		var snap = 4
		# Snap to the top-left of the 4x4 grid to give a much larger hit tolerance
		var gx = int(floor(float(raw_gx) / snap) * snap) + 1
		var gy = int(floor(float(raw_gy) / snap) * snap) + 1
		
		if gx >= 0 and gx < grid_width and gy >= 0 and gy < grid_height:
			var cell_id = _get_cell(gx, gy)
			if _is_music_mat(cell_id):
				var m_data = _get_music_data(cell_id)
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
					
					var screen_pos = get_viewport().get_mouse_position()
					var vp_size = get_viewport_rect().size
					var p_size = pop.size
					if p_size.x == 0: p_size = pop.get_minimum_size() # Fallback if size hasn't updated yet
					
					var target_y = screen_pos.y - p_size.y - 100 * _get_ui_scale()
					var target_x = screen_pos.x - p_size.x / 2.0
					
					# If it hits the top edge, shift it to the side instead of clipping
					if target_y < 10:
						# Keep it slightly above the finger, but lower than the ideal height
						target_y = max(10, screen_pos.y - p_size.y - 40 * _get_ui_scale())
						if screen_pos.x < vp_size.x / 2.0:
							# Finger is on left half, place popup to the RIGHT
							target_x = screen_pos.x + 80 * _get_ui_scale()
						else:
							# Finger is on right half, place popup to the LEFT
							target_x = screen_pos.x - p_size.x - 80 * _get_ui_scale()
							
					# Ensure it doesn't go off horizontally
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
	# --------------------------

	# Simulation
	if not is_paused:
		_handle_controlled_npc_input(delta) # Handle player control
		
		# OPTIMIZATION: Update spatial hash every 2 frames
		if _frame_count % 2 == 0:
			_update_npc_spatial_hash()
			
		# Open/Close NPC Doors based on NPC proximity before cellular physics updates
		_update_npc_doors(delta)
		_update_phase_blocks()
		_simulate_pistons()
		_simulate_cannons(delta)
		_simulate_pipes(delta)
		
		# Pipe Structure Pass (BEFORE physics)
		for p in active_pipes:
			_update_pipe_visuals(p, 0)
		for p in active_pipes_x2:
			_update_pipe_x2_visuals(p, 0)
		
		_step_simulation()
		
		# Pipe Elements Pass (AFTER physics)
		for p in active_pipes:
			_update_pipe_visuals(p, 1)
		for p in active_pipes_x2:
			_update_pipe_x2_visuals(p, 1)
		
		# NPC AI & Physics
		_process_npcs(delta)
		
		# Projectiles (Arrows)
		_process_projectiles(delta)
		
		# Weather system
		_process_weather()
		
		# Earthquake processing
		_process_earthquake(delta)
		
		# Tornado processing
		_process_tornado(delta)
		
		# Tsunami processing
		_process_tsunami(delta)
		
		# Bomber processing
		_process_bombardero(delta)
		
		# Fireworks updates
		_update_active_fireworks(delta)
		_update_visual_sparks(delta)
	
	# Render
	_update_texture()
	queue_redraw()

# --- HISTORY SYSTEM ---
func _deep_copy_npcs() -> Array:
	var result = []
	for npc in active_npcs:
		var copy = npc.duplicate()
		copy["pos"] = Vector2i(npc.pos.x, npc.pos.y)
		# Clear volatile references that shouldn't persist across undo
		copy["social_target"] = null
		copy["cached_target"] = null
		copy["cached_closest_enemy"] = null
		copy["cached_closest_ally"] = null
		result.append(copy)
	return result

func _deep_copy_logic_gates() -> Array:
	var result = []
	for gate in active_logic_gates:
		var copy = gate.duplicate()
		if copy.has("grid_pos"):
			copy["grid_pos"] = Vector2i(copy.grid_pos.x, copy.grid_pos.y)
		result.append(copy)
	return result

func _deep_copy_pistons() -> Array:
	var result = []
	for p in active_pistons:
		var copy = p.duplicate()
		copy["pos"] = Vector2i(p.pos.x, p.pos.y)
		result.append(copy)
	return result

func save_history_state():
	# If we're not at the head of the buffer (we undid something), clear the "future"
	if history_current_index < history_buffer.size() - 1:
		history_buffer.resize(history_current_index + 1)

	# OPTIMIZATION: Don't save identical consecutive states (e.g. clicking without drawing)
	var current_snapshot = {
		"cells": cells.duplicate(),
		"charge": charge_array.duplicate(),
		"tags": tags_array.duplicate(),
		"chunks": chunks_active.duplicate(),
		"next_chunks": next_chunks_active.duplicate(),
		"npcs": _deep_copy_npcs(),
		"logic_gates": _deep_copy_logic_gates(),
		"active_pistons": _deep_copy_pistons()
	}
	
	if history_buffer.size() > 0:
		var last = history_buffer.back()
		# HIGH-PERFORMANCE CHANGE DETECTION
		# Only save if the actual grid cells have changed
		if last.cells == current_snapshot.cells:
			return

	history_buffer.append(current_snapshot)
	
	if history_buffer.size() > history_max_steps:
		history_buffer.pop_front()
	
	history_current_index = history_buffer.size() - 1

func _restore_npcs_from_snapshot(snapshot):
	# 1. Clear current NPC pixels from the grid
	for npc in active_npcs:
		_draw_npc_pixels(npc, 0)
	active_npcs.clear()
	controlled_npc = null
	active_projectiles.clear()
	
	# 2. Restore NPCs from snapshot
	if snapshot.has("npcs"):
		for npc in snapshot.npcs:
			var copy = npc.duplicate()
			copy["pos"] = Vector2i(npc.pos.x, npc.pos.y)
			copy["social_target"] = null
			copy["cached_target"] = null
			copy["cached_closest_enemy"] = null
			copy["cached_closest_ally"] = null
			copy["stuck_timer"] = 0.0
			active_npcs.append(copy)

func _restore_logic_gates_from_snapshot(snapshot):
	active_logic_gates.clear()
	if snapshot.has("logic_gates"):
		for gate in snapshot.logic_gates:
			var copy = gate.duplicate()
			if copy.has("grid_pos"):
				copy["grid_pos"] = Vector2i(copy.grid_pos.x, copy.grid_pos.y)
			active_logic_gates.append(copy)

func undo_history():
	if history_current_index > 0:
		history_current_index -= 1
		var snapshot = history_buffer[history_current_index]
		_restore_npcs_from_snapshot(snapshot)
		_restore_logic_gates_from_snapshot(snapshot)
		cells = snapshot.cells.duplicate()
		charge_array = snapshot.charge.duplicate()
		tags_array = snapshot.tags.duplicate()
		chunks_active = snapshot.chunks.duplicate()
		next_chunks_active = snapshot.next_chunks.duplicate()
		# Reset electricity state so BFS rebuilds from scratch
		# Zero out stale conductor charges but preserve explosive timers
		for ci in range(charge_array.size()):
			var cid = cells[ci] & 0xFFFF
			if cid > 0 and _get_tags_id(cid) < material_tags_raw.size():
				if not (material_tags_raw[_get_tags_id(cid)] & SandboxMaterial.Tags.EXPLOSIVE):
					charge_array[ci] = 0
			elif cid == 0:
				charge_array[ci] = 0
		charge_visual_buffer.fill(0)
		active_charge_indices.clear()
		powered_frame.fill(0)
		charge_dirty = true
		# Wake all chunks so electricity can re-propagate
		for i in range(next_chunks_active.size()):
			next_chunks_active[i] = 60
		_reconstruct_sources_from_cells(snapshot)
		_update_texture()
		queue_redraw()

func redo_history():
	if history_current_index < history_buffer.size() - 1:
		history_current_index += 1
		var snapshot = history_buffer[history_current_index]
		_restore_npcs_from_snapshot(snapshot)
		_restore_logic_gates_from_snapshot(snapshot)
		cells = snapshot.cells.duplicate()
		charge_array = snapshot.charge.duplicate()
		tags_array = snapshot.tags.duplicate()
		chunks_active = snapshot.chunks.duplicate()
		next_chunks_active = snapshot.next_chunks.duplicate()
		# Reset electricity state so BFS rebuilds from scratch
		# Zero out stale conductor charges but preserve explosive timers
		for ci in range(charge_array.size()):
			var cid = cells[ci] & 0xFFFF
			if cid > 0 and _get_tags_id(cid) < material_tags_raw.size():
				if not (material_tags_raw[_get_tags_id(cid)] & SandboxMaterial.Tags.EXPLOSIVE):
					charge_array[ci] = 0
			elif cid == 0:
				charge_array[ci] = 0
		charge_visual_buffer.fill(0)
		active_charge_indices.clear()
		powered_frame.fill(0)
		charge_dirty = true
		# Wake all chunks so electricity can re-propagate
		for i in range(next_chunks_active.size()):
			next_chunks_active[i] = 60
		_reconstruct_sources_from_cells(snapshot)
		_update_texture()
		queue_redraw()

func _draw():
	if not is_grid_ready: return
	var f = _get_safe_font()
	if not f: return
	var s = _get_ui_scale()
	g_scale = float(grid_scale)
	
	# MUSICAL RHYTHM GRID / MECHANISM GRID
	var music_menu_node = get_parent().get_node_or_null("UI/MusicPanel")
	var is_mechanism = selected_material == 96 or selected_material == 97 or selected_material == 95 or selected_material == 93
	if (music_menu_node and music_menu_node.visible) or _is_music_active() or (is_mechanism_mode_active and (selected_material == 8 or selected_material == 5)) or is_mechanism or force_grid_visible:
		var grid_col = Color("#4D4D4D") # Muy visible
		var thickness = 2.0
		# Vertical lines - Safety margin for virtual/scaled resolutions
		for x in range(0, grid_width + 8, 4):
			draw_line(Vector2(x * g_scale, 0), Vector2(x * g_scale, (grid_height + 8) * g_scale), grid_col, thickness)
		# Horizontal lines - Safety margin for virtual/scaled resolutions
		for y in range(0, grid_height + 8, 4):
			draw_line(Vector2(0, y * g_scale), Vector2((grid_width + 8) * g_scale, y * g_scale), grid_col, thickness)
			
	# METRONOME VISUAL RHYTHM PULSE
	if _frame_count % music_tempo_frames < 5:
		for y in range(0, dynamic_grid_height, 4):
			for x in range(0, grid_width, 4):
				if _get_cell(x, y) == 600:
					draw_rect(Rect2(Vector2(x, y) * g_scale, Vector2(g_scale * 2, g_scale * 2)), Color(1, 1, 1, 0.4), false, 1.5)
	
	# NPC EMOJIS
	for npc in active_npcs:
		if npc.get("current_emoji", "") != "":
			var world_pos = Vector2(float(npc.pos.x) + 1.0, float(npc.pos.y)) * g_scale
			var offset = Vector2(-40.0 * s, -14.0 * s)
			if npc.get("is_lying", false): offset = Vector2(-40.0 * s, 8.0 * s) # Lower emoji for lying NPCs
			draw_string(f, world_pos + offset, npc.current_emoji, HORIZONTAL_ALIGNMENT_CENTER, 80.0 * s, 20 * s)

	# BOMBARDERO (PLANE) VISUAL
	if bombardero_intensity > 0 and bombardero_texture:
		var size = Vector2(32.0, 32.0) * g_scale
		var offset = size / 2.0
		var center_pos = Vector2(bombardero_x, bombardero_y) * g_scale
		if bombardero_dir < 0.0:
			draw_set_transform(center_pos, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(bombardero_texture, Rect2(-offset, size), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.0))
		else:
			draw_texture_rect(bombardero_texture, Rect2(center_pos - offset, size), false)
			
	# BOMBS VISUAL
	for p in active_projectiles:
		if p.type == "bomber_bomb":
			var world_pos = p.pos * g_scale
			# Draw a premium black bomb with a lit red fuse (scaling visual size with explosion radius)
			var size_factor = 0.75
			var r_val = p.get("explosion_radius", 6)
			if r_val == 12:
				size_factor = 1.0
			elif r_val == 20:
				size_factor = 1.35
			var rad = g_scale * size_factor
			draw_circle(world_pos, rad, Color("202020"))
			draw_circle(world_pos + Vector2(0, -rad * 0.8), rad * 0.35, Color("FF3333"))
		elif p.type == "magic_lifted":
			var world_pos = p.pos * g_scale
			var mat = p.get("block_material", 1)
			var col = mat_colors_1[mat] if mat < mat_colors_1.size() else Color("#717E80")
			# Draw 1x1 block
			draw_rect(Rect2(world_pos, Vector2(g_scale, g_scale)), col)
			# Draw multi-layered neon blue & white glow
			var neon_blue = Color("#00EAFF")
			draw_rect(Rect2(world_pos - Vector2(g_scale, g_scale), Vector2(g_scale * 3, g_scale * 3)), Color(neon_blue.r, neon_blue.g, neon_blue.b, 0.15), false, 1.0)
			draw_rect(Rect2(world_pos - Vector2(g_scale * 0.5, g_scale * 0.5), Vector2(g_scale * 2, g_scale * 2)), Color(neon_blue.r, neon_blue.g, neon_blue.b, 0.4), false, 1.0)
			draw_rect(Rect2(world_pos - Vector2(g_scale * 0.2, g_scale * 0.2), Vector2(g_scale * 1.4, g_scale * 1.4)), Color(1.0, 1.0, 1.0, 0.85), false, 0.8)

func _process_tsunami(delta):
	if tsunami_timer <= 0:
		tsunami_intensity = 0
		if tsunami_player.playing: tsunami_player.stop()
		_update_menu_highlights()
		return
	
	tsunami_timer -= delta
	
	# Move the wave front from Left to Right (Gaussian Center)
	tsunami_wave_x += (grid_width / 5.0) * delta * 5.0
	if tsunami_wave_x > grid_width + 150:
		tsunami_intensity = 0 # STOP AFTER ONE PASS
		_update_menu_highlights()
		return
	
	# Wave Configuration Constants (HALF POWER)
	var radius = 25 + (20 * tsunami_intensity)
	var max_wave_height = 4 + (3 * tsunami_intensity) # MEGA = ~13 pixels total
	var sigma_sq = pow(radius / 2.5, 2)
	
	# Determine Sea Reference Level (Reference height outside the wave)
	var ref_x = int(tsunami_wave_x - radius - 10)
	if ref_x >= 0 and ref_x < grid_width:
		for gy in range(5, grid_height - 5):
			var idx = gy * grid_width + ref_x
			if (cells[idx] & 0xFF) > 0 and (material_tags_raw[_get_tags_id(cells[idx] & 0xFF)] & SandboxMaterial.Tags.LIQUID):
				break
	
	for ox in range(-radius, radius):
		var rx = int(tsunami_wave_x + ox)
		if rx < 0 or rx >= grid_width: continue
		
		# Gaussian Height target
		var dist_sq = float(ox * ox)
		var gauss_h = int(max_wave_height * exp(-dist_sq / (2.0 * sigma_sq)))
		if gauss_h <= 1: continue
		
		# Find surface and material
		var y_top = -1
		var mid = 0
		for gy in range(5, grid_height - 5):
			var idx = gy * grid_width + rx
			if idx >= 0 and idx < cells.size():
				var raw_id = cells[idx]
				var pure_id = raw_id & 0xFFFF
				if pure_id > 0 and _get_tags_id(pure_id) < material_tags_raw.size():
					if (material_tags_raw[_get_tags_id(pure_id)] & SandboxMaterial.Tags.LIQUID):
						y_top = gy
						mid = raw_id # Keep variant info
						break
		
		if y_top == -1: continue
		surface_cache[rx] = y_top
		
		# SOLID PIXEL SPAWNING (Smooth, no tremor)
		for i in range(gauss_h):
			var target_y = y_top - i
			var source_y = y_top + i + 1
			
			if target_y > 5 and source_y < grid_height:
				# Purely mathematical shift, no randf()
				if _get_cell(rx, target_y) == 0:
					_set_cell(rx, target_y, mid)
					var check_id = _get_cell(rx, source_y) & 0xFFFF
					if check_id > 0 and _get_tags_id(check_id) < material_tags_raw.size():
						if (material_tags_raw[_get_tags_id(check_id)] & SandboxMaterial.Tags.LIQUID):
							_set_cell(rx, source_y, 0)

func _start_bombardero():
	# Decide random direction: -1 (right to left) or 1 (left to right)
	bombardero_dir = 1.0 if _get_lut_rand() < 0.5 else -1.0
	
	# Determine speed (crosses in 4.0s)
	bombardero_speed = grid_width / 4.0
	
	# Determine Y position
	bombardero_y = 12.0
	
	# Start position outside grid
	if bombardero_dir == 1.0:
		bombardero_x = -40.0
	else:
		bombardero_x = grid_width + 40.0
		
	# Determine check count and drop probability based on intensity
	var checks_count = 4
	if bombardero_intensity == 1:
		bombardero_drop_prob = 0.3
		checks_count = 4
	elif bombardero_intensity == 2:
		bombardero_drop_prob = 0.55
		checks_count = 8
	elif bombardero_intensity == 3:
		bombardero_drop_prob = 0.8
		checks_count = 12
		
	# Distribute check points between x = 15.0 and x = grid_width - 15.0
	bombardero_pending_checks.clear()
	var check_xs = []
	for i in range(checks_count):
		var fraction = (float(i) + 0.5) / float(checks_count)
		var cx = lerp(15.0, float(grid_width) - 15.0, fraction)
		check_xs.append(cx)
		
	if bombardero_dir == 1.0:
		check_xs.sort()
	else:
		check_xs.sort()
		check_xs.reverse()
		
	bombardero_pending_checks = check_xs
	
	if not bombardero_texture:
		bombardero_texture = load("res://assets/icon_game/avion_bombardero.png")
		
	_manage_looping_player(bombardero_player, "bomber_engine")
	if is_instance_valid(bombardero_player):
		bombardero_player.volume_db = -6.0

func _stop_bombardero():
	bombardero_intensity = 0
	bombardero_pending_checks.clear()
	if is_instance_valid(bombardero_player) and bombardero_player.playing:
		bombardero_player.stop()

func _spawn_bomber_bomb(x, y):
	var bomb_r = 6
	if bombardero_intensity == 2:
		bomb_r = 12
	elif bombardero_intensity == 3:
		bomb_r = 20
		
	active_projectiles.append({
		"pos": Vector2(x, y),
		"vel": Vector2(bombardero_dir * 15.0, 50.0), # forward momentum + initial downward vel
		"team": -1,
		"type": "bomber_bomb",
		"life": 8.0,
		"explosion_radius": bomb_r
	})
	_play_action_sound("bomb_drop", 0.05)

func _process_bombardero(delta):
	if bombardero_intensity <= 0:
		return
		
	# Move the plane
	bombardero_x += bombardero_dir * bombardero_speed * delta
	
	# Perform checks
	if bombardero_dir == 1.0:
		while bombardero_pending_checks.size() > 0 and bombardero_x >= bombardero_pending_checks[0]:
			var _cx = bombardero_pending_checks.pop_front()
			if _get_lut_rand() < bombardero_drop_prob:
				_spawn_bomber_bomb(bombardero_x, bombardero_y)
	else:
		while bombardero_pending_checks.size() > 0 and bombardero_x <= bombardero_pending_checks[0]:
			var _cx = bombardero_pending_checks.pop_front()
			if _get_lut_rand() < bombardero_drop_prob:
				_spawn_bomber_bomb(bombardero_x, bombardero_y)
				
	# Check exit
	var is_finished = false
	if bombardero_dir == 1.0:
		if bombardero_x > grid_width + 40.0:
			is_finished = true
	else:
		if bombardero_x < -40.0:
			is_finished = true
			
	if is_finished:
		_stop_bombardero()
		_update_menu_highlights()

func _process_tornado(delta):
	if tornado_timer <= 0:
		tornado_intensity = 0
		tornado_element = 0
		tornado_element_timer = 0
		tornado_visual.visible = false # Ensure visual disappears
		if tornado_player.playing: tornado_player.stop()
		_update_menu_highlights()
		return
	
	tornado_timer -= delta
	
	# Play sound loop while tornado is active
	_manage_looping_player(tornado_player, "tornado_loop")
	
	# 1. Autonomous Movement
	if abs(tornado_x - tornado_target_x) < 5:
		tornado_target_x = _get_lut_rand() * grid_width
	
	tornado_x = lerp(tornado_x, tornado_target_x, delta * 0.5)
	
	# 1.5 Ground Tracking (Find the surface)
	var tx = int(tornado_x)
	var detected_y = grid_height - 1 # Default bottom
	# SCAN FROM BOTTOM UP: Find the first solid mass connected to the floor
	# and then find the 'air gap' above it to identify the true surface.
	var found_floor = false
	for gy in range(grid_height - 1, 40, -1):
		var c = _get_cell(tx, gy)
		var is_solid = (c > 0 and c != 17 and c != 15)
		
		if not found_floor:
			if is_solid: found_floor = true
		else:
			if not is_solid:
				# This is the air gap above the main ground mass
				detected_y = gy + 1
				break
	
	# If we are in intensity 3, the tornado is more 'sticky' to its height
	# Landing Animation: Faster lerp when descending from sky
	var is_landing = tornado_ground_y < detected_y - 50
	var lerp_val = 0.15 if is_landing else (0.05 if tornado_intensity < 3 else 0.02)
	tornado_ground_y = lerp(tornado_ground_y, float(detected_y), lerp_val)
	
	# Update Dedicated Visual Node
	if tornado_intensity > 0:
		tornado_visual.visible = true
		var t_width = (80.0 + tornado_intensity * 60.0) * grid_scale
		tornado_visual.size = Vector2(t_width, tornado_ground_y * grid_scale)
		tornado_visual.position = Vector2(tornado_x * grid_scale - t_width * 0.5, 0)
		
		# --- LOGRO: MAESTRO DE VIENTOS (Detección de seguridad) ---
		if not achievements["wind_master"].unlocked:
			_record_tornado_discovery(tornado_element)
			
		if tornado_element_timer > 0:
			tornado_element_timer -= delta
			if tornado_element_timer <= 0:
				tornado_element = 0
		
		# Absorption decay
		tornado_absorb_fire = lerp(tornado_absorb_fire, 0.0, delta * 2.0)
		tornado_absorb_acid = lerp(tornado_absorb_acid, 0.0, delta * 2.0)
		tornado_absorb_elec = lerp(tornado_absorb_elec, 0.0, delta * 2.0)
		
		# Thresholds to switch element
		if tornado_absorb_elec > 150:
			tornado_element = 3; tornado_element_timer = 6.0; tornado_absorb_elec = 0
			_record_tornado_discovery(3)
		elif tornado_absorb_acid > 200:
			tornado_element = 2; tornado_element_timer = 6.0; tornado_absorb_acid = 0
			_record_tornado_discovery(2)
		elif tornado_absorb_fire > 200:
			tornado_element = 1; tornado_element_timer = 6.0; tornado_absorb_fire = 0
			_record_tornado_discovery(1)
		
		tornado_visual.material.set_shader_parameter("intensity", float(tornado_intensity))
		tornado_visual.material.set_shader_parameter("element_type", tornado_element)
	else:
		tornado_visual.visible = false
	
	# 2. Conical Vortex Physics & Clouds
	# DELAY PHYSICS until the tornado touches the ground
	if is_landing:
		return
		
	# Spawn clouds at the top and internal dust to ensure it's always visible
	if _get_lut_rand() < 0.3:
		_set_cell(int(tornado_x + _get_lut_rand_range(-40, 40)), 2, 17)
		_set_cell(int(tornado_x + _get_lut_rand_range(-20, 20)), 1, 17)
	
	# INTERNAL DUST: Always spawn some particles inside the funnel so it's not 'empty'
	if _get_lut_rand() < 0.4:
		var spawn_y = int(tornado_ground_y - _get_lut_rand() * 150.0)
		if spawn_y > 0 and spawn_y < grid_height:
			var rel_y_s = 1.0 - (float(spawn_y) / tornado_ground_y) if tornado_ground_y > 0 else 1.0
			var rad_s = (25.0 + tornado_intensity * 15.0) + (50.0 * tornado_intensity * rel_y_s)
			_set_cell(int(tornado_x + _get_lut_rand_range(-rad_s * 0.4, rad_s * 0.4)), spawn_y, 15)
	
	# OPTIMIZED ITERATIONS: Increased for major destruction
	var points_to_process = 2000 * tornado_intensity if tornado_intensity < 3 else 6000
	
	for i in range(points_to_process):
		# Sample with bias: 60% of samples focus on the area near the ground
		var ry: int
		if _get_lut_rand() < 0.6:
			ry = int(tornado_ground_y + _get_lut_rand_range(-40, 100))
		else:
			ry = int(_get_lut_rand() * grid_height)
		
		if ry < 0 or ry >= grid_height: continue

		# Variable Radius relative to current GROUND level
		var rel_y = 1.0 - (float(ry) / tornado_ground_y) if tornado_ground_y > 0 else 1.0
		
		# Variable Radius calculation
		var current_radius = 0.0
		if ry <= tornado_ground_y:
			current_radius = (25.0 + tornado_intensity * 15.0) + (50.0 * tornado_intensity * rel_y)
		else:
			# Dig slightly into the ground
			current_radius = max(0, (25.0 + tornado_intensity * 15.0) - (ry - tornado_ground_y))
			
		# OPTIMIZED SAMPLING: Only sample within the area that passes the suction_threshold
		var suction_threshold = 0.4 if ry < tornado_ground_y - 80 else 0.6
		var max_dist_x = current_radius * (1.0 - suction_threshold)
		
		var rx = int(tornado_x + _get_lut_rand_range(-max_dist_x, max_dist_x))
		
		if rx < 0 or rx >= grid_width or ry < 0 or ry >= grid_height: continue
		
		var tid = cells[ry * grid_width + rx] & 0xFFFF # Inline fast lookup
		if tid == 0 or tid == 17: continue 
		
		var tags = material_tags_raw[_get_tags_id(tid)]
		
		# Absorption tracking (Prioritize Electricity/Acid tags if material has multiple)
		if (tags & SandboxMaterial.Tags.ELECTRICITY): tornado_absorb_elec += 1
		elif (tags & SandboxMaterial.Tags.ACID): tornado_absorb_acid += 1
		elif (tags & SandboxMaterial.Tags.INCENDIARY): tornado_absorb_fire += 1
		
		# Elemental Effects
		if tornado_element == 1: # FIRE
			if (tags & SandboxMaterial.Tags.FLAMMABLE):
				_set_cell(rx, ry, 3) # Ignite to Fire
			elif _get_lut_rand() < 0.05:
				_set_cell(rx, ry, 3)
		elif tornado_element == 2: # ACID
			if not (tags & SandboxMaterial.Tags.ANTI_ACID):
				if _get_lut_rand() < 0.2: _set_cell(rx, ry, 13) # Convert to Acid
		elif tornado_element == 3: # ELECTRIC
			charge_array[ry * grid_width + rx] = 255
			if _get_lut_rand() < 0.02: _set_cell(rx, ry, 43) # Spawn sparks
		
		# Vortex Forces
		var dist_x_abs = abs(tornado_x - rx)
		var pull_strength = 1.0 - (dist_x_abs / (current_radius + 1.0))

		var target_x = tornado_x + _get_lut_rand_range(-current_radius * 0.7, current_radius * 0.7)
		var dx = sign(target_x - rx)
		
		# Pull up FORCE: Massive buff for all levels
		var base_up = -8 if tornado_intensity < 2 else (-16 if tornado_intensity == 2 else -32)
		var dy = int(base_up * pull_strength)
		if dy >= 0: dy = -1 # Ensure it always moves up if caught
		
		if ry > tornado_ground_y: dy = 1 if _get_lut_rand() < 0.5 else -1 # Chaos/digging
		
		# Swirl/Orbital chance
		if _get_lut_rand() < 0.3: dx = -dx 
		
		# --- NPC INTERACTION (Fixes trails and adds physics) ---
		if (tags & SandboxMaterial.Tags.NPC):
			var nearby_npcs = _get_nearby_npcs(rx, ry, 15.0)
			for n in nearby_npcs:
				# Precise hit check for the NPC body
				if abs(n.pos.x - rx) <= 3 and ry >= n.pos.y and ry <= n.pos.y + 6:
					# Apply physics force instead of moving pixels directly
					n.vx += dx * pull_strength * 5.0
					n.vy += float(dy) * 0.4
					
					# Elemental Damage
					if tornado_element == 1: # Fire
						n.hp -= 0.6; n.hit_flash = 4; n.hit_type = "fire"
					elif tornado_element == 2: # Acid
						n.hp -= 1.0; n.hit_flash = 4; n.hit_type = "acid"
					elif tornado_element == 3: # Electric
						n.hp -= 0.5; n.hit_flash = 4; n.hit_type = "electric"
						
					if _get_lut_rand() < 0.05: _set_npc_emoji(n, "😱", 1.0)
			continue # SKIP manual pixel swap for NPCs to prevent tearing/trails
		
		# Suction Chance for normal materials
		if _get_lut_rand() < pull_strength:
			var nx = rx + dx
			var ny = ry + dy
			if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
				# Suction can lift anything into air
				if _get_cell(nx, ny) == 0:
					_swap_cells(rx, ry, nx, ny)
				elif _get_lut_rand() < 0.2: # Can also mix with other particles inside funnel
					_swap_cells(rx, ry, nx, ny)

func _process_earthquake(delta):
	if earthquake_timer <= 0:
		if texture_rect.position != Vector2.ZERO:
			texture_rect.position = Vector2.ZERO
		earthquake_intensity = 0
		if quake_player.playing: quake_player.stop()
		_update_menu_highlights()
		return
	
	earthquake_timer -= delta
	
	# Play sound loop while earthquake is active
	_manage_looping_player(quake_player, "quake_loop")
	
	# 1. Screen Shake (Visual) - Much more violent for higher intensities
	var shake_force = float(earthquake_intensity) * 6.0
	if earthquake_intensity >= 3: shake_force = 15.0 # Extra violent for BRUTAL
	
	if shake_force > 0:
		texture_rect.position = Vector2(_get_lut_rand_range(-shake_force, shake_force), _get_lut_rand_range(-shake_force, shake_force))
	
	# 2. Physics Chaos (Actual material movement)
	# Scaled iterations: light=4000, med=8000, brutal=15000 per frame
	var iterations = 4000 * earthquake_intensity 
	# Max displacement range: light=8, med=16, brutal=24 pixels
	var max_offset = float(earthquake_intensity * 8.0) 
	
	for i in range(iterations):
		# Random sampling across the whole grid
		var rx = int(_get_lut_rand() * grid_width)
		var ry = int(_get_lut_rand() * grid_height)
		var idx = ry * grid_width + rx
		
		# Skip air for performance optimization
		if cells[idx] == 0: continue
		
		# ANTI-TEARING: Don't move NPC pixels (they are managed as a single entity)
		var tid = cells[idx] & 0xFFFF
		if material_tags_raw[_get_tags_id(tid)] & SandboxMaterial.Tags.NPC: continue
		
		# Random direction and distance using LUT for "disparar" effect
		var dx = int(_get_lut_rand_range(-max_offset, max_offset))
		var dy = int(_get_lut_rand_range(-max_offset, max_offset))
		
		var nx = rx + dx
		var ny = ry + dy
		
		if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height:
			# ANTI-TEARING: Don't overwrite NPC pixels at destination either
			var n_tid = cells[ny * grid_width + nx] & 0xFFFF
			if not (material_tags_raw[_get_tags_id(n_tid)] & SandboxMaterial.Tags.NPC):
				# Massive mixing/dispersal: Swap regardless of what's there (liquefaction)
				_swap_cells(rx, ry, nx, ny)
				_activate_chunk(nx, ny) # Ensure it keeps moving/falling
			
	# 3. NPC Panic & Physical Displacement
	# NPCs should feel the earth moving without flying to the ceiling
	var shock_limit = float(earthquake_intensity) * 0.4
	for n in active_npcs:
		if n.hp > 0:
			# Very small horizontal jitter
			n.vx += _get_lut_rand_range(-shock_limit, shock_limit)
			
			# Occasional small vertical "pop" to simulate ground shock, 
			# but rare enough that gravity (20Hz) can easily overcome it
			if _get_lut_rand() < 0.05: 
				n.vy -= _get_lut_rand() * float(earthquake_intensity) * 1.5
			
			# Chance to trip or show emoji (less frequent)
			if _get_lut_rand() < 0.02 * earthquake_intensity:
				_set_npc_emoji(n, ["🫨", "😱", "😨"].pick_random(), 0.8)
	
	# Automatic stop after timer
	if earthquake_timer <= 0:
		earthquake_intensity = 0

func _process_weather():
	if current_weather == 0 and acid_rain_intensity == 0: 
		if weather_player.playing: weather_player.stop()
		return
	
	# Manage weather sound loop (rain_light, rain_med, rain_storm)
	var max_intensity = max(current_weather, acid_rain_intensity)
	var w_key = "weather_" + str(max_intensity)
	_manage_looping_player(weather_player, w_key)
	
	# Always spawn some clouds at the top if weather or acid rain is active
	for i in range(5):
		_set_cell(int(_get_lut_rand() * grid_width), 1, 17)
	
	# Spawn normal rain based on intensity
	if current_weather > 0:
		var rain_chance = 0.05 if current_weather == 1 else (0.2 if current_weather == 2 else 0.5)
		if _get_lut_rand() < rain_chance:
			# Spawn multiple droplets based on level
			for i in range(current_weather * 2):
				_set_cell(int(_get_lut_rand() * grid_width), 5 + int(_get_lut_rand() * 5), 2) # Spawn Water
				
	# Spawn acid rain based on intensity
	if acid_rain_intensity > 0:
		var acid_rain_chance = 0.05 if acid_rain_intensity == 1 else (0.2 if acid_rain_intensity == 2 else 0.5)
		if _get_lut_rand() < acid_rain_chance:
			# Spawn multiple acid droplets based on level
			for i in range(acid_rain_intensity * 2):
				_set_cell(int(_get_lut_rand() * grid_width), 5 + int(_get_lut_rand() * 5), 13) # Spawn Acid
			
	# Lightning in Storm (Level 3)
	if max_intensity == 3 and _get_lut_rand() < 0.01: # Rare but impactful
		_strike_lightning()
		
	# Spontaneous Grass growth during normal rain or near water (SURFACE ONLY)
	if current_weather > 0 and _get_lut_rand() < 0.2: # Check in 20% of frames
		for i in range(100): # 100 random samples per check
			var rx = int(_get_lut_rand() * grid_width)
			var ry = int(_get_lut_rand() * (grid_height - 10)) + 5
			var tid = _get_cell(rx, ry)
			if tid == 6 or tid == 1: # EARTH or SAND (FERTILE)
				if _get_cell(rx, ry-1) == 0: # Space above (Surface check)
					# Check for moisture (OVAL 20x10)
					if current_weather > 0 or _has_tag_within_oval(rx, ry, SandboxMaterial.Tags.LIQUID, 20, 10):
						if _get_lut_rand() < 0.1: # Organic chance
							_set_cell(rx, ry-1, 21) # GROW GRASS
							if i > 5: break

func _strike_lightning():
	_play_action_sound("lightning")
	var lx = int(_get_lut_rand() * grid_width)
	# Trace a bolt from top to first solid/liquid or bottom
	for ly in range(0, grid_height):
		var target_id = _get_cell(lx, ly)
		# Ignite everything in the bolt path
		_set_cell(lx, ly, 9) # Deploy Electricity!
		# If we hit something non-empty, stop bolt and create small explosion
		# NEW: Ignore rain (2) so it hits the ground
		if target_id > 0 and target_id != 17 and target_id != 15 and target_id != 2:
			_explode(lx, ly, 5, "explosion", EXP_VOLCANO | 128) # Small localized explosion
			break

func _strike_lightning_at(lx: int):
	_play_action_sound("lightning_user")
	# Trace a bolt straight down from the top at the given column
	for ly in range(0, grid_height):
		var target_id = _get_cell(lx, ly)
		_set_cell(lx, ly, 9) # Deploy Electricity!
		# Stop bolt at first solid/liquid (ignore rain=2, steam=17, snow=15)
		if target_id > 0 and target_id != 17 and target_id != 15 and target_id != 2:
			_explode(lx, ly, 5, "explosion", EXP_VOLCANO | 128) # Small localized explosion
			break

func _paint_background_circle(cx: int, cy: int, diameter: int, color: Color):
	var radius = diameter / 2.0
	var r2 = radius * radius
	# Expand range slightly to capture all relevant pixels
	var r_int = int(ceil(radius))
	for x in range(cx - r_int, cx + r_int + 1):
		for y in range(cy - r_int, cy + r_int + 1):
			if x >= 0 and x < grid_width and y >= 0 and y < dynamic_grid_height:
				# Use pixel-center distance (0.5 offset) for perfect circles
				var dx = float(x - cx)
				var dy = float(y - cy)
				if dx*dx + dy*dy <= r2:
					background_img.set_pixel(x, y, color)
					background_dirty = true

func _paint_elements_circle(cx: int, cy: int, diameter: int, color: Color):
	var radius = diameter / 2.0
	var r2 = radius * radius
	var r_int = int(ceil(radius))
	var color_int = color.to_abgr32() # Simulation-friendly format
	for x in range(cx - r_int, cx + r_int + 1):
		for y in range(cy - r_int, cy + r_int + 1):
			if x >= 0 and x < grid_width and y >= 0 and y < dynamic_grid_height:
				var dx = float(x - cx)
				var dy = float(y - cy)
				if dx*dx + dy*dy <= r2:
					var idx = y * grid_width + x
					# ONLY paint if there is a material (NOT air)
					if (cells[idx] & 0xFFFF) != 0:
						cell_paint_colors[idx] = color_int
						element_paint_dirty = true

func _draw_circle(cx, cy, radius, mat_id):
	if mat_id == 0:
		# ERASER: Also remove NPCs in range
		var nearby = _get_nearby_npcs(cx, cy, radius + 2)
		for npc in nearby:
			# Precise collision check: if any of the NPC's 5x2 pixels are inside the circle
			var hit = false
			for oy in range(5):
				for ox in range(2):
					var px = npc.pos.x + ox
					var py = npc.pos.y + oy
					if (px - cx)**2 + (py - cy)**2 <= radius**2:
						hit = true; break
				if hit: break
			
			if hit:
				npc.hp = 0 # Instant kill
				npc.hit_flash = 1 # Minimal flash to trigger removal next frame
	
	var r2 = radius * radius
	# BATCH OPTIMIZATION: We will manually activate the entire bounding box area once
	# to avoid redundant neighbor-checks in _set_cell/_activate_chunk
	var min_cx = int(float(cx - radius) / CHUNK_SIZE)
	var max_cx = int(float(cx + radius) / CHUNK_SIZE)
	var min_cy = int(float(cy - radius) / CHUNK_SIZE)
	var max_cy = int(float(cy + radius) / CHUNK_SIZE)
	
	for acy in range(min_cy - 1, max_cy + 2):
		if acy < 0 or acy >= chunks_y: continue
		var row = acy * chunks_x
		for acx in range(min_cx - 1, max_cx + 2):
			if acx >= 0 and acx < chunks_x:
				next_chunks_active[row + acx] = 60

	for y in range(-radius, radius + 1):
		var y2 = y * y
		var gy = cy + y
		if gy < 0 or gy >= dynamic_grid_height: continue
		for x in range(-radius, radius + 1):
			if x*x + y2 <= r2:
				_set_cell(cx + x, gy, mat_id)

func _set_cell_by_idx(idx: int, mat_id: int):
	if idx < 0 or idx >= cells.size(): return
	var x = idx % grid_width
	var y = int(idx / float(grid_width))
	_set_cell(x, y, mat_id)

func _prime_explosive_by_idx(idx: int, id: int, manual_flags: int = -1):
	_prime_explosive(idx % grid_width, int(idx / float(grid_width)), id, manual_flags)

func _register_material(id: int, color1: Color, tags: int, color2 = null, color3 = null):
	mat_colors_1[id] = color1
	mat_colors_2[id] = color2 if color2 != null else color1
	mat_colors_3[id] = color3 if color3 != null else (color2 if color2 != null else color1)
	material_tags_raw[_get_tags_id(id)] = tags

func _set_cell(x, y, mat_id):
	var ix = int(x)
	var iy = int(y)
	if ix >= 0 and ix < grid_width and iy >= 0 and iy < dynamic_grid_height:
		var idx = iy * grid_width + ix
		
		# NPC Activator (90) and NPC Door (91) PROTECTION from NPC Overwriting
		var current_tid = cells[idx] & 0xFFFF
		if (current_tid == 90 or current_tid == 91) and mat_id != 0:
			var look_pure = mat_id & 0xFFFF
			if look_pure >= 0 and _get_tags_id(look_pure) < material_tags_raw.size():
				if (material_tags_raw[_get_tags_id(look_pure)] & SandboxMaterial.Tags.NPC):
					return
		
		# CRITICAL PERFORMANCE OPTIMIZATION: Early Exit for Air
		if mat_id == 0:
			if cells[idx] == 0: return # Already air, no work needed
			@warning_ignore("confusable_local_declaration")
			var _old_id_c = cells[idx] & 0xFFFF
			if _old_id_c == 600: active_metronome_indices.erase(idx)
			elif _old_id_c == 88: active_battery_indices.erase(idx)
			elif _old_id_c == 9: active_electricity_source_indices.erase(idx)
			if _old_id_c == 91 and not is_npc_door_updating:
				door_registry.erase(idx)
			if _old_id_c == 92 and not is_phase_block_updating:
				phase_block_registry.erase(idx)
			if _old_id_c == 96 and not is_hollowing_pipe:
				is_pipe_dirty = true
				var bx = int(floor(float(x) / 4.0)) * 4
				var by = int(floor(float(y) / 4.0)) * 4
				for oy in range(4):
					for ox in range(4):
						var tidx = (by + oy) * grid_width + (bx + ox)
						if tidx >= 0 and tidx < cells.size() and (cells[tidx] & 0xFFFF) == 96:
							cells[tidx] = 0
							cell_paint_colors[tidx] = 0
			elif _old_id_c == 97 and not is_hollowing_pipe:
				is_pipe_dirty = true
				var bx = int(floor(float(x) / 8.0)) * 8
				var by = int(floor(float(y) / 8.0)) * 8
				for oy in range(8):
					for ox in range(8):
						var tidx = (by + oy) * grid_width + (bx + ox)
						if tidx >= 0 and tidx < cells.size() and (cells[tidx] & 0xFFFF) == 97:
							cells[tidx] = 0
							cell_paint_colors[tidx] = 0
			
			cells[idx] = 0
			if cell_paint_colors[idx] != 0:
				cell_paint_colors[idx] = 0
				if not element_paint_dirty: element_paint_dirty = true
			tags_array[idx] = 0
			charge_array[idx] = 0
			charge_visual_buffer[idx] = 0
			charge_dirty = true
			_activate_chunk(x, y)
			return

		# ENSURE mat_id is just the base material ID for lookup (Strip variants/data)
		var pure_id = mat_id & 0xFFFF
		var tags_id = _get_tags_id(mat_id)

		if tags_id < 0 or tags_id >= material_tags_raw.size(): return
		
		# PERFORMANCE: Early exit if the material is already exactly the same
		if (cells[idx] & 0xFFFF) == pure_id: return
		
		var tags = material_tags_raw[_get_tags_id(tags_id)]
		
		# Scalable Texturing Variant calculation
		var variant = (mat_id >> 24) & 0xFF
		if pure_id == 89 and variant == 0:
			variant = 8 if selected_led_color == 7 else selected_led_color
		if variant == 0 and (tags & (SandboxMaterial.Tags.TEXTURE_DOUBLE | SandboxMaterial.Tags.TEXTURE_TRIPLE)):
			var mix_prob = 0.35 # Medium default
			if (tags & SandboxMaterial.Tags.MIX_LOW): mix_prob = 0.15
			elif (tags & SandboxMaterial.Tags.MIX_HIGH): mix_prob = 0.55
			
			if randf() < mix_prob:
				variant = 1
				if (tags & SandboxMaterial.Tags.TEXTURE_TRIPLE) and randf() < 0.35:
					variant = 2
		
		# TRACK METRONOME, BATTERY, AND ELECTRICITY REGISTRIES
		@warning_ignore("confusable_local_declaration")
		var _old_id_c = cells[idx] & 0xFFFF
		if _old_id_c == 600: active_metronome_indices.erase(idx)
		elif _old_id_c == 88: active_battery_indices.erase(idx)
		elif _old_id_c == 9: active_electricity_source_indices.erase(idx)
		if _old_id_c == 91 and not is_npc_door_updating:
			door_registry.erase(idx)
		if _old_id_c == 92 and not is_phase_block_updating:
			phase_block_registry.erase(idx)
		
		if pure_id == 600: active_metronome_indices[idx] = true
		elif pure_id == 88: active_battery_indices[idx] = true
		elif pure_id == 9: active_electricity_source_indices[idx] = true
		if pure_id == 91:
			door_registry[idx] = true
		if pure_id == 92:
			phase_block_registry[idx] = true
			_check_phase_block_tutorial(Vector2i(x / 4, y / 4))

		# For specific IDs (Metronome/Music), clear paint
		if pure_id >= 500: cell_paint_colors[idx] = 0
		
		cells[idx] = (mat_id & 0xFFFF) | (variant << 24)
		tags_array[idx] = tags
		# CLEANUP GLOW: Prevent ghost colors when painting over old explosions
		charge_array[idx] = 0
		if idx < charge_visual_buffer.size():
			charge_visual_buffer[idx] = 0
		charge_dirty = true
		
		# CLEAR PAINT on material change to avoid "phantom" colors
		if cell_paint_colors[idx] != 0:
			cell_paint_colors[idx] = 0
			if not element_paint_dirty: element_paint_dirty = true
			
		_activate_chunk(ix, iy)

		if (tags & SandboxMaterial.Tags.ELECTRICITY): 
			charge_array[idx] = 101
			_register_charge(idx)
			charge_dirty = true

func _activate_chunk(gx, gy):
	var cx = int(gx) >> 4
	var cy = int(gy) >> 4
	if cx >= 0 and cx < chunks_x and cy >= 0 and cy < chunks_y:
		var c_idx = cy * chunks_x + cx
		if next_chunks_active[c_idx] >= 60: return
		next_chunks_active[c_idx] = 60
		for oy in range(-1, 2):
			var ncy = cy + oy
			if ncy >= 0 and ncy < chunks_y:
				var row_offset = ncy * chunks_x
				for ox in range(-1, 2):
					var ncx = cx + ox
					if ncx >= 0 and ncx < chunks_x:
						next_chunks_active[row_offset + ncx] = 60

func _get_cell(x, y):
	var ix = int(x)
	var iy = int(y)
	if ix >= 0 and ix < grid_width and iy >= 0 and iy < dynamic_grid_height:
		return cells[iy * grid_width + ix] & 0xFFFF
	return -1

func _step_simulation():
	# --- FIX GODOT 4 COW THREADING BUG ---
	# Force copy-on-write on the main thread before workers start. 
	# If save_history_state() duplicated the arrays, the first write detaches the buffer.
	# Doing this in a worker thread concurrently causes engine-level memory crashes!
	if cells.size() > 0:
		cells[0] = cells[0]
		tags_array[0] = tags_array[0]
		charge_array[0] = charge_array[0]
		if charge_visual_buffer.size() > 0: charge_visual_buffer[0] = charge_visual_buffer[0]
		
	# Reset flags de sonidos ambientales
	is_volcano_active = false
	is_fire_active = false
	
	# Pass 0: RESET FRAME COUNTERS
	explosions_this_frame = 0
	
	# Pass 0.1: METRONOME GLOBAL PULSE
	if _frame_count % music_tempo_frames == 0:
		for idx in active_metronome_indices:
			charge_array[idx] = 101
			_register_charge(idx)
			_activate_chunk(idx % grid_width, int(idx / float(grid_width)))
	
	# Pass 0.2: Swap and Decay Chunks (Memory efficient)
	var tmp = chunks_active
	chunks_active = next_chunks_active
	next_chunks_active = tmp # Swap buffers
	
	for i in range(chunks_active.size()):
		var val = chunks_active[i]
		if val > 0:
			next_chunks_active[i] = val - 1
		else:
			next_chunks_active[i] = 0
			
	# Pass 0.3: Random Chunk Ticks (Allows nature to grow slowly in sleeping areas)
	if chunks_active.size() > 0:
		var pokes = max(1, int(chunks_active.size() / 10.0))
		for p in range(pokes):
			var poke_idx = randi() % chunks_active.size()
			if chunks_active[poke_idx] == 0:
				chunks_active[poke_idx] = 2
				next_chunks_active[poke_idx] = 1
	
	# Pass 1: Electricity Pulse Processing (SPARSE)
	_process_electricity()
	
	# Transition Active Charges to Next Frame
	active_charge_indices.append_array(next_charge_indices)
	next_charge_indices.clear()
	
	# Pass 2 & 3: Movement and Interactions (Calculated)
	# ... after main loops conclude, manage the persistent sounds once ...
	
	var is_even_frame = (_frame_count % 2 == 0)
	var pass_groups = ceil(float(chunks_x) / 2.0)
	
	# Pass 2: RISING and SPECIAL particles (Top-to-Bottom by Active Chunks)
	# Executed synchronously on Main Thread to PREVENT Scudo Memory Corruption! (C++ handles 90% of the physics anyway)
	for i in range(pass_groups): _thread_pass2(i, is_even_frame)
	for i in range(pass_groups): _thread_pass2(i, not is_even_frame)

	# Pass 3: FALLING/STATIC particles (Bottom-to-Top by Active Chunks)
	
	var cpp_state = { 
		"cells": cells, 
		"tags_array": tags_array,
		"charge_array": charge_array,
		"material_tags_raw": material_tags_raw,
		"charge_visual_buffer": charge_visual_buffer,
		"cell_paint_colors": cell_paint_colors
	}
	# CLEAR GDScript references before passing to C++ to PREVENT massive 10-second Copy-On-Write GC freezes!
	cells = PackedInt32Array()
	tags_array = PackedInt64Array()
	charge_array = PackedInt32Array()
	charge_visual_buffer = PackedByteArray()
	cell_paint_colors = PackedInt32Array()
	
	cpp_state = process_physics(cpp_state, grid_width, dynamic_grid_height, _frame_count)
	cells = cpp_state["cells"]
	tags_array = cpp_state["tags_array"]
	charge_array = cpp_state["charge_array"]
	charge_visual_buffer = cpp_state["charge_visual_buffer"]
	cell_paint_colors = cpp_state["cell_paint_colors"]
	if cpp_state.get("paint_changed", false):
		element_paint_dirty = true
		
	if cpp_state.has("moved_charges"):
		active_charge_indices.append_array(cpp_state["moved_charges"])
	
	var cpp_explosions = cpp_state.get("explosions", [])
	if cpp_explosions.size() > 0:
		for expl in cpp_explosions:
			var ign_flags = expl[4] if expl.size() > 4 else 0
			_explode(expl[0], expl[1], expl[2], expl[3], ign_flags, true, 0.0, true)
			var b_idx = (expl[1] / 8) * 1000 + (expl[0] / 8)
			if not _tnt_buckets_this_frame.has(b_idx):
				_tnt_buckets_this_frame[b_idx] = true
				_tnt_chain_count += 1
				_tnt_chain_flags |= expl[4]
				_tnt_chain_timer = 0.6
	# ============================================

	for i in range(pass_groups): _thread_pass3(i, is_even_frame)
	for i in range(pass_groups): _thread_pass3(i, not is_even_frame)

	# === GESTIÓN GLOBAL DE SONIDOS AMBIENTALES ===
	if is_volcano_active: 
		_manage_looping_player(volcano_loop_player, "volcan_active")
	else: 
		if volcano_loop_player.playing: volcano_loop_player.stop()
		
	if is_fire_active:
		_manage_looping_player(fire_loop_player, "burn_loop")
	else:
		if fire_loop_player.playing: fire_loop_player.stop()

func _thread_pass2(i: int, process_evens: bool):
	var cx = (i * 2) if process_evens else (i * 2 + 1)
	if cx >= chunks_x: return
	
	var sweep_reverse_base = _frame_count % 2 == 0
	var x_start = cx * CHUNK_SIZE
	var x_end = min(x_start + CHUNK_SIZE, grid_width)
	var x_range = x_end - x_start
	
	for cy in range(chunks_y):
		var c_idx = cy * chunks_x + cx
		if chunks_active[c_idx] == 0: continue
		var y_start = cy * CHUNK_SIZE
		var y_end = min(y_start + CHUNK_SIZE, dynamic_grid_height)
		
		for y in range(y_start, y_end):
			var row_idx = y * grid_width
			var sweep_reverse = (sweep_reverse_base != (y % 2 == 0))
			
			for xi in range(x_range):
				var x = (x_end - 1 - xi) if sweep_reverse else (x_start + xi)
				var idx = row_idx + x
				if idx >= cells.size() or idx >= tags_array.size(): continue
				var raw_id = cells[idx]
				var pure_id = raw_id & 0xFFFF
				if pure_id == 0: continue
				
				var tags = tags_array[idx]
				if pure_id == 7: # Primed Explosives
					_activate_chunk(x, y)
					continue

				if (tags & SandboxMaterial.Tags.GRAV_UP):
					if (tags & TAGS_INTERACTIVE) != 0 or pure_id >= 18:
						_process_interactions(x, y, idx, raw_id, pure_id, tags)
						
					if cells[idx] == raw_id and pure_id != 28:
						_move_particle(x, y, raw_id, tags, -1)

func _thread_pass3(i: int, process_evens: bool):
	var cx = (i * 2) if process_evens else (i * 2 + 1)
	if cx >= chunks_x: return
	
	var sweep_reverse_base = _frame_count % 2 == 0
	var x_start = cx * CHUNK_SIZE
	var x_end = min(x_start + CHUNK_SIZE, grid_width)
	var x_range = x_end - x_start
	
	for cy in range(chunks_y - 1, -1, -1):
		var c_idx = cy * chunks_x + cx
		if chunks_active[c_idx] == 0: continue
		var y_start = cy * CHUNK_SIZE
		var y_end = min(y_start + CHUNK_SIZE, dynamic_grid_height)
		
		for y in range(y_end - 1, y_start - 1, -1):
			var row_idx = y * grid_width
			var sweep_reverse = (sweep_reverse_base != (y % 2 == 0))
			
			for xi in range(x_range):
				var x = (x_end - 1 - xi) if sweep_reverse else (x_start + xi)
				var idx = row_idx + x
				if idx >= cells.size() or idx >= tags_array.size(): continue
				var raw_id = cells[idx]
				var pure_id = raw_id & 0xFFFF
				
				if pure_id > 0:
					var tags = tags_array[idx]
					
					if (not (tags & SandboxMaterial.Tags.GRAV_UP)): 
						if (tags & TAGS_INTERACTIVE) != 0 or pure_id >= 18 or pure_id == 7 or pure_id == 9 or pure_id == 13: 
							_process_interactions(x, y, idx, raw_id, pure_id, tags)
							
						if cells[idx] == raw_id and not (tags & SandboxMaterial.Tags.GRAV_STATIC):
							var should_move = true
							if (tags & SandboxMaterial.Tags.GRAV_SLOW) and _get_lut_rand() > 0.3:
								should_move = false
							
							if should_move:
								pass

func _process_electricity():
	var frame = _frame_count
	
	# 1. Store previous frame active music charges in a set for edge-triggering music blocks
	var prev_active_music_charges = {}
	var prev_charges = {}
	for idx in active_charge_indices:
		prev_charges[idx] = true
		var mid = cells[idx] & 0xFFFF
		if _is_music_mat(mid):
			prev_active_music_charges[idx] = true
		
	# 2. Collect constant sources this frame
	var sources = []
	
	# Batteries (ID 88)
	for idx in active_battery_indices:
		sources.append(idx)
		
	# Electricity (ID 9)
	for idx in active_electricity_source_indices:
		sources.append(idx)
		
	# NPC Activators (ID 90) detection
	for npc in active_npcs:
		if npc.hp <= 0: continue
		var w = 3 if (npc.type == "zombie_tank") else 2
		var h = 6 if (npc.type == "zombie_tank" or npc.type == "mage") else 5
		
		var start_x = int(npc.pos.x)
		var start_y = int(npc.pos.y)
		for oy in range(h + 1):
			var ny = start_y + oy
			if ny < 0 or ny >= grid_height: continue
			var row_offset = ny * grid_width
			for ox in range(w):
				var nx = start_x + ox
				if nx < 0 or nx >= grid_width: continue
				
				var n_idx = row_offset + nx
				if (cells[n_idx] & 0xFFFF) == 90:
					sources.append(n_idx)
		
	# Metronomes (ID 600) on pulsing frames
	var is_metronome_pulsing = (frame % music_tempo_frames == 0)
	if is_metronome_pulsing:
		for idx in active_metronome_indices:
			var gx = idx % grid_width
			var gy = idx / grid_width
			for dy in range(2):
				var ny = gy + dy
				if ny >= grid_height: continue
				var row_offset = ny * grid_width
				for dx in range(2):
					var nx = gx + dx
					if nx >= grid_width: continue
					var n_idx = row_offset + nx
					sources.append(n_idx)
					
	# Logic gate outputs
	for gate in active_logic_gates:
		if gate.get("output_active", false):
			var pins = _get_logic_gate_output_pins(gate)
			for p_idx in pins:
				sources.append(p_idx)
				
	# Initialize sources to 100 in charge_array
	for idx in sources:
		charge_array[idx] = 100
		charge_visual_buffer[idx] = 100
		_register_charge(idx)
		
	# Pack the state and sources
	var state = {
		"cells": cells,
		"tags_array": tags_array,
		"charge_array": charge_array,
		"charge_visual_buffer": charge_visual_buffer,
		"powered_frame": powered_frame,
		"next_chunks_active": next_chunks_active,
		"active_charge_indices": active_charge_indices,
		"sources_indices": sources,
		"phase_blocks_indices": phase_block_registry.keys(),
		"prev_charges": prev_charges.keys(),
		"prev_active_music_charges": prev_active_music_charges.keys()
	}
	# Drop references to prevent Godot Copy-On-Write lag spikes
	cells = PackedInt32Array()
	tags_array = PackedInt64Array()
	charge_array = PackedInt32Array()
	charge_visual_buffer = PackedByteArray()
	powered_frame = PackedInt32Array()
	next_chunks_active = PackedByteArray()
	active_charge_indices = PackedInt32Array()
	
	# Execute native physics for electricity
	var new_state = process_electricity(state, grid_width, grid_height, frame)
	
	# Recover updated state
	cells = new_state["cells"]
	tags_array = new_state["tags_array"]
	charge_array = new_state["charge_array"]
	charge_visual_buffer = new_state["charge_visual_buffer"]
	active_charge_indices = new_state["active_charge_indices"]
	powered_frame = new_state["powered_frame"]
	next_chunks_active = new_state["next_chunks_active"]
	
	# Spawn sparks from BFS
	var out_sparks = new_state["out_sparks"]
	for spark_pos in out_sparks:
		_add_spark(spark_pos.x, spark_pos.y, _get_lut_rand_range(-10, 10), _get_lut_rand_range(-10, 10), Color("#FFC107"), 0.3)
		
	# Trigger music notes
	var out_music_notes = new_state["out_music_notes"]
	for note_data in out_music_notes:
		var inst = int(note_data.x)
		var note = int(note_data.y)
		var b_idx = -1
		if typeof(note_data) == TYPE_VECTOR3:
			b_idx = int(note_data.z)
			
		if inst == 5:
			_play_music_note(5, 0, false, 2, b_idx)
		else:
			var raw_mid = (inst * 16) + note + 500
			var m_data = _get_music_data(raw_mid)
			_play_music_note(m_data.inst, m_data.note, false, m_data.octave, b_idx)
		
	charge_dirty = true
	
	# 6. Simulate logic gates to prepare outputs for next frame
	_simulate_logic_gates()




func _move_particle(x, y, _mat_id, tags, v_dir):
	# SPECIAL GAS BEHAVIOR: Random Diffusion (Expansion)
	if (tags & SandboxMaterial.Tags.GAS):
		# Higher chance of random movement to simulate expansion
		if _get_lut_rand() < 0.3: # 30% chance of random "jump"
			var rx = x + (1 if _get_lut_rand() > 0.5 else -1)
			var ry = y + (1 if _get_lut_rand() > 0.5 else -1)
			if _get_cell(rx, ry) == 0:
				_swap_cells(x, y, rx, ry)
				return
	
	var next_y = y + v_dir
	if next_y < 0 or next_y >= dynamic_grid_height: return
	
	# Try directly moving
	if _get_cell(x, next_y) == 0:
		_swap_cells(x, y, x, next_y)
		return
	
	# Try diagonals (only for powder, liquids and gases)
	if (tags & (SandboxMaterial.Tags.POWDER | SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GAS)):
		var side = 1 if _get_lut_rand() > 0.5 else -1
		if _get_cell(x + side, next_y) == 0:
			_swap_cells(x, y, x + side, next_y)
		elif _get_cell(x - side, next_y) == 0:
			_swap_cells(x, y, x - side, next_y)
		elif (tags & (SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.GAS)):
			# Flow laterally if gravity path is blocked
			if _get_cell(x + side, y) == 0:
				_swap_cells(x, y, x + side, y)
			elif _get_cell(x - side, y) == 0:
				_swap_cells(x, y, x - side, y)

func _swap_cells(x1, y1, x2, y2):
	if y1 < 0 or y1 >= dynamic_grid_height or y2 < 0 or y2 >= dynamic_grid_height: return
	if x1 < 0 or x1 >= grid_width or x2 < 0 or x2 >= grid_width: return
	
	if view_zoom > 1.0:
		# Enforce virtual physical boundaries tied to the camera viewport
		var in_cam1 = (x1 >= cam_min_x and x1 < cam_max_x and y1 >= cam_min_y and y1 < cam_max_y)
		var in_cam2 = (x2 >= cam_min_x and x2 < cam_max_x and y2 >= cam_min_y and y2 < cam_max_y)
		if in_cam1 != in_cam2: return # Block swaps that cross the camera boundary
	
	var idx1 = y1 * grid_width + x1
	var idx2 = y2 * grid_width + x2
	
	if idx1 >= cells.size() or idx2 >= cells.size() or idx1 >= tags_array.size() or idx2 >= tags_array.size(): return
	
	var m1 = cells[idx1]
	var m2 = cells[idx2]
	
	cells[idx1] = m2
	tags_array[idx1] = material_tags_raw[_get_tags_id(m2)]
	cells[idx2] = m1
	tags_array[idx2] = material_tags_raw[_get_tags_id(m1)]
	
	# LAZY UPDATE: Only swap extra arrays if they contain data (Huge memory bandwidth save)
	var c1 = charge_array[idx1]
	var c2 = charge_array[idx2]
	if c1 > 0 or c2 > 0:
		charge_array[idx1] = c2
		charge_array[idx2] = c1
		var cv1 = charge_visual_buffer[idx1]
		var cv2 = charge_visual_buffer[idx2]
		charge_visual_buffer[idx1] = cv2
		charge_visual_buffer[idx2] = cv1
		charge_dirty = true
		if c1 > 0: _register_charge(idx2)
		if c2 > 0: _register_charge(idx1)
	
	var color1 = cell_paint_colors[idx1]
	var color2 = cell_paint_colors[idx2]
	if color1 != 0 or color2 != 0:
		cell_paint_colors[idx1] = color2
		cell_paint_colors[idx2] = color1
		element_paint_dirty = true
	
	_activate_chunk(x1, y1)
	_activate_chunk(x2, y2)

func _register_charge(idx):
	var frame = _frame_count
	if charge_queued_frame[idx] != frame:
		sim_mutex.lock()
		if charge_queued_frame[idx] != frame:
			charge_queued_frame[idx] = frame
			next_charge_indices.append(idx)
		sim_mutex.unlock()

func _process_interactions(x, y, idx, _raw_id, pure_id, tags):
	# PULSANT ELECTRICAL SOURCE
	if pure_id == 9:
		if charge_array[idx] == 0:
			charge_array[idx] = 101
			_register_charge(idx)
			
	# METRONOME: Self-pulsing electrical source
	if pure_id == 600:
		if _frame_count % music_tempo_frames == 0:
			var gx = idx % grid_width
			var gy = int(float(idx) / grid_width)
			# Only pulse from the master pixel of the 2x2 block
			if (gx % 2 == 0 and gy % 2 == 0):
				# Emit a pulse only if it's not already busy
				if charge_array[idx] <= 10: 
					charge_array[idx] = 101
					_register_charge(idx)
		
	# VIRUS / EXPAND LOGIC (Laboratory Exclusive)
	if (tags & SandboxMaterial.Tags.VIRUS):
		if _get_lut_rand() < 0.05: # Reduced probability for better performance (from 0.15)
			var nx = x + _get_lut_rand_range(-1, 1)
			var ny = y + _get_lut_rand_range(-1, 1)
			if nx >= 0 and nx < grid_width and ny >= 0 and ny < dynamic_grid_height:
				var nid = cells[ny * grid_width + nx] & 0xFFFF # Faster than _get_cell
				# RANGE FIX: Allow infecting up to ID 1000 to include Lab Experiments (900+)
				if nid > 0 and nid != pure_id and nid < 1000: 
					var n_tags = material_tags_raw[_get_tags_id(nid)]
					
					# FIGHT LOGIC: If the target is ANOTHER type of virus, ignore protections!
					# This allows different virus types to "fight" for territory.
					var is_enemy_virus = (n_tags & SandboxMaterial.Tags.VIRUS) != 0
					var is_protected = (n_tags & (SandboxMaterial.Tags.ANTI_ACID | SandboxMaterial.Tags.INVINCIBLE)) != 0
					
					if is_enemy_virus or not is_protected: 
						_set_cell(nx, ny, pure_id)
						
	# RADIOACTIVE LOGIC (Laboratory Exclusive - Constant Energy Reactor)
	if (tags & SandboxMaterial.Tags.RADIOACTIVE):
		if _get_lut_rand() < 0.005: # Reduced frequency (from 0.02)
			for ny in range(y - 1, y + 2):
				for nx in range(x - 1, x + 2):
					if nx == x and ny == y: continue
					if nx < 0 or nx >= grid_width or ny < 0 or ny >= dynamic_grid_height: continue
					var n_idx = ny * grid_width + nx
					if charge_array[n_idx] < 50:
						charge_array[n_idx] = 101 # Intense electrical pulse
						_register_charge(n_idx)
			# Occasional visual discharge
			if _get_lut_rand() < 0.1 and _get_cell(x, y - 1) == 0:
				_set_cell(x, y - 1, 43)
				
	# VORTEX LOGIC (Laboratory Exclusive - Black Hole Effect)
	if (tags & SandboxMaterial.Tags.VORTEX):
		# SUPER VORTEX: Optimized processing (10% chance per pixel, but high density pulse)
		if _get_lut_rand() < 0.1:
			# 1. MATERIAL SUCTION & CONSUMPTION
			for i in range(20): # from 20 power
				var l_idx = int(_get_lut_rand() * (LUT_SIZE - 1))
				var dist = int(_get_lut_rand() * 45)
				var vx = x + int(cos_lut[l_idx] * dist)
				var vy = y + int(sin_lut[l_idx] * dist)
				
				if vx >= 0 and vx < grid_width and vy >= 0 and vy < dynamic_grid_height:
					if vx == x and vy == y: continue
					var vid = cells[vy * grid_width + vx] & 0xFFFF
					if vid > 0 and vid != pure_id and vid < 500:
						var n_tags = material_tags_raw[_get_tags_id(vid)]
						if not (n_tags & SandboxMaterial.Tags.INVINCIBLE):
							# Use squared distance to avoid sqrt in inner loop
							var dx_v = x - vx
							var dy_v = y - vy
							var d_sq = dx_v*dx_v + dy_v*dy_v
							
							if d_sq <= 36: # dist <= 6
								_set_cell(vx, vy, 0)
								if _get_lut_rand() < 0.05: _add_spark(float(vx), float(vy), 0, 0, Color.BLACK, 0.4)
							elif not (n_tags & SandboxMaterial.Tags.GRAV_STATIC): # Move mobile things
								var dx = sign(dx_v)
								var dy = sign(dy_v)
								if dy < 0 and _get_lut_rand() < 0.4: dy = -1 
								
								var tx = vx + dx; var ty = vy + dy
								if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
									var tid = cells[ty * grid_width + tx] & 0xFFFF
									if tid == 0 or tid < 500: 
										_swap_cells(vx, vy, tx, ty)
			
			# 2. NPC PULL (Sparse calculation: 20% of vortex pixels pull NPCs)
			if _get_lut_rand() < 0.1:
				var nearby_npcs = _get_nearby_npcs(x, y, 30.0)
				for npc in nearby_npcs:
					var dx_n = x - npc.pos.x
					var dy_n = y - npc.pos.y
					var d_inv = 1.0 / max(1.0, sqrt(dx_n*dx_n + dy_n*dy_n))
					npc.vx += dx_n * d_inv * 0.1
					npc.vy += dy_n * d_inv * 0.1
					if (dx_n*dx_n + dy_n*dy_n) < 36: 
						npc.hp -= 10.0 
		
	# REPEL LOGIC (Laboratory Exclusive - Fan/Wind effect)
	if (tags & SandboxMaterial.Tags.REPEL):
		if _get_lut_rand() < 0.1: # Reduced from 0.1
			# 1. MEGA MATERIAL REPULSION (Blast Away)
			for i in range(30): # 20 POWER
				var l_idx = int(_get_lut_rand() * (LUT_SIZE - 1))
				var dist = int(_get_lut_rand() * 35)
				var vx = x + int(cos_lut[l_idx] * dist)
				var vy = y + int(sin_lut[l_idx] * dist)
				
				if vx >= 0 and vx < grid_width and vy >= 0 and vy < dynamic_grid_height:
					if vx == x and vy == y: continue
					var vid = cells[vy * grid_width + vx] & 0xFFFF
					if vid > 0 and vid != pure_id and vid < 1000:
						var n_tags = material_tags_raw[_get_tags_id(vid)]
						if not (n_tags & SandboxMaterial.Tags.GRAV_STATIC):
							var dx = sign(vx - x) * _get_lut_rand_range(2, 6)
							var dy = sign(vy - y) * _get_lut_rand_range(1, 4)
							if dy == 0: dy = -1 
							
							var tx = vx + dx; var ty = vy + dy
							if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
								if (cells[ty * grid_width + tx] & 0xFFFF) == 0:
									_swap_cells(vx, vy, tx, ty)
									if _get_lut_rand() < 0.05: _add_spark(float(vx), float(vy), float(dx), float(dy), Color.WHITE, 0.4)
			
			# 2. NPC PUSH (Sparse calculation: 20% of repel pixels push NPCs)
			if _get_lut_rand() < 0.02:
				var nearby_npcs = _get_nearby_npcs(x, y, 5.0)
				for npc in nearby_npcs:
					var dx_n = npc.pos.x - x
					var dy_n = npc.pos.y - y
					var d_sq = dx_n*dx_n + dy_n*dy_n
					if d_sq < 9.0: d_sq = 9.0 
					var force = 35.0 / sqrt(d_sq)
					var d_inv = 1.0 / sqrt(d_sq)
					npc.vx += dx_n * d_inv * force * 1.5
					npc.vy += (dy_n * d_inv * force) - 3.5 
					if _get_lut_rand() < 0.05: npc.hp -= 1.0 
		
	# FIRE AND HEAT REACTIONS (Lógica térmica movida a C++ Fase 3)
	if (tags & SandboxMaterial.Tags.INCENDIARY):
		if pure_id == 3 or pure_id == 14: is_fire_active = true

	# REACTIVE MATERIALS (Explosives) - Flammable logic moved to C++
	if (tags & SandboxMaterial.Tags.EXPLOSIVE):
		var is_primed_or_hot = charge_array[idx] > 50 or (_get_lut_rand() < 0.2 and _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY))
		if is_primed_or_hot:
			# Only explosive materials with ELECTRIC_ACTIVATED can be primed by electricity
			# We check for both charge (pulses) OR direct contact with Electric pixels (ID 9)
			var has_elec_contact = _count_neighbor_id(x, y, 9) > 0
			var can_elec_prime = (tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED) and (charge_array[idx] > 50 or has_elec_contact)
			
			# Fire/Heat ignition: Now ignores electricity pixels (ID 9) to respect the ELECTRIC_ACTIVATED requirement
			var can_fire_prime = false
			if not can_elec_prime:
				for ny in range(y - 1, y + 2):
					for nx in range(x - 1, x + 2):
						if nx == x and ny == y: continue
						var nid = _get_cell(nx, ny)
						if nid > 0 and nid != 9: # Ignore Electricity ID 9 here
							if (material_tags_raw[_get_tags_id(nid)] & SandboxMaterial.Tags.INCENDIARY):
								can_fire_prime = true; break
			
			var can_acid_prime = _has_tag_neighbor(x, y, SandboxMaterial.Tags.ACID)
			
			if can_fire_prime or can_elec_prime or can_acid_prime:
				var trigger_type = 0 # Default (Heat)
				if can_acid_prime: trigger_type = 64
				elif can_elec_prime: trigger_type = 128
				_prime_explosive(x, y, pure_id, trigger_type)

	# FIREWORKS IGNITION (Material 18)
	if pure_id == 18:
		# Check for electricity (charge_array is filled by C++)
		# Or occasionally check for heat to avoid lag from neighbor checks on large brushes
		if charge_array[idx] > 50 or (_get_lut_rand() < 0.1 and _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY)):
			_set_cell(x, y, 19)
			charge_array[idx] = int(_get_lut_rand_range(20, 70))
			_register_charge(idx)
			_play_action_sound("fuse_burning", 0.1)

	# (Redundant Metronome Pulse removed to consolidate logic)
	# --- MUSIC INTERACTIONS ---
	if (tags & SandboxMaterial.Tags.MUSIC):
		# Trigger only on neighbor heat (electricity check removed as it's handled in _process_electricity)
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY):
			var gx = idx % grid_width
			var gy = idx / grid_width
			# 2x2 DUPES FILTER: Only trigger for the "top-left" pixel of the 2x2 block
			if (gx % 2 == 0 and gy % 2 == 0):
				if pure_id == 600:
					_play_music_note(5, 0)
				else:
					var m_data = _get_music_data(pure_id)
					_play_music_note(m_data.inst, m_data.note, false, m_data.octave)

	if pure_id == 19: 
		charge_array[idx] -= 1
		if charge_array[idx] > 0: _register_charge(idx)
		charge_visual_buffer[idx] = clampi(charge_array[idx], 0, 255) # For shader
		if _frame_count % 4 == 0: _set_cell(x, y, 18)
		elif _frame_count % 4 == 2: _set_cell(x, y, 19)
		if charge_array[idx] <= 0: _launch_firework(x, y)

	# --- CRYOGENICS ---
	if pure_id == 60:
		if _has_tag_neighbor(x, y, SandboxMaterial.Tags.INCENDIARY):
			if _get_lut_rand() < 0.2: _set_cell(x, y, 2); return
		if _get_lut_rand() < 0.05:
			for ny in range(y - 1, y + 2):
				if ny < 0 or ny >= grid_height: continue
				for nx in range(x - 1, x + 2):
					if nx < 0 or nx >= grid_width: continue
					if nx == x and ny == y: continue
					if (cells[ny * grid_width + nx] & 0xFFFF) == 2:
						_set_cell(nx, ny, 60); return
						
	if pure_id == 70:
		for ny in range(y - 1, y + 2):
			if ny < 0 or ny >= grid_height: continue
			for nx in range(x - 1, x + 2):
				if nx < 0 or nx >= grid_width: continue
				if nx == x and ny == y: continue
				var n_idx = ny * grid_width + nx
				var n_pid = cells[n_idx] & 0xFFFF
				
				if n_pid == 11: 
					_set_cell(x, y, 17); _set_cell(nx, ny, 12); return
				elif n_pid == 3:
					_set_cell(x, y, 2) # Melt Ice -> Water
					_set_cell(nx, ny, 15) # Extinguish Fire -> Smoke
					return
				elif n_pid == 15 or n_pid == 17: # SMOKE/CLOUD (Warm Air)
					if _get_lut_rand() < 0.02: # Slow melting
						_set_cell(x, y, 2) # Melt Ice -> Water
						return
		
		# 2. Freeze adjacent Water (Slow growth)
		if _get_lut_rand() < 0.05:
			for ny in range(y - 1, y + 2):
				if ny < 0 or ny >= grid_height: continue
				for nx in range(x - 1, x + 2):
					if nx < 0 or nx >= grid_width: continue
					if nx == x and ny == y: continue
					if (cells[ny * grid_width + nx] & 0xFFFF) == 2: # WATER
						_set_cell(nx, ny, 70) # FREEZE!
						return

	# ELECTRIC SEEDING (Pure Static Electricity)
	if (tags & SandboxMaterial.Tags.ELECTRICITY):
		if not (tags & (SandboxMaterial.Tags.LIQUID | SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.VOLATILE)):
			if _get_lut_rand() < 0.7: _set_cell(x, y, 0)



	# --- BIOLOGICAL INTERACTIONS (PLANTS & SEEDS) ---
	if _get_lut_rand() < 0.02:
		match pure_id:
			21: # Grass
				# WIDE SEARCH: Grass now feels water from further away (20x10)
				if current_weather > 0 or _has_id_in_lookup(idx, 2, oval_lookup_20x10):
					if _get_lut_rand() < 0.3:
						var gx = x + (_get_lut_rand_range(0, 4) - 2)
						var gy = y + (_get_lut_rand_range(0, 4) - 2)
						if gx >= 0 and gx < grid_width and gy >= 0 and gy < dynamic_grid_height:
							var g_idx = gy * grid_width + gx
							var target_id = cells[g_idx] & 0xFFFF
							# ONLY grow into AIR (0) and if the target is next to FERTILE ground
							if target_id == 0:
								# Check if the pixel BELOW or around is fertile
								var can_grow = false
								for oy in range(-1, 2):
									for ox in range(-1, 2):
										var neighbor_id = _get_cell(gx + ox, gy + oy)
										if (material_tags_raw[_get_tags_id(neighbor_id)] & SandboxMaterial.Tags.FERTILE):
											can_grow = true; break
									if can_grow: break
								
								if can_grow and _get_lut_rand() < 0.7: # 70% Population Density
									if _count_neighbor_id_fast(g_idx, 21) < 4:
										_set_cell(gx, gy, 21)
			1, 6: # Fertile Soil
				if current_weather > 0 or _has_id_in_lookup(idx, 2, oval_lookup_16x8):
					_set_cell(x, y, 22 if pure_id == 1 else 23)
			22, 23: # Wet Soil
				if current_weather > 0 or _has_id_in_lookup(idx, 2, oval_lookup_20x10):
					if _get_lut_rand() < 0.05 and _has_tag_neighbor(x, y, SandboxMaterial.Tags.PLANT):
						if _count_neighbor_id_fast(idx, 21) < 4:
							_set_cell(x, y, 21)
					elif _get_lut_rand() < 0.15: # Sprout vines
						if y > 0 and (cells[idx - grid_width] & 0xFFFF) == 0:
							# DENSITY FIX: Only sprout vines if no other vines are nearby (Separation)
							if _count_neighbor_id_radius(x, y, 24, 2) < 2:
								_set_cell(x, y-1, 24)
								if _get_lut_rand() < 0.5:
									charge_array[idx - grid_width] = int(_get_lut_rand_range(1, 4)) # Flowers (1-3)
								else:
									charge_array[idx - grid_width] = int(_get_lut_rand_range(104, 108)) # Vines (4-8)
				else:
					if current_weather == 0 and _get_lut_rand() < 0.1:
						_set_cell(x, y, 1 if pure_id == 22 else 6)
			24: # Vines
				var h_left = charge_array[idx]
				if h_left > 0 and _get_lut_rand() < 0.3 and y > 0:
					if (cells[idx - grid_width] & 0xFFFF) == 0:
						# Keep vines single-column (Don't clump)
						if _count_neighbor_id_fast(idx - grid_width, 24) < 2:
							if h_left == 1:
								var flower_colors = [31, 32, 33, 34]
								var f_mat = flower_colors[int(_get_lut_rand_range(0, 4))]
								_set_cell(x, y-1, f_mat)
							elif h_left == 101:
								_set_cell(x, y-1, 24)
								# End of normal vine, charge becomes 0
							else:
								_set_cell(x, y-1, 24)
								charge_array[idx - grid_width] = h_left - 1
							charge_array[idx] = 0
		

	
	# 7. FRESH CEMENT HARDENING 
	if pure_id == 25:
		if charge_array[idx] == 0: charge_array[idx] = int(_get_lut_rand_range(60, 120)) 
		charge_array[idx] -= 1
		if charge_array[idx] <= 1: _set_cell(x, y, 26) 
		
func _setup_paint_ui():
	_set_panning_mode(false)
	var s = _get_ui_scale()
	var paint_btn = _create_vertical_category_btn("🎨", "paint")
	paint_btn.name = "PaintBtn"
	ui_elements["paint_btn"] = paint_btn
	paint_btn.add_theme_font_override("font", _get_safe_font())
	paint_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	paint_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_hbox.add_child(paint_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.2, 0.15, 1.0) # Dark yellow-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.6, 0.6, 0.3)
	paint_btn.add_theme_stylebox_override("normal", btn_style)
	paint_btn.add_theme_stylebox_override("hover", btn_style)
	paint_btn.add_theme_stylebox_override("pressed", btn_style)
	paint_btn.set_meta("base_style", btn_style)
	
	ui_root = get_parent().get_node("UI")
	paint_panel = PanelContainer.new()
	paint_panel.name = "PaintPanel"
	ui_root.add_child(paint_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.05, 0.95) # Near opaque dark yellow
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.6, 0.3)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	paint_panel.add_theme_stylebox_override("panel", panel_style)
	
	# COMPACT DYNAMIC POSITIONING
	var p_width = 540 * s
	var p_height = 680 * s
	
	# Limit height in landscape to avoid ad overlap
	if is_inside_tree() and get_viewport_rect().size.x > get_viewport_rect().size.y:
		p_height = 570 * s
		
	_align_panel_to_hud(paint_panel, p_width, p_height)
	paint_panel.visible = ui_root.get_meta("paint_v", false)
	
	paint_btn.pressed.connect(func():
		_toggle_category_panel(paint_panel)
		if is_instance_valid(paint_panel) and paint_panel.visible:
			var inner_vbox = paint_panel.find_child("PaintVBox", true, false)
			if inner_vbox:
				_show_menu_reminder("paint", inner_vbox, "TUTORIAL_STEP_6")
			selected_material = -1
			_update_material_highlights()
			_update_paint_recent_ui()
	)
	
	paint_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	paint_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	# SETUP SCROLL FOR PAINT PANEL (Prevention for small screens/landscape)
	var scroll = ScrollContainer.new()
	scroll.name = "PaintScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 25
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	paint_panel.add_child(scroll)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "PaintVBox"
	main_vbox.add_theme_constant_override("separation", 15 * s)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main_vbox)
	
	# Title
	var title = Label.new()
	title.text = tr("paint")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 34 * s)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	main_vbox.add_child(title)
	
	# Mode Buttons
	var mode_margin = MarginContainer.new()
	mode_margin.add_theme_constant_override("margin_left", 15 * s)
	mode_margin.add_theme_constant_override("margin_right", 15 * s)
	main_vbox.add_child(mode_margin)
	
	var mode_hbox = HBoxContainer.new()
	mode_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_hbox.add_theme_constant_override("separation", 20 * s)
	mode_margin.add_child(mode_hbox)
	
	var create_mode_btn = func(text_key: String, mode_idx: int):
		var btn = Button.new()
		btn.text = tr(text_key)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 50 * s)
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 22 * s)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
		
		var st_n = StyleBoxFlat.new()
		st_n.bg_color = Color(0.12, 0.12, 0.15, 0.8)
		st_n.border_width_left = 1; st_n.border_width_top = 1
		st_n.border_width_right = 1; st_n.border_width_bottom = 1
		st_n.border_color = Color(0.3, 0.3, 0.4)
		st_n.set_corner_radius_all(12 * s)
		btn.add_theme_stylebox_override("normal", st_n)
		
		var st_p = StyleBoxFlat.new()
		st_p.bg_color = Color(0.2, 0.5, 1.0) # Premium Blue
		st_p.set_corner_radius_all(12 * s)
		st_p.border_width_bottom = 4 * s
		st_p.border_color = Color(0.5, 0.8, 1.0) # Light blue accent
		btn.add_theme_stylebox_override("pressed", st_p)
		btn.add_theme_stylebox_override("hover", st_p) # Keep highlight on hover if active
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			paint_mode = mode_idx
			# Refresh highlights
			for b in mode_hbox.get_children():
				if b != btn: b.button_pressed = false
			btn.button_pressed = true
		)
		
		btn.button_pressed = (paint_mode == mode_idx)
		mode_hbox.add_child(btn)
		return btn
		
	create_mode_btn.call("paint_elements", 0)
	create_mode_btn.call("paint_background", 1)
	
	# Color Grid 6x4
	var color_grid = GridContainer.new()
	color_grid.columns = 6
	color_grid.add_theme_constant_override("h_separation", 10 * s)
	color_grid.add_theme_constant_override("v_separation", 10 * s)
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
		st.set_corner_radius_all(10 * s)
		# NO BORDERS AS REQUESTED
		btn.add_theme_stylebox_override("normal", st)
		btn.add_theme_stylebox_override("hover", st)
		btn.add_theme_stylebox_override("pressed", st)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			selected_paint_color = c
			_update_paint_slider_grabber()
			_add_recent_paint_color(c)
		)
		color_grid.add_child(btn)
	
	# Custom Color Picker
	var custom_hbox = HBoxContainer.new()
	custom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(custom_hbox)
	
	var custom_cp = ColorPickerButton.new()
	custom_cp.text = "Color Personalizado"
	custom_cp.custom_minimum_size = Vector2(300 * s, 50 * s)
	custom_cp.add_theme_font_override("font", _get_safe_font())
	custom_cp.add_theme_font_size_override("font_size", 20 * s)
	custom_cp.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	custom_cp.color_changed.connect(func(c):
		selected_paint_color = c
		_update_paint_slider_grabber()
	)
	custom_cp.popup_closed.connect(func():
		_add_recent_paint_color(custom_cp.color)
	)
	custom_hbox.add_child(custom_cp)
	
	# Recent Colors
	var recent_hbox = HBoxContainer.new()
	recent_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	recent_hbox.add_theme_constant_override("separation", 15 * s)
	main_vbox.add_child(recent_hbox)
	ui_elements["paint_recent_colors"] = recent_hbox
	_update_paint_recent_ui()
	
	# Brush Slider
	var slider_vbox = VBoxContainer.new()
	slider_vbox.add_theme_constant_override("separation", 5 * s)
	main_vbox.add_child(slider_vbox)
	
	var slider_label = Label.new()
	slider_label.text = tr("brush")
	slider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slider_label.add_theme_font_override("font", _get_safe_font())
	slider_label.add_theme_font_size_override("font_size", 20 * s)
	slider_vbox.add_child(slider_label)
	
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 5
	slider.step = 1
	slider.value = paint_brush_radius_idx
	slider.custom_minimum_size = Vector2(400 * s, 40 * s)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Stylized Slider
	var slider_style = StyleBoxFlat.new()
	slider_style.bg_color = Color(0.3, 0.3, 0.3)
	slider_style.content_margin_top = 8 * s
	slider_style.content_margin_bottom = 8 * s
	slider_style.set_corner_radius_all(8 * s)
	slider.add_theme_stylebox_override("slider", slider_style)
	
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = selected_paint_color
	grabber_style.border_width_left = 2; grabber_style.border_width_top = 2
	grabber_style.border_width_right = 2; grabber_style.border_width_bottom = 2
	grabber_style.border_color = Color.BLACK
	grabber_style.set_corner_radius_all(15 * s)
	grabber_style.expand_margin_left = 10 * s; grabber_style.expand_margin_right = 10 * s
	grabber_style.expand_margin_top = 10 * s; grabber_style.expand_margin_bottom = 10 * s
	
	ui_elements["paint_grabber_style"] = grabber_style
	slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	
	slider.value_changed.connect(func(v):
		_play_action_sound("ui_click")
		paint_brush_radius_idx = int(v)
		var _sizes = [1, 3, 5, 10, 15, 25]
		slider_label.text = tr("brush") + ": " + str(_sizes[paint_brush_radius_idx])
		_save_tool_settings()
	)
	slider_vbox.add_child(slider)
	
	var sizes = [1, 3, 5, 10, 15, 25]
	slider_label.text = tr("brush") + ": " + str(sizes[paint_brush_radius_idx])

func _add_recent_paint_color(c: Color):
	if recent_paint_colors.has(c):
		recent_paint_colors.erase(c)
	recent_paint_colors.insert(0, c)
	if recent_paint_colors.size() > 6:
		recent_paint_colors.pop_back()
	_update_paint_recent_ui()

func _update_paint_recent_ui():
	var s = _get_ui_scale()
	var hbox = ui_elements.get("paint_recent_colors")
	if not is_instance_valid(hbox): return
	
	for child in hbox.get_children():
		child.queue_free()
		
	# Show 5 colors + 1 Eraser
	for i in range(6):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(60 * s, 60 * s)
		var st = StyleBoxFlat.new()
		st.set_corner_radius_all(30 * s)
		
		if i < 5:
			var c = recent_paint_colors[i]
			st.bg_color = c
			if c.to_html() == selected_paint_color.to_html() and selected_paint_color.a > 0:
				st.border_width_left = 8 * s; st.border_width_top = 8 * s
				st.border_width_right = 8 * s; st.border_width_bottom = 8 * s
				st.border_color = Color(0.2, 0.6, 1.0)
			
			btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_paint_color = c
				_update_paint_slider_grabber()
				_update_paint_recent_ui()
			)
		else: # THE ERASER 🧼
			btn.text = "🧼"
			btn.add_theme_font_size_override("font_size", 30 * s)
			st.bg_color = Color(0.1, 0.1, 0.12)
			if selected_paint_color.a == 0:
				st.border_width_left = 8 * s; st.border_width_top = 8 * s
				st.border_width_right = 8 * s; st.border_width_bottom = 8 * s
				st.border_color = Color(0.2, 0.6, 1.0)
				
			btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_paint_color = Color(0, 0, 0, 0) # Transparent = Erase
				_update_paint_slider_grabber()
				_update_paint_recent_ui()
			)
			
		btn.add_theme_stylebox_override("normal", st)
		btn.add_theme_stylebox_override("hover", st)
		btn.add_theme_stylebox_override("pressed", st)
		hbox.add_child(btn)

func _update_paint_slider_grabber():
	var st = ui_elements.get("paint_grabber_style")
	if st is StyleBoxFlat:
		st.bg_color = selected_paint_color
	# Refresh recent UI to update borders if needed
	_update_paint_recent_ui()

func _setup_npc_panel_node():
	# If it exists but was lost during a UI refresh, we need to ensure it's in the tree
	ui_root = get_parent().get_node("UI")
	
	npc_panel = PanelContainer.new()
	npc_panel.name = "NPCPanel"
	ui_root.add_child(npc_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.15, 0.1, 0.95) # Near opaque dark green-grey
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.5, 0.4)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	npc_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Compact dynamic positioning (Middle menu)
	var s = _get_ui_scale()
	_align_panel_to_hud(npc_panel, 530 * s, 350 * s)
	
	# RESTORE STATE
	npc_panel.visible = ui_root.get_meta("npc_v", false)
	
	# SETUP INTERNAL SCROLL (REPLACEMENT FOR DIRECT VBOX)
	for child in npc_panel.get_children(): 
		if is_instance_valid(child): child.free()
		
	var scroll = ScrollContainer.new()
	scroll.name = "NPCScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	npc_panel.add_child(main_vbox)
	
	var title = Label.new()
	title.text = tr("npc")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 34 * s)
	ui_elements["npc_panel_title"] = title
	main_vbox.add_child(title)
	
	main_vbox.add_child(scroll)
	
	var v_box = VBoxContainer.new()
	v_box.name = "NPCVBox"
	v_box.add_theme_constant_override("separation", 10 * s)
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v_box)
	
	npc_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	npc_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)

func _setup_npc_control_gui():
	var s = 1.25 # FIXED SCALE: Unified size for movement/action pads (Increased for mobile)
	ui_root = get_parent().get_node("UI")
	main_controls = ui_root.get_node("Controls")
	
	if is_instance_valid(npc_control_gui):
		# Avoid duplicate connections or nodes
		npc_control_gui.get_parent().remove_child(npc_control_gui)
		npc_control_gui.queue_free()
		
	npc_control_gui = Control.new()
	npc_control_gui.name = "NPCControlGUI"
	npc_control_gui.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	npc_control_gui.offset_top = -cached_hud_height
	npc_control_gui.mouse_filter = Control.MOUSE_FILTER_PASS 
	
	# Visibility based on Control State + Menu Toggle
	var in_control = is_instance_valid(controlled_npc)
	npc_control_gui.visible = in_control and not is_npc_mode_menu_open
	if is_instance_valid(main_controls):
		main_controls.visible = not in_control or is_npc_mode_menu_open
		
	ui_root.add_child(npc_control_gui)
	
	# Block interaction with game world below UI
	npc_control_gui.mouse_entered.connect(func(): is_mouse_over_ui = true)
	npc_control_gui.mouse_exited.connect(func(): is_mouse_over_ui = false)
	
	# Translucent background for the bar
	var bg = Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.6)
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP # IMPORTANT: Block clicks
	npc_control_gui.add_child(bg)
	
	# Common Auto-Closer for any arcade control touch
	var arcade_closer = func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and is_npc_mode_menu_open:
			_toggle_npc_mode_menu(false)
	
	bg.gui_input.connect(arcade_closer)
	
	# Left: Virtual PAD (Arcade Style - Circular)
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
	npc_control_gui.set_meta("is_pad_active", false) # Initial state
	npc_control_gui.add_child(pad)
	
	# Visual Cross inside PAD (Thicker)
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

	# Center buttons (Vertically stacked)
	# 1. MENU Button (Toggle HUD)
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
	menu_btn.add_theme_font_size_override("font_size", 22 * s)
	menu_btn.pressed.connect(func():
		_toggle_npc_mode_menu(!is_npc_mode_menu_open)
	)
	npc_control_gui.add_child(menu_btn)
	ui_elements["arcade_menu_btn"] = menu_btn
	
	# 1b. EXTERNAL LABELS (Below the Menu Button)
	var arcade_labels = HBoxContainer.new()
	arcade_labels.name = "ArcadeLabels"
	arcade_labels.custom_minimum_size = Vector2(300 * s, 40 * s)
	arcade_labels.anchor_left = 0.5; arcade_labels.anchor_right = 0.5; arcade_labels.anchor_top = 0.5; arcade_labels.anchor_bottom = 0.5
	arcade_labels.offset_left = -150 * s; arcade_labels.offset_right = 150 * s
	arcade_labels.offset_top = -60 * s; arcade_labels.offset_bottom = 12 * s # Positioned starting at MenuBtn bottom
	arcade_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arcade_labels.add_theme_constant_override("separation", 0)
	npc_control_gui.add_child(arcade_labels)

	# 2. EXIT Button (Circle, shifted down)
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
	exit_btn.add_theme_font_size_override("font_size", 34 * s)
	exit_btn.add_theme_constant_override("outline_size", 6 * s)
	exit_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_btn.pressed.connect(func():
		_stop_controlling_npc()
	)
	npc_control_gui.add_child(exit_btn)

	# Right: Action Button
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
	action_style.border_color = Color(0.04, 0.15, 0.4) # Much darker blue border
	action_btn.add_theme_stylebox_override("normal", action_style)
	action_btn.add_theme_font_override("font", _get_safe_font())
	action_btn.add_theme_font_size_override("font_size", 32 * s)
	action_btn.add_theme_constant_override("outline_size", 7 * s)
	action_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	action_btn.gui_input.connect(arcade_closer)
	action_btn.pressed.connect(func():
		_trigger_controlled_npc_action()
	)
	npc_control_gui.add_child(action_btn)
	ui_elements["arcade_action_btn"] = action_btn

func _stop_controlling_npc(keep_menus_open: bool = false):
	_play_action_sound("ui_click")
	controlled_npc = null
	is_selecting_npc_to_control = false
	is_npc_mode_menu_open = false
	
	if is_instance_valid(npc_control_gui):
		# Just hide the pad, the HUD itself might transition back
		npc_control_gui.visible = false
	
	ui_root = get_parent().get_node("UI")
	main_controls = ui_root.get_node("Controls")
	if is_instance_valid(main_controls):
		main_controls.visible = true
		main_controls.offset_top = -cached_hud_height
		main_controls.offset_bottom = 0
	
	if not keep_menus_open:
		# Close all floating menus
		if is_instance_valid(tools_panel): tools_panel.visible = false
		if is_instance_valid(disaster_panel): disaster_panel.visible = false
		if is_instance_valid(npc_panel): npc_panel.visible = false
	
	# Always reset mouse over ui state when stopping control to avoid stuck pointer logic
	is_mouse_over_ui = false 
	_update_menu_highlights() 
	_update_arcade_dynamic_button()

func _toggle_npc_mode_menu(p_show: bool):
	ui_root = get_parent().get_node("UI")
	main_controls = ui_root.get_node("Controls")
	if not is_instance_valid(main_controls) or not is_instance_valid(ui_root): return
	_play_action_sound("ui_click")
	is_npc_mode_menu_open = p_show
	
	# SWAP VISIBILITY: Building Menu vs Arcade HUD
	main_controls.visible = p_show
	if is_instance_valid(npc_control_gui):
		npc_control_gui.visible = !p_show
	
	if !p_show:
		# Close floating sub-panels
		if is_instance_valid(tools_panel): tools_panel.visible = false
		if is_instance_valid(disaster_panel): disaster_panel.visible = false
		if is_instance_valid(npc_panel): npc_panel.visible = false
		
		# PROTECTOR
		touch_started_on_ui = true 
		
		# Remove Full-screen protector
		var blocker = ui_root.get_node_or_null("ArcadeMenuBlocker")
		if blocker: blocker.queue_free()
	else:
		# Create Full-screen protector (Block all workspace clicks)
		var blocker = ui_root.get_node_or_null("ArcadeMenuBlocker")
		if not blocker:
			blocker = Control.new()
			blocker.name = "ArcadeMenuBlocker"
			blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			blocker.mouse_filter = Control.MOUSE_FILTER_STOP
			ui_root.add_child(blocker)
			# Ensure it's behind the panels but above the world
			ui_root.move_child(blocker, 0)
			blocker.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					_toggle_npc_mode_menu(false) # Close if touching outside
			)

func _handle_controlled_npc_input(delta):
	if not controlled_npc or not is_instance_valid(npc_control_gui) or not npc_control_gui.visible: return
	
	# Detect if dead
	if controlled_npc.hp <= 0:
		_stop_controlling_npc()
		return
	
	var s = _get_ui_scale()
	var pad = npc_control_gui.get_meta("pad_node")
	var action_btn = npc_control_gui.get_meta("action_btn")
	
	# Detect ground state
	var is_on_ground = !_can_npc_fit(controlled_npc.pos.x, controlled_npc.pos.y + 1, controlled_npc)
	
	# --- MOVEMENT (PAD) ---
	var move_dir = 0
	var want_jump = false
	var want_down = false
	var pad_active = npc_control_gui.get_meta("is_pad_active") if npc_control_gui.has_meta("is_pad_active") else false
	
	if pad_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var m_pos = get_viewport().get_mouse_position()
		if is_instance_valid(pad):
			var pad_center = pad.get_global_rect().get_center()
			# Horizontal
			if m_pos.x < pad_center.x - (25 * s): move_dir = -1
			elif m_pos.x > pad_center.x + (25 * s): move_dir = 1
			# Vertical
			if m_pos.y < pad_center.y - (40 * s): want_jump = true
			elif m_pos.y > pad_center.y + (40 * s): want_down = true
	elif not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		npc_control_gui.set_meta("is_pad_active", false) # Safety: ensure release reset
	
	# Apply physics movement (Inertia)
	var target_vel = float(move_dir) * 2.1 # Reduced speed to half
	var accel = 0.5 if is_on_ground else 0.15 # Air control is lower
	controlled_npc.vx = lerp(controlled_npc.vx, target_vel, accel)
	
	if move_dir != 0:
		controlled_npc.dir = move_dir
		controlled_npc["last_dir"] = move_dir
		
		# --- MINER SPECIAL TUNNELING ---
		if controlled_npc.type == "miner":
			var tx = controlled_npc.pos.x + move_dir
			var blocked = !_can_npc_fit(tx, controlled_npc.pos.y, controlled_npc)
			
			if want_down or blocked:
				# Use a timer to limit dig speed
				var dig_timer = controlled_npc.get("manual_dig_timer", 0.0)
				dig_timer += delta
				if dig_timer >= 0.14:
					dig_timer = 0.0
					_miner_dig(controlled_npc, want_down)
					
					# Smoothly advance into the tunnel
					var next_x = controlled_npc.pos.x + move_dir
					var next_y = controlled_npc.pos.y + (1 if want_down else 0)
					if _can_npc_fit(next_x, next_y, controlled_npc):
						# MANDATORY CLEANUP: Pre-erase old position at 60Hz before snap
						_draw_npc_pixels(controlled_npc, 0)
						controlled_npc.pos = Vector2i(next_x, next_y)
						controlled_npc.vx = 0.0 
						controlled_npc.vy = 0.0
				controlled_npc["manual_dig_timer"] = dig_timer
	else:
		controlled_npc.dir = 0 # No autonomous movement
	
	# --- JUMP ---
	if want_jump and is_on_ground:
		controlled_npc.vy = -5.5 # Reduced jump height (approx half of previous)
		_play_action_sound("ui_click") # Subtle feedback
	
	# --- ACTION ---
	if is_instance_valid(action_btn) and action_btn.is_pressed() and controlled_npc.attack_cooldown <= 0:
		_trigger_controlled_npc_action()

func _trigger_controlled_npc_action():
	if not controlled_npc: return
	
	match controlled_npc.type:
		"warrior":
			# Find closest enemy to attack
			var target = _find_closest_enemy(controlled_npc, 30.0)
			if target:
				_attack_npc(controlled_npc, target)
				controlled_npc.attack_cooldown = 0.6
			else:
				# Swing at air
				_play_action_sound("warrior_attack")
				controlled_npc.attack_cooldown = 0.4
		"zombie":
			var target = _find_closest_enemy(controlled_npc, 30.0)
			if target:
				_attack_npc(controlled_npc, target)
				controlled_npc.attack_cooldown = 0.8
			else:
				var p_scale = 0.65 + float((controlled_npc.id * 23) % 40) / 40.0 * 0.40
				_play_action_sound("zombie_attack", 0.08, 0.0, p_scale)
				controlled_npc.attack_cooldown = 0.5
		"zombie_tank":
			var target = _find_closest_enemy(controlled_npc, 30.0)
			if target and controlled_npc.pos.distance_to(target.pos) < 20.0:
				_attack_npc(controlled_npc, target)
				controlled_npc.attack_cooldown = 1.0
			else:
				var face_dir = controlled_npc.get("last_dir", 1)
				var found_x = -1; var found_y = -1; var found_mat = 2
				for dy in range(-4, 7):
					for dx in range(-5, 6):
						var tx = controlled_npc.pos.x + dx; var ty = controlled_npc.pos.y + dy
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							var tid = _get_cell(tx, ty)
							if tid > 0 and tid != 1 and not (material_tags_raw[_get_tags_id(tid)] & SandboxMaterial.Tags.NPC):
								found_x = tx; found_y = ty; found_mat = tid; break
					if found_x != -1: break
					
				if found_x != -1:
					_set_cell(found_x, found_y, 0)
					for _s in range(5):
						_add_spark(float(found_x), float(found_y), _get_lut_rand_range(-30, 30), _get_lut_rand_range(-50, -10), mat_colors_1[found_mat] if found_mat < mat_colors_1.size() else Color.GRAY, 0.4)
						
				var aim_target = _find_controlled_aim_target(controlled_npc, face_dir, 150.0)
				var vx = face_dir * 120.0
				var vy = -80.0
				if aim_target:
					var target_x = float(aim_target.pos.x)
					var target_y = float(aim_target.pos.y)
					var dir = 1 if (target_x - controlled_npc.pos.x) > 0 else -1
					controlled_npc["last_dir"] = dir
					controlled_npc.dir = dir
					face_dir = dir
					target_x += _get_lut_rand_range(-10.0, 10.0)
					target_y += _get_lut_rand_range(-6.0, 6.0)
					var dist_x = abs(target_x - controlled_npc.pos.x)
					if dist_x < 2.0: dist_x = 2.0
					var time_to_target = dist_x / 120.0
					time_to_target = clamp(time_to_target, 0.4, 2.5)
					vx = dir * dist_x / time_to_target
					vy = (target_y - controlled_npc.pos.y) / time_to_target - (0.5 * 200.0 * time_to_target)
				
				active_projectiles.append({
					"pos": Vector2(controlled_npc.pos.x + face_dir * 3, controlled_npc.pos.y + 1),
					"vel": Vector2(vx, vy),
					"team": controlled_npc.team,
					"type": "thrown_rock",
					"life": 3.0,
					"block_material": found_mat,
					"atk_dmg": 1.5
				})
				
				var p_scale = 0.65 + float((controlled_npc.id * 23) % 40) / 40.0 * 0.40
				_play_action_sound("zombie_tank_throw", 0.08, 0.0, p_scale)
				_set_npc_emoji(controlled_npc, "🪨", 1.2)
				controlled_npc.attack_cooldown = 2.0
		"archer":
			# Shoot arrow in current face direction
			var face_dir = controlled_npc.get("last_dir", 1)
			var target = _find_controlled_aim_target(controlled_npc, face_dir, 160.0)
			if target:
				var target_dir = 1 if (target.pos.x - controlled_npc.pos.x) > 0 else -1
				controlled_npc["last_dir"] = target_dir
				controlled_npc.dir = target_dir
				_shoot_arrow(controlled_npc, target)
			else:
				var dummy_target = {"pos": Vector2i(controlled_npc.pos.x + face_dir * 100, controlled_npc.pos.y)}
				_shoot_arrow(controlled_npc, dummy_target)
			controlled_npc.attack_cooldown = 1.0
		"medic":
			# Simple AOE heal
			var nearby = _get_nearby_npcs(controlled_npc.pos.x, controlled_npc.pos.y, 60.0)
			var healed_somebody = false
			var has_z = _has_active_zombies()
			for other in nearby:
				if _is_ally(controlled_npc, other, has_z) and other != controlled_npc and other.hp > 0:
					var mhp = other.get("max_hp", 100.0)
					if other.hp < mhp:
						other.hp = min(other.hp + controlled_npc.get("heal_power", 25.0), mhp)
						healed_somebody = true
						_set_npc_emoji(other, "😊", 1.0)
						for _f in range(4): _add_spark(float(other.pos.x), float(other.pos.y-2), 0.0, -20.0, Color.GREEN, 0.5)
			
			if healed_somebody:
				_play_action_sound("medic_heal")
				_set_npc_emoji(controlled_npc, "💚", 1.0)
				controlled_npc.attack_cooldown = 0.8
		"mage":
			# Shoot fireball in current face direction
			var face_dir = controlled_npc.get("last_dir", 1)
			var target = _find_controlled_aim_target(controlled_npc, face_dir, 150.0)
			if target:
				var target_dir = 1 if (target.pos.x - controlled_npc.pos.x) > 0 else -1
				controlled_npc["last_dir"] = target_dir
				controlled_npc.dir = target_dir
				_shoot_fireball(controlled_npc, target)
			else:
				var dummy_target = {"pos": Vector2i(controlled_npc.pos.x + face_dir * 90, controlled_npc.pos.y)}
				_shoot_fireball(controlled_npc, dummy_target)
			controlled_npc.attack_cooldown = 1.5
		"miner":
			# Place TNT in front
			var face_dir = controlled_npc.get("last_dir", 1)
			var tx = controlled_npc.pos.x + (face_dir * 3)
			var ty = controlled_npc.pos.y + 2
			# Boundary check
			if tx >= 1 and tx < grid_width - 1 and ty >= 1 and ty < dynamic_grid_height - 1:
				_set_cell(tx, ty, 5) # 5 = TNT
				_set_cell(tx+1, ty, 5)
				_set_cell(tx, ty+1, 5)
				_set_cell(tx+1, ty+1, 5)
				_play_action_sound("npc_place")
				controlled_npc.attack_cooldown = 1.5

func _setup_npc_ui():
	_set_panning_mode(false)
	var s = _get_ui_scale()
	var npc_btn = _create_vertical_category_btn("👥", "npc")
	npc_btn.name = "NPCBtn"
	ui_elements["npc_btn"] = npc_btn
	npc_btn.add_theme_font_override("font", _get_safe_font())
	npc_btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
	npc_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_hbox.add_child(npc_btn)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.25, 0.2, 1.0) # SOLID dark green-grey
	btn_style.border_width_left = 1; btn_style.border_width_top = 1
	btn_style.border_width_right = 1; btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.4, 0.5, 0.4)
	btn_style.corner_radius_top_left = 0; btn_style.corner_radius_top_right = 0
	btn_style.corner_radius_bottom_left = 0; btn_style.corner_radius_bottom_right = 0
	npc_btn.add_theme_stylebox_override("normal", btn_style)
	npc_btn.add_theme_stylebox_override("hover", btn_style)
	npc_btn.add_theme_stylebox_override("pressed", btn_style)
	npc_btn.set_meta("base_style", btn_style)
	
	npc_btn.pressed.connect(func():
		_toggle_category_panel(npc_panel)
		if is_instance_valid(npc_panel) and npc_panel.visible:
			_show_menu_reminder("npc", npc_panel.get_child(0), "TUTORIAL_STEP_5")
	)
	
	# Clear and Fill
	if is_instance_valid(npc_panel):
		var scroll = npc_panel.find_child("NPCScroll", true, false)
		var v_box = scroll.find_child("NPCVBox", true, false) if scroll else null
		
		if is_instance_valid(v_box):
			for child in v_box.get_children(): 
				if is_instance_valid(child): child.queue_free()
		
		# ----------------------------------------------------
		# NPC CONTROL SECTION (NEW PHILOSOPHY)
		var control_lbl = Label.new()
		control_lbl.text = tr("npc_controller_title") + ": "
		control_lbl.add_theme_font_size_override("font_size", 22 * s)
		control_lbl.add_theme_font_override("font", _get_safe_font())
		v_box.add_child(control_lbl)
		ui_elements["control_npc_lbl"] = control_lbl
		
		var control_flow = HFlowContainer.new()
		control_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(control_flow)
		
		ui_root = get_parent().get_node("UI")
		
		# PREMIUM BASE STYLE FOR NPC
		var n_base = StyleBoxFlat.new()
		n_base.bg_color = Color(0.1, 0.15, 0.1, 0.8) # Subtle green-grey
		n_base.border_width_left = 1; n_base.border_width_top = 1
		n_base.border_width_right = 1; n_base.border_width_bottom = 1
		n_base.border_color = Color(0.3, 0.4, 0.3)
		n_base.set_corner_radius_all(10 * s)
		
		# Button: ACTIVE
		var active_btn = Button.new()
		active_btn.text = tr("active")
		active_btn.custom_minimum_size = Vector2(100 * s, 45 * s)
		active_btn.add_theme_font_override("font", _get_safe_font())
		active_btn.add_theme_font_size_override("font_size", 20 * s)
		active_btn.add_theme_stylebox_override("normal", n_base)
		active_btn.set_meta("base_style", n_base)
		active_btn.pressed.connect(func():
			_play_action_sound("ui_click")
			if not is_instance_valid(controlled_npc):
				is_selecting_npc_to_control = true
				selected_material = 0 
				is_paint_tool_active = false
				_update_material_highlights()
			_update_menu_highlights()
			_on_arcade_selection_made(true)
		)
		control_flow.add_child(active_btn)
		ui_elements["control_active_btn"] = active_btn
		
		# Button: DISABLED
		var disabled_btn = Button.new()
		disabled_btn.text = tr("inactive")
		disabled_btn.custom_minimum_size = Vector2(120 * s, 45 * s)
		disabled_btn.add_theme_font_override("font", _get_safe_font())
		disabled_btn.add_theme_font_size_override("font_size", 20 * s)
		disabled_btn.add_theme_stylebox_override("normal", n_base)
		disabled_btn.set_meta("base_style", n_base)
		disabled_btn.pressed.connect(func():
			_play_action_sound("ui_click")
			_stop_controlling_npc(true) # Keep NPC Panel open when disabling controller
		)
		control_flow.add_child(disabled_btn)
		ui_elements["control_disabled_btn"] = disabled_btn
		
		# ----------------------------------------------------

		# NPC Selection (NOW RESPONSIVE)
		var npc_lbl = Label.new()
		npc_lbl.text = tr("npc") + ": "
		npc_lbl.add_theme_font_size_override("font_size", 22 * s)
		v_box.add_child(npc_lbl)
		
		var npc_flow = HFlowContainer.new()
		npc_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_box.add_child(npc_flow)
		
		var create_npc_btn = func(key: String, id: int, target_flow = npc_flow):
			var btn = Button.new()
			btn.text = tr(key)
			btn.custom_minimum_size = Vector2(100 * s, 45 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			btn.add_theme_font_size_override("font_size", 20 * s)
			btn.mouse_filter = Control.MOUSE_FILTER_PASS
			btn.add_theme_stylebox_override("normal", n_base)
			btn.set_meta("base_style", n_base)
			btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_material = id # Master Warrior Material
				is_paint_tool_active = false
				is_mechanism_mode_active = false
				if not is_instance_valid(controlled_npc):
					is_selecting_npc_to_control = false
				_update_material_highlights()
				_update_menu_highlights()
				_on_arcade_selection_made(false)
			)
			ui_elements[key + "_btn"] = btn
			target_flow.add_child(btn)
		
		create_npc_btn.call("warrior", 1000)
		create_npc_btn.call("archer", 1010)
		create_npc_btn.call("miner", 1020)
		create_npc_btn.call("medic", 1040)
		create_npc_btn.call("mage", 1070)
		
		# Teams Row (NOW RESPONSIVE)
		var team_lbl = Label.new()
		team_lbl.text = tr("team") + ": "
		team_lbl.add_theme_font_size_override("font_size", 22 * s)
		ui_elements["team_lbl"] = team_lbl
		v_box.add_child(team_lbl)
		
		var team_flow = HFlowContainer.new()
		team_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui_elements["team_flow"] = team_flow
		v_box.add_child(team_flow)
		
		var team_keys = ["team_red", "team_blue", "team_yellow", "team_green"]
		for i in range(4):
			var t_btn = Button.new()
			t_btn.text = tr(team_keys[i])
			t_btn.custom_minimum_size = Vector2(80 * s, 45 * s)
			t_btn.add_theme_font_size_override("font_size", 20 * s)
			t_btn.add_theme_font_override("font", _get_safe_font())
			t_btn.mouse_filter = Control.MOUSE_FILTER_PASS
			t_btn.add_theme_stylebox_override("normal", n_base)
			t_btn.set_meta("base_style", n_base)
			var tidx = i
			t_btn.pressed.connect(func():
				_play_action_sound("ui_click")
				selected_team = tidx
				_update_menu_highlights()
				_on_arcade_selection_made(true)
			)
			ui_elements["team_btn_" + str(i)] = t_btn
			team_flow.add_child(t_btn)

		# Neutral / Factionless Row (NOW RESPONSIVE)
		var neutral_lbl = Label.new()
		neutral_lbl.text = tr("factionless") + ": "
		neutral_lbl.add_theme_font_size_override("font_size", 22 * s)
		ui_elements["neutral_lbl"] = neutral_lbl
		v_box.add_child(neutral_lbl)
		
		var neutral_flow = HFlowContainer.new()
		neutral_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ui_elements["neutral_flow"] = neutral_flow
		v_box.add_child(neutral_flow)
		
		create_npc_btn.call("zombie", 1050, neutral_flow)
		create_npc_btn.call("zombie_tank", 1060, neutral_flow)
		
		_add_ui_header(v_box, "coming_soon")
		
		var npc_flow_fut = HFlowContainer.new()
		npc_flow_fut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		npc_flow_fut.modulate = Color(0.6, 0.6, 0.6, 0.7)
		v_box.add_child(npc_flow_fut)
		
		var create_fut_npc = func(key: String):
			var btn = Button.new()
			btn.text = tr(key)
			btn.custom_minimum_size = Vector2(100.0 * s, 45.0 * s)
			btn.add_theme_font_override("font", _get_safe_font())
			btn.add_theme_font_size_override("font_size", 20.0 * s)
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			npc_flow_fut.add_child(btn)
			ui_elements[key + "_btn"] = btn # Support refresh
		
		create_fut_npc.call("summoner")
		create_fut_npc.call("bomber")
		create_fut_npc.call("kamikaze")
		create_fut_npc.call("builder")

func _place_npc(x, y):
	var origin_x = x - 1
	var origin_y = y - 4
	
	var start_x = origin_x
	var start_y = origin_y
	
	# AUTO-REPOSITION (Protección Exclusiva Anti-Clones)
	# Busca el primer hueco libre de OTROS NPCs, ignorando la arena/tierra/paredes para permitir ahogos manuales
	var found_spot = false
	for radius in range(0, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, 2): 
				if abs(dx) == radius or abs(dy) == radius or radius == 0:
					var test_x = origin_x + dx
					var test_y = origin_y + dy
					
					var nearby = _get_nearby_npcs(test_x, test_y, 10.0)
					var overlap = false
					for other in nearby:
						if test_x < other.pos.x + 2 and test_x + 2 > other.pos.x and test_y < other.pos.y + 5 and test_y + 5 > other.pos.y:
							overlap = true
							break
					
					if not overlap:
						start_x = test_x
						start_y = test_y
						found_spot = true
						break
			if found_spot: break
		if found_spot: break
		
	if not found_spot: return # Imposible encontrar hueco incluso a 15 pixeles, abortar spawn silenciosamente
	
	var n_type = "warrior"
	if selected_material == 1010 or selected_material == 1011: n_type = "archer"
	elif selected_material == 1020 or selected_material == 1021: n_type = "miner"
	elif selected_material == 1040 or selected_material == 1041: n_type = "medic"
	elif selected_material == 1050 or selected_material == 1051: n_type = "zombie"
	elif selected_material == 1060 or selected_material == 1061: n_type = "zombie_tank"
	elif selected_material == 1070 or selected_material == 1071: n_type = "mage"

	
	# Register in entity list
	var new_npc = {
		"pos": Vector2i(start_x, start_y),
		"team": -1 if (n_type == "zombie" or n_type == "zombie_tank") else selected_team,
		"dir": 1 if _get_lut_rand() > 0.5 else -1,
		"type": n_type,
		"hp": _get_lut_rand_range(280.0, 320.0) if n_type == "zombie_tank" else _get_lut_rand_range(85.0, 115.0), # Variación en resistencia base
		"attack_cooldown": 0.0,
		"hit_flash": 0,
		"hit_type": "none",
		"dig_timer": 0.0,
		"spawn_y": start_y,
		"mine_state": "ramp",
		"state_steps": 25,
		"fall_depth": 0,
		"last_dig_time": 0,
		"miss_counter": 0,
		"vx": 0.0,
		"vy": 0.0,
		
		# -- ESTADÍSTICAS RPG ÚNICAS POR SOLDADO --
		"max_hp": 0.0, # Se calibra debajo
		"atk_dmg": _get_lut_rand_range(0.8, 1.25), # +-20% Variación en daño
		"knockback_mult": _get_lut_rand_range(0.7, 1.3), # Unidades fuertes tiran más lejos
		"cowardice": _get_lut_rand_range(0.15, 0.45), # Probabilidad personal de huir
		"precision": _get_lut_rand_range(-0.6, 0.6), # Peor/Mejor puntería con arco
		"heal_power": _get_lut_rand_range(15.0, 35.0), # Variación en fuerza de las curas médicas
		"is_fire_variant": _get_lut_rand() < 0.05,
		
		# --- SISTEMA EMOCIONAL (Pintado directo) ---
		"emoji_timer": 0.0,
		"current_emoji": "",
		"idle_emote_timer": _get_lut_rand_range(2.0, 5.0),
		"has_spotted_enemy": false,
		"stuck_timer": 0.0, 
		"last_pos_x": start_x,
		"invul_timer": 0.0,
		"suffocation_timer": 0.0,
		"checked_rescue_map": {},
		"id": _npc_id_counter
	}
	_npc_id_counter += 1
	
	new_npc["max_hp"] = new_npc["hp"]
	active_npcs.append(new_npc)
	_draw_npc_pixels(new_npc)

func _spawn_explosion_npc(x, y, team = 0):
	# Final Full-Structure Sync to ensure 100% compatibility with _process_npcs
	if active_npcs.size() > 100: return null 
	
	var types = ["warrior", "archer", "miner", "medic", "bomber"]
	var n_type = types[randi() % types.size()]
	
	var new_npc = {
		"pos": Vector2i(x, y),
		"team": team,
		"dir": 1 if _get_lut_rand() > 0.5 else -1,
		"type": n_type,
		"hp": 100.0,
		"max_hp": 100.0,
		"atk_dmg": 1.0,
		"knockback_mult": 1.0,
		"precision": 0.0,
		"cowardice": 0.3,
		"heal_power": 25.0,
		"attack_cooldown": 0.0,
		"hit_flash": 0,
		"hit_type": "none",
		"dig_timer": 0.0,
		"spawn_y": y,
		"mine_state": "ramp",
		"state_steps": 25,
		"last_dig_time": 0,
		"vx": 0.0,
		"vy": 0.0,
		"emoji_timer": 0.0,
		"current_emoji": "",
		"idle_emote_timer": 2.0,
		"stuck_timer": 0.0,
		"last_pos_x": x,
		"fall_depth": 0,
		"miss_counter": 0,
		"is_fire_variant": false,
		"has_spotted_enemy": false,
		"invul_timer": 0.0,
		"suffocation_timer": 0.0,
		"checked_rescue_map": {},
		"id": _npc_id_counter
	}
	_npc_id_counter += 1
	active_npcs.append(new_npc)
	_draw_npc_pixels(new_npc)
	return new_npc


func _draw_npc_pixels(npc, override_mat = -1):
	if override_mat != 0 and (npc.get("pipe_inside_id", -1) != -1 or npc.get("is_in_pipe", false)):
		return
		
	var is_dead = npc.hp <= 0; var is_flashing = npc.hit_flash > 0
	var is_lying = npc.get("is_lying", false)
	
	if override_mat == 0:
		# CONTINUOUS ZONE CLEANUP: Wipe everything between the current physics pos AND the last render pos
		var last_x = int(npc.get("last_render_x", npc.pos.x))
		var last_y = int(npc.get("last_render_y", npc.pos.y))
		
		var was_lying = npc.get("last_render_lying", false)
		var is_tank = (npc.type == "zombie_tank")
		var is_mage = (npc.type == "mage")
		
		var pad_left = 7 if was_lying else (1 if is_tank else 1)
		var pad_right = 7 if was_lying else (3 if is_tank else 2)
		var pad_top = 1
		var pad_bottom = 7 if (is_tank or is_mage) else 6
		
		var min_x = min(npc.pos.x, last_x) - pad_left - 1
		var max_x = max(npc.pos.x, last_x) + pad_right + 1
		var min_y = min(npc.pos.y, last_y) - pad_top - 1
		var max_y = max(npc.pos.y, last_y) + pad_bottom + 1
		
		for cy in range(min_y, max_y + 1):
			for cx in range(min_x, max_x + 1):
				if cx >= 0 and cx < grid_width and cy >= 0 and cy < dynamic_grid_height:
					var tid = cells[cy * grid_width + cx] & 0xFFFF
					if tid > 0 and (material_tags_raw[_get_tags_id(tid)] & SandboxMaterial.Tags.NPC): 
						_set_cell(cx, cy, 0)
		return
		
	var sx = int(npc.pos.x); var sy = int(npc.pos.y)
	if is_flashing and not is_dead:
		sx += int(_get_lut_rand_range(-1.0, 1.9))
		sy += int(_get_lut_rand_range(-1.0, 1.9))
	elif is_dead:
		sy += 2; sx += 1 if (npc.dir > 0) else -1
		if (npc.hit_flash % 2 == 0): override_mat = 0
		
	# Store this exact render position and state for the next erasure pass
	npc["last_render_x"] = sx
	npc["last_render_y"] = sy
	npc["last_render_lying"] = is_lying
		
	# 1. Definir materiales por Clase (Dedicados para personalización)
	var m_head = 1001; var m_skin = 1003; var m_torso = 1002; var m_shoes = 1008
	var team_mat = 1004 + npc.team
	
	if npc.type == "archer":
		m_head = 1011; m_skin = 1013; m_torso = 1014; m_shoes = 1015
	elif npc.type == "miner":
		m_head = 1021; m_skin = 1022; m_torso = 1023; m_shoes = 1024
	elif npc.type == "medic":
		m_head = 1044; m_skin = 1042; m_torso = 1043; m_shoes = 1045
	elif npc.type == "zombie":
		m_head = 1051; m_skin = 1051; m_torso = 1052; m_shoes = 1054; team_mat = 1053
	elif npc.type == "zombie_tank":
		m_head = 1061; m_skin = 1061; m_torso = 1062; m_shoes = 1064; team_mat = 1063
	elif npc.type == "mage":
		m_head = 1071 # Mago Barba
		m_skin = 1072 # Mago Piel
		m_torso = 1070 # Mago Master
		m_shoes = 1008 # Standard shoes
		if npc.team == 0: team_mat = 1074
		elif npc.team == 1: team_mat = 1075
		elif npc.team == 2: team_mat = 1076
		elif npc.team == 3: team_mat = 1077
		else: team_mat = 1074

	
	# 2. Aplicar Overrides (Daño/Muerte)
	if override_mat != -1:
		m_head = override_mat; m_skin = override_mat; m_torso = override_mat; m_shoes = override_mat; team_mat = override_mat
	elif is_flashing:
		var f_mat = 1033; if is_dead: f_mat = 1034
		elif npc.hit_type == "acid": f_mat = 1030
		elif npc.hit_type == "fire": f_mat = 1031
		elif npc.hit_type == "explosive": f_mat = 1032
		elif npc.hit_type == "electric": f_mat = 1035
		m_head = f_mat; m_skin = f_mat; m_torso = f_mat; m_shoes = f_mat; team_mat = f_mat
		
	# 3. SET PIXELS (2x5 Grid or 5x2 Lying down)
	var face_dir = npc.get("dir", 1)
	if face_dir == 0: face_dir = npc.get("last_dir", 1)
	else: npc["last_dir"] = face_dir
		
	if is_lying:
		if npc.type == "zombie_tank":
			# --- LYING DOWN ZOMBIE TANK (6x3) ---
			var lx = sx; var ly = sy + 3
			if face_dir > 0:
				_set_cell(lx, ly, m_head); _set_cell(lx+1, ly, m_skin); _set_cell(lx+2, ly, team_mat); _set_cell(lx+3, ly, m_torso); _set_cell(lx+4, ly, team_mat); _set_cell(lx+5, ly, m_shoes)
				_set_cell(lx, ly+1, m_head); _set_cell(lx+1, ly+1, m_head); _set_cell(lx+2, ly+1, m_torso); _set_cell(lx+3, ly+1, team_mat); _set_cell(lx+4, ly+1, team_mat); _set_cell(lx+5, ly+1, m_shoes)
				_set_cell(lx, ly+2, m_head); _set_cell(lx+1, ly+2, m_skin); _set_cell(lx+2, ly+2, m_torso); _set_cell(lx+3, ly+2, m_torso); _set_cell(lx+4, ly+2, team_mat); _set_cell(lx+5, ly+2, m_shoes)
			else:
				_set_cell(lx, ly, m_shoes); _set_cell(lx+1, ly, team_mat); _set_cell(lx+2, ly, m_torso); _set_cell(lx+3, ly, team_mat); _set_cell(lx+4, ly, m_skin); _set_cell(lx+5, ly, m_head)
				_set_cell(lx, ly+1, m_shoes); _set_cell(lx+1, ly+1, team_mat); _set_cell(lx+2, ly+1, team_mat); _set_cell(lx+3, ly+1, m_torso); _set_cell(lx+4, ly+1, m_head); _set_cell(lx+5, ly+1, m_head)
				_set_cell(lx, ly+2, m_shoes); _set_cell(lx+1, ly+2, team_mat); _set_cell(lx+2, ly+2, m_torso); _set_cell(lx+3, ly+2, m_torso); _set_cell(lx+4, ly+2, m_skin); _set_cell(lx+5, ly+2, m_head)
		elif npc.type == "mage":
			# --- LYING DOWN WIZARD/MAGO (6x2) ---
			var lx = sx; var ly = sy + 4
			if face_dir > 0:
				_set_cell(lx, ly, team_mat); _set_cell(lx+1, ly, m_skin); _set_cell(lx+2, ly, team_mat); _set_cell(lx+3, ly, team_mat); _set_cell(lx+4, ly, team_mat); _set_cell(lx+5, ly, m_shoes)
				_set_cell(lx, ly+1, team_mat); _set_cell(lx+1, ly+1, m_head); _set_cell(lx+2, ly+1, m_head); _set_cell(lx+3, ly+1, m_head); _set_cell(lx+4, ly+1, m_head); _set_cell(lx+5, ly+1, m_shoes)
			else:
				# Mirror (Lying down facing left)
				_set_cell(lx, ly, m_shoes); _set_cell(lx+1, ly, team_mat); _set_cell(lx+2, ly, team_mat); _set_cell(lx+3, ly, team_mat); _set_cell(lx+4, ly, m_skin); _set_cell(lx+5, ly, team_mat)
				_set_cell(lx, ly+1, m_shoes); _set_cell(lx+1, ly+1, m_head); _set_cell(lx+2, ly+1, m_head); _set_cell(lx+3, ly+1, m_head); _set_cell(lx+4, ly+1, m_head); _set_cell(lx+5, ly+1, team_mat)
		else:
			# --- LYING DOWN (Horizontal 5x2 - Face Up) ---
			var lx = sx; var ly = sy + 3
			if face_dir > 0:
				# Fila Superior (Cara y pecho mirando arriba)
				_set_cell(lx, ly, m_head); _set_cell(lx+1, ly, m_skin)
				_set_cell(lx+2, ly, team_mat); _set_cell(lx+3, ly, m_torso)
				_set_cell(lx+4, ly, m_shoes)
				# Fila Inferior (Base del cuerpo)
				_set_cell(lx, ly+1, m_head); _set_cell(lx+1, ly+1, m_head)
				_set_cell(lx+2, ly+1, m_torso); _set_cell(lx+3, ly+1, team_mat)
				_set_cell(lx+4, ly+1, m_shoes)
			else:
				# Espejo
				_set_cell(lx, ly, m_shoes); _set_cell(lx, ly+1, m_shoes)
				_set_cell(lx-1, ly, team_mat); _set_cell(lx-2, ly, m_torso)
				_set_cell(lx-1, ly+1, m_torso); _set_cell(lx-2, ly+1, team_mat)
				_set_cell(lx-3, ly, m_skin); _set_cell(lx-4, ly, m_head)
				_set_cell(lx-3, ly+1, m_head); _set_cell(lx-4, ly+1, m_head)
	else:
		if npc.type == "zombie_tank":
			# --- STANDING ZOMBIE TANK (3x6) ---
			var px0 = sx if face_dir > 0 else sx + 2
			var px1 = sx + 1
			var px2 = sx + 2 if face_dir > 0 else sx
			
			# Fila 0 (Parte superior de la cabeza)
			_set_cell(px0, sy, m_head); _set_cell(px1, sy, m_head); _set_cell(px2, sy, m_head)
			# Fila 1 (Cara y nuca)
			_set_cell(px0, sy+1, m_head); _set_cell(px1, sy+1, m_skin); _set_cell(px2, sy+1, m_skin)
			# Fila 2 (Torso alto / Hombros)
			_set_cell(px0, sy+2, team_mat); _set_cell(px1, sy+2, m_torso); _set_cell(px2, sy+2, m_torso)
			# Fila 3 (Torso bajo)
			_set_cell(px0, sy+3, m_torso); _set_cell(px1, sy+3, team_mat); _set_cell(px2, sy+3, team_mat)
			# Fila 4 (Pantalones)
			_set_cell(px0, sy+4, team_mat); _set_cell(px1, sy+4, team_mat); _set_cell(px2, sy+4, team_mat)
			# Fila 5 (Pies descalzos)
			_set_cell(px0, sy+5, m_shoes); _set_cell(px1, sy+5, m_shoes); _set_cell(px2, sy+5, m_shoes)
		elif npc.type == "mage":
			# --- STANDING WIZARD/MAGO (2x6) ---
			var px0 = sx if face_dir > 0 else sx + 1 # Back
			var px1 = sx + 1 if face_dir > 0 else sx # Front
			
			# Row 0: Hat tip
			_set_cell(px0, sy, team_mat); _set_cell(px1, sy, team_mat)
			# Row 1: Head / Face
			_set_cell(px0, sy+1, m_head); _set_cell(px1, sy+1, m_skin)
			# Row 2: Tunic / Beard
			_set_cell(px0, sy+2, team_mat); _set_cell(px1, sy+2, m_head)
			# Row 3: Tunic / Beard
			_set_cell(px0, sy+3, team_mat); _set_cell(px1, sy+3, m_head)
			# Row 4: Tunic / Beard
			_set_cell(px0, sy+4, team_mat); _set_cell(px1, sy+4, m_head)
			# Row 5: Shoes
			_set_cell(px0, sy+5, m_shoes); _set_cell(px1, sy+5, m_shoes)
		else:
			# --- STANDING (Vertical 2x5) ---
			var px0 = sx if face_dir > 0 else sx + 1
			var px1 = sx + 1 if face_dir > 0 else sx
			_set_cell(px0, sy, m_head); _set_cell(px1, sy, m_head)
			_set_cell(px0, sy+1, m_head); _set_cell(px1, sy+1, m_skin)
			if npc.type == "medic" and override_mat == -1 and !is_flashing:
				_set_cell(px0, sy+2, 1041); _set_cell(px1, sy+2, 1041)
				_set_cell(px0, sy+3, team_mat); _set_cell(px1, sy+3, team_mat)
			elif npc.type == "archer" and override_mat == -1 and !is_flashing:
				_set_cell(px0, sy+2, team_mat); _set_cell(px1, sy+2, team_mat)
				_set_cell(px0, sy+3, team_mat); _set_cell(px1, sy+3, team_mat)
			else:
				_set_cell(px0, sy+2, m_torso); _set_cell(px1, sy+2, team_mat)
				_set_cell(px0, sy+3, team_mat); _set_cell(px1, sy+3, m_torso)
			_set_cell(px0, sy+4, m_shoes); _set_cell(px1, sy+4, m_shoes)

func _update_npc_spatial_hash():
	for cell in npc_spatial_grid:
		cell.clear()
	for npc in active_npcs:
		if npc.get("pipe_inside_id", -1) != -1 or npc.get("is_in_pipe", false): continue
		var cx = clampi(int(npc.pos.x / SPATIAL_CELL_SIZE), 0, spatial_grid_w - 1)
		var cy = clampi(int(npc.pos.y / SPATIAL_CELL_SIZE), 0, spatial_grid_h - 1)
		npc_spatial_grid[cy * spatial_grid_w + cx].append(npc)

func _get_nearby_npcs(px, py, radius) -> Array:
	var results = []
	if npc_spatial_grid.is_empty(): return results
	var inv_cell_size = 1.0 / float(SPATIAL_CELL_SIZE)
	var x_min = clampi(int((px - radius) * inv_cell_size), 0, spatial_grid_w - 1)
	var x_max = clampi(int((px + radius) * inv_cell_size), 0, spatial_grid_w - 1)
	var y_min = clampi(int((py - radius) * inv_cell_size), 0, spatial_grid_h - 1)
	var y_max = clampi(int((py + radius) * inv_cell_size), 0, spatial_grid_h - 1)
	for gy in range(y_min, y_max + 1):
		var row_offset = gy * spatial_grid_w
		for gx in range(x_min, x_max + 1):
			results.append_array(npc_spatial_grid[row_offset + gx])
	return results

func _process_npcs(delta):
	# --- VISUALES POR FRAME (Suavidad total y cero lag) ---
	# queue_redraw() se llama al final para renderizar los emojis
	
	# --- LÓGICA DE IA (20 veces por segundo para rendimiento) ---
	npc_update_timer += delta
	if npc_update_timer < 0.05: return 
	npc_update_timer = 0.0
	
	# CALCULAR DOMINANCIA DE EQUIPOS
	var t_counts = {}
	var total_alive = 0
	for npc in active_npcs:
		if npc.hp > 0:
			t_counts[npc.team] = t_counts.get(npc.team, 0) + 1
			total_alive += 1
			
	var win_team = -1
	var show_dom = false
	if t_counts.size() > 1 and total_alive > 0:
		for t in t_counts:
			if t_counts[t] >= total_alive * 0.7:
				win_team = t
		if win_team != -1:
			show_dom = true
			for t in t_counts:
				if t != win_team and t_counts[t] > 10: # Si ALGÚN equipo perdedor tiene > 10 NPCs, se anula
					show_dom = false; break
	
	_ai_tick_count += 1
	var dead_indices = []
	for i in range(active_npcs.size()):
		var npc = active_npcs[i]
		
		if npc.get("pipe_inside_id", -1) != -1 or npc.get("is_in_pipe", false):
			var invul = npc.get("invul_timer", 0.0)
			if invul > 0:
				npc["invul_timer"] = max(0.0, invul - 0.05)
			continue
			
		# Sanitize NaN or Inf states to prevent stuck/immortal ghost NPCs
		if is_nan(npc.get("hp", 0.0)) or is_nan(npc.pos.x) or is_nan(npc.pos.y):
			npc.hp = 0.0
			npc.pos.x = clamp(npc.pos.x, 0.0, float(grid_width - 2))
			npc.pos.y = clamp(npc.pos.y, 0.0, float(dynamic_grid_height - 6))
		if is_nan(npc.get("invul_timer", 0.0)):
			npc["invul_timer"] = 0.0
		if npc.get("hp", 0.0) > 99999.0:
			npc.hp = npc.get("max_hp", 100.0)
			
		# --- ANTI-STUCK ---
		_resolve_npc_overlap(npc)
		
		var profile = NPC_PROFILES.get(npc.type, {})
		
		# Decrement invulnerability protection timer
		var invul_val = npc.get("invul_timer", 0.0)
		if invul_val > 0:
			npc["invul_timer"] = max(0.0, invul_val - 0.05)
		
		# Procesar timers de emojis y visibilidad (Lógica de Ciclo Emocional Optimizado)
		var emotes = []
		if npc.hp <= 0: emotes = ["💀"]
		else:
			if npc.get("is_fleeing", false): emotes.append("😭")
			if npc.get("dance_timer", 0.0) > 0: emotes.append("🎵")
			
			var is_winning = show_dom and npc.team == win_team
			var is_losing = show_dom and npc.team != win_team
			
			if is_losing:
				emotes.append("😱")
			elif npc.get("has_spotted_enemy", false):
				emotes.append("😡")
				if is_winning: emotes.append("😎")
			
			if npc.get("mine_state", "") == "saboteur": emotes.append("⭐"); emotes.append("😄")
			
			if npc.get("is_lying", false):
				if npc.hp < (npc.max_hp * 0.3): emotes.append("🤕")
				else: emotes.append("😴")
			elif !npc.get("has_spotted_enemy", false) and !is_losing:
				if npc.type != "zombie":
					emotes.append("👀")
					if is_winning: emotes.append("😎")
		
		# Lógica de visualización
		if npc.emoji_timer > 0:
			npc.emoji_timer -= 0.05
		else:
			if emotes.size() == 1 and emotes[0] == "👀":
				var t_ms = Time.get_ticks_msec() % 3000
				npc.current_emoji = "👀" if t_ms < 1000 else ""
			elif emotes.size() > 0:
				var time_idx = int(Time.get_ticks_msec() / 1000.0) % emotes.size()
				npc.current_emoji = emotes[time_idx]
			else:
				npc.current_emoji = ""
		
		if npc.hit_flash > 0: 
			npc.hit_flash -= 1
			if npc.hit_flash == 0: npc.hit_type = "none"
		_draw_npc_pixels(npc, 0)
		
		# Stagger environmental & suffocation checks once every 10 ticks (0.5s) to eliminate CPU spikes
		if (_ai_tick_count + npc.id) % 10 == 0:
			_check_npc_environment_damage(npc)
		
		# Infección Zombie: si la vida baja del 20% y no ha sido verificado aún (solo por ataque zombie o daño por ácido)
		if not _is_zombie(npc.type) and npc.hp > 0 and npc.hp < npc.max_hp * 0.2 and not npc.get("zombie_checked", false):
			var can_infect = npc.get("zombie_infected", false) or npc.get("hit_type", "") == "acid"
			if can_infect:
				npc["zombie_checked"] = true
				if _get_lut_rand() < 0.5:
					_convert_to_zombie(npc)
		
		var np = npc.pos; var target = null
		if npc.hp > 0:
			# Update common timers
			if npc.attack_cooldown > 0: npc.attack_cooldown -= 0.05
			var s_cd = npc.get("social_cooldown", 0.0)
			if s_cd > 0: npc["social_cooldown"] = s_cd - 0.05
			var m_boost = npc.get("morale_boost_timer", 0.0)
			if m_boost > 0: npc["morale_boost_timer"] = m_boost - 0.05
			
			# OPTIMIZATION: Staggered AI Logic (Now using dedicated AI tick counter)
			var can_think = (npc.id % 6 == _ai_tick_count % 6)
			if can_think:
				_world_peace_timer += 0.3 # Approx 0.05 * 6
			
			# AUTONOMOUS AI LOGIC (Skip if controlled)
			if npc != controlled_npc:
				if npc.type == "mage" and npc.hp > 0:
					_process_mage_rescue(npc)
			
			if npc != controlled_npc and not npc.get("is_rescuing", false):
				var is_socializing = false
				
				# --- DOWNED / SLEEPING STATE HANDLER ---
				var is_lying = npc.get("is_lying", false)
				var lying_t = npc.get("lying_timer", 0.0)
				if is_lying:
					# Wake up if peace is broken! (combat, disaster, or user interaction)
					if _world_peace_timer == 0: 
						npc["lying_timer"] = 0; npc["is_lying"] = false; npc.current_emoji = ""
					else:
						npc["lying_timer"] = lying_t - 0.05
						npc.dir = 0
						if npc["lying_timer"] <= 0:
							npc["is_lying"] = false; npc["social_cooldown"] = 5.0
						is_socializing = true # Block other actions
				
				# --- SOCIAL STATE HANDLER ---
				var s_timer = npc.get("social_timer", 0.0)
				if s_timer > 0:
					npc["social_timer"] = s_timer - 0.05
					if npc["social_timer"] <= 0:
						npc["social_timer"] = 0
						npc["social_cooldown"] = _get_lut_rand_range(25.0, 45.0) 
						npc["social_target"] = null
					else:
						var s_target = npc.get("social_target", null)
						if s_target and s_target.hp > 0:
							var s_dist_x = s_target.pos.x - np.x
							if abs(s_dist_x) > 8:
								npc.dir = 1 if s_dist_x > 0 else -1
								if _get_lut_rand() < 0.1: npc.vy = -2.0 
							else:
								npc.dir = 0 
								npc["last_dir"] = 1 if s_dist_x > 0 else -1 # Look at partner
								if _get_lut_rand() < 0.12:
									var topic = npc.get("social_topic", "🍎")
									var emoji = "💬" if _get_lut_rand() > 0.5 else topic
									_set_npc_emoji(npc, emoji, 1.4)
								
								# --- OPTIMIZATION: Chance to invite a 3rd person (Group) ---
								if can_think and _get_lut_rand() < 0.05:
									var others = _get_nearby_npcs(np.x, np.y, 45.0)
									for o in others:
										if o.team == npc.team and o != npc and o != s_target:
											if o.get("social_timer", 0.0) <= 0 and o.get("social_cooldown", 0.0) <= 0:
												o["social_timer"] = npc["social_timer"]
												o["social_target"] = npc
												o["social_topic"] = npc["social_topic"]
												_set_npc_emoji(o, "👋", 1.2); break
							is_socializing = true
						else: 
							npc["social_timer"] = 0
							npc["social_cooldown"] = _get_lut_rand_range(15.0, 30.0) 
				
				# Cancel social if danger appears
				if (target != null or npc.get("is_fleeing", false)) and is_socializing:
					npc["social_timer"] = 0; is_socializing = false
					npc["social_cooldown"] = 10.0 # Shorter cooldown if interrupted by battle
				
				# --- LEADERSHIP SYSTEM (Update & Aura) ---
				if can_think:
					if npc.get("is_leader", false):
						# Leader's Aura: Boost morale of nearby allies
						var allies = _get_nearby_npcs(np.x, np.y, 140.0)
						var has_z = _has_active_zombies()
						for a in allies:
							if _is_ally(npc, a, has_z) and a != npc: a["morale_boost_timer"] = 2.0
						if _ai_tick_count % 30 == 0 and npc.get("emoji_timer", 0.0) <= 0: _set_npc_emoji(npc, "👑", 2.0)
					else:
						# Promotion Check: If 5+ allies are together without a leader
						var allies = _get_nearby_npcs(np.x, np.y, 100.0)
						var ally_count = 0; var leader_found = false
						for a in allies:
							if a.team == npc.team:
								ally_count += 1
								if a.get("is_leader", false): leader_found = true; break
						if ally_count >= 5 and not leader_found:
							npc["is_leader"] = true; npc["max_hp"] *= 1.5; npc["hp"] *= 1.5; npc["knockback_mult"] *= 0.7
							_set_npc_emoji(npc, "👑", 5.0)
				
				# --- DELAYED CONTAGION HANDLER ---
				var wait_t = npc.get("contagion_wait_timer", 0.0)
				if wait_t > 0:
					npc["contagion_wait_timer"] = wait_t - 0.05
					if npc["contagion_wait_timer"] <= 0:
						npc["dance_timer"] = 5.0
						npc["recently_celebrated"] = true
						npc["celebration_mode"] = randi() % 4 # 0:sparks, 1:launch, 2:burst, 3:just_dance
						npc["celebration_fw_timer"] = _get_lut_rand_range(0.3, 1.2)
						_set_npc_emoji(npc, "😎", 5.0)
				
				var is_dancing = false
				var dance_t = npc.get("dance_timer", 0.0)
				if dance_t > 0:
					npc["dance_timer"] = dance_t - 0.05
					var msec = Time.get_ticks_msec() + (npc.id * 137)
					var wiggle_speed = 180 + (npc.id % 50)
					npc.dir = 1 if (msec / wiggle_speed) % 2 == 0 else -1
					var jump_freq = 350 + (npc.id % 150)
					if (msec / jump_freq) % 2 == 0 and not _can_npc_fit(np.x, np.y + 1, npc):
						npc.vy = -3.0 - (float(npc.id % 5) * 0.5)
					
					# --- PERIODIC FIREWORKS DURING CELEBRATION ---
					var fw_mode = npc.get("celebration_mode", 0)
					if fw_mode != 3: # 3 is "Just Dance" (No fireworks)
						var fw_t = npc.get("celebration_fw_timer", 0.0)
						if fw_t > 0:
							npc["celebration_fw_timer"] = fw_t - 0.05
						else:
							var fw_type = randi() % 3
							if fw_type == 0: # Multi-color sparks
								var f_cols = [Color.RED, Color.YELLOW, Color.CYAN, Color.GREEN, Color.MAGENTA, Color.WHITE]
								var f_col = f_cols[randi() % f_cols.size()]
								for s in range(12): _add_spark(float(np.x), float(np.y - 12), _get_lut_rand_range(-70, 70), _get_lut_rand_range(-190, -70), f_col, 0.8)
							elif fw_type == 1: # Real firework launch
								_launch_firework(np.x, np.y - 5)
							else: # Real firework burst
								var f_col = Color.from_hsv(_get_lut_rand(), 0.8, 1.0)
								_explode_firework(np.x, np.y - 15, f_col)
							npc["celebration_fw_timer"] = _get_lut_rand_range(0.8, 2.0)
					
					npc["has_spotted_enemy"] = false
					is_dancing = true
					npc["social_timer"] = 0 # Cancel socializing if dancing
				
				if not is_dancing and not is_socializing:
					# --- CONTAGION CHECK (Victory or Panic) ---
					if can_think:
						var nearby = _get_nearby_npcs(np.x, np.y, 80.0)
						for other in nearby:
							if other.team == npc.team and other != npc:
								# 1. Join celebration?
								if profile.get("can_celebrate", true) and other.get("dance_timer", 0.0) > 1.0 and not npc.get("recently_celebrated", false):
									if _get_lut_rand() < 0.35 and npc.get("contagion_wait_timer", 0.0) <= 0:
										npc["contagion_wait_timer"] = _get_lut_rand_range(0.4, 2.0)
										break
								# 2. Join panic? (If we see an ally fleeing with a scare emoji)
								elif profile.get("can_flee", true) and other.get("is_fleeing", false) and other.current_emoji in ["😱", "😰", "🏃", "😨"]:
									if not npc.get("is_fleeing", false) and _get_lut_rand() < npc.get("cowardice", 0.3):
										npc["is_fleeing"] = true
										_set_npc_emoji(npc, other.current_emoji, 2.0)
										break
				
				if not is_dancing and not is_socializing:
					if npc.type == "medic":
						var heal_cd = npc.attack_cooldown
						var closest_enemy = null
						var closest_ally = null
						var ally_dist = 999.0
						
						if can_think:
							closest_enemy = _find_closest_enemy(npc, 180.0)
							var nearby = _get_nearby_npcs(npc.pos.x, npc.pos.y, 180.0)
							var has_z = _has_active_zombies()
							for other in nearby:
								if _is_ally(npc, other, has_z) and other != npc and other.hp > 0 and other.type != "medic":
									var mhp = other.get("max_hp", 100.0)
									if other.hp < mhp: 
										var d = npc.pos.distance_to(other.pos)
										if d < ally_dist: ally_dist = d; closest_ally = other
							# Store results to avoid recalculating every frame
							npc["cached_closest_enemy"] = closest_enemy
							npc["cached_closest_ally"] = closest_ally
							npc["cached_ally_dist"] = ally_dist
						else:
							closest_enemy = npc.get("cached_closest_enemy", null)
							closest_ally = npc.get("cached_closest_ally", null)
							ally_dist = npc.get("cached_ally_dist", 999.0)
							
						var medic_critical = npc.hp < (npc.get("max_hp", 100.0) * 0.5)
						var enemy_very_close = closest_enemy and npc.pos.distance_to(closest_enemy.pos) < 120.0
						if (medic_critical and enemy_very_close) or (enemy_very_close and not closest_ally):
							npc.dir = 1 if closest_enemy.pos.x < np.x else -1; npc["is_fleeing"] = true
						else:
							npc["is_fleeing"] = false
							if closest_ally:
								if ally_dist < 25.0:
									npc.dir = 0
									if heal_cd <= 0:
										closest_ally.hp = min(closest_ally.hp + npc.get("heal_power", 20.0), closest_ally.get("max_hp", 100.0))
										npc["attack_cooldown"] = 1.0; _play_action_sound("medic_heal")
										_set_npc_emoji(npc, "💚", 1.0) 
										if closest_ally.hp > closest_ally.get("max_hp", 100.0) * 0.3:
											closest_ally["morale_broken"] = false; closest_ally["is_fleeing"] = false
										_set_npc_emoji(closest_ally, "😊", 1.5)
										for _f in range(6): _add_spark(float(closest_ally.pos.x+_get_lut_rand_range(-3,3)),float(closest_ally.pos.y+_get_lut_rand_range(-5,0)),0.0,_get_lut_rand_range(-35.0,-15.0),Color.GREEN,0.6)
								else: npc.dir = 1 if closest_ally.pos.x > np.x else -1
							else:
								if npc.get("has_spotted_enemy", false):
									# VICTORY CELEBRATION (Medic variant)
									if profile.get("can_celebrate", true) and _get_lut_rand() < 0.4:
										npc["dance_timer"] = 5.0
										npc["recently_celebrated"] = true
										npc["celebration_mode"] = randi() % 4
										npc["celebration_fw_timer"] = 0.1 # Start firing immediately
										_set_npc_emoji(npc, "😎", 5.0)
								npc["has_spotted_enemy"] = false
								var rethink_chance = 0.045 if npc.dir == 0 else 0.012
								if _get_lut_rand() < rethink_chance: 
									var r = _get_lut_rand()
									if r < 0.35: npc.dir = 1
									elif r < 0.7: npc.dir = -1
									else: npc.dir = 0 # Guard mode / Stay still
						# (Medic logic ends here)
						pass
					elif npc.type != "miner":
						if can_think:
							target = _find_closest_enemy(npc, 250.0)
							npc["cached_target"] = target
						else:
							target = npc.get("cached_target", null)
							
						if target and !npc.get("morale_broken", false):
							npc["recently_celebrated"] = false # Ready for next time
							npc["contagion_wait_timer"] = 0.0
							if !npc.get("has_spotted_enemy", false):
								var spot_emoji = "📣" if npc.get("is_leader", false) else "❗"
								_set_npc_emoji(npc, spot_emoji, 1.2)
								npc["has_spotted_enemy"] = true
								_world_peace_timer = 0.0 # Combat resets peace
								# Shared Vision: Leader alerts nearby allies
								if npc.get("is_leader", false):
									var allies = _get_nearby_npcs(np.x, np.y, 150.0)
									for a in allies:
										if a.team == npc.team and !a.get("has_spotted_enemy", false):
											a["has_spotted_enemy"] = true; _set_npc_emoji(a, "❗", 1.0)
						elif !target:
							if npc.get("has_spotted_enemy", false):
								# VICTORY CELEBRATION!
								if profile.get("can_celebrate", true) and _get_lut_rand() < 0.4:
									npc["dance_timer"] = 5.0
									npc["recently_celebrated"] = true
									npc["celebration_mode"] = randi() % 4
									npc["celebration_fw_timer"] = 0.1 # Start firing immediately
									_set_npc_emoji(npc, "😎", 5.0)
							npc["has_spotted_enemy"] = false
					
					# --- EMERGENT DISASTER PANIC ---
					var disaster_near = false
					var run_from_x = -1.0
					if tornado_intensity > 0 and abs(npc.pos.x - tornado_x) < 180:
						disaster_near = true; run_from_x = tornado_x
					if tsunami_intensity > 0 and abs(npc.pos.x - tsunami_wave_x) < 220:
						disaster_near = true; run_from_x = tsunami_wave_x
					if earthquake_intensity > 1.2:
						disaster_near = true
					
					if disaster_near and profile.get("can_panic_disaster", true):
						_world_peace_timer = 0.0 # Disasters reset peace
						if not npc.get("is_fleeing", false):
							var panic_chance = npc.get("cowardice", 0.3) * 1.8
							if npc.get("morale_boost_timer", 0.0) > 0: panic_chance *= 0.5 # Protected by leader
							if _get_lut_rand() < panic_chance:
								npc["is_fleeing"] = true
								var panic_emoji = ["😱", "😰", "🏃", "😨"][randi() % 4]
								_set_npc_emoji(npc, panic_emoji, 2.5)
						
						if npc.get("is_fleeing", false):
							if run_from_x != -1.0:
								npc.dir = 1 if npc.pos.x > run_from_x else -1
							else:
								if _get_lut_rand() < 0.02: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
					
					# Reset panic state if the danger is gone
					if not disaster_near and npc.get("is_fleeing", false):
						if not npc.get("morale_broken", false) and not npc.current_emoji in ["😱", "😰", "🏃", "😨"]:
							npc["is_fleeing"] = false
					
					# --- EMOTIONAL PERSONALITY (SPONTANEOUS) ---
					if can_think and not is_dancing and not is_socializing and not npc.get("is_fleeing", false) and not target:
						var chance = _get_lut_rand()
						
						# 1. Rain Awareness
						if current_weather > 0 and chance < 0.1:
							_set_npc_emoji(npc, "☔", 3.0)
						
						# 2. Greed/Curiosity (Near Metal or tech blocks)
						elif chance < 0.15:
							var is_near_tech = false
							for ox in range(-6, 7, 3):
								for oy in range(-6, 7, 3):
									var tid = _get_cell(np.x + ox, np.y + oy)
									if tid == 8 or tid == 9 or tid == 27: is_near_tech = true; break
								if is_near_tech: break
							if is_near_tech: _set_npc_emoji(npc, "🤩", 2.0)
							
						# 3. Fire Aversion (Near Fire or Lava)
						elif chance < 0.2:
							var is_near_fire = false
							for ox in range(-5, 6, 2):
								for oy in range(-5, 6, 2):
									var tid = _get_cell(np.x + ox, np.y + oy)
									if tid == 3 or tid == 11: is_near_fire = true; break
								if is_near_fire: break
							if is_near_fire: _set_npc_emoji(npc, "😰", 1.5)
						
						# 4. Socialize (Move to chat with ally)
						var is_bored = npc.get("recently_bored", false)
						var social_chance = 0.2 if is_bored else 0.012
						if profile.get("can_socialize", true) and _get_lut_rand() < social_chance and npc.get("social_cooldown", 0.0) <= 0:
							var nearby = _get_nearby_npcs(np.x, np.y, 42.0) 
							var has_z = _has_active_zombies()
							for other in nearby:
								if _is_ally(npc, other, has_z) and other != npc and abs(other.vx) < 0.2 and not other.get("dance_timer", 0.0) > 0 and other.get("social_cooldown", 0.0) <= 0 and not other.get("is_lying", false):
									var meet_t = _get_lut_rand_range(3.0, 5.0)
									var topics = [
										"🍎", "🧪", "🔥", "🏠", "⚔️", "💎", "🌧️", "🌳", "⚡", "📜", "💰", "👑", "🗣️", "🍻", "🐺", "💀", "🗺️", "🏹", "🛡️", "🔮", "👁️", "☄️", "🍄", "🗝️", "🍞", "⚒️", "⚖️", "🐎", "🕯️" ];
									var chosen_topic = topics[randi() % topics.size()]
									npc["social_timer"] = meet_t; npc["social_target"] = other; npc["social_topic"] = chosen_topic
									other["social_timer"] = meet_t; other["social_target"] = npc; other["social_topic"] = chosen_topic
									npc["recently_bored"] = false; other["recently_bored"] = false
									_set_npc_emoji(npc, "👋", 1.2); _set_npc_emoji(other, "👋", 1.2)
									is_socializing = true
									break
							
						# 6. Boredom (Linked to Social)
						elif npc.get("social_cooldown", 0.0) <= 0 and chance < 0.25:
							if _get_lut_rand() < 0.05 and not npc.get("recently_bored", false):
								_set_npc_emoji(npc, "🥱", 2.0); npc["recently_bored"] = true
							
							# 7. Sleeping (If world has been at peace for 2+ minutes)
							if profile.get("can_sleep", true) and _world_peace_timer > 120.0 and _get_lut_rand() < 0.25: # Significantly higher chance
								if not npc.get("is_leader", false) or _get_lut_rand() < 0.15: 
									npc["is_lying"] = true; npc["lying_timer"] = 9999.0 
									_set_npc_emoji(npc, "😴", 9999.0); npc["recently_bored"] = false
						else:
							if _get_lut_rand() < 0.01: npc["recently_bored"] = false
						
						# 8. Collapse (If very low HP)
						if profile.get("can_sleep", true) and npc.hp < (npc.max_hp * 0.2) and _get_lut_rand() < 0.03:
							npc["is_lying"] = true; npc["lying_timer"] = _get_lut_rand_range(3.0, 6.0)
							_set_npc_emoji(npc, "🤕", 2.5)
					
					var critical_hp = npc.get("max_hp", 100.0) * 0.3
					if profile.get("can_flee", true) and npc.hp <= critical_hp and not npc.get("morale_broken", false):
						npc["morale_broken"] = true
						if _get_lut_rand() < npc.get("cowardice", 0.30):
							npc["is_fleeing"] = true
							_set_npc_emoji(npc, "😭", 3.0) 
							var start_drop_x = np.x + (1 if npc.dir == -1 else 0)
							if _get_cell(start_drop_x, np.y) == 0: _set_cell(start_drop_x, np.y, 2)
					
					if npc.type != "miner" and npc.type != "medic" and npc.type != "zombie" and npc.type != "zombie_tank":
						if npc.get("is_fleeing", false):
							if target: npc.dir = 1 if target.pos.x < np.x else -1
							if npc.dir == 0: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
							if _get_lut_rand() < 0.10:
								var drop_x = np.x + (1 if npc.dir == -1 else 0)
								if _get_cell(drop_x, np.y) == 0: _set_cell(drop_x, np.y, 2)
						elif !target:
							var rethink_chance = 0.045 if npc.dir == 0 else 0.012
							if _get_lut_rand() < rethink_chance: 
								var r = _get_lut_rand()
								if r < 0.35: npc.dir = 1
								elif r < 0.7: npc.dir = -1
								else: npc.dir = 0 # Guard mode / Stay still
						elif target:
							var dist_x = target.pos.x - np.x; var dx_abs = abs(dist_x); var dy_abs = abs(target.pos.y - np.y)
							if npc.type == "warrior":
								var target_below = target.pos.y > np.y + 8
								if target_below:
									if npc.dir == 0: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
								else: npc.dir = 1 if dist_x > 0 else -1
								if dx_abs < 6 and dy_abs < 6:
									if npc.attack_cooldown <= 0: _attack_npc(npc, target); npc.attack_cooldown = 0.6
								if dx_abs < 4 and !target_below: npc.dir = 0 
							elif npc.type == "archer":
								var target_below = target.pos.y > np.y + 12
								if npc.miss_counter < 0:
									npc.miss_counter += 1
									if npc.dir == 0: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
								else:
									if dx_abs > 120: npc.dir = 1 if dist_x > 0 else -1
									elif dx_abs < 50: npc.dir = -1 if dist_x > 0 else 1
									else:
										if target_below:
											if npc.dir == 0: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
										else: npc.dir = 0
								if npc.attack_cooldown <= 0:
									_shoot_arrow(npc, target); npc.miss_counter += 1
									if npc.miss_counter >= 3: npc.miss_counter = -40
									npc.attack_cooldown = 1.1 if dx_abs > 50 else 1.5
							elif npc.type == "mage":
								var target_below = target.pos.y > np.y + 12
								if dx_abs > 110: npc.dir = 1 if dist_x > 0 else -1
								elif dx_abs < 35: npc.dir = -1 if dist_x > 0 else 1
								else:
									if target_below:
										if npc.dir == 0: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
									else: npc.dir = 0
								if npc.attack_cooldown <= 0:
									_shoot_fireball(npc, target)
									npc.attack_cooldown = 1.8
					elif npc.type == "zombie_tank":
						if target:
							npc["recently_celebrated"] = false
							npc["contagion_wait_timer"] = 0.0
							npc["has_spotted_enemy"] = true
							_world_peace_timer = 0.0
							
							var dist_x = target.pos.x - np.x
							var dx_abs = abs(dist_x)
							var dy_abs = abs(target.pos.y - np.y)
							var target_below = target.pos.y > np.y + 8
							
							# Heavy slower movement decisions
							if _get_lut_rand() < 0.08:
								var r_choice = _get_lut_rand()
								if r_choice < 0.4:
									npc.dir = 0
									if _get_lut_rand() < 0.3:
										_set_npc_emoji(npc, "🧟", 1.0)
								elif r_choice < 0.7:
									npc.dir = -1 if dist_x > 0 else 1
								else:
									if !_can_npc_fit(np.x, np.y + 1, npc):
										npc.vy = -3.5 - (_get_lut_rand() * 1.5)
							else:
								if target_below:
									if npc.dir == 0: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
								else:
									npc.dir = 1 if dist_x > 0 else -1
							
							# Melee attack
							if dx_abs < 7 and dy_abs < 7:
								if npc.attack_cooldown <= 0:
									_attack_npc(npc, target)
									npc.attack_cooldown = 1.0
									
							# Ranged block throw
							var dist = npc.pos.distance_to(target.pos)
							if dist >= 35.0 and dist <= 150.0 and npc.attack_cooldown <= 0:
								var found_x = -1; var found_y = -1; var found_mat = 2
								for dy in range(-4, 7):
									for dx in range(-5, 6):
										var tx = np.x + dx; var ty = np.y + dy
										if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
											var tid = _get_cell(tx, ty)
											if tid > 0 and tid != 1 and not (material_tags_raw[_get_tags_id(tid)] & SandboxMaterial.Tags.NPC):
												found_x = tx; found_y = ty; found_mat = tid; break
									if found_x != -1: break
									
								if found_x != -1:
									_set_cell(found_x, found_y, 0)
									for _s in range(5):
										_add_spark(float(found_x), float(found_y), _get_lut_rand_range(-30, 30), _get_lut_rand_range(-50, -10), mat_colors_1[found_mat] if found_mat < mat_colors_1.size() else Color.GRAY, 0.4)
										
								var time_to_target = abs(dist_x) / 120.0
								time_to_target = clamp(time_to_target, 0.4, 2.5)
								var vx = dist_x / time_to_target
								var vy = (target.pos.y - np.y) / time_to_target - (0.5 * 200.0 * time_to_target)
								
								active_projectiles.append({
									"pos": Vector2(np.x + (1 if dist_x > 0 else -1) * 3, np.y + 1),
									"vel": Vector2(vx, vy),
									"team": npc.team,
									"type": "thrown_rock",
									"life": 3.0,
									"block_material": found_mat,
									"atk_dmg": 1.5
								})
								
								var p_scale = 0.65 + float((npc.id * 23) % 40) / 40.0 * 0.40
								_play_action_sound("zombie_tank_throw", 0.08, 0.0, p_scale)
								_set_npc_emoji(npc, "🪨", 1.2)
								npc.attack_cooldown = 2.5
								
							if dx_abs < 4 and not target_below:
								npc.dir = 0
						else:
							npc["has_spotted_enemy"] = false
							var rethink_chance = 0.08 if npc.dir == 0 else 0.03
							if _get_lut_rand() < rethink_chance:
								var r = _get_lut_rand()
								if r < 0.4: npc.dir = 1
								elif r < 0.8: npc.dir = -1
								else: npc.dir = 0
								
								if _get_lut_rand() < 0.15 and !_can_npc_fit(np.x, np.y + 1, npc):
									npc.vy = -3.5 - (_get_lut_rand() * 1.2)
								
								if _get_lut_rand() < 0.08:
									_set_npc_emoji(npc, "🧟", 1.5)
							
							# Slow down wandering tank (move only on 1/4 of the ticks)
							if (npc.id + _ai_tick_count) % 4 != 0:
								npc.dir = 0
								
					elif npc.type == "zombie":
						if target:
							npc["recently_celebrated"] = false
							npc["contagion_wait_timer"] = 0.0
							npc["has_spotted_enemy"] = true
							_world_peace_timer = 0.0
							
							var dist_x = target.pos.x - np.x
							var dx_abs = abs(dist_x)
							var dy_abs = abs(target.pos.y - np.y)
							var target_below = target.pos.y > np.y + 8
							
							if _get_lut_rand() < 0.12:
								var r_choice = _get_lut_rand()
								if r_choice < 0.4:
									npc.dir = 0
									if _get_lut_rand() < 0.3:
										var z_emotes = ["🧟", "🧠", "🥩"]
										_set_npc_emoji(npc, z_emotes[randi() % z_emotes.size()], 1.0)
								elif r_choice < 0.7:
									npc.dir = -1 if dist_x > 0 else 1
								else:
									if !_can_npc_fit(np.x, np.y + 1, npc):
										npc.vy = -3.2 - (_get_lut_rand() * 1.5)
							else:
								if target_below:
									if npc.dir == 0: npc.dir = 1 if _get_lut_rand() > 0.5 else -1
								else:
									npc.dir = 1 if dist_x > 0 else -1
							
							if dx_abs < 6 and dy_abs < 6:
								if npc.attack_cooldown <= 0:
									_attack_npc(npc, target)
									npc.attack_cooldown = 0.8
							if dx_abs < 4 and not target_below:
								npc.dir = 0
						else:
							npc["has_spotted_enemy"] = false
							var rethink_chance = 0.08 if npc.dir == 0 else 0.03
							if _get_lut_rand() < rethink_chance:
								var r = _get_lut_rand()
								if r < 0.4: npc.dir = 1
								elif r < 0.8: npc.dir = -1
								else: npc.dir = 0
								
								if _get_lut_rand() < 0.15 and !_can_npc_fit(np.x, np.y + 1, npc):
									npc.vy = -3.0 - (_get_lut_rand() * 1.2)
								
								if _get_lut_rand() < 0.08:
									var z_emotes = ["🧟", "🧠", "🥩"]
									_set_npc_emoji(npc, z_emotes[randi() % z_emotes.size()], 1.5)
							
							# Slow down wandering zombie (move only on 1/3 of the ticks)
							if (npc.id + _ai_tick_count) % 3 != 0:
								npc.dir = 0
					
					if npc.type == "miner":
						var dig_speed = 0.15 if npc.hp < 100.0 else 0.05 
						if npc.hit_flash == 5: npc.dir = -npc.dir
						npc.dig_timer += dig_speed
						if npc.dig_timer >= 0.15:
							npc.dig_timer = 0.0
							if !_can_npc_fit(np.x, np.y + 1, npc):
								if not (npc.has("mine_state") and npc.mine_state == "saboteur"): npc.state_steps -= 1
								if !(_get_cell(np.x, np.y - 4) != 0) and npc.mine_state == "gallery":
									npc.mine_state = "ramp"; npc.state_steps = 25
								if npc.state_steps <= 0:
									if npc.mine_state == "saboteur":
										_set_cell(np.x, np.y + 5, 3); npc.hp = 0; npc.hit_flash = 10
										_unlock_achievement("miner_plan")
									elif npc.mine_state == "ramp": npc.mine_state = "gallery"; npc.state_steps = _get_lut_rand_range(60, 100)
									else: npc.mine_state = "ramp"; npc.state_steps = _get_lut_rand_range(15, 25)
								
								if npc.hp > 0:
									var dig_down = (npc.mine_state == "ramp")
									_miner_dig(npc, dig_down)
									var next_x = np.x + npc.dir; var next_y = np.y + (1 if dig_down else 0); var hit_wall = false
									if next_y >= dynamic_grid_height - 15:
										if npc.mine_state != "saboteur":
											npc.mine_state = "saboteur"; npc["saboteur_start_x"] = np.x; npc["saboteur_bounces"] = 0; npc.dir = 1 if _get_lut_rand() > 0.5 else -1
										next_y = np.y; next_x = np.x + npc.dir
									
									if npc.has("mine_state") and npc.mine_state == "saboteur" and npc.has("saboteur_bounces") and npc.saboteur_bounces >= 3:
										for fx in range(-2, 3):
											var f_idx = np.x + fx
											if f_idx >= 0 and f_idx < grid_width: 
												_set_cell(f_idx, np.y + 5, 3) 
												_set_cell(f_idx, np.y - 1, 3)
										npc.hp = 0
										npc.hit_flash = 10
										_unlock_achievement("miner_plan")
										npc.hp = 0; npc.hit_flash = 10
									else:
										var old_dir = npc.dir
										if next_x < 5 or next_x > grid_width - 5: hit_wall = true; npc.dir = -npc.dir
										elif _can_npc_fit(next_x, next_y, npc): np.x = next_x ; np.y = next_y
										elif !dig_down and _can_npc_fit(next_x, np.y - 1, npc): np.x = next_x ; np.y -= 1
										else: hit_wall = true; npc.dir = -npc.dir
										if hit_wall:
											if not (npc.has("mine_state") and npc.mine_state == "saboteur" and npc.has("saboteur_bounces") and npc.saboteur_bounces >= 2) and (next_x <= 5 or next_x >= grid_width - 5):
												var wall_x1 = np.x + 2 if old_dir == 1 else np.x - 1
												var wall_x2 = np.x + 3 if old_dir == 1 else np.x - 2
												for wy in range(np.y - 1, np.y + 6):
													if wy >= 0 and wy < dynamic_grid_height:
														if wall_x1 >= 0 and wall_x1 < grid_width: _set_cell(wall_x1, wy, 16)
														if wall_x2 >= 0 and wall_x2 < grid_width: _set_cell(wall_x2, wy, 16)
											if npc.has("mine_state") and npc.mine_state == "saboteur":
												if not npc.has("saboteur_bounces"): npc["saboteur_bounces"] = 0
												if npc.saboteur_bounces < 4: npc.saboteur_bounces += 1

		if not npc.has("vx"): npc["vx"] = 0.0
		if not npc.has("vy"): npc["vy"] = 0.0
		
		# Forzar físicas para el NPC controlado si está en el aire (Gravedad)
		if npc == controlled_npc and _can_npc_fit(np.x, np.y + 1, npc):
			if abs(npc.vy) < 0.1: npc.vy = 0.1
			
		var moved_by_physics = false
		if abs(npc.vx) > 0.1 or abs(npc.vy) > 0.1:
			var steps_x = int(ceil(abs(npc.vx))); var dir_x = sign(npc.vx)
			var steps_y = int(ceil(abs(npc.vy))); var dir_y = sign(npc.vy)
			var max_steps = max(steps_x, steps_y)
			
			# FISICA DE EJES SEPARADOS: Permite deslizarse por paredes (Slide Physics)
			for j in range(max_steps):
				# Paso Horizontal (X)
				if j < steps_x:
					var next_x = np.x + int(dir_x)
					# Bloqueo por límites de pantalla
					if next_x < 0 or next_x + 1 >= grid_width:
						npc.vx = 0.0
					elif _can_npc_fit(next_x, np.y, npc):
						np.x = next_x
					else:
						npc.vx = 0.0
				
				# Paso Vertical (Y)
				if j < steps_y:
					var next_y = np.y + int(dir_y)
					if _can_npc_fit(np.x, next_y, npc):
						np.y = next_y
					else:
						npc.vy = 0.0
			if _can_npc_fit(np.x, np.y + 1, npc): # EN EL AIRE
				npc.vy += 1.0 # Gravedad
				npc.fall_depth += 1
				
				# --- CONTROL AEREO ---
				# Si el NPC tiene una dirección (dir), intentar mantener/ganar velocidad horizontal en el aire
				if npc.dir != 0:
					var air_speed_target = float(npc.dir) * 3.5
					npc.vx = lerp(npc.vx, air_speed_target, 0.15)
				
				npc.vx *= 0.99 # Rozamiento de aire leve
			else: # EN EL SUELO
				if npc.vy > 0: 
					if npc.vy >= 7.0 or npc.fall_depth >= 15: 
						var fall_dmg = max(5.0, (npc.fall_depth - 10) * 1.5)
						if npc == controlled_npc: fall_dmg *= 0.5 # 50% fall damage reduction
						npc.hp -= fall_dmg; npc.hit_flash = 5
					npc.vy = 0.0; npc.fall_depth = 0
				npc.vx *= 0.6 # Fricción de suelo
			
			if abs(npc.vx) < 0.2: npc.vx = 0.0
			if npc.vy > 8.0: npc.vy = 8.0
			moved_by_physics = true
		
		# --- 3. MOVIMIENTO IA (SI NO HAY FISICA ACTIVA Y NO ESTÁ POSEÍDO) ---
		if not moved_by_physics and npc != controlled_npc:
			# 1. GRAVEDAD SOBERANA: Chequeo solo bajo los pies para evitar "colgarse" lateralmente
			var w = 3 if (npc.type == "zombie_tank") else 2
			var h = 6 if (npc.type == "zombie_tank" or npc.type == "mage") else 5
			var feet_y = np.y + h
			var can_fall = true
			if feet_y >= dynamic_grid_height: can_fall = false
			else:
				for ox in range(w):
					var tid = _get_cell(np.x + ox, feet_y)
					if tid != 0 and tid != 15 and tid != 3 and tid != 17:
						if !(material_tags_raw[_get_tags_id(tid)] & (SandboxMaterial.Tags.NPC | SandboxMaterial.Tags.PLANT)):
							can_fall = false; break
			
			if can_fall:
				np.y += 1; npc.fall_depth += 1
			elif npc.type != "miner":
				if npc.fall_depth >= 12: 
					var fall_dmg = (npc.fall_depth - 10) * 1.5
					if npc == controlled_npc: fall_dmg *= 0.5
					npc.hp -= fall_dmg; npc.hit_flash = 5
				if npc.fall_depth >= 3: npc.dir = -npc.dir
				npc.fall_depth = 0
				
				# Detectar si estamos atascados (sin movernos horizontalmente)
				var is_trying_to_move = (npc.dir != 0 or target != null)
				var cur_stuck = npc.get("stuck_timer", 0.0)
				if is_trying_to_move and abs(np.x - npc.get("last_pos_x", np.x)) < 0.1:
					cur_stuck += 0.05
				else:
					cur_stuck = 0.0
				npc["stuck_timer"] = cur_stuck
				npc["last_pos_x"] = np.x
				
				if npc.dir != 0:
					var moved = false
					# Asegurar límites de mapa antes de procesar
					np.x = clampi(np.x, 0, grid_width - 2)
					var front_edge = np.x + 1 if npc.dir == 1 else np.x
					var hazard_stop = false
					
					# 1. ESCANEO DE PELIGROS (Lava, Ácido, TNT)
					var danger_dist = -1; var safe_landing_dist = -1
					for dx in range(1, 15):
						var detect_x = front_edge + (npc.dir * dx)
						if detect_x < 0 or detect_x >= grid_width: break
						var is_danger = false
						for oy in range(0, 6):
							var tid = _get_cell(detect_x, np.y + oy)
							if tid > 0 and (material_tags_raw[_get_tags_id(tid)] & (SandboxMaterial.Tags.INCENDIARY | SandboxMaterial.Tags.ACID | SandboxMaterial.Tags.EXPLOSIVE)): 
								is_danger = true; break
						if is_danger:
							if danger_dist == -1: danger_dist = dx
						elif danger_dist != -1 and not is_danger: 
							safe_landing_dist = dx; break
					
					if danger_dist != -1:
						if danger_dist <= 5: 
							var hazard_width = safe_landing_dist - danger_dist
							if safe_landing_dist != -1 and hazard_width <= 20: # Salto largo para lava
								if _can_npc_fit(np.x, np.y - 1, npc): npc.vy = -4.8; npc.vx = npc.dir * 3.6; moved = true
							else: 
								_set_npc_emoji(npc, "😨", 1.5)
								if target == null: npc.dir = -npc.dir; moved = true
								else: hazard_stop = true # Detenerse ante el peligro si hay target
					
					# 2. ESCANEO DE ACANTILADOS (Si no hay enemigo, no suicidarse)
					if not moved and not hazard_stop:
						var edge_x = np.x + (npc.dir * 2); var drop_depth = 0
						for dy in range(1, 15):
							if not _can_npc_fit(edge_x, np.y + dy, npc): break
							drop_depth += 1
						if drop_depth >= 12:
							var ignore_cliff = (target != null and target.pos.y > np.y and abs(target.pos.x - np.x) < 60)
							if not ignore_cliff: 
								if target == null: npc.dir = -npc.dir; moved = true
								else: hazard_stop = true # Detenerse en el borde si hay target, esperar a stuck_timer

					# 3. COLISIONES CON ALIADOS Y OBSTRUCCIONES
					if not moved and not hazard_stop:
						var step_size = 2 if (npc.type == "mage" and npc.get("is_rescuing", false)) else 1
						var tx_1 = np.x + npc.dir * step_size
						var tx_2 = np.x + (npc.dir * (step_size + 1))
						var tx_test = tx_1 if (target != null or _get_lut_rand() < 0.5) else tx_2
						
						var nearby = _get_nearby_npcs(tx_test, np.y, 10.0)
						var bumped_ally = false
						var has_z = _has_active_zombies()
						for other in nearby:
							if _is_ally(npc, other, has_z) and other != npc:
								var ow = 3 if (other.type == "zombie_tank") else 2
								var oh = 6 if (other.type == "zombie_tank" or other.type == "mage") else 5
								if tx_test < other.pos.x + ow and tx_test + w > other.pos.x and np.y < other.pos.y + oh and np.y + h > other.pos.y:
									bumped_ally = true; break
						
						if bumped_ally: 
							if target == null: 
								var bumps = npc.get("bump_counter", 0)
								npc["bump_counter"] = bumps + 1
								if bumps >= 5:
									if _can_npc_fit(np.x, np.y - 1, npc):
										npc.vy = -4.0; npc.vx = npc.dir * 2.5; moved = true
										npc["bump_counter"] = 0
								else:
									npc.dir = -npc.dir; moved = true
							else: # Intentar saltar sobre el aliado si estamos persiguiendo
								if _can_npc_fit(np.x, np.y - 1, npc): 
									npc.vy = -3.5; npc.vx = npc.dir * 2.0; moved = true
									npc["bump_counter"] = 0 # Reset bump on successful jump
						
						if not moved:
							# --- STEP-UP SISTEMA ---
							for dy in [0, -1, -2, -3]:
								if _can_npc_fit(tx_1, np.y + dy, npc):
									np.x = tx_1; np.y += dy; moved = true; break
							
							# If blocked by something taller, use a physics jump instead of teleporting
							if not moved:
								var max_jump = -12
								for dy in range(-4, max_jump - 1, -1):
									if _can_npc_fit(tx_2, np.y + dy, npc):
										# Instead of np.y += dy (teleport), we apply physics
										# This makes the "climb" look like a real jump and prevents teleport-loops
										npc.vy = -5.2; npc.vx = npc.dir * 3.4
										npc["stuck_timer"] = 0.0 # Reset as we are attempting a leap
										moved = true; break
					
					# 4. SISTEMA ANTI-ATASCO: SALTO FORZADO (Solo si no hemos avanzado)
					if not moved and target != null and npc.get("stuck_timer", 0.0) > 0.8:
						if _can_npc_fit(np.x, np.y - 1, npc):
							npc.vy = -4.5; npc.vx = npc.dir * 2.5; npc["stuck_timer"] = 0.0; moved = true
							_set_npc_emoji(npc, "🔨", 0.8)

					# 5. SI NADA FUNCIONÓ, GIRAR
					if not moved:
							if target == null or np.x <= 2 or np.x >= grid_width - 4:
								npc.dir = -npc.dir
							elif npc.get("stuck_timer", 0.0) > 2.0: # Si sigue atascado demasiado tiempo persiguiendo
								npc.dir = -npc.dir; npc["stuck_timer"] = 0.0 # Intentar buscar otra ruta
		
		npc.pos = np; _draw_npc_pixels(npc)
		if npc.hp <= 0 and npc.hit_flash <= 0:
			if not _is_zombie(npc.type) and npc.get("hit_type", "") == "acid":
				_convert_to_zombie(npc)
			else:
				_set_npc_emoji(npc, "💀", 2.0)
				_draw_npc_pixels(npc, 0); _play_action_sound("npc_death")
				if npc.type == "miner" and npc.has("mine_state") and npc.mine_state == "saboteur":
					for fx in range(-2, 3):
						var f_idx = np.x + fx
						if f_idx >= 0 and f_idx < grid_width: _set_cell(f_idx, np.y + 5, 3); _set_cell(f_idx, np.y - 1, 3)
				npc.current_emoji = ""
				dead_indices.append(i)
	dead_indices.sort(); dead_indices.reverse()
	for idx in dead_indices: active_npcs.remove_at(idx)
	for npc in active_npcs: _draw_npc_pixels(npc)

func _miner_dig(npc, dig_down=false):
	if npc.hp <= 0: return
	var now = Time.get_ticks_msec()
	if now - npc.last_dig_time >= 3000: _play_action_sound("miner_dig"); npc.last_dig_time = now
	
	# RESTORED MISSING LOGIC
	var dy_offset = 1 if dig_down else 0
	var ty_start = npc.pos.y - 2 + dy_offset
	var ty_end = npc.pos.y + 5 + dy_offset
	var beam_len = 3 if dig_down else 6
	var is_saboteur = npc.has("mine_state") and npc.mine_state == "saboteur"
	var c_mat = 16 

	var tx_c = npc.pos.x + (npc.dir * 3)
	for ox in range(0, beam_len):
		var wx = tx_c + (ox * npc.dir)
		if wx < 0 or wx >= grid_width: continue
		if ty_start >= 0:
			var mountain_ahead = false
			for rx in range(0, 4):
				var r_check = wx + (rx * npc.dir)
				if r_check >= 0 and r_check < grid_width:
					var look_id = _get_cell(r_check, ty_start)
					if look_id != 0 and look_id != c_mat: mountain_ahead = true; break
			if mountain_ahead or is_saboteur:
				_set_cell(wx, ty_start, c_mat)
				if !dig_down and ty_start - 1 >= 0: _set_cell(wx, ty_start - 1, c_mat)
	var f_mat = 5 if is_saboteur else 16 # Piso TNT o Madera normal
	var tx_f = npc.pos.x - (npc.dir * 2) 
	var f_len = 6
	for ox in range(0, f_len):
		var wx = tx_f + (ox * npc.dir)
		if wx < 0 or wx >= grid_width: continue
		if ty_end < dynamic_grid_height:
			_set_cell(wx, ty_end, f_mat)
			if !dig_down and ty_end + 1 < dynamic_grid_height: _set_cell(wx, ty_end + 1, f_mat)
	for dx in range(0, 4):
		for dy in range(ty_start + 1, ty_end):
			var cx = npc.pos.x + (dx * npc.dir); var cy = dy 
			if cx < 0 or cx >= grid_width or cy < 0 or cy >= dynamic_grid_height: continue
			var tid = _get_cell(cx, cy)
			if tid == 0 or tid == 9 or tid == 12: continue
			_set_cell(cx, cy, 0)

func _get_connected_door_cells(start_idx: int) -> Array:
	var group = []
	var queue = [start_idx]
	var visited = {}
	visited[start_idx] = true
	
	var w = grid_width
	var h = dynamic_grid_height
	
	var q_idx = 0
	while q_idx < queue.size():
		var curr = queue[q_idx]
		q_idx += 1
		group.append(curr)
		
		var cx = curr % w
		var cy = curr / w
		
		# Left
		if cx > 0:
			var n = curr - 1
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
		# Right
		if cx < w - 1:
			var n = curr + 1
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
		# Up
		if cy > 0:
			var n = curr - w
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
		# Down
		if cy < h - 1:
			var n = curr + w
			if not visited.has(n) and door_registry.has(n):
				visited[n] = true
				queue.append(n)
				
	return group

func _update_npc_doors(delta: float):
	if door_registry.size() == 0: return
	
	is_npc_door_updating = true
	
	# 1. Proximity detection: Find door indices directly near any active NPC (within 8px)
	var triggered_door_cells = {}
	for npc in active_npcs:
		if npc.hp <= 0: continue
		var npc_w = 3 if (npc.type == "zombie_tank") else 2
		var npc_h = 6 if (npc.type == "zombie_tank" or npc.type == "mage") else 5
		var min_x = npc.pos.x - 8
		var max_x = npc.pos.x + npc_w - 1 + 8
		var min_y = npc.pos.y - 8
		var max_y = npc.pos.y + npc_h + 8
		
		# Hybrid Scan: loop registry if small, otherwise scan local bounding box
		if door_registry.size() < 200:
			for idx in door_registry:
				if triggered_door_cells.has(idx): continue
				var dx = idx % grid_width
				var dy = idx / grid_width
				if dx >= min_x and dx <= max_x and dy >= min_y and dy <= max_y:
					triggered_door_cells[idx] = true
		else:
			for dy in range(min_y, max_y + 1):
				if dy < 0 or dy >= dynamic_grid_height: continue
				var row_offset = dy * grid_width
				for dx in range(min_x, max_x + 1):
					if dx < 0 or dx >= grid_width: continue
					var idx = row_offset + dx
					if door_registry.has(idx):
						triggered_door_cells[idx] = true
				
	# 2. Connected Component Opening: Open entire connected door groups if any part is triggered
	var final_open_cells = {}
	for idx in triggered_door_cells:
		if final_open_cells.has(idx): continue
		var group = _get_connected_door_cells(idx)
		for g_idx in group:
			final_open_cells[g_idx] = true
			
	# 3. Update timers and apply cell changes
	for idx in door_registry:
		var x = idx % grid_width
		var y = idx / grid_width
		
		if idx in final_open_cells:
			# NPC is near -> Open door and set/reset timer to 1.0 second
			door_close_timers[idx] = 1.0
			var tid = cells[idx] & 0xFFFF
			if tid == 91:
				_set_cell(x, y, 0)
		else:
			# NPC not near -> Tick timer down
			var timer = door_close_timers.get(idx, 0.0)
			if timer > 0.0:
				timer -= delta
				door_close_timers[idx] = timer
				# Keep open (clear to Air if it closed early)
				var tid = cells[idx] & 0xFFFF
				if tid == 91:
					_set_cell(x, y, 0)
			else:
				# Timer expired -> Close door (restore to 91)
				var tid = cells[idx] & 0xFFFF
				if tid != 91:
					_set_cell(x, y, 91)
					
	is_npc_door_updating = false

func _shoot_arrow(npc, target):
	if npc.hp <= 0: return
	_play_action_sound("archer_shoot")
	var target_x = float(target.pos.x)
	var target_y = float(target.pos.y)
	if npc == controlled_npc and target.get("hp") != null:
		target_x += _get_lut_rand_range(-10.0, 10.0)
		target_y += _get_lut_rand_range(-6.0, 6.0)
	var dx = target_x - npc.pos.x
	var dir = 1 if (target.pos.x - npc.pos.x) > 0 else -1
	var aim_dy = (target_y + 2.0) - npc.pos.y
	var speed_x = clamp(abs(dx) * 1.5, 90.0, 150.0)
	var vx = dir * speed_x
	var t = abs(dx) / speed_x
	if t < 0.1: t = 0.1
	if !npc.get("morale_broken", false): _set_npc_emoji(npc, "🏹", clamp(t + 0.2, 0.5, 1.5))
	var arrow_gravity = 200.0
	var vy = (aim_dy / t) - (0.5 * arrow_gravity * t)
	vy += npc.get("precision", 0.0) * 15.0
	vy = clamp(vy, -280.0, 40.0)
	active_projectiles.append({ "pos": Vector2(npc.pos.x + dir*2, npc.pos.y + 1), "vel": Vector2(vx, vy), "team": npc.team, "type": "arrow", "life": 2.5, "atk_dmg": npc.get("atk_dmg", 1.0), "is_fire": npc.get("is_fire_variant", false) })

func _shoot_fireball(npc, target):
	if npc.hp <= 0: return
	_play_action_sound("mage_shoot", 0.1, 0.0, 1.4)
	var target_x = float(target.pos.x)
	var target_y = float(target.pos.y)
	if npc == controlled_npc and target.get("hp") != null:
		target_x += _get_lut_rand_range(-10.0, 10.0)
		target_y += _get_lut_rand_range(-6.0, 6.0)
	var dx = target_x - npc.pos.x
	var dir = 1 if (target.pos.x - npc.pos.x) > 0 else -1
	var aim_dy = (target_y + 2.0) - npc.pos.y
	var speed_x = clamp(abs(dx) * 1.2, 70.0, 120.0)
	var vx = dir * speed_x
	var t = abs(dx) / speed_x
	if t < 0.1: t = 0.1
	if !npc.get("morale_broken", false): _set_npc_emoji(npc, "🔥", clamp(t + 0.2, 0.5, 1.5))
	var gravity = 120.0
	var vy = (aim_dy / t) - (0.5 * gravity * t)
	vy = clamp(vy, -220.0, 40.0)
	active_projectiles.append({ "pos": Vector2(npc.pos.x + dir*2, npc.pos.y + 1), "vel": Vector2(vx, vy), "team": npc.team, "type": "fireball", "life": 3.0, "atk_dmg": npc.get("atk_dmg", 1.0), "gravity": gravity, "attacker_id": npc.id })

func _is_npc_suffocating(npc) -> bool:
	return npc.hp > 0 and npc.suffocation_timer > 0.0

func _resolve_npc_overlap(npc):
	# Anti-Stuck / Piston Push Resolution
	# If the NPC is embedded inside a solid block (e.g. pushed by piston or falling sand)
	if not _can_npc_fit(npc.pos.x, npc.pos.y, npc):
		var resolved = false
		# Try moving UP (up to 15 pixels for fast moving pistons or multiple blocks)
		for push in range(1, 15):
			if _can_npc_fit(npc.pos.x, npc.pos.y - float(push), npc):
				npc.pos.y -= float(push)
				resolved = true
				break
		# Try moving sideways
		if not resolved:
			for push in range(1, 6):
				if _can_npc_fit(npc.pos.x + float(push), npc.pos.y, npc):
					npc.pos.x += float(push)
					resolved = true
					break
				elif _can_npc_fit(npc.pos.x - float(push), npc.pos.y, npc):
					npc.pos.x -= float(push)
					resolved = true
					break
		# Try moving DOWN
		if not resolved:
			for push in range(1, 6):
				if _can_npc_fit(npc.pos.x, npc.pos.y + float(push), npc):
					npc.pos.y += float(push)
					resolved = true
					break

func _launch_flying_block(tx: int, ty: int, vx: float, vy: float, team: int = 0, lifetime: float = 2.5, gravity: float = 200.0) -> bool:
	if tx < 0 or tx >= grid_width or ty < 0 or ty >= dynamic_grid_height:
		return false
	var tid = cells[ty * grid_width + tx] & 0xFFFF
	if tid > 0:
		_set_cell(tx, ty, 0)
		active_projectiles.append({
			"pos": Vector2(tx, ty),
			"vel": Vector2(vx, vy),
			"team": team,
			"type": "magic_lifted",
			"life": lifetime,
			"block_material": tid,
			"gravity": gravity
		})
		return true
	return false

func _process_mage_rescue(npc):
	if npc.hp <= 0: return
	
	# If suffocating, self-rescue takes highest priority!
	if _is_npc_suffocating(npc):
		npc["rescue_target"] = npc
		npc["is_rescuing"] = true
	
	# 1. Abort rescue if damaged (except if self-rescuing)
	if npc.hit_flash > 0 and npc.get("rescue_target", null) != null and npc.get("rescue_target") != npc:
		npc["rescue_target"] = null
		npc["is_rescuing"] = false
		_set_npc_emoji(npc, "😡", 1.5)
	
	# 2. Check rescue target validity
	var res_target = npc.get("rescue_target", null)
	if res_target:
		var is_active = false
		if res_target == npc:
			is_active = true
		else:
			for a in active_npcs:
				if a == res_target:
					is_active = true
					break
		if not is_active or res_target.hp <= 0 or not _is_npc_suffocating(res_target):
			npc["rescue_target"] = null
			npc["is_rescuing"] = false
			res_target = null
			
	# 3. If actively rescuing, execute rescue
	if res_target:
		npc["is_rescuing"] = true
		
		# Set face direction towards target
		var look_dir = sign(res_target.pos.x - npc.pos.x)
		if look_dir != 0:
			npc["last_dir"] = look_dir

		# Check horizontal distance
		var h_dist = abs(npc.pos.x - res_target.pos.x)
		if h_dist > 15:
			npc.dir = look_dir
			_set_npc_emoji(npc, "🏃", 0.6)
			return
			
		# Within 15 pixels: stop and channel
		npc.dir = 0
		npc.attack_cooldown = 0.5
		_play_action_sound("mage_rescue", 0.5)
		
		# Alternate emojis
		var alt_emoji = "✨" if int(_ai_tick_count / 10.0) % 2 == 0 else "⬆️"
		_set_npc_emoji(npc, alt_emoji, 0.6)
		
		# Magic lifting
		var th = 6 if (res_target.type == "zombie_tank" or res_target.type == "mage") else 5
		for dx in range(-2, 3):
			var tx = res_target.pos.x + dx
			if tx < 0 or tx >= grid_width: continue
			
			# Scan from 50 blocks above target's head down to their feet to find the topmost block of the dune
			var start_y = max(0, res_target.pos.y - 50)
			for ty in range(start_y, res_target.pos.y + th):
				var tid = cells[ty * grid_width + tx] & 0xFFFF
				if tid > 0:
					var tags = material_tags_raw[_get_tags_id(tid)]
					if (tags & SandboxMaterial.Tags.SOLID) != 0 or (tags & SandboxMaterial.Tags.POWDER) != 0 or (tags & SandboxMaterial.Tags.LIQUID) != 0:
						# Launch projectile upward and push to the sides via the isolated helper function
						var vx = 0.0
						var dx_sign = sign(tx - res_target.pos.x)
						if dx_sign < 0:
							vx = _get_lut_rand_range(-55.0, -25.0)
						elif dx_sign > 0:
							vx = _get_lut_rand_range(25.0, 55.0)
						else:
							vx = _get_lut_rand_range(-40.0, -15.0) if _get_lut_rand() < 0.5 else _get_lut_rand_range(15.0, 40.0)
							
						var vy = _get_lut_rand_range(-150.0, -100.0)
						_launch_flying_block(tx, ty, vx, vy, npc.team, 2.5)
						# Spawn magic sparks (Neon Blue, White, Yellow)
						var spark_colors = [Color("#00EAFF"), Color.WHITE, Color.YELLOW]
						var col = spark_colors[int(_get_lut_rand() * spark_colors.size())]
						_add_spark(float(tx), float(ty), _get_lut_rand_range(-20.0, 20.0), _get_lut_rand_range(-50.0, -20.0), col, 0.5)
						break
		return
		
	# 4. If not rescuing, scan for nearby suffocating allies
	var checked_map = npc.get("checked_rescue_map", {})
	var to_clean = []
	for cid in checked_map:
		var found = false
		for a in active_npcs:
			if a.id == cid and a.hp > 0 and _is_npc_suffocating(a):
				found = true
				break
		if not found:
			to_clean.append(cid)
	for cid in to_clean:
		checked_map.erase(cid)
	npc["checked_rescue_map"] = checked_map
	
	# Scan allies within 160 cells
	var allies = _get_nearby_npcs(npc.pos.x, npc.pos.y, 160.0)
	var has_z = _has_active_zombies()
	var suffocating_allies = []
	for other in allies:
		if other != npc and other.hp > 0 and _is_ally(npc, other, has_z):
			if _is_npc_suffocating(other):
				suffocating_allies.append(other)
				
	if suffocating_allies.size() > 0:
		var closest_ally = suffocating_allies[0]
		var min_d = npc.pos.distance_to(closest_ally.pos)
		for a in suffocating_allies:
			var d = npc.pos.distance_to(a.pos)
			if d < min_d:
				min_d = d
				closest_ally = a
				
		# Evaluate 40% probability roll once per target (decided once per ally lifetime)
		if not checked_map.has(closest_ally.id):
			var decide_rescue = _get_lut_rand() < 0.4
			checked_map[closest_ally.id] = decide_rescue
			
		if checked_map[closest_ally.id]:
			npc["rescue_target"] = closest_ally
			npc["is_rescuing"] = true
			npc.dir = 0
			npc.attack_cooldown = 0.5

func _convert_to_ally(npc, new_team):
	_draw_npc_pixels(npc, 0)
	npc["team"] = new_team
	npc["invul_timer"] = 1.0 # 1s protection to prevent instant friendly-fire death
	_set_npc_emoji(npc, "↪️", 2.0)
	_play_action_sound("medic_heal", 0.08, 0.0, 0.9)
	var team_colors = [Color("#A83938"), Color("#384BA8"), Color("#C79B1E"), Color("#74A838")]
	var spark_color = team_colors[new_team] if (new_team >= 0 and new_team < team_colors.size()) else Color.WHITE
	for _i in range(10):
		_add_spark(float(npc.pos.x) + _get_lut_rand_range(0.0, 2.0), float(npc.pos.y) + _get_lut_rand_range(0.0, 5.0), _get_lut_rand_range(-50.0, 50.0), _get_lut_rand_range(-80.0, -20.0), spark_color, _get_lut_rand_range(0.4, 0.8))
	_draw_npc_pixels(npc)

func _convert_to_zombie(npc):
	_draw_npc_pixels(npc, 0)
	var is_tank = _get_lut_rand() < 0.2
	if is_tank:
		npc["type"] = "zombie_tank"
		npc["max_hp"] = _get_lut_rand_range(280.0, 320.0)
	else:
		npc["type"] = "zombie"
		npc["max_hp"] = _get_lut_rand_range(80.0, 110.0)
	npc["team"] = -1
	npc["hp"] = npc["max_hp"]
	npc["morale_broken"] = false
	npc["is_fleeing"] = false
	npc["social_timer"] = 0.0
	npc["dance_timer"] = 0.0
	npc["zombie_checked"] = true
	npc["has_spotted_enemy"] = false
	npc.current_emoji = ""
	_play_action_sound("damage_npc")
	_set_npc_emoji(npc, "🧟", 2.0)
	for _i in range(12):
		_add_spark(
			float(npc.pos.x) + _get_lut_rand_range(0.0, 2.0),
			float(npc.pos.y) + _get_lut_rand_range(0.0, 5.0),
			_get_lut_rand_range(-60.0, 60.0),
			_get_lut_rand_range(-100.0, -30.0),
			Color("#5D9C36"),
			_get_lut_rand_range(0.4, 0.8)
		)
	_unlock_achievement("patient-zero")

func _process_projectiles(delta):
	var to_remove = []
	for i in range(active_projectiles.size()):
		var p = active_projectiles[i]
		
		# 1. Clear last frame's pixels
		var last_gx = int(p.pos.x); var last_gy = int(p.pos.y)
		if p.type == "thrown_rock":
			var mat = p.get("block_material", 2)
			for ox in range(2):
				for oy in range(2):
					var tx = last_gx + ox; var ty = last_gy + oy
					if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
						var tid = cells[ty * grid_width + tx] & 0xFFFF
						if tid == mat: _set_cell(tx, ty, 0)
		else:
			if last_gx >= 0 and last_gx < grid_width and last_gy >= 0 and last_gy < dynamic_grid_height:
				if p.type != "bomber_bomb" and p.type != "magic_lifted":
					_set_cell(last_gx, last_gy, 0)
				
		# 2. Advance projectile physics
		p.pos += p.vel * delta
		var proj_grav = p.get("gravity", 200.0)
		p.vel.y += proj_grav * delta
		p.life -= delta
		
		var gx = int(p.pos.x); var gy = int(p.pos.y)
		if p.type == "magic_lifted" and p.life <= 0:
			if gx >= 0 and gx < grid_width and gy >= 0 and gy < dynamic_grid_height:
				var mat = p.get("block_material", 1)
				var placed = false
				for oy in range(0, -6, -1):
					var ty = gy + oy
					if ty >= 0 and ty < dynamic_grid_height and _get_cell(gx, ty) == 0:
						_set_cell(gx, ty, mat)
						placed = true
						break
				if not placed:
					_set_cell(gx, gy, mat)
			to_remove.append(i); continue

		if gx < 0 or gx >= grid_width or gy < 0 or gy >= dynamic_grid_height or p.life <= 0:
			to_remove.append(i); continue
			
		if p.type == "fireball":
			if _get_lut_rand() < 0.3:
				_add_spark(float(gx), float(gy), -p.vel.x * 0.2 + _get_lut_rand_range(-10, 10), -p.vel.y * 0.2 + _get_lut_rand_range(-10, 10), Color("#FF8200"), 0.3)
			
		# 3. Check NPC collisions
		var hit_npc = null
		var nearby = _get_nearby_npcs(gx, gy, 12.0)
		var has_z = _has_active_zombies()
		for other in nearby:
			var is_enemy = false
			if p.team == -1:
				is_enemy = (other.team != -1)
			else:
				if has_z:
					is_enemy = (other.type == "zombie" or other.type == "zombie_tank")
				else:
					is_enemy = (other.team != p.team)
					
			if is_enemy and other.hp > 0 and other.invul_timer <= 0:
				var ow = 3 if (other.type == "zombie_tank") else 2
				var oh = 6 if (other.type == "zombie_tank" or other.type == "mage") else 5
				var overlaps = false
				if p.type == "bomber_bomb":
					for ox in range(-1, 1):
						for oy in range(-1, 1):
							var px = gx + ox; var py = gy + oy
							if px >= other.pos.x and px < other.pos.x + ow and py >= other.pos.y and py < other.pos.y + oh:
								overlaps = true; break
						if overlaps: break
				else:
					overlaps = (gx >= other.pos.x and gx < other.pos.x + ow and gy >= other.pos.y and gy < other.pos.y + oh)
					
				if overlaps:
					hit_npc = other; break
					
		if hit_npc:
			if p.type == "thrown_rock":
				_trigger_rock_impact(gx, gy, p)
			elif p.type == "bomber_bomb":
				_explode(gx, gy, p.get("explosion_radius", 6), "explosion", EXP_VOLCANO | 128)
			elif p.type == "fireball":
				var converted = false
				if p.get("team", -1) >= 0 and hit_npc.team != -1 and hit_npc.team != p.team:
					if _get_lut_rand() < 0.05:
						converted = true
						_convert_to_ally(hit_npc, p.team)
						var a_id = p.get("attacker_id", -1)
						if a_id != -1:
							for a_npc in active_npcs:
								if a_npc.id == a_id and a_npc.hp > 0:
									_set_npc_emoji(a_npc, "✨", 2.0)
									break
				if converted:
					_play_action_sound("explosion", 0.08, -12.0, 1.5)
				else:
					hit_npc.hp -= 35.0 * p.get("atk_dmg", 1.0)
					hit_npc.hit_flash = 4
					hit_npc.hit_type = "fire"
					for _j in range(8):
						_add_spark(float(gx), float(gy), _get_lut_rand_range(-50, 50), _get_lut_rand_range(-60, 10), Color("#FF4500"), 0.4)
					if _get_cell(gx, gy) == 0: _set_cell(gx, gy, 3)
					_play_action_sound("explosion", 0.08, -12.0, 1.5)
			else:
				hit_npc.hp -= 40.0 * p.get("atk_dmg", 1.0); hit_npc.hit_flash = 4; hit_npc.hit_type = "normal"
				if p.get("is_fire", false):
					if _get_cell(gx, gy) == 0: _set_cell(gx, gy, 3)
				_play_action_sound("npc_hit")
				for _j in range(5): _add_spark(float(gx), float(gy), _get_lut_rand_range(-40, 40), _get_lut_rand_range(-40, 0), Color.WHITE, 0.3)
			to_remove.append(i); continue
			
		# 4. Check Grid collisions (Solid blocks) with sweep to prevent tunneling
		var collides_block = false
		var hit_gx = gx
		var hit_gy = gy
		var last_empty_gx = last_gx
		var last_empty_gy = last_gy
		
		var sweep_steps = max(1, max(abs(gx - last_gx), abs(gy - last_gy)))
		for s_idx in range(1, sweep_steps + 1):
			var t_fraction = float(s_idx) / sweep_steps
			var tx = int(round(lerp(float(last_gx), float(gx), t_fraction)))
			var ty = int(round(lerp(float(last_gy), float(gy), t_fraction)))
			
			var is_colliding_step = false
			if p.type == "thrown_rock":
				for ox in range(2):
					for oy in range(2):
						var cx = tx + ox; var cy = ty + oy
						if cx >= 0 and cx < grid_width and cy >= 0 and cy < dynamic_grid_height:
							var tid = _get_cell(cx, cy)
							if tid != 0 and tid != 15 and tid != 3 and tid != 17:
								is_colliding_step = true; break
					if is_colliding_step: break
			elif p.type == "bomber_bomb":
				for ox in range(-1, 1):
					for oy in range(-1, 1):
						var cx = tx + ox; var cy = ty + oy
						if cx >= 0 and cx < grid_width and cy >= 0 and cy < dynamic_grid_height:
							if _get_cell(cx, cy) != 0:
								is_colliding_step = true; break
					if is_colliding_step: break
			else:
				var tid = _get_cell(tx, ty)
				if tid != 0 and tid != 15 and tid != 3 and tid != 17:
					is_colliding_step = true
					
			if is_colliding_step:
				collides_block = true
				hit_gx = tx
				hit_gy = ty
				break
			else:
				last_empty_gx = tx
				last_empty_gy = ty
				
		if collides_block:
			gx = hit_gx
			gy = hit_gy
			if p.type == "thrown_rock":
				_trigger_rock_impact(gx, gy, p)
			elif p.type == "bomber_bomb":
				_explode(gx, gy, p.get("explosion_radius", 6), "explosion", EXP_VOLCANO | 128)
			elif p.type == "magic_lifted":
				var mat = p.get("block_material", 1)
				var placed = false
				for oy in range(0, -6, -1):
					var ty = last_empty_gy + oy
					if ty >= 0 and ty < dynamic_grid_height and _get_cell(last_empty_gx, ty) == 0:
						_set_cell(last_empty_gx, ty, mat)
						placed = true
						break
				if not placed:
					_set_cell(last_empty_gx, last_empty_gy, mat)
			elif p.type == "fireball":
				var hit_mat = _get_cell(gx, gy)
				var hit_flammable = false
				if hit_mat > 0:
					var n_tags = material_tags_raw[_get_tags_id(hit_mat)]
					if (n_tags & SandboxMaterial.Tags.FLAMMABLE) != 0:
						hit_flammable = true
				
				if hit_flammable:
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var tx = gx + dx; var ty = gy + dy
							if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
								if _get_cell(tx, ty) == 0:
									_set_cell(tx, ty, 3)
				else:
					var px = gx - int(sign(p.vel.x))
					if px >= 0 and px < grid_width and _get_cell(px, gy) == 0:
						_set_cell(px, gy, 3)
				_play_action_sound("explosion", 0.08, -12.0, 1.5)
			else:
				if p.get("is_fire", false):
					var px = gx - int(sign(p.vel.x))
					if px >= 0 and px < grid_width and _get_cell(px, gy) == 0: _set_cell(px, gy, 3)
			to_remove.append(i); continue
			
		# 5. Draw projectile pixels
		if p.type == "thrown_rock":
			var mat = p.get("block_material", 2)
			for ox in range(2):
				for oy in range(2):
					var tx = gx + ox; var ty = gy + oy
					if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
						if _get_cell(tx, ty) == 0: _set_cell(tx, ty, mat)
		elif p.type == "bomber_bomb":
			pass
		elif p.type == "fireball":
			if _get_cell(gx, gy) == 0:
				_set_cell(gx, gy, 3)
		elif p.type == "magic_lifted":
			pass
		else:
			_set_cell(gx, gy, 1012)
			
	to_remove.reverse()
	for idx in to_remove: active_projectiles.remove_at(idx)

func _trigger_rock_impact(gx, gy, p):
	var mat = p.get("block_material", 2)
	var is_liquid = false
	if _get_tags_id(mat) < material_tags_raw.size():
		is_liquid = (material_tags_raw[_get_tags_id(mat)] & SandboxMaterial.Tags.LIQUID) != 0
		
	if is_liquid:
		# Splash liquid
		var rad = 2
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if dx*dx + dy*dy <= rad*rad:
					var tx = gx + dx; var ty = gy + dy
					if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
						var tid = _get_cell(tx, ty)
						if tid == 0 or tid == 3: # Empty or fire
							_set_cell(tx, ty, mat)
		_play_action_sound("bomb_drop", 0.08, -3.0, 1.5)
	else:
		# 1. Destroy cells in a radius of 3
		var rad = 3
		var _mat_color = mat_colors_1[mat] if mat < mat_colors_1.size() else Color("#717E80")
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if dx*dx + dy*dy <= rad*rad:
					var tx = gx + dx; var ty = gy + dy
					if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
						var tid = _get_cell(tx, ty)
						if tid > 0 and tid != 1:
							_set_cell(tx, ty, 0)
							
	# 2. Damage nearby NPCs in a radius of 18
	var nearby_npcs = _get_nearby_npcs(gx, gy, 18.0)
	var has_z = _has_active_zombies()
	for other in nearby_npcs:
		var is_enemy = false
		if p.team == -1:
			is_enemy = (other.team != -1)
		else:
			if has_z:
				is_enemy = (other.type == "zombie" or other.type == "zombie_tank")
			else:
				is_enemy = (other.team != p.team)
				
		if is_enemy and other.hp > 0 and other.invul_timer <= 0:
			var dist = other.pos.distance_to(Vector2(gx, gy))
			if dist < 18.0:
				var dmg_ratio = 1.0 - (dist / 18.0)
				other.hp -= 50.0 * dmg_ratio * p.get("atk_dmg", 1.0)
				other.hit_flash = 5; other.hit_type = "explosive"
				
	# 3. Sound and particle effects
	if not is_liquid:
		_play_action_sound("explosion", 0.1)
		var mat_color = mat_colors_1[mat] if mat < mat_colors_1.size() else Color("#717E80")
		for _j in range(12):
			_add_spark(float(gx) + _get_lut_rand_range(-1, 2), float(gy) + _get_lut_rand_range(-1, 2), _get_lut_rand_range(-80, 80), _get_lut_rand_range(-100, -30), mat_color if _get_lut_rand() > 0.4 else Color.WHITE, _get_lut_rand_range(0.3, 0.7))

func _find_closest_enemy(me, radar_range):
	var closest = null; var min_dist_sq = radar_range * radar_range
	var nearby = _get_nearby_npcs(me.pos.x, me.pos.y, radar_range)
	var has_zombies = _has_active_zombies()
	for other in nearby:
		if other.hp > 0:
			var is_enemy = not _is_ally(me, other, has_zombies)
			if is_enemy:
				var d_sq = me.pos.distance_squared_to(other.pos)
				if d_sq < min_dist_sq: min_dist_sq = d_sq; closest = other
	return closest

func _find_controlled_aim_target(me, face_dir, radar_range):
	var closest = null; var min_dist_sq = radar_range * radar_range
	var nearby = _get_nearby_npcs(me.pos.x, me.pos.y, radar_range)
	var has_zombies = _has_active_zombies()
	for other in nearby:
		if other.hp > 0 and other != me:
			var is_enemy = not _is_ally(me, other, has_zombies)
			if is_enemy:
				var dx = other.pos.x - me.pos.x
				if dx * face_dir >= -8:
					var d_sq = me.pos.distance_squared_to(other.pos)
					if d_sq < min_dist_sq: min_dist_sq = d_sq; closest = other
	return closest

func _is_zombie(type: String) -> bool:
	return type == "zombie" or type == "zombie_tank"

func _has_active_zombies() -> bool:
	return _cached_has_zombies

func _is_ally(me, other, has_zombies) -> bool:
	if _is_zombie(me.type):
		return _is_zombie(other.type)
	else:
		if has_zombies:
			return not _is_zombie(other.type)
		else:
			return other.team == me.team

func _attack_npc(attacker, victim):
	if attacker.hp <= 0 or victim.hp <= 0: return
	if victim.invul_timer > 0: return # Converted protection
	
	var a_profile = NPC_PROFILES.get(attacker.type, {})
	var hit_emoji = a_profile.get("hit_emoji", "⚔️")
	if !attacker.get("morale_broken", false): _set_npc_emoji(attacker, hit_emoji, 0.5)
	
	var dmg = 15.0 * attacker.get("atk_dmg", 1.0)
	if victim == controlled_npc: dmg *= 0.6 # 40% reduction for the player's controlled NPC
	victim.hp -= dmg; victim.hit_flash = 5; victim.hit_type = "normal"
	if _is_zombie(attacker.type):
		victim["zombie_infected"] = true
	if victim.hp <= 0 and not _is_zombie(victim.type) and _is_zombie(attacker.type):
		_convert_to_zombie(victim)
	if attacker.get("is_fire_variant", false):
		var fx = victim.pos.x + _get_lut_rand_range(0, 1); var fy = victim.pos.y + _get_lut_rand_range(2, 4)
		if fx >= 0 and fx < grid_width and fy >= 0 and fy < dynamic_grid_height:
			if _get_cell(fx, fy) == 0: _set_cell(fx, fy, 3)
	
	_play_action_sound("npc_hit")
	var a_sound = a_profile.get("attack_sound", "warrior_attack")
	var p_scale = 1.0
	if _is_zombie(attacker.type):
		p_scale = 0.65 + float((attacker.id * 23) % 40) / 40.0 * 0.40
	_play_action_sound(a_sound, 0.08, 0.0, p_scale)
	
	var t_colors = [Color.RED, Color("1E90FF"), Color.YELLOW, Color.GREEN]
	var bleed_color = Color("#5D9C36") if _is_zombie(victim.type) else (t_colors[victim.team] if (victim.team < t_colors.size() and victim.team >= 0) else Color.WHITE)
	for _i in range(10): _add_spark(float(victim.pos.x) + _get_lut_rand_range(0, 2), float(victim.pos.y) + _get_lut_rand_range(0, 5), _get_lut_rand_range(-80, 80), _get_lut_rand_range(-120, -30), bleed_color if _get_lut_rand() > 0.4 else Color.WHITE, _get_lut_rand_range(0.3, 0.7))
	var ldir = 1 if attacker.pos.x < victim.pos.x else -1
	for d in range(3, 0, -1):
		var lx = attacker.pos.x + ldir * d; var ly = attacker.pos.y - 1
		if _can_npc_fit(lx, ly, attacker): attacker.pos.x = lx; attacker.pos.y = ly; break
	var push_dir = 1 if attacker.pos.x < victim.pos.x else -1
	if victim.type == "archer": attacker.vx = -push_dir * 3.5; attacker.vy = -4.0
	else:
		if _get_lut_rand() < 0.35: victim.vx = push_dir * _get_lut_rand_range(3.0, 5.0) * attacker.get("knockback_mult", 1.0); victim.vy = _get_lut_rand_range(-4.0, -8.0)

func _check_npc_environment_damage(npc) -> bool:
	if npc.hp <= 0 or npc.invul_timer > 0: return false
	var took_damage = false; var p = npc.pos
	var check_points = [p, p + Vector2i(1, 2), p + Vector2i(0, 4), p + Vector2i(0, 5), p + Vector2i(1, 5), p + Vector2i(-1, 2), p + Vector2i(2, 2)]
	for pt in check_points:
		if pt.x < 0 or pt.x >= grid_width or pt.y < 0 or pt.y >= dynamic_grid_height: continue
		var cell_idx = pt.y * grid_width + pt.x
		var tid = cells[cell_idx] & 0xFFFF
		var t_tags = material_tags_raw[_get_tags_id(tid)]
		var dmg_mult = 0.5 if npc == controlled_npc else 1.0
		if (t_tags & SandboxMaterial.Tags.ACID):
			npc.hp -= 3.5 * dmg_mult; npc.hit_flash = 5; npc.hit_type = "acid"; took_damage = true
			if _get_lut_rand() < 0.4: _add_spark(float(pt.x)+_get_lut_rand_range(-2,2),float(pt.y),_get_lut_rand_range(-10,10),_get_lut_rand_range(-40,-20),Color("#39FF14"),0.6)
		elif (t_tags & SandboxMaterial.Tags.INCENDIARY):
			npc.hp -= 1.2 * dmg_mult; took_damage = true; if npc.hit_type != "acid": npc.hit_flash = 5; npc.hit_type = "fire"
			if _get_lut_rand() < 0.3: _add_spark(float(pt.x),float(pt.y),_get_lut_rand_range(-15,15),_get_lut_rand_range(-35,-15),Color("#FF8200"),0.5)
		
		# Electricity Damage
		if charge_array[cell_idx] > 50:
			npc.hp -= 2.5 * dmg_mult; took_damage = true; npc.hit_flash = 5; npc.hit_type = "electric"
			if _get_lut_rand() < 0.4: _add_spark(float(pt.x),float(pt.y),_get_lut_rand_range(-20,20),_get_lut_rand_range(-40,-10),Color.CYAN,0.4)
	var is_lying = npc.get("is_lying", false)
	var w = 2
	var h = 5
	if npc.type == "zombie_tank":
		w = 3
		h = 6
	elif npc.type == "mage":
		w = 2
		h = 6
		
	var px = npc.pos.x
	var py = npc.pos.y
	
	if is_lying:
		w = 6 if npc.type == "mage" else (6 if npc.type == "zombie_tank" else 5)
		h = 2 if npc.type == "mage" else (3 if npc.type == "zombie_tank" else 2)
		py += 4 if npc.type == "mage" else 3
		
	var air_found = false
	
	var check_powered_pb = func(row_off: int, col_x: int) -> bool:
		var idx = row_off + col_x
		if charge_array[idx] > 0: return true
		var px2 = idx % grid_width
		var py2 = int(idx / float(grid_width))
		if px2 > 0 and (charge_array[idx - 1] > 0 or active_battery_indices.has(idx - 1)): return true
		if px2 < grid_width - 1 and (charge_array[idx + 1] > 0 or active_battery_indices.has(idx + 1)): return true
		if py2 > 0 and (charge_array[idx - grid_width] > 0 or active_battery_indices.has(idx - grid_width)): return true
		if py2 < dynamic_grid_height - 1 and (charge_array[idx + grid_width] > 0 or active_battery_indices.has(idx + grid_width)): return true
		return false
	
	# 1. Check top row (above head/lying body)
	var ty_top = py - 1
	if ty_top >= 0:
		var row_offset = ty_top * grid_width
		for ox in range(w):
			var tx = px + ox
			if tx >= 0 and tx < grid_width:
				var nid = cells[row_offset + tx] & 0xFFFF
				if nid == 0 or nid == 15 or nid == 17:
					air_found = true; break
				if nid == 92 and check_powered_pb.call(row_offset, tx):
					air_found = true; break
				var tags = material_tags_raw[_get_tags_id(nid)]
				if (tags & SandboxMaterial.Tags.SOLID) == 0 and (tags & SandboxMaterial.Tags.POWDER) == 0 and (tags & SandboxMaterial.Tags.LIQUID) == 0:
					air_found = true; break
					
	if not air_found:
		# 2. Check left and right side columns of head/lying body (only upper part for standing)
		var check_h = h if is_lying else min(3, h)
		for oy in range(check_h):
			var ty = py + oy
			if ty >= 0 and ty < dynamic_grid_height:
				var row_offset = ty * grid_width
				# Left
				var tx_l = px - 1
				if tx_l >= 0:
					var nid = cells[row_offset + tx_l] & 0xFFFF
					if nid == 0 or nid == 15 or nid == 17:
						air_found = true; break
					if nid == 92 and check_powered_pb.call(row_offset, tx_l):
						air_found = true; break
					var tags = material_tags_raw[_get_tags_id(nid)]
					if (tags & SandboxMaterial.Tags.SOLID) == 0 and (tags & SandboxMaterial.Tags.POWDER) == 0 and (tags & SandboxMaterial.Tags.LIQUID) == 0:
						air_found = true; break
				# Right
				var tx_r = px + w
				if tx_r < grid_width:
					var nid = cells[row_offset + tx_r] & 0xFFFF
					if nid == 0 or nid == 15 or nid == 17:
						air_found = true; break
					if nid == 92 and check_powered_pb.call(row_offset, tx_r):
						air_found = true; break
					var tags = material_tags_raw[_get_tags_id(nid)]
					if (tags & SandboxMaterial.Tags.SOLID) == 0 and (tags & SandboxMaterial.Tags.POWDER) == 0 and (tags & SandboxMaterial.Tags.LIQUID) == 0:
						air_found = true; break
	if !air_found: 
		var suff_dmg = 3.0; if npc == controlled_npc: suff_dmg = 1.0
		npc.hp -= suff_dmg; npc.hit_flash = 4; took_damage = true
		npc.suffocation_timer = 2.0
	else:
		if npc.suffocation_timer > 0:
			npc.suffocation_timer = max(0.0, npc.suffocation_timer - 0.5)
	if took_damage: _play_action_sound("damage_npc", 0.4)
	return took_damage

func _set_npc_emoji(npc, emoji_text: String, duration: float = 2.0):
	if npc.current_emoji == emoji_text: return # Avoid spamming same emoji
	npc.current_emoji = emoji_text
	npc.emoji_timer = duration

func _can_npc_fit(gx, gy, moving_npc = null) -> bool:
	var w = 2
	var h = 5
	if moving_npc != null:
		if moving_npc.type == "zombie_tank":
			w = 3
			h = 6
		elif moving_npc.type == "mage":
			w = 2
			h = 6
		
	if gx < 0 or gx + w - 1 >= grid_width or gy < 0 or gy + h - 1 >= dynamic_grid_height: return false
	
	# Chequeo de píxeles: Ignorar Plantas y NPCs para fluidez
	for oy in range(h):
		var row_offset = (gy + oy) * grid_width
		for ox in range(w):
			var tid = cells[row_offset + gx + ox] & 0xFFFF
			if tid != 0 and tid != 15 and tid != 3 and tid != 17:
				if tid == 90 or tid == 91:
					continue
				if tid == 92:
					var idx = row_offset + gx + ox
					var is_pb_powered = false
					var px = idx % grid_width
					var py = int(idx / float(grid_width))
					if charge_array[idx] > 0:
						is_pb_powered = true
					else:
						if px > 0 and (charge_array[idx - 1] > 0 or active_battery_indices.has(idx - 1)):
							is_pb_powered = true
						elif px < grid_width - 1 and (charge_array[idx + 1] > 0 or active_battery_indices.has(idx + 1)):
							is_pb_powered = true
						elif py > 0 and (charge_array[idx - grid_width] > 0 or active_battery_indices.has(idx - grid_width)):
							is_pb_powered = true
						elif py < dynamic_grid_height - 1 and (charge_array[idx + grid_width] > 0 or active_battery_indices.has(idx + grid_width)):
							is_pb_powered = true
					if is_pb_powered:
						continue
				# Si es sólido, pero es una PLANTA, permitimos el paso (los soldados las pisan/atraviesan)
				var tags = material_tags_raw[_get_tags_id(tid)]
				if (tags & SandboxMaterial.Tags.PLANT): continue
				if !(tags & SandboxMaterial.Tags.NPC): return false
				
	# Chequeo de lista de NPCs: Ignorar aliados para evitar atascos de grupo
	if moving_npc != null:
		var nearby = _get_nearby_npcs(gx, gy, 15.0)
		var has_z = _has_active_zombies()
		for other in nearby:
			if other == moving_npc: continue
			# Regla de oro: Aliados no se estorban
			if _is_ally(moving_npc, other, has_z): continue 
			
			var ow = 3 if (other.type == "zombie_tank") else 2
			var oh = 6 if (other.type == "zombie_tank" or other.type == "mage") else 5
			if gx < other.pos.x + ow and gx + w > other.pos.x and gy < other.pos.y + oh and gy + h > other.pos.y: return false
	return true

func _has_tag_neighbor(x, y, tag):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var nid = _get_cell(nx, ny)
			if nid > 0 and (material_tags_raw[_get_tags_id(nid)] & tag): return true
	return false

func _has_tag_within_oval(x, y, tag, rx, ry):
	for oy in range(-ry, ry + 1, 3): 
		for ox in range(-rx, rx + 1, 3):
			if (float(ox*ox)/(rx*rx) + float(oy*oy)/(ry*ry)) <= 1.0:
				var nid = _get_cell(x + ox, y + oy)
				if nid > 0 and (material_tags_raw[_get_tags_id(nid)] & tag): return true
	return false

func _precalculate_optimization_tables():
	# 1. Neighbor Offsets (3x3 relative indices)
	neighbor_offsets = PackedInt32Array([
		-grid_width - 1, -grid_width, -grid_width + 1,
		-1, 1,
		grid_width - 1, grid_width, grid_width + 1
	])
	
	# 2. Oval Lookups (Offsets to the center)
	# Increased ranges (20x10 and 16x8) with larger steps (5px) for high-performance ecology
	oval_lookup_10x5 = _get_oval_offsets(10, 5, 3) # Fine search
	oval_lookup_20x10 = _get_oval_offsets(20, 10, 5) # Wide search (Water)
	oval_lookup_16x8 = _get_oval_offsets(16, 8, 4) # Medium search

func _get_oval_offsets(rx: int, ry: int, step: int) -> PackedInt32Array:
	var offsets = PackedInt32Array()
	var rx_sq = float(rx * rx)
	var ry_sq = float(ry * ry)
	for oy in range(-ry, ry + 1):
		var row_offset = oy * grid_width
		var oy_norm = float(oy * oy) / ry_sq
		for ox in range(-rx, rx + 1):
			if (float(ox * ox) / rx_sq + oy_norm) <= 1.0:
				var dist_sq = ox * ox + oy * oy
				# Dense core (radius 4) or matches the sparse step
				if dist_sq <= 16 or (abs(ox) % step == 0 and abs(oy) % step == 0):
					offsets.append(row_offset + ox)
	return offsets

func _has_id_in_lookup(idx: int, target_id: int, lookup: PackedInt32Array) -> bool:
	var cx = idx % grid_width
	for offset in lookup:
		var n_idx = idx + offset
		if n_idx >= 0 and n_idx < cells.size():
			if grid_width > 0 and abs(cx - (n_idx % grid_width)) <= 30:
				if n_idx < cells.size(): # Double check for race conditions
					if (cells[n_idx] & 0xFFFF) == target_id: return true
	return false

func _count_neighbor_id_fast(idx: int, target_id: int) -> int:
	var x = idx % grid_width
	var y = int(idx / float(grid_width))
	var count = 0
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			if _get_cell(nx, ny) == target_id: count += 1
	return count

func _has_id_within_oval(x, y, target_id, rx, ry):
	# ULTRA-OPTIMIZED: Use larger steps (4px) and avoid float math if possible
	var rx_sq = float(rx * rx)
	var ry_sq = float(ry * ry)
	for oy in range(-ry, ry + 1, 4): 
		var row_idx = (y + oy) * grid_width
		if row_idx < 0 or row_idx >= cells.size(): continue
		var oy_sq_norm = float(oy * oy) / ry_sq
		for ox in range(-rx, rx + 1, 4):
			if (float(ox * ox) / rx_sq + oy_sq_norm) <= 1.0:
				var target_x = x + ox
				if target_x >= 0 and target_x < grid_width:
					if (cells[row_idx + target_x] & 0xFFFF) == target_id: return true
	return false

func _consume_neighbor_tag(x, y, tag):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var nid = _get_cell(nx, ny)
			if nid > 0 and (material_tags_raw[_get_tags_id(nid)] & tag): _set_cell(nx, ny, 0); return true
	return false

func _count_neighbor_id(x, y, id):
	var count = 0
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			if _get_cell(nx, ny) == id: count += 1
	return count

func _count_neighbor_id_radius(x, y, id, radius):
	var count = 0
	for ny in range(y - radius, y + radius + 1):
		for nx in range(x - radius, x + radius + 1):
			if nx == x and ny == y: continue
			if _get_cell(nx, ny) == id: count += 1
	return count

func _prime_explosive(x, y, id, manual_flags = -1):
	if x < 0 or x >= grid_width or y < 0 or y >= grid_height: return
	var idx = y * grid_width + x; var current_id = cells[idx] & 0xFFFF
	
	# Prevent resetting the timer if it's already primed
	if charge_array[idx] > 0: return
	
	# Handle legacy already primed cells or Volcano states (Volcanos handle their own activation)
	if current_id == 7 or current_id == 77 or current_id == 71 or current_id == 72: return 
	if id == 27 or id == 28 or id == 29: return
	
	# Determine explosion type
	var m_tags = material_tags_raw[_get_tags_id(id)]
	if (m_tags & SandboxMaterial.Tags.INVINCIBLE): return
	var ignition_flags = 0
	
	# --- CODE A MEDIDA (Official dynamic behavior) ---
	# For TNT (5) and Gunpowder (20), we allow the trigger to change the explosion type
	if id == 5 or id == 20:
		if manual_flags != -1: ignition_flags = manual_flags
	else:
		# For Laboratory materials, we follow tags 100% for predictability
		# Stackable explosions
		if (m_tags & SandboxMaterial.Tags.EXP_ACID): ignition_flags |= 64
		if (m_tags & SandboxMaterial.Tags.EXP_ELECTRIC): ignition_flags |= 128
		if (m_tags & SandboxMaterial.Tags.EXP_WATER): ignition_flags |= 256
		if (m_tags & SandboxMaterial.Tags.EXP_LAVA): ignition_flags |= 512
		if (m_tags & SandboxMaterial.Tags.EXP_NPC): ignition_flags |= 1024
		if (m_tags & SandboxMaterial.Tags.EXP_LIFE): ignition_flags |= 2048
		if (m_tags & SandboxMaterial.Tags.EXP_GAS): ignition_flags |= 131072
		if (m_tags & SandboxMaterial.Tags.EXP_QUAKE): ignition_flags |= 262144
		if (m_tags & SandboxMaterial.Tags.EXP_PINATA): ignition_flags |= 524288
		
		# Team flags (Corrected 0-indexed IDs)
		if (m_tags & SandboxMaterial.Tags.EXP_TEAM_RED): ignition_flags |= 4096
		elif (m_tags & SandboxMaterial.Tags.EXP_TEAM_BLUE): ignition_flags |= 8192
		elif (m_tags & SandboxMaterial.Tags.EXP_TEAM_GREEN): ignition_flags |= 16384
		elif (m_tags & SandboxMaterial.Tags.EXP_TEAM_YELLOW): ignition_flags |= 32768
		
		# Separate bit for mixed mode
		if (m_tags & SandboxMaterial.Tags.EXP_TEAM_MIXED): ignition_flags |= 65536
	
	charge_array[idx] = 40 | ignition_flags
	charge_visual_buffer[idx] = 160 # Bright priming glow

func _trigger_electric_devices(x, y):
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var n_id = _get_cell(nx, ny)
			if n_id > 0 and (material_tags_raw[_get_tags_id(n_id)] & SandboxMaterial.Tags.ELECTRIC_ACTIVATED): _prime_explosive(nx, ny, n_id)

func _check_neighbors_for_reaction(x, y, is_heat):
	var my_id = _get_cell(x, y)
	for ny in range(y - 1, y + 2):
		for nx in range(x - 1, x + 2):
			if nx == x and ny == y: continue
			var n_id = _get_cell(nx, ny)
			if n_id > 0:
				var n_idx = ny * grid_width + nx; var n_tags = material_tags_raw[_get_tags_id(n_id)]
				if (my_id == 11 and n_id == 2) or (my_id == 2 and n_id == 11): _set_cell(x, y, 12); _set_cell(nx, ny, 12); return
				var my_tags = tags_array[y * grid_width + x]
				if (my_tags & SandboxMaterial.Tags.ACID):
					# If neighbor is NOT empty and NOT acid and NOT anti-acid
					if n_id > 0 and n_id != 13 and !(n_tags & SandboxMaterial.Tags.ANTI_ACID):
						if _get_lut_rand() < 0.6: # Faster melting speed
							_set_cell(nx, ny, 0) # Dissolve neighbor
							if _get_lut_rand() < 0.05: _set_cell(x, y, 0)
							return
				if is_heat:
					if (n_tags & SandboxMaterial.Tags.FLAMMABLE):
						if n_id == 14: continue
						if _get_lut_rand() < 0.8:
							if n_id == 18: _set_cell(nx, ny, 19); charge_array[n_idx] = int(_get_lut_rand_range(20, 70))
							elif (n_tags & SandboxMaterial.Tags.BURN_COAL): _set_cell(nx, ny, 14 if _get_lut_rand() < 0.5 else 3)
							elif (n_tags & SandboxMaterial.Tags.BURN_SMOKE):
								if _get_cell(nx, ny - 1) == 0: _set_cell(nx, ny - 1, 15)
								if _get_lut_rand() < 0.1: _set_cell(nx, ny, 3)
								else: _set_cell(nx, ny, 0)
							else: _set_cell(nx, ny, 3)
					elif (n_tags & SandboxMaterial.Tags.EXPLOSIVE):
						if n_id == 27: _set_cell(nx, ny, 29); charge_array[nx + ny * grid_width] = int(_get_lut_rand_range(80, 120))
						elif n_id == 18: _set_cell(nx, ny, 19); charge_array[n_idx] = int(_get_lut_rand_range(20, 70))
						else:
							# Trigger check: If I am electricity, neighbor MUST be ELECTRIC_ACTIVATED
							var source_is_elec = (my_id == 9 or (my_tags & SandboxMaterial.Tags.ELECTRICITY))
							var source_is_acid = (my_tags & SandboxMaterial.Tags.ACID)
							
							if not source_is_elec or (n_tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED):
								# Pass the correct trigger type (128 for elec, 64 for acid) so TNT knows what effect to use
								var t_flag = -1
								if source_is_elec: t_flag = 128
								elif source_is_acid: t_flag = 64
								_prime_explosive(nx, ny, n_id, t_flag)
				else:
					if (n_tags & SandboxMaterial.Tags.CONDUCTOR) and charge_array[n_idx] == 0: charge_array[n_idx] = 101
					elif (n_tags & SandboxMaterial.Tags.ELECTRIC_ACTIVATED):
						if n_id == 27: _set_cell(nx, ny, 29); charge_array[n_idx] = int(_get_lut_rand_range(80, 120))
						elif n_id == 18: _set_cell(nx, ny, 19); charge_array[n_idx] = int(_get_lut_rand_range(20, 70))
						else:
							_prime_explosive(nx, ny, n_id)

# Optimization #6: Explosion Budgeting (Prevents CPU choking during chain reactions)
const MAX_EXPLOSIONS_PER_FRAME = 20 # SANE default for smooth experience
var explosions_this_frame = 0
var _explosion_queue = [] # Queue of [x, y, radius, sfx, flags]

# Audio Optimization: SFX Budgeting (Max 30 explosion sounds per second)
var explosions_sfx_budget = 0
var explosions_sfx_timer = 0.0

func _explode(x, y, radius, sfx_action: String = "explosion", ignition_flags = 0, ___ignore_budget = false, volume_boost: float = 0.0, skip_physics: bool = false):
	sim_mutex.lock()
	explosions_this_frame += 1
	var is_heavy_load = explosions_this_frame > 10
	sim_mutex.unlock()
	
	if not skip_physics:
		# CLEAR the trigger cell immediately
		_set_cell(x, y, 0)
	
	# Wake up chunks around explosion for C++ particles (Sparks, Drops, etc)
	var effect_radius = int(radius) + 15
	var start_cy = max(0, (y - effect_radius) / 8)
	var end_cy = min(chunks_y - 1, (y + effect_radius) / 8)
	var start_cx = max(0, (x - effect_radius) / 8)
	var end_cx = min(chunks_x - 1, (x + effect_radius) / 8)
	for cy in range(start_cy, end_cy + 1):
		for cx in range(start_cx, end_cx + 1):
			var c_idx = cy * chunks_x + cx
			if c_idx >= 0 and c_idx < next_chunks_active.size():
				next_chunks_active[c_idx] = 60
				chunks_active[c_idx] = 60
	
	# Limit sound spam: Only play sound if budget allows and ONCE per frame for chain reactions
	if explosions_this_frame == 1 and explosions_sfx_budget < 30:
		_play_action_sound(sfx_action, 0.08, volume_boost)
		explosions_sfx_budget += 1
	var center = Vector2i(x, y)
	var nearby = _get_nearby_npcs(x, y, radius + 5)
	for npc in nearby:
		if npc.invul_timer > 0: continue
		var dist = Vector2(npc.pos).distance_to(Vector2(center))
		if dist < radius:
			var ratio = 1.0 - (dist / radius)
			var exp_dmg = ratio * 120.0
			if npc == controlled_npc: exp_dmg *= 0.5 # 50% explosion reduction
			npc.hp -= exp_dmg; npc.hit_flash = 12; npc.hit_type = "explosive"
			var blast_dir = (Vector2(npc.pos) - Vector2(center)).normalized()
			if blast_dir.length() < 0.1: blast_dir = Vector2.UP
			npc.vx = blast_dir.x * ratio * 15.0; npc.vy = blast_dir.y * ratio * 15.0 - 6.0
			for _s in range(5): _add_spark(float(npc.pos.x),float(npc.pos.y),_get_lut_rand_range(-50,50),_get_lut_rand_range(-80,0),Color.DARK_GRAY,0.6)
	if not skip_physics:
		# Pixel clearance, physics push, and standard drops (Restored for dynamic projectiles like Bombs)
		var r2 = radius * radius
		for ry in range(-radius, radius + 1):
			for rx in range(-radius, radius + 1):
				var dist_sq = rx * rx + ry * ry
				if dist_sq <= r2:
					var tx = x + rx
					var ty = y + ry
					if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
						var raw_id = cells[ty * grid_width + tx]
						var tid = raw_id & 0xFFFF
						if tid > 0:
							var t_tags = 0 if tid >= material_tags_raw.size() else material_tags_raw[_get_tags_id(tid)]
							if t_tags & SandboxMaterial.Tags.INVINCIBLE: continue
							
							if t_tags & SandboxMaterial.Tags.EXPLOSIVE:
								if tid == 7 or tid == 71 or tid == 72 or tid == 77 or tid == 19: continue
								if tid == 18:
									_set_cell(tx, ty, 19)
									charge_array[ty * grid_width + tx] = (20 + int(_get_lut_rand() * 30)) | ignition_flags
								else:
									_set_cell(tx, ty, 7 if tid == 5 else 71)
									charge_array[ty * grid_width + tx] = (25 + int(_get_lut_rand() * 20)) | ignition_flags
								continue
								
							if dist_sq < (r2 * 0.16):
								_set_cell(tx, ty, 0)
							else:
								if ignition_flags & (128 | EXP_VOLCANO):
									# VOLCANO EFFECT
									var prob = 0.5 - (float(dist_sq) / float(r2)) * 0.5
									if _get_lut_rand() < prob:
										var push_dist = 1.0 + _get_lut_rand() * 4.0
										var len_f = sqrt(float(dist_sq))
										if len_f == 0.0: len_f = 1.0
										var nx = tx + int(float(rx) * push_dist / len_f)
										var ny = ty + int(float(ry) * push_dist / len_f)
										if nx >= 0 and nx < grid_width and ny >= 0 and ny < dynamic_grid_height:
											if _get_cell(nx, ny) == 0:
												_swap_cells(tx, ty, nx, ny)
											else:
												_set_cell(tx, ty, 0)
										else:
											_set_cell(tx, ty, 0)
								else:
									# CLASSIC EFFECT
									var prob = 1.0 - (float(dist_sq) / float(r2))
									if _get_lut_rand() < prob:
										_set_cell(tx, ty, 0)
									
	# Dynamic sparks based on ignition_flags
	var spark_id = -1
	if ignition_flags & 128: spark_id = 43 # Electric sparks
	elif ignition_flags & 64: spark_id = 44 # Acid splash
	
	if spark_id != -1:
		var spark_count = 15 if is_heavy_load else 30
		for _i in range(spark_count):
			var ang = _get_lut_rand() * TAU
			var s_dist = 2.0 + _get_lut_rand() * 5.0
			var sx = x + int(cos(ang) * s_dist)
			var sy = y + int(sin(ang) * s_dist)
			if sx >= 0 and sx < grid_width and sy >= 0 and sy < dynamic_grid_height:
				if _get_cell(sx, sy) == 0:
					_set_cell(sx, sy, spark_id)
					var deg = int(ang * 180.0 / PI)
					if deg < 0: deg += 360
					var dir_idx = int((deg + 112.5) / 45.0) % 8
					charge_array[sy * grid_width + sx] = ((60 + int(_get_lut_rand() * 40)) << 3) | dir_idx

	# Add burning smoke for Lava/Normal explosions
	var smoke_count = 15
	if ignition_flags & 128: smoke_count = 12 # 50% less smoke for electric explosion
	elif ignition_flags & 64: smoke_count = 25 # Acid smoke
	elif ignition_flags == 0: smoke_count = 8 # Less smoke for normal fire explosion
	for i in range(smoke_count):
		var smx = x + int(_get_lut_rand_range(-radius, radius)); var smy = y + int(_get_lut_rand_range(-radius, radius))
		if smx >= 0 and smx < grid_width and smy >= 0 and smy < dynamic_grid_height:
			if _get_cell(smx, smy) == 0: _set_cell(smx, smy, 15)
				
	# 5. NPC SPASH (Bit 1024)
	if ignition_flags & 1024:
		# Determine base team from flags (Corrected index for user's game order)
		var target_team = selected_team # Fallback to current
		if ignition_flags & 4096: target_team = 0    # Red
		elif ignition_flags & 8192: target_team = 1  # Blue
		elif ignition_flags & 16384: target_team = 3 # Green (Changed)
		elif ignition_flags & 32768: target_team = 2 # Yellow (Changed)
		
		var npc_total = 3 if is_heavy_load else 8
		for i in range(npc_total):
			var final_team = target_team
			if ignition_flags & 65536: final_team = int(_get_lut_rand_range(0, 3)) # Mixed 0-3 
			
			var ang = _get_lut_rand() * TAU; var dist = _get_lut_rand_range(radius, radius + 5)
			var nx = x + int(cos(ang) * dist); var ny = y + int(sin(ang) * dist)
			if nx >= 0 and nx < grid_width and ny >= 0 and ny < dynamic_grid_height:
				var npc = _spawn_explosion_npc(nx, ny, final_team)
				if npc: 
					npc.vx = cos(ang) * 15.0; npc.vy = sin(ang) * 15.0 # Launch them away!

	# 6. LIFE EXPLOSION (Bit 2048)
	if ignition_flags & 2048:
		for i in range(40 if is_heavy_load else 90):
			var dist = _get_lut_rand_range(radius * 0.45, radius + 5); var ang = _get_lut_rand() * TAU
			var sx = x + int(cos(ang) * dist); var sy = y + int(sin(ang) * dist)
			if sx >= 0 and sx < grid_width and sy >= 0 and sy < dynamic_grid_height:
				if _get_cell(sx, sy) == 0:
					var rand = _get_lut_rand()
					if rand < 0.5: _set_cell(sx, sy, 6) # Fertile Soil
					elif rand < 0.8: _set_cell(sx, sy, 22) # Plant Seeds/Grass
					else: _set_cell(sx, sy, 2) # A bit of water for the plants
	
	# 7. SMOKE / GAS EXPLOSION (Bit 131072)
	if ignition_flags & 131072:
		var count = 60 if is_heavy_load else 150
		for i in range(count):
			var dist = _get_lut_rand_range(radius * 0.4, radius + 15); var ang = _get_lut_rand() * TAU
			var sx = x + int(cos(ang) * dist); var sy = y + int(sin(ang) * dist)
			if sx >= 0 and sx < grid_width and sy >= 0 and sy < dynamic_grid_height:
				if _get_cell(sx, sy) == 0: _set_cell(sx, sy, 15) # Smoke ID

	# 8. SEISMIC EXPLOSION (Bit 262144)
	if ignition_flags & 262144:
		earthquake_intensity = 3 # Trigger a medium quake
		earthquake_timer = 2.0 # Shake for 2 seconds

	# 9. PIÑATA / FIREWORKS (Bit 524288)
	if ignition_flags & 524288:
		for i in range(6):
			var ang = _get_lut_rand() * TAU
			var px = x + int(cos(ang) * radius)
			var py = y + int(sin(ang) * radius)
			if _get_lut_rand() < 0.5:
				_launch_firework(px, py) # 50% Launch
			else:
				var color = Color.from_hsv(_get_lut_rand(), 0.8, 1.0)
				_explode_firework(px, py, color) # 50% Burst

func _push_particle(x, y, dx, dy):
	var dir_x = sign(dx); var dir_y = -1 if dy < 0 else (1 if dy > 0 else 0)
	var tx = x + dir_x * 2; var ty = y + dir_y * 2
	if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
		if _get_cell(tx, ty) == 0: _swap_cells(x, y, tx, ty)

func _update_texture():
	# 1. Update Tornado Parameters
	var s_mat = texture_rect.material as ShaderMaterial
	if s_mat:
		s_mat.set_shader_parameter("tornado_x", float(tornado_x))
		s_mat.set_shader_parameter("tornado_ground_y", float(tornado_ground_y))
		s_mat.set_shader_parameter("tornado_intensity", float(tornado_intensity))
		
	# 2. BULK DATA TRANSFER (Cells -> Raw Bytes)
	var raw_data = cells.to_byte_array()
	
	# 3. OPTIMIZED VISUAL OVERLAY (Write directly to raw_data buffer)
	# This is MUCH faster than img.set_pixel()
	if vs_ptr > 0 or active_fireworks.size() > 0:
		# Visual sparks processing
		for i in range(MAX_VISUAL_SPARKS):
			var life = vs_life[i]
			if life <= 0.2: continue
			var sx = int(vs_x[i]); var sy = int(vs_y[i])
			if sx >= 0 and sx < grid_width and sy >= 0 and sy < grid_height:
				var sc = vs_color[i]
				sc.a = life
				sc.b = max(0.02, sc.b) # Hybrid shader marker
				var color_u32 = sc.to_abgr32()
				raw_data.encode_u32((sy * grid_width + sx) * 4, color_u32)
				
		for fw in active_fireworks:
			var fx = int(fw.x); var fy = int(fw.y)
			if fx >= 0 and fx < grid_width and fy >= 0 and fy < grid_height:
				var fc = fw.color
				fc.b = max(0.02, fc.b)
				raw_data.encode_u32((fy * grid_width + fx) * 4, fc.to_abgr32())
	
	# Update persistent image object (Thread-safe for RenderingServer)
	var new_img = Image.create_from_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, raw_data)
	_img_history.append(new_img)
	texture_rect.texture.update(new_img)
	img = new_img
	
	# 4. CONDITIONAL AUXILIARY UPDATES
	# Only update charge texture if there are active charges OR if something changed (decay/movement)
	if active_charge_indices.size() > 0 or charge_dirty or _frame_count % 60 == 0:
		var new_charge_img = Image.create_from_data(grid_width, grid_height, false, Image.FORMAT_L8, charge_visual_buffer.duplicate())
		_img_history.append(new_charge_img)
		charge_tex.update(new_charge_img)
		charge_img = new_charge_img
		charge_dirty = false
	
	# Only update paint texture if dirty or actively painting
	if is_paint_tool_active or element_paint_dirty:
		var new_paint_img = Image.create_from_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, cell_paint_colors.to_byte_array())
		_img_history.append(new_paint_img)
		element_paint_tex.update(new_paint_img)
		element_paint_img = new_paint_img
		element_paint_dirty = false
	
	if background_dirty:
		var new_bg_img = Image.create_from_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, background_img.get_data())
		_img_history.append(new_bg_img)
		background_tex.update(new_bg_img)
		background_img = new_bg_img
		background_dirty = false
		
	while _img_history.size() > 16:
		_img_history.pop_front()

func _launch_firework(x, y):
	sim_mutex.lock()
	_set_cell(x, y, 0) # Clear the station
	_play_action_sound("firework_launch")
	# Neon Palette for launch selection
	var neon_colors = [Color("#00FFFF"), Color("#FF00FF"), Color("#00FF00"), Color("#FFFF00"), Color("#FFFFFF")]
	var fw = {
		"x": float(x),
		"y": float(y),
		"target_y": max(15, y - _get_lut_rand_range(60, 250)), # Absolute ceiling margin
		"color": neon_colors[randi() % neon_colors.size()] # Lock color at launch!
	}
	active_fireworks.append(fw)
	sim_mutex.unlock()

func _update_active_fireworks(delta):
	if active_fireworks.size() > 0:
		_manage_looping_player(ascent_player, "firework_ascent")
	else:
		if ascent_player.playing: ascent_player.stop()

	var to_remove = []
	for i in range(active_fireworks.size()):
		var fw = active_fireworks[i]
		fw.y -= 125.0 * delta # Half speed (125 instead of 250)
		
		# Sutil trail (Visual Sparks instead of physical Smoke)
		if _get_lut_rand() < 0.6:
			var ptr = _lut_state[0]
			var trail_colors = [Color.GRAY, Color.YELLOW, Color.WHITE, Color.GOLD]
			_add_spark(
				float(fw.x) + _get_lut_rand_range(-1.2, 1.2), 
				float(fw.y + 1), 
				(random_lut[(ptr+1)%LUT_SIZE] - 0.5) * 20.0, # -10 to 10
				20.0 + random_lut[(ptr+2)%LUT_SIZE] * 30.0,  # 20 to 50
				trail_colors[int(_get_lut_rand() * 1000000) % trail_colors.size()], 
				0.2 + random_lut[(ptr+3)%LUT_SIZE] * 0.4    # 0.2 to 0.6
			)
			_lut_state[0] = (ptr + 4) % LUT_SIZE
			
		# Check if reached altitude or safe boundary
		if fw.y <= fw.target_y or fw.y < 15:
			_explode_firework(int(fw.x), int(fw.y), fw.color) # Use the locked color!
			to_remove.append(i)
	
	to_remove.reverse()
	for i in to_remove:
		active_fireworks.remove_at(i)

func _add_spark(px, py, p_vx, p_vy, p_color, p_life):
	sim_mutex.lock()
	vs_x[vs_ptr] = px; vs_y[vs_ptr] = py; vs_vx[vs_ptr] = p_vx; vs_vy[vs_ptr] = p_vy
	vs_color[vs_ptr] = p_color; vs_life[vs_ptr] = p_life
	vs_ptr = (vs_ptr + 1) % MAX_VISUAL_SPARKS
	sim_mutex.unlock()

func _update_visual_sparks(delta):
	# OPTIMIZATION: Process only active sparks with cached life
	for i in range(MAX_VISUAL_SPARKS):
		var l = vs_life[i]
		if l <= 0: continue
		
		vs_x[i] += vs_vx[i] * delta
		vs_y[i] += vs_vy[i] * delta
		vs_vy[i] += 30.0 * delta
		
		l -= 1.3 * delta
		vs_life[i] = l

func _explode_firework(ex, ey, color):
	_play_action_sound("firework_burst")
	# Randomized explosion scale (Reduced max to 1/3 of previous)
	var size_mult = _get_lut_rand_range(0.4, 0.9) 
	var spark_count = int(100 * size_mult)  # High density!
	var p_color = (Color.WHITE if color == Color.BLACK else color)
	
	# Create GHOST particles (Visual only) 
	for i in range(spark_count):
		# Decouple indices to avoid spiral shapes (Cardioids)
		var angle_idx = (_lut_state[0] + i) % LUT_SIZE
		var force_idx = (_lut_state[0] + i + 500) % LUT_SIZE
		var life_idx = (_lut_state[0] + i + 1000) % LUT_SIZE
		
		var f_cos = cos_lut[angle_idx]
		var f_sin = sin_lut[angle_idx]
		var force = (20.0 + random_lut[force_idx] * 40.0) * size_mult 
		var spark_life = 1.0 + random_lut[life_idx] * 0.8
		_add_spark(float(ex), float(ey), f_cos * force, f_sin * force, p_color, spark_life)
		
	_lut_state[0] = (_lut_state[0] + spark_count) % LUT_SIZE

func _clear_all():
	cells.fill(0)
	charge_array.fill(0)
	charge_visual_buffer.fill(0)
	charge_dirty = true
	tags_array.fill(0)
	surface_cache.fill(0)
	active_npcs.clear()
	active_logic_gates.clear()
	active_pistons.clear()
	active_cannons.clear()
	active_pipes.clear()
	active_pipes_x2.clear()
	active_projectiles.clear()
	active_metronome_indices.clear()
	door_registry.clear()
	door_close_timers.clear()
	phase_block_registry.clear()
	vs_life.fill(0.0)
	active_charge_indices.clear()
	next_charge_indices.clear()
	charge_queued_frame.fill(-1)
	powered_frame.fill(-1)
	
	# CLEAR PAINTING
	cell_paint_colors.fill(0)
	if is_instance_valid(background_img):
		background_img.fill(Color(0, 0, 0, 0))
	background_dirty = true
	element_paint_dirty = true
	
	_reset_all_disasters() # Optimized & Scalable reset
	
	_update_texture()
	_update_material_highlights()
	_update_menu_highlights()

func _reset_all_disasters():
	current_weather = 0
	earthquake_intensity = 0; earthquake_timer = 0.0
	tornado_intensity = 0; tornado_timer = 0.0
	tsunami_intensity = 0; tsunami_timer = 0.0
	bombardero_intensity = 0
	
	# Future/Upcoming Resets
	acid_rain_intensity = 0
	lava_rain_intensity = 0
	meteor_storm_intensity = 0
	black_hole_intensity = 0
	sinkhole_intensity = 0
	sand_storm_intensity = 0
	
	# Stop all looping players
	if is_instance_valid(weather_player) and weather_player.playing: weather_player.stop()
	if is_instance_valid(quake_player) and quake_player.playing: quake_player.stop()
	if is_instance_valid(tornado_player) and tornado_player.playing: tornado_player.stop()
	if is_instance_valid(tsunami_player) and tsunami_player.playing: tsunami_player.stop()
	if is_instance_valid(volcano_loop_player) and volcano_loop_player.playing: volcano_loop_player.stop()
	if is_instance_valid(bombardero_player) and bombardero_player.playing: bombardero_player.stop()
	bombardero_pending_checks.clear()

func _on_arcade_selection_made(is_team_change = false):
	# Removed "npc_control_gui.visible" AND "controlled_npc" guards.
	# If the Arcade menu is open at all, selecting an item MUST force it to close and update!
	if is_instance_valid(npc_control_gui):
		if not is_team_change and is_npc_mode_menu_open:
			_toggle_npc_mode_menu(false)
		_update_arcade_dynamic_button()

func _update_arcade_dynamic_button():
	if not is_instance_valid(npc_control_gui): return
	var menu_btn = npc_control_gui.find_child("MenuBtn", true, false)
	if not is_instance_valid(menu_btn): return
	var s = 1.1 # FIXED SCALE: Must match the Arcade UI scale for alignment
	
	# Clear children of the menu button's container
	for child in menu_btn.get_children(): 
		if is_instance_valid(child): child.queue_free()
	
	menu_btn.text = tr("menu")
	menu_btn.modulate = Color.WHITE
	
	# Determine if something is "Selected"
	var active_name = ""
	var active_val = ""
	var active_color = Color.WHITE
	var is_disaster = false
	
	var intensity_labels = ["off", "light", "med", "heavy", "violent"]
	
	# Check Disasters (Priority)
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
	# Check NPCs
	elif selected_material >= 1000:
		if selected_material == 1000 or selected_material == 1001: active_name = tr("warrior")
		elif selected_material == 1010 or selected_material == 1011: active_name = tr("archer")
		elif selected_material == 1020 or selected_material == 1021: active_name = tr("miner")
		elif selected_material == 1040 or selected_material == 1041: active_name = tr("medic")
		elif selected_material == 1070 or selected_material == 1071: active_name = tr("mage")
		elif selected_material == 1050 or selected_material == 1051: active_name = tr("zombie")
		elif selected_material == 1060 or selected_material == 1061: active_name = tr("zombie_tank")
		
		if selected_material == 1050 or selected_material == 1051 or selected_material == 1060 or selected_material == 1061:
			active_color = Color("#4E822E") if (selected_material == 1060 or selected_material == 1061) else Color("#5D9C36")
			active_val = tr("factionless")
		else:
			var t_colors = [Color.RED, Color.CORNFLOWER_BLUE, Color.GOLD, Color.GREEN]
			active_color = t_colors[selected_team] if selected_team < 4 else Color.WHITE
			active_val = "T." + str(selected_team + 1)
	# Check Material
	elif selected_material > 0:
		if mat_id_to_key.has(selected_material):
			active_name = tr(mat_id_to_key[selected_material])
		else:
			active_name = "Mat." + str(selected_material)
		active_val = "S." + str(brush_radius)
		active_color = mat_colors_1[selected_material]
	
	if active_name != "":
		menu_btn.text = "" # Hide base text
		
		# 1. INTERNAL CONTENT
		var hbox = HBoxContainer.new()
		hbox.name = "DynamicContent"
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("separation", 0)
		menu_btn.add_child(hbox)
		
		# --- LEFT SIDE ---
		var left_side = CenterContainer.new()
		left_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(left_side)
		
		if is_disaster:
			# Disaster Name
			var name_lbl = Label.new()
			name_lbl.text = active_name
			name_lbl.add_theme_font_override("font", _get_safe_font())
			name_lbl.add_theme_font_size_override("font_size", 22 * s) # LARGE
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_side.add_child(name_lbl)
		else:
			# Material Color
			var color_box = ColorRect.new()
			color_box.custom_minimum_size = Vector2(50 * s, 30 * s)
			color_box.color = active_color
			color_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_side.add_child(color_box)
		
		# Divider
		var div = ColorRect.new()
		div.custom_minimum_size = Vector2(4 * s, 0)
		div.color = Color(1, 1, 1, 0.2)
		div.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(div)
		
		# --- RIGHT SIDE ---
		var right_side = CenterContainer.new()
		right_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(right_side)
		
		var val_lbl = Label.new()
		val_lbl.text = active_val
		val_lbl.add_theme_font_override("font", _get_safe_font())
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		if is_disaster:
			val_lbl.add_theme_font_size_override("font_size", 28 * s) # LARGE
			val_lbl.add_theme_color_override("font_color", Color.WHITE) # More legible
		else:
			# Material Size (with Brush Emoji)
			var brush_sizes = [0, 1, 2, 5, 7, 12]
			var brush_labels = ["1", "3", "5", "10", "15", "25"]
			var brush_idx = brush_sizes.find(brush_radius)
			var display_val = brush_labels[brush_idx] if brush_idx != -1 else str(brush_radius)
			val_lbl.text = "🖌️:" + display_val
			val_lbl.add_theme_font_size_override("font_size", 28 * s)
			val_lbl.add_theme_color_override("font_color", Color.YELLOW)
		
		right_side.add_child(val_lbl)
		
		# 2. EXTERNAL LABELS (Below the button)
		var ext_labels = npc_control_gui.get_node_or_null("ArcadeLabels")
		if ext_labels:
			for child in ext_labels.get_children(): child.queue_free()
			
			# ONLY add external labels if NOT a disaster (to avoid redundant names)
			if not is_disaster:
				var name_lbl = Label.new()
				name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				name_lbl.text = active_name
				name_lbl.add_theme_font_override("font", _get_safe_font())
				name_lbl.add_theme_font_size_override("font_size", 30 * s)
				name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ext_labels.add_child(name_lbl)
	else:
		# CLEAR external labels when in "MENU" mode
		var ext_labels = npc_control_gui.get_node_or_null("ArcadeLabels")
		if ext_labels:
			for child in ext_labels.get_children(): child.queue_free()

# --- MUSIC SYSTEM IMPLEMENTATION (NEW) ---

func _register_musical_materials():
	# Register 5 distinct instrument sets (4 pianos + 1 drum set)
	for inst in range(5):
		var base_color = MUSIC_INST_COLORS[inst]
		for note in range(16):
			var mat_id = MUSIC_ID_START + (inst * 16) + note
			var color = base_color
			var max_n = 15.0 if inst < 4 else 8.0 # 16 notes for pianos, 9 notes for drums
			var factor = 0.4 + (float(note % int(max_n + 1)) / max_n) * 0.6 
			color = base_color.darkened(1.0 - factor)
			
			_register_material(mat_id, color, SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.MUSIC | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.CONDUCTOR)
	
	# Register METRONOME (ID 600) - Neon Cyan pulses
	_register_material(600, Color("#00F2FF"), SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED | SandboxMaterial.Tags.MUSIC)

func _place_music_block(gx, gy, mat_id):
	# Places a 2x2 block (4 pixels)
	for oy in range(2):
		for ox in range(2):
			_set_cell(gx + ox, gy + oy, mat_id)

func _is_cell_charged(bx: int, by: int) -> bool:
	for dy in range(4):
		var gy = by + dy
		if gy < 0 or gy >= grid_height: continue
		var row_offset = gy * grid_width
		for dx in range(4):
			var gx = bx + dx
			if gx < 0 or gx >= grid_width: continue
			var idx = row_offset + gx
			if charge_array[idx] > 0:
				return true
	return false

func _charge_cell(bx: int, by: int):
	for dy in range(4):
		var gy = by + dy
		if gy < 0 or gy >= grid_height: continue
		var row_offset = gy * grid_width
		for dx in range(4):
			var gx = bx + dx
			if gx < 0 or gx >= grid_width: continue
			var idx = row_offset + gx
			
			charge_array[idx] = 100
			charge_visual_buffer[idx] = 100
			_register_charge(idx)
			_activate_chunk(gx, gy)
			
			# Spread to adjacent conductor neighbors (like Metal wire)
			for ny in range(gy - 1, gy + 2):
				if ny < 0 or ny >= grid_height: continue
				var n_row = ny * grid_width
				for nx in range(gx - 1, gx + 2):
					if nx < 0 or nx >= grid_width: continue
					var n_idx = n_row + nx
					var n_tags = tags_array[n_idx]
					if (n_tags & SandboxMaterial.Tags.CONDUCTOR) and charge_array[n_idx] == 0:
						charge_array[n_idx] = 101
						_register_charge(n_idx)
						_activate_chunk(nx, ny)

func _discharge_cell(bx: int, by: int):
	for dy in range(4):
		var gy = by + dy
		if gy < 0 or gy >= grid_height: continue
		var row_offset = gy * grid_width
		for dx in range(4):
			var gx = bx + dx
			if gx < 0 or gx >= grid_width: continue
			var idx = row_offset + gx
			if charge_array[idx] > 0:
				charge_array[idx] = 0
				charge_visual_buffer[idx] = 0

func _simulate_logic_gates():
	if cells.size() == 0: return
	var i = active_logic_gates.size() - 1
	while i >= 0:
		var gate = active_logic_gates[i]
		var grid_pos = gate["grid_pos"]
		var orientation = gate["orientation"]
		var type = gate["type"]
		
		# Center cell row 1, col 1
		var cx = grid_pos.x
		var cy = grid_pos.y
		var center_gx = (cx + 1) * 4
		var center_gy = (cy + 1) * 4
		var center_idx = center_gy * grid_width + center_gx
		
		if center_idx >= cells.size():
			active_logic_gates.remove_at(i)
			i -= 1
			continue
			
		var center_mid = cells[center_idx] & 0xFFFF
		if center_mid < 81 or center_mid > 87:
			# Gate center was overwritten, remove it!
			active_logic_gates.remove_at(i)
			i -= 1
			continue
		
		var pin_A_r = 0
		var pin_A_c = 0
		var pin_B_r = 0
		var pin_B_c = 0
		var pin_out_r = 0
		var pin_out_c = 0
		
		match orientation:
			0: # UP
				pin_A_r = 2; pin_A_c = 0
				pin_B_r = 2; pin_B_c = 2
				pin_out_r = 0; pin_out_c = 1
			1: # RIGHT
				pin_A_r = 0; pin_A_c = 0
				pin_B_r = 2; pin_B_c = 0
				pin_out_r = 1; pin_out_c = 2
			2: # DOWN
				pin_A_r = 0; pin_A_c = 0
				pin_B_r = 0; pin_B_c = 2
				pin_out_r = 2; pin_out_c = 1
			3: # LEFT
				pin_A_r = 0; pin_A_c = 2
				pin_B_r = 2; pin_B_c = 2
				pin_out_r = 1; pin_out_c = 0
		
		var bx_A = (cx + pin_A_c) * 4
		var by_A = (cy + pin_A_r) * 4
		var bx_B = (cx + pin_B_c) * 4
		var by_B = (cy + pin_B_r) * 4
		var _bx_out = (cx + pin_out_c) * 4
		var _by_out = (cy + pin_out_r) * 4
		
		var val_A = _is_cell_charged(bx_A, by_A)
		var val_B = _is_cell_charged(bx_B, by_B)
		
		var out_val = false
		match type:
			"not":
				out_val = not (val_A or val_B)
			"and":
				out_val = val_A and val_B
			"or":
				out_val = val_A or val_B
			"nand":
				out_val = not (val_A and val_B)
			"nor":
				out_val = not (val_A or val_B)
			"xor":
				out_val = val_A != val_B
			"xnor":
				out_val = val_A == val_B
				
		gate["output_active"] = out_val
		i -= 1



func _load_active_logic_gates(dict: Dictionary):
	active_logic_gates.clear()
	if dict.has("active_logic_gates"):
		var old_w = int(dict.get("width", grid_width))
		var old_h = int(dict.get("height", grid_height))
		var y_offset_px = old_h - grid_height
		y_offset_px = int(floor(float(y_offset_px) / 4.0)) * 4
		var x_offset_px = int((old_w - grid_width) / 2.0)
		x_offset_px = int(floor(float(x_offset_px) / 4.0)) * 4
		
		var offset_logic_x = int(x_offset_px / 4.0)
		var offset_logic_y = int(y_offset_px / 4.0)
		
		var max_tx = int(grid_width / 4.0)
		var max_ty = int(grid_height / 4.0)

		for gate_data in dict["active_logic_gates"]:
			var gate = gate_data.duplicate(true)
			if gate.has("grid_pos"):
				var pos = gate["grid_pos"]
				var px = 0
				var py = 0
				if pos is Vector2 or pos is Vector2i:
					px = int(pos.x)
					py = int(pos.y)
				elif typeof(pos) == TYPE_DICTIONARY:
					px = int(pos.get("x", 0))
					py = int(pos.get("y", 0))
				gate["grid_pos"] = Vector2i(px - offset_logic_x, py - offset_logic_y)
				
				# Bounds check: logic gate spans 3x3 tiles
				if gate["grid_pos"].x >= 0 and gate["grid_pos"].x + 2 < max_tx and gate["grid_pos"].y >= 0 and gate["grid_pos"].y + 2 < max_ty:
					active_logic_gates.append(gate)

func _reconstruct_sources_from_cells(dict: Dictionary = {}):
	var old_pipe_elements = {}
	for p in active_pipes:
		if p.has("path") and p.has("elements"):
			for i in range(p.path.size()):
				var coord = p.path[i]
				if i < p.elements.size():
					old_pipe_elements[coord] = p.elements[i]
					
	var old_pipe_x2_elements = {}
	for p in active_pipes_x2:
		if p.has("path") and p.has("elements"):
			for i in range(p.path.size()):
				var coord = p.path[i]
				if i < p.elements.size():
					old_pipe_x2_elements[coord] = p.elements[i]
					
	active_battery_indices.clear()
	active_electricity_source_indices.clear()
	door_registry.clear()
	door_close_timers.clear()
	phase_block_registry.clear()
	active_metronome_indices.clear()
	active_pistons.clear()
	
	if dict.has("active_pistons"):
		var p_y_offset = 0
		var p_x_offset = 0
		if dict.has("width") and dict.has("height"):
			var old_w = int(dict["width"])
			var old_h = int(dict["height"])
			p_y_offset = old_h - grid_height
			p_y_offset = int(floor(float(p_y_offset) / 4.0)) * 4
			p_x_offset = int((old_w - grid_width) / 2.0)
			p_x_offset = int(floor(float(p_x_offset) / 4.0)) * 4
		for p_data in dict["active_pistons"]:
			var p = p_data.duplicate(true)
			if p.has("pos"):
				var px = p["pos"].x
				var py = p["pos"].y
				if px is float: px = int(px)
				if py is float: py = int(py)
				p["pos"] = Vector2i(px - p_x_offset, py - p_y_offset)
			active_pistons.append(p)
			
	active_cannons.clear()
	active_pipes.clear()
	active_pipes_x2.clear()
	
	# 1. Restore open doors, powered phase blocks, and timers from save dict if present
	var translate_idx = func(old_idx: int) -> int:
		if not dict.has("width") or not dict.has("height"):
			return old_idx
		var old_w = int(dict["width"])
		var old_h = int(dict["height"])
		var old_y = int(old_idx / float(old_w))
		var old_x = old_idx % old_w
		
		var y_offset = old_h - grid_height
		y_offset = int(floor(float(y_offset) / 4.0)) * 4
		var x_offset = int((old_w - grid_width) / 2.0)
		x_offset = int(floor(float(x_offset) / 4.0)) * 4
		
		var new_x = old_x - x_offset
		var new_y = old_y - y_offset
		if new_x >= 0 and new_x < grid_width and new_y >= 0 and new_y < grid_height:
			return new_y * grid_width + new_x
		return -1

	if dict.has("door_registry"):
		for idx in dict["door_registry"]:
			var new_idx = translate_idx.call(int(idx))
			if new_idx != -1:
				door_registry[new_idx] = true
	if dict.has("door_close_timers"):
		var timers = dict["door_close_timers"]
		for idx_str in timers:
			var new_idx = translate_idx.call(int(idx_str))
			if new_idx != -1:
				door_close_timers[new_idx] = float(timers[idx_str])
	if dict.has("phase_block_registry"):
		for idx in dict["phase_block_registry"]:
			var new_idx = translate_idx.call(int(idx))
			if new_idx != -1:
				phase_block_registry[new_idx] = true
			
	# 2. Loop over cells to reconstruct batteries, electricity source blocks, metronomes, and solid doors/phase blocks
	if cells.size() == 0: return
	var special_indices = get_special_source_indices(cells)
	for idx in special_indices:
		var mid = cells[idx] & 0xFFFF
		if mid == 88:
			active_battery_indices[idx] = true
		elif mid == 9:
			active_electricity_source_indices[idx] = true
		elif mid == 600:
			active_metronome_indices[idx] = true
		elif mid == 91:
			door_registry[idx] = true
		elif mid == 92:
			phase_block_registry[idx] = true
		elif mid == 95 or mid == 195 or mid == 295 or mid == 395 or mid == 495 or mid == 595 or mid == 695 or mid == 795:
			var px = idx % grid_width
			var py = int(idx / float(grid_width))
			var val = cells[idx]
			var variant = (val >> 24) & 0xFF
			var local_x = variant & 0x0F
			var local_y = variant >> 4
			var gx = px - local_x + 3
			var gy = py - local_y + 3
			var already_registered = false
			for c in active_cannons:
				if c.pos.x == gx and c.pos.y == gy:
					already_registered = true
					break
			if not already_registered:
				var orient = int((mid - 95) / 100.0)
				var new_c = {
					"pos": Vector2i(gx, gy),
					"orientation": orient,
					"cooldown": 0.0
				}
				active_cannons.append(new_c)
		elif mid == 93:
			var px = idx % grid_width
			var py = int(idx / float(grid_width))
			var already_registered = false
			for p in active_pistons:
				var orient = p.get("orientation", 0)
				var in_base = false
				if orient == 0:
					in_base = (px >= p.pos.x and px < p.pos.x + 4 and py >= p.pos.y + 1 and py < p.pos.y + 4)
				elif orient == 1:
					in_base = (px >= p.pos.x and px < p.pos.x + 3 and py >= p.pos.y and py < p.pos.y + 4)
				elif orient == 2:
					in_base = (px >= p.pos.x and px < p.pos.x + 4 and py >= p.pos.y and py < p.pos.y + 3)
				elif orient == 3:
					in_base = (px >= p.pos.x + 1 and px < p.pos.x + 4 and py >= p.pos.y and py < p.pos.y + 4)
				if in_base:
					already_registered = true
					break
			if not already_registered:
				# Base layout boundary hits starting pixel.
				# Scan the 4x4 bounding box to identify base pixels and head location to find orientation:
				var gx = px
				var gy = py
				# Find top-left of the 4x4 grid cell:
				gx = int(floor(float(px) / 4.0) * 4.0)
				gy = int(floor(float(py) / 4.0) * 4.0)
				
				var detected_orient = 0
				if _get_cell(gx + 3, gy) == 94 and _get_cell(gx + 3, gy + 3) == 94:
					detected_orient = 1 # RIGHT
				elif _get_cell(gx, gy + 3) == 94 and _get_cell(gx + 3, gy + 3) == 94:
					detected_orient = 2 # DOWN
				elif _get_cell(gx, gy) == 94 and _get_cell(gx, gy + 3) == 94:
					detected_orient = 3 # LEFT
				
				# Scan along the detected orientation direction to find the current extension
				var ext = 0
				for ey in range(0, 61):
					var head_found = true
					var head_pixels = []
					if detected_orient == 0: # UP
						var ty = gy - ey
						for ox in range(4):
							head_pixels.append(Vector2i(gx + ox, ty))
					elif detected_orient == 1: # RIGHT
						var tx = gx + 3 + ey
						for oy in range(4):
							head_pixels.append(Vector2i(tx, gy + oy))
					elif detected_orient == 2: # DOWN
						var ty = gy + 3 + ey
						for ox in range(4):
							head_pixels.append(Vector2i(gx + ox, ty))
					elif detected_orient == 3: # LEFT
						var tx = gx - ey
						for oy in range(4):
							head_pixels.append(Vector2i(tx, gy + oy))
							
					for pix in head_pixels:
						if pix.x < 0 or pix.x >= grid_width or pix.y < 0 or pix.y >= grid_height or _get_cell(pix.x, pix.y) != 94:
							head_found = false
							break
					if head_found:
						ext = ey
					else:
						break
				var new_p = {
					"pos": Vector2i(gx, gy),
					"current_ext": float(ext),
					"target_ext": selected_piston_length,
					"is_active": false,
					"orientation": detected_orient,
					"is_insulated": (mid == 193)
				}
				active_pistons.append(new_p)

	# Reconstruct pipes paths from cells
	var pipe_blocks = {}
	for idx_pt in range(cells.size()):
		if (cells[idx_pt] & 0xFFFF) == 96:
			var px = idx_pt % grid_width
			var py = int(idx_pt / float(grid_width))
			var gx = int(floor(float(px) / 4.0) * 4.0)
			var gy = int(floor(float(py) / 4.0) * 4.0)
			pipe_blocks[Vector2i(gx, gy)] = true
			
	var unvisited = pipe_blocks.keys()
	
	var get_neighbors = func(pt: Vector2i) -> Array:
		var npts = []
		var dirs = [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]
		for d in dirs:
			var target = pt + d
			if pipe_blocks.has(target):
				npts.append(target)
		return npts
		
	while unvisited.size() > 0:
		var start = unvisited[0]
		for pt in unvisited:
			if get_neighbors.call(pt).size() == 1:
				start = pt
				break
				
		var path = [start]
		unvisited.erase(start)
		
		var current = start
		while true:
			var neighbors = get_neighbors.call(current)
			var next_block = null
			for n in neighbors:
				if n in unvisited:
					next_block = n
					break
			if next_block != null:
				path.append(next_block)
				unvisited.erase(next_block)
				current = next_block
			else:
				break
				
		var elem_list = []
		for pt in path:
			if old_pipe_elements.has(pt):
				elem_list.append(old_pipe_elements[pt])
			else:
				elem_list.append([])
		active_pipes.append({
			"path": path,
			"elements": elem_list,
			"flow_dir": 0
		})
		
	for p in active_pipes:
		_update_pipe_visuals(p)

	# Reconstruct pipe_x2 paths from cells
	var pipe_x2_blocks = {}
	for idx_pt in range(cells.size()):
		if (cells[idx_pt] & 0xFFFF) == 97:
			var px = idx_pt % grid_width
			var py = int(idx_pt / float(grid_width))
			var gx = int(floor(float(px) / 8.0) * 8.0)
			var gy = int(floor(float(py) / 8.0) * 8.0)
			pipe_x2_blocks[Vector2i(gx, gy)] = true
			
	var unvisited_x2 = pipe_x2_blocks.keys()
	
	var get_neighbors_x2 = func(pt: Vector2i) -> Array:
		var npts = []
		var dirs = [Vector2i(8, 0), Vector2i(-8, 0), Vector2i(0, 8), Vector2i(0, -8)]
		for d in dirs:
			var target = pt + d
			if pipe_x2_blocks.has(target):
				npts.append(target)
		return npts
		
	while unvisited_x2.size() > 0:
		var start = unvisited_x2[0]
		for pt in unvisited_x2:
			if get_neighbors_x2.call(pt).size() == 1:
				start = pt
				break
				
		var path = [start]
		unvisited_x2.erase(start)
		
		var current = start
		while true:
			var neighbors = get_neighbors_x2.call(current)
			var next_block = null
			for n in neighbors:
				if n in unvisited_x2:
					next_block = n
					break
			if next_block != null:
				path.append(next_block)
				unvisited_x2.erase(next_block)
				current = next_block
			else:
				break
				
		var elem_list = []
		for pt in path:
			var item = old_pipe_x2_elements.get(pt, null)
			if item is Dictionary and item.has("a") and item.has("b"):
				var flat = []
				for elem in item["a"]:
					flat.append(elem)
				for elem in item["b"]:
					flat.append(elem)
				elem_list.append(flat)
			elif item is Array:
				elem_list.append(item)
			else:
				elem_list.append([])
		active_pipes_x2.append({
			"path": path,
			"elements": elem_list,
			"flow_dir": 0
		})
		
	for p in active_pipes_x2:
		_update_pipe_x2_visuals(p)

func _get_gate_pin_cell_indices(gate, pin_type: String) -> Array:
	var cx = gate["grid_pos"].x
	var cy = gate["grid_pos"].y
	var orientation = gate["orientation"]
	
	var r = 0
	var c = 0
	
	if pin_type == "out":
		match orientation:
			0: r = 0; c = 1 # UP
			1: r = 1; c = 2 # RIGHT
			2: r = 2; c = 1 # DOWN
			3: r = 1; c = 0 # LEFT
	elif pin_type == "in_a":
		match orientation:
			0: r = 2; c = 0 # UP
			1: r = 0; c = 0 # RIGHT
			2: r = 0; c = 2 # DOWN
			3: r = 2; c = 2 # LEFT
	elif pin_type == "in_b":
		match orientation:
			0: r = 2; c = 2 # UP
			1: r = 2; c = 0 # RIGHT
			2: r = 0; c = 0 # DOWN
			3: r = 0; c = 2 # LEFT
			
	var pins = []
	var bx = (cx + c) * 4
	var by = (cy + r) * 4
	for dy in range(4):
		var gy = by + dy
		if gy < 0 or gy >= grid_height: continue
		var row_offset = gy * grid_width
		for dx in range(4):
			var gx = bx + dx
			if gx < 0 or gx >= grid_width: continue
			pins.append(row_offset + gx)
	return pins

func _get_logic_gate_output_pins(gate) -> Array:
	return _get_gate_pin_cell_indices(gate, "out")

func _place_circuit_block(gx: int, gy: int, mat_id: int):
	# Places a 4x4 block (16 pixels) to fully occupy the grid cell
	for oy in range(4):
		for ox in range(4):
			_set_cell(gx + ox, gy + oy, mat_id)

func _get_piston_direction(orientation: int) -> Vector2i:
	match orientation:
		0: return Vector2i(0, -1) # UP
		1: return Vector2i(1, 0)  # RIGHT
		2: return Vector2i(0, 1)  # DOWN
		3: return Vector2i(-1, 0) # LEFT
	return Vector2i(0, -1)

func _get_piston_head_pixels(p, ext: int) -> Array:
	var px = p.pos.x
	var gy = p.pos.y
	var pixels = []
	var orient = p.get("orientation", 0)
	if orient == 0: # UP
		var ty = gy - ext
		for ox in range(4):
			pixels.append(Vector2i(px + ox, ty))
	elif orient == 1: # RIGHT
		var tx = px + 3 + ext
		for oy in range(4):
			pixels.append(Vector2i(tx, gy + oy))
	elif orient == 2: # DOWN
		var ty = gy + 3 + ext
		for ox in range(4):
			pixels.append(Vector2i(px + ox, ty))
	elif orient == 3: # LEFT
		var tx = px - ext
		for oy in range(4):
			pixels.append(Vector2i(tx, gy + oy))
	return pixels

func _get_piston_base_pixels(p) -> Array:
	var px = p.pos.x
	var gy = p.pos.y
	var pixels = []
	var orient = p.get("orientation", 0)
	if orient == 0: # UP
		for oy in range(1, 4):
			for ox in range(4):
				pixels.append(Vector2i(px + ox, gy + oy))
	elif orient == 1: # RIGHT
		for oy in range(4):
			for ox in range(3):
				pixels.append(Vector2i(px + ox, gy + oy))
	elif orient == 2: # DOWN
		for oy in range(3):
			for ox in range(4):
				pixels.append(Vector2i(px + ox, gy + oy))
	elif orient == 3: # LEFT
		for oy in range(4):
			for ox in range(1, 4):
				pixels.append(Vector2i(px + ox, gy + oy))
	return pixels

func _place_piston(gx: int, gy: int):
	if gx < 0 or gx + 3 >= grid_width or gy < 0 or gy + 3 >= grid_height:
		return
		
	# Check if there is an existing piston at this exact snapping coordinate gx, gy
	var existing_idx = -1
	for idx in range(active_pistons.size()):
		if active_pistons[idx].pos.x == gx and active_pistons[idx].pos.y == gy:
			existing_idx = idx
			break
			
	if existing_idx != -1:
		# Rotate existing piston!
		var p = active_pistons[existing_idx]
		
		# 1. Erase old piston shape (base + head + any extension)
		var _base_mat_to_erase = 193 if p.get("is_insulated", false) else 93
		var base_pix_erase = _get_piston_base_pixels(p)
		for pix in base_pix_erase:
			_set_cell(pix.x, pix.y, 0)
			
		var ext_limit = int(p.current_ext)
		for ext_val in range(ext_limit + 1):
			@warning_ignore("confusable_local_declaration")
			var head_pix = _get_piston_head_pixels(p, ext_val)
			for pix in head_pix:
				_set_cell(pix.x, pix.y, 0)
				
		# 2. Update orientation
		p.orientation = (p.get("orientation", 0) + 1) % 4
		p.current_ext = 0.0
		
		# 3. Draw new piston shape
		var b_mat_new = 193 if p.get("is_insulated", false) else 93
		var h_mat_new = 194 if p.get("is_insulated", false) else 94
		var base_pix = _get_piston_base_pixels(p)
		for pix in base_pix:
			_set_cell(pix.x, pix.y, b_mat_new)
		@warning_ignore("confusable_local_declaration")
		var head_pix = _get_piston_head_pixels(p, 0)
		for pix in head_pix:
			_set_cell(pix.x, pix.y, h_mat_new)
			
		_play_action_sound("ui_click")
		return
		
	# Remove overlapping pistons
	var i = active_pistons.size() - 1
	while i >= 0:
		var p = active_pistons[i]
		if abs(p.pos.x - gx) < 4 and abs(p.pos.y - gy) < 4:
			# Erase cells of overlapping piston to prevent orphans
			for oy in range(4):
				for ox in range(4):
					_set_cell(p.pos.x + ox, p.pos.y + oy, 0)
			var ext_limit = int(p.current_ext)
			for ext_val in range(ext_limit + 1):
				@warning_ignore("confusable_local_declaration")
				var head_pix = _get_piston_head_pixels(p, ext_val)
				for pix in head_pix:
					_set_cell(pix.x, pix.y, 0)
			active_pistons.remove_at(i)
		i -= 1

	var base_mat_new = 193 if is_piston_insulated else 93
	var head_mat_new = 194 if is_piston_insulated else 94
	for oy in range(1, 4):
		for ox in range(4):
			_set_cell(gx + ox, gy + oy, base_mat_new)
			
	for ox in range(4):
		_set_cell(gx + ox, gy, head_mat_new)
			
	var new_p = {
		"pos": Vector2i(gx, gy),
		"current_ext": 0.0,
		"target_ext": selected_piston_length,
		"is_active": false,
		"orientation": 0,
		"is_insulated": is_piston_insulated
	}
	active_pistons.append(new_p)
	
	if not is_piston_tutorial_done:
		_show_piston_tutorial_bubble(Vector2i(gx, gy))
func _get_cannon_active_cells(orient: int, inlet_side: String = "") -> Array:
	if inlet_side == "":
		if orient == 0: inlet_side = "left"
		elif orient == 1: inlet_side = "bottom"
		elif orient == 2: inlet_side = "bottom"
		elif orient == 3: inlet_side = "bottom"
		elif orient == 4: inlet_side = "right"
		else: inlet_side = "left"

	var list = []
	# 1. Base / Stand (depends on inlet_side, shifted by +1)
	if inlet_side == "bottom":
		list.append(Vector2i(4, 8))
		list.append(Vector2i(5, 8))
		list.append(Vector2i(6, 8))
		list.append(Vector2i(7, 8))
		list.append(Vector2i(4, 9))
		list.append(Vector2i(7, 9))
		list.append(Vector2i(4, 10))
		list.append(Vector2i(7, 10))
		list.append(Vector2i(4, 11))
		list.append(Vector2i(7, 11))
	elif inlet_side == "top":
		list.append(Vector2i(4, 3))
		list.append(Vector2i(5, 3))
		list.append(Vector2i(6, 3))
		list.append(Vector2i(7, 3))
		list.append(Vector2i(4, 2))
		list.append(Vector2i(7, 2))
		list.append(Vector2i(4, 1))
		list.append(Vector2i(7, 1))
		list.append(Vector2i(4, 0))
		list.append(Vector2i(7, 0))
	elif inlet_side == "left":
		list.append(Vector2i(3, 4))
		list.append(Vector2i(3, 5))
		list.append(Vector2i(3, 6))
		list.append(Vector2i(3, 7))
		list.append(Vector2i(2, 4))
		list.append(Vector2i(2, 7))
		list.append(Vector2i(1, 4))
		list.append(Vector2i(1, 7))
		list.append(Vector2i(0, 4))
		list.append(Vector2i(0, 7))
	elif inlet_side == "right":
		list.append(Vector2i(8, 4))
		list.append(Vector2i(8, 5))
		list.append(Vector2i(8, 6))
		list.append(Vector2i(8, 7))
		list.append(Vector2i(9, 4))
		list.append(Vector2i(9, 7))
		list.append(Vector2i(10, 4))
		list.append(Vector2i(10, 7))
		list.append(Vector2i(11, 4))
		list.append(Vector2i(11, 7))
	
	# 2. Main Body (always active, shifted by +1)
	for py in range(4, 8):
		for px in range(4, 8):
			list.append(Vector2i(px, py))
			
	# 3. Pivot & Barrel (depends on orientation, shifted by +1)
	if orient == 0: # 0 deg (Right)
		list.append(Vector2i(8, 5))
		list.append(Vector2i(8, 6))
		list.append(Vector2i(9, 5))
		list.append(Vector2i(9, 6))
	elif orient == 1: # 45 deg (Top-Right)
		# Pivot
		list.append(Vector2i(7, 3))
		list.append(Vector2i(8, 4))
		# Barrel
		list.append(Vector2i(8, 2))
		list.append(Vector2i(8, 3))
		list.append(Vector2i(9, 3))
	elif orient == 2: # 90 deg (Up)
		# Pivot
		list.append(Vector2i(5, 3))
		list.append(Vector2i(6, 3))
		# Barrel
		list.append(Vector2i(5, 1))
		list.append(Vector2i(6, 1))
		list.append(Vector2i(5, 2))
		list.append(Vector2i(6, 2))
	elif orient == 3: # 135 deg (Top-Left)
		# Pivot
		list.append(Vector2i(4, 3))
		list.append(Vector2i(3, 4))
		# Barrel
		list.append(Vector2i(3, 2))
		list.append(Vector2i(3, 3))
		list.append(Vector2i(2, 3))
	elif orient == 4: # 180 deg (Left)
		# Pivot
		list.append(Vector2i(3, 5))
		list.append(Vector2i(3, 6))
		# Barrel
		list.append(Vector2i(2, 5))
		list.append(Vector2i(2, 6))
	elif orient == 5: # 225 deg (Bottom-Left)
		# Pivot
		list.append(Vector2i(4, 8))
		list.append(Vector2i(3, 7))
		# Barrel
		list.append(Vector2i(3, 9))
		list.append(Vector2i(3, 8))
		list.append(Vector2i(2, 8))
	elif orient == 6: # 270 deg (Down)
		# Pivot
		list.append(Vector2i(5, 8))
		list.append(Vector2i(6, 8))
		# Barrel
		list.append(Vector2i(5, 10))
		list.append(Vector2i(6, 10))
		list.append(Vector2i(5, 9))
		list.append(Vector2i(6, 9))
	elif orient == 7: # 315 deg (Bottom-Right)
		# Pivot
		list.append(Vector2i(7, 8))
		list.append(Vector2i(8, 7))
		# Barrel
		list.append(Vector2i(8, 9))
		list.append(Vector2i(8, 8))
		list.append(Vector2i(9, 8))
		
	return list

func _place_cannon(gx: int, gy: int):
	# The 12x12 bounds are: tx = gx + px - 4, ty = gy + py - 4
	# So tx ranges from gx-4 to gx+7, ty ranges from gy-4 to gy+7.
	# We must make sure that gx-4 >= 0 and gx+7 < grid_width and gy-4 >= 0 and gy+7 < grid_height.
	if gx - 4 < 0 or gx + 7 >= grid_width or gy - 4 < 0 or gy + 7 >= grid_height:
		return
		
	# Check if there is an existing cannon at this exact snapping coordinate gx, gy
	var existing_idx = -1
	for idx in range(active_cannons.size()):
		if active_cannons[idx].pos.x == gx and active_cannons[idx].pos.y == gy:
			existing_idx = idx
			break
			
	if existing_idx != -1:
		var c = active_cannons[existing_idx]
		_open_cannon_settings_panel(c)
		return
		
	# Remove any overlapping cannons (anchors within 6 cells)
	var i = active_cannons.size() - 1
	while i >= 0:
		var c = active_cannons[i]
		if abs(c.pos.x - gx) < 6 and abs(c.pos.y - gy) < 6:
			# Clear their 12x12 area
			for py in range(12):
				for px in range(12):
					var tx = c.pos.x + px - 4
					var ty = c.pos.y + py - 4
					if tx >= 0 and tx < grid_width and ty >= 0 and ty < grid_height:
						_set_cell(tx, ty, 0)
			active_cannons.remove_at(i)
		i -= 1
		
	# Place new cannon (initial orientation 0: Right)
	var new_c = {
		"pos": Vector2i(gx, gy),
		"orientation": 0,
		"cooldown": 0.0,
		"inlet_side": "left"
	}
	active_cannons.append(new_c)
	
	# Clear the 12x12 area
	for py in range(12):
		for px in range(12):
			var tx = gx + px - 4
			var ty = gy + py - 4
			_set_cell(tx, ty, 0)
			
	# Write active cells for orientation 0
	var active_cells = _get_cannon_active_cells(0, "left")
	var mat_id = 95
	for pt in active_cells:
		var tx = gx + pt.x - 4
		var ty = gy + pt.y - 4
		var variant = pt.x | (pt.y << 4)
		var val_encoded = mat_id | (variant << 24)
		_set_cell(tx, ty, val_encoded)
		
	_play_action_sound("ui_click")
	
	if not is_cannon_tutorial_done:
		_show_cannon_tutorial_bubble(Vector2i(gx, gy))

func _place_pipe(gx: int, gy: int):
	if gx < 0 or gx + 3 >= grid_width or gy < 0 or gy + 3 >= grid_height:
		return
		
	# Check if we already have a pipe at this snapping coordinate
	var existing = false
	for p in active_pipes:
		if p.has("path") and Vector2i(gx, gy) in p.path:
			existing = true
			break
			
	if not existing:
		# Draw the 4x4 block of material ID 96
		for oy in range(4):
			for ox in range(4):
				_set_cell(gx + ox, gy + oy, 96)
		_reconstruct_sources_from_cells()
		_play_action_sound("ui_click")

func _place_pipe_x2(gx: int, gy: int):
	if gx < 0 or gx + 7 >= grid_width or gy < 0 or gy + 7 >= grid_height:
		return
		
	# Check if we already have a pipe x2 at this snapping coordinate
	var existing = false
	for p in active_pipes_x2:
		if p.has("path") and Vector2i(gx, gy) in p.path:
			existing = true
			break
			
	if not existing:
		# Draw the 8x8 block of material ID 97
		for oy in range(8):
			for ox in range(8):
				_set_cell(gx + ox, gy + oy, 97)
		_reconstruct_sources_from_cells()
		_play_action_sound("ui_click")

func _is_piston_base_powered(p) -> bool:
	var px = p.pos.x
	var gy = p.pos.y
	var orient = p.get("orientation", 0)
	
	if orient == 0: # UP
		var r1 = (gy + 1) * grid_width
		var r2 = (gy + 2) * grid_width
		var r3 = (gy + 3) * grid_width
		var i = r1 + px
		if charge_array[i] > 0 or active_battery_indices.has(i): return true
		if charge_array[i+1] > 0 or active_battery_indices.has(i+1): return true
		if charge_array[i+2] > 0 or active_battery_indices.has(i+2): return true
		if charge_array[i+3] > 0 or active_battery_indices.has(i+3): return true
		i = r2 + px
		if charge_array[i] > 0 or active_battery_indices.has(i): return true
		if charge_array[i+1] > 0 or active_battery_indices.has(i+1): return true
		if charge_array[i+2] > 0 or active_battery_indices.has(i+2): return true
		if charge_array[i+3] > 0 or active_battery_indices.has(i+3): return true
		i = r3 + px
		if charge_array[i] > 0 or active_battery_indices.has(i): return true
		if charge_array[i+1] > 0 or active_battery_indices.has(i+1): return true
		if charge_array[i+2] > 0 or active_battery_indices.has(i+2): return true
		if charge_array[i+3] > 0 or active_battery_indices.has(i+3): return true
	elif orient == 1: # RIGHT
		for oy in range(4):
			var r = (gy + oy) * grid_width + px
			if charge_array[r] > 0 or active_battery_indices.has(r): return true
			if charge_array[r+1] > 0 or active_battery_indices.has(r+1): return true
			if charge_array[r+2] > 0 or active_battery_indices.has(r+2): return true
	elif orient == 2: # DOWN
		for oy in range(3):
			var r = (gy + oy) * grid_width + px
			if charge_array[r] > 0 or active_battery_indices.has(r): return true
			if charge_array[r+1] > 0 or active_battery_indices.has(r+1): return true
			if charge_array[r+2] > 0 or active_battery_indices.has(r+2): return true
			if charge_array[r+3] > 0 or active_battery_indices.has(r+3): return true
	elif orient == 3: # LEFT
		for oy in range(4):
			var r = (gy + oy) * grid_width + px + 1
			if charge_array[r] > 0 or active_battery_indices.has(r): return true
			if charge_array[r+1] > 0 or active_battery_indices.has(r+1): return true
			if charge_array[r+2] > 0 or active_battery_indices.has(r+2): return true
			
	return false

func _activate_piston_chunks(px: int, gy: int):
	var start_cx = int(px / 4.0)
	var end_cx = int((px + 4) / 4.0)
	var start_cy = clamp(int((gy - 64) / 4.0), 0, int(grid_height / 4.0))
	var end_cy = clamp(int((gy + 16) / 4.0), 0, int(grid_height / 4.0))
	for cy in range(start_cy, end_cy + 1):
		for cx in range(start_cx, end_cx + 1):
			_activate_chunk(cx, cy)

func _pack_state_for_cpp() -> Dictionary:
	return {
		"cells": cells,
		"tags_array": tags_array,
		"charge_array": charge_array,
		"next_chunks_active": next_chunks_active,
		"cell_paint_colors": cell_paint_colors
	}

func _simulate_pistons():
	if active_pistons.size() == 0: return
	
	var old_exts = []
	for p in active_pistons:
		old_exts.append(p.current_ext)
	
	# Piston processing in C++ (Extremely fast, handles all block pushes directly)
	var state = _pack_state_for_cpp()
	state = process_pistons(active_pistons, state, grid_width, dynamic_grid_height, 0.0)
	var new_pistons = state["new_pistons"]
	
	cells = state["cells"]
	tags_array = state["tags_array"]
	charge_array = state["charge_array"]
	next_chunks_active = state["next_chunks_active"]
	cell_paint_colors = state["cell_paint_colors"]
	
	# NPC Push logic (Needs to be done in GDScript since NPCs are nodes/complex objects)
	for i in range(active_pistons.size()):
		var _p_old = active_pistons[i]
		if i >= new_pistons.size(): break # In case it was deleted
		var p_new = new_pistons[i]
		
		var p_old_ext = old_exts[i]
		
		# If piston extended, push NPCs
		if p_new.current_ext > p_old_ext:
			var px = p_new.pos.x
			var gy = p_new.pos.y
			var orient = p_new.get("orientation", 0)
			var ext = int(p_old_ext)
			# Find push_height by checking how many blocks are in front
			var push_height = 0
			var step_idx = 1
			while true:
				var p0: Vector2i; var p3: Vector2i
				if orient == 0:
					var ty = gy - ext - step_idx
					p0 = Vector2i(px, ty); p3 = Vector2i(px + 3, ty)
				elif orient == 1:
					var tx = px + 3 + ext + step_idx
					p0 = Vector2i(tx, gy); p3 = Vector2i(tx, gy + 3)
				elif orient == 2:
					var ty = gy + 3 + ext + step_idx
					p0 = Vector2i(px, ty); p3 = Vector2i(px + 3, ty)
				elif orient == 3:
					var tx = px - ext - step_idx
					p0 = Vector2i(tx, gy); p3 = Vector2i(tx, gy + 3)
					
				if p0.x < 0 or p0.x >= grid_width or p0.y < 0 or p0.y >= dynamic_grid_height or p3.x < 0 or p3.x >= grid_width or p3.y < 0 or p3.y >= dynamic_grid_height: break
				
				var has_blocks = false
				if orient == 0 or orient == 2:
					for ox in range(4):
						if _get_cell(p0.x + ox, p0.y) != 0: has_blocks = true; break
				else:
					for oy in range(4):
						if _get_cell(p0.x, p0.y + oy) != 0: has_blocks = true; break
						
				if not has_blocks: break
				push_height += 1
				if push_height > 120: break
				step_idx += 1
				
			var col_left = px
			var col_right = px + 4
			if orient == 0: # UP
				var col_bottom = gy - ext + 1
				var col_top = gy - ext - push_height
				for npc in active_npcs:
					if npc.pos.x >= col_left - 10 and npc.pos.x <= col_right + 10:
						if npc.pos.y >= col_top - 4 and npc.pos.y <= col_bottom + 2:
							npc.pos.y -= 1.0
			elif orient == 1: # RIGHT
				var col_start = gy
				var col_end = gy + 4
				var ext_start = px + 3 + ext
				var ext_end = px + 3 + ext + push_height
				for npc in active_npcs:
					if npc.pos.y >= col_start - 10 and npc.pos.y <= col_end + 10:
						if npc.pos.x >= ext_start - 2 and npc.pos.x <= ext_end + 4:
							npc.pos.x += 1.0
			elif orient == 2: # DOWN
				var col_top = gy + 3 + ext
				var col_bottom = gy + 3 + ext + push_height
				for npc in active_npcs:
					if npc.pos.x >= col_left - 10 and npc.pos.x <= col_right + 10:
						if npc.pos.y >= col_top - 2 and npc.pos.y <= col_bottom + 4:
							npc.pos.y += 1.0
			elif orient == 3: # LEFT
				var col_start = gy
				var col_end = gy + 4
				var ext_start = px - ext - push_height
				var ext_end = px - ext
				for npc in active_npcs:
					if npc.pos.y >= col_start - 10 and npc.pos.y <= col_end + 10:
						if npc.pos.x >= ext_start - 4 and npc.pos.x <= ext_end + 2:
							npc.pos.x -= 1.0

	active_pistons = new_pistons

const LOGIC_GATE_SHAPES = {
	0: [ # UP
		[0, 1, 0],
		[1, 1, 1],
		[1, 0, 1]
	],
	1: [ # RIGHT
		[1, 1, 0],
		[0, 1, 1],
		[1, 1, 0]
	],
	2: [ # DOWN
		[1, 0, 1],
		[1, 1, 1],
		[0, 1, 0]
	],
	3: [ # LEFT
		[0, 1, 1],
		[1, 1, 0],
		[0, 1, 1]
	]
}

func _get_logic_gate_cell_variant(r: int, c: int, orientation: int) -> int:
	match orientation:
		0: # UP
			if r == 0 and c == 1: return 14 # Output (Top)
			elif r == 2 and c == 0: return 12 # Input A (Bottom)
			elif r == 2 and c == 2: return 12 # Input B (Bottom)
		1: # RIGHT
			if r == 1 and c == 2: return 15 # Output (Right)
			elif r == 0 and c == 0: return 13 # Input A (Left)
			elif r == 2 and c == 0: return 13 # Input B (Left)
		2: # DOWN
			if r == 2 and c == 1: return 16 # Output (Bottom)
			elif r == 0 and c == 2: return 10 # Input A (Top)
			elif r == 0 and c == 0: return 10 # Input B (Top)
		3: # LEFT
			if r == 1 and c == 0: return 17 # Output (Left)
			elif r == 2 and c == 2: return 11 # Input A (Right)
			elif r == 0 and c == 2: return 11 # Input B (Right)
	return 0

func _draw_logic_gate_shape(grid_pos: Vector2i, orientation: int, erase: bool, type: String = "and"):
	var shape = LOGIC_GATE_SHAPES.get(orientation, LOGIC_GATE_SHAPES[0])
	var mat = 0
	if not erase:
		match type:
			"not": mat = 81
			"and": mat = 82
			"or": mat = 83
			"nand": mat = 84
			"nor": mat = 85
			"xor": mat = 86
			"xnor": mat = 87
			_: mat = 82
	for r in range(3):
		for c in range(3):
			if shape[r][c] == 1:
				var cell_mat = mat
				if not erase and mat > 0:
					var variant = _get_logic_gate_cell_variant(r, c, orientation)
					cell_mat = mat | (variant << 24)
				_place_circuit_block((grid_pos.x + c) * 4, (grid_pos.y + r) * 4, cell_mat)

func _check_logic_gate_tutorial(grid_pos: Vector2i):
	if not is_logic_gate_tutorial_done:
		_show_logic_gate_tutorial_bubble(grid_pos)

func _show_logic_gate_tutorial_bubble(grid_pos: Vector2i):
	logic_gate_tutorial_bubble = _show_unified_tutorial_bubble(
		grid_pos,
		"tut_logic_gate",
		func():
			is_logic_gate_tutorial_done = true
			_save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		200.0
	)

func _show_grid_tutorial_bubble():
	var bubble = _show_unified_tutorial_bubble(
		Vector2i.ZERO,
		"tut_grid",
		func(): pass,
		Color(0.25, 0.45, 0.85, 0.95),
		200.0
	)
	if is_instance_valid(bubble):
		var s = _get_ui_scale()
		var screen_size = get_viewport_rect().size
		# Force position to center of screen since it's a general tip
		bubble.position = Vector2(screen_size.x / 2.0 - (160 * s), screen_size.y / 2.0 - (100 * s))


func _show_unified_tutorial_bubble(_grid_pos: Vector2i, text_key: String, on_got_it: Callable, border_color: Color, bubble_h_unscaled: float) -> PanelContainer:
	if is_instance_valid(logic_gate_tutorial_bubble):
		logic_gate_tutorial_bubble.queue_free()
	if is_instance_valid(phase_block_tutorial_bubble):
		phase_block_tutorial_bubble.queue_free()

		
	if not is_instance_valid(ui_root):
		ui_root = get_parent().get_node_or_null("UI")
		if not ui_root: return null
		
	var s = _get_ui_scale()
	
	var bubble = PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	p_style.set_corner_radius_all(18 * s)
	p_style.border_width_left = 3; p_style.border_width_top = 3
	p_style.border_width_right = 3; p_style.border_width_bottom = 3
	p_style.border_color = border_color
	p_style.shadow_color = Color(0, 0, 0, 0.45)
	p_style.shadow_size = 10
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
	vbox.add_theme_constant_override("separation", 10 * s)
	margin.add_child(vbox)
	
	var lbl = Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.text = tr(text_key)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(280 * s, 0)
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_font_size_override("font_size", 20 * s)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.text = tr("GOT_IT")
	btn.custom_minimum_size = Vector2(130 * s, 46 * s)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", _get_safe_font())
	btn.add_theme_font_size_override("font_size", 18 * s)
	
	var btn_style_norm = StyleBoxFlat.new()
	btn_style_norm.bg_color = border_color
	btn_style_norm.set_corner_radius_all(10 * s)
	
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
	
	var screen_pos = get_viewport().get_mouse_position()
	
	var bubble_w = 320 * s
	var bubble_h = bubble_h_unscaled * s
	var margin_y = 20 * s
	
	var target_y = screen_pos.y - bubble_h - margin_y
	if target_y < 30 * s:
		target_y = screen_pos.y + 40 * s
		
	bubble.position.x = screen_pos.x - bubble_w / 2
	bubble.position.y = target_y
	
	var screen_size = get_viewport_rect().size
	bubble.position.x = clamp(bubble.position.x, 10 * s, screen_size.x - bubble_w - 10 * s)
	bubble.position.y = clamp(bubble.position.y, 10 * s, screen_size.y - bubble_h - 10 * s)
	
	return bubble

func _check_phase_block_tutorial(grid_pos: Vector2i):
	if not is_phase_block_tutorial_done:
		_show_phase_block_tutorial_bubble(grid_pos)

func _show_phase_block_tutorial_bubble(grid_pos: Vector2i):
	phase_block_tutorial_bubble = _show_unified_tutorial_bubble(
		grid_pos,
		"tut_phase_block",
		func():
			is_phase_block_tutorial_done = true
			_save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		230.0
	)

func _show_cannon_tutorial_bubble(grid_pos: Vector2i):
	cannon_tutorial_bubble = _show_unified_tutorial_bubble(
		grid_pos,
		"tut_cannon",
		func():
			is_cannon_tutorial_done = true
			_save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		330.0
	)

func _show_piston_tutorial_bubble(grid_pos: Vector2i):
	piston_tutorial_bubble = _show_unified_tutorial_bubble(
		grid_pos,
		"tut_piston",
		func():
			is_piston_tutorial_done = true
			_save_tool_settings(),
		Color(0.25, 0.45, 0.85, 0.95),
		230.0
	)

func _update_phase_blocks():
	if phase_block_registry.size() == 0: return
	
	is_phase_block_updating = true
	var w = grid_width
	var h = dynamic_grid_height
	
	var invalid_indices = []
	for idx in phase_block_registry:
		if idx < 0 or idx >= cells.size():
			invalid_indices.append(idx)
			continue
		var cx = idx % w
		var cy = idx / w
		
		# Check neighbors for electricity charge
		var is_powered = false
		
		# Left
		if cx > 0:
			var n = idx - 1
			if n >= 0 and n < charge_array.size() and (charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
		# Right
		if not is_powered and cx < w - 1:
			var n = idx + 1
			if n >= 0 and n < charge_array.size() and (charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
		# Up
		if not is_powered and cy > 0:
			var n = idx - w
			if n >= 0 and n < charge_array.size() and (charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
		# Down
		if not is_powered and cy < h - 1:
			var n = idx + w
			if n >= 0 and n < charge_array.size() and (charge_array[n] > 0 or active_battery_indices.has(n)):
				is_powered = true
				
		var curr_mat = cells[idx] & 0xFFFF
		if is_powered:
			if curr_mat == 92:
				cells[idx] = 0
				tags_array[idx] = 0
				_activate_chunk(cx / 4, cy / 4)
		else:
			if curr_mat != 92:
				# Re-solidify: overwrite whatever material is inside
				cells[idx] = 92
				tags_array[idx] = SandboxMaterial.Tags.SOLID | SandboxMaterial.Tags.GRAV_STATIC | SandboxMaterial.Tags.CONDUCTOR | SandboxMaterial.Tags.ELECTRIC_ACTIVATED
				_activate_chunk(cx / 4, cy / 4)
				
	for idx in invalid_indices:
		phase_block_registry.erase(idx)
	is_phase_block_updating = false

func _get_music_data(id: int) -> Dictionary:
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

func _encode_music_id(inst: int, note: int, octave: int) -> int:
	var base_id = MUSIC_ID_START + (inst * 16) + note
	if octave == 2: return base_id
	return ((octave + 1) * 10000) + base_id


func _get_tags_id(mat_id: int) -> int:
	var tags_id = mat_id & 0xFFFF
	if tags_id >= 10000:
		tags_id = tags_id % 10000
	return tags_id

func _is_music_mat(mat_id: int) -> bool:
	if mat_id == 600: return true
	var tags_id = _get_tags_id(mat_id)
	if tags_id >= 0 and _get_tags_id(tags_id) < material_tags_raw.size():
		if (material_tags_raw[_get_tags_id(tags_id)] & SandboxMaterial.Tags.MUSIC): return true
	return false

func _play_music_note(inst_idx, note_idx, ignore_achievement: bool = false, octave: int = 2, b_idx: int = -1):
	if b_idx != -1:
		var current_time = Time.get_ticks_msec()
		if music_block_cooldowns.has(b_idx) and current_time - music_block_cooldowns[b_idx] < 150:
			return
		music_block_cooldowns[b_idx] = current_time

	var hash_key = str(inst_idx) + "_" + str(note_idx) + "_" + str(octave)
	if played_music_this_frame.has(hash_key):
		return
	played_music_this_frame[hash_key] = true
	
	sim_mutex.lock()
	
	# Achievement Tracking: Composer (Exclude Metronome)
	if inst_idx != 5 and not ignore_achievement and not achievements["compositor"].unlocked:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_note_play_time <= 1.0:
			composition_note_count += 1
			if composition_note_count >= 5:
				_unlock_achievement("compositor")
		else:
			composition_note_count = 1 # Start new count
		last_note_play_time = current_time
	
	var s_name = MUSIC_INSTRUMENTS[inst_idx]
	var p_scale = MUSIC_PITCHES[note_idx % 12]
	
	if inst_idx < 4:
		# Pianos: Multi-sampling (1 file per octave)
		# Octave 0 = 1ra Octava (oct1)
		# Octave 1 = 2da Octava (oct2)
		# Octave 2 = 3ra Octava (oct3)
		# Octave 3 = 4ta Octava (oct4)
		# Octave 4 = 5ta Octava (oct5)
		var actual_octave = octave + 1
		s_name = s_name + "_oct" + str(actual_octave)
		# We do NOT multiply p_scale by octave_multiplier because the base file handles the octave base!
		
	elif inst_idx == 4: # Drum Set
		var drum_keys = ["drum_kick", "drum_snare", "drum_hihat", "drum_tom", "drum_tom_low", "drum_tom_high", "drum_ride", "drum_crash", "drum_sticks"]
		s_name = drum_keys[note_idx % 9]
		p_scale = 1.0
	elif inst_idx == 5: # Metronome
		s_name = "ui_pop" # Or any tick sound
		p_scale = 2.0
		
	var stream = _get_sfx_stream(s_name)
	if stream:
		# POLYPHONY: Use next available player in the music pool
		var p = music_player_pool[music_next_idx]
		music_next_idx = (music_next_idx + 1) % 32
		
		p.set_deferred("stream", stream)
		p.set_deferred("pitch_scale", p_scale)
		p.set_deferred("volume_db", -5.0) # Lower base volume per note to allow headroom for chords
		p.call_deferred("play")
		_trigger_npc_dance()
	sim_mutex.unlock()

func _trigger_npc_dance():
	for npc in active_npcs:
		if npc.hp > 0 and _get_lut_rand() < 0.85:
			npc["dance_timer"] = 3.5 
			npc["has_spotted_enemy"] = false 
			npc["recently_celebrated"] = false # Ensure music dance doesn't trigger victory achievement
			npc["celebration_mode"] = 3 # 3 = JUST DANCE (No fireworks for music)
			var music_emojis = ["🎵", "🕺", "💃", "🎶"]
			_set_npc_emoji(npc, music_emojis[randi() % music_emojis.size()], 3.5)

func _setup_music_ui(force_refresh: bool = false):
	_set_panning_mode(false)
	var s = _get_ui_scale()
	ui_root = get_parent().get_node("UI")
	
	# EXCLUSIVE TOGGLE: If already open, close it (like other panels)
	if not force_refresh and is_instance_valid(music_panel) and music_panel.visible:
		_close_music_menu()
		return
		
	# CLEAN UP 
	for child in ui_root.get_children():
		if child.name.begins_with("MusicMenuBlocker") or child.name.begins_with("MusicPanel") or child.name == "TO_DELETE":
			child.name = "TO_DELETE"
			child.hide()
			child.queue_free()
	circuit_panel = null
	
	music_panel = PanelContainer.new()
	music_panel.name = "MusicPanel"
	ui_root.add_child(music_panel)
	
	is_blocking = false # NO MORE BLOCKING (non-modal like tools)
	
	var panel_style = StyleBoxFlat.new()
	if selected_mechanism_tab == 0:
		panel_style.bg_color = Color(0.06, 0.08, 0.12, 0.96) # Premium semi-transparent dark blue
		panel_style.border_color = Color("#4169E1", 0.75) # Royal Blue electrical glow
	else:
		panel_style.bg_color = Color(0.1, 0.07, 0.1, 0.95) # Premium semi-transparent dark purple
		panel_style.border_color = Color(0.8, 0.1, 0.5, 0.6) # Soft musical glow
	panel_style.border_width_left = 2; panel_style.border_width_top = 2
	panel_style.border_width_right = 2; panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	music_panel.add_theme_stylebox_override("panel", panel_style)
	music_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# ROBUST POSITIONING (Same as ToolsPanel: Centered above Bottom HUD)
	var m_width = 530 * s
	var m_height = 655 * s
	
	# Limit height in landscape to avoid ad overlap
	if is_inside_tree() and get_viewport_rect().size.x > get_viewport_rect().size.y:
		m_height = 570 * s
		
	music_panel.custom_minimum_size = Vector2(m_width, m_height)
	
	_align_panel_to_hud(music_panel, m_width, m_height)

	# Main container vbox for layout
	var outer_vbox = VBoxContainer.new()
	outer_vbox.name = "OuterVBox"
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 10 * s)
	music_panel.add_child(outer_vbox)
	
	# Sub-tabs row at the top
	var sub_tab_hbox = HBoxContainer.new()
	sub_tab_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_tab_hbox.add_theme_constant_override("separation", 8 * s)
	outer_vbox.add_child(sub_tab_hbox)
	
	# Create sub-tabs (Circuits & Music)
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
			t_style.bg_color = base_col.darkened(0.2) # Active accent
			t_style.border_width_bottom = 4
			t_style.border_color = Color.WHITE
		else:
			t_style.bg_color = base_col.darkened(0.7) # Inactive accent
		tab_btn.add_theme_stylebox_override("normal", t_style)
		tab_btn.add_theme_stylebox_override("hover", t_style)
		tab_btn.add_theme_stylebox_override("pressed", t_style)
		
		var idx = tab_idx
		tab_btn.pressed.connect(func():
			_play_action_sound("ui_click")
			selected_mechanism_tab = idx
			_setup_music_ui(true)
		)
		sub_tab_hbox.add_child(tab_btn)
		
	# Populate based on selected sub-tab
	if selected_mechanism_tab == 0:
		# --- CIRCUITS VIEW ---
		circuit_panel = PanelContainer.new()
		circuit_panel.name = "CircuitPanel"
		circuit_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		circuit_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		circuit_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		circuit_panel.mouse_filter = Control.MOUSE_FILTER_PASS
		outer_vbox.add_child(circuit_panel)
		
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
		
		_show_menu_reminder("circuits", circ_vbox, "REMINDER_CIRCUITS")
		
		@warning_ignore("confusable_local_declaration")
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
		
		# Grid for mechanisms
		var circ_grid = GridContainer.new()
		circ_grid.columns = 2
		circ_grid.add_theme_constant_override("h_separation", 12 * s)
		circ_grid.add_theme_constant_override("v_separation", 12 * s)
		circ_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		circ_grid.mouse_filter = Control.MOUSE_FILTER_PASS
		circ_vbox.add_child(circ_grid)
		
		# Circuits elements: Metal, TNT, NPC Trigger, Door, Phase Block, Battery, LED, Logic Gates (NOT, AND, OR, NAND, NOR, XOR, XNOR), Piston, Cannon
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
			btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
			
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
				val_btn.text = str(selected_piston_length)
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
					_play_action_sound("ui_click")
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
					
					var grid = GridContainer.new()
					grid.columns = 3
					grid.add_theme_constant_override("h_separation", 15 * s)
					grid.add_theme_constant_override("v_separation", 15 * s)
					
					for val in vals:
						var opt_btn = Button.new()
						opt_btn.text = str(val)
						opt_btn.custom_minimum_size = Vector2(90 * s, 90 * s)
						opt_btn.add_theme_font_override("font", _get_safe_font())
						opt_btn.add_theme_font_size_override("font_size", 36 * s)
						
						var opt_style = StyleBoxFlat.new()
						if val == selected_piston_length:
							opt_style.bg_color = Color("#32CD32").darkened(0.2) # Highlight current
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
							_play_action_sound("ui_click")
							selected_piston_length = val
							val_btn.text = str(val)
							popup.hide()
						)
						grid.add_child(opt_btn)
					
					vbox.add_child(grid)
						
					var margin = MarginContainer.new()
					margin.add_theme_constant_override("margin_top", 20 * s)
					margin.add_theme_constant_override("margin_bottom", 20 * s)
					margin.add_theme_constant_override("margin_left", 20 * s)
					margin.add_theme_constant_override("margin_right", 20 * s)
					margin.add_child(vbox)
					
					popup.add_child(margin)
					get_tree().current_scene.add_child(popup)
					
					# Clean up when closed
					popup.popup_hide.connect(func(): popup.queue_free())
					
					# Position popup near the button but adjusted for larger size
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
				color_btn.text = led_emojis[selected_led_color]
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
					_play_action_sound("ui_click")
					_open_led_color_panel(color_btn)
				)
				
				hbox.add_child(color_btn)
				container = hbox
			else:
				btn.custom_minimum_size = Vector2(210 * s, 70 * s)
			
			btn.pressed.connect(func():
				_play_action_sound("ui_click")
				if item_key == "metal":
					selected_material = 8
					selected_circuit_tool = ""
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "tnt":
					selected_material = 5
					selected_circuit_tool = ""
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "battery":
					selected_material = 88
					selected_circuit_tool = ""
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "led":
					selected_material = 89
					selected_circuit_tool = ""
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "npc_act":
					selected_material = 90
					selected_circuit_tool = ""
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "door":
					selected_material = 91
					selected_circuit_tool = ""
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "phase_block":
					selected_material = 92
					selected_circuit_tool = ""
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "piston":
					selected_material = 93
					selected_circuit_tool = "piston"
					is_piston_insulated = false
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "piston_ins":
					selected_material = 93
					selected_circuit_tool = "piston"
					is_piston_insulated = true
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "cannon":
					selected_material = 95
					selected_circuit_tool = "cannon"
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "pipe":
					selected_material = 96
					selected_circuit_tool = "pipe"
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "pipe_x2":
					selected_material = 97
					selected_circuit_tool = "pipe_x2"
					is_mechanism_mode_active = true
					_close_music_menu()
				elif item_key == "not" or item_key == "and" or item_key == "or" or item_key == "nand" or item_key == "nor" or item_key == "xor" or item_key == "xnor":
					selected_material = -2
					selected_circuit_tool = item_key
					is_mechanism_mode_active = true
					_close_music_menu()
			)
			circ_grid.add_child(container)
		return # Return early so the music UI setup below does not run!
		
	# --- MUSIC VIEW ---
	var scroll = ScrollContainer.new()
	scroll.name = "MusicScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(scroll)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15 * s)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main_vbox)
	
	_show_menu_reminder("music", main_vbox, "REMINDER_MUSIC")
	
	# Title
	var title = Label.new()
	title.text = tr("music_tab")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 34 * s)
	main_vbox.add_child(title)
	
	# 1. Instrument Selection Tabs (GRID for 2 rows)
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
		# Larger buttons
		btn.custom_minimum_size = Vector2(160 * s, 60 * s)
		btn.add_theme_font_override("font", _get_safe_font())
		btn.add_theme_font_size_override("font_size", 18 * s) # Bigger font
		
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = MUSIC_INST_COLORS[i].darkened(0.6)
		b_style.set_corner_radius_all(10 * s)
		if i == selected_music_instrument:
			b_style.border_width_bottom = 5
			b_style.border_color = Color.WHITE
			b_style.bg_color = MUSIC_INST_COLORS[i].darkened(0.2)
		btn.add_theme_stylebox_override("normal", b_style)
		btn.add_theme_stylebox_override("hover", b_style)
		btn.add_theme_stylebox_override("pressed", b_style)
		
		var idx = i
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			selected_music_instrument = idx
			if idx == 5: # METRONOME (Now at index 5)
				selected_material = 600
			else:
				selected_material = _encode_music_id(idx, selected_music_note, selected_music_octave)
				_play_music_note(selected_music_instrument, selected_music_note, true, selected_music_octave)
			_setup_music_ui(true)
		)
		inst_grid.add_child(btn)
	
	# 2. Tab Content Area
	if selected_music_instrument == 5: # METRONOME VIEW (Index 5 after 4 pianos + 1 drums)
		var metro_vbox = VBoxContainer.new()
		metro_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		metro_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		main_vbox.add_child(metro_vbox)
		
		var bpm_val = int(3600.0 / float(music_tempo_frames))
		
		# EDITABLE BPM INPUT (Looks like a big label)
		var bpm_edit = LineEdit.new()
		bpm_edit.text = str(bpm_val)
		bpm_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		bpm_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		bpm_edit.context_menu_enabled = false
		bpm_edit.add_theme_font_override("font", _get_safe_font())
		bpm_edit.add_theme_font_size_override("font_size", 54 * s)
		
		# Stylized Edit Box
		var edit_style = StyleBoxFlat.new()
		edit_style.bg_color = Color(0,0,0,0.2) # Very subtle dark backing
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
		
		# SYNC Slider -> Input
		bpm_slider.value_changed.connect(func(val):
			music_tempo_frames = int(3600.0 / float(val))
			bpm_edit.text = str(int(val))
		)
		
		# SYNC Input -> Slider + Validation
		bpm_edit.text_changed.connect(func(new_text):
			# Filter: only allow numbers
			var filtered = ""
			for c in new_text:
				if c in "0123456789": filtered += c
			if filtered != new_text: bpm_edit.text = filtered; bpm_edit.caret_column = filtered.length()
			
			if filtered.length() > 0:
				var val = clampi(int(filtered), 1, 240)
				music_tempo_frames = int(3600.0 / float(val))
				bpm_slider.value = val # Sync slider
		)
		
		metro_vbox.add_child(bpm_slider)
		
		var info = Label.new()
		info.text = tr("metronome_info")
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_font_override("font", _get_safe_font())
		info.add_theme_font_size_override("font_size", 22 * s) # BIGGER INFO
		info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8)) # Lighter grey-blue
		metro_vbox.add_child(info)
		
	else: # PIANO/DRUMS VIEW
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
			# Fine-tuned size: 135px fits better without hitting the bottom
			var b_size = 105 * s if selected_music_instrument < 4 else 140 * s
			btn.custom_minimum_size = Vector2(b_size, b_size)
			btn.add_theme_font_override("font", _get_safe_font())
			btn.mouse_filter = Control.MOUSE_FILTER_PASS # ALLOW MOBILE SCROLL DRAG
			
			if selected_music_instrument < 4:
				# Piano Notes with Dual Labels
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
				# Drums/Metronome labels
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
			if i == selected_music_note:
				n_style.border_width_left = 4; n_style.border_width_top = 4
				n_style.border_width_right = 4; n_style.border_width_bottom = 4
				n_style.border_color = Color.WHITE
			btn.add_theme_stylebox_override("normal", n_style)
			
			var nid = i
			btn.pressed.connect(func():
				selected_music_note = nid
				selected_material = _encode_music_id(selected_music_instrument, nid, selected_music_octave)
				_play_music_note(selected_music_instrument, nid, true, selected_music_octave)
				_setup_music_ui(true)
			)
			note_grid.add_child(btn)
			
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
			
			# Color matching the piano, darkened by octave index (0 = dark, 4 = bright)
			var base_color = MUSIC_INST_COLORS[selected_music_instrument]
			var max_o = 4.0
			var factor = 0.4 + (float(i) / max_o) * 0.6
			var o_color = base_color.darkened(1.0 - factor)
			
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = o_color
			b_style.set_corner_radius_all(8 * s)
			
			if i == selected_music_octave:
				b_style.border_width_left = 3; b_style.border_width_top = 3
				b_style.border_width_right = 3; b_style.border_width_bottom = 3
				b_style.border_color = Color.WHITE
			
			btn.add_theme_stylebox_override("normal", b_style)
			btn.add_theme_stylebox_override("hover", b_style)
			btn.add_theme_stylebox_override("pressed", b_style)
			
			btn.pressed.connect(func():
				selected_music_octave = i
				selected_material = _encode_music_id(selected_music_instrument, selected_music_note, selected_music_octave)
				if has_method("_play_action_sound"): _play_action_sound("ui_click")
				_setup_music_ui(true)
			)
			oct_hbox.add_child(btn)
		# Toggle "Ver notas al pulsar"
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
		var state_str = tr("active") if show_music_notes_popup else tr("inactive")
		t_btn.text = state_str
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
			if has_method("_play_action_sound"): _play_action_sound("ui_click")
			_save_tool_settings()
			_setup_music_ui(true)
		)
		toggle_hbox.add_child(t_btn)
	
	pass

func _close_music_menu():
	is_blocking = false
	ui_root = get_parent().get_node_or_null("UI")
	if ui_root:
		for child in ui_root.get_children():
			if child.name.begins_with("MusicMenuBlocker") or child.name.begins_with("MusicPanel") or child.name == "TO_DELETE":
				child.queue_free()
	circuit_panel = null
	_update_material_highlights()
	_update_menu_highlights()
	_on_arcade_selection_made(false)
	
func _setup_music_button():
	var btn = _create_vertical_category_btn("⚙️", "music")
	btn.name = "MusicBtn"
	ui_elements["music_btn"] = btn
	
	var m_style = StyleBoxFlat.new()
	m_style.bg_color = Color("#9E1FFF").darkened(0.6) # Consistent dark purple base
	m_style.border_width_left = 1; m_style.border_width_top = 1
	m_style.border_width_right = 1; m_style.border_width_bottom = 1
	m_style.border_color = Color(0.4, 0.4, 0.5) # Same border color as others
	m_style.set_corner_radius_all(0)
	
	# Apply FIXED style to all states
	btn.add_theme_stylebox_override("normal", m_style)
	btn.add_theme_stylebox_override("hover", m_style)
	btn.add_theme_stylebox_override("pressed", m_style)
	btn.add_theme_stylebox_override("focus", m_style)
	btn.set_meta("base_style", m_style)
	
	btn.pressed.connect(func():
		_play_action_sound("ui_click")
		
		# EXCLUSIVE SELECTION: Close all other panels
		is_paint_tool_active = false
		_close_all_popups()
		
		_setup_music_ui()
		_update_menu_highlights()
	)
	
	action_hbox.add_child(btn)
	ui_elements["music_btn"] = btn

func _is_music_active() -> bool:
	# Show grid if mechanisms/music menu is open OR if a musical material or mechanism drawing mode is selected
	if is_instance_valid(music_panel) and music_panel.visible:
		return true
	if is_mechanism_mode_active:
		return true
	return _is_music_mat(selected_material)

# --- SAVE / LOAD SYSTEM ---

func _setup_save_ui():
	# Close other menus first (this frees any old save_panel via queue_free)
	_close_all_popups()
	
	_set_panning_mode(false)
	var s = _get_ui_scale()
	ui_root = get_parent().get_node("UI")
	
	save_panel = PanelContainer.new()
	save_panel.name = "SavePanel"
	ui_root.add_child(save_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	panel_style.border_width_left = 3; panel_style.border_width_top = 3
	panel_style.border_width_right = 3; panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.6, 0.5, 0.2)
	panel_style.corner_radius_top_left = 30; panel_style.corner_radius_top_right = 30
	save_panel.add_theme_stylebox_override("panel", panel_style)
	save_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	save_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	save_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)

	var m_width = 530 * s
	var is_landscape = get_viewport_rect().size.x > get_viewport_rect().size.y
	var base_height = 530 * s if is_landscape else 650 * s
	var m_height = min(base_height, get_viewport_rect().size.y * 0.8)
	_align_panel_to_hud(save_panel, m_width, m_height)
	
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
	
	# Centering Container for Grid
	var grid_hbox = HBoxContainer.new()
	grid_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	grid_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_hbox)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10 * s)
	grid.add_theme_constant_override("v_separation", 15 * s)
	grid_hbox.add_child(grid)
	
	for i in range(1, 11):
		_add_save_slot_ui(grid, i)

func _add_save_slot_ui(container, slot_idx):
	var s = _get_ui_scale()
	var slot_data = _get_slot_data(slot_idx)
	
	var slot_panel = PanelContainer.new()
	slot_panel.custom_minimum_size = Vector2(235 * s, 0) # Narrower to fit 530px width, height auto-wraps
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18)
	style.set_corner_radius_all(10 * s)
	style.border_width_left = 2; style.border_width_top = 2
	style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3)
	slot_panel.add_theme_stylebox_override("panel", style)
	slot_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	slot_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
	slot_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
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
			_confirm_load(slot_idx, lbl_name.text)
		else:
			_confirm_save(slot_idx, lbl_name.text)
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
	share_btn.pressed.connect(func(): _on_share_pressed(slot_idx, lbl_name.text))
	share_hbox.add_child(share_btn)
	
	var import_btn = Button.new()
	import_btn.text = tr("import_btn_ui")
	import_btn.custom_minimum_size = Vector2(0, 45 * s)
	import_btn.add_theme_font_size_override("font_size", 20 * s)
	import_btn.add_theme_font_override("font", _get_safe_font())
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	import_btn.pressed.connect(func(): _on_import_pressed(slot_idx))
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
	save_btn.pressed.connect(func(): _confirm_save(slot_idx, lbl_name.text))
	btn_hbox.add_child(save_btn)
	
	if slot_data.has("name"):
		var load_btn = Button.new()
		load_btn.text = tr("load")
		load_btn.custom_minimum_size = Vector2(0, 45 * s)
		load_btn.add_theme_font_size_override("font_size", 20 * s)
		load_btn.add_theme_font_override("font", _get_safe_font())
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		load_btn.pressed.connect(func(): _confirm_load(slot_idx, lbl_name.text))
		btn_hbox.add_child(load_btn)

func _get_slot_data(idx):
	var path = "user://save_slot_" + str(idx) + ".dat"
	var thumb_path_jpg = "user://save_slot_" + str(idx) + ".jpg"
	var thumb_path_webp = "user://save_slot_" + str(idx) + ".webp"
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
		var _img = Image.load_from_file(final_path)
		if _img:
			data.thumbnail = ImageTexture.create_from_image(_img)
			
	return data

func _confirm_save(idx, current_name):
	var s = _get_ui_scale()
	var slot_data = _get_slot_data(idx)
	var has_thumb = slot_data.has("thumbnail")
	
	# Create a generic Control container to bypass PanelContainer layout rules on children
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
	# Corner radius matching the save_panel stylebox exactly
	d_style.corner_radius_top_left = 30
	d_style.corner_radius_top_right = 30
	d_style.corner_radius_bottom_left = 0
	d_style.corner_radius_bottom_right = 0
	dialog.add_theme_stylebox_override("panel", d_style)
	
	# Cover the entire save panel layout area
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
		_save_to_slot(idx, name_edit.text)
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
	
	# Add reference image below buttons if slot has existing data
	if has_thumb:
		var rect = TextureRect.new()
		rect.texture = slot_data.thumbnail
		rect.ignore_texture_size = true
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

func _confirm_load(idx, current_name):
	var s = _get_ui_scale()
	var slot_data = _get_slot_data(idx)
	var has_thumb = slot_data.has("thumbnail")
	
	# Create a generic Control container to bypass PanelContainer layout rules on children
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
	# Corner radius matching the save_panel stylebox exactly
	d_style.corner_radius_top_left = 30
	d_style.corner_radius_top_right = 30
	d_style.corner_radius_bottom_left = 0
	d_style.corner_radius_bottom_right = 0
	dialog.add_theme_stylebox_override("panel", d_style)
	
	# Cover the entire save panel layout area
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
		_execute_monetized_action("load", func():
			_load_from_slot(idx)
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
	
	# Add reference image below buttons if slot has existing data
	if has_thumb:
		var rect = TextureRect.new()
		rect.texture = slot_data.thumbnail
		rect.ignore_texture_size = true
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



func _sanitize_filename(filename: String) -> String:
	var invalid_chars = ["/", "\\", "?", "*", ":", "|", "\"", "<", ">"]
	var result = filename
	for c in invalid_chars:
		result = result.replace(c, "_")
	return result.strip_edges()

func _is_version_newer(imported_ver: String, current_ver: String) -> bool:
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

func _show_confirm_dialog(title_text: String, message_text: String, on_confirm: Callable):
	var s = _get_ui_scale()
	if not is_instance_valid(ui_root):
		ui_root = get_parent().get_node_or_null("UI")
		if not ui_root: return
		
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
	p_style.border_color = Color(0.8, 0.6, 0.2) # Golden border
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
	ui_root.add_child(blocker)
	
	# Position near mouse
	var screen_pos = get_viewport().get_mouse_position()
	await get_tree().process_frame # Wait for layout to calculate size
	
	if is_instance_valid(bubble):
		var bubble_size = bubble.size
		var margin_y = 20 * s
		
		var target_y = screen_pos.y - bubble_size.y - margin_y
		if target_y < 30 * s:
			target_y = screen_pos.y + 40 * s
			
		bubble.position.x = screen_pos.x - bubble_size.x / 2
		bubble.position.y = target_y
		
		var screen_size = get_viewport_rect().size
		bubble.position.x = clamp(bubble.position.x, 10 * s, screen_size.x - bubble_size.x - 10 * s)
		bubble.position.y = clamp(bubble.position.y, 10 * s, screen_size.y - bubble_size.y - 10 * s)

func _show_modal_message(title_text: String, message_text: String):
	var s = _get_ui_scale()
	var dialog_container = Control.new()
	dialog_container.name = "MessageDialogContainer"
	dialog_container.mouse_filter = Control.MOUSE_FILTER_PASS
	dialog_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if is_instance_valid(save_panel) and save_panel.visible:
		save_panel.add_child(dialog_container)
	elif is_instance_valid(workshop_panel) and workshop_panel.visible:
		workshop_panel.add_child(dialog_container)
	elif is_instance_valid(ui_root):
		ui_root.add_child(dialog_container)
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

func _check_and_request_storage_permission(on_granted: Callable):
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
	save_panel.add_child(dialog_container)
	
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
		_show_modal_message(
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

func _show_processing_overlay(text: String) -> Control:
	var s = _get_ui_scale()
	var canvas = get_tree().root.find_child("UI", true, false)
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

func _execute_monetized_action(button_type: String, action_callable: Callable):
	var overlay = _show_processing_overlay(tr("processing_creation"))
	
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

func _on_share_pressed(slot_idx: int, slot_name: String):
	_check_and_request_storage_permission(func():
		_execute_monetized_action("share", func():
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
				_show_modal_message(
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
				
			var clean_name = _sanitize_filename(slot_name)
			var export_filename = clean_name + ".sbu"
			var export_path = downloads_dir.path_join(export_filename)
			
			var sbu_file = FileAccess.open_compressed(export_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
			if sbu_file:
				sbu_file.store_var(sbu_dict, true)
				sbu_file.close()
				AnalyticsManager.log_event("world_exported", {})
				_show_modal_message(
					tr("share_btn_ui"),
					tr("export_success").format([export_filename])
				)
			else:
				_show_modal_message(
					tr("share_btn_ui"),
					tr("export_fail")
				)
		)
	)

func _on_import_pressed(slot_idx: int):
	_check_and_request_storage_permission(func():
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
			_show_modal_message(
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
		save_panel.add_child(dialog_container)
		
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
				_execute_monetized_action("import", func():
					_import_sbu_file(downloads_dir.path_join(file_name), slot_idx)
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

func _import_sbu_file(file_path: String, slot_idx: int):
	var sbu_file = FileAccess.open_compressed(file_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if not sbu_file:
		_show_modal_message(
			tr("import_btn_ui"),
			tr("import_fail")
		)
		return
		
	var sbu_dict = sbu_file.get_var(true)
	sbu_file.close()
	
	if not sbu_dict or not sbu_dict.has("grid_data"):
		_show_modal_message(
			tr("import_btn_ui"),
			tr("import_fail")
		)
		return
		
	var current_ver = str(ProjectSettings.get_setting("application/config/version", "1.2.0"))
	var imported_ver = str(sbu_dict.get("game_version", ""))
	
	if imported_ver != "" and _is_version_newer(imported_ver, current_ver):
		var msg = tr("import_newer_version_warning").format([imported_ver, current_ver])
		_show_confirm_dialog(
			tr("import_btn_ui"),
			msg,
			func():
				_execute_import_data(sbu_dict, file_path, slot_idx)
		)
	else:
		_execute_import_data(sbu_dict, file_path, slot_idx)

func _execute_import_data(sbu_dict: Dictionary, file_path: String, slot_idx: int):
	var target_dat_path = "user://save_slot_" + str(slot_idx) + ".dat"
	var target_png_path = "user://save_slot_" + str(slot_idx) + ".png"
	
	var data_dict = sbu_dict["grid_data"]
	
	var dat_file = FileAccess.open_compressed(target_dat_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if dat_file:
		dat_file.store_var(data_dict, true)
		dat_file.close()
	else:
		_show_modal_message(
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
	_show_modal_message(
		tr("import_btn_ui"),
		tr("import_success").format([file_path.get_file().left(file_path.get_file().length() - 4)])
	)
	_setup_save_ui()

func _save_to_slot(idx, custom_name: String = ""):
	var path = "user://save_slot_" + str(idx) + ".dat"
	var thumb_path = "user://save_slot_" + str(idx) + ".png"
	
	# Log to Firebase Analytics
	AnalyticsManager.log_event("save_game", {"slot": int(idx)})
	
	var time = Time.get_datetime_dict_from_system()
	var date_str = "{0}/{1}/{2} {3}:{4}".format([time.day, time.month, time.year, time.hour, time.minute])
	var save_name = custom_name if custom_name != "" else ("Save " + str(idx))
	# CLEAN CIRCULAR REFERENCES BEFORE SAVING
	# NPCs often point to each other (social_target, cached_target), which causes infinite recursion in store_var
	var clean_npcs = []
	var keys_to_nullify = ["social_target", "cached_target", "cached_closest_enemy", "cached_closest_ally", "social_partner"]
	for npc in active_npcs:
		var c = {}
		for key in npc:
			if key in keys_to_nullify:
				c[key] = null
			else:
				c[key] = npc[key]
		clean_npcs.append(c)

	var save_dict = {
		"name": save_name,
		"date": date_str,
		"width": grid_width,
		"height": grid_height,
		"grid": cells,
		"charge": charge_array,
		"tags": tags_array,
		"cell_paint": cell_paint_colors,
		"bg_paint": background_img.get_data().to_int32_array(),
		"lab_data": _get_cleaned_lab_data(),
		"npcs": clean_npcs,
		"ach_unlocked": is_achievement_menu_unlocked,
		"door_registry": door_registry.keys(),
		"door_close_timers": door_close_timers,
		"phase_block_registry": phase_block_registry.keys(),
		"frame_count": _frame_count,
		"music_tempo_frames": music_tempo_frames,
		"active_logic_gates": active_logic_gates,
		"active_pistons": active_pistons,
		"disasters": {
			"current_weather": current_weather,
			"acid_rain_intensity": acid_rain_intensity,
			"earthquake_intensity": earthquake_intensity,
			"earthquake_timer": earthquake_timer,
			"tornado_intensity": tornado_intensity,
			"tornado_timer": tornado_timer,
			"tornado_x": tornado_x,
			"tornado_target_x": tornado_target_x,
			"tornado_ground_y": tornado_ground_y,
			"tornado_element": tornado_element,
			"tsunami_intensity": tsunami_intensity,
			"tsunami_timer": tsunami_timer,
			"tsunami_wave_x": tsunami_wave_x,
			"bombardero_intensity": bombardero_intensity,
			"bombardero_x": bombardero_x,
			"bombardero_y": bombardero_y,
			"bombardero_dir": bombardero_dir,
			"bombardero_speed": bombardero_speed,
			"bombardero_drop_prob": bombardero_drop_prob,
			"bombardero_pending_checks": bombardero_pending_checks
		}
	}
	
	var file = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_var(save_dict, true)
		file.close()
		
	# CAPTURE ACCURATE MINI SCREENSHOT
	# We only capture up to dynamic_grid_height to avoid the empty HUD space
	var sample_height = dynamic_grid_height
	var thumb_w = grid_width
	var thumb_h = sample_height
	var thumb = Image.create(thumb_w, thumb_h, false, Image.FORMAT_RGBA8)
	
	for ty in range(thumb_h):
		for tx in range(thumb_w):
			# Sample the grid (1:1 Native Resolution)
			var gx = tx
			var gy = ty
			var cell_idx = gy * grid_width + gx
			var raw_id = cells[cell_idx]
			var mid = raw_id & 0xFFFF
			var variant = (raw_id >> 24) & 0xFF
			
			var color = Color(0,0,0,0) # Transparencia real
			
			# 1. Start with background paint
			var bg_color = background_img.get_pixel(gx, gy)
			if bg_color.a > 0: color = bg_color
			
			# 2. Add element (Palette or Custom)
			if mid > 0:
				var custom_i32 = cell_paint_colors[cell_idx]
				if custom_i32 != 0:
					var r = (custom_i32 & 0xFF) / 255.0
					var g = ((custom_i32 >> 8) & 0xFF) / 255.0
					var b = ((custom_i32 >> 16) & 0xFF) / 255.0
					color = Color(r, g, b, 1.0)
				else:
					var render_id = mid
					if render_id >= 10000:
						render_id = render_id % 10000
					if variant == 1: color = mat_colors_2[render_id] if render_id < mat_colors_2.size() else Color.BLACK
					elif variant == 2: color = mat_colors_3[render_id] if render_id < mat_colors_3.size() else Color.BLACK
					else: color = mat_colors_1[render_id] if render_id < mat_colors_1.size() else Color.BLACK
			
			thumb.set_pixel(tx, ty, color)
	
	var thumb_path_webp = thumb_path.replace(".png", ".webp")
	thumb.save_webp(thumb_path_webp, false) # Falso = Lossless (Sin pérdida de colores, ideal para Pixel Art)
	
	_setup_save_ui() # Refresh list

func _load_from_slot(idx):
	var path = "user://save_slot_" + str(idx) + ".dat"
	
	# Log to Firebase Analytics
	AnalyticsManager.log_event("load_game", {"slot": int(idx)})
	
	_load_world_from_path(path)

func _load_world_from_path(path: String):
	if not FileAccess.file_exists(path): return
	
	var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file:
		var dict = file.get_var(true)
		file.close()
		
		if dict:
			# 1. CLEAN CURRENT STATE
			_clear_all() 
			
			# 2. UNIFIED MAPPER (Restores Grid, Charge, Tags, Paint & Wakes Chunks)
			_map_grid_data(dict)
			
			# Map next_charge_indices to active_charge_indices immediately for first frame
			active_charge_indices = next_charge_indices
			next_charge_indices = PackedInt32Array()
			
			if dict.has("frame_count"):
				_frame_count = int(dict["frame_count"])
			else:
				_frame_count = 0
			if dict.has("music_tempo_frames"):
				music_tempo_frames = int(dict["music_tempo_frames"])

			_load_active_logic_gates(dict)
			_reconstruct_sources_from_cells(dict)
			_simulate_logic_gates()
			
			# 3. RESTORE LABORATORY EXPERIMENTS
			if dict.has("lab_data"):
				_restore_lab_data(dict["lab_data"])
				
			# 4. RESTORE DISASTERS
			if dict.has("disasters"):
				var d = dict["disasters"]
				current_weather = d.get("current_weather", 0)
				acid_rain_intensity = d.get("acid_rain_intensity", 0)
				earthquake_intensity = d.get("earthquake_intensity", 0)
				earthquake_timer = d.get("earthquake_timer", 0.0)
				tornado_intensity = d.get("tornado_intensity", 0)
				tornado_timer = d.get("tornado_timer", 0.0)
				tornado_x = d.get("tornado_x", 0.0)
				tornado_target_x = d.get("tornado_target_x", 0.0)
				tornado_ground_y = d.get("tornado_ground_y", 0.0)
				tornado_element = d.get("tornado_element", 0)
				tsunami_intensity = d.get("tsunami_intensity", 0)
				tsunami_timer = d.get("tsunami_timer", 0.0)
				tsunami_wave_x = d.get("tsunami_wave_x", 0.0)
				bombardero_intensity = d.get("bombardero_intensity", 0)
				bombardero_x = d.get("bombardero_x", 0.0)
				bombardero_y = d.get("bombardero_y", 12.0)
				bombardero_dir = d.get("bombardero_dir", 1.0)
				bombardero_speed = d.get("bombardero_speed", 0.0)
				bombardero_drop_prob = d.get("bombardero_drop_prob", 0.0)
				bombardero_pending_checks = d.get("bombardero_pending_checks", [])
				
				# Reiniciar sonidos si están activos
				if earthquake_intensity > 0: _play_action_sound("earthquake")
				if tornado_intensity > 0: _play_action_sound("tornado")
				if tsunami_intensity > 0: _play_action_sound("tsunami")
				if bombardero_intensity > 0:
					if not bombardero_texture: bombardero_texture = load("res://assets/icon_game/avion_bombardero.png")
					_manage_looping_player(bombardero_player, "bomber_engine")
					if is_instance_valid(bombardero_player): bombardero_player.volume_db = -6.0
			else:
				current_weather = 0; acid_rain_intensity = 0
				earthquake_intensity = 0; earthquake_timer = 0.0
				tornado_intensity = 0; tornado_timer = 0.0
				tsunami_intensity = 0; tsunami_timer = 0.0
				bombardero_intensity = 0; bombardero_pending_checks.clear()
				if is_instance_valid(bombardero_player) and bombardero_player.playing: bombardero_player.stop()
			
			_update_arcade_dynamic_button()
			
			if dict.has("ach_unlocked"):
				is_achievement_menu_unlocked = dict["ach_unlocked"]
				_setup_main_ui_containers() # Ensure menu appears if unlocked
				
			_update_texture()
			queue_redraw()
			if is_instance_valid(save_panel): save_panel.queue_free()

func _get_cleaned_lab_data() -> Array:
	var clean_lab = []
	for i in range(3):
		var data = lab_custom_data[i]
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

func _restore_lab_data(lab_data: Array):
	for i in range(min(3, lab_data.size())):
		var data = lab_data[i]
		lab_custom_data[i]["name"] = data.get("name", "Name")
		lab_custom_data[i]["c1"] = Color(data.get("c1", "00000000"))
		lab_custom_data[i]["c2"] = Color(data.get("c2", "00000000"))
		lab_custom_data[i]["c3"] = Color(data.get("c3", "00000000"))
		lab_custom_data[i]["mix"] = data.get("mix", 0)
		lab_custom_data[i]["grav"] = data.get("grav", 0)
		lab_custom_data[i]["state"] = data.get("state", 0)
		lab_custom_data[i]["tags"] = data.get("tags", 0)
		
		# Re-apply to engine immediately
		_apply_custom_material_to_engine(i)
		
		# Update UI LineEdit if it exists
		if ui_elements.has("lab_name_edits") and ui_elements["lab_name_edits"].size() > i:
			ui_elements["lab_name_edits"][i].text = lab_custom_data[i]["name"]
	
	# Refresh UI if it exists
	if is_instance_valid(lab_panel):
		for i in range(3):
			_update_lab_preview(i)
		_update_lab_inspector()
	
	# Always update tool list
	_update_custom_mats_in_material_grid()

func _trigger_achievement_reveal():
	# 1. Capture current button widths to prevent shrinking
	var screen_w = get_viewport_rect().size.x
	var s = _get_ui_scale()
	var h_cat = 60 * s
	var fixed_w = (screen_w - (5 * 2 * s)) / 6.0
	
	for child in action_hbox.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(fixed_w, h_cat)
			child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			child.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 2. Unlock & Persist
	is_achievement_menu_unlocked = true
	_save_global_achievements()
	
	# 3. UI Implementation
	var achievement_btn_new = _create_vertical_category_btn("🏆", "achievement_btn")
	achievement_btn_new.name = "AchievementButton"
	achievement_btn_new.custom_minimum_size = Vector2(fixed_w * 2.0, h_cat)
	achievement_btn_new.modulate.a = 0
	achievement_btn_new.pressed.connect(_setup_achievement_menu)
	achievement_btn = achievement_btn_new
	action_hbox.add_child(achievement_btn_new)
	
	var gold_style = StyleBoxFlat.new()
	gold_style.bg_color = Color("#D4AF37")
	gold_style.set_corner_radius_all(0)
	achievement_btn_new.add_theme_stylebox_override("normal", gold_style)
	achievement_btn_new.add_theme_stylebox_override("hover", gold_style)
	achievement_btn_new.add_theme_stylebox_override("pressed", gold_style)
	
	# 4. Cinematic Sequence with Background Audio
	var p = AudioStreamPlayer.new()
	p.stream = _get_sfx_stream("achievement_menu_unlock")
	p.bus = "Master"
	p.volume_db = -80
	get_tree().root.add_child(p)
	p.play()
	var audio_t = create_tween()
	audio_t.tween_property(p, "volume_db", 5.0, 0.4)
	audio_t.tween_interval(2.5)
	audio_t.tween_property(p, "volume_db", -80.0, 1.2)
	audio_t.finished.connect(p.queue_free)
	var scroll_t = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	scroll_t.tween_property(action_scroll, "scroll_horizontal", 2000, 1.5)
	await scroll_t.finished


	
	# After scroll, show button
	var fade_t = create_tween().bind_node(achievement_btn_new).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_t.tween_property(achievement_btn_new, "modulate:a", 1.0, 0.6)
	
	# Idle pulse
	if is_instance_valid(achievement_pulse_tween): achievement_pulse_tween.kill()
	achievement_pulse_tween = create_tween().set_loops().bind_node(achievement_btn_new)
	achievement_pulse_tween.tween_property(achievement_btn_new, "modulate", Color(1.3, 1.3, 1.1, 1.0), 0.8)
	achievement_pulse_tween.tween_property(achievement_btn_new, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)
	
	await fade_t.finished




func _show_achievement_notification(id: String):
	var s = _get_ui_scale()
	var viewport_w = get_viewport_rect().size.x
	
	var a = achievements[id]
	var title = a.title
	
	# 1. Ensure menu is visible (Cinematic Chain for the first time)
	if not is_achievement_menu_unlocked:
		await _trigger_achievement_reveal()
		await get_tree().create_timer(1.0).timeout # Pause for audio to breathe and impact
	else:
		var scroll_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		scroll_tween.tween_property(action_scroll, "scroll_horizontal", 2000, 1.0)
		await scroll_tween.finished
	
	# 2. Dimensions & UI Root
	var icon_size = 75 * s
	var origin_pos = Vector2(viewport_w - 100 * s, get_viewport_rect().size.y - 40 * s)
	if is_instance_valid(achievement_btn):
		origin_pos = achievement_btn.global_position + achievement_btn.size / 2.0
		# Handle pulse logic
		var is_menu_open = is_instance_valid(achievement_panel) and achievement_panel.visible
		if not is_menu_open:
			if is_instance_valid(achievement_pulse_tween): achievement_pulse_tween.kill()
			achievement_pulse_tween = achievement_btn.create_tween().set_loops()
			achievement_pulse_tween.tween_property(achievement_btn, "modulate", Color(1.3, 1.3, 1.1, 1.0), 0.8)
			achievement_pulse_tween.tween_property(achievement_btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)
	
	var toast_layer = CanvasLayer.new()
	toast_layer.layer = 100
	ui_root.add_child(toast_layer)
	
	# --- 3. UI Construction ---
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
	mask.global_position = Vector2(origin_x_right, target_y - icon_size/2.0)
	
	# --- 4. Animation Sequence ---
	# Bind Tweens to toast_layer for automatic mobile cleanup
	var t1 = create_tween().bind_node(toast_layer).set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t1.tween_property(icon_container, "scale", Vector2.ONE, 0.5)
	t1.tween_property(icon_container, "modulate:a", 1.0, 0.3)
	t1.tween_property(icon_container, "global_position:y", target_y, 0.6)
	_play_achievement_unlock_sfx(false) # Local boost +5dB
	await t1.finished
	
	await get_tree().create_timer(0.2).timeout
	mask.visible = true
	
	var t2 = create_tween().bind_node(toast_layer).set_parallel(true).set_trans(Tween.TRANS_EXPO)
	t2.tween_property(icon_container, "global_position:x", target_x + icon_size/2.0, 1.0)
	t2.tween_property(mask, "global_position:x", target_x, 1.0)
	t2.tween_property(mask, "size:x", final_w, 1.0)
	t2.tween_property(static_content, "position:x", 0, 1.0).from(final_w)
	await t2.finished
	
	# Hold for readability
	await get_tree().create_timer(1.5).timeout
	
	var t3 = create_tween().bind_node(toast_layer).set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t3.tween_property(icon_container, "global_position:y", get_viewport_rect().size.y + 200 * s, 0.8)
	t3.tween_property(mask, "global_position:y", get_viewport_rect().size.y + 200 * s, 0.8)
	t3.tween_property(icon_container, "modulate:a", 0.0, 0.5)
	t3.tween_property(mask, "modulate:a", 0.0, 0.5)
	await t3.finished
	
	if is_instance_valid(toast_layer):
		toast_layer.queue_free()

func _setup_achievement_menu():
	_play_action_sound("ui_click")
	
	# KILL THE PULSE DEFINITIVELY
	if is_instance_valid(achievement_pulse_tween):
		achievement_pulse_tween.kill()
		achievement_pulse_tween = null
	
	if is_instance_valid(achievement_btn):
		# Aggressive Reset
		var kill_tw = create_tween()
		kill_tw.tween_property(achievement_btn, "modulate", Color(1, 1, 1, 1), 0.1)
		achievement_btn.modulate = Color(1, 1, 1, 1)

	var s = _get_ui_scale()
	
	# 1. Toggle Logic like other panels
	if is_instance_valid(achievement_panel) and achievement_panel.visible:
		achievement_panel.visible = false
		_update_menu_highlights()
		return
		
	# MARK ALL AS SEEN
	var changed = false
	for id in achievements:
		if achievements[id].unlocked and not achievements[id].get("seen", false):
			achievements[id].seen = true
			changed = true
	if changed:
		_save_global_achievements()
		
	_toggle_category_panel(null) # Close others
	
	if not is_instance_valid(achievement_panel):
		achievement_panel = PanelContainer.new()
		ui_root.add_child(achievement_panel)
		achievement_panel.mouse_entered.connect(func(): is_mouse_over_ui = true)
		achievement_panel.mouse_exited.connect(func(): is_mouse_over_ui = false)
		
		var p_style = StyleBoxFlat.new()
		p_style.bg_color = Color(0.12, 0.12, 0.14, 0.98)
		p_style.corner_radius_top_left = 20 * s
		p_style.corner_radius_top_right = 20 * s
		p_style.corner_radius_bottom_left = 0
		p_style.corner_radius_bottom_right = 0
		p_style.set_border_width_all(4 * s)
		p_style.border_color = Color(0.35, 0.35, 0.4)
		achievement_panel.add_theme_stylebox_override("panel", p_style)
		
		# Position it exactly like tools/npcs
		_align_panel_to_hud(achievement_panel, 600 * s, 500 * s)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", int(35 * s))
		margin.add_theme_constant_override("margin_right", int(35 * s))
		margin.add_theme_constant_override("margin_top", int(20 * s))
		margin.add_theme_constant_override("margin_bottom", int(20 * s))
		achievement_panel.add_child(margin)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 15 * s)
		margin.add_child(vbox)
		
		# Header
		var title = Label.new()
		title.name = "AchievementMenuTitle"
		title.text = tr("achievement_menu_title")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_override("font", _get_safe_font())
		title.add_theme_font_size_override("font_size", 32 * s)
		title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		vbox.add_child(title)
		
		var scroll = ScrollContainer.new()
		scroll.name = "AchieveScroll"
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS # Allow dragging from background
		vbox.add_child(scroll)
		
		var item_vbox = VBoxContainer.new()
		item_vbox.name = "AchieveList"
		item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_vbox.add_theme_constant_override("separation", 10 * s)
		scroll.add_child(item_vbox)

	# REFRESH LIST (Reuse existing nodes to avoid stutter)
	achievement_panel.visible = true
	
	# Update Title Language
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
			# CREATE ONLY IF MISSING
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
						if dist < 12 * s: # Small threshold in screen pixels to count as tap
							var ach_id = item.get_meta("achievement_id", "")
							if ach_id != "":
								_on_achievement_item_clicked(ach_id)
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
			new_lock_label.add_theme_font_override("font", _get_safe_font())
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
			new_title.add_theme_font_override("font", _get_safe_font())
			text_vbox.add_child(new_title)
			
			var new_desc = Label.new()
			new_desc.name = "Desc"
			new_desc.add_theme_font_override("font", _get_safe_font())
			text_vbox.add_child(new_desc)
		
		# UPDATE VISUAL STATE (Cheap)
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
				icon_tex.modulate = Color(0.08, 0.08, 0.08, 0.85) # Dark silhouette for organic mystery
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
			
			# Show subtle hint for locked achievements instead of hiding description
			var hint_key = a.desc.replace("_desc", "_hint")
			a_desc.text = tr(hint_key)
			a_desc.visible = true
			a_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			a_desc.add_theme_font_size_override("font_size", 16 * s)
			a_desc.modulate = Color(0.55, 0.55, 0.6, 0.65) # Dark and mysterious gray
			
		item.add_theme_stylebox_override("panel", i_style)
		idx += 1

	_update_menu_highlights()

func _on_achievement_item_clicked(ach_id: String):
	if not achievements.has(ach_id) or not achievements[ach_id].unlocked:
		return
	
	_play_action_sound("ui_click")
	
	var s = _get_ui_scale()
	var screen_size = get_viewport_rect().size
	
	# Full-screen overlay
	var overlay = Control.new()
	overlay.name = "AchievementDetailPopup"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	
	# Close on tap/click outside/anywhere on dim
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_play_action_sound("ui_click")
			overlay.queue_free()
	)
	
	# Panel
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.1, 0.1, 0.15, 0.96)
	p_style.set_border_width_all(int(4 * s))
	p_style.border_color = Color("#D4AF37") # Gold border
	p_style.set_corner_radius_all(20 * s)
	panel.add_theme_stylebox_override("panel", p_style)
	overlay.add_child(panel)
	
	var marg = MarginContainer.new()
	var m_val = int(30 * s)
	marg.add_theme_constant_override("margin_top", m_val)
	marg.add_theme_constant_override("margin_bottom", m_val + int(20 * s)) # Extra bottom margin for position label
	marg.add_theme_constant_override("margin_left", m_val)
	marg.add_theme_constant_override("margin_right", m_val)
	panel.add_child(marg)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(18 * s))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	marg.add_child(vbox)
	
	var a = achievements[ach_id]
	
	# 1. Icon (Large)
	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(180 * s, 180 * s)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ACHIEVEMENT_ICONS.has(ach_id):
		icon_rect.texture = load(ACHIEVEMENT_ICONS[ach_id])
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon_rect)
	
	# 2. Title (Gold)
	var title_lbl = Label.new()
	title_lbl.text = tr(a.title)
	title_lbl.add_theme_font_override("font", _get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", int(26 * s))
	title_lbl.add_theme_color_override("font_color", Color("#D4AF37"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(320 * s, 0)
	vbox.add_child(title_lbl)
	
	# 3. Hint (Gray)
	var hint_lbl = Label.new()
	var hint_key = a.desc.replace("_desc", "_hint")
	hint_lbl.text = tr(hint_key)
	hint_lbl.add_theme_font_override("font", _get_safe_font())
	hint_lbl.add_theme_font_size_override("font_size", int(18 * s))
	hint_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.custom_minimum_size = Vector2(320 * s, 0)
	vbox.add_child(hint_lbl)
	
	# 4. Description (Gold)
	var desc_lbl = Label.new()
	desc_lbl.text = tr(a.desc)
	desc_lbl.add_theme_font_override("font", _get_safe_font())
	desc_lbl.add_theme_font_size_override("font_size", int(22 * s))
	desc_lbl.add_theme_color_override("font_color", Color("#D4AF37"))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(320 * s, 0)
	vbox.add_child(desc_lbl)
	
	# Close / OK Button (Premium styled)
	var close_btn = Button.new()
	close_btn.text = "OK"
	close_btn.custom_minimum_size = Vector2(120 * s, 50 * s)
	close_btn.add_theme_font_override("font", _get_safe_font())
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
		_play_action_sound("ui_click")
		overlay.queue_free()
	)
	vbox.add_child(close_btn)
	
	# Position Label (Bottom-right corner)
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
	pos_lbl.add_theme_font_override("font", _get_safe_font())
	pos_lbl.add_theme_font_size_override("font_size", int(14 * s))
	pos_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	pos_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	pos_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	corner_margin.add_child(pos_lbl)
	
	# Center panel on screen
	await get_tree().process_frame
	var p_size = panel.get_combined_minimum_size()
	panel.position = (screen_size - p_size) / 2.0


func _show_thank_you_popup(prev_paused: bool):
	var s = _get_ui_scale()
	var screen_size = get_viewport_rect().size
	
	# Full-screen dimmed overlay
	var overlay = Control.new()
	overlay.name = "ThankYouPopupOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(overlay)
	
	# Translucent background
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75) # Deep dimmer
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	
	# PanelContainer (Background container with slate/navy fill and corner radius)
	var panel = PanelContainer.new()
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.98) # Elegant dark slate/navy
	bg_style.set_corner_radius_all(24 * s) # Smooth rounded corners
	bg_style.shadow_size = 0 # No shadow on the background container itself
	panel.add_theme_stylebox_override("panel", bg_style)
	
	# Center the panel in the overlay
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)
	
	# Glow Panel (Renders the white border and shadow, colored by the neon shader)
	var glow_panel = Panel.new()
	glow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.0, 0.0, 0.0, 0.0) # Transparent background
	p_style.set_border_width_all(int(6 * s)) # Thicker border for a neon tube look
	p_style.border_color = Color(1.0, 1.0, 1.0, 1.0) # White base border to be replaced by shader
	p_style.set_corner_radius_all(24 * s)
	p_style.draw_center = false # Do not draw background for the glow panel (prevents overlapping parent)
	
	# Add shadow properties to simulate neon glow aura (colored by shader)
	p_style.shadow_color = Color(1.0, 1.0, 1.0, 1.0) # Fully bright white shadow base
	p_style.shadow_size = int(72 * s) # Wide, diffuse shadow size for a soft neon glow
	p_style.shadow_offset = Vector2.ZERO
	glow_panel.add_theme_stylebox_override("panel", p_style)
	
	# Neon rotating multicolor border shader
	var neon_shader = Shader.new()
	neon_shader.code = "shader_type canvas_item;
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
	
	// Bright core effect: blend with white where alpha is high (border itself)
	// Completely branchless transition using clamp
	float core_factor = clamp((COLOR.a - 0.7) / 0.3, 0.0, 1.0);
	vec3 neon_color = mix(rgb, vec3(1.0), core_factor * 0.55);
	
	// Soft/diffuse fade: use a power curve (> 1.0) to make the outer edges
	// blend completely imperceptibly into the dark background, avoiding hard contours.
	float alpha = pow(COLOR.a, 2.2);
	
	COLOR = vec4(neon_color, alpha * 0.95);
}"
	var neon_mat = ShaderMaterial.new()
	neon_mat.shader = neon_shader
	neon_mat.set_shader_parameter("time_speed", 0.06) # Slower, elegant neon rotation
	glow_panel.material = neon_mat
	panel.add_child(glow_panel)
	
	# Margin Container
	var marg = MarginContainer.new()
	var m_val = int(25 * s)
	marg.add_theme_constant_override("margin_top", m_val)
	marg.add_theme_constant_override("margin_bottom", m_val)
	marg.add_theme_constant_override("margin_left", m_val)
	marg.add_theme_constant_override("margin_right", m_val)
	panel.add_child(marg)
	
	# VBoxContainer for layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(15 * s))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	marg.add_child(vbox)
	
	# Images and messages setup
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
	
	# Cargar o inicializar los pools persistentes para que no se repitan
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
			
	# Si están vacíos, rellenar y mezclar
	if remaining_images.size() == 0:
		remaining_images = [0, 1, 2, 3, 4, 5]
		remaining_images.shuffle()
	if remaining_messages.size() == 0:
		remaining_messages = [0, 1, 2, 3, 4, 5]
		remaining_messages.shuffle()
		
	# Tomar el último elemento de cada pool
	var img_idx = remaining_images.pop_back()
	var msg_idx = remaining_messages.pop_back()
	
	# Guardar los pools actualizados de inmediato
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
			# Si es una foto de contenido vertical (todas excepto la horizontal Primera_Interfaz.jpg) pero el archivo viene guardado en formato horizontal, rotar 90°
			if not img_path.ends_with("Primera_Interfaz.jpg") and raw_img.get_width() > raw_img.get_height():
				raw_img.rotate_90(0) # 0 is CLOCKWISE in Godot 4
			aspect_ratio = float(raw_img.get_width()) / float(raw_img.get_height())
			texture = ImageTexture.create_from_image(raw_img)
		else:
			texture = loaded_tex
			aspect_ratio = float(loaded_tex.get_width()) / float(loaded_tex.get_height())
		
	# Determine sizing based on screen constraints and aspect ratio
	var is_portrait = screen_size.y > screen_size.x
	var max_img_h = 0.0
	if is_portrait:
		if aspect_ratio < 1.0: # Vertical
			max_img_h = 320.0 * s
		else: # Horizontal
			max_img_h = 200.0 * s
	else:
		if aspect_ratio < 1.0: # Vertical
			max_img_h = 180.0 * s
		else: # Horizontal
			max_img_h = 140.0 * s
			
	# Panel width constraint
	panel.custom_minimum_size = Vector2(min(screen_size.x * 0.9, 450 * s), 0)
	
	# Title "Gracias por tu apoyo" in gold
	var title_lbl = Label.new()
	title_lbl.text = tr("THANKS_TITLE")
	title_lbl.add_theme_font_override("font", _get_safe_font())
	title_lbl.add_theme_font_size_override("font_size", int(26 * s)) # Large size for presence
	title_lbl.add_theme_color_override("font_color", Color("#D4AF37")) # Gold
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size = Vector2(min(screen_size.x * 0.8, 380 * s), 0)
	vbox.add_child(title_lbl)
	
	# Aspect Ratio Container for image
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
	
	# Make image interactive (clickable to zoom)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	tex_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tex_rect.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_play_action_sound("ui_click")
			_show_fullscreen_image(texture, aspect_ratio)
	)
	
	# Image descriptions mapping
	var img_keys = [
		"THANKS_IMG_TRAILER",
		"THANKS_IMG_PHOTO",
		"THANKS_IMG_INTERFACE",
		"THANKS_IMG_MUSIC",
		"THANKS_IMG_GOOGLE_PLAY",
		"THANKS_IMG_ACHIEVEMENTS"
	]
	
	# Small caption explaining the image
	var caption_lbl = Label.new()
	caption_lbl.text = tr(img_keys[img_idx])
	caption_lbl.add_theme_font_override("font", _get_safe_font())
	caption_lbl.add_theme_font_size_override("font_size", int(17 * s)) # Enlarged caption font size
	caption_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75)) # Brighter gray
	caption_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_lbl.custom_minimum_size = Vector2(min(screen_size.x * 0.8, 380 * s), 0)
	vbox.add_child(caption_lbl)
	
	# Golden legend text
	var legend_lbl = Label.new()
	var is_es = current_language.begins_with("es")
	var selected_messages = messages_es if is_es else messages_en
	legend_lbl.text = selected_messages[msg_idx]
	legend_lbl.add_theme_font_override("font", _get_safe_font())
	legend_lbl.add_theme_font_size_override("font_size", int(21 * s)) # Enlarged thank-you legend font size
	legend_lbl.add_theme_color_override("font_color", Color("#D4AF37")) # Gold
	legend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_lbl.custom_minimum_size = Vector2(min(screen_size.x * 0.8, 400 * s), 0)
	vbox.add_child(legend_lbl)
	
	# Back Button: "Volver a Sandbox Ultra"
	var back_btn = Button.new()
	back_btn.text = tr("Volver a Sandbox Ultra")
	back_btn.custom_minimum_size = Vector2(200 * s, 50 * s)
	back_btn.add_theme_font_override("font", _get_safe_font())
	back_btn.add_theme_font_size_override("font_size", int(22 * s))
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.45, 0.22, 0.9) # Emerald green
	btn_style.border_width_left = 2; btn_style.border_width_top = 2
	btn_style.border_width_right = 2; btn_style.border_width_bottom = 2
	btn_style.border_color = Color(0.3, 0.7, 0.4)
	btn_style.corner_radius_top_left = 12 * s; btn_style.corner_radius_top_right = 12 * s
	btn_style.corner_radius_bottom_left = 12 * s; btn_style.corner_radius_bottom_right = 12 * s
	
	back_btn.add_theme_stylebox_override("normal", btn_style)
	back_btn.add_theme_stylebox_override("hover", btn_style)
	back_btn.add_theme_stylebox_override("pressed", btn_style)
	back_btn.add_theme_color_override("font_color", Color.WHITE)
	
	back_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		overlay.queue_free()
		
		# Restore original pause state
		is_paused = prev_paused
		
		var p_btn = ui_elements.get("pause_btn")
		if is_instance_valid(p_btn):
			p_btn.text = tr("play") if is_paused else tr("pause")
			
		var players = [weather_player, quake_player, tornado_player, tsunami_player, firework_player, ascent_player, volcano_loop_player, fire_loop_player, bombardero_player]
		for p in players:
			if is_instance_valid(p):
				p.stream_paused = is_paused
	)
	vbox.add_child(back_btn)


func _show_fullscreen_image(tex: Texture2D, ratio: float):
	var s = _get_ui_scale()
	var v_size = get_viewport_rect().size
	
	# Zoom overlay on top of everything
	var zoom_overlay = Control.new()
	zoom_overlay.name = "ZoomOverlay"
	zoom_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(zoom_overlay)
	
	# Solid/Deep black background
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.98) # Dark elegant backdrop
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom_overlay.add_child(bg)
	
	# Center VBox layout to align the aspect container and the close button
	var center_vbox = VBoxContainer.new()
	center_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.add_theme_constant_override("separation", int(20 * s))
	zoom_overlay.add_child(center_vbox)
	
	# Calculate maximum size for zoomed image to fit nicely within viewport
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
	
	# Close button ("X")
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(60 * s, 60 * s)
	close_btn.add_theme_font_override("font", _get_safe_font())
	close_btn.add_theme_font_size_override("font_size", int(28 * s))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var x_style = StyleBoxFlat.new()
	x_style.bg_color = Color(0.25, 0.25, 0.3, 0.85)
	x_style.border_width_left = int(2 * s); x_style.border_width_top = int(2 * s)
	x_style.border_width_right = int(2 * s); x_style.border_width_bottom = int(2 * s)
	x_style.border_color = Color(0.83, 0.69, 0.22) # Gold border matches panel
	x_style.set_corner_radius_all(30 * s) # Circular button
	
	close_btn.add_theme_stylebox_override("normal", x_style)
	close_btn.add_theme_stylebox_override("hover", x_style)
	close_btn.add_theme_stylebox_override("pressed", x_style)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	
	close_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		zoom_overlay.queue_free()
	)
	center_vbox.add_child(close_btn)
	
	# Clicking anywhere on the background also closes it
	zoom_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_play_action_sound("ui_click")
			zoom_overlay.queue_free()
	)

func _is_cannon_powered(c) -> bool:
	var cx = c.pos.x
	var cy = c.pos.y
	for oy in range(4):
		for ox in range(4):
			var idx = (cy + oy) * grid_width + (cx + ox)
			if idx >= 0 and idx < cells.size():
				if charge_array[idx] > 0 or active_battery_indices.has(idx):
					return true
	return false

func _is_pipe_connected_on_inlet(c, pt: Vector2i, is_x2: bool) -> bool:
	var inlet_side = c.get("inlet_side", "left")
	var cx = c.pos.x
	var cy = c.pos.y
	
	if pt.x == cx + 2 and pt.y == cy + 2:
		return true
		
	if not is_x2:
		if inlet_side == "left":
			return pt.x == cx - 5 and pt.y >= cy and pt.y <= cy + 3
		elif inlet_side == "right":
			return pt.x == cx + 8 and pt.y >= cy and pt.y <= cy + 3
		elif inlet_side == "top":
			return pt.y == cy - 5 and pt.x >= cx and pt.x <= cx + 3
		elif inlet_side == "bottom":
			return pt.y == cy + 8 and pt.x >= cx and pt.x <= cx + 3
	else:
		if inlet_side == "left":
			return abs(pt.x - (cx - 5)) <= 4 and abs(pt.y - (cy + 1.5)) <= 4
		elif inlet_side == "right":
			return abs(pt.x - (cx + 8)) <= 4 and abs(pt.y - (cy + 1.5)) <= 4
		elif inlet_side == "top":
			return abs(pt.y - (cy - 5)) <= 4 and abs(pt.x - (cx + 1.5)) <= 4
		elif inlet_side == "bottom":
			return abs(pt.y - (cy + 8)) <= 4 and abs(pt.x - (cx + 1.5)) <= 4
	return false

func _find_connected_pipe_and_endpoint(c) -> Dictionary:
	for p in active_pipes:
		var path = p.get("path", [])
		var L = path.size()
		if L == 0: continue
		
		# Check start endpoint (path[0])
		var pt0 = path[0]
		if _is_pipe_connected_on_inlet(c, pt0, false):
			return { "pipe": p, "endpoint_idx": 0 }
				
		# Check end endpoint (path[L-1])
		var ptL = path[L - 1]
		if _is_pipe_connected_on_inlet(c, ptL, false):
			return { "pipe": p, "endpoint_idx": L - 1 }
				
	for p in active_pipes_x2:
		var path = p.get("path", [])
		var L = path.size()
		if L == 0: continue
		
		# Check start endpoint (path[0]) for double pipe (8x8 blocks)
		var pt0 = path[0]
		if _is_pipe_connected_on_inlet(c, pt0, true):
			return { "pipe": p, "endpoint_idx": 0 }
				
		# Check end endpoint (path[L-1]) for double pipe (8x8 blocks)
		var ptL = path[L - 1]
		if _is_pipe_connected_on_inlet(c, ptL, true):
			return { "pipe": p, "endpoint_idx": L - 1 }
				
	return {}

func _find_connected_cannon(pt: Vector2i) -> Dictionary:
	for c in active_cannons:
		if abs(pt.x - c.pos.x) <= 4 and abs(pt.y - c.pos.y) <= 8:
			if abs(pt.x - c.pos.x) < 4 or abs(pt.y - c.pos.y) < 8:
				return { "cannon": c }
	return {}

func _is_cannon_base_material(mat: int) -> bool:
	return mat == 95 or mat == 195 or mat == 295 or mat == 395 or mat == 495 or mat == 595 or mat == 695 or mat == 795

func _get_next_cannon_shoot_material(c) -> int:
	var loaded_mat = c.get("loaded_material", 0)
	if loaded_mat > 0:
		c["loaded_material"] = 0
		return loaded_mat
		
	var end_info = _find_connected_pipe_and_endpoint(c)
	if not end_info.is_empty():
		var p = end_info["pipe"]
		var idx = end_info["endpoint_idx"]
		var elems = p.elements[idx]
		for i in range(elems.size()):
			var elem = elems[i]
			if not elem.has("npc_id") and elem.get("mat", 0) > 0:
				var mat = elem.mat
				elems.remove_at(i)
				return mat
				
	return _find_cannon_inlet_material(c)

func _fire_cannon(c, loaded_mat1: int = 0, loaded_mat2: int = 0, is_stream: bool = false):
	var orient = c.get("orientation", 0)
	var start_x = float(c.pos.x)
	var start_y = float(c.pos.y)
	var vx = 0.0
	var vy = 0.0
	
	var center_x = start_x
	var center_y = start_y
	var px = 0.0
	var py = 0.0
	
	if orient == 0: # 0 deg (Right)
		center_x += 5.5
		center_y += 1.5
		vx = 180.0
		vy = 0.0
		px = 0.0
		py = 1.0
	elif orient == 1: # 45 deg (Top-Right)
		center_x += 5.0
		center_y -= 2.0
		vx = 127.28
		vy = -127.28
		px = 0.707
		py = 0.707
	elif orient == 2: # 90 deg (Up)
		center_x += 1.5
		center_y -= 3.0
		vx = 0.0
		vy = -180.0
		px = 1.0
		py = 0.0
	elif orient == 3: # 135 deg (Top-Left)
		center_x -= 2.0
		center_y -= 2.0
		vx = -127.28
		vy = -127.28
		px = -0.707
		py = 0.707
	elif orient == 4: # 180 deg (Left)
		center_x -= 2.0
		center_y += 1.5
		vx = -180.0
		vy = 0.0
		px = 0.0
		py = 1.0
	elif orient == 5: # 225 deg (Bottom-Left)
		center_x -= 2.0
		center_y += 5.0
		vx = -127.28
		vy = 127.28
		px = -0.707
		py = -0.707
	elif orient == 6: # 270 deg (Down)
		center_x += 1.5
		center_y += 6.0
		vx = 0.0
		vy = 180.0
		px = 1.0
		py = 0.0
	elif orient == 7: # 315 deg (Bottom-Right)
		center_x += 5.0
		center_y += 5.0
		vx = 127.28
		vy = 127.28
		px = 0.707
		py = -0.707
		
	var power = c.get("shoot_power", CANNON_POWER_MED)
	vx *= power
	vy *= power
	
	var vol_boost = -18.0 if is_stream else -5.0
	_play_action_sound("explosion", 0.05, vol_boost, 1.8)
	
	var posA = Vector2(center_x - px * 0.5, center_y - py * 0.5)
	var posB = Vector2(center_x + px * 0.5, center_y + py * 0.5)
	
	var launch_projectile = func(pos: Vector2, mat: int):
		if mat > 0 and mat != 3:
			# Launch block material
			var tx = int(round(pos.x))
			var ty = int(round(pos.y))
			var success = false
			if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
				var old_mat = _get_cell(tx, ty)
				_set_cell(tx, ty, mat)
				success = _launch_flying_block(tx, ty, vx, vy, -1, 3.0, 120.0)
				if not success:
					_set_cell(tx, ty, old_mat)
			if not success:
				active_projectiles.append({
					"pos": pos,
					"vel": Vector2(vx, vy),
					"team": -1,
					"type": "thrown_rock",
					"life": 3.0,
					"block_material": mat,
					"atk_dmg": 1.5,
					"gravity": 120.0
				})
		else:
			# Launch fireball
			active_projectiles.append({
				"pos": pos,
				"vel": Vector2(vx, vy),
				"team": -1,
				"type": "fireball",
				"life": 3.0,
				"atk_dmg": 1.0,
				"gravity": 0.0
			})

	var fire_A = false
	var fire_B = false
	
	if loaded_mat1 > 0:
		fire_A = true
	if loaded_mat2 > 0:
		fire_B = true
	if loaded_mat1 == 0 and loaded_mat2 == 0:
		fire_A = true
		fire_B = true
		
	if fire_A:
		launch_projectile.call(posA, loaded_mat1)
	if fire_B:
		launch_projectile.call(posB, loaded_mat2)


func _find_cannon_inlet_material(c) -> int:
	var cx = c.pos.x
	var cy = c.pos.y
	var inlet_side = c.get("inlet_side", "")
	
	# Fallback if inlet_side is not set yet
	if inlet_side == "":
		var orient = c.get("orientation", 0)
		if orient == 0: inlet_side = "left"
		elif orient == 1: inlet_side = "bottom"
		elif orient == 2: inlet_side = "bottom"
		elif orient == 3: inlet_side = "bottom"
		elif orient == 4: inlet_side = "right"
		else: inlet_side = "left"
		c["inlet_side"] = inlet_side
		
	var check_cells = []
	if inlet_side == "left":
		for oy in range(4):
			check_cells.append(Vector2i(cx - 5, cy + oy))
	elif inlet_side == "right":
		for oy in range(4):
			check_cells.append(Vector2i(cx + 8, cy + oy))
	elif inlet_side == "top":
		for ox in range(4):
			check_cells.append(Vector2i(cx + ox, cy - 5))
	elif inlet_side == "bottom":
		for ox in range(4):
			check_cells.append(Vector2i(cx + ox, cy + 8))
			
	for pt in check_cells:
		if pt.x >= 0 and pt.x < grid_width and pt.y >= 0 and pt.y < dynamic_grid_height:
			var mat = _get_cell(pt.x, pt.y)
			if mat > 0 and not _is_cannon_base_material(mat) and mat != 96:
				var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
				if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
					# Absorb the cell
					_set_cell(pt.x, pt.y, 0)
					return mat
	return 0

func _simulate_cannons(delta: float):
	if cells.size() == 0: return
	var idx = active_cannons.size() - 1
	while idx >= 0:
		if idx >= active_cannons.size():
			idx -= 1
			continue
		var c = active_cannons[idx]
		
		# Lazy cleanup: check if cannon base still exists
		var base_cx = c.pos.x + 2
		var base_cy = c.pos.y + 2
		if base_cx < 0 or base_cx >= grid_width or base_cy < 0 or base_cy >= grid_height:
			active_cannons.remove_at(idx)
			idx -= 1
			continue
		var base_mat = cells[base_cy * grid_width + base_cx] & 0xFFFF
		if not _is_cannon_base_material(base_mat):
			# Clear all parts of this cannon structure to avoid orphaned pieces
			for py in range(10):
				for px in range(10):
					var tx = c.pos.x + px - 3
					var ty = c.pos.y + py - 3
					if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
						var m = cells[ty * grid_width + tx] & 0xFFFF
						if _is_cannon_base_material(m):
							_set_cell(tx, ty, 0)
			active_cannons.remove_at(idx)
			idx -= 1
			continue
			
		if c.get("cooldown", 0.0) > 0.0:
			c.cooldown -= delta
			
		if c.get("cooldown", 0.0) <= 0.0:
			var powered = _is_cannon_powered(c)
			var is_stream = powered
			var cooldown_time = 0.06 if powered else 1.0
			
			var loaded1 = _get_next_cannon_shoot_material(c)
			if loaded1 > 0:
				var loaded2 = _get_next_cannon_shoot_material(c)
				if loaded2 == 0:
					loaded2 = loaded1
				_fire_cannon(c, loaded1, loaded2, is_stream)
				c.cooldown = cooldown_time
			else:
				# 2. If no material loaded, fallback to electricity powered firing (infinite fireballs)
				if powered:
					_fire_cannon(c, 0, 0, is_stream)
					c.cooldown = cooldown_time
			
		idx -= 1

func _update_pipe_visuals(p, pass_index = -1):
	var path = p.path
	var L = path.size()
	
	var phase = _frame_count % 10
	var flow_dir = p.get("flow_dir", 0)
	
	if pass_index == -1 or pass_index == 0:
		is_hollowing_pipe = true
		
		# First pass: static pipe structure (walls + air core 0)
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			# Find connections to adjacent blocks in path
			var has_left_conn = false
			var has_right_conn = false
			var has_top_conn = false
			var has_bottom_conn = false
			
			if i > 0:
				var prev = path[i - 1]
				if prev.x == pt.x - 4 and prev.y == pt.y: has_left_conn = true
				elif prev.x == pt.x + 4 and prev.y == pt.y: has_right_conn = true
				elif prev.x == pt.x and prev.y == pt.y - 4: has_top_conn = true
				elif prev.x == pt.x and prev.y == pt.y + 4: has_bottom_conn = true
			if i < L - 1:
				var next = path[i + 1]
				if next.x == pt.x - 4 and next.y == pt.y: has_left_conn = true
				elif next.x == pt.x + 4 and next.y == pt.y: has_right_conn = true
				elif next.x == pt.x and next.y == pt.y - 4: has_top_conn = true
				elif next.x == pt.x and next.y == pt.y + 4: has_bottom_conn = true
				
			# Open visual endpoints opposite to connections
			var is_left_open = has_left_conn
			var is_right_open = has_right_conn
			var is_top_open = has_top_conn
			var is_bottom_open = has_bottom_conn
			
			if L == 1:
				is_left_open = true
				is_right_open = true
			else:
				if i == 0 or i == L - 1:
					var conn_count = int(has_left_conn) + int(has_right_conn) + int(has_top_conn) + int(has_bottom_conn)
					if conn_count == 1:
						if has_left_conn: is_right_open = true
						elif has_right_conn: is_left_open = true
						elif has_top_conn: is_bottom_open = true
						elif has_bottom_conn: is_top_open = true
						
			# Draw outer pipe walls (96) and empty cores/openings
			_set_cell(gx, gy, 96)
			_set_cell(gx + 3, gy, 96)
			_set_cell(gx, gy + 3, 96)
			_set_cell(gx + 3, gy + 3, 96)
			
			if is_top_open:
				_set_cell(gx + 1, gy, 0)
				_set_cell(gx + 2, gy, 0)
			else:
				_set_cell(gx + 1, gy, 96)
				_set_cell(gx + 2, gy, 96)
				
			if is_bottom_open:
				_set_cell(gx + 1, gy + 3, 0)
				_set_cell(gx + 2, gy + 3, 0)
			else:
				_set_cell(gx + 1, gy + 3, 96)
				_set_cell(gx + 2, gy + 3, 96)
				
			if is_left_open:
				_set_cell(gx, gy + 1, 0)
				_set_cell(gx, gy + 2, 0)
			else:
				_set_cell(gx, gy + 1, 96)
				_set_cell(gx, gy + 2, 96)
				
			if is_right_open:
				_set_cell(gx + 3, gy + 1, 0)
				_set_cell(gx + 3, gy + 2, 0)
			else:
				_set_cell(gx + 3, gy + 1, 96)
				_set_cell(gx + 3, gy + 2, 96)
				
			# Draw inner core (0)
			_set_cell(gx + 1, gy + 1, 0)
			_set_cell(gx + 2, gy + 1, 0)
			_set_cell(gx + 1, gy + 2, 0)
			_set_cell(gx + 2, gy + 2, 0)

		is_hollowing_pipe = false

	if pass_index == -1 or pass_index == 1:
		# Second pass: draw traveling elements at interpolated position
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			var elems = p.elements[i]
			if elems.size() == 0: continue
			
			# Compute interpolation target
			var next_pt = pt
			if flow_dir == 1:
				if i < L - 1:
					next_pt = path[i + 1]
				else:
					next_pt = pt
			elif flow_dir == -1:
				if i > 0:
					next_pt = path[i - 1]
				else:
					next_pt = pt
					
			var offset = Vector2i(0, 0)
			if flow_dir != 0:
				var diff = next_pt - pt
				offset = Vector2i(
					int(round(float(diff.x) / 10.0 * float(phase))),
					int(round(float(diff.y) / 10.0 * float(phase)))
				)
				
			var is_horizontal = false
			if i > 0:
				var prev = path[i - 1]
				if prev.x != pt.x: is_horizontal = true
			elif i < L - 1:
				var next = path[i + 1]
				if next.x != pt.x: is_horizontal = true
			else:
				is_horizontal = true
				
			var count = 0
			for elem in elems:
				var mat = elem.mat
				if mat > 0:
					var cx = count % 4
					var cy = int(count / 4.0)
					if is_horizontal:
						var tx = gx + cx + offset.x
						if flow_dir == -1: tx = gx + 3 - cx + offset.x
						var ty = gy + 1 + cy + offset.y
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 96: _set_cell(tx, ty, mat)
					else:
						var ty = gy + cx + offset.y
						if flow_dir == -1: ty = gy + 3 - cx + offset.y
						var tx = gx + 1 + cy + offset.x
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 96: _set_cell(tx, ty, mat)
				count += 1


func _update_pipe_x2_visuals(p, pass_index = -1):
	var path = p.path
	var L = path.size()
	
	var phase = _frame_count % 10
	var flow_dir = p.get("flow_dir", 0)
	
	if pass_index == -1 or pass_index == 0:
		# First pass: draw static structures (walls and cores set to 0)
		is_hollowing_pipe = true
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			# Find connections to adjacent blocks in path
			var has_left_conn = false
			var has_right_conn = false
			var has_top_conn = false
			var has_bottom_conn = false
			
			if i > 0:
				var prev = path[i - 1]
				if prev.x == pt.x - 8 and prev.y == pt.y: has_left_conn = true
				elif prev.x == pt.x + 8 and prev.y == pt.y: has_right_conn = true
				elif prev.x == pt.x and prev.y == pt.y - 8: has_top_conn = true
				elif prev.x == pt.x and prev.y == pt.y + 8: has_bottom_conn = true
			if i < L - 1:
				var next = path[i + 1]
				if next.x == pt.x - 8 and next.y == pt.y: has_left_conn = true
				elif next.x == pt.x + 8 and next.y == pt.y: has_right_conn = true
				elif next.x == pt.x and next.y == pt.y - 8: has_top_conn = true
				elif next.x == pt.x and next.y == pt.y + 8: has_bottom_conn = true
				
			var is_left_open = has_left_conn
			var is_right_open = has_right_conn
			var is_top_open = has_top_conn
			var is_bottom_open = has_bottom_conn
			
			if L == 1:
				is_left_open = true
				is_right_open = true
			else:
				if i == 0 or i == L - 1:
					var conn_count = int(has_left_conn) + int(has_right_conn) + int(has_top_conn) + int(has_bottom_conn)
					if conn_count == 1:
						if has_left_conn: is_right_open = true
						elif has_right_conn: is_left_open = true
						elif has_top_conn: is_bottom_open = true
						elif has_bottom_conn: is_top_open = true
						
			# Fill block with wall (97)
			for dy in range(8):
				for dx in range(8):
					_set_cell(gx + dx, gy + dy, 97)
					
			# Clear core to empty (0)
			for dy in range(2, 6):
				for dx in range(2, 6):
					_set_cell(gx + dx, gy + dy, 0)
					
			# Open visual endpoints
			if is_top_open:
				for dy in range(2):
					for dx in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)
			if is_bottom_open:
				for dy in range(6, 8):
					for dx in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)
			if is_left_open:
				for dx in range(2):
					for dy in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)
			if is_right_open:
				for dx in range(6, 8):
					for dy in range(2, 6):
						_set_cell(gx + dx, gy + dy, 0)

		is_hollowing_pipe = false

	if pass_index == -1 or pass_index == 1:
		# Second pass: draw elements at their interpolated positions
		for i in range(L):
			var pt = path[i]
			var gx = pt.x
			var gy = pt.y
			
			var block_elems = p.elements[i] if (p.has("elements") and i < p.elements.size()) else []
			if block_elems.size() == 0: continue
			
			var is_horizontal = false
			if i > 0:
				var prev = path[i - 1]
				if prev.x != pt.x: is_horizontal = true
			elif i < L - 1:
				var next = path[i + 1]
				if next.x != pt.x: is_horizontal = true
			else:
				is_horizontal = true
				
			# Compute interpolation target
			var next_pt = pt
			if flow_dir == 1:
				if i < L - 1:
					next_pt = path[i + 1]
				else:
					next_pt = pt
			elif flow_dir == -1:
				if i > 0:
					next_pt = path[i - 1]
				else:
					next_pt = pt
					
			var offset = Vector2i(0, 0)
			if flow_dir != 0:
				var diff = next_pt - pt
				offset = Vector2i(
					int(round(float(diff.x) / 10.0 * float(phase))),
					int(round(float(diff.y) / 10.0 * float(phase)))
				)
				
			var count = 0
			for elem in block_elems:
				var mat = elem.mat
				if mat > 0:
					var cx = count % 8
					var cy = int(count / 8.0)
					
					var tx = gx
					var ty = gy
					
					if is_horizontal:
						tx = gx + cx + offset.x
						if flow_dir == -1: tx = gx + 7 - cx + offset.x
						ty = gy + 2 + cy + offset.y
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 97: _set_cell(tx, ty, mat)
					else:
						ty = gy + cx + offset.y
						if flow_dir == -1: ty = gy + 7 - cx + offset.y
						tx = gx + 2 + cy + offset.x
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							if _get_cell(tx, ty) != 97: _set_cell(tx, ty, mat)
					
				count += 1


func _find_pipe_x2_endpoint_opening_side(p, endpoint_idx: int) -> String:
	var path = p.path
	var L = path.size()
	if L == 0: return ""
	var pt = path[endpoint_idx]
	
	if L == 1:
		return "horizontal"
		
	var nb = path[1] if endpoint_idx == 0 else path[L - 2]
	if nb.x > pt.x: return "left"
	if nb.x < pt.x: return "right"
	if nb.y > pt.y: return "top"
	if nb.y < pt.y: return "bottom"
	return "horizontal"

# Helper: Find NPC by ID
func _find_npc_by_id(npc_id: int) -> Variant:
	for npc in active_npcs:
		if npc.id == npc_id:
			return npc
	return null

# Helper: Find NPC at pipe endpoint opening
func _find_npc_at_pipe_endpoint(p, endpoint_idx: int, is_x2: bool) -> Variant:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = _find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	var min_x = 0
	var max_x = 0
	var min_y = 0
	var max_y = 0
	
	var block_size = 8 if is_x2 else 4
	
	if side == "left":
		min_x = gx - 2
		max_x = gx
		min_y = gy
		max_y = gy + block_size - 1
	elif side == "right":
		min_x = gx + block_size
		max_x = gx + block_size + 2
		min_y = gy
		max_y = gy + block_size - 1
	elif side == "top" or side == "horizontal":
		min_x = gx
		max_x = gx + block_size - 1
		min_y = gy - 2
		max_y = gy
	elif side == "bottom":
		min_x = gx
		max_x = gx + block_size - 1
		min_y = gy + block_size
		max_y = gy + block_size + 2
	else:
		return null
		
	for npc in active_npcs:
		if npc.hp <= 0: continue
		if npc.get("is_in_pipe", false): continue
		
		var w = npc.get("width", 2)
		var h = npc.get("height", 6)
		if npc.get("is_lying", false):
			w = npc.get("height", 6)
			h = npc.get("width", 2)
			
		var overlap_x = not (npc.pos.x + w - 1 < min_x or npc.pos.x > max_x)
		var overlap_y = not (npc.pos.y + h - 1 < min_y or npc.pos.y > max_y)
		if overlap_x and overlap_y:
			return npc
	return null

# Helper: Try to absorb NPC at pipe endpoint
func _try_absorb_npc_at_endpoint(p, endpoint_idx: int, dir: int, is_x2: bool) -> bool:
	var npc: Variant = _find_npc_at_pipe_endpoint(p, endpoint_idx, is_x2)
	if npc != null:
		var block_size = 8 if is_x2 else 4
		if _get_lut_rand() < 0.2:
			# SHREDDER! (20% chance)
			_draw_npc_pixels(npc, 0)
			_play_action_sound("volcan_burst")
			
			var debris = [11, 14, 13] # Lava (Red), Carbon (Dark), Acid (Green)
			for mat in debris:
				if is_x2:
					if p.elements[endpoint_idx].size() < 32:
						p.elements[endpoint_idx].append({ "mat": mat, "dir": dir, "lane": 2 })
				else:
					if p.elements[endpoint_idx].size() < 4:
						p.elements[endpoint_idx].append({ "mat": mat, "dir": dir })
			npc.hp = 0.0
			_set_npc_emoji(npc, "💀", 1.5)
			# Drop some blood/debris on the grid around the entrance
			var pt = p.path[endpoint_idx]
			for ox in range(block_size):
				for oy in range(block_size):
					if _get_lut_rand() < 0.3:
						var tx = pt.x + ox
						var ty = pt.y + oy
						if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
							var cell_mat = _get_cell(tx, ty)
							if cell_mat == 0 or cell_mat == 96 or cell_mat == 97:
								_set_cell(tx, ty, 11 if _get_lut_rand() < 0.5 else 13)
		else:
			# TRAVEL! (80% chance)
			_draw_npc_pixels(npc, 0)
			npc["is_in_pipe"] = true
			npc["pipe_ref"] = p
			_set_npc_emoji(npc, "😮", 1.0)
			_play_action_sound("medic_heal")
			if is_x2:
				p.elements[endpoint_idx].append({ "mat": 0, "dir": dir, "npc_id": npc.id, "lane": 2 })
			else:
				p.elements[endpoint_idx].append({ "mat": 0, "dir": dir, "npc_id": npc.id })
		return true
	return false

# Helper: Try to eject NPC from pipe
func _eject_npc_from_pipe(p, endpoint_idx: int, npc_id: int) -> bool:
	var npc: Variant = _find_npc_by_id(npc_id)
	if npc == null: return true
	
	var path = p.path
	var pt = path[endpoint_idx]
	var side = _find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	var ej_x = pt.x
	var ej_y = pt.y
	
	var is_x2 = p.elements[0].size() >= 8 if p.elements.size() > 0 else false
	var block_size = 8 if is_x2 else 4
	
	if side == "left":
		ej_x = pt.x - 2
		ej_y = pt.y + int(block_size / 2.0)
	elif side == "right":
		ej_x = pt.x + block_size
		ej_y = pt.y + int(block_size / 2.0)
	elif side == "top" or side == "horizontal":
		ej_x = pt.x + int(block_size / 2.0)
		ej_y = pt.y - 6
	elif side == "bottom":
		ej_x = pt.x + int(block_size / 2.0)
		ej_y = pt.y + block_size
		
	var found_spot = false
	var fit_x = ej_x
	var fit_y = ej_y
	
	for dx in [0, -1, 1, -2, 2]:
		for dy in [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5]:
			var tx = ej_x + dx
			var ty = ej_y + dy
			if _can_npc_fit(tx, ty, npc):
				fit_x = tx
				fit_y = ty
				found_spot = true
				break
		if found_spot: break
		
	if found_spot:
		npc["is_in_pipe"] = false
		npc.pos = Vector2i(fit_x, fit_y)
		
		npc.vx = 0.0
		npc.vy = 0.0
		if side == "left":
			npc.vx = -12.0
			npc.vy = -4.0
		elif side == "right":
			npc.vx = 12.0
			npc.vy = -4.0
		elif side == "top" or side == "horizontal":
			npc.vx = 0.0
			npc.vy = -12.0
		elif side == "bottom":
			npc.vx = 0.0
			npc.vy = 12.0
			
		_draw_npc_pixels(npc)
		_set_npc_emoji(npc, "🤪", 1.5)
		_play_action_sound("mage_shoot")
		return true
		
	return false

func _find_pipe_endpoint_opening_side(p, endpoint_idx: int) -> String:
	var path = p.path
	var L = path.size()
	if L == 0: return ""
	var pt = path[endpoint_idx]
	
	if L == 1:
		return "horizontal"
		
	var nb = path[1] if endpoint_idx == 0 else path[L - 2]
	if nb.x > pt.x: return "left"
	if nb.x < pt.x: return "right"
	if nb.y > pt.y: return "top"
	if nb.y < pt.y: return "bottom"
	return ""

func _find_pipe_absorbable_cell_at_endpoint(p, endpoint_idx: int) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = _find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	if side == "left":
		for d in range(1, 5):
			for oy in range(4):
				var tx = gx - d
				var ty = gy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 96:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	elif side == "right":
		for d in range(0, 4):
			for oy in range(4):
				var tx = gx + 4 + d
				var ty = gy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 96:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	elif side == "top" or side == "horizontal":
		for d in range(1, 5):
			for ox in range(4):
				var tx = gx + ox
				var ty = gy - d
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 96:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	elif side == "bottom":
		for d in range(0, 4):
			for ox in range(4):
				var tx = gx + ox
				var ty = gy + 4 + d
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 96:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	return Vector2i(-1, -1)

func _find_pipe_ejection_cell_at_endpoint(p, endpoint_idx: int) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = _find_pipe_endpoint_opening_side(p, endpoint_idx)
	
	if side == "bottom" or side == "horizontal":
		for ox in range(4):
			var tx = gx + ox
			var ty = gy + 4
			if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
				if _get_cell(tx, ty) == 0:
					return Vector2i(tx, ty)
	if side == "top":
		for ox in range(4):
			var tx = gx + ox
			var ty = gy - 1
			if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
				if _get_cell(tx, ty) == 0:
					return Vector2i(tx, ty)
	if side == "left" or side == "horizontal":
		for oy in range(4):
			var tx = gx - 1
			var ty = gy + oy
			if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
				if _get_cell(tx, ty) == 0:
					return Vector2i(tx, ty)
	if side == "right" or side == "horizontal":
		for oy in range(4):
			var tx = gx + 4
			var ty = gy + oy
			if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
				if _get_cell(tx, ty) == 0:
					return Vector2i(tx, ty)
	return Vector2i(-1, -1)

func _find_pipe_x2_absorbable_cell_at_endpoint(p, endpoint_idx: int) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = _find_pipe_x2_endpoint_opening_side(p, endpoint_idx)
	
	var offsets = [2, 3, 4, 5]
	
	if side == "left":
		for ox in range(1, 9):
			for oy in offsets:
				var tx = gx - ox
				var ty = gy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 97:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	elif side == "right":
		for ox in range(8, 16):
			for oy in offsets:
				var tx = gx + ox
				var ty = gy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 97:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	elif side == "top" or side == "horizontal":
		for oy in range(1, 9):
			for ox in offsets:
				var tx = gx + ox
				var ty = gy - oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 97:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	elif side == "bottom":
		for oy in range(8, 16):
			for ox in offsets:
				var tx = gx + ox
				var ty = gy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					var mat = _get_cell(tx, ty)
					if mat > 0 and not _is_cannon_base_material(mat) and mat != 97:
						var tags = material_tags_raw[_get_tags_id(mat)] if _get_tags_id(mat) < material_tags_raw.size() else 0
						if (tags & SandboxMaterial.Tags.GRAV_STATIC) == 0:
							return Vector2i(tx, ty)
	return Vector2i(-1, -1)

func _find_pipe_x2_ejection_cell_at_endpoint(p, endpoint_idx: int, preferred_lane: int = 2) -> Vector2i:
	var path = p.path
	var pt = path[endpoint_idx]
	var gx = pt.x
	var gy = pt.y
	var side = _find_pipe_x2_endpoint_opening_side(p, endpoint_idx)
	
	var offsets = []
	if preferred_lane == 2 or preferred_lane == 3:
		offsets = [3, 4, 2, 5]
	else:
		offsets = [4, 3, 5, 2]
			
	if side == "bottom" or side == "horizontal":
		for dy in [8, 9]:
			for ox in offsets:
				var tx = gx + ox
				var ty = gy + dy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					if _get_cell(tx, ty) == 0:
						return Vector2i(tx, ty)
	if side == "top":
		for dy in [1, 2]:
			for ox in offsets:
				var tx = gx + ox
				var ty = gy - dy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					if _get_cell(tx, ty) == 0:
						return Vector2i(tx, ty)
	if side == "left" or side == "horizontal":
		for dx in [1, 2]:
			for oy in offsets:
				var tx = gx - dx
				var ty = gy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					if _get_cell(tx, ty) == 0:
						return Vector2i(tx, ty)
	if side == "right" or side == "horizontal":
		for dx in [8, 9]:
			for oy in offsets:
				var tx = gx + dx
				var ty = gy + oy
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < dynamic_grid_height:
					if _get_cell(tx, ty) == 0:
						return Vector2i(tx, ty)
	return Vector2i(-1, -1)

func _simulate_pipes(_delta: float):
	if _frame_count % 10 != 0: return
	if active_pipes.size() == 0 and active_pipes_x2.size() == 0: return
	
	if true:
		for p in active_pipes:
			var path = p.get("path", [])
			var L = path.size()
			if L == 0: continue
			var end_idx = L - 1
			
			# 1. Check/update flow direction based on contents and input presence
			var total_elems = 0
			for list in p.elements:
				total_elems += list.size()
			if total_elems == 0:
				var empty_ticks = p.get("empty_ticks", 0) + 1
				p["empty_ticks"] = empty_ticks
				if empty_ticks >= 15:
					p["flow_dir"] = 0
			else:
				p["empty_ticks"] = 0
				
			if p.get("flow_dir", 0) == 0:
				var npc_0 = _find_npc_at_pipe_endpoint(p, 0, false)
				if npc_0 != null:
					p["flow_dir"] = 1
				else:
					var npc_end = _find_npc_at_pipe_endpoint(p, end_idx, false)
					if npc_end != null:
						p["flow_dir"] = -1
					else:
						var absorb_pos_0 = _find_pipe_absorbable_cell_at_endpoint(p, 0)
						if absorb_pos_0.x != -1:
							p["flow_dir"] = 1
						else:
							var absorb_pos_end = _find_pipe_absorbable_cell_at_endpoint(p, end_idx)
							if absorb_pos_end.x != -1:
								p["flow_dir"] = -1
						
			var flow_dir = p.get("flow_dir", 0)
			if flow_dir == 1:
				# --- FORWARD SIMULATION (0 -> end_idx) ---
				# Eject at end
				var end_pt = path[end_idx]
				var end_elems = p.elements[end_idx]
				var next_end_elems = []
				var end_conn = _find_connected_cannon(end_pt)
				for elem in end_elems:
					if elem.has("npc_id"):
						if not _eject_npc_from_pipe(p, end_idx, elem.npc_id):
							next_end_elems.append(elem)
					elif not end_conn.is_empty():
						var c = end_conn["cannon"]
						if c.get("loaded_material", 0) == 0:
							c["loaded_material"] = elem.mat
						else:
							next_end_elems.append(elem)
					else:
						var empty_pos = _find_pipe_ejection_cell_at_endpoint(p, end_idx)
						if empty_pos.x != -1:
							_set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_end_elems.append(elem)
				p.elements[end_idx] = next_end_elems
				
				# Propagate forward
				for i in range(L - 2, -1, -1):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i+1].size() < 8:
							p.elements[i+1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at start (0)
				while p.elements[0].size() < 8:
					if not _try_absorb_npc_at_endpoint(p, 0, 1, false):
						var absorb_pos = _find_pipe_absorbable_cell_at_endpoint(p, 0)
						if absorb_pos.x != -1:
							var mat = _get_cell(absorb_pos.x, absorb_pos.y)
							_set_cell(absorb_pos.x, absorb_pos.y, 0)
							p.elements[0].append({ "mat": mat, "dir": 1 })
						else:
							break
						
			elif flow_dir == -1:
				# --- BACKWARD SIMULATION (end_idx -> 0) ---
				# Eject at start (0)
				var start_pt = path[0]
				var start_elems = p.elements[0]
				var next_start_elems = []
				var start_conn = _find_connected_cannon(start_pt)
				for elem in start_elems:
					if elem.has("npc_id"):
						if not _eject_npc_from_pipe(p, 0, elem.npc_id):
							next_start_elems.append(elem)
					elif not start_conn.is_empty():
						var c = start_conn["cannon"]
						if c.get("loaded_material", 0) == 0:
							c["loaded_material"] = elem.mat
						else:
							next_start_elems.append(elem)
					else:
						var empty_pos = _find_pipe_ejection_cell_at_endpoint(p, 0)
						if empty_pos.x != -1:
							_set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_start_elems.append(elem)
				p.elements[0] = next_start_elems
				
				# Propagate backward
				for i in range(1, L):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i-1].size() < 8:
							p.elements[i-1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at end
				while p.elements[end_idx].size() < 8:
					if not _try_absorb_npc_at_endpoint(p, end_idx, -1, false):
						var absorb_pos = _find_pipe_absorbable_cell_at_endpoint(p, end_idx)
						if absorb_pos.x != -1:
							var mat = _get_cell(absorb_pos.x, absorb_pos.y)
							_set_cell(absorb_pos.x, absorb_pos.y, 0)
							p.elements[end_idx].append({ "mat": mat, "dir": -1 })
						else:
							break

		for p in active_pipes_x2:
			var path = p.get("path", [])
			var L = path.size()
			if L == 0: continue
			var end_idx = L - 1
			
			var total_elems = 0
			for list in p.elements:
				total_elems += list.size()
			if total_elems == 0:
				var empty_ticks = p.get("empty_ticks", 0) + 1
				p["empty_ticks"] = empty_ticks
				if empty_ticks >= 15:
					p["flow_dir"] = 0
			else:
				p["empty_ticks"] = 0
				
			if p.get("flow_dir", 0) == 0:
				var npc_0 = _find_npc_at_pipe_endpoint(p, 0, true)
				if npc_0 != null:
					p["flow_dir"] = 1
				else:
					var npc_end = _find_npc_at_pipe_endpoint(p, end_idx, true)
					if npc_end != null:
						p["flow_dir"] = -1
					else:
						var absorb_pos_0 = _find_pipe_x2_absorbable_cell_at_endpoint(p, 0)
						if absorb_pos_0.x != -1:
							p["flow_dir"] = 1
						else:
							var absorb_pos_end = _find_pipe_x2_absorbable_cell_at_endpoint(p, end_idx)
							if absorb_pos_end.x != -1:
								p["flow_dir"] = -1
						
			var flow_dir = p.get("flow_dir", 0)
			if flow_dir == 1:
				# --- FORWARD SIMULATION (0 -> end_idx) ---
				# Eject at end
				var end_elems = p.elements[end_idx]
				var next_end_elems = []
				for elem in end_elems:
					if elem.has("npc_id"):
						if not _eject_npc_from_pipe(p, end_idx, elem.npc_id):
							next_end_elems.append(elem)
					else:
						var preferred_lane = elem.get("lane", 2)
						var empty_pos = _find_pipe_x2_ejection_cell_at_endpoint(p, end_idx, preferred_lane)
						if empty_pos.x != -1:
							_set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_end_elems.append(elem)
				p.elements[end_idx] = next_end_elems
				
				# Propagate forward
				for i in range(L - 2, -1, -1):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i+1].size() < 32:
							p.elements[i+1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at start (0)
				while p.elements[0].size() < 32:
					if _try_absorb_npc_at_endpoint(p, 0, 1, true):
						continue
					var absorb_pos = _find_pipe_x2_absorbable_cell_at_endpoint(p, 0)
					if absorb_pos.x != -1:
						var mat = _get_cell(absorb_pos.x, absorb_pos.y)
						_set_cell(absorb_pos.x, absorb_pos.y, 0)
						var side = _find_pipe_x2_endpoint_opening_side(p, 0)
						var pt = path[0]
						var lane = (absorb_pos.y - pt.y) if (side == "left" or side == "right") else (absorb_pos.x - pt.x)
						p.elements[0].append({ "mat": mat, "dir": 1, "lane": lane })
					else:
						break
						
			elif flow_dir == -1:
				# --- BACKWARD SIMULATION (end_idx -> 0) ---
				# Eject at start (0)
				var start_elems = p.elements[0]
				var next_start_elems = []
				for elem in start_elems:
					if elem.has("npc_id"):
						if not _eject_npc_from_pipe(p, 0, elem.npc_id):
							next_start_elems.append(elem)
					else:
						var preferred_lane = elem.get("lane", 2)
						var empty_pos = _find_pipe_x2_ejection_cell_at_endpoint(p, 0, preferred_lane)
						if empty_pos.x != -1:
							_set_cell(empty_pos.x, empty_pos.y, elem.mat)
						else:
							next_start_elems.append(elem)
				p.elements[0] = next_start_elems
				
				# Propagate backward
				for i in range(1, L):
					var cur_elems = p.elements[i]
					var next_cur = []
					for elem in cur_elems:
						if p.elements[i-1].size() < 32:
							p.elements[i-1].append(elem)
						else:
							next_cur.append(elem)
					p.elements[i] = next_cur
					
				# Absorb at end
				while p.elements[end_idx].size() < 32:
					if _try_absorb_npc_at_endpoint(p, end_idx, -1, true):
						continue
					var absorb_pos = _find_pipe_x2_absorbable_cell_at_endpoint(p, end_idx)
					if absorb_pos.x != -1:
						var mat = _get_cell(absorb_pos.x, absorb_pos.y)
						_set_cell(absorb_pos.x, absorb_pos.y, 0)
						var side = _find_pipe_x2_endpoint_opening_side(p, end_idx)
						var pt = path[end_idx]
						var lane = (absorb_pos.y - pt.y) if (side == "left" or side == "right") else (absorb_pos.x - pt.x)
						p.elements[end_idx].append({ "mat": mat, "dir": -1, "lane": lane })
					else:
						break
						
	# (Visuals are now handled in _physics_process to run at 60 FPS)

func _is_orientation_allowed(orient: int, inlet_side: String) -> bool:
	if inlet_side == "left":
		return orient != 3 and orient != 4 and orient != 5
	elif inlet_side == "right":
		return orient != 7 and orient != 0 and orient != 1
	elif inlet_side == "top":
		return orient != 1 and orient != 2 and orient != 3
	elif inlet_side == "bottom":
		return orient != 5 and orient != 6 and orient != 7
	return true


func _open_cannon_settings_panel(c):
	if is_instance_valid(cannon_settings_panel):
		cannon_settings_panel.queue_free()
		
	var s = _get_ui_scale()
	
	cannon_settings_panel = PanelContainer.new()
	cannon_settings_panel.name = "CannonSettingsPanel"
	ui_root.add_child(cannon_settings_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95) # Dark premium slate
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.8, 0.6, 0.2) # Glowing gold border
	panel_style.corner_radius_top_left = 24
	panel_style.corner_radius_top_right = 24
	panel_style.corner_radius_bottom_left = 24
	panel_style.corner_radius_bottom_right = 24
	cannon_settings_panel.add_theme_stylebox_override("panel", panel_style)
	cannon_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	_align_panel_to_hud(cannon_settings_panel, 340 * s, 460 * s)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15 * s)
	cannon_settings_panel.add_child(main_vbox)
	
	# Header
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	var spacer_left = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_left)
	
	var title = Label.new()
	title.text = "Controlador"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 28 * s)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	header_hbox.add_child(title)
	
	var spacer_right = Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_right)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40 * s, 40 * s)
	close_btn.add_theme_font_override("font", _get_safe_font())
	close_btn.add_theme_font_size_override("font_size", 18 * s)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.35, 0.15, 0.15, 0.8)
	close_style.set_corner_radius_all(20 * s)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		cannon_settings_panel.queue_free()
	)
	header_hbox.add_child(close_btn)
	
	var div = ColorRect.new()
	div.custom_minimum_size.y = 2 * s
	div.color = Color(0.3, 0.3, 0.4, 0.5)
	main_vbox.add_child(div)
	
	# Direction row
	var dir_hbox = HBoxContainer.new()
	dir_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dir_hbox.add_theme_constant_override("separation", 20 * s)
	main_vbox.add_child(dir_hbox)
	
	var btn_left = Button.new()
	btn_left.text = "◀"
	btn_left.custom_minimum_size = Vector2(50 * s, 50 * s)
	btn_left.add_theme_font_size_override("font_size", 22 * s)
	var arrow_style = StyleBoxFlat.new()
	arrow_style.bg_color = Color(0.2, 0.2, 0.28, 0.9)
	arrow_style.border_width_left = 1; arrow_style.border_width_top = 1; arrow_style.border_width_right = 1; arrow_style.border_width_bottom = 1
	arrow_style.border_color = Color(0.5, 0.5, 0.6)
	arrow_style.set_corner_radius_all(10 * s)
	btn_left.add_theme_stylebox_override("normal", arrow_style)
	dir_hbox.add_child(btn_left)
	
	var dir_label = Label.new()
	dir_label.text = "Dirección"
	dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dir_label.add_theme_font_override("font", _get_safe_font())
	dir_label.add_theme_font_size_override("font_size", 20 * s)
	dir_hbox.add_child(dir_label)
	
	var btn_right = Button.new()
	btn_right.text = "▶"
	btn_right.custom_minimum_size = Vector2(50 * s, 50 * s)
	btn_right.add_theme_font_size_override("font_size", 22 * s)
	btn_right.add_theme_stylebox_override("normal", arrow_style)
	dir_hbox.add_child(btn_right)
	
	# Preview
	var preview_container = PanelContainer.new()
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.04, 0.04, 0.06, 1.0)
	preview_style.border_width_left = 2; preview_style.border_width_top = 2; preview_style.border_width_right = 2; preview_style.border_width_bottom = 2
	preview_style.border_color = Color(0.25, 0.25, 0.35)
	preview_style.corner_radius_top_left = 12
	preview_style.corner_radius_top_right = 12
	preview_style.corner_radius_bottom_left = 12
	preview_style.corner_radius_bottom_right = 12
	preview_container.add_theme_stylebox_override("panel", preview_style)
	preview_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(preview_container)
	
	var preview_ctrl = Control.new()
	preview_ctrl.custom_minimum_size = Vector2(180 * s, 180 * s)
	preview_container.add_child(preview_ctrl)
	
	var conn_label = Label.new()
	conn_label.text = "Conexión de Tubería"
	conn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conn_label.add_theme_font_override("font", _get_safe_font())
	conn_label.add_theme_font_size_override("font_size", 18 * s)
	conn_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(conn_label)
	
	var redraw_preview = func():
		preview_ctrl.queue_redraw()
		
	var update_cannon_in_grid = func():
		for py in range(12):
			for px in range(12):
				var tx = c.pos.x + px - 4
				var ty = c.pos.y + py - 4
				if tx >= 0 and tx < grid_width and ty >= 0 and ty < grid_height:
					_set_cell(tx, ty, 0)
					
		var inlet_side = c.get("inlet_side", "left")
		var active_cells = _get_cannon_active_cells(c.orientation, inlet_side)
		var mat_id = 95 + c.orientation * 100
		for pt in active_cells:
			var tx = c.pos.x + pt.x - 4
			var ty = c.pos.y + pt.y - 4
			if tx >= 0 and tx < grid_width and ty >= 0 and ty < grid_height:
				var variant = pt.x | (pt.y << 4)
				var val_encoded = mat_id | (variant << 24)
				_set_cell(tx, ty, val_encoded)
				
	btn_left.pressed.connect(func():
		_play_action_sound("ui_click")
		var next_orient = (c.orientation + 1) % 8
		while not _is_orientation_allowed(next_orient, c.get("inlet_side", "left")):
			next_orient = (next_orient + 1) % 8
		c.orientation = next_orient
		update_cannon_in_grid.call()
		redraw_preview.call()
	)
	
	btn_right.pressed.connect(func():
		_play_action_sound("ui_click")
		var prev_orient = (c.orientation + 7) % 8
		while not _is_orientation_allowed(prev_orient, c.get("inlet_side", "left")):
			prev_orient = (prev_orient + 7) % 8
		c.orientation = prev_orient
		update_cannon_in_grid.call()
		redraw_preview.call()
	)
	
	preview_ctrl.draw.connect(func():
		var size = preview_ctrl.size
		var pixel_size = size.x / 12.0
		var inlet_side = c.get("inlet_side", "left")
		
		# Draw stand/base dynamically based on inlet_side (White)
		var stand_cells = []
		if inlet_side == "bottom":
			stand_cells = [
				Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7),
				Vector2i(3, 8), Vector2i(6, 8),
				Vector2i(3, 9), Vector2i(6, 9),
				Vector2i(3, 10), Vector2i(6, 10)
			]
		elif inlet_side == "top":
			stand_cells = [
				Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
				Vector2i(3, 1), Vector2i(6, 1),
				Vector2i(3, 0), Vector2i(6, 0),
				Vector2i(3, -1), Vector2i(6, -1)
			]
		elif inlet_side == "left":
			stand_cells = [
				Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6),
				Vector2i(1, 3), Vector2i(1, 6),
				Vector2i(0, 3), Vector2i(0, 6),
				Vector2i(-1, 3), Vector2i(-1, 6)
			]
		elif inlet_side == "right":
			stand_cells = [
				Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6),
				Vector2i(8, 3), Vector2i(8, 6),
				Vector2i(9, 3), Vector2i(9, 6),
				Vector2i(10, 3), Vector2i(10, 6)
			]
			
		for cell in stand_cells:
			var rect = Rect2((cell.x + 1) * pixel_size, (cell.y + 1) * pixel_size, pixel_size, pixel_size)
			preview_ctrl.draw_rect(rect, Color.WHITE)
			
		# Draw body
		var body_color = Color(0.25, 0.3, 0.38)
		for py in range(3, 7):
			for px in range(3, 7):
				var rect = Rect2((px + 1) * pixel_size, (py + 1) * pixel_size, pixel_size, pixel_size)
				preview_ctrl.draw_rect(rect, body_color)
				
		# Draw Pivot and Barrel
		var pivot_cells = []
		var barrel_cells = []
		if c.orientation == 0:
			pivot_cells = [Vector2i(7, 4), Vector2i(7, 5)]
			barrel_cells = [Vector2i(8, 4), Vector2i(8, 5)]
		elif c.orientation == 1:
			pivot_cells = [Vector2i(6, 2), Vector2i(7, 3)]
			barrel_cells = [Vector2i(7, 1), Vector2i(7, 2), Vector2i(8, 2)]
		elif c.orientation == 2:
			pivot_cells = [Vector2i(4, 2), Vector2i(5, 2)]
			barrel_cells = [Vector2i(4, 0), Vector2i(5, 0), Vector2i(4, 1), Vector2i(5, 1)]
		elif c.orientation == 3:
			pivot_cells = [Vector2i(3, 2), Vector2i(2, 3)]
			barrel_cells = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2)]
		elif c.orientation == 4:
			pivot_cells = [Vector2i(2, 4), Vector2i(2, 5)]
			barrel_cells = [Vector2i(1, 4), Vector2i(1, 5)]
		elif c.orientation == 5:
			pivot_cells = [Vector2i(3, 7), Vector2i(2, 6)]
			barrel_cells = [Vector2i(2, 8), Vector2i(2, 7), Vector2i(1, 7)]
		elif c.orientation == 6:
			pivot_cells = [Vector2i(4, 7), Vector2i(5, 7)]
			barrel_cells = [Vector2i(4, 9), Vector2i(5, 9), Vector2i(4, 8), Vector2i(5, 8)]
		elif c.orientation == 7:
			pivot_cells = [Vector2i(6, 7), Vector2i(7, 6)]
			barrel_cells = [Vector2i(7, 8), Vector2i(7, 7), Vector2i(8, 7)]
			
		for cell in pivot_cells:
			var rect = Rect2((cell.x + 1) * pixel_size, (cell.y + 1) * pixel_size, pixel_size, pixel_size)
			preview_ctrl.draw_rect(rect, Color.RED)
			
		for cell in barrel_cells:
			var rect = Rect2((cell.x + 1) * pixel_size, (cell.y + 1) * pixel_size, pixel_size, pixel_size)
			preview_ctrl.draw_rect(rect, body_color)
			
		# Draw Tappable Indicator Points
		var sides = ["left", "right", "top", "bottom"]
		for side in sides:
			if _is_orientation_allowed(c.orientation, side):
				var center = Vector2(0, 0)
				if side == "left":
					center = Vector2(1.5 * pixel_size, 5.5 * pixel_size)
				elif side == "right":
					center = Vector2(10.5 * pixel_size, 5.5 * pixel_size)
				elif side == "top":
					center = Vector2(5.5 * pixel_size, 1.5 * pixel_size)
				elif side == "bottom":
					center = Vector2(5.5 * pixel_size, 10.5 * pixel_size)
					
				if side == inlet_side:
					preview_ctrl.draw_circle(center, 8 * s, Color(0.0, 0.7, 1.0))
					preview_ctrl.draw_circle(center, 4 * s, Color.WHITE)
				else:
					var pulse = 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.01)
					preview_ctrl.draw_circle(center, 8 * s * pulse, Color(0.0, 0.8, 0.4, 0.4))
					preview_ctrl.draw_circle(center, 5 * s, Color(0.0, 0.9, 0.5))
	)
	
	preview_ctrl.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = event.position
			var size = preview_ctrl.size
			var pixel_size = size.x / 12.0
			
			var sides = {
				"left": Vector2(1.5 * pixel_size, 5.5 * pixel_size),
				"right": Vector2(10.5 * pixel_size, 5.5 * pixel_size),
				"top": Vector2(5.5 * pixel_size, 1.5 * pixel_size),
				"bottom": Vector2(5.5 * pixel_size, 10.5 * pixel_size)
			}
			
			var closest_side = ""
			var min_dist = 9999.0
			for side in sides.keys():
				if _is_orientation_allowed(c.orientation, side):
					var dist = local_pos.distance_to(sides[side])
					if dist < min_dist:
						min_dist = dist
						closest_side = side
						
			if min_dist < 30 * s and closest_side != "" and closest_side != c.get("inlet_side", "left"):
				_play_action_sound("ui_click")
				c["inlet_side"] = closest_side
				update_cannon_in_grid.call()
				redraw_preview.call()
	)
	
	# Power Slider
	var power_vbox = VBoxContainer.new()
	power_vbox.add_theme_constant_override("separation", 6 * s)
	main_vbox.add_child(power_vbox)
	
	var power_label = Label.new()
	power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_label.add_theme_font_override("font", _get_safe_font())
	power_label.add_theme_font_size_override("font_size", 18 * s)
	power_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	power_vbox.add_child(power_label)
	
	var slider_hbox = HBoxContainer.new()
	slider_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	power_vbox.add_child(slider_hbox)
	
	var power_slider = HSlider.new()
	power_slider.custom_minimum_size = Vector2(220 * s, 0)
	power_slider.min_value = 0
	power_slider.max_value = 2
	power_slider.step = 1
	power_slider.tick_count = 3
	power_slider.ticks_on_borders = true
	
	var curr_p = c.get("shoot_power", CANNON_POWER_MED)
	if curr_p <= CANNON_POWER_MIN + 0.05:
		power_slider.value = 0
	elif curr_p >= CANNON_POWER_MAX - 0.05:
		power_slider.value = 2
	else:
		power_slider.value = 1
		
	var update_power_label = func(val):
		var tr_key = "cannon_power_med"
		if val == 0:
			tr_key = "cannon_power_min"
		elif val == 2:
			tr_key = "cannon_power_max"
		power_label.text = tr("cannon_power_label") % tr(tr_key)
		
	update_power_label.call(power_slider.value)
	
	power_slider.value_changed.connect(func(val):
		var p = CANNON_POWER_MED
		if val == 0:
			p = CANNON_POWER_MIN
		elif val == 2:
			p = CANNON_POWER_MAX
		c["shoot_power"] = p
		update_power_label.call(val)
		_play_action_sound("ui_click")
	)
	slider_hbox.add_child(power_slider)

func _open_led_color_panel(color_btn_ref):
	if is_instance_valid(led_color_panel):
		led_color_panel.queue_free()
		led_color_panel = null
		return
		
	# Close other settings panels if open to prevent overlap
	if is_instance_valid(cannon_settings_panel):
		cannon_settings_panel.queue_free()
		cannon_settings_panel = null
		
	var s = _get_ui_scale()
	led_color_panel = PanelContainer.new()
	led_color_panel.name = "LEDColorPanel"
	ui_root.add_child(led_color_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95) # Dark premium slate
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.25, 0.45, 0.85) # Blue theme border
	panel_style.corner_radius_top_left = 20 * s
	panel_style.corner_radius_top_right = 20 * s
	panel_style.corner_radius_bottom_left = 20 * s
	panel_style.corner_radius_bottom_right = 20 * s
	led_color_panel.add_theme_stylebox_override("panel", panel_style)
	led_color_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	_align_panel_to_hud(led_color_panel, 280 * s, 190 * s)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10 * s)
	led_color_panel.add_child(main_vbox)
	
	# Header
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	var spacer_left = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_left)
	
	var title = Label.new()
	title.text = tr("led_color_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _get_safe_font())
	title.add_theme_font_size_override("font_size", 20 * s)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	header_hbox.add_child(title)
	
	var spacer_right = Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_right)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30 * s, 30 * s)
	close_btn.add_theme_font_override("font", _get_safe_font())
	close_btn.add_theme_font_size_override("font_size", 14 * s)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.35, 0.15, 0.15, 0.8)
	close_style.set_corner_radius_all(15 * s)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_style)
	close_btn.add_theme_stylebox_override("pressed", close_style)
	close_btn.pressed.connect(func():
		_play_action_sound("ui_click")
		led_color_panel.queue_free()
		led_color_panel = null
	)
	header_hbox.add_child(close_btn)
	
	# Grid of colors
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8 * s)
	grid.add_theme_constant_override("v_separation", 8 * s)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(grid)
	
	var colors = [
		Color(1.0, 0.1, 0.1),      # Red
		Color(0.15, 0.45, 1.0),    # Blue
		Color(0.15, 1.0, 0.15),    # Green
		Color(1.0, 0.85, 0.05),    # Yellow
		Color(1.0, 1.0, 1.0),      # White
		Color(1.0, 0.25, 0.75),    # Pink
		Color(0.2, 0.8, 1.0),      # Celeste
		Color(0.5, 0.5, 0.5)       # Rainbow placeholder (animated stylebox)
	]
	
	var led_emojis = ["🔴", "🔵", "🟢", "🟡", "⚪", "💗", "💠", "🌈"]
	
	for idx in range(8):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(50 * s, 50 * s)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		
		if idx == 7:
			btn.text = "🌈"
			btn.add_theme_font_override("font", _get_safe_font())
			btn.add_theme_font_size_override("font_size", 20 * s)
		
		var b_style = StyleBoxFlat.new()
		b_style.bg_color = colors[idx]
		b_style.set_corner_radius_all(10 * s)
		if idx == selected_led_color:
			b_style.border_width_left = 2
			b_style.border_width_top = 2
			b_style.border_width_right = 2
			b_style.border_width_bottom = 2
			b_style.border_color = Color(1.0, 1.0, 0.0) # Highlight yellow
			
		btn.add_theme_stylebox_override("normal", b_style)
		btn.add_theme_stylebox_override("hover", b_style)
		btn.add_theme_stylebox_override("pressed", b_style)
		
		btn.pressed.connect(func():
			_play_action_sound("ui_click")
			selected_led_color = idx
			if is_instance_valid(color_btn_ref):
				color_btn_ref.text = led_emojis[selected_led_color]
			
			# Select LED tool automatically
			selected_material = 89
			selected_circuit_tool = ""
			is_mechanism_mode_active = true
			_close_music_menu()
			
			# Close panel
			led_color_panel.queue_free()
			led_color_panel = null
		)
		
		# Tag the rainbow button so we can animate it
		if idx == 7:
			btn.set_meta("is_rainbow_btn", true)
			
		grid.add_child(btn)


func _show_centered_bubble(msg: String, border_color: Color):
	var s = _get_ui_scale()
	if not is_instance_valid(ui_root):
		ui_root = get_parent().get_node_or_null("UI")
		if not ui_root: return
		
	var bubble = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	p_style.set_corner_radius_all(18 * s)
	p_style.border_width_left = 3 * s
	p_style.border_width_top = 3 * s
	p_style.border_width_right = 3 * s
	p_style.border_width_bottom = 3 * s
	p_style.border_color = border_color
	p_style.shadow_color = Color(0, 0, 0, 0.45)
	p_style.shadow_size = 10
	bubble.add_theme_stylebox_override("panel", p_style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20 * s)
	margin.add_theme_constant_override("margin_top", 16 * s)
	margin.add_theme_constant_override("margin_right", 20 * s)
	margin.add_theme_constant_override("margin_bottom", 16 * s)
	bubble.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15 * s)
	margin.add_child(vbox)
	
	var lbl = Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(280 * s, 0)
	lbl.add_theme_font_override("font", _get_safe_font())
	lbl.add_theme_font_size_override("font_size", 20 * s)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.text = tr("GOT_IT")
	btn.custom_minimum_size = Vector2(130 * s, 46 * s)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", _get_safe_font())
	btn.add_theme_font_size_override("font_size", 18 * s)
	var btn_style_norm = StyleBoxFlat.new()
	btn_style_norm.bg_color = border_color
	btn_style_norm.set_corner_radius_all(10 * s)
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
