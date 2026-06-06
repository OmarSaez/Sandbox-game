#ifndef SANDBOX_REGISTER_TYPES_H
#define SANDBOX_REGISTER_TYPES_H

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void initialize_sandbox_module(ModuleInitializationLevel p_level);
void uninitialize_sandbox_module(ModuleInitializationLevel p_level);

#endif // SANDBOX_REGISTER_TYPES_H
