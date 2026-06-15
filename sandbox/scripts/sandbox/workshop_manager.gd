extends Node

signal upload_started
signal upload_progress(percent: float)
signal upload_completed(success: bool, message: String)

var is_uploading: bool = false
var auth_retries: int = 0

func _ready():
	# Intentar autenticar anónimamente al inicio si no hay sesión
	call_deferred("_try_auth")

func _try_auth():
	if Firebase.Auth.check_auth_file():
		return # Ya autenticado previamente
		
	if Firebase.Auth.auth == null or not Firebase.Auth.auth.has("localid") or Firebase.Auth.auth.localid == "":
		Firebase.Auth.login_anonymous()

func upload_world(slot_id: int, public_name: String, category_idx: int):
	if is_uploading:
		return
		
	is_uploading = true
	emit_signal("upload_started")
	
	# Asegurar autenticación antes de subir
	if Firebase.Auth.auth == null or not Firebase.Auth.auth.has("localid") or Firebase.Auth.auth.localid == "":
		var auth_state = {"done": false, "success": false}
		var _on_succ = func(_auth_data): auth_state.success = true; auth_state.done = true
		var _on_fail = func(_code, _msg): auth_state.success = false; auth_state.done = true
		
		Firebase.Auth.login_succeeded.connect(_on_succ, CONNECT_ONE_SHOT)
		Firebase.Auth.login_failed.connect(_on_fail, CONNECT_ONE_SHOT)
		
		Firebase.Auth.login_anonymous()
		while not auth_state.done:
			await get_tree().process_frame
			
		if not auth_state.success:
			_finish_upload(false, "Error de autenticación. Revisa tu conexión a internet o las reglas de Firebase.")
			return
		
	var grid_node = get_tree().get_root().find_child("SandboxGrid", true, false)
	if not grid_node:
		_finish_upload(false, "Error interno: Grid no encontrado")
		return
		
	# 1. Preparar datos
	var slot_data = grid_node._get_slot_data(slot_id)
	if not slot_data.has("name"):
		_finish_upload(false, "El slot está vacío")
		return
		
	var author_name = "Player" # Todo: Añadir sistema de nombre de usuario en el futuro si se desea
	
	# 2. Generar Buffer SBU
	var file_path = "user://save_slot_" + str(slot_id) + ".dat"
	if not FileAccess.file_exists(file_path):
		_finish_upload(false, "El archivo de guardado no existe en el disco.")
		return
	var sbu_bytes = FileAccess.get_file_as_bytes(file_path)
	if sbu_bytes.size() == 0:
		_finish_upload(false, "El archivo de guardado está vacío.")
		return
	
	# 3. Generar Buffer Thumbnail
	var thumb_bytes = PackedByteArray()
	if slot_data.has("thumbnail"):
		var img = slot_data.thumbnail.get_image()
		if img:
			thumb_bytes = img.save_png_to_buffer()
			
	var unique_id = str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
	var sbu_filename = "worlds/" + unique_id + ".sbu"
	var thumb_filename = "thumbnails/" + unique_id + ".png"
	
	emit_signal("upload_progress", 0.2)
	
	# 4. Subir Thumbnail (si existe)
	var thumb_url = ""
	if thumb_bytes.size() > 0:
		var thumb_res = await Firebase.Storage.ref(thumb_filename).put_data(thumb_bytes, {"Content-Type": "image/png"})
		if thumb_res == null or (typeof(thumb_res) == TYPE_DICTIONARY and thumb_res.has("error")):
			_finish_upload(false, "Error al subir imagen de miniatura.")
			return
			
		var bucket = Firebase._config.storageBucket
		thumb_url = "https://firebasestorage.googleapis.com/v0/b/" + bucket + "/o/" + thumb_filename.replace("/", "%2F") + "?alt=media"
	
	emit_signal("upload_progress", 0.6)
	
	# 5. Subir SBU
	var sbu_res = await Firebase.Storage.ref(sbu_filename).put_data(sbu_bytes, {"Content-Type": "application/octet-stream"})
	if sbu_res == null or (typeof(sbu_res) == TYPE_DICTIONARY and sbu_res.has("error")):
		_finish_upload(false, "Error al subir los datos del mundo.")
		return
		
	var bucket_sbu = Firebase._config.storageBucket
	var sbu_url = "https://firebasestorage.googleapis.com/v0/b/" + bucket_sbu + "/o/" + sbu_filename.replace("/", "%2F") + "?alt=media"
	
	emit_signal("upload_progress", 0.9)
	
	var current_week_id = int(Time.get_unix_time_from_system() / 604800)
	
	# 6. Guardar en Firestore
	var doc_data = {
		"title": public_name,
		"author": author_name,
		"category": category_idx,
		"likes": 0,
		"dislikes": 0,
		"downloads": 0,
		"reports": 0,
		"weekly_score": 0,
		"weekly_week_id": current_week_id,
		"timestamp": Time.get_unix_time_from_system(),
		"sbu_url": sbu_url,
		"thumbnail_url": thumb_url
	}
	
	var firestore_collection = Firebase.Firestore.collection("community_worlds")
	var doc_res = await firestore_collection.add("", doc_data)
	if doc_res == null or (typeof(doc_res) == TYPE_DICTIONARY and doc_res.has("error")):
		var err_msg = "Desconocido"
		if typeof(doc_res) == TYPE_DICTIONARY and doc_res.has("error"):
			err_msg = str(doc_res.error)
		_finish_upload(false, "Error al guardar información del mundo en la base de datos. Detalle: " + err_msg)
		return
	
	_finish_upload(true, "¡Mundo subido con éxito!")

func _finish_upload(success: bool, msg: String):
	is_uploading = false
	emit_signal("upload_completed", success, msg)
