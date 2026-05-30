# MIT License
# Copyright (c) 2026-present Omar Saez (Elex Studio)

extends Node

# URL del archivo de configuración JSON remoto.
# Por defecto, configurado para leer de la rama principal del repositorio de GitHub.
const CONFIG_URL = "https://raw.githubusercontent.com/OmarSaez/Sandbox-game/main/version_config.json"

# URL de respaldo de la Play Store por si el JSON no la especifica.
const DEFAULT_PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=dbox.elexstudio"

func _ready() -> void:
	# Solo realizamos la comprobación de versión en dispositivos móviles o en builds reales.
	# Si estás en el editor, puedes simularlo desactivando esta condición.
	if OS.has_feature("editor"):
		print("VERSION_MANAGER: Ejecutándose en el editor. Saltando comprobación real (puedes comentarlo para probar).")
		# return # Descomenta para probar el flujo de actualización en el editor.

	# Crear el nodo HTTPRequest de forma dinámica y añadirlo a la escena
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	print("VERSION_MANAGER: Iniciando petición HTTP a: ", CONFIG_URL)
	var error = http_request.request(CONFIG_URL)
	if error != OK:
		print("VERSION_MANAGER: Error al iniciar la petición HTTP: ", error)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("VERSION_MANAGER: Fallo al descargar el archivo de versión. Código de resultado: ", result)
		return
		
	if response_code != 200:
		print("VERSION_MANAGER: El servidor devolvió el código HTTP: ", response_code)
		return

	# Procesar el cuerpo de la respuesta JSON
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		print("VERSION_MANAGER: Error al parsear el JSON de versión.")
		return
		
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		print("VERSION_MANAGER: El JSON recibido no tiene el formato de diccionario esperado.")
		return
		
	# Extraer valores del JSON
	var latest_version = str(data.get("latest_version", "1.2.0"))
	var min_version = str(data.get("min_version", "1.2.0"))
	var update_url = str(data.get("update_url", DEFAULT_PLAY_STORE_URL))
	
	# Detectar idioma para el registro de cambios (changelog)
	var current_lang = TranslationServer.get_locale().split("_")[0]
	var changelog = ""
	if current_lang == "es":
		changelog = str(data.get("changelog_es", "Nueva versión disponible con mejoras de estabilidad."))
	else:
		changelog = str(data.get("changelog_en", "New version available with stability improvements."))
		
	# Obtener la versión actual configurada en el proyecto
	var current_version = ProjectSettings.get_setting("application/config/version", "1.2.0")
	print("VERSION_MANAGER: Versión actual: %s | Requerida mínima: %s | Última versión: %s" % [current_version, min_version, latest_version])
	
	# 1. Comprobar si requiere Actualización Crítica/Obligatoria
	if _is_version_older(current_version, min_version):
		print("VERSION_MANAGER: Versión obsoleta detectada. Mostrando bloqueo crítico.")
		_show_update_modal(changelog, update_url, true)
		
	# 2. Comprobar si requiere Actualización Opcional/Recomendada
	elif _is_version_older(current_version, latest_version):
		print("VERSION_MANAGER: Nueva actualización disponible. Mostrando aviso opcional.")
		_show_update_modal(changelog, update_url, false)
		
	else:
		print("VERSION_MANAGER: El juego está actualizado.")

# Algoritmo de comparación semántica de versiones (ej: "1.1.2" < "1.2.0")
func _is_version_older(current: String, target: String) -> bool:
	var current_parts = current.split(".")
	var target_parts = target.split(".")
	
	var max_parts = max(current_parts.size(), target_parts.size())
	for i in range(max_parts):
		var curr_val = 0
		if i < current_parts.size():
			curr_val = int(current_parts[i])
			
		var targ_val = 0
		if i < target_parts.size():
			targ_val = int(target_parts[i])
			
		if curr_val < targ_val:
			return true
		elif curr_val > targ_val:
			return false
			
	return false

