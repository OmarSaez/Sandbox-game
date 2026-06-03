extends SceneTree

func _init():
	print("==================================================")
	print(" RUNNING INTEGRATION TEST: CANNON HOSE STREAM ")
	print("==================================================")
	
	# Load the main scene to get all nodes and initializations
	var main_scene = load("res://scenes/main/main_scene.tscn")
	if not main_scene:
		print("FAIL: Could not load main_scene.tscn")
		quit(1)
		return
		
	var instance = main_scene.instantiate()
	root.add_child(instance)
	
	# Let's wait a bit for ready to complete
	await create_timer(0.5).timeout
	
	var grid: SandboxGrid = instance.get_node("SandboxGrid")
	if not grid:
		print("FAIL: SandboxGrid node not found in main scene!")
		quit(1)
		return

	# Force grid to be ready (normally initialized in viewport resize, but we are headless)
	grid.grid_width = 135
	grid.grid_height = 240
	grid.dynamic_grid_height = 200
	grid.cells.resize(grid.grid_width * grid.grid_height)
	grid.cells.fill(0)
	grid.charge_array.resize(grid.grid_width * grid.grid_height)
	grid.charge_array.fill(0)
	grid.active_cannons.clear()
	grid.active_pipes.clear()
	grid.active_projectiles.clear()
	grid.active_battery_indices.clear()
	grid.is_grid_ready = true

	# Snapped coordinate for cannon placement (make sure gx-3 >= 0 and gx+6 < grid_width etc.)
	var gx = 20
	var gy = 20
	
	# Place the cannon Snapped
	grid._place_cannon(gx, gy)
	if grid.active_cannons.size() != 1:
		print("FAIL: Cannon was not placed successfully!")
		quit(1)
		return
		
	var c = grid.active_cannons[0]
	print("Cannon placed successfully at: ", c.pos, " with orientation: ", c.orientation)
	
	# ----------------------------------------------------
	# Test Case 1: Powered Cannon (Electricity) shoots rapid Fireballs if no pipe/materials.
	# ----------------------------------------------------
	print("\n--- Test Case 1: Powered Cannon (No Pipe/No Materials) ---")
	grid.active_projectiles.clear()
	# Power the cannon by adding its anchor index to active_battery_indices
	var power_idx = (c.pos.y) * grid.grid_width + (c.pos.x)
	grid.active_battery_indices.append(power_idx)
	
	# Reset cooldown
	c.cooldown = 0.0
	
	# Run simulation tick
	grid._simulate_cannons(0.1)
	
	# Cooldown should be set to 0.06s (stream mode rapid-fire)
	print("Cannon Powered state: ", grid._is_cannon_powered(c))
	print("Cannon cooldown: ", c.cooldown)
	if c.cooldown != 0.06:
		print("FAIL: Cooldown was not set to 0.06s for powered stream mode!")
		quit(1)
		return
		
	# Projectiles check
	if grid.active_projectiles.size() != 1:
		print("FAIL: Expected 1 projectile, found: ", grid.active_projectiles.size())
		quit(1)
		return
		
	var proj = grid.active_projectiles[0]
	print("Launched projectile type: ", proj.type, " gravity: ", proj.get("gravity"))
	if proj.type != "fireball" or proj.get("gravity") != 0.0:
		print("FAIL: Expected fireball with gravity 0.0!")
		quit(1)
		return
	print("PASS: Test Case 1 succeeded!")

	# ----------------------------------------------------
	# Test Case 2: Powered Cannon connected to pipe with materials shoots rapid blocks.
	# ----------------------------------------------------
	print("\n--- Test Case 2: Powered Cannon + Pipe with Materials ---")
	grid.active_projectiles.clear()
	grid.active_pipes.clear()
	
	# Setup pipe connected to the cannon endpoint.
	# The endpoint offset for cannon is (c.pos.x + 2, c.pos.y + 2) in grid logic.
	# Let's create a pipe with 1 element at the endpoint.
	var pipe_path = [Vector2i(c.pos.x + 2, c.pos.y + 2)]
	var pipe_elems = [[{"mat": 1}]] # mat 1 = concrete/stone block
	
	grid.active_pipes.append({
		"path": pipe_path,
		"elements": pipe_elems,
		"flow_dir": 0
	})
	
	# Reset cooldown
	c.cooldown = 0.0
	
	# Run simulation tick
	grid._simulate_cannons(0.1)
	
	# Cooldown should be 0.06s
	print("Cannon cooldown after firing block: ", c.cooldown)
	if c.cooldown != 0.06:
		print("FAIL: Cooldown was not set to 0.06s for powered stream mode!")
		quit(1)
		return
		
	# The pipe element should have been consumed
	var p = grid.active_pipes[0]
	print("Pipe elements after firing: ", p.elements[0])
	if p.elements[0].size() != 0:
		print("FAIL: Pipe element was not consumed!")
		quit(1)
		return
		
	# Projectiles check
	if grid.active_projectiles.size() != 1:
		print("FAIL: Expected 1 projectile, found: ", grid.active_projectiles.size())
		quit(1)
		return
		
	proj = grid.active_projectiles[0]
	print("Launched projectile type: ", proj.type, " block_material: ", proj.get("block_material"), " gravity: ", proj.get("gravity"))
	if proj.type != "magic_lifted" or proj.get("block_material") != 1 or proj.get("gravity") != 120.0:
		print("FAIL: Expected magic_lifted block of material 1 with gravity 120.0!")
		quit(1)
		return
	print("PASS: Test Case 2 succeeded!")

	# ----------------------------------------------------
	# Test Case 3: Unpowered Cannon connected to pipe with materials shoots slow blocks.
	# ----------------------------------------------------
	print("\n--- Test Case 3: Unpowered Cannon + Pipe with Materials ---")
	grid.active_projectiles.clear()
	grid.active_pipes.clear()
	grid.active_battery_indices.clear()
	
	# Add pipe with concrete material again
	grid.active_pipes.append({
		"path": pipe_path,
		"elements": [[{"mat": 2}]], # mat 2
		"flow_dir": 0
	})
	
	# Reset cooldown
	c.cooldown = 0.0
	
	# Run simulation tick
	grid._simulate_cannons(0.1)
	
	# Cooldown should be 1.0s (normal unpowered cooldown)
	print("Cannon Powered state: ", grid._is_cannon_powered(c))
	print("Cannon cooldown after unpowered firing: ", c.cooldown)
	if c.cooldown != 1.0:
		print("FAIL: Cooldown was not set to 1.0s for unpowered mode!")
		quit(1)
		return
		
	# Projectiles check
	if grid.active_projectiles.size() != 1:
		print("FAIL: Expected 1 projectile, found: ", grid.active_projectiles.size())
		quit(1)
		return
		
	proj = grid.active_projectiles[0]
	print("Launched projectile type: ", proj.type, " block_material: ", proj.get("block_material"), " gravity: ", proj.get("gravity"))
	if proj.type != "magic_lifted" or proj.get("block_material") != 2 or proj.get("gravity") != 120.0:
		print("FAIL: Expected magic_lifted block of material 2 with gravity 120.0!")
		quit(1)
		return
	print("PASS: Test Case 3 succeeded!")
	
	print("\n==================================================")
	print(" ALL INTEGRATION TESTS PASSED SUCCESSFULLY! ")
	print("==================================================")
	quit(0)
