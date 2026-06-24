extends PanelContainer
class_name WorldCard

enum CardMode {
	COMMUNITY,
	MANAGEMENT,
	DOWNLOADED,
	UPLOADS
}

signal download_requested(world_data: Dictionary)
signal play_requested(world_data: Dictionary)
signal delete_requested(world_data: Dictionary)
signal edit_requested(world_data: Dictionary)
signal like_requested(world_data: Dictionary)
signal unlike_requested(world_data: Dictionary)
signal report_requested(world_data: Dictionary)

var is_liked: bool = false

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var author_label: Label = $VBoxContainer/AuthorLabel
@onready var code_label: Label = $VBoxContainer/CodeLabel
@onready var thumbnail_rect: TextureRect = $VBoxContainer/ThumbnailRect
@onready var likes_label: Label = $VBoxContainer/HBoxContainer/LikesBox/LikesLabel
@onready var downloads_label: Label = $VBoxContainer/HBoxContainer/DownloadsBox/DownloadsLabel

# Contenedores de botones según modo
@onready var community_buttons: VBoxContainer = $VBoxContainer/CommunityButtons
@onready var download_button: Button = $VBoxContainer/CommunityButtons/DownloadButton
@onready var report_button: Button = $VBoxContainer/CommunityButtons/ReportButton

@onready var management_buttons: VBoxContainer = $VBoxContainer/ManagementButtons
@onready var edit_button: Button = $VBoxContainer/ManagementButtons/HBoxContainer/EditButton
@onready var delete_button: Button = $VBoxContainer/ManagementButtons/HBoxContainer/DeleteButton
@onready var reports_label: Label = $VBoxContainer/ManagementButtons/ReportsLabel

var world_data: Dictionary
var current_mode: int = CardMode.COMMUNITY

var like_button: Button = null

func _set_mouse_filter_pass_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_set_mouse_filter_pass_recursive(child)

func _ready() -> void:
	_set_mouse_filter_pass_recursive(self)
	_apply_scaling()
	
	if download_button:
		download_button.pressed.connect(_on_main_action_button_pressed)
	if report_button:
		report_button.text = "🚩 " + tr("card_report")
		report_button.pressed.connect(_on_report_button_pressed)
		
		# Crear el LikeButton clonando el ReportButton para mantener el estilo flat
		like_button = report_button.duplicate()
		like_button.name = "LikeButton"
		like_button.text = "👍 " + tr("card_like", "Dar Like")
		like_button.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		community_buttons.add_child(like_button)
		community_buttons.move_child(like_button, report_button.get_index()) # Mover arriba del reporte
		like_button.pressed.connect(_on_like_button_pressed)
		
	if edit_button:
		edit_button.text = "✏️ " + tr("card_edit", "Modificar")
		edit_button.pressed.connect(_on_edit_button_pressed)
	if delete_button:
		delete_button.text = "🗑️ " + tr("card_delete", "Borrar")
		delete_button.pressed.connect(_on_delete_button_pressed)

