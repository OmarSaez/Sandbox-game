extends Node

# SCRIPT DE ADMOB LIMPIEZA FINAL
# 1. Sin etiquetas de depuración en pantalla.
# 2. Inicialización automática al arrancar el juego.
# 3. Solo logs internos por consola (si se desea).

signal ad_dismissed
signal consent_info_updated
signal rewarded_ad_loaded(success: bool)
signal lab_rewarded_ad_loaded(success: bool)
signal interstitial_ad_loaded(success: bool)

var _banner_view : AdView
var _banner_is_showing : bool = false
var _banner_loading : bool = false
var _interstitial_ad : InterstitialAd
var _rewarded_ad : RewardedAd
var _lab_rewarded_ad : RewardedAd
var _active_ad # Keeps the current ad alive
var _active_consent_form : ConsentForm # Keeps the UMP consent form alive
var _interstitial_loading : bool = false
var _rewarded_loading : bool = false
var _lab_rewarded_loading : bool = false
signal lab_unlocked
var ad_free_time : float = 0.0 # Segundos restantes sin anuncios
var first_pause_used : bool = false
var first_reset_used : bool = false
var first_share_used : bool = false

var _app_is_paused : bool = false
var _banner_needs_to_show_on_resume : bool = false

func _process(delta: float) -> void:
	if ad_free_time > 0:
		var prev_time = ad_free_time
		ad_free_time -= delta
		
		# Avisar cuando queda 1 minuto exacto (umbral)
		if prev_time > 60.0 and ad_free_time <= 60.0:
			print("ADMOB: ¡ATENCIÓN! Queda solo 1 minuto de tiempo libre.")
		
		# Avisar cuando llega a cero
		if prev_time > 0 and ad_free_time <= 0:
			ad_free_time = 0
			print("ADMOB: El tiempo libre SE HA AGOTADO. Los anuncios volverán.")

var _is_sdk_initialized: bool = false

func _ready() -> void:
	# Interceptar salida para matar el proceso antes del teardown natural de Godot
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	
	# Verificamos plataforma para no dar error en PC
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		print("ADMOB: Saltado (No es plataforma móvil)")
		return

	_update_consent_info()

func _update_consent_info():
	print("ADMOB: Actualizando información de consentimiento...")
	var params := ConsentRequestParameters.new()
	params.tag_for_under_age_of_consent = false

	# Para depurar consentimiento en desarrollo (puedes descomentar en dispositivo de test):
	# var debug_settings := ConsentDebugSettings.new()
	# debug_settings.debug_geography = DebugGeography.Values.EEA
	# debug_settings.test_device_hashed_ids.append("63C11C9CC2D48590AE31E6C4E9C6B175")
	# debug_settings.test_device_hashed_ids.append("63c11c9cc2d48590ae31e6c4e9c6b175")
	# params.consent_debug_settings = debug_settings

	UserMessagingPlatform.consent_information.update(params, _on_consent_update_success, _on_consent_update_failure)

func _on_consent_update_success():
	print("ADMOB: Información de consentimiento actualizada con éxito.")
	
	var status = UserMessagingPlatform.consent_information.get_consent_status()
	if status == UserMessagingPlatform.consent_information.ConsentStatus.NOT_REQUIRED:
		print("ADMOB: [GEOGRAFÍA] Se detectó que el jugador NO es de Europa (Consentimiento no requerido).")
	elif status == UserMessagingPlatform.consent_information.ConsentStatus.OBTAINED:
		print("ADMOB: [GEOGRAFÍA] Jugador de Europa, pero ya aceptó/denegó anteriormente.")
	elif status == UserMessagingPlatform.consent_information.ConsentStatus.REQUIRED:
		print("ADMOB: [GEOGRAFÍA] Jugador de Europa y se requiere solicitar consentimiento.")
	else:
		print("ADMOB: [GEOGRAFÍA] Estado de consentimiento desconocido: ", status)
		
	consent_info_updated.emit()
	
	if UserMessagingPlatform.consent_information.get_is_consent_form_available():
		_load_consent_form()
	else:
		print("ADMOB: Formulario no disponible. Inicializando SDK...")
		_initialize_sdk()

func _on_consent_update_failure(error: FormError):
	print("ADMOB: Error al actualizar información de consentimiento -> ", error.message)
	consent_info_updated.emit()
	print("ADMOB: Usando fallback: Inicializando SDK...")
	_initialize_sdk()

