extends SceneTree
## Renders a small world under high() and for-phone low() at phone size into screenshots/.

func _initialize() -> void:
	root.size = Vector2i(720, 1280)
	var w := root.get_window()
	w.size = Vector2i(720, 1280)
	var holder := Node3D.new()
	root.add_child(holder)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.position = Vector3(0, 3, 7)
	cam.look_at(Vector3.ZERO)
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20)
	floor_m.mesh = pm
	holder.add_child(floor_m)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(0, 0.5, 0)
	holder.add_child(box)
	var doc := DotLightDocument.new()
	await process_frame
	var name := "low" if OS.get_cmdline_user_args().has("low") else "high"
	var prof: DotLightProfile = DotLightProfile.low() if name == "low" else DotLightProfile.high()
	DotLightRig.apply(holder, doc, prof)
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png("res://screenshots/profile_%s.png" % name)
	quit()
