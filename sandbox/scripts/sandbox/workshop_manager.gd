extends Node

signal upload_started
signal upload_progress(percent: float)
signal upload_completed(success: bool, message: String, doc_data: Dictionary)
signal update_completed(success: bool, message: String, doc_data: Dictionary)
signal google_play_auth_changed(is_auth: bool)

var is_uploading: bool = false
var auth_retries: int = 0

var google_play_id: String = ""
var google_play_name: String = ""
var play_games_sign_in
var play_games_players

func _ready():
	# Intentar autenticar anónimamente al inicio si no hay sesión
	call_deferred("_try_auth")
	call_deferred("_init_play_games")

func _init_play_games():
	if OS.has_feature("android") and Engine.has_singleton("GodotPlayGameServices"):
		var gps = get_node_or_null("/root/GodotPlayGameServices")
		if gps:
			var init_status = gps.initialize()
			print("WORKSHOP_MANAGER: GPS Initialize status: ", init_status)
			
		play_games_sign_in = preload("res://addons/GodotPlayGameServices/scripts/sign_in/sign_in_client.gd").new()
		add_child(play_games_sign_in)
		play_games_sign_in.user_authenticated.connect(_on_google_play_auth)
		
		play_games_players = preload("res://addons/GodotPlayGameServices/scripts/players/players_client.gd").new()
		add_child(play_games_players)
		play_games_players.current_player_loaded.connect(_on_current_player_loaded)
		
		play_games_sign_in.is_authenticated()

func request_manual_sign_in():
	if play_games_sign_in:
		play_games_sign_in.sign_in()

func _on_google_play_auth(is_auth: bool):
	if is_auth:
		play_games_players.load_current_player(true)
	else:
		google_play_id = ""
		google_play_name = ""
		google_play_auth_changed.emit(false)