func is_privacy_button_required() -> bool:
	if not Engine.has_singleton("PoingGodotAdMob"):
		return false
	var status = UserMessagingPlatform.consent_information.get_consent_status()
	return status == UserMessagingPlatform.consent_information.ConsentStatus.REQUIRED or status == UserMessagingPlatform.consent_information.ConsentStatus.OBTAINED

func _load_consent_form():
	print("ADMOB: Cargando formulario de consentimiento...")
	UserMessagingPlatform.load_consent_form(_on_form_load_success, _on_form_load_failure)

func _on_form_load_success(consent_form: ConsentForm):
	print("ADMOB: Formulario cargado correctamente.")
	_active_consent_form = consent_form
	var status = UserMessagingPlatform.consent_information.get_consent_status()
	
	if status == UserMessagingPlatform.consent_information.ConsentStatus.REQUIRED:
		print("ADMOB: Formulario requerido. Mostrando...")
		consent_form.show(_on_form_dismissed)
	else:
		print("ADMOB: Formulario no requerido en esta región (o ya fue respondido). Inicializando SDK...")
		_active_consent_form = null
		_initialize_sdk()

func _on_form_load_failure(error: FormError):
	print("ADMOB: Error al cargar formulario de consentimiento -> ", error.message)
	_active_consent_form = null
	print("ADMOB: Usando fallback: Inicializando SDK...")
	_initialize_sdk()

func _on_form_dismissed(error: FormError):
	if error:
		print("ADMOB: Formulario cerrado con error -> ", error.message)
	else:
		print("ADMOB: Formulario cerrado por el usuario.")
	_active_consent_form = null
	_initialize_sdk()

# Función pública para reabrir las opciones de privacidad (invocada desde el panel de configuración)
func show_consent_options():
	print("ADMOB: Solicitando mostrar opciones de consentimiento...")

	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		return
	
	# Usamos el singleton PoingGodotAdMob para cargar el formulario
	if not Engine.has_singleton("PoingGodotAdMob"):
		print("ADMOB: Singleton de AdMob no disponible.")
		return
		
	# Para reabrir el formulario, UMP requiere cargarlo de nuevo
	var on_success = func(consent_form: ConsentForm):
		print("ADMOB: Formulario de privacidad reabierto con éxito.")
		_active_consent_form = consent_form
		var on_dismissed = func(error: FormError):
			if error:
				print("ADMOB: Error al cerrar el formulario reabierto -> ", error.message)
			_active_consent_form = null
		consent_form.show(on_dismissed)
		
	var on_failure = func(error: FormError):
		print("ADMOB: Error al cargar el formulario de privacidad para reabrir -> ", error.message)
		_active_consent_form = null
		
	UserMessagingPlatform.load_consent_form(on_success, on_failure)

func _initialize_sdk():

	if _is_sdk_initialized:
		print("ADMOB: SDK ya inicializado previamente.")
		return
	_is_sdk_initialized = true
	print("ADMOB: Inicializando SDK de Google...")
	
	var init_listener = OnInitializationCompleteListener.new()
	init_listener.on_initialization_complete = func(_status):
		print("ADMOB: SDK Inicializado. Cargando banner...")
		if _app_is_paused: return
		_create_banner()
	
	MobileAds.initialize(init_listener)

func _create_banner():
	if _app_is_paused: return
	if _banner_loading or _banner_view: return
	_banner_loading = true
	print("ADMOB: Creando Banner oficial...")
	var unit_id = "ca-app-pub-6982275568315854/6392385312"
	
	_banner_view = AdView.new(unit_id, AdSize.BANNER, AdPosition.Values.TOP)
	
	var ad_listener := AdListener.new()
	
	ad_listener.on_ad_loaded = func():
		print("ADMOB: ¡Banner cargado con éxito!")
		_banner_loading = false
		if _app_is_paused:
			print("ADMOB: La app está en segundo plano. Destruyendo banner cargado por seguridad.")
			if _banner_view:
				_banner_view.destroy()
				_banner_view = null
			_banner_is_showing = false
		else:
			_banner_is_showing = true
			_banner_view.show()
	
	ad_listener.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Fallo de carga de Banner -> ", error.message)
		_banner_loading = false
		_banner_is_showing = false
		if _banner_view:
			_banner_view.destroy()
			_banner_view = null
		
		if _app_is_paused or not is_inside_tree(): return
		print("ADMOB: Reintentando cargar el banner en 15 segundos...")
		await get_tree().create_timer(15.0).timeout
		if _app_is_paused or not is_inside_tree(): return
		_create_banner()
		
	_banner_view.ad_listener = ad_listener
	_banner_view.load_ad(AdRequest.new())

