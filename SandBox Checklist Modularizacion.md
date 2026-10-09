# Checklist Maestro de Modularización: `sandbox_grid.gd`
> **Propósito del Documento**: Este archivo sirve como el **panel de control vivo y registro de estado permanente** para la modularización de `sandbox_grid.gd`.  
> Para cada uno de los 12 módulos, documenta:
> 1. Su estado actual (`[x] COMPLETADO` o `[ ] PENDIENTE`).
> 2. La ruta definitiva del archivo modular en `res://sandbox/scripts/sandbox/modules/`.
> 3. Sus responsabilidades principales.
> 4. **Las consideraciones y enlaces pendientes** que deberán retocarse cuando se extraigan los módulos subsiguientes.
> 5. Las funciones exactas involucradas que requerirán repaso en cada hito.

---

## 1. Tabla de Progreso General

| Paso | Módulo | Archivo Destino | Estado | Líneas Aprox. | Fecha de Finalización |
| :-: | :--- | :--- | :-: | :-: | :-: |
| **1** | **`SandboxFontHelper`** | `modules/sandbox_font_helper.gd` | `[x] COMPLETADO` | ~510 | 2026-09-05 |
| **2** | **`SandboxHistoryManager`** | `modules/sandbox_history.gd` | `[x] COMPLETADO` | ~200 | 2026-09-05 |
| **3** | **`SandboxAchievementManager`** | `modules/sandbox_achievements.gd` | `[x] COMPLETADO` | ~1.080 | 2026-09-05 |
| **4** | **`SandboxDialogManager`** | `modules/sandbox_dialogs.gd` | `[x] COMPLETADO` | ~1.350 | 2026-10-06 |
| **5** | **`SandboxToolsPaintUI`** | `modules/sandbox_tools_ui.gd` | `[x] COMPLETADO` | ~1.100 | 2026-10-06 |
| **6** | **`SandboxSaveSystem`** | `modules/sandbox_save_system.gd` | `[x] COMPLETADO Y VERIFICADO` | ~1.400 | 2026-10-09 |
| **7** | **`SandboxWorkshopUI`** | `modules/sandbox_workshop_ui.gd` | `[x] COMPLETADO Y VERIFICADO` | ~2.713 | 2026-10-09 |
| **8** | **`SandboxLabUI`** | `modules/sandbox_lab.gd` | `[x] COMPLETADO Y VERIFICADO` | ~1.400 | 2026-10-09 |
| **9** | **`SandboxMusicSystem`** | `modules/sandbox_music.gd` | `[x] COMPLETADO (Listo para Verificación)` | ~1.200 | 2026-10-09 |
| **10** | **`SandboxNpcControlManager`**| `modules/sandbox_npc_control.gd` | `[ ] PENDIENTE (Siguiente a Ejecutar)` | ~800 | — |
| **11** | **`SandboxDisasterManager`** | `modules/sandbox_disasters.gd` | `[ ] PENDIENTE` | ~850 | — |
| **12** | **`SandboxMechanismsManager`** | `modules/sandbox_mechanisms.gd` | `[ ] PENDIENTE` | ~1.850 | — |

**Progreso Actual**: **9 de 12 módulos completados (75.0%)**. Líneas extraídas/delegadas del núcleo: **9.452 líneas** (de 21.844 a 12.392).

---

## 2. Fichas de Control Detalladas por Módulo

---

