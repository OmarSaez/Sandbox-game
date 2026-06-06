import sys, re

filepath = 'sandbox/scripts/sandbox/sandbox_grid.gd'
with open(filepath, 'r', encoding='utf-8') as f:
    text = f.read()

def insert_before(text, search_str, insert_str):
    pattern = r'(^[ \t]*)(' + re.escape(search_str) + r')'
    def repl(m):
        return m.group(1) + insert_str + '\n' + m.group(1) + m.group(2)
    return re.sub(pattern, repl, text, flags=re.MULTILINE)

# 1. _old_id_c warnings
text = insert_before(text, 'var _old_id_c = cells[idx] & 0xFFFF', '@warning_ignore("confusable_local_declaration")')

# 2. head_pix warnings
text = insert_before(text, 'var head_pix = _get_piston_head_pixels(p, ext_val)', '@warning_ignore("confusable_local_declaration")')
text = insert_before(text, 'var head_pix = _get_piston_head_pixels(p, 0)', '@warning_ignore("confusable_local_declaration")')

# Deduplicate any double warning ignores
text = text.replace('@warning_ignore("confusable_local_declaration")\n\t\t\t@warning_ignore("confusable_local_declaration")', '@warning_ignore("confusable_local_declaration")')
text = text.replace('@warning_ignore("confusable_local_declaration")\n\t\t@warning_ignore("confusable_local_declaration")', '@warning_ignore("confusable_local_declaration")')
text = text.replace('@warning_ignore("confusable_local_declaration")\n\t\t\t\t\t\t@warning_ignore("confusable_local_declaration")', '@warning_ignore("confusable_local_declaration")')
text = text.replace('@warning_ignore("confusable_local_declaration")\n\t\t\t\t@warning_ignore("confusable_local_declaration")', '@warning_ignore("confusable_local_declaration")')

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(text)
print('Fixed warning ignores')
