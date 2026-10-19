@tool
extends EditorPlugin

## Editor entry point for dot-lighting. Registers inspector types, and with
## `--dot-bake-lightmaps=` on the command line bakes a directory of bake scenes and quits
## ([DotLightBake]); without it, nothing else. A game that bakes keeps it enabled in
## project.godot: the editor reads [editor_plugins] from there alone, not from override.cfg.
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


## `godot --editor --path <project> -- --dot-bake-lightmaps=res://<dir>` bakes every scene in
## that directory and quits (editor/dot_light_bake_runner.gd; bake/bake.sh runs it).
const BAKE_ARG := "--dot-bake-lightmaps="

var _baker: Node = null


func _enter_tree() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(BAKE_ARG):
			_baker = (load("res://addons/dot_lighting/editor/dot_light_bake_runner.gd") as GDScript).new()
			_baker.set("directory", arg.trim_prefix(BAKE_ARG))
			add_child(_baker)

	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	if _baker != null:
		_baker.queue_free()
		_baker = null

	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