func _apply_scaling() -> void:
	var s = 1.7
	if is_inside_tree() and get_viewport_rect().size.x > get_viewport_rect().size.y:
		s = 1.7 * 1.30
		
	custom_minimum_size = Vector2(200 * s, 0)
	var safe_font = _get_safe_font()
	
	if title_label: 
		title_label.add_theme_font_override("font", safe_font)
		title_label.add_theme_font_size_override("font_size", 26 * s)
		title_label.custom_minimum_size = Vector2(0, 75 * s)
	if author_label:
		author_label.add_theme_font_override("font", safe_font)
		author_label.add_theme_font_size_override("font_size", 18 * s)
	if code_label:
		code_label.add_theme_font_override("font", safe_font)
		code_label.add_theme_font_size_override("font_size", 16 * s)
		
	if thumbnail_rect:
		thumbnail_rect.custom_minimum_size = Vector2(0, 200 * s)
		thumbnail_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Add background to thumbnail to preserve the "map background" look
		var bg = thumbnail_rect.get_node_or_null("ThumbBG")
		if not bg:
			bg = ColorRect.new()
			bg.name = "ThumbBG"
			bg.color = Color("#2e3036") # The original card background color
			bg.show_behind_parent = true
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			thumbnail_rect.add_child(bg)
			
		thumbnail_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		thumbnail_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not thumbnail_rect.gui_input.is_connected(_on_thumbnail_gui_input):
			thumbnail_rect.gui_input.connect(_on_thumbnail_gui_input)
		if not thumbnail_rect.draw.is_connected(_on_thumbnail_draw):
			thumbnail_rect.draw.connect(_on_thumbnail_draw)
			
	# Make the card itself black
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color("#111214") # Very dark / black
	card_style.set_corner_radius_all(10 * s)
	card_style.content_margin_left = 15 * s
	card_style.content_margin_right = 15 * s
	card_style.content_margin_top = 15 * s
	card_style.content_margin_bottom = 15 * s
	add_theme_stylebox_override("panel", card_style)
		
	if likes_label: 
		likes_label.add_theme_font_override("font", safe_font)
		likes_label.add_theme_font_size_override("font_size", 20 * s)
	if downloads_label: 
		downloads_label.add_theme_font_override("font", safe_font)
		downloads_label.add_theme_font_size_override("font_size", 20 * s)
	
	if download_button:
		download_button.add_theme_font_override("font", safe_font)
		download_button.add_theme_font_size_override("font_size", 20 * s)
		download_button.custom_minimum_size = Vector2(0, 45 * s)
	if report_button:
		report_button.add_theme_font_override("font", safe_font)
		report_button.add_theme_font_size_override("font_size", 16 * s)
	if like_button:
		like_button.add_theme_font_override("font", safe_font)
		like_button.add_theme_font_size_override("font_size", 18 * s)
	if edit_button:
		edit_button.add_theme_font_override("font", safe_font)
		edit_button.add_theme_font_size_override("font_size", 30 * s)
		edit_button.custom_minimum_size = Vector2(0, 45 * s)
	if delete_button:
		delete_button.add_theme_font_override("font", safe_font)
		delete_button.add_theme_font_size_override("font_size", 30 * s)
		delete_button.custom_minimum_size = Vector2(0, 45 * s)
	if reports_label:
		reports_label.add_theme_font_override("font", safe_font)
		reports_label.add_theme_font_size_override("font_size", 16 * s)

func setup(data: Dictionary, mode: int = CardMode.COMMUNITY) -> void:
	world_data = data
	current_mode = mode
	
	if title_label: title_label.text = data.get("title", tr("card_untitled"))
	if author_label: author_label.text = tr("card_by") + data.get("author", tr("card_anonymous"))
	
	var w_id = data.get("id", data.get("world_id", ""))
	if code_label:
		if w_id != "":
			code_label.text = "ID: " + w_id
			code_label.visible = true
			code_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			code_label.mouse_filter = Control.MOUSE_FILTER_STOP
			if not code_label.gui_input.is_connected(_on_code_label_gui_input):
				code_label.gui_input.connect(_on_code_label_gui_input)
		else:
			code_label.visible = false
			
	if likes_label: likes_label.text = "👍 " + str(data.get("likes", 0))
	if downloads_label: downloads_label.text = "⬇️ " + str(data.get("downloads", 0))
	
	_setup_mode(mode)
	
	var url = data.get("thumbnail_url", "")
	if url != "" and thumbnail_rect:
		_download_thumbnail(url)

func _on_code_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var w_id = world_data.get("id", world_data.get("world_id", ""))
		if w_id != "":
			DisplayServer.clipboard_set(w_id)
			var old_text = code_label.text
			code_label.text = tr("msg_copied")
			var t = get_tree().create_timer(1.5)
			t.timeout.connect(func():
				if is_instance_valid(code_label):
					code_label.text = old_text
			)

func _on_thumbnail_draw() -> void:
	if not is_instance_valid(thumbnail_rect) or not thumbnail_rect.texture: return
	var bg = thumbnail_rect.get_node_or_null("ThumbBG")
	if not is_instance_valid(bg): return
	
	var tex_size = thumbnail_rect.texture.get_size()
	var rect_size = thumbnail_rect.size
	if tex_size.x == 0 or tex_size.y == 0 or rect_size.x == 0 or rect_size.y == 0: return
	
	var scale_x = rect_size.x / tex_size.x
	var scale_y = rect_size.y / tex_size.y
	var min_scale = min(scale_x, scale_y)
	
	var drawn_size = tex_size * min_scale
	bg.size = drawn_size
	bg.position = (rect_size - drawn_size) / 2.0

