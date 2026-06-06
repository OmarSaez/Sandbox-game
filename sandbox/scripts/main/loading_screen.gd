extends Control

var next_scene_path: String = "res://scenes/main/main_scene.tscn"
@onready var progress_bar: ProgressBar = $ProgressBar

func _ready() -> void:
	# Empezar a cargar la escena principal en segundo plano
	ResourceLoader.load_threaded_request(next_scene_path)

func _process(delta: float) -> void:
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(next_scene_path, progress)
	
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		progress_bar.value = progress[0]
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		# La carga terminó, cambiar a la escena principal
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(next_scene_path))
		set_process(false)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Error al cargar la escena principal en segundo plano")
		set_process(false)
