import sys

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

clean_lines = []
for line in lines:
    if '@warning_ignore("integer_division")' not in line:
        clean_lines.append(line)

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(clean_lines)
print('Removed all warning_ignores')
