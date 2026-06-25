tool
extends EditorPlugin

func get_plugin_name() -> String:
	return "Virtual Joystick"

func _enter_tree() -> void:
	add_custom_type("VirtualJoystick", "Control",
		preload("virtual_joystick.gd"), null)

func _exit_tree() -> void:
	remove_custom_type("VirtualJoystick")