### [x] Paso 1: `SandboxFontHelper` (Módulo 12)
* **Estado**: **COMPLETADO**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_font_helper.gd`
* **Tipo de Objeto**: `RefCounted` (Clase utilitaria con métodos y caché estáticos).
* **Qué hace**:
  - Provee `SandboxFontHelper.get_safe_font(custom_emoji_font)` combinando `SystemFont` (`sans-serif`, `arial`) con los fallbacks locales de emojis (`Twemoji`, `NotoColorEmoji`, `FluentEmoji`) y fuentes del sistema.
  - Mantiene un único `FontVariation` en memoria para no recalcular fuentes en tiempo de ejecución.
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [x] **En Paso 4 (`SandboxDialogManager`)**: Todas las etiquetas y botones de UI consumen directamente `SandboxFontHelper.get_safe_font()`.
  - [ ] **En los restantes módulos de UI (Pasos 5, 7, 8, 9, 10, 12)**: Al extraer cada panel, sustituir cualquier llamado indirecto a `grid._get_safe_font()` por llamadas directas a `SandboxFontHelper.get_safe_font()`.
  - [ ] **En `sandbox_grid.gd`**: Cuando se finalice la extracción de todos los paneles de UI, comprobar cuántas llamadas a `_get_safe_font()` restan en el archivo central; si ya no quedan, eliminar el método puente temporal.
* **Funciones Clave a Repasar**:
  - `SandboxFontHelper.get_safe_font()`
  - Puente temporal en `sandbox_grid.gd`: `func _get_safe_font() -> Font`
  - Puente en `world_card.gd`: `func _get_safe_font() -> Font`

---

### [x] Paso 2: `SandboxHistoryManager` (Módulo 11)
* **Estado**: **COMPLETADO**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_history.gd`
* **Tipo de Objeto**: `RefCounted` (Instanciado e inyectado en `_ready()`).
* **Qué hace**:
  - Administra la pila circular de estados para Deshacer (`undo`) y Rehacer (`redo`).
  - Realiza copias profundas de snapshots: celdas, pintura de píxeles (`cell_paint_colors`), NPCs (`_deep_copy_npcs`), compuertas lógicas (`_deep_copy_logic_gates`) y pistones (`_deep_copy_pistons`).
  - Actualiza el estado visual habilitado/deshabilitado de los botones `↩️` y `↪️` del HUD (`update_undo_redo_ui`).
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [ ] **Con Paso 5 (`SandboxToolsPaintUI`)**: Los botones de la cuadrícula de acciones rápidas (`qa_grid`) de deshacer y rehacer deberán conectarse a `grid.history_manager.undo()` y `grid.history_manager.redo()`.
  - [ ] **Con Paso 6 (`SandboxSaveSystem`)**: Al cargar una partida nueva o importar un mapa, se debe llamar obligatoriamente a `grid.history_manager.clear_history()` para evitar que el usuario haga "Undo" y mezcle dos mundos distintos.
  - [ ] **Con Paso 12 (`SandboxMechanismsManager`)**: Cuando se extraiga la lógica de compuertas y pistones, la rutina de clonado profundo (`_deep_copy_logic_gates` y `_deep_copy_pistons`) deberá coordinarse con el nuevo módulo de mecanismos.
* **Funciones Clave a Repasar**:
  - `history_manager.save_state()`, `history_manager.undo()`, `history_manager.redo()`, `history_manager.clear_history()`
  - Métodos puente en `sandbox_grid.gd`: `save_history_state()`, `undo_history()`, `redo_history()`, `_update_undo_redo_ui()`

---

### [x] Paso 3: `SandboxAchievementManager` (Módulo 4)
* **Estado**: **COMPLETADO Y VERIFICADO**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_achievements.gd`
* **Tipo de Objeto**: `Node` (requiere `Timer` o `_process` para polling cada 2s).
* **Qué hace**:
  - Almacena el diccionario maestro de los 22 logros y la integración con Google Play Games Services (`GOOGLE_PLAY_ACHIEVEMENTS`) y Firebase Analytics.
  - Ejecuta la máquina de polling distribuido en 13 pasos (`_check_achievement_step`).
  - Ejecuta la animación cinemática del botón 🏆 (`_trigger_achievement_reveal`) y el cartel flotante deslizante (`_show_achievement_notification`).
  - Despliega el menú modal de logros con tarjetas deslizables.
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [x] **Con Paso 4 (`SandboxDialogManager`)**: El toast de notificación de logros utiliza `CanvasLayer` con Z-index 100. Coordinado con diálogos y tutoriales para no solaparse en pantalla.
  - [ ] **Con Paso 8 (`SandboxLabUI`)**: Cuando el usuario guarde su primer elemento custom o use los 3 slots a la vez, el laboratorio debe emitir la señal para desbloquear `mad_scientist` y `supreme_alchemist`.
  - [ ] **Con Paso 9 (`SandboxMusicSystem`)**: Cuando el jugador toque 5 notas seguidas, el sistema musical debe notificar al logro `compositor`.
  - [ ] **Con Paso 10 (`SandboxNpcControlManager`)**: Al poseer a un NPC en modo arcade, el mando debe disparar el logro `retro_time`.
  - [ ] **Con Paso 11 (`SandboxDisasterManager`)**: Al activar tsunamis de 4 líquidos (`tsunami_master`), tornados elementales (`wind_master`), erupción masiva (`volcano_giant`) o bombardero nivel 3 (`great-bomber`), el gestor de desastres debe notificar directamente a este manager en vez de escanear masivamente la cuadrícula.
* **Funciones Clave a Repasar**:
  - `_check_achievement_step(step)`, `_unlock_achievement(id)`, `_record_tornado_discovery(type)`
  - `_show_achievement_notification(id)`, `_setup_achievement_menu()`

---

### [x] Paso 4: `SandboxDialogManager` (Módulo 5)
* **Estado**: **COMPLETADO (Listo para Verificación)**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_dialogs.gd`
* **Tipo de Objeto**: `Node` (controla elementos visuales en `ui_root` y `CanvasLayer`).
* **Qué hace**:
  - Orquesta el tutorial guiado interactivo paso a paso y los efectos de pulso visual (`_start_pulse`, `_stop_pulse`).
  - Controla el popup de calificación de Google Play con sistema de estrellas (`_show_rating_popup`) y temporizador de sesión.
  - Genera las burbujas contextuales flotantes explicativas para compuertas, celdas, cañones y pistones (`_show_unified_tutorial_bubble`).
  - Presenta el diálogo especial de agradecimiento con shader multicolor neón (`_show_thank_you_popup`) y el visor de pantalla completa con zoom.
  - Presenta la burbuja informativa flotante centrada (`_show_centered_bubble`).
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [ ] **Con Paso 5 (`SandboxToolsPaintUI`)**: Cuando el usuario pulse "Limpiar Todo" (`Clear`), solicitar confirmación a través de un modal de este manager. Las aperturas de menús de herramientas y pintura llaman a `show_menu_reminder`.
  - [ ] **Con Paso 6 (`SandboxSaveSystem`)**: Los mensajes de confirmación de sobrescritura de ranura y avisos de éxito/error al importar `.sbu` usarán `show_centered_bubble`.
  - [ ] **Con Paso 7 (`SandboxWorkshopUI`)**: Los 8 avisos emergentes del taller ya llaman a `_show_centered_bubble`, enlazados mediante el método puente en `sandbox_grid.gd`.
  - [ ] **Con Paso 12 (`SandboxMechanismsManager`)**: Los disparadores `_show_cannon_tutorial_bubble`, `_show_piston_tutorial_bubble`, `_show_logic_gate_tutorial_bubble` se invocarán desde las herramientas de colocación hacia este manager.