func show_toast(text: String):
	# Intenta encontrar el CanvasLayer de la UI para mostrar un mensaje temporal
	var canvas = get_tree().root.find_child("UI", true, false)
	if not canvas:
		OS.alert(text, "AdMob")
		return
		
	# Contenedor para posicionar en la pantalla (usando CenterContainer de tamaño completo pero mouse passthrough)
	var overlay = CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS # No bloquear clicks
	
	# Tarjeta del mensaje
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 160)
	
	# Estilo oscuro y borde rojo suave para errores / advertencias
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.1, 0.1, 0.95) # Rojo/oscuro moderno
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.2, 0.2, 0.8) # Borde rojo de aviso
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	
	# Contenedor de márgenes
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 30)
	margin_container.add_theme_constant_override("margin_top", 20)
	margin_container.add_theme_constant_override("margin_right", 30)
	margin_container.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin_container)
	
	# Label del texto
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9)) # Blanco rojizo
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	margin_container.add_child(label)
	
	canvas.add_child(overlay)
	
	# Animación de desvanecimiento
	var tween = overlay.create_tween()
	tween.tween_interval(2.5) # Espera 2.5s antes de desvanecerse
	tween.tween_property(overlay, "modulate:a", 0.0, 0.4) # Desvanecer en 0.4s
	await tween.finished
	
	if is_instance_valid(overlay):
		overlay.queue_free()

func _show_loading_overlay(message: String) -> Control:
	var canvas = get_tree().root.find_child("UI", true, false)
	if not canvas:
		return null
		
	# Contenedor principal de pantalla completa (oscurece el fondo)
	var overlay = PanelContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP # Con esto bloqueamos clics en el fondo
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.6) # Fondo semi-transparente
	overlay.add_theme_stylebox_override("panel", bg_style)
	
	# CenterContainer para forzar el centrado robusto de la tarjeta
	var center = CenterContainer.new()
	overlay.add_child(center)
	
	# Panel contenedor central (la tarjeta)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(800, 380)
	
	# StyleBoxFlat para diseño premium
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.95) # Oscuro moderno
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 20
	style.shadow_offset = Vector2(0, 10)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.25, 0.27, 0.35, 0.8) # Borde sutil
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	# Contenedor de márgenes para separar el contenido del borde
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 40)
	margin_container.add_theme_constant_override("margin_top", 40)
	margin_container.add_theme_constant_override("margin_right", 40)
	margin_container.add_theme_constant_override("margin_bottom", 40)
	panel.add_child(margin_container)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	margin_container.add_child(vbox)
	
	# Título del anuncio (ej: "Laboratorio")
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # Dorado premium
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(label)
	
	# Spinner animado en lugar de la barra de progreso
	var spinner = Control.new()
	spinner.custom_minimum_size = Vector2(240, 120)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spinner.set_script(load("res://scripts/loading_spinner.gd"))
	vbox.add_child(spinner)
	
	# Subtítulo ("Cargando anuncio... Por favor, espera unos segundos")
	var sublabel = Label.new()
	sublabel.text = tr("LOADING_AD")
	sublabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sublabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sublabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sublabel.add_theme_font_size_override("font_size", 26)
	sublabel.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9)) # Blanco suave
	sublabel.add_theme_color_override("font_outline_color", Color.BLACK)
	sublabel.add_theme_constant_override("outline_size", 4)
	vbox.add_child(sublabel)
	
	canvas.add_child(overlay)
	
	# Guardar referencias para el estado de fallo
	overlay.set_meta("spinner", spinner)
	overlay.set_meta("sublabel", sublabel)
	
	return overlay

# --- SISTEMA DE REWARDED (APOYO AL CREADOR) ---

