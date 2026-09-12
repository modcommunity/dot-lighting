@tool
extends EditorPlugin

## Editor entry point for dot-lighting. Registers inspector types only.
##
## No autoloads. A lighting rig belongs to a world, and a process that runs a server and a
## client — or two worlds while one is loading over the other — needs two of them; a global
## would make that the one arrangement this family cannot have.

const _ICON := "res://addons/dot_lighting/icon_placeholder.svg"

const _TYPES := [
	[
		"DotLightZone",
		"Node3D",
		"res://addons/dot_lighting/runtime/dot_light_zone.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