* **Funciones Clave a Repasar**:
  - `dialog_manager.start_interactive_tutorial()`, `dialog_manager.show_main_tutorial_step()`
  - `dialog_manager.show_unified_tutorial_bubble()`, `dialog_manager.show_rating_popup()`, `dialog_manager.show_thank_you_popup()`
  - `dialog_manager.show_centered_bubble()`

---

### [x] Paso 5: `SandboxToolsPaintUI` (Módulo 7)
* **Estado**: **COMPLETADO (Listo para Verificación)**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_tools_ui.gd`
* **Tipo de Objeto**: `Node` (gestiona los paneles `tools_panel` y `paint_panel`).
* **Qué hace**:
  - Panel 🛠️ Herramientas: Slider de tamaño de pincel, slider de volumen master, conmutador de idiomas (ES/EN/etc.), botón de pausa con cuenta regresiva de 3 segundos y botón de reinicio.
  - Panel 🎨 Pintura: Selector de color RGBA/HSV, conmutador entre teñir fondo (`background_tex`) y elementos (`element_paint_tex`), historial dinámico de colores recientes.
  - Almacena y persiste la configuración del jugador en `user://tools_settings.json`.
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [x] **Con Paso 2 (`SandboxHistoryManager`)**: Los botones de deshacer/rehacer de la cuadrícula de acciones rápidas invocan limpiamente `grid.undo_history()` y `grid.redo_history()`.
  - [ ] **Con Paso 4 (`SandboxDialogManager`)**: Llamar al modal de confirmación antes de vaciar la cuadrícula al presionar el botón "Clear/Reset".
  - [ ] **Con Paso 8 (`SandboxLabUI`)**: Sincronizar el panel de pintura para que no interfiera con los colores de paleta de laboratorio.
* **Funciones Clave a Repasar**:
  - `_setup_tools_ui()`, `_update_game_volume()`, `_save_tool_settings()`, `_load_tool_settings()`
  - `_setup_paint_ui()`, `_add_recent_paint_color()`, `_update_paint_recent_ui()`, `_update_paint_slider_grabber()`

---