# Crea e instancia la UI del aviso de actualización programáticamente
func _show_update_modal(changelog_text: String, update_url: String, is_critical: bool) -> void:
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 120 # Capa alta por encima de la UI del juego
	add_child(canvas_layer)
	
	# 1. Fondo Oscuro Semitransparente
	var background = ColorRect.new()
	background.color = Color(0.04, 0.04, 0.06, 0.0) # Empezamos transparente para animar
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP # Bloquear interacción con el fondo
	canvas_layer.add_child(background)
	
	# 2. Contenedor de Centrado
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(center)
	
	# 3. Panel de Contenido Principal
	var panel = PanelContainer.new()
	# Adaptar tamaño según plataforma
	var panel_width = 800 if not OS.has_feature("mobile") else 950
	panel.custom_minimum_size = Vector2(panel_width, 420)
	
	# Estilo visual moderno y "premium" (Dark Mode con bordes redondeados y sombra)
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.09, 0.1, 0.13, 1.0) # Slate Grey profundo
	stylebox.corner_radius_top_left = 24
	stylebox.corner_radius_top_right = 24
	stylebox.corner_radius_bottom_left = 24
	stylebox.corner_radius_bottom_right = 24
	stylebox.border_width_left = 3
	stylebox.border_width_top = 3
	stylebox.border_width_right = 3
	stylebox.border_width_bottom = 3
	
	# Borde sutil azul/morado en obligatorias, gris en opcionales
	if is_critical:
		stylebox.border_color = Color(0.3, 0.45, 0.85, 0.8)
	else:
		stylebox.border_color = Color(0.22, 0.25, 0.32, 0.8)
		
	stylebox.shadow_color = Color(0, 0, 0, 0.5)
	stylebox.shadow_size = 20
	stylebox.shadow_offset = Vector2(0, 10)
	panel.add_theme_stylebox_override("panel", stylebox)
	center.add_child(panel)
	
	# 4. Márgenes Internos
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)
	
	# 5. Caja Vertical de Elementos
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)
	
	# 6. Título del Aviso
	var title_label = Label.new()
	if is_critical:
		title_label.text = "Actualización Requerida" if TranslationServer.get_locale().split("_")[0] == "es" else "Update Required"
	else:
		title_label.text = "Actualización Disponible" if TranslationServer.get_locale().split("_")[0] == "es" else "Update Available"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	vbox.add_child(title_label)
	
	# 7. Descripción o Changelog
	var desc_label = Label.new()
	desc_label.text = changelog_text
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	vbox.add_child(desc_label)
	
	# 8. Contenedor de Botones
	var buttons_box = HBoxContainer.new()
	buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_box.add_theme_constant_override("separation", 24)
	vbox.add_child(buttons_box)
	
	# Estilos para botón "Luego" (Gris neutro)
	var style_later_normal = StyleBoxFlat.new()
	style_later_normal.bg_color = Color(0.18, 0.2, 0.24, 1.0)
	style_later_normal.corner_radius_top_left = 12
	style_later_normal.corner_radius_top_right = 12
	style_later_normal.corner_radius_bottom_left = 12
	style_later_normal.corner_radius_bottom_right = 12
	
	var style_later_hover = style_later_normal.duplicate()
	style_later_hover.bg_color = Color(0.24, 0.27, 0.32, 1.0)
	
	var style_later_pressed = style_later_normal.duplicate()
	style_later_pressed.bg_color = Color(0.12, 0.14, 0.17, 1.0)
	
	# Estilos para botón "Actualizar" (Azul Premium)
	var style_update_normal = StyleBoxFlat.new()
	style_update_normal.bg_color = Color(0.2, 0.45, 0.85, 1.0)
	style_update_normal.corner_radius_top_left = 12
	style_update_normal.corner_radius_top_right = 12
	style_update_normal.corner_radius_bottom_left = 12
	style_update_normal.corner_radius_bottom_right = 12
	
	var style_update_hover = style_update_normal.duplicate()
	style_update_hover.bg_color = Color(0.25, 0.55, 0.95, 1.0)
	
	var style_update_pressed = style_update_normal.duplicate()
	style_update_pressed.bg_color = Color(0.15, 0.35, 0.75, 1.0)
	
	# Botón "Luego" (Solo si no es crítica/obligatoria)
	if not is_critical:
		var later_btn = Button.new()
		later_btn.text = "Luego" if TranslationServer.get_locale().split("_")[0] == "es" else "Later"
		later_btn.custom_minimum_size = Vector2(160, 56)
		later_btn.add_theme_font_size_override("font_size", 18)
		later_btn.add_theme_stylebox_override("normal", style_later_normal)
		later_btn.add_theme_stylebox_override("hover", style_later_hover)
		later_btn.add_theme_stylebox_override("pressed", style_later_pressed)
		buttons_box.add_child(later_btn)
		later_btn.pressed.connect(func():
			_close_modal(canvas_layer)
		)
		
	# Botón "Actualizar" (Siempre visible)
	var update_btn = Button.new()
	update_btn.text = "Actualizar" if TranslationServer.get_locale().split("_")[0] == "es" else "Update"
	update_btn.custom_minimum_size = Vector2(180, 56)
	update_btn.add_theme_font_size_override("font_size", 18)
	update_btn.add_theme_stylebox_override("normal", style_update_normal)
	update_btn.add_theme_stylebox_override("hover", style_update_hover)
	update_btn.add_theme_stylebox_override("pressed", style_update_pressed)
	buttons_box.add_child(update_btn)
	update_btn.pressed.connect(func():
		OS.shell_open(update_url)
	)
	
	# --- ANIMACIÓN DE APERTURA (TWEEN) ---
	panel.pivot_offset = Vector2(panel_width / 2.0, 210.0) # Pivote centrado
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate.a = 0.0
	
	var tween = create_tween().set_parallel(true)
	# Difuminar fondo
	tween.tween_property(background, "color:a", 0.75, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Escalado elástico de la ventana
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Transparencia de la ventana
	tween.tween_property(panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# Cierra la ventana con animación fluida
func _close_modal(layer: CanvasLayer) -> void:
	var background = layer.get_child(0)
	var center = layer.get_child(1)
	var panel = center.get_child(0)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(background, "color:a", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "scale", Vector2(0.8, 0.8), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished
	layer.queue_free()
