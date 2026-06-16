extends PanelContainer
class_name WorldCard

enum CardMode {
	COMMUNITY,
	MANAGEMENT,
	DOWNLOADED
}

signal download_requested(world_data: Dictionary)
signal play_requested(world_data: Dictionary)
signal delete_requested(world_data: Dictionary)

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var author_label: Label = $VBoxContainer/AuthorLabel
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
		report_button.text = tr("card_report")
		report_button.pressed.connect(_on_report_button_pressed)
	if edit_button:
		edit_button.text = tr("card_edit")
		edit_button.pressed.connect(_on_edit_button_pressed)
	if delete_button:
		delete_button.text = tr("card_delete")
		delete_button.pressed.connect(_on_delete_button_pressed)

func _apply_scaling() -> void:
	var s = 1.7
	if is_inside_tree() and get_viewport_rect().size.x > get_viewport_rect().size.y:
		s = 1.7 * 1.30
		
	custom_minimum_size = Vector2(235 * s, 0) # Igual que save slot
	
	if title_label: 
		title_label.add_theme_font_size_override("font_size", 26 * s)
	if author_label:
		author_label.add_theme_font_size_override("font_size", 18 * s)
		
	if thumbnail_rect:
		thumbnail_rect.custom_minimum_size = Vector2(215 * s, 250 * s)
		thumbnail_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED # Enum 5
		
	if likes_label: likes_label.add_theme_font_size_override("font_size", 20 * s)
	if downloads_label: downloads_label.add_theme_font_size_override("font_size", 20 * s)
	
	if download_button:
		download_button.add_theme_font_size_override("font_size", 20 * s)
		download_button.custom_minimum_size = Vector2(0, 45 * s)
	if report_button:
		report_button.add_theme_font_size_override("font_size", 16 * s)
	if edit_button:
		edit_button.add_theme_font_size_override("font_size", 20 * s)
		edit_button.custom_minimum_size = Vector2(0, 45 * s)
	if delete_button:
		delete_button.add_theme_font_size_override("font_size", 20 * s)
		delete_button.custom_minimum_size = Vector2(0, 45 * s)
	if reports_label:
		reports_label.add_theme_font_size_override("font_size", 16 * s)

func setup(data: Dictionary, mode: int = CardMode.COMMUNITY) -> void:
	world_data = data
	current_mode = mode
	
	if title_label: title_label.text = data.get("title", tr("card_untitled"))
	if author_label: author_label.text = tr("card_by") + data.get("author", tr("card_anonymous"))
	if likes_label: likes_label.text = "👍 " + str(data.get("likes", 0))
	if downloads_label: downloads_label.text = "⬇️ " + str(data.get("downloads", 0))
	
	_setup_mode(mode)
	
	var url = data.get("thumbnail_url", "")
	if url != "" and thumbnail_rect:
		_download_thumbnail(url)

func _setup_mode(mode: int) -> void:
	if mode == CardMode.COMMUNITY or mode == CardMode.DOWNLOADED:
		community_buttons.visible = true
		management_buttons.visible = (mode == CardMode.DOWNLOADED)
		if mode == CardMode.DOWNLOADED:
			report_button.visible = true
			download_button.text = tr("card_play")
			if edit_button: edit_button.visible = false
			if reports_label: reports_label.visible = false
		else:
			report_button.visible = true
			download_button.text = tr("card_play_download")
	elif mode == CardMode.MANAGEMENT:
		community_buttons.visible = false
		management_buttons.visible = true
		if edit_button: edit_button.visible = true
		if reports_label: reports_label.visible = true
		reports_label.text = tr("card_reports") + str(world_data.get("reports", 0))

func _download_thumbnail(url: String) -> void:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_thumbnail_downloaded.bind(http_request))
	
	var headers = PackedStringArray()
	if Firebase.Auth.auth != null and Firebase.Auth.auth.has("idtoken"):
		headers.append("Authorization: Bearer " + Firebase.Auth.auth.idtoken)
		
	http_request.request(url, headers)

func _on_thumbnail_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
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
			print("Thumbnail loaded successfully!")
		else:
			print("Error parsing image buffer. Err code: ", err)
	else:
		print("Thumbnail download failed! Result: ", result, " HTTP Code: ", response_code)
		if body.size() > 0:
			print("Response body: ", body.get_string_from_utf8())
			
	http_request.queue_free()

func _on_main_action_button_pressed() -> void:
	if current_mode == CardMode.DOWNLOADED:
		play_requested.emit(world_data)
	else:
		download_requested.emit(world_data)

func _on_edit_button_pressed() -> void:
	print("Editar mundo: ", world_data.get("id", ""))
	# TODO: Abrir popup para cambiar nombre

func _on_delete_button_pressed() -> void:
	delete_requested.emit(world_data)
	# TODO: Confirmar y borrar de Firebase

func _on_report_button_pressed() -> void:
	print("Reportar mundo: ", world_data.get("id", ""))
	# TODO: Lógica de reporte