### [x] Paso 6: `SandboxSaveSystem` (Módulo 2)
* **Estado**: **COMPLETADO (Listo para Verificación)**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_save_system.gd`
* **Tipo de Objeto**: `Node` (I/O, compresión ZSTD, slots locales, thumbnails y modales de confirmación).
* **Qué hace**:
  - Serializa y deserializa el universo en formato `.sbu` comprimido (metadatos, celdas, tags, colores de pintura, NPCs, circuitos y ranuras de laboratorio).
  - Gestiona las 10 ranuras de guardado local en `user://`, comprobación de versiones de guardado y nombres seguros.
  - Genera capturas de pantalla miniaturas WebP lossless y gestiona caché de rotación (`user://rotation_cache.dat`).
  - Controla la exportación y carga con el explorador nativo en Android/PC y solicitud de permisos en runtime.
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [x] **CRÍTICO PARA PASO 7 (`SandboxWorkshopUI`)**: Métodos públicos `save_system.serialize_world_to_dict()` y `save_system.load_world_from_dict()` implementados y listos para ser consumidos por el Taller.
  - [x] **Con Paso 2 (`SandboxHistoryManager`)**: Al cargar cualquier ranura o archivo externo, se invoca `history_manager.clear_history()` para evitar historial inconsistente.
  - [ ] **Con Paso 8 (`SandboxLabUI`)**: `get_cleaned_lab_data()` y `restore_lab_data()` ya serializan la estructura de laboratorio; en Paso 8 se afinará la reactividad directa si se añaden más campos.
* **Funciones Clave Implementadas**:
  - `save_to_slot()`, `load_from_slot()`, `load_world_from_path()`, `serialize_world_to_dict()`, `load_world_from_dict()`
  - `import_sbu_file()`, `execute_import_data()`, `on_share_pressed()`, `on_import_pressed()`
  - `get_slot_data()`, `save_rotation_cache()`, `load_rotation_cache()`, `generate_thumbnail_image()`
  - `setup_save_ui()`, `confirm_save()`, `confirm_load()`, `show_confirm_dialog()`, `show_modal_message()`

---

### [x] Paso 7: `SandboxWorkshopUI` (Módulo 1)
* **Estado**: **COMPLETADO Y VERIFICADO**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_workshop_ui.gd`
* **Tipo de Objeto**: `Node` (panel visual completo `workshop_panel`).
* **Qué hace**:
  - Gestiona la comunidad en línea vía Firebase Firestore y Storage.
  - Pestañas Top Semanal (con subcategorías Histórico, Tendencias, Joyas Ocultas, Ruleta), Recientes, Mis Mundos, Mis Descargas y paginación asíncrona.
  - Búsqueda por código de 8 caracteres con dígito verificador hash (Base 36).
  - Sistema de likes, votos, buffer diferido (RTDB) y reportes de contenido.
  - Diálogos de subida y edición de mapas, cuotas de descargas gratuitas diarias y recompensas AdMob.
  - Temporizador de cuenta regresiva en vivo sincronizado con los ciclos de actualización UTC.
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [x] **Enlace con Paso 6 (`SandboxSaveSystem`)**: `load_world_from_path(path)` integrado para ejecutar mundos descargados sin inconsistencias. Diálogos modales y overlays enlazados a `save_system`. Selector de ranuras de subida consume `save_system.get_slot_data()`.
  - [x] **Compatibilidad con `world_card.gd`**: Las tarjetas de previsualización se comunican limpiamente mediante sus señales `download_requested`, `play_requested`, `delete_requested`, `like_requested`, `unlike_requested`, `report_requested`, `edit_requested`.
  - [ ] **Con Paso 8 (`SandboxLabUI`)**: Cuando se carguen o descarguen mundos de la comunidad que contengan materiales de laboratorio, `SandboxSaveSystem` restaura los datos del laboratorio manteniendo la consistencia de paleta.
* **Funciones Clave Implementadas**:
  - `setup_workshop_ui()`, `fetch_top_async()`, `fetch_recientes_async()`, `fetch_mis_descargas_async()`, `fetch_mis_mundos_async()`
  - `on_search_world_requested()`, `verify_map_code()`, `on_world_play_requested()`, `on_world_download_requested()`
  - `show_upload_world_dialog()`, `show_edit_world_dialog()`, `show_world_manager_dialog()`, `show_upload_slot_selector()`
  - `load_workshop_economy()`, `save_workshop_economy()`, `get_next_update_unix()`, `update_day_check()`, `process_countdown()`

---

### [x] Paso 8: `SandboxLabUI` (Módulo 3)
* **Estado**: **COMPLETADO Y VERIFICADO**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_lab.gd`
* **Tipo de Objeto**: `Node` (panel `lab_panel`).
* **Qué hace**:
  - Permite al usuario diseñar 3 materiales experimentales (IDs 900, 901, 902).
  - Configura estados físicos (sólido, líquido, gas, polvo), gravedades, tags de reacción (ácido, virus, explosiones, vórtice) y colores primario, secundario y terciario.
  - Sincroniza las filas de la textura de 2048x3 (`palette_tex`) que alimentan el fragment shader `sandbox_render.gdshader`.
  - Controla el desbloqueo temporal de 12 horas mediante anuncios recompensados de AdMob y procesa la cuenta regresiva en vivo.
  - Gestiona el tutorial guiado con máscaras oscuras dinámicas (`update_lab_tutorial_highlight()`).
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [x] **Con Paso 6 (`SandboxSaveSystem`)**: `lab_ui.get_cleaned_lab_data()` y `lab_ui.restore_lab_data(...)` integrados y enlazados bidireccionalmente con `SandboxSaveSystem`.
  - [x] **Con Paso 3 (`SandboxAchievementManager`)**: Al equipar el primer material experimental diseñado se desbloquea el logro `mad_scientist`.
  - [ ] **Con Paso 9 (`SandboxMusicSystem`)**: Asegurar que los materiales de laboratorio no interfieran con las notas musicales registradas.
