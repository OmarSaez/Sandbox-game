filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

for i, line in enumerate(text.split('\n')):
    # remove comments to avoid false positives
    line = line.split('#')[0]
    if line.count('(') != line.count(')'):
        if '"' not in line and "'" not in line:
            print(f'Line {i+1}: unmatched parens: {line}')
