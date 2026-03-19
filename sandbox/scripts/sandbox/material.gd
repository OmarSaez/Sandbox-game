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
}

@export var name: String = "Material"
@export var color: Color = Color.WHITE
@export var tags: int = Tags.NONE

static func has_tag(material_tags: int, tag: int) -> bool:
	return (material_tags & tag) != 0