* **Funciones Clave Implementadas**:
  - `setup_lab_ui()`, `sync_palette_to_shader()`, `apply_custom_material_to_engine()`
  - `save_lab_state()`, `load_lab_state()`, `update_custom_mats_in_material_grid()`
  - `update_lab_inspector()`, `update_lab_preview()`, `process_lab()`
  - `get_cleaned_lab_data()`, `restore_lab_data()`, `connect_admob_signals()`

---

### [x] Paso 9: `SandboxMusicSystem` (Módulo 6)
* **Estado**: **COMPLETADO (Listo para Verificación)**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_music.gd`
* **Tipo de Objeto**: `Node` (gestiona UI musical y pool de polifonía de audio de 32 canales).
* **Qué hace**:
  - Mapea 5 instrumentos con escalas cromáticas afinadas (4 pianos, batería acústica, metrónomo) y calcula semitonos y frecuencias en tiempo real.
  - Administra el bus dedicado `MusicBus` con `AudioEffectLimiter` para prevenir saturación y distorsión digital en acordes densos.
  - Genera la interfaz gráfica dual `music_panel` con sub-pestañas: `⚡ Circuitos` (mecanismos, compuertas, pistones) y `🎵 Música` (instrumentos, teclado, slider/input numérico de BPM y conmutador de visualización de notas).
  - Detecta taps sobre bloques musicales y muestra el popup contextual de nota musical y octava (`update_music_note_popup`).
  - Reproduce las notas al ser tocadas por corriente eléctrica y activa la coreografía de baile en los NPCs cercanos (`trigger_npc_dance`).
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [x] **Con el Núcleo Eléctrico (`sandbox_grid.gd`)**: En `_process_electricity`, la activación de cualquier celda con tag `MUSIC` invoca `_play_music_note(inst, note, ...)`, delegada limpiamente a `music_system`.
  - [x] **Con Paso 3 (`SandboxAchievementManager`)**: Al tocar 5 notas consecutivas en menos de 1s, reporta el logro `compositor`.
  - [ ] **Con Paso 12 (`SandboxMechanismsManager`)**: La sub-pestaña de Circuitos en `music_panel` interactúa con compuertas, pistones y cañones; al modularizar mecanismos, se coordinará el acceso a sus propiedades.
* **Funciones Clave Implementadas**:
  - `init_audio_bus_and_pool()`, `register_musical_materials()`, `place_music_block()`, `play_music_note()`
  - `get_music_data()`, `encode_music_id()`, `is_music_mat()`, `trigger_npc_dance()`
  - `setup_music_ui()`, `close_music_menu()`, `setup_music_button()`, `is_music_active()`, `update_music_note_popup()`

---

### [ ] Paso 10: `SandboxNpcControlManager` (Módulo 10)
* **Estado**: **PENDIENTE**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_npc_control.gd`
* **Tipo de Objeto**: `Node` (controla la capa visual `NPCControlGUI` y procesa inputs táctiles).
* **Qué hace**:
  - Despliega el joystick circular virtual y los botones de salto y acción para poseer a cualquier personaje del mapa.
  - Adapta contextualmente el botón de acción según la clase del personaje (el minero pica túneles, el arquero tensa el arco, el guerrero asesta tajos, el mago conjura fuego).
  - Gestiona la entrada táctil analógica y el desposeer al personaje devolviendo el control a la IA autónoma.
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [ ] **Con Paso 3 (`SandboxAchievementManager`)**: Al poseer un NPC por primera vez, desbloquear el logro `retro_time`.
  - [ ] **Con Paso 4 (`SandboxDialogManager`)**: Asegurar que mientras el Gamepad táctil esté activo, se oculten burbujas tutoriales que puedan interferir en la visión.
  - [ ] **Con el Núcleo de NPCs (`sandbox_grid.gd`)**: Las acciones de excavación o disparo invocan las rutinas especializadas del grid (`_miner_dig`, `_shoot_arrow`, `_shoot_fireball`).
