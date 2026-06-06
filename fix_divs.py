import sys

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i in range(len(lines)):
    line = lines[i]
    if ' / ' in line and 'float' not in line and '.0' not in line and 'Vector2' not in line and not line.strip().startswith('#'):
        if 'Engine.get_frames_drawn() / 15' in line:
            lines[i] = line.replace('Engine.get_frames_drawn() / 15', 'int(Engine.get_frames_drawn() / 15.0)')
        elif ' / snap' in line:
            lines[i] = line.replace(' / snap', ' / float(snap)')
            lines[i] = lines[i].replace('var cx =', 'var cx = int').replace('var cy =', 'var cy = int').replace('var target_cx =', 'var target_cx = int').replace('var target_cy =', 'var target_cy = int')
            lines[i] = lines[i].replace('intprev', 'int(prev').replace('intgx', 'int(gx').replace('intgy', 'int(gy')
            if 'int(' in lines[i]:
                lines[i] = lines[i].rstrip() + ')\n'
        elif ' / 8' in line:
            lines[i] = line.replace(' / 8', ' / 8.0')
            if 'var b_idx = ' in lines[i]:
                lines[i] = lines[i].replace('var b_idx = ', 'var b_idx = int(').rstrip() + ')\n'
        elif ' / 4' in line:
            lines[i] = line.replace(' / 4', ' / 4.0')
        elif ' / 2' in line:
            lines[i] = line.replace(' / 2', ' / 2.0')
        elif ' / grid_width' in line:
            lines[i] = line.replace(' / grid_width', ' / float(grid_width)')
            if 'var old_y = ' in lines[i]:
                lines[i] = lines[i].replace('var old_y = ', 'var old_y = int(').rstrip() + ')\n'
            elif 'var gy =' in lines[i]:
                lines[i] = lines[i].replace('var gy =', 'var gy = int(').rstrip() + ')\n'
        elif ' / old_w' in line:
            lines[i] = line.replace(' / old_w', ' / float(old_w)')
            if 'var old_y =' in lines[i]:
                lines[i] = lines[i].replace('var old_y =', 'var old_y = int(').rstrip() + ')\n'
        elif ' / 16' in line:
            lines[i] = line.replace(' / 16', ' / 16.0')
            if 'var inst =' in lines[i]:
                lines[i] = lines[i].replace('var inst =', 'var inst = int(').rstrip() + ')\n'
        elif ' / float(val)' in line:
            pass
        elif ' / 10' in line:
            lines[i] = line.replace(' / 10', ' / 10.0')

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)
