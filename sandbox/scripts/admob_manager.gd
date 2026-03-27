extends Node

# SCRIPT DE ADMOB LIMPIEZA FINAL
# 1. Sin etiquetas de depuración en pantalla.
# 2. Inicialización automática al arrancar el juego.
# 3. Solo logs internos por consola (si se desea).

signal ad_dismissed

var _banner_view : AdView
var _interstitial_ad : InterstitialAd
var _rewarded_ad : RewardedAd
var _active_ad # Keeps the current ad alive
var _interstitial_loading : bool = false
var _rewarded_loading : bool = false
var ad_free_time : float = 0.0 # Segundos restantes sin anuncios
var first_pause_used : bool = false
var first_reset_used : bool = false

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

func _ready() -> void:
	# Verificamos plataforma para no dar error en PC
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		print("ADMOB: Saltado (No es plataforma móvil)")
		return

	# Esperamos un pequeño momento para asegurar que el motor está estable
	await get_tree().create_timer(1.0).timeout
	
	_initialize_sdk()

func _initialize_sdk():
	print("ADMOB: Inicializando SDK de Google...")
	
	var init_listener = OnInitializationCompleteListener.new()
	init_listener.on_initialization_complete = func(_status):
		print("ADMOB: SDK Inicializado.")
		_create_banner()
		_load_interstitial() # Pre-cargar el de sistema
		_load_rewarded()     # Pre-cargar el de apoyo
	
	MobileAds.initialize(init_listener)

func _create_banner():
	print("ADMOB: Creando Banner oficial...")
	# ID de PRUEBA de Google para banners en Android
	var unit_id = "ca-app-pub-3940256099942544/6300978111"
	
	_banner_view = AdView.new(unit_id, AdSize.BANNER, AdPosition.Values.TOP)
	
	var ad_listener := AdListener.new()
	
	ad_listener.on_ad_loaded = func():
		print("ADMOB: ¡Banner cargado con éxito!")
		_banner_view.show()
	
	ad_listener.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Fallo de carga -> ", error.message)
		
	_banner_view.ad_listener = ad_listener
	_banner_view.load_ad(AdRequest.new())

# --- SISTEMA DE REWARDED (APOYO AL CREADOR) ---

func _load_rewarded():
	if _rewarded_loading or _rewarded_ad: return
	_rewarded_loading = true
	
	# ID SEGURO DE PRUEBA DE GOOGLE (DE LA IMAGEN)
	var unit_id = "ca-app-pub-3940256099942544/5224354917"
	var load_callback := RewardedAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Rewarded falló -> ", error.message)
		_rewarded_loading = false

	load_callback.on_ad_loaded = func(ad : RewardedAd):
		print("ADMOB: Rewarded CARGADO.")
		_rewarded_ad = ad
		_rewarded_loading = false
	
	var request = AdRequest.new()
	print("ADMOB: Cargando Rewarded (Apoyo)...")
	RewardedAdLoader.new().load(unit_id, request, load_callback)

func show_rewarded() -> bool:
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
		_load_rewarded()
		return false

# --- SISTEMA DE INTERSTITIAL (PAUSA / RESET) ---

func _load_interstitial():
	if _interstitial_loading or _interstitial_ad: return
	_interstitial_loading = true
	
	# ID de prueba de Intersticial (Pausa/Limpieza)
	var unit_id = "ca-app-pub-3940256099942544/1033173712"
	var load_callback := InterstitialAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Intersticial falló -> ", error.message)
		_interstitial_loading = false

	load_callback.on_ad_loaded = func(ad : InterstitialAd):
		print("ADMOB: Intersticial CARGADO.")
		_interstitial_ad = ad
		_interstitial_loading = false
	
	var request = AdRequest.new()
	InterstitialAdLoader.new().load(unit_id, request, load_callback)

func show_interstitial() -> bool:
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

func _exit_tree() -> void:
	if _banner_view:
		_banner_view.destroy()
		_banner_view = null