func _load_rewarded():
	if _app_is_paused: return
	if _rewarded_loading or _rewarded_ad: return
	_rewarded_loading = true
	
	var unit_id = "ca-app-pub-6982275568315854/5277514113"
	var load_callback := RewardedAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Rewarded falló -> ", error.message)
		_rewarded_loading = false
		rewarded_ad_loaded.emit(false)

	load_callback.on_ad_loaded = func(ad : RewardedAd):
		print("ADMOB: Rewarded CARGADO.")
		if _app_is_paused:
			print("ADMOB: App pausada, descartando rewarded cargado por seguridad.")
			ad.destroy()
			_rewarded_loading = false
			rewarded_ad_loaded.emit(false)
		else:
			_rewarded_ad = ad
			_rewarded_loading = false
			rewarded_ad_loaded.emit(true)
	
	var request = AdRequest.new()
	print("ADMOB: Cargando Rewarded (Apoyo)...")
	RewardedAdLoader.new().load(unit_id, request, load_callback)

func show_rewarded() -> bool:

	if not Engine.has_singleton("PoingGodotAdMob"):
		print("ADMOB: show_rewarded() saltado (Plugin desactivado).")
		return false
	if _rewarded_ad:
		print("ADMOB: Mostrando Rewarded inmediato...")
		_active_ad = _rewarded_ad
		_rewarded_ad = null
		
		var callback := FullScreenContentCallback.new()
		callback.on_ad_dismissed_full_screen_content = func():
			print("ADMOB: Rewarded cerrado.")
			_active_ad = null
			ad_dismissed.emit()
		
		var reward_listener := OnUserEarnedRewardListener.new()
		reward_listener.on_user_earned_reward = func(rewarded_item):
			print("ADMOB: ¡RECOMPENSA GANADA! -> ", rewarded_item.amount, " ", rewarded_item.type)
			ad_free_time += 60.0 # 1 Minuto
		
		_active_ad.full_screen_content_callback = callback
		_active_ad.show(reward_listener)
		return true
	else:
		print("ADMOB: Rewarded no listo. Cargando bajo demanda...")
		var overlay = _show_loading_overlay(tr("support"))
		
		if not _rewarded_loading:
			_load_rewarded()
			
		var success = await rewarded_ad_loaded
		
		if success and _rewarded_ad:
			if is_instance_valid(overlay):
				overlay.queue_free()
				
			print("ADMOB: Mostrando Rewarded recién cargado...")
			_active_ad = _rewarded_ad
			_rewarded_ad = null
			
			var callback := FullScreenContentCallback.new()
			callback.on_ad_dismissed_full_screen_content = func():
				print("ADMOB: Rewarded cerrado.")
				_active_ad = null
				ad_dismissed.emit()
			
			var reward_listener := OnUserEarnedRewardListener.new()
			reward_listener.on_user_earned_reward = func(rewarded_item):
				print("ADMOB: ¡RECOMPENSA GANADA! -> ", rewarded_item.amount, " ", rewarded_item.type)
				ad_free_time += 60.0 # 1 Minuto
			
			_active_ad.full_screen_content_callback = callback
			_active_ad.show(reward_listener)
			return true
		else:
			print("ADMOB: Falló la carga del anuncio bajo demanda.")
			if is_instance_valid(overlay):
				var spinner = overlay.get_meta("spinner")
				var sublabel = overlay.get_meta("sublabel")
				if spinner:
					spinner.is_failed = true
				if sublabel:
					sublabel.text = tr("LOAD_AD_FAILED")
					sublabel.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
				
				var tween = overlay.create_tween()
				tween.tween_interval(2.1)
				tween.tween_property(overlay, "modulate:a", 0.0, 0.4)
				await overlay.get_tree().create_timer(2.5).timeout
				if is_instance_valid(overlay):
					overlay.queue_free()
			return false

# --- SISTEMA DE REWARDED (LABORATORIO) ---

func _load_lab_rewarded():
	if _app_is_paused: return
	if _lab_rewarded_loading or _lab_rewarded_ad: return
	_lab_rewarded_loading = true
	
	var unit_id = "ca-app-pub-6982275568315854/2828758798"
	var load_callback := RewardedAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Lab Rewarded falló -> ", error.message)
		_lab_rewarded_loading = false
		lab_rewarded_ad_loaded.emit(false)

	load_callback.on_ad_loaded = func(ad : RewardedAd):
		print("ADMOB: Lab Rewarded CARGADO.")
		if _app_is_paused:
			print("ADMOB: App pausada, descartando lab rewarded cargado por seguridad.")
			ad.destroy()
			_lab_rewarded_loading = false
			lab_rewarded_ad_loaded.emit(false)
		else:
			_lab_rewarded_ad = ad
			_lab_rewarded_loading = false
			lab_rewarded_ad_loaded.emit(true)
	
	var request = AdRequest.new()
	print("ADMOB: Cargando Rewarded (Laboratorio)...")
	RewardedAdLoader.new().load(unit_id, request, load_callback)

