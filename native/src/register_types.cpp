#include "windows_archive_lease.hpp"

#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_solo_rxjh_native(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		ClassDB::register_class<WindowsArchiveLease>();
	}
}

void uninitialize_solo_rxjh_native(ModuleInitializationLevel) {
}

extern "C" {

GDExtensionBool GDE_EXPORT solorxjh_native_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_object(p_get_proc_address, p_library, r_initialization);
	init_object.register_initializer(initialize_solo_rxjh_native);
	init_object.register_terminator(uninitialize_solo_rxjh_native);
	init_object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}

} // extern "C"