func _on_current_player_loaded(player):
	if player:
		google_play_id = player.player_id
		google_play_name = player.display_name
		google_play_auth_changed.emit(true)
	else:
		google_play_auth_changed.emit(false)

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
			_finish_upload(false, "Error de autenticación. Revisa tu conexión a internet o las reglas de Firebase.", {})
			return
		
	var grid_node = get_tree().get_root().find_child("SandboxGrid", true, false)
	if not grid_node:
		_finish_upload(false, "Error interno: Grid no encontrado", {})
		return
		
	# 1. Preparar datos
	var slot_data = grid_node._get_slot_data(slot_id)
	if not slot_data.has("name"):
		_finish_upload(false, "El slot está vacío", {})
		return
		
	var author_name = google_play_name
	if author_name == "": author_name = "Player"
	var author_id = google_play_id
	
	# 2. Generar Buffer SBU
	var file_path = "user://save_slot_" + str(slot_id) + ".dat"
	if not FileAccess.file_exists(file_path):
		_finish_upload(false, "El archivo de guardado no existe en el disco.", {})
		return
	var sbu_bytes = FileAccess.get_file_as_bytes(file_path)
	if sbu_bytes.size() == 0:
		_finish_upload(false, "El archivo de guardado está vacío.", {})
		return
	
	# 3. Generar Buffer Thumbnail
	var thumb_bytes = PackedByteArray()
	if slot_data.has("thumbnail"):
		var img = slot_data.thumbnail.get_image()
		if img:
			thumb_bytes = img.save_webp_to_buffer(false) # Lossless WEBP
			
	var unique_id = str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
	var sbu_filename = "worlds/" + unique_id + ".sbu"
	var thumb_filename = "thumbnails/" + unique_id + ".webp"
	
	emit_signal("upload_progress", 0.2)
	
	# 4. Subir Thumbnail (si existe)
	var thumb_url = ""
	if thumb_bytes.size() > 0:
		var thumb_res = await Firebase.Storage.ref(thumb_filename).put_data(thumb_bytes, {"Content-Type": "image/webp"})
		if thumb_res == null or (typeof(thumb_res) == TYPE_DICTIONARY and thumb_res.has("error")):
			_finish_upload(false, "Error al subir imagen de miniatura.", {})
			return
			
		var bucket = Firebase._config.storageBucket
		thumb_url = "https://firebasestorage.googleapis.com/v0/b/" + bucket + "/o/" + thumb_filename.replace("/", "%2F") + "?alt=media"
	
	emit_signal("upload_progress", 0.6)
	
	# 5. Subir SBU
	var sbu_res = await Firebase.Storage.ref(sbu_filename).put_data(sbu_bytes, {"Content-Type": "application/octet-stream"})
	if sbu_res == null or (typeof(sbu_res) == TYPE_DICTIONARY and sbu_res.has("error")):
		_finish_upload(false, "Error al subir los datos del mundo.", {})
		return
		
	var bucket_sbu = Firebase._config.storageBucket
	var sbu_url = "https://firebasestorage.googleapis.com/v0/b/" + bucket_sbu + "/o/" + sbu_filename.replace("/", "%2F") + "?alt=media"
	
	emit_signal("upload_progress", 0.9)
	
	var current_week_id = int(Time.get_unix_time_from_system() / 604800)
	
	# 6. Guardar en Firestore
	var doc_data = {
		"title": public_name,
		"author": author_name,
		"author_id": author_id,
		"category": category_idx,
		"likes": 0,
		"dislikes": 0,
		"downloads": 0,
		"reports": 0,
		"weekly_score": 0,
		"historical_score": 0,
		"weekly_week_id": current_week_id,
		"timestamp": Time.get_unix_time_from_system(),
		"sbu_url": sbu_url,
		"thumbnail_url": thumb_url
	}
	
	var firestore_collection = Firebase.Firestore.collection("community_worlds")
	
	var final_map_id = ""
	var is_unique = false
	var attempts = 0
	
	while not is_unique and attempts < 10:
		emit_signal("upload_progress", 0.91 + (attempts * 0.01))
		final_map_id = _generate_map_code()
		var check_doc = await firestore_collection.get_doc(final_map_id)
		
		# Si retorna null, no existe. GodotFirebase a veces devuelve FirestoreDocument
		# sin la propiedad document si falla, o un null, o un dict de error.
		if not check_doc or (typeof(check_doc) == TYPE_OBJECT and not "document" in check_doc) or (typeof(check_doc) == TYPE_DICTIONARY and check_doc.has("error")):
			is_unique = true
		else:
			print("WORKSHOP: ID de mapa ya existe: ", final_map_id, " reintentando...")
			attempts += 1
			
	if not is_unique:
		_finish_upload(false, "Error: No se pudo generar un ID único para el mapa. Intenta de nuevo.", {})
		return
		
	doc_data["id"] = final_map_id
	
	# Usamos add con el final_map_id para que lo use como ID del documento
	var doc_res = await firestore_collection.add(final_map_id, doc_data)
	if doc_res == null or (typeof(doc_res) == TYPE_DICTIONARY and doc_res.has("error")):
		var err_msg = "Desconocido"
		if typeof(doc_res) == TYPE_DICTIONARY and doc_res.has("error"):
			err_msg = str(doc_res.error)
		_finish_upload(false, "Error al guardar información del mundo en la base de datos. Detalle: " + err_msg, {})
		return
	
	_finish_upload(true, "¡Mundo subido con éxito!", doc_data)

func _get_char_value(c: String) -> int:
	var ascii = c.unicode_at(0)
	if ascii >= 48 and ascii <= 57: return ascii - 48 # 0-9
	if ascii >= 97 and ascii <= 122: return ascii - 97 + 10 # a-z
	return 0

func _get_value_char(val: int) -> String:
	if val >= 0 and val <= 9: return String.chr(val + 48)
	if val >= 10 and val <= 35: return String.chr(val - 10 + 97)
	return "0"

func _generate_map_code() -> String:
	var chars = "0123456789abcdefghijklmnopqrstuvwxyz"
	var code = ""
	for i in range(8):
		code += chars[randi() % chars.length()]
		
	var sum = 0
	for i in range(8):
		sum += _get_char_value(code[i]) * (i + 1)
		
	var check_digit_val = sum % 36
	var check_char = _get_value_char(check_digit_val)
	
	return code + "-" + check_char

func _finish_upload(success: bool, msg: String, doc_data: Dictionary):
	is_uploading = false
	emit_signal("upload_completed", success, msg, doc_data)

