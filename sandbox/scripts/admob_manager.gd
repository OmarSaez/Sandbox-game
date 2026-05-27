extends Node

# SCRIPT DE ADMOB LIMPIEZA FINAL
# 1. Sin etiquetas de depuración en pantalla.
# 2. Inicialización automática al arrancar el juego.
# 3. Solo logs internos por consola (si se desea).

signal ad_dismissed
signal consent_info_updated

var _banner_view : AdView
var _banner_is_showing : bool = false
var _interstitial_ad : InterstitialAd
var _rewarded_ad : RewardedAd
var _lab_rewarded_ad : RewardedAd
var _active_ad # Keeps the current ad alive
var _active_consent_form : ConsentForm # Keeps the UMP consent form alive
var _interstitial_loading : bool = false
var _rewarded_loading : bool = false
var _lab_rewarded_loading : bool = false
signal lab_unlocked
signal banner_finished_loading
var _initial_banner_loaded : bool = false
var ad_free_time : float = 0.0 # Segundos restantes sin anuncios
var first_pause_used : bool = false
var first_reset_used : bool = false

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
		print("ADMOB: SDK Inicializado. Iniciando carga escalonada...")
		if _app_is_paused: return
		_create_banner()
		
		# PRIORITY: Wait for the banner to finish loading before starting other network requests!
		await self.banner_finished_loading
		
		if _app_is_paused: return
		await get_tree().create_timer(3.0).timeout
		if _app_is_paused: return
		_load_interstitial()
		
		await get_tree().create_timer(6.0).timeout
		if _app_is_paused: return
		_load_rewarded()
		
		await get_tree().create_timer(6.0).timeout
		if _app_is_paused: return
		_load_lab_rewarded()
	
	MobileAds.initialize(init_listener)

func _create_banner():
	if _app_is_paused: return
	print("ADMOB: Creando Banner oficial...")
	var unit_id = "ca-app-pub-6982275568315854/6392385312"
	
	_banner_view = AdView.new(unit_id, AdSize.BANNER, AdPosition.Values.TOP)
	
	var ad_listener := AdListener.new()
	
	ad_listener.on_ad_loaded = func():
		print("ADMOB: ¡Banner cargado con éxito!")
		if _app_is_paused:
			print("ADMOB: La app está en segundo plano. Destruyendo banner cargado por seguridad.")
			if _banner_view:
				_banner_view.destroy()
				_banner_view = null
			_banner_is_showing = false
		else:
			_banner_is_showing = true
			_banner_view.show()
		if not _initial_banner_loaded:
			_initial_banner_loaded = true
			banner_finished_loading.emit()
	
	ad_listener.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Fallo de carga -> ", error.message)
		_banner_is_showing = false
		if not _initial_banner_loaded:
			_initial_banner_loaded = true
			banner_finished_loading.emit()
		
	_banner_view.ad_listener = ad_listener
	_banner_view.load_ad(AdRequest.new())

func show_toast(text: String):
	# Intenta encontrar el CanvasLayer de la UI para mostrar un mensaje temporal
	var canvas = get_tree().root.find_child("UI", true, false)
	if not canvas:
		# Fallback a alerta de sistema si no hay UI
		OS.alert(text, "AdMob")
		return
		
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_font_size_override("font_size", 40)
	canvas.add_child(label)
	
	# Animación simple de desaparición
	var timer = get_tree().create_timer(2.5)
	await timer.timeout
	if is_instance_valid(label):
		label.queue_free()

# --- SISTEMA DE REWARDED (APOYO AL CREADOR) ---

func _load_rewarded():
	if _app_is_paused: return
	if _rewarded_loading or _rewarded_ad: return
	_rewarded_loading = true
	
	var unit_id = "ca-app-pub-6982275568315854/2842922463"
	var load_callback := RewardedAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Rewarded falló -> ", error.message)
		_rewarded_loading = false

	load_callback.on_ad_loaded = func(ad : RewardedAd):
		print("ADMOB: Rewarded CARGADO.")
		if _app_is_paused:
			print("ADMOB: App pausada, descartando rewarded cargado por seguridad.")
			ad.destroy()
			_rewarded_loading = false
		else:
			_rewarded_ad = ad
			_rewarded_loading = false
	
	var request = AdRequest.new()
	print("ADMOB: Cargando Rewarded (Apoyo)...")
	RewardedAdLoader.new().load(unit_id, request, load_callback)

