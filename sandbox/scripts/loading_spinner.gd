extends Control

# Colores oficiales de los materiales del juego
const COLOR_HEAD = Color("717E80")
const COLOR_SKIN = Color("FFE2BD")
const COLOR_TORSO = Color("1F1F1F")
const COLOR_SHOES = Color("717E80")
const COLOR_RED = Color("E00000")
const COLOR_BLUE = Color("008EE6")

# Configuración de tamaño y físicas de animación
@export var pixel_size: float = 12.0
@export var jump_height: float = 30.0
@export var jump_speed: float = 7.0

var is_failed: bool = false:
	set(val):
		is_failed = val
		if is_failed:
			_show_emojis()

var red_emoji_label: Label
var blue_emoji_label: Label

func _ready() -> void:
	# Aseguramos que el pivote esté centrado
	pivot_offset = size / 2
	
	# Crear etiqueta para el soldado rojo (❌)
	red_emoji_label = Label.new()
	red_emoji_label.text = "❌"
	red_emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	red_emoji_label.add_theme_font_size_override("font_size", 22)
	red_emoji_label.visible = false
	add_child(red_emoji_label)
	
	# Crear etiqueta para el soldado azul (❗)
	blue_emoji_label = Label.new()
	blue_emoji_label.text = "❗"
	blue_emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blue_emoji_label.add_theme_font_size_override("font_size", 24)
	blue_emoji_label.visible = false
	add_child(blue_emoji_label)

func _show_emojis() -> void:
	var center_x = size.x / 2
	var floor_y = size.y - 16.0
	
	# Centrar etiquetas sobre las cabezas de los soldados
	# Ajustamos offset de X e Y para centrar el emoji
	red_emoji_label.position = Vector2(center_x - 48 - 16, floor_y - 94)
	blue_emoji_label.position = Vector2(center_x + 48 - 16, floor_y - 94)
	
	red_emoji_label.visible = true
	blue_emoji_label.visible = true

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	# Centro del control y posición del suelo
	var center_x = size.x / 2
	var floor_y = size.y - 16.0
	
	# 1. Dibujar el suelo de arena
	var sand_color = Color("E5C158") # Arena amarillenta
	draw_line(Vector2(0, floor_y), Vector2(size.x, floor_y), sand_color, 8.0, true)
	
	# Físicas de salto
	var red_jump = 0.0
	var blue_jump = 0.0
	var red_time = 0.0
	var blue_time = 0.0
	
	if not is_failed:
		red_time = time * jump_speed
		red_jump = abs(sin(red_time)) * jump_height
		
		blue_time = (time + 0.45) * jump_speed
		blue_jump = abs(sin(blue_time)) * jump_height
	
	# 2. Dibujar el Soldado Rojo (Izquierda, mirando a la derecha)
	var red_pos = Vector2(center_x - 60, floor_y - (7 * pixel_size) - red_jump)
	_draw_warrior(red_pos, COLOR_RED, 1)
	
	# 3. Dibujar el Soldado Azul (Derecha, mirando a la izquierda)
	var blue_pos = Vector2(center_x + 36, floor_y - (7 * pixel_size) - blue_jump)
	_draw_warrior(blue_pos, COLOR_BLUE, -1)
	
	# 4. Dibujar partículas de polvo al aterrizar
	if not is_failed:
		_draw_landing_dust(center_x - 48, floor_y, red_time)
		_draw_landing_dust(center_x + 48, floor_y, blue_time)

func _draw_warrior(pos: Vector2, team_color: Color, dir: int) -> void:
	# Definición de la cuadrícula de 5x7 celdas del NPC Standing
	var C_T = Color.TRANSPARENT
	var cells = [
		[COLOR_HEAD, COLOR_HEAD, COLOR_HEAD, COLOR_HEAD, C_T],
		[COLOR_HEAD, COLOR_TORSO, COLOR_SKIN, COLOR_TORSO, C_T],
		[COLOR_HEAD, COLOR_SKIN, COLOR_SKIN, COLOR_SKIN, C_T],
		[team_color, COLOR_TORSO, team_color, COLOR_TORSO, C_T],
		[COLOR_SKIN, team_color, COLOR_TORSO, team_color, COLOR_SKIN],
		[COLOR_SHOES, COLOR_SHOES, COLOR_SHOES, COLOR_SHOES, C_T],
		[COLOR_SHOES, C_T, C_T, COLOR_SHOES, C_T]
	]
	
	for y in range(7):
		for x in range(5):
			var draw_x = x if dir > 0 else 4 - x
			var cell_color = cells[y][draw_x]
			if cell_color != Color.TRANSPARENT:
				var rect_pos = pos + Vector2(x * pixel_size, y * pixel_size)
				draw_rect(Rect2(rect_pos, Vector2(pixel_size, pixel_size)), cell_color)

func _draw_landing_dust(x: float, y: float, jump_time: float) -> void:
	var fraction = abs(sin(jump_time))
	if fraction < 0.25:
		var progress = (0.25 - fraction) / 0.25
		var dust_color = Color("E5C158", 0.5 * (1.0 - progress))
		var radius = progress * 14.0
		draw_circle(Vector2(x - 8 - radius, y - 2), 3.0 * (1.0 - progress), dust_color)
		draw_circle(Vector2(x + 8 + radius, y - 2), 3.0 * (1.0 - progress), dust_color)
