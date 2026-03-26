extends Node

# SCRIPT DE ADMOB LIMPIEZA FINAL
# 1. Sin etiquetas de depuración en pantalla.
# 2. Inicialización automática al arrancar el juego.
# 3. Solo logs internos por consola (si se desea).

var _banner_view : AdView
var _interstitial_ad : InterstitialAd
var _interstitial_loading : bool = false
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
		_load_interstitial() # Pre-cargar el anuncio de apoyo
	
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

# --- SISTEMA DE INTERSTITIAL (APOYO AL CREADOR) ---

func _load_interstitial():
	if _interstitial_loading or _interstitial_ad: return
	_interstitial_loading = true
	
	var unit_id = "ca-app-pub-3940256099942544/1033173712"
	var load_callback := InterstitialAdLoadCallback.new()
	
	load_callback.on_ad_failed_to_load = func(error : LoadAdError):
		print("ADMOB: Intersticial falló -> ", error.message)
		_interstitial_loading = false

	load_callback.on_ad_loaded = func(ad : InterstitialAd):
		print("ADMOB: Intersticial CARGADO.")
		_interstitial_ad = ad
		_interstitial_loading = false
	
	# FIX TOTAL PARA GODOT 4.6 (CRASH POR ASIGNACIÓN DE ARRAYS)
	# No tocamos ninguna propiedad del AdRequest para que Godot no dé error de tipos
	var request = AdRequest.new()
	
	print("ADMOB: Lanzando carga de Intersticial (Modo ultra-limpio 4.6)...")
	InterstitialAdLoader.new().load(unit_id, request, load_callback)

func show_interstitial():
	if _interstitial_ad:
		print("ADMOB: Mostrando anuncio. +5 min de tiempo libre.")
		_interstitial_ad.show()
		_interstitial_ad = null 
		ad_free_time += 300.0 # Sumamos 5 minutos (Acumulable)
		_load_interstitial() 
	else:
		print("ADMOB: El anuncio aún no está listo.")
		_load_interstitial()

func check_and_show_interstitial(button_type: String = ""):
	# PRIMERA VEZ GRACIA: Si es la primera vez que se pulsa un botón específico, NO mostrar.
	if button_type == "pause" and not first_pause_used:
		print("ADMOB: Primera pausa gratis.")
		first_pause_used = true
		return
	if button_type == "reset" and not first_reset_used:
		print("ADMOB: Primer reset gratis.")
		first_reset_used = true
		return

	if ad_free_time <= 0:
		print("ADMOB: Tiempo agotado. Solicitando anuncio obligatorio.")
		show_interstitial()
	else:
		print("ADMOB: Aún queda tiempo libre de anuncios (%.1f s). Saltando." % ad_free_time)

func _exit_tree() -> void:
	if _banner_view:
		_banner_view.destroy()
		_banner_view = null