func _on_thumbnail_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var tex = thumbnail_rect.texture
		if tex:
			var ui = get_tree().current_scene.get_node_or_null("UI")
			if ui:
				_show_large_thumbnail(tex, ui)

func _show_large_thumbnail(tex: Texture2D, ui: Node) -> void:
	var blocker = ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.92)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.z_index = 4096
	ui.add_child(blocker)
	
	blocker.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			blocker.accept_event()
			if blocker.is_inside_tree():
				blocker.get_viewport().set_input_as_handled()
			blocker.queue_free()
	)
	
	var tr_node = TextureRect.new()
	tr_node.texture = tex
	tr_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var s = 1.0
	if is_inside_tree() and get_viewport_rect().size.x > get_viewport_rect().size.y:
		s = 1.3
		
	tr_node.offset_left = 60 * s
	tr_node.offset_right = -60 * s
	tr_node.offset_top = 80 * s
	tr_node.offset_bottom = -120 * s # Make room for the button
	tr_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(tr_node)
	
	var bg = ColorRect.new()
	bg.color = Color("#2e3036")
	bg.show_behind_parent = true
	tr_node.add_child(bg)
	
	tr_node.draw.connect(func():
		var tex_size = tr_node.texture.get_size()
		var rect_size = tr_node.size
		if tex_size.x == 0 or tex_size.y == 0 or rect_size.x == 0 or rect_size.y == 0: return
		var scale_x = rect_size.x / tex_size.x
		var scale_y = rect_size.y / tex_size.y
		var min_scale = min(scale_x, scale_y)
		var drawn_size = tex_size * min_scale
		bg.size = drawn_size
		bg.position = (rect_size - drawn_size) / 2.0
	)
	
	var close_btn = Button.new()
	close_btn.text = "✖"
	close_btn.add_theme_font_override("font", _get_safe_font())
	close_btn.add_theme_font_size_override("font_size", 40 * s)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	
	var circle_style = StyleBoxFlat.new()
	circle_style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	circle_style.set_corner_radius_all(100) # Circular
	
	close_btn.add_theme_stylebox_override("normal", circle_style)
	close_btn.add_theme_stylebox_override("hover", circle_style)
	close_btn.add_theme_stylebox_override("pressed", circle_style)
	close_btn.add_theme_stylebox_override("focus", circle_style)
	
	close_btn.anchor_left = 0.5
	close_btn.anchor_right = 0.5
	close_btn.anchor_top = 1.0
	close_btn.anchor_bottom = 1.0
	close_btn.offset_left = -40 * s
	close_btn.offset_right = 40 * s
	close_btn.offset_top = -100 * s
	close_btn.offset_bottom = -20 * s
	
	close_btn.pressed.connect(func(): blocker.queue_free())
	blocker.add_child(close_btn)

func _setup_mode(mode: int) -> void:
	if mode == CardMode.COMMUNITY or mode == CardMode.DOWNLOADED:
		community_buttons.visible = true
		management_buttons.visible = (mode == CardMode.DOWNLOADED)
		
		# Modo descargas
		if mode == CardMode.DOWNLOADED:
			report_button.visible = true
			if like_button: like_button.visible = true
			download_button.text = tr("card_play")
			if edit_button: edit_button.visible = false
			if reports_label: reports_label.visible = false
		
		# Modo comunidad normal
		else:
			report_button.visible = true
			if like_button: like_button.visible = false
			download_button.text = "⬇️ " + tr("card_play_download", "Descargar")
			
	elif mode == CardMode.MANAGEMENT:
		community_buttons.visible = false
		management_buttons.visible = true
		if edit_button: edit_button.visible = true
		if reports_label:
			reports_label.visible = true
			reports_label.text = "🚩 Reportes: " + str(world_data.get("reports", 0))
	elif mode == CardMode.UPLOADS:
		community_buttons.visible = false
		management_buttons.visible = false

	call_deferred("_apply_offline_state")

