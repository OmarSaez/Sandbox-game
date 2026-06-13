import re

path = 'c:/Users/omaez/OneDrive/Escritorio/Proyecto juego/Sandbox-game/sandbox/scripts/sandbox/sandbox_grid.gd'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

bad_block_1 = """				else:
					var side = _find_pipe_x2_endpoint_opening_side(p, i)
					var _ejection_dir = Vector2i(0, 0)
					if side == "bottom" or side == "horizontal": _ejection_dir = Vector2i(0, 1)
					elif side == "top": _ejection_dir = Vector2i(0, -1)
					elif side == "left": _ejection_dir = Vector2i(-1, 0)
					elif side == "right": _ejection_dir = Vector2i(1, 0)
					next_pt = pt"""

good_block = """				else:
					next_pt = pt"""

content = content.replace(bad_block_1, good_block)

# And fix the warnings about integer division
content = content.replace("var cy = count / 4", "var cy = int(count / 4)")
content = content.replace("var cy = count / 8", "var cy = int(count / 8)")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