func update_world(world_id: String, old_data: Dictionary, new_title: String, new_category: int, overwrite_slot_id: int):
	emit_signal("upload_started")
	
	if Firebase.Auth.auth == null or not Firebase.Auth.auth.has("localid") or Firebase.Auth.auth.localid == "":
		_finish_update(false, "Error de autenticación.", {})
		return
		
	var sbu_url = old_data.get("sbu_url", "")
	var thumb_url = old_data.get("thumbnail_url", "")
	
	if overwrite_slot_id > 0:
		var grid_node = get_tree().get_root().find_child("SandboxGrid", true, false)
		if not grid_node:
			_finish_update(false, "Error interno: Grid no encontrado", {})
			return
			
		var slot_data = grid_node._get_slot_data(overwrite_slot_id)
		
		var file_path = "user://save_slot_" + str(overwrite_slot_id) + ".dat"
		if not FileAccess.file_exists(file_path):
			_finish_update(false, "El archivo de guardado no existe en el disco.", {})
			return
		var sbu_bytes = FileAccess.get_file_as_bytes(file_path)
		if sbu_bytes.size() == 0:
			_finish_update(false, "El archivo de guardado está vacío.", {})
			return
		
		var thumb_bytes = PackedByteArray()
		if slot_data.has("thumbnail"):
			var img = slot_data.thumbnail.get_image()
			if img: thumb_bytes = img.save_webp_to_buffer(false)
			
		var unique_id = str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000) + "_upd"
		var sbu_filename = "worlds/" + unique_id + ".sbu"
		var thumb_filename = "thumbnails/" + unique_id + ".webp"
		
		emit_signal("upload_progress", 0.2)
		
		if thumb_bytes.size() > 0:
			var thumb_res = await Firebase.Storage.ref(thumb_filename).put_data(thumb_bytes, {"Content-Type": "image/webp"})
			if thumb_res == null or (typeof(thumb_res) == TYPE_DICTIONARY and thumb_res.has("error")):
				_finish_update(false, "Error al subir nueva miniatura.", {})
				return
			var bucket = Firebase._config.storageBucket
			thumb_url = "https://firebasestorage.googleapis.com/v0/b/" + bucket + "/o/" + thumb_filename.replace("/", "%2F") + "?alt=media"
			
		emit_signal("upload_progress", 0.6)
		
		var sbu_res = await Firebase.Storage.ref(sbu_filename).put_data(sbu_bytes, {"Content-Type": "application/octet-stream"})
		if sbu_res == null or (typeof(sbu_res) == TYPE_DICTIONARY and sbu_res.has("error")):
			_finish_update(false, "Error al subir los datos del nuevo mundo.", {})
			return
		var bucket_sbu = Firebase._config.storageBucket
		sbu_url = "https://firebasestorage.googleapis.com/v0/b/" + bucket_sbu + "/o/" + sbu_filename.replace("/", "%2F") + "?alt=media"
		
		emit_signal("upload_progress", 0.8)
		
		# Delete old files safely (ignoring errors if they fail)
		var old_sbu = old_data.get("sbu_url", "")
		if "worlds%2F" in old_sbu:
			var name = "worlds/" + old_sbu.split("worlds%2F")[1].split("?")[0]
			await Firebase.Storage.ref(name).delete()
		
		var old_thumb = old_data.get("thumbnail_url", "")
		if "thumbnails%2F" in old_thumb:
			var name = "thumbnails/" + old_thumb.split("thumbnails%2F")[1].split("?")[0]
			await Firebase.Storage.ref(name).delete()
			
	emit_signal("upload_progress", 0.9)
	
	var firestore_col = Firebase.Firestore.collection("community_worlds")
	var doc = await firestore_col.get_doc(world_id)
	if typeof(doc) != TYPE_OBJECT:
		_finish_update(false, "Error al obtener documento del mundo.", {})
		return
		
	doc.add_or_update_field("title", new_title)
	doc.add_or_update_field("category", new_category)
	if overwrite_slot_id > 0:
		doc.add_or_update_field("sbu_url", sbu_url)
		doc.add_or_update_field("thumbnail_url", thumb_url)
		
	var updated_doc = await firestore_col.update(doc)
	if updated_doc != null:
		emit_signal("upload_progress", 1.0)
		var final_data = old_data.duplicate()
		final_data["title"] = new_title
		final_data["category"] = new_category
		final_data["sbu_url"] = sbu_url
		final_data["thumbnail_url"] = thumb_url
		_finish_update(true, "Mundo actualizado exitosamente.", final_data)
	else:
		_finish_update(false, "Error al actualizar la base de datos.", {})

func _finish_update(success: bool, msg: String, data: Dictionary):
	emit_signal("update_completed", success, msg, data)
