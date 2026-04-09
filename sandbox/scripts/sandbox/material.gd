extends Resource
class_name SandboxMaterial

enum Tags {
	NONE = 0,
	SOLID = 1 << 0,
	LIQUID = 1 << 1,
	GAS = 1 << 2,
	POWDER = 1 << 3,
	FLAMMABLE = 1 << 4,
	INCENDIARY = 1 << 5,
	EXPLOSIVE = 1 << 6,
	
	# Electricity
	ELECTRICITY = 1 << 7,
	CONDUCTOR = 1 << 8,
	ELECTRIC_ACTIVATED = 1 << 9,
	
	# Gravity behaviors
	GRAV_NORMAL = 1 << 10,
	GRAV_SLOW = 1 << 11,
	GRAV_UP = 1 << 12,
	GRAV_STATIC = 1 << 13,
	
	# Interactions
	ACID = 1 << 14,
	ANTI_ACID = 1 << 15,
	
	# Burn Products
	BURN_SMOKE = 1 << 16,
	BURN_COAL = 1 << 17,
	BURN_NONE = 1 << 18,
	ANTI_EXPLOSIVE = 1 << 19,
	
	# Plant life
	PLANT = 1 << 20,
	EXP_ELECTRIC = 1 << 21,  # Produces sparks on explosion
	FERTILE = 1 << 22,
	
	# NPC system
	NPC = 1 << 23,
	
	# Volatile/Projectile behavior
	VOLATILE = 1 << 24,
	
	# --- SCALABLE TEXTURING SYSTEM ---
	TEXTURE_DOUBLE = 1 << 25, # Material uses 2 colors
	TEXTURE_TRIPLE = 1 << 26, # Material uses 3 colors
	MIX_LOW = 1 << 27,        # ~15% secondary color
	MIX_MEDIUM = 1 << 28,     # ~35% secondary color
	MIX_HIGH = 1 << 29,       # ~50% secondary color
	
	# Music system
	MUSIC = 1 << 30,
	EXP_ACID = 1 << 31,       # Produces acid drops on explosion
	
	# --- EXTENDED TAGS (64-bit range) ---
	EXP_WATER = 1 << 32,      # Produces water drops on explosion
	EXP_LAVA = 1 << 33,       # Produces lava drops on explosion
	EXP_NPC = 1 << 34,        # Produces random NPCs on explosion
	EXP_LIFE = 1 << 35,       # Produces plants/life on explosion
	
	# --- EXPLOSION TEAM FLAGS ---
	EXP_TEAM_RED = 1 << 36,
	EXP_TEAM_BLUE = 1 << 37,
	EXP_TEAM_GREEN = 1 << 38,
	EXP_TEAM_YELLOW = 1 << 39,
	EXP_TEAM_MIXED = 1 << 40,
	
	# Experimental Laboratory (New)
	VIRUS = 1 << 41,
	RADIOACTIVE = 1 << 42,
	INVINCIBLE = 1 << 43,
	VORTEX = 1 << 44
}

@export var name: String = "Material"
@export var color: Color = Color.WHITE
@export var tags: int = Tags.NONE

static func has_tag(material_tags: int, tag: int) -> bool:
	return (material_tags & tag) != 0
