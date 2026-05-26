extends Node

var _plugin: Object = null
var current_screen: String = "gameplay"
var gameplay_time_accumulator: float = 0.0
var check_timer: float = 0.0

func _ready() -> void:
	# Initialize Android plugin if available
	if Engine.has_singleton("FirebaseAnalyticsPlugin"):
		_plugin = Engine.get_singleton("FirebaseAnalyticsPlugin")
		print("[AnalyticsManager] FirebaseAnalyticsPlugin initialized successfully.")
	else:
		print("[AnalyticsManager] FirebaseAnalyticsPlugin not found (PC editor / other platforms). Using local console logs.")

	# Log initial application start
	log_event("app_start", {})

func _process(delta: float) -> void:
	# Periodically check active UI screens (every 200ms for performance optimization)
	check_timer += delta
	if check_timer >= 0.2:
		check_timer = 0.0
		_update_current_screen()
	
	# Accumulate active gameplay time when no menu is open
	if current_screen == "gameplay":
		gameplay_time_accumulator += delta
		# Periodically flush every 60 seconds of continuous gameplay to prevent losing data on crash/force close
		if gameplay_time_accumulator >= 60.0:
			flush_gameplay_time()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			print("[AnalyticsManager] App suspended/paused, flushing active play time.")
			flush_gameplay_time()
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			print("[AnalyticsManager] App closing, flushing active play time.")
			flush_gameplay_time()

func log_event(event_name: String, params: Dictionary = {}) -> void:
	if _plugin:
		_plugin.logEvent(event_name, params)
	else:
		print("[AnalyticsManager] [Editor Log] Event: '%s' | Params: %s" % [event_name, str(params)])

func set_screen(screen_name: String) -> void:
	if current_screen == screen_name:
		return
		
	# If we are transitioning away from gameplay, record the gameplay duration first
	if current_screen == "gameplay":
		flush_gameplay_time()
		
	current_screen = screen_name
	
	if _plugin:
		_plugin.setScreenName(screen_name)
	else:
		print("[AnalyticsManager] [Editor Log] Screen View: '%s'" % screen_name)

func flush_gameplay_time() -> void:
	if gameplay_time_accumulator >= 1.0:
		var duration = int(gameplay_time_accumulator)
		log_event("gameplay_duration", {
			"seconds": duration,
			"duration_seconds": duration
		})
		gameplay_time_accumulator = 0.0

# Recursively finds the SandboxGrid node in the active scene tree
func _find_sandbox_grid(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	if node.name == "SandboxGrid" or node.has_method("_toggle_category_panel"):
		return node
	for child in node.get_children():
		var res = _find_sandbox_grid(child)
		if res:
			return res
	return null

func _update_current_screen() -> void:
	var new_screen = "gameplay"
	
	var scene = get_tree().current_scene
	if scene:
		# Check blocking full-screen overlay popups first
		var ui = scene.get_node_or_null("UI")
		if ui:
			if ui.has_node("RatingPopupOverlay"):
				new_screen = "rating"
			elif ui.has_node("ThankYouPopupOverlay"):
				new_screen = "thank_you"
			elif ui.has_node("WelcomeOverlay"):
				new_screen = "welcome"
		
		# If no overlay is open, check visibility of SandboxGrid panels
		if new_screen == "gameplay":
			var grid = _find_sandbox_grid(scene)
			if grid:
				if "achievement_panel" in grid and is_instance_valid(grid.achievement_panel) and grid.achievement_panel.visible:
					new_screen = "achievements"
				elif "lab_panel" in grid and is_instance_valid(grid.lab_panel) and grid.lab_panel.visible:
					new_screen = "lab"
				elif "tools_panel" in grid and is_instance_valid(grid.tools_panel) and grid.tools_panel.visible:
					new_screen = "tools"
				elif "disaster_panel" in grid and is_instance_valid(grid.disaster_panel) and grid.disaster_panel.visible:
					new_screen = "disasters"
				elif "npc_panel" in grid and is_instance_valid(grid.npc_panel) and grid.npc_panel.visible:
					new_screen = "npcs"
				elif "paint_panel" in grid and is_instance_valid(grid.paint_panel) and grid.paint_panel.visible:
					new_screen = "paint"
				elif "save_panel" in grid and is_instance_valid(grid.save_panel) and grid.save_panel.visible:
					new_screen = "save_load"
				elif "music_panel" in grid and is_instance_valid(grid.music_panel) and grid.music_panel.visible:
					new_screen = "music"
				elif "controlled_npc" in grid and grid.controlled_npc != null:
					# Play time spent controlling an NPC
					new_screen = "npc_control"

	set_screen(new_screen)
