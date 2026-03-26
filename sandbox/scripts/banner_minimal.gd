extends Node

# --- SCRIPT MÍNIMO ADMOB PARA PROYECTO LIMPIO ---
# Instrucciones:
# 1. Añade un nodo "Node" en tu escena.
# 2. Ponle este script.
# 3. Exporta con los permisos necesarios activos.

var _ad_view : AdView

func _ready() -> void:
    print("TEST_ADMOB: Iniciando sistema...")
    # Esperar 2 segundos para asegurar carga
    await get_tree().create_timer(2.0).timeout
    
    # PASO 1: Inicializar SDK de Google
    var listener = OnInitializationCompleteListener.new()
    listener.on_initialization_complete = func(_status):
        print("TEST_ADMOB: SDK Inicializado con éxito.")
        _load_test_banner()
    
    print("TEST_ADMOB: Llamando a MobileAds.initialize()...")
    MobileAds.initialize(listener)

func _load_test_banner():
    # ID OFICIAL DE PRUEBA DE GOOGLE PARA ANDROID
    var unit_id = "ca-app-pub-3940256099942544/6300978111"
    print("TEST_ADMOB: Creando AdView con ID: ", unit_id)
    
    _ad_view = AdView.new(unit_id, AdSize.BANNER, AdPosition.Values.TOP)
    
    var ad_listener := AdListener.new()
    
    ad_listener.on_ad_loaded = func():
        print("TEST_ADMOB: ¡ÉXITO! BANNER CARGADO.")
        _ad_view.show()
    
    ad_listener.on_ad_failed_to_load = func(error : LoadAdError):
        print("TEST_ADMOB: ERROR DE GOOGLE -> ", error.message)
        
    _ad_view.ad_listener = ad_listener
    
    print("TEST_ADMOB: Solicitando carga de anuncio...")
    _ad_view.load_ad(AdRequest.new())

func _exit_tree() -> void:
    if _ad_view:
        _ad_view.destroy()
        _ad_view = null
