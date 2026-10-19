@tool
extends Node

## Bakes every bake scene in one directory, unattended, then quits the editor. Started by
## dot-lighting's editor plugin when the editor is launched with
## `-- --dot-bake-lightmaps=res://<dir>` (`bake/bake.sh` does that); inert otherwise.
##
## [b]Why the editor, and why it is driven through its own button.[/b] `LightmapGI.bake` is not
## bound for scripts in 4.7: the only way in is the editor's "Bake Lightmaps" action, which asks
## for a file and then bakes on the rendering device (Forward+ or Mobile; the Compatibility
## renderer cannot bake, though it draws the result). So this opens each scene, selects its
## [LightmapGI], presses the button, answers the file dialog with `<scene>.lmbake`, and when the
## light data appears turns it into the shipped file ([method DotLightBake.store]). The press
## and the answer both run synchronously; a bake that fails leaves no light data and is reported.
##
## Every outcome is one stdout line, `DOT_BAKE ok <scene> <ms> <bytes> <out>` or
## `DOT_BAKE fail <scene> <why>`, which bake.sh reads; the editor exits 0 only if all baked.

const BUTTON_TEXT := "Bake Lightmaps"

var directory: String = ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# The editor's first frames: the filesystem scan and the main screen.
	await get_tree().create_timer(3.0).timeout
	var failed := 0
	var scenes: PackedStringArray = []

	for file in DirAccess.get_files_at(directory):
		if file.get_extension() == "tscn":
			scenes.append(directory.path_join(file))

	print("DOT_BAKE start %d scenes in %s" % [scenes.size(), directory])

	for scene in scenes:
		var why := await _bake(scene)
		if why != "":
			failed += 1
			print("DOT_BAKE fail %s %s" % [scene, why])

	print("DOT_BAKE end %d of %d baked" % [scenes.size() - failed, scenes.size()])
	get_tree().quit(1 if failed > 0 else 0)


func _bake(scene: String) -> String:
	EditorInterface.open_scene_from_path(scene)
	await get_tree().create_timer(1.0).timeout
	var root := EditorInterface.get_edited_scene_root() as Node3D

	if root == null or root.scene_file_path != scene:
		return "did not open"

	var gi := root.get_node_or_null(NodePath(String(DotLightBake.NODE_NAME))) as LightmapGI

	if gi == null:
		return "has no %s" % DotLightBake.NODE_NAME

	gi.light_data = null
	EditorInterface.edit_node(gi)
	await get_tree().process_frame
	var button := _find_button(EditorInterface.get_base_control())

	if button == null:
		return "no '%s' button (an editor in another language?)" % BUTTON_TEXT

	var started := Time.get_ticks_msec()
	button.pressed.emit()
	await get_tree().process_frame
	var dialog := _find_dialog(get_tree().root)

	if dialog == null and gi.light_data == null:
		return "the bake asked for no file and made nothing"

	if dialog != null:
		var target := scene.get_basename() + ".lmbake"
		dialog.hide()
		dialog.file_selected.emit(target)

	if gi.light_data == null:
		return "the bake made no light data (see the editor's errors above)"

	var ms := Time.get_ticks_msec() - started
	var stored := DotLightBake.store(gi.light_data, str(root.get_meta(DotLightBake.META_FINGERPRINT, "")),
		str(root.get_meta(DotLightBake.META_OUT, "")))

	if not stored.ok:
		return "baked but not stored: %s" % stored.error.message

	var info: Dictionary = stored.value
	print("DOT_BAKE ok %s %d %d %s %dx%dx%d" % [scene, ms, int(info["bytes"]), info["path"],
		(info["size"] as Vector2i).x, (info["size"] as Vector2i).y, int(info["layers"])])
	return ""


func _find_button(node: Node) -> Button:
	if node is Button and (node as Button).text == BUTTON_TEXT:
		return node as Button

	for child in node.get_children():
		var found := _find_button(child)
		if found != null:
			return found

	return null


func _find_dialog(node: Node) -> EditorFileDialog:
	if node is EditorFileDialog and (node as Window).visible:
		return node as EditorFileDialog

	for child in node.get_children():
		var found := _find_dialog(child)
		if found != null:
			return found

	return null
