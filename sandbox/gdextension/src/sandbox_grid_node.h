#ifndef SANDBOX_GRID_NODE_H
#define SANDBOX_GRID_NODE_H

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class SandboxGridNode : public Node2D {
	GDCLASS(SandboxGridNode, Node2D)

private:
	// Tags mapping from GDScript SandboxMaterial
	enum Tags : uint64_t {
		NONE = 0,
		SOLID = 1ULL << 0,
		LIQUID = 1ULL << 1,
		GAS = 1ULL << 2,
		POWDER = 1ULL << 3,
		FLAMMABLE = 1ULL << 4,
		INCENDIARY = 1ULL << 5,
		EXPLOSIVE = 1ULL << 6,
		ELECTRICITY = 1ULL << 7,
		CONDUCTOR = 1ULL << 8,
		ELECTRIC_ACTIVATED = 1ULL << 9,
		GRAV_NORMAL = 1ULL << 10,
		GRAV_SLOW = 1ULL << 11,
		GRAV_UP = 1ULL << 12,
		GRAV_STATIC = 1ULL << 13,
		ACID = 1ULL << 14,
		ANTI_ACID = 1ULL << 15,
		BURN_SMOKE = 1ULL << 16,
		BURN_COAL = 1ULL << 17,
		BURN_NONE = 1ULL << 18,
		ANTI_EXPLOSIVE = 1ULL << 19,
		PLANT = 1ULL << 20,
		EXP_ELECTRIC = 1ULL << 21,
		FERTILE = 1ULL << 22,
		NPC = 1ULL << 23,
		VOLATILE = 1ULL << 24,
		TEXTURE_DOUBLE = 1ULL << 25,
		TEXTURE_TRIPLE = 1ULL << 26,
		MIX_LOW = 1ULL << 27,
		MIX_MEDIUM = 1ULL << 28,
		MIX_HIGH = 1ULL << 29,
		MUSIC = 1ULL << 30,
		EXP_ACID = 1ULL << 31,
		EXP_WATER = 1ULL << 32,
		EXP_LAVA = 1ULL << 33,
		EXP_NPC = 1ULL << 34,
		EXP_LIFE = 1ULL << 35,
		VIRUS = 1ULL << 41,
		RADIOACTIVE = 1ULL << 42,
		INVINCIBLE = 1ULL << 43,
		VORTEX = 1ULL << 44,
		EXP_GAS = 1ULL << 45,
		EXP_QUAKE = 1ULL << 46,
		EXP_PINATA = 1ULL << 47,
		REPEL = 1ULL << 48
	};

protected:
	static void _bind_methods();

public:
	SandboxGridNode();
	~SandboxGridNode();

	Dictionary process_physics(Dictionary state, int width, int height, int frame_count);
	Dictionary process_electricity(Dictionary state, int width, int height, int frame_count);
	Dictionary map_grid_data(Dictionary state, Dictionary dict, int grid_width, int grid_height);
	PackedInt32Array get_special_source_indices(PackedInt32Array cells);
};

}

#endif // SANDBOX_GRID_NODE_H