* **Funciones Clave a Repasar**:
  - `_setup_npc_control_gui()`, `_handle_controlled_npc_input()`, `_trigger_controlled_npc_action()`
  - `_stop_controlling_npc()`, `_update_arcade_dynamic_button()`

---

### [ ] Paso 11: `SandboxDisasterManager` (Módulo 8)
* **Estado**: **PENDIENTE**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_disasters.gd`
* **Tipo de Objeto**: `Node` (procesa eventos marco en `_process`).
* **Qué hace**:
  - Panel de activación de desastres 🌋 (Volcán, Tornado, Tsunami, Bombardero, Terremoto, Lluvia ácida y Tormenta eléctrica).
  - Controla la cinemática de erupción volcánica y expulsión de bombas de lava.
  - Controla el vórtice del tornado y su nodo shader de distorsión visual (`tornado_visual.gdshader`).
  - Simula la ola expansiva del tsunami, el vuelo del avión bombardero y las sacudidas sísmicas.
  - Ofrece el botón de parada de emergencia global (`_reset_all_disasters`).
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [ ] **Con Paso 3 (`SandboxAchievementManager`)**: Notificar directamente los logros climáticos (`wind_master`, `tsunami_master`, `volcano_giant`, `great-bomber`, `dancing-rain`).
  - [ ] **Con el Núcleo Físico (`sandbox_grid.gd`)**: Los proyectiles y celdas modificadas por desastres deben invocar `grid.set_cell(x, y, id)` y `grid.explode(x, y, radius)`.
* **Funciones Clave a Repasar**:
  - `_setup_disaster_ui()`, `_reset_all_disasters()`
  - `_process_volcano()`, `_process_tornado()`, `_process_tsunami()`
  - `_process_bombardero()`, `_process_earthquake()`, `_process_weather()`

---

### [ ] Paso 12: `SandboxMechanismsManager` (Módulo 9)
* **Estado**: **PENDIENTE**
* **Ruta del Archivo**: `res://sandbox/scripts/sandbox/modules/sandbox_mechanisms.gd`
* **Tipo de Objeto**: `Node` (procesa transporte de tuberías y disparo de cañones).
* **Qué hace**:
  - Colocación y orientación cardinal de cañones y tuberías neumáticas (simples y dobles X2).
  - Simulación paso a paso del flujo de partículas y absorción/transporte/eyección de soldados (NPCs) en tuberías.
  - Detección de energización eléctrica de cañones y disparo balístico según ángulo y potencia.
  - Despliega el panel de ajustes del cañón (`CannonSettingsPanel`) y el selector de color de LEDs (`_open_led_color_panel`).
* **Consideraciones a Actualizar Pendientes en Próximos Módulos**:
  - [ ] **Con Paso 6 (`SandboxSaveSystem`)**: Serializar y deserializar las listas `active_cannons`, `active_pipes` y `active_pipes_x2`.
  - [ ] **Con Paso 4 (`SandboxDialogManager`)**: Disparar las burbujas tutoriales al seleccionar tuberías o cañones en la barra de herramientas.
  - [ ] **Con el Núcleo de Simulación (`sandbox_grid.gd`)**: Coordinar la absorción y eyección de NPCs con la lista `active_npcs` del núcleo.
* **Funciones Clave a Repasar**:
  - `_simulate_cannons()`, `_fire_cannon()`, `_open_cannon_settings_panel()`
  - `_simulate_pipes()`, `_try_absorb_npc_at_endpoint()`, `_eject_npc_from_pipe()`
  - `_open_led_color_panel()`

---

## 3. Bitácora de Ejecución y Enlaces Realizados

*Registro cronológico de los módulos completados y qué funciones fueron retocadas:*

### Hito 1 (2026-09-05): Paso 1 - `SandboxFontHelper`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_font_helper.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se eliminó la variable `var _combined_font: FontVariation` (línea 678 original).
  - Se redujo la función `_get_safe_font()` a un puente limpio de 2 líneas que delega en `SandboxFontHelper.get_safe_font(custom_emoji_font)`.
  - Se mantuvieron intactas las 198 llamadas internas en `sandbox_grid.gd`.
- **Modificaciones en `world_card.gd`**:
  - Se eliminó la copia duplicada de `_get_safe_font()` (líneas 501-526 originales) y su variable estática `_combined_font`.
  - La función `_get_safe_font()` ahora delega en `SandboxFontHelper.get_safe_font()`.
- **Pruebas Superadas**: Textos, fuentes y emojis verificados en pantalla sin errores de parser en Godot.