func show_rewarded() -> bool:

	if not Engine.has_singleton("PoingGodotAdMob"):
		print("ADMOB: show_rewarded() saltado (Plugin desactivado).")
		return false
	if _rewarded_ad:
		print("ADMOB: Mostrando Rewarded...")
		_active_ad = _rewarded_ad
		_rewarded_ad = null
		
		var callback := FullScreenContentCallback.new()
		callback.on_ad_dismissed_full_screen_content = func():
			print("ADMOB: Rewarded cerrado.")
			_active_ad = null
			_load_rewarded()
			ad_dismissed.emit()
		
		var reward_listener := OnUserEarnedRewardListener.new()
		reward_listener.on_user_earned_reward = func(rewarded_item):
			print("ADMOB: ¡RECOMPENSA GANADA! -> ", rewarded_item.amount, " ", rewarded_item.type)
			ad_free_time += 300.0 # 5 Minutos
		
		_active_ad.full_screen_content_callback = callback
		_active_ad.show(reward_listener)
		return true
	else:
		print("ADMOB: Rewarded no listo.")
		show_toast(tr("ad_not_ready"))
		_load_rewarded()
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

	load_callback.on_ad_loaded = func(ad : RewardedAd):
		print("ADMOB: Lab Rewarded CARGADO.")
		if _app_is_paused:
			print("ADMOB: App pausada, descartando lab rewarded cargado por seguridad.")
			ad.destroy()
			_lab_rewarded_loading = false
		else:
			_lab_rewarded_ad = ad
			_lab_rewarded_loading = false
	
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
		print("ADMOB: Mostrando Lab Rewarded...")
		_active_ad = _lab_rewarded_ad
		_lab_rewarded_ad = null
		
		var callback := FullScreenContentCallback.new()
		callback.on_ad_dismissed_full_screen_content = func():
			print("ADMOB: Lab Rewarded cerrado.")
			_active_ad = null
			_load_lab_rewarded()
			ad_dismissed.emit()
		
		var reward_listener := OnUserEarnedRewardListener.new()
		reward_listener.on_user_earned_reward = func(_rewarded_item):
			print("ADMOB: ¡LABORATORIO DESBLOQUEADO (12h)!")
			lab_unlocked.emit()
		
		_active_ad.full_screen_content_callback = callback
		_active_ad.show(reward_listener)
		return true
	else:
		print("ADMOB: Lab Rewarded no listo.")
		show_toast(tr("lab_ad_not_ready"))
		_load_lab_rewarded()
		return false

# --- SISTEMA DE INTERSTITIAL (PAUSA / RESET) ---

func _load_interstitial():
	if _app_is_paused: return
	if _interstitial_loading or _interstitial_ad: return
	_interstitial_loading = true
	
	var unit_id = "ca-app-pub-6982275568315854/5277514113"
	var load_callback := InterstitialAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Intersticial falló -> ", error.message)
		_interstitial_loading = false

	load_callback.on_ad_loaded = func(ad : InterstitialAd):
		print("ADMOB: Intersticial CARGADO.")
		if _app_is_paused:
			print("ADMOB: App pausada, descartando intersticial cargado por seguridad.")
			ad.destroy()
			_interstitial_loading = false
		else:
			_interstitial_ad = ad
			_interstitial_loading = false
	
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
			_load_interstitial()
			ad_dismissed.emit()
		
		_active_ad.full_screen_content_callback = callback
		_active_ad.show()
		
		# Los obligatorios también dan tiempo libre para no ser tan pesados
		ad_free_time += 300.0 
		return true
	else:
		_load_interstitial()
		return false

func check_and_show_interstitial(button_type: String = "") -> bool:

	if not Engine.has_singleton("PoingGodotAdMob"):
		return false
	# PRIMERA VEZ GRACIA: Si es la primera vez que se pulsa un botón específico, NO mostrar.
	if button_type == "pause" and not first_pause_used:
		print("ADMOB: Primera pausa gratis.")
		first_pause_used = true
		return false
	if button_type == "reset" and not first_reset_used:
		print("ADMOB: Primer reset gratis.")
		first_reset_used = true
		return false

	if ad_free_time <= 0:
		print("ADMOB: Tiempo agotado. Solicitando anuncio obligatorio.")
		return show_interstitial()
	else:
		print("ADMOB: Saltando anuncio. Tiempo libre: %.1f s" % ad_free_time)
		return false

func _notification(what: int) -> void:

		
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_app_is_paused = true
		if _banner_view and _banner_is_showing:
			print("ADMOB: App pausada, ocultando banner...")
			_banner_view.hide()
			
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_app_is_paused = false
		if _banner_view and _banner_is_showing:
			print("ADMOB: App reanudada, mostrando banner...")
			_banner_view.show()

func _exit_tree() -> void:

	print("ADMOB: _exit_tree() detectado. Limpiando todos los anuncios para evitar crashes.")
	if _banner_view:
		_banner_is_showing = false
		_banner_view.destroy()
		_banner_view = null
	if _interstitial_ad:
		print("ADMOB: Destruyendo _interstitial_ad")
		_interstitial_ad.destroy()
		_interstitial_ad = null
	if _rewarded_ad:
		print("ADMOB: Destruyendo _rewarded_ad")
		_rewarded_ad.destroy()
		_rewarded_ad = null
	if _lab_rewarded_ad:
		print("ADMOB: Destruyendo _lab_rewarded_ad")
		_lab_rewarded_ad.destroy()
		_lab_rewarded_ad = null
	if _active_ad:
		print("ADMOB: Destruyendo _active_ad")
		_active_ad.destroy()
		_active_ad = null

	# Matar el proceso en Android para evitar que los hilos nativos de WebView/AdMob (Java)
	# intenten llamar a JNI/EGL cuando el motor C++ de Godot ya ha sido destruido (evita crash en caché).
	if OS.get_name() == "Android":
		print("ADMOB: Forzando salida del proceso en Android para evitar crashes en caché.")
		OS.kill(OS.get_process_id())
