import sys

path = 'c:/Users/omaez/OneDrive/Escritorio/Proyecto juego/Sandbox-game/sandbox/scripts/sandbox/sandbox_grid.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix flow_dir in reconstruct
content = content.replace('''	for key in dict:
		var pos = dict[key]
		
		# Identify normal pipe''', '''	for key in dict:
		var pos = dict[key]
		var flow_dir = 0
		if p_data != null:
			for op in p_data:
				var path = op.get("path", [])
				if path.size() > 0 and path[0] == pos:
					flow_dir = op.get("flow_dir", 0)
					break
		
		# Identify normal pipe''')

content = content.replace('''			"elements": elements,
			"flow_dir": 0
		}
		active_pipes.append(p)''', '''			"elements": elements,
			"flow_dir": flow_dir
		}
		active_pipes.append(p)''')

content = content.replace('''	for key in dict_x2:
		var pos = dict_x2[key]
		
		# Identify x2 pipe''', '''	for key in dict_x2:
		var pos = dict_x2[key]
		var flow_dir = 0
		if px2_data != null:
			for op in px2_data:
				var path = op.get("path", [])
				if path.size() > 0 and path[0] == pos:
					flow_dir = op.get("flow_dir", 0)
					break
		
		# Identify x2 pipe''')

content = content.replace('''			"elements": elements,
			"flow_dir": 0
		}
		active_pipes_x2.append(p)''', '''			"elements": elements,
			"flow_dir": flow_dir
		}
		active_pipes_x2.append(p)''')


# 2. Fix _physics_process to call the visual updates
content = content.replace('''		_simulate_cannons(delta)
		_simulate_pipes(delta)
		
		_step_simulation()''', '''		_simulate_cannons(delta)
		_simulate_pipes(delta)
		
		# Pipe Structure Pass (BEFORE physics)
		for p in active_pipes:
			_update_pipe_visuals(p, 0)
		for p in active_pipes_x2:
			_update_pipe_x2_visuals(p, 0)
		
		_step_simulation()
		
		# Pipe Elements Pass (AFTER physics)
		for p in active_pipes:
			_update_pipe_visuals(p, 1)
		for p in active_pipes_x2:
			_update_pipe_x2_visuals(p, 1)''')


# 3. Remove the visual updates from _simulate_pipes
content = content.replace('''	# Draw/animate visuals every frame (60 Hz)
	for p in active_pipes:
		_update_pipe_visuals(p)
	for p in active_pipes_x2:
		_update_pipe_x2_visuals(p)''', '''	# (Visuals are now handled in _physics_process to run at 60 FPS)''')


with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