### Hito 2 (2026-09-05): Paso 2 - `SandboxHistoryManager`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_history.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se eliminaron las variables `history_buffer`, `history_max_steps` y `history_current_index` (líneas 584-586 originales).
  - Se añadió la instancia `var history_manager: SandboxHistoryManager`.
  - En `_ready()`: Se inicializa e inyecta la instancia con `history_manager = SandboxHistoryManager.new()`, `history_manager.setup(self)` y `history_manager.save_state()`.
  - Se extrajeron ~180 líneas de código original (copia profunda de entidades, buffer de snapshots, lógica de restauración de celdas, pintura y electricidad) hacia el módulo.
  - Se implementaron los 4 métodos puente en `sandbox_grid.gd`: `save_history_state()`, `undo_history()`, `redo_history()` y `_update_undo_redo_ui()`.
  - **Reducción neta**: -171 líneas en `sandbox_grid.gd`.
- **Pruebas Superadas y Corrección Validada**:
  - Deshacer trazo de arena/piedra con `↩️` comprobado.
  - Rehacer trazo con `↪️` comprobado.
  - Persistencia de NPCs tras deshacer una barrera comprobada.
  - Comprobación de límites de pila sin crasheos.
  - **Corrección de cargas eléctricas en tránsito**: Se incorporó en el snapshot `charge_visual_buffer`, `active_charge_indices` y `powered_frame`, garantizando que la electricidad en movimiento por cables continúe su propagación intacta al hacer Undo/Redo.

### Hito 3 (2026-09-05): Paso 3 - `SandboxAchievementManager`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_achievements.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se añadió la instancia `var achievement_manager: SandboxAchievementManager`.
  - En `_ready()`: Se inicializa con `achievement_manager = SandboxAchievementManager.new()`, se añade al árbol y se vincula con `setup(self)`.
  - Se extrajo el bloque masivo de datos y polling distribuido (constantes `GOOGLE_PLAY_ACHIEVEMENTS`, `ACHIEVEMENT_ICONS`, diccionario maestro de 22 logros, temporizadores y máquina de estados de 13 pasos).
  - Se extrajo el bloque masivo de interfaz y cinemáticas (`_trigger_achievement_reveal`, `_show_achievement_notification`, `_setup_achievement_menu`, `_on_achievement_item_clicked`).
  - Se unificó el botón de logros en `_setup_action_buttons()` delegando a `achievement_manager.setup_achievement_button()`.
  - Se mantuvieron getters/setters y métodos puente transparentes para preservar 100% de compatibilidad hacia atrás en todo el proyecto.
- **Pruebas Superadas y Verificadas por el Desarrollador**:
  - **Persistencia**: Carga y guardado de `user://achievements.cfg` verificado correctamente con logros preexistentes.
  - **Menú de Trofeos**: Apertura fluida del panel modal con el botón dorado 🏆, scroll suave de las 22 tarjetas, iconos y popup de detalle centrada funcionando sin problemas.
  - **Desbloqueo en Caliente**: Verificado el desbloqueo de `electrifying` (agua + electricidad) y `boom` (cadena de TNT).
  - **Toast y Audio**: Notificación animada con borde dorado deslizante y reproducción de SFX (`achievement_unlock` / `achievement_menu_unlock`) funcionando sin micro-tirones ni errores de consola.

### Hito 4 (2026-10-06): Paso 4 - `SandboxDialogManager`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_dialogs.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se añadió la instancia `var dialog_manager: SandboxDialogManager`.
  - En `_ready()`: Se inicializa con `dialog_manager = SandboxDialogManager.new()`, se añade al árbol con `add_child(dialog_manager)` y se vincula con `dialog_manager.setup(self)`.
  - Se extrajo el bloque completo de tutoriales interactivos, onboarding de zoom, popups de bienvenida y calificación en Google Play, efectos de atención visual (`start_pulse` / `stop_pulse`), recordatorios en menús, burbujas flotantes de mecanismos, diálogo de agradecimiento con shader multicolor neón, visor modal de imágenes y burbujas centradas.
  - Se reemplazaron todas las llamadas tipográficas locales por `SandboxFontHelper.get_safe_font()`.
  - Se mantuvieron 19 métodos puente y 15 propiedades proxy con getters/setters en `sandbox_grid.gd` para garantizar 100% de compatibilidad hacia atrás en todo el código preexistente.
  - **Reducción neta**: -1.221 líneas en `sandbox_grid.gd` (de 20.601 a 19.380 líneas).

