extends RefCounted
class_name SandboxFontHelper

## Utilidad centralizada de tipografía y fuentes seguras con soporte multi-plataforma y fallback para emojis.

static var _combined_font: FontVariation = null

## Retorna una fuente combinada segura con soporte de texto estándar y fallbacks para emojis/iconos.
## [param custom_emoji]: Fuente opcional especificada en el Inspector.
static func get_safe_font(custom_emoji: Font = null) -> Font:
	if not _combined_font:
		_combined_font = FontVariation.new()
		
		# 1. FUENTE BASE (Texto estándar del sistema)
		var base_font = SystemFont.new()
		base_font.font_names = PackedStringArray(["sans-serif", "arial"])
		_combined_font.base_font = base_font
		
		# 2. FUENTE DE ICONOS Y EMOJIS (Búsqueda en assets locales)
		var emoji_f: Font = custom_emoji
		if not emoji_f:
			var paths = [
				"res://assets/fonts/Twemoji.Mozilla.ttf",
				"res://assets/fonts/Twemoji.ttf",
				"res://assets/fonts/NotoColorEmoji.ttf",
				"res://assets/fonts/FluentEmoji.ttf"
			]
			for p in paths:
				if ResourceLoader.exists(p):
					emoji_f = load(p)
					break
		
		# 3. ÚLTIMO RECURSO: Fuentes del sistema operativo móvil/escritorio
		if not emoji_f:
			emoji_f = SystemFont.new()
			emoji_f.font_names = PackedStringArray(["Emoji", "ColorEmoji", "Noto Color Emoji"])
			emoji_f.multichannel_signed_distance_field = false
			
		if emoji_f:
			_combined_font.set_fallbacks([emoji_f])
			
	return _combined_font