func show_lab_rewarded() -> bool:

	if not Engine.has_singleton("PoingGodotAdMob"):
		print("ADMOB: [PLUGIN DESACTIVADO] Laboratorio Desbloqueado de forma gratuita.")
		lab_unlocked.emit()
		ad_dismissed.emit()
		return true

	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		print("ADMOB: [PC EMULADOR] Laboratorio Desbloqueado.")
		lab_unlocked.emit()
		ad_dismissed.emit()
		return true
		
	if _lab_rewarded_ad:
		print("ADMOB: Mostrando Lab Rewarded inmediato...")
		_active_ad = _lab_rewarded_ad
		_lab_rewarded_ad = null
		
		var callback := FullScreenContentCallback.new()
		callback.on_ad_dismissed_full_screen_content = func():
			print("ADMOB: Lab Rewarded cerrado.")
			_active_ad = null
			ad_dismissed.emit()
		
		var reward_listener := OnUserEarnedRewardListener.new()
		reward_listener.on_user_earned_reward = func(_rewarded_item):
			print("ADMOB: ¡LABORATORIO DESBLOQUEADO (12h)!")
			lab_unlocked.emit()
		
		_active_ad.full_screen_content_callback = callback
		_active_ad.show(reward_listener)
		return true
	else:
		print("ADMOB: Lab Rewarded no listo. Cargando bajo demanda...")
		var overlay = _show_loading_overlay(tr("lab"))
		
		if not _lab_rewarded_loading:
			_load_lab_rewarded()
			
		var success = await lab_rewarded_ad_loaded
		
		if success and _lab_rewarded_ad:
			if is_instance_valid(overlay):
				overlay.queue_free()
				
			print("ADMOB: Mostrando Lab Rewarded recién cargado...")
			_active_ad = _lab_rewarded_ad
			_lab_rewarded_ad = null
			
			var callback := FullScreenContentCallback.new()
			callback.on_ad_dismissed_full_screen_content = func():
				print("ADMOB: Lab Rewarded cerrado.")
				_active_ad = null
				ad_dismissed.emit()
			
			var reward_listener := OnUserEarnedRewardListener.new()
			reward_listener.on_user_earned_reward = func(_rewarded_item):
				print("ADMOB: ¡LABORATORIO DESBLOQUEADO (12h)!")
				lab_unlocked.emit()
			
			_active_ad.full_screen_content_callback = callback
			_active_ad.show(reward_listener)
			return true
		else:
			print("ADMOB: Falló la carga de Lab Rewarded.")
			if is_instance_valid(overlay):
				var spinner = overlay.get_meta("spinner")
				var sublabel = overlay.get_meta("sublabel")
				if spinner:
					spinner.is_failed = true
				if sublabel:
					sublabel.text = tr("LOAD_AD_FAILED")
					sublabel.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
				
				var tween = overlay.create_tween()
				tween.tween_interval(2.1)
				tween.tween_property(overlay, "modulate:a", 0.0, 0.4)
				await overlay.get_tree().create_timer(2.5).timeout
				if is_instance_valid(overlay):
					overlay.queue_free()
			return false

func preload_interstitial():
	if not Engine.has_singleton("PoingGodotAdMob"):
		return
	_load_interstitial()

func _load_interstitial():
	if _app_is_paused: return
	if _interstitial_loading or _interstitial_ad: return
	_interstitial_loading = true
	
	var unit_id = "ca-app-pub-6982275568315854/2842922463"
	var load_callback := InterstitialAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Intersticial falló -> ", error.message)
		_interstitial_loading = false
		interstitial_ad_loaded.emit(false)

	load_callback.on_ad_loaded = func(ad : InterstitialAd):
		print("ADMOB: Intersticial CARGADO.")
		if _app_is_paused:
			print("ADMOB: App pausada, descartando intersticial cargado por seguridad.")
			ad.destroy()
			_interstitial_loading = false
			interstitial_ad_loaded.emit(false)
		else:
			_interstitial_ad = ad
			_interstitial_loading = false
			interstitial_ad_loaded.emit(true)
	
	var request = AdRequest.new()
	InterstitialAdLoader.new().load(unit_id, request, load_callback)