### Hito 5 (2026-10-06): Paso 5 - `SandboxToolsPaintUI`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_tools_ui.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se añadió la instancia `var tools_ui: SandboxToolsPaintUI`.
  - En `_ready()`: Se inicializa con `tools_ui = SandboxToolsPaintUI.new()`, se añade al árbol con `add_child(tools_ui)` y se vincula con `tools_ui.setup(self)`.
  - Se extrajo el bloque completo de configuración de herramientas (`_setup_tools_ui`, `_save_tool_settings`, `_load_tool_settings`, `_update_game_volume`).
  - Se extrajo el bloque completo del sistema de pintura cromática (`_setup_paint_ui`, `_add_recent_paint_color`, `_update_paint_recent_ui`, `_update_paint_slider_grabber`).
  - Se encapsuló la delegación del botón de herramientas (`_on_tools_btn_pressed`).
  - Se crearon propiedades proxy transparentes para `tools_panel`, `paint_panel`, `brush_radius`, `paint_brush_radius_idx`, `game_volume`, `pre_mute_volume`, `is_muted`, `selected_paint_color`, `paint_mode`, `recent_paint_colors` e `is_unpausing`.
  - **Reducción neta**: -1.057 líneas en `sandbox_grid.gd` (de 19.381 a 18.324 líneas).

### Hito 6 (2026-10-09): Paso 6 - `SandboxSaveSystem`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_save_system.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se añadió la instancia `var save_system: SandboxSaveSystem`.
  - En `_ready()`: Inicialización con `save_system = SandboxSaveSystem.new()`, inyección con `save_system.setup(self)`.
  - Se extrajo la serialización/deserialización binaria comprimida `.sbu`, 10 slots locales, snapshots WebP y modales de confirmación.
  - Se implementaron delegadores públicos `save_world_to_path`, `load_world_from_path`, `serialize_world_to_dict`, `load_world_from_dict`.
  - **Reducción neta**: -1.280 líneas en `sandbox_grid.gd` (de 18.324 a 17.044 líneas).

### Hito 7 (2026-10-09): Paso 7 - `SandboxWorkshopUI`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_workshop_ui.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se añadió la instancia `var workshop_ui: SandboxWorkshopUI`.
  - En `_ready()`: Inicialización con `workshop_ui = SandboxWorkshopUI.new()`, inyección con `workshop_ui.setup(self)`.
  - Se extrajo el sistema completo del Taller en la nube (Firestore/Storage, Top Semanal, Recientes, Mis Mundos, Mis Descargas, likes diferidos, reportes, buscador Base 36, economía AdMob y temporizador en vivo).
  - Coordinado con `SandboxSaveSystem` y `world_card.gd`.
  - **Reducción neta**: -2.713 líneas en `sandbox_grid.gd` (de 17.044 a 14.331 líneas).

### Hito 8 (2026-10-09): Paso 8 - `SandboxLabUI`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_lab.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se añadió la instancia `var lab_ui: SandboxLabUI`.
  - En `_ready()`: Inicialización con `lab_ui = SandboxLabUI.new()`, inyección con `lab_ui.setup(self)`.
  - Se extrajo el diseñador de 3 materiales experimentales (IDs 900, 901, 902), sincronización con `palette_tex` (2048x3) para shaders, desbloqueo AdMob por 12 horas y tutorial con máscaras.
  - Enlazado bidireccionalmente con `SandboxSaveSystem` para persistencia en `.sbu`.
  - **Reducción neta**: -1.090 líneas en `sandbox_grid.gd` (de 14.331 a 13.241 líneas).

### Hito 9 (2026-10-09): Paso 9 - `SandboxMusicSystem`
- **Módulo Creado**: `res://sandbox/scripts/sandbox/modules/sandbox_music.gd`.
- **Modificaciones en `sandbox_grid.gd`**:
  - Se añadió la instancia `var music_system: SandboxMusicSystem`.
  - En `_ready()`: Inicialización con `music_system = SandboxMusicSystem.new()`, inyección con `music_system.setup(self)`.
  - Se extrajo la configuración de bus `MusicBus` con `AudioEffectLimiter` y pool de 32 `AudioStreamPlayer`.
  - Se extrajo el registro de materiales musicales (5 instrumentos afinados + metrónomo ID 600) y colocación de bloques 2x2.
  - Se extrajo la interfaz visual dual `music_panel` (`⚡ Circuitos` y `🎵 Música`) con selector de instrumentos, teclado cromático, slider numérico de BPM y conmutador de etiquetas.
  - Se extrajo el popup contextual de nota al tocar bloques en la cuadrícula (`update_music_note_popup`).
  - Se conservaron 13 métodos delegadores y 12 propiedades proxy con getters/setters en `sandbox_grid.gd` para 100% compatibilidad hacia atrás.
  - **Reducción neta**: -849 líneas en `sandbox_grid.gd` (de 13.241 a 12.392 líneas).