func _apply_offline_state() -> void:
	if not is_inside_tree() or not get_tree() or not get_tree().current_scene: return
	var ui_node = get_tree().current_scene.get_node_or_null("UI")
	if not ui_node: return
	
	if not ui_node.get_meta("has_internet", true):
		if report_button:
			report_button.disabled = true
			report_button.modulate = Color(0.5, 0.5, 0.5)
			report_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
		if like_button:
			like_button.disabled = true
			like_button.modulate = Color(0.5, 0.5, 0.5)
			like_button.mouse_default_cursor_shape = Control.CURSOR_ARROW

func set_liked_state(liked: bool) -> void:
	is_liked = liked
	if like_button:
		if is_liked:
			like_button.modulate = Color(0.9, 0.4, 0.4) # Red color for liked
			like_button.text = tr("card_liked", "❤️ Ya te gusta")
		else:
			like_button.modulate = Color(1.0, 1.0, 1.0) # Normal color
			like_button.text = tr("card_like", "👍 Dar Like")

func _download_thumbnail(url: String) -> void:
	var world_id = world_data.get("id", "")
	var cache_path = "user://thumb_cache_" + str(world_id) + ".bin"
	
	if world_id != "" and FileAccess.file_exists(cache_path):
		var modified_time = FileAccess.get_modified_time(cache_path)
		var current_time = Time.get_unix_time_from_system()
		if (current_time - modified_time) <= (7 * 86400): # 7 días
			var f = FileAccess.open(cache_path, FileAccess.READ)
			if f:
				var body = f.get_buffer(f.get_length())
				f.close()
				if _apply_thumbnail_buffer(body):
					return # Cache válido y aplicado con éxito
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_thumbnail_downloaded.bind(http_request, cache_path))
	
	var headers = PackedStringArray()
	if Firebase.Auth.auth != null and Firebase.Auth.auth.has("idtoken"):
		headers.append("Authorization: Bearer " + Firebase.Auth.auth.idtoken)
		
	http_request.request(url, headers)

func _apply_thumbnail_buffer(body: PackedByteArray) -> bool:
	var image = Image.new()
	var is_png = body.size() > 8 and body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47
	var is_jpg = body.size() > 3 and body[0] == 0xFF and body[1] == 0xD8 and body[2] == 0xFF
	var is_webp = body.size() > 12 and body[8] == 0x57 and body[9] == 0x45 and body[10] == 0x42 and body[11] == 0x50
	
	var err = FAILED
	if is_png:
		err = image.load_png_from_buffer(body)
	elif is_jpg:
		err = image.load_jpg_from_buffer(body)
	elif is_webp:
		err = image.load_webp_from_buffer(body)
		
	if err == OK:
		var texture = ImageTexture.create_from_image(image)
		thumbnail_rect.texture = texture
		return true
	return false

func _on_thumbnail_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, cache_path: String) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		if _apply_thumbnail_buffer(body) and cache_path != "":
			var f = FileAccess.open(cache_path, FileAccess.WRITE)
			if f:
				f.store_buffer(body)
				f.close()
	http_request.queue_free()

func _on_main_action_button_pressed() -> void:
	if current_mode == CardMode.DOWNLOADED:
		play_requested.emit(world_data)
	else:
		download_requested.emit(world_data)

func _on_edit_button_pressed() -> void:
	edit_requested.emit(world_data)

func _on_delete_button_pressed() -> void:
	delete_requested.emit(world_data)
	# TODO: Confirmar y borrar de Firebase

func _on_report_button_pressed() -> void:
	report_requested.emit(world_data)

func _on_like_button_pressed() -> void:
	if is_liked:
		unlike_requested.emit(world_data)
	else:
		like_requested.emit(world_data)

static var _combined_font: FontVariation = null

func _get_safe_font() -> Font:
	if not _combined_font:
		_combined_font = FontVariation.new()
		
		# 1. FUENTE BASE (Texto estándar)
		var base_font = SystemFont.new()
		base_font.font_names = PackedStringArray(["sans-serif", "arial"])
		_combined_font.base_font = base_font
		
		# 2. FUENTE DE ICONOS
		var emoji_f: Font = null
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
				
		if emoji_f:
			_combined_font.set_fallbacks([emoji_f])
			
	return _combined_font
