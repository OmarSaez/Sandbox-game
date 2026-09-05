extends RefCounted
class_name SandboxHistoryManager

## Gestor modular del historial de estados (Deshacer / Rehacer).
## Administra la pila circular de snapshots de celdas, pintura, NPCs, circuitos y pistones.

var grid: Node = null

var history_buffer: Array = []
var history_max_steps: int = 6 # Almacena 6 snapshots para permitir 5 pasos de deshacer
var history_current_index: int = -1

func setup(p_grid: Node) -> void:
	grid = p_grid

## Limpia la pila completa de historial (útil al cargar nuevos mapas o reiniciar)
func clear_history() -> void:
	history_buffer.clear()
	history_current_index = -1
	update_undo_redo_ui()

## Guarda un snapshot del estado actual de la cuadrícula y entidades
func save_state() -> void:
	if not grid: return
	
	# Si no estamos en la cabeza del buffer (se hizo un Undo previo), descartar el futuro
	if history_current_index < history_buffer.size() - 1:
		history_buffer.resize(history_current_index + 1)

	# Captura profunda del snapshot incluyendo buffers de propagación eléctrica
	var current_snapshot = {
		"cells": grid.cells.duplicate(),
		"charge": grid.charge_array.duplicate(),
		"charge_visual_buffer": grid.charge_visual_buffer.duplicate(),
		"active_charge_indices": grid.active_charge_indices.duplicate(),
		"powered_frame": grid.powered_frame.duplicate(),
		"tags": grid.tags_array.duplicate(),
		"chunks": grid.chunks_active.duplicate(),
		"next_chunks": grid.next_chunks_active.duplicate(),
		"npcs": _deep_copy_npcs(),
		"logic_gates": _deep_copy_logic_gates(),
		"active_pistons": _deep_copy_pistons(),
		"cell_paint": grid.cell_paint_colors.duplicate(),
		"bg_paint": grid.background_img.duplicate(),
		"el_paint_img": grid.element_paint_img.duplicate()
	}
	
	# Optimización: evitar guardar estados idénticos consecutivos
	if history_buffer.size() > 0:
		var last = history_buffer.back()
		if last.cells == current_snapshot.cells and last.cell_paint == current_snapshot.cell_paint and not grid.is_paint_tool_active:
			return

	history_buffer.append(current_snapshot)
	
	if history_buffer.size() > history_max_steps:
		history_buffer.pop_front()
	
	history_current_index = history_buffer.size() - 1
	update_undo_redo_ui()

## Deshace el último paso registrado
func undo() -> void:
	if not grid: return
	if history_current_index > 0:
		history_current_index -= 1
		var snapshot = history_buffer[history_current_index]
		_restore_snapshot(snapshot)

## Rehace el paso previamente deshecho
func redo() -> void:
	if not grid: return
	if history_current_index < history_buffer.size() - 1:
		history_current_index += 1
		var snapshot = history_buffer[history_current_index]
		_restore_snapshot(snapshot)

## Aplica el snapshot completo al controlador central
func _restore_snapshot(snapshot: Dictionary) -> void:
	_restore_npcs_from_snapshot(snapshot)
	_restore_logic_gates_from_snapshot(snapshot)
	
	grid.cells = snapshot.cells.duplicate()
	grid.charge_array = snapshot.charge.duplicate()
	grid.tags_array = snapshot.tags.duplicate()
	grid.chunks_active = snapshot.chunks.duplicate()
	grid.next_chunks_active = snapshot.next_chunks.duplicate()
	
	# Restaurar buffers de electricidad de bajo nivel (mantener pulsos activos en cables)
	if snapshot.has("charge_visual_buffer"):
		grid.charge_visual_buffer = snapshot.charge_visual_buffer.duplicate()
	else:
		grid.charge_visual_buffer.fill(0)
		for ci in range(grid.charge_array.size()):
			if grid.charge_array[ci] > 0:
				grid.charge_visual_buffer[ci] = 100
				
	if snapshot.has("active_charge_indices"):
		grid.active_charge_indices = snapshot.active_charge_indices.duplicate()
	else:
		grid.active_charge_indices.clear()
		
	if snapshot.has("powered_frame"):
		grid.powered_frame = snapshot.powered_frame.duplicate()
	else:
		grid.powered_frame.fill(-1)
		
	# Garantizar que cualquier celda conductora con carga activa esté registrada para propagación en el motor C++
	var active_set = {}
	for idx in grid.active_charge_indices:
		active_set[idx] = true
	for ci in range(grid.charge_array.size()):
		if grid.charge_array[ci] > 0 and not active_set.has(ci):
			var cid = grid.cells[ci] & 0xFFFF
			if cid > 0 and grid._get_tags_id(cid) < grid.material_tags_raw.size():
				if grid.material_tags_raw[grid._get_tags_id(cid)] & SandboxMaterial.Tags.CONDUCTOR:
					grid.active_charge_indices.append(ci)
					active_set[ci] = true
					
	grid.charge_queued_frame.fill(-1)
	grid.next_charge_indices.clear()
	grid.charge_dirty = true
	
	if snapshot.has("cell_paint"):
		grid.cell_paint_colors = snapshot.cell_paint.duplicate()
		if snapshot.has("bg_paint"):
			grid.background_img.copy_from(snapshot.bg_paint)
			grid.background_dirty = true
		if snapshot.has("el_paint_img"):
			grid.element_paint_img.copy_from(snapshot.el_paint_img)
			grid.element_paint_dirty = true
	
	# Despertar todos los chunks para que la electricidad vuelva a propagarse
	for i in range(grid.next_chunks_active.size()):
		grid.next_chunks_active[i] = 60
		
	grid._reconstruct_sources_from_cells(snapshot)
	grid._update_texture()
	grid.queue_redraw()
	update_undo_redo_ui()