func show_interstitial() -> bool:

	if not Engine.has_singleton("PoingGodotAdMob"):
		return false
	if _interstitial_ad:
		print("ADMOB: Mostrando Intersticial...")
		_active_ad = _interstitial_ad
		_interstitial_ad = null 
		
		var callback := FullScreenContentCallback.new()
		callback.on_ad_dismissed_full_screen_content = func():
			print("ADMOB: Intersticial cerrado.")
			_active_ad = null
			ad_dismissed.emit()
		
		_active_ad.full_screen_content_callback = callback
		_active_ad.show()
		
		# Los obligatorios también dan tiempo libre para no ser tan pesados: 2 minutos (120s)
		ad_free_time += 120.0 
		return true
	else:
		_load_interstitial()
		return false

func check_and_show_interstitial(button_type: String = "") -> bool:

	if not Engine.has_singleton("PoingGodotAdMob"):
		return false
	# PRIMERA VEZ GRACIA: Si es la primera vez que se pulsa un botón específico, NO mostrar.
	if button_type == "pause" and not first_pause_used:
		print("ADMOB: Primera pausa gratis. Iniciando carga perezosa de intersticial...")
		first_pause_used = true
		_load_interstitial() # Lazy load for the next time!
		return false
	if button_type == "reset" and not first_reset_used:
		print("ADMOB: Primer reset gratis. Iniciando carga perezosa de intersticial...")
		first_reset_used = true
		_load_interstitial() # Lazy load for the next time!
		return false
	if button_type == "share" and not first_share_used:
		print("ADMOB: Primer share gratis.")
		first_share_used = true
		return false

	if ad_free_time <= 0:
		print("ADMOB: Tiempo agotado. Solicitando anuncio obligatorio.")
		return show_interstitial()
	else:
		print("ADMOB: Saltando anuncio. Tiempo libre: %.1f s" % ad_free_time)
		return false

func is_interstitial_loaded() -> bool:
	return _interstitial_ad != null

func check_and_consume_free_use(button_type: String) -> bool:
	if not Engine.has_singleton("PoingGodotAdMob"):
		return true
	if button_type == "share" and not first_share_used:
		first_share_used = true
		return true
	if ad_free_time > 0:
		return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# ¡LA GUILLOTINA (Botón Atrás)!
		if OS.get_name() == "Android":
			print("ADMOB: Interceptando botón Atrás. Ejecutando OS.kill() instantáneo.")
			OS.kill(OS.get_process_id())
		else:
			get_tree().quit()
			
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_app_is_paused = true
		if _banner_view and _banner_is_showing:
			print("ADMOB: App pausada, ocultando banner...")
			_banner_view.hide()
			
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_app_is_paused = false
		if _banner_view:
			print("ADMOB: App reanudada, mostrando banner...")
			_banner_is_showing = true
			_banner_view.show()
		elif not _banner_loading:
			print("ADMOB: App reanudada y el banner no existe (destruido en background/error). Re-creando banner...")
			_create_banner()

func _exit_tree() -> void:
	# ¡LA GUILLOTINA (Fondo / Low Memory Killer)!
	# Si Android mata la app o el usuario cierra por Task Manager, Godot fuerza _exit_tree.
	# OS.kill debe ser la PRIMERA instrucción para ganar la carrera contra la destrucción de GLThread.
	if OS.get_name() == "Android":
		print("ADMOB: _exit_tree() detectado. Ejecutando OS.kill() de emergencia.")
		OS.kill(OS.get_process_id())

	print("ADMOB: _exit_tree() detectado. Limpiando todos los anuncios.")
	if _banner_view:
		_banner_is_showing = false
		_banner_view.destroy()
		_banner_view = null
	if _interstitial_ad:
		_interstitial_ad.destroy()
		_interstitial_ad = null
	if _rewarded_ad:
		_rewarded_ad.destroy()
		_rewarded_ad = null
	if _lab_rewarded_ad:
		_lab_rewarded_ad.destroy()
		_lab_rewarded_ad = null
	if _active_ad:
		_active_ad.destroy()
		_active_ad = null
