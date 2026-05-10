extends Node

# SCRIPT DE GESTIÓN DE NOTIFICACIONES LOCALES
# Se encarga de programar recordatorios cuando el usuario deja el juego.

const CHANNEL_ID = "reminders"
const NOTIFICATION_ID = 1001

var _is_scheduled: bool = false

func _ready() -> void:
	# Solo proceder si estamos en Android
	if OS.get_name() != "Android":
		return
		
	# Inicializar el plugin
	NotificationScheduler.initialize()
	
	# Cancelar cualquier notificación pendiente al iniciar (Cold Start)
	print("NOTIFICACIONES: Juego iniciado. Cancelando recordatorios previos...")
	NotificationScheduler.cancel(NOTIFICATION_ID)
	_is_scheduled = false
	
	# Crear el canal de notificaciones (requerido en Android 8+)
	var channel = NotificationChannel.new()
	channel.set_id(CHANNEL_ID)
	channel.set_name("Recordatorios de juego")
	channel.set_description("Notificaciones para recordarte experimentos interesantes")
	channel.set_importance(NotificationChannel.Importance.DEFAULT)
	NotificationScheduler.create_notification_channel(channel)
	
	# Si estamos en Android 13+, pedir permiso si no lo tenemos
	if OS.get_name() == "Android":
		if not NotificationScheduler.has_post_notifications_permission():
			# Pedimos el permiso. El usuario verá el diálogo del sistema.
			NotificationScheduler.request_post_notifications_permission()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if _is_scheduled: return # Evitar doble disparo
		
		# El usuario ha minimizado o cerrado el juego.
		# Programamos una notificación para dentro de 2 días (172,800,000 ms)
		print("NOTIFICACIONES: Aplicación pausada. Programando recordatorio para dentro de 48h...")
		_is_scheduled = true
		_schedule_reminder(172800000) 
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		# El usuario ha vuelto al juego. Cancelamos la notificación pendiente.
		print("NOTIFICACIONES: Aplicación resumida. Cancelando notificaciones pendientes...")
		_is_scheduled = false
		if OS.get_name() == "Android":
			NotificationScheduler.cancel(NOTIFICATION_ID)

func _schedule_reminder(delay_ms: int) -> void:
	# Elegir un mensaje al azar
	var messages = [
		"NOTIF_LAVA_ICE",
		"NOTIF_LAB_CRAZY",
		"NOTIF_MISS_YOU",
		"NOTIF_FIRE_TORNADO"
	]
	var random_key = messages[randi() % messages.size()]
	
	print("NOTIFICACIONES: Programando ID ", NOTIFICATION_ID, " con mensaje: ", random_key)
	
	if OS.get_name() == "Android":
		var data = NotificationData.new()
		data.set_id(NOTIFICATION_ID)
		data.set_channel_id(CHANNEL_ID)
		data.set_title("Sandbox")
		data.set_content(tr(random_key))
		data.set_delay(delay_ms)
		NotificationScheduler.schedule(data)
	else:
		print("NOTIFICACIONES: (Simulado) La notificación se enviaría si estuviéramos en Android.")