## Actualiza la modulación alfa de los botones de Deshacer y Rehacer en la UI
func update_undo_redo_ui() -> void:
	if not grid: return
	if grid.ui_elements.has("btn_undo") and is_instance_valid(grid.ui_elements["btn_undo"]):
		var can_undo = history_current_index > 0
		grid.ui_elements["btn_undo"].modulate.a = 1.0 if can_undo else 0.3

	if grid.ui_elements.has("btn_redo") and is_instance_valid(grid.ui_elements["btn_redo"]):
		var can_redo = history_current_index < history_buffer.size() - 1
		grid.ui_elements["btn_redo"].modulate.a = 1.0 if can_redo else 0.3

# --- RUTINAS DE COPIA PROFUNDA Y RESTAURACIÓN ---

func _deep_copy_npcs() -> Array:
	var result = []
	for npc in grid.active_npcs:
		var copy = npc.duplicate()
		copy["pos"] = Vector2i(npc.pos.x, npc.pos.y)
		# Limpiar referencias volátiles que no deben persistir al hacer Undo
		copy["social_target"] = null
		copy["cached_target"] = null
		copy["cached_closest_enemy"] = null
		copy["cached_closest_ally"] = null
		result.append(copy)
	return result

func _deep_copy_logic_gates() -> Array:
	var result = []
	for gate in grid.active_logic_gates:
		var copy = gate.duplicate()
		if copy.has("grid_pos"):
			copy["grid_pos"] = Vector2i(copy.grid_pos.x, copy.grid_pos.y)
		result.append(copy)
	return result

func _deep_copy_pistons() -> Array:
	var result = []
	for p in grid.active_pistons:
		var copy = p.duplicate()
		copy["pos"] = Vector2i(p.pos.x, p.pos.y)
		result.append(copy)
	return result

func _restore_npcs_from_snapshot(snapshot: Dictionary) -> void:
	# 1. Limpiar píxeles actuales de los NPCs en la cuadrícula
	for npc in grid.active_npcs:
		grid._draw_npc_pixels(npc, 0)
	grid.active_npcs.clear()
	grid.controlled_npc = null
	grid.active_projectiles.clear()
	
	# 2. Restaurar NPCs desde el snapshot
	if snapshot.has("npcs"):
		for npc in snapshot.npcs:
			var copy = npc.duplicate()
			copy["pos"] = Vector2i(npc.pos.x, npc.pos.y)
			copy["social_target"] = null
			copy["cached_target"] = null
			copy["cached_closest_enemy"] = null
			copy["cached_closest_ally"] = null
			copy["stuck_timer"] = 0.0
			grid.active_npcs.append(copy)

func _restore_logic_gates_from_snapshot(snapshot: Dictionary) -> void:
	grid.active_logic_gates.clear()
	if snapshot.has("logic_gates"):
		for gate in snapshot.logic_gates:
			var copy = gate.duplicate()
			if copy.has("grid_pos"):
				copy["grid_pos"] = Vector2i(copy.grid_pos.x, copy.grid_pos.y)
			grid.active_logic_gates.append(copy)
