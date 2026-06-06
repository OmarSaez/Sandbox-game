import re
filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

lines = text.split('\n')
for i in range(len(lines)):
    if '@warning_ignore("integer_division")' in lines[i] and not lines[i].strip().startswith('#'):
        if i + 1 < len(lines):
            next_line = lines[i+1]
            leading_ws = next_line[:len(next_line) - len(next_line.lstrip())]
            lines[i] = leading_ws + '@warning_ignore("integer_division")'

with open(filepath, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
