extends Node

# SCRIPT DE GESTIÓN DE NOTIFICACIONES LOCALES
# Se encarga de programar recordatorios cuando el usuario deja el juego.

const CHANNEL_ID = "reminders"
const NOTIFICATION_ID_1 = 1001
const NOTIFICATION_ID_2 = 1002

# var _is_scheduled: bool = false

func _ready() -> void:
	# Solo proceder si estamos en Android
	if OS.get_name() != "Android":
		return
		
	# Inicializar el plugin
	NotificationScheduler.initialize()
	
	# Crear el canal de notificaciones (requerido en Android 8+)
	var channel = NotificationChannel.new()
	channel.set_id(CHANNEL_ID)
	channel.set_name("Recordatorios de juego")
	channel.set_description("Notificaciones para recordarte experimentos interesantes")
	channel.set_importance(NotificationChannel.Importance.DEFAULT)
	NotificationScheduler.create_notification_channel(channel)
	
	# Si estamos en Android 13+, pedir permiso si no lo tenemos
	if not NotificationScheduler.has_post_notifications_permission():
		# Pedimos el permiso. El usuario verá el diálogo del sistema.
		NotificationScheduler.request_post_notifications_permission()
		
	# Programar el recordatorio inicial en diferido después de 2.0 segundos para no bloquear la pantalla de carga
	get_tree().create_timer(2.0).timeout.connect(func():
		_reschedule_reminders()
	)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		print("[Lifecycle] Aplicación pausada (PAUSED)")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		print("[Lifecycle] Aplicación reanudada (RESUMED)")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		print("[Lifecycle] Solicitud de cierre/salida detectada (%d)" % what)

func _reschedule_reminders() -> void:
	if OS.get_name() == "Android":
		print("NOTIFICACIONES: Cancelando recordatorios previos...")
		NotificationScheduler.cancel(NOTIFICATION_ID_1)
		NotificationScheduler.cancel(NOTIFICATION_ID_2)
		
		# Programamos 1 notificación aleatoria entre 42 y 70 horas.
		var delay_seconds = randi_range(42 * 3600, 70 * 3600)
		var hours: float = float(delay_seconds) / 3600.0
		print("NOTIFICACIONES: Programando recordatorio para dentro de %d segundos (%.2f horas)..." % [delay_seconds, hours])
		_schedule_reminder(NOTIFICATION_ID_1, delay_seconds)

func _schedule_reminder(notif_id: int, delay_seconds: int) -> void:
	# Elegir un mensaje al azar
	var messages = [
		"NOTIF_LAVA_ICE",
		"NOTIF_LAB_CRAZY",
		"NOTIF_MISS_YOU",
		"NOTIF_FIRE_TORNADO",
		"NOTIF_NPC_WAR",
		"NOTIF_MUSIC",
		"NOTIF_DISASTERS",
		"NOTIF_LAB_CREATION",
		"NOTIF_METAL_ELEC_TNT",
		"NOTIF_CEMENT_AIR",
		"NOTIF_ACID_NPC",
		"NOTIF_HEALER_WARRIOR",
		"NOTIF_MINER_PLAN",
		"NOTIF_STORM_LIGHTNING",
		"NOTIF_PAINT_CUSTOM",
		"NOTIF_VOLCANO_WAR",
		"NOTIF_PHONE_MELT",
		"NOTIF_LAVA_TSUNAMI",
		"NOTIF_GUNPOWDER_TNT",
		"NOTIF_ACID_TNT"
	]
	var random_key = messages[randi() % messages.size()]
	
	print("NOTIFICACIONES: Programando ID ", notif_id, " con retraso de ", delay_seconds, "s con mensaje: ", random_key)
	
	if OS.get_name() == "Android":
		var data = NotificationData.new()
		data.set_id(notif_id)
		data.set_channel_id(CHANNEL_ID)
		data.set_title("Sandbox")
		data.set_content(tr(random_key))
		data.set_delay(delay_seconds)
		NotificationScheduler.schedule(data)
	else:
		print("NOTIFICACIONES: (Simulado) La notificación se enviaría si estuviéramos en Android.")
