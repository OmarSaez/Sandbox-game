filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

import re

for line in text.split('\n'):
    if '@warning_ignore("confusable_local_declaration")' in line:
        print('Ignored: ', line)
