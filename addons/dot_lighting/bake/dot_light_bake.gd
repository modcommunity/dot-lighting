class_name DotLightBake
extends RefCounted

## Baked light for a world a game builds in code: the offline half writes one file per map, the
## runtime half finds it, checks it was baked from this geometry, and lays it over the world.
##
## A world generated at load does not exist in the editor, so the offline half builds it, saves
## the drawn half as a scene with a [LightmapGI] ([method prepare]), the editor bakes it
## (`bake/bake.sh`), and [method store] writes ONE self-contained resource for the pack.
##
## At runtime the client rebuilds the same meshes under the same node names, with the same UV2
## ([DotLightmapSheet]), and calls [method attach]. A file whose fingerprint disagrees is refused
## with a WARN and the live lights are used; no bake at all is the same fallback, said at DEBUG.
##
## [codeblock]
## var res := DotLightBake.attach(map_node, "res://lightmaps/%s.res" % id, my_fingerprint)
## if res.ok:
##     for lamp in my_lamps: lamp.light_bake_mode = Light3D.BAKE_STATIC   # baked, not drawn twice
## [/codeblock]
##
## One file, no import, no external reference: the editor's `.lmbake` points at an `.exr` that only
## becomes a (BPTC, maybe undecodable) texture on import, and a pack is never re-imported. [method store]
## embeds the EXR's pixels as RGB9E5, zstd-compressed. Never on a server: [method attach] refuses
## with `CODE_UNSUPPORTED`. `BAKE_STATIC` lights are baked whole; `BAKE_DYNAMIC` give bounce and stay live.

const CHANNEL := "dot.lighting.bake"

## Bump when what a bake means changes (its settings, which lights are baked): every
## fingerprint includes it, so old files are refused as stale rather than drawn wrong.
const VERSION := 2

## Where a bake scene says what it was built from and where its output goes.
const META_FINGERPRINT := &"dot_light_fingerprint"
const META_OUT := &"dot_light_out"
## Per-component hashes (name to sha256) beside the fingerprint, so a stale bake can say which part moved.
const META_COMPONENTS := &"dot_light_components"

## Top-level parts [method fingerprint] leaves out: the sky and fog are drawn live, props and
## dynamic nodes move. A bake only depends on static lights and static geometry.
const IGNORED_PARTS: Array[String] = ["environment", "props", "dynamic", "sky", "fog", "weather", "ambient"]

## Floats are rounded to this step before hashing, so a re-saved document does not change it.
const FLOAT_STEP := 0.001

## The [LightmapGI] node's name, the same in the bake scene and at runtime: the lightmap names
## its meshes by path from it.
const NODE_NAME := &"LightmapGI"

## The atlas page size. A browser is the smallest target: 2048 is safe on every WebGL 2 device.
const MAX_TEXTURE_SIZE := 2048


## A stable hash of [param parts] (anything JSON can hold) together with this file's and
## [DotLightmapSheet]'s versions. The bake and the runtime compute it from the same document.
## A Dictionary's [constant IGNORED_PARTS] are dropped, floats rounded and Vectors flattened.
static func fingerprint(parts: Variant) -> String:
	var text := JSON.stringify([VERSION, DotLightmapSheet.VERSION, _canonical(_relevant(parts))], "", true, true)
	return text.sha256_text()


## One sha256 per top-level key of [param parts] (after the same dropping and rounding as
## [method fingerprint]); stored with a bake to name what changed.
static func components(parts: Dictionary) -> Dictionary:
	var out := {}
	var kept: Dictionary = _relevant(parts)
	for key in kept:
		out[str(key)] = JSON.stringify(_canonical(kept[key]), "", true, true).sha256_text()
	return out


## The first component (sorted by name) that differs between two [method components] results,
## or "" when they agree.
static func first_difference(baked: Dictionary, now: Dictionary) -> String:
	var names := {}
	for key in baked:
		names[str(key)] = true
	for key in now:
		names[str(key)] = true
	var sorted := names.keys()
	sorted.sort()
	for key in sorted:
		if baked.get(key, "") != now.get(key, ""):
			return str(key)
	return ""


## Fingerprint parts for a scene under [param root]: static lights and static meshes (UV2 hash)
## in a stable order. Unbaked nodes (dynamic lights, props, non-static GI meshes) are left out,
## so adding them leaves a bake valid.
static func scan(root: Node3D) -> Dictionary:
	var lights: Array = []
	var meshes: Array = []
	_scan_into(root, root, lights, meshes)
	lights.sort_custom(func(a, b): return a[0] < b[0])
	meshes.sort_custom(func(a, b): return a[0] < b[0])
	return {"lights": lights, "meshes": meshes}


static func _scan_into(root: Node3D, node: Node, lights: Array, meshes: Array) -> void:
	for child in node.get_children():
		if child is Light3D and child.light_bake_mode != Light3D.BAKE_DISABLED:
			var light := child as Light3D
			lights.append([str(root.get_path_to(light)), _relative(root, light),
				light.light_energy, light.light_color, int(light.light_bake_mode)])
		elif child is MeshInstance3D and child.gi_mode == GeometryInstance3D.GI_MODE_STATIC and child.mesh != null:
			var mi := child as MeshInstance3D
			var uv := PackedVector2Array()
			for surface in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(surface)
				if arrays.size() > Mesh.ARRAY_TEX_UV2 and arrays[Mesh.ARRAY_TEX_UV2] != null:
					uv.append_array(arrays[Mesh.ARRAY_TEX_UV2])
			meshes.append([str(root.get_path_to(mi)), _relative(root, mi),
				mi.mesh.get_surface_count(), _canonical(uv).hash()])
		_scan_into(root, child, lights, meshes)


## [param node]'s transform in [param root]'s space, from local transforms so it works outside a tree.
static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


static func _relevant(parts: Variant) -> Variant:
	if parts is Dictionary:
		var kept := {}
		for key in parts:
			if not IGNORED_PARTS.has(str(key)):
				kept[key] = parts[key]
		return kept
	return parts


## Rounded floats (a whole one becomes an int, so 1 and 1.0 agree), Vectors, Colors and
## Transforms as flat arrays, containers recursed.
static func _canonical(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var r := snappedf(v, FLOAT_STEP)
			return int(r) if is_equal_approx(r, roundf(r)) and absf(r) < 1e15 else r
		TYPE_ARRAY:
			return (v as Array).map(_canonical)
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return Array(v).map(_canonical)
		TYPE_DICTIONARY:
			var out := {}
			for key in v:
				out[str(key)] = _canonical(v[key])
			return out
		TYPE_VECTOR2:
			return [_canonical(v.x), _canonical(v.y)]
		TYPE_VECTOR3:
			return [_canonical(v.x), _canonical(v.y), _canonical(v.z)]
		TYPE_COLOR:
			return [_canonical(v.r), _canonical(v.g), _canonical(v.b), _canonical(v.a)]
		TYPE_TRANSFORM3D:
			return _canonical([v.basis.x, v.basis.y, v.basis.z, v.origin])
		_:
			return v


## Whether this process can draw a lightmap at all.
static func can_draw() -> bool:
	return DisplayServer.get_name() != "headless"


## Lays the bake at [param path] over [param host]'s world, if it was baked from
## [param expected]. Success carries the [LightmapGI] added as [param host]'s child; failure
## means nothing changed: `CODE_UNSUPPORTED` (nothing draws here), `CODE_IO` (no bake for
## this world, said at DEBUG), `CODE_INTEGRITY` (stale: baked from other geometry, a WARN) or
## `CODE_PARSE` (not a bake, a WARN).
## Pass [param expected_parts] (what [method fingerprint] was made from) and a stale WARN names the
## first component that differs.
static func attach(host: Node3D, path: String, expected: String, expected_parts: Dictionary = {}) -> DotResult:
	if not can_draw():
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "nothing draws a lightmap in a headless process")

	if not ResourceLoader.exists(path):
		DotLog.debug(CHANNEL, "no bake for this world; its live lights draw it", {"path": path})
		return DotResult.fail(DotError.CODE_IO, "no bake at %s" % path)

	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as LightmapGIData

	if data == null:
		DotLog.warn(CHANNEL, "a bake file is not a lightmap; the world is drawn with its live lights", {"path": path})
		return DotResult.fail(DotError.CODE_PARSE, "%s is not a LightmapGIData" % path)

	var baked_from := str(data.get_meta(META_FINGERPRINT, ""))

	if baked_from != expected:
		var baked_parts: Dictionary = data.get_meta(META_COMPONENTS, {})
		var which := first_difference(baked_parts, components(expected_parts)) if not expected_parts.is_empty() else ""
		if which == "" and baked_parts.is_empty():
			which = "(no components stored: baked by an older tool, or the version changed)"
		elif which == "" and not expected_parts.is_empty():
			which = "(version or settings, parts agree)"
		DotLog.warn(CHANNEL, "a bake is stale (its world changed since); the world is drawn with its live lights", {
			"path": path, "baked": baked_from.left(12), "now": expected.left(12), "first_difference": which,
		})
		return DotResult.fail(DotError.CODE_INTEGRITY, "%s was baked from different geometry" % path)

	var old := host.get_node_or_null(NodePath(String(NODE_NAME)))

	if old != null:
		host.remove_child(old)
		old.queue_free()

	var gi := LightmapGI.new()
	gi.name = NODE_NAME
	gi.light_data = data
	host.add_child(gi)
	DotLog.debug(CHANNEL, "baked light laid over a world", {"path": path, "meshes": data.get_user_count()})
	return DotResult.success(gi)


## Offline: adds the [LightmapGI] the editor bakes to [param root] (a bake scene) and records
## [param fp] and [param out_path] on [param root] for [method store]. [param settings] may set
## `quality` (a LightmapGI.BakeQuality), `bounces`, `texel_scale`, `probes` (a
## LightmapGI.GenerateProbes) and `denoise`.
## [param parts] (optional) are what [param fp] was made from; their [method components] ride along.
static func prepare(root: Node3D, fp: String, out_path: String, settings: Dictionary = {}, parts: Dictionary = {}) -> LightmapGI:
	var gi := LightmapGI.new()
	gi.name = NODE_NAME
	gi.quality = int(settings.get("quality", LightmapGI.BAKE_QUALITY_MEDIUM))
	gi.bounces = int(settings.get("bounces", 3))
	gi.texel_scale = float(settings.get("texel_scale", 1.0))
	gi.max_texture_size = MAX_TEXTURE_SIZE
	gi.generate_probes_subdiv = int(settings.get("probes", LightmapGI.GENERATE_PROBES_SUBDIV_4))
	gi.use_denoiser = bool(settings.get("denoise", true))
	gi.directional = false
	gi.environment_mode = LightmapGI.ENVIRONMENT_MODE_SCENE
	root.add_child(gi)
	root.set_meta(META_FINGERPRINT, fp)
	root.set_meta(META_OUT, out_path)
	if not parts.is_empty():
		root.set_meta(META_COMPONENTS, components(parts))
	return gi


## Offline, after the editor baked: [param data] (the editor's `.lmbake`) as one self-contained
## file at [param out_path], stamped with [param fp]. Needs a rendering device (the textures'
## pixels are read back from it), so it runs in the editor, never headless.
static func store(data: LightmapGIData, fp: String, out_path: String, parts_hashes: Dictionary = {}) -> DotResult:
	if data == null:
		return DotResult.fail(DotError.CODE_INVALID, "no light data to store")

	var textures := data.get_lightmap_textures()

	if textures.is_empty() or textures[0] == null:
		return DotResult.fail(DotError.CODE_INVALID, "the bake has no lightmap texture")

	var source := textures[0] as TextureLayered
	var layers := source.get_layers()
	var exr := source.resource_path

	# The EXR, not the imported texture: that one is BPTC, which a browser may not decode.
	var whole := Image.load_from_file(ProjectSettings.globalize_path(exr)) if exr.get_extension() == "exr" else null
	var images: Array[Image] = []

	if whole != null and not whole.is_empty():
		var height := whole.get_height() / layers
		for i in layers:
			images.append(whole.get_region(Rect2i(0, i * height, whole.get_width(), height)))
	else:
		for i in layers:
			var layer := source.get_layer_data(i)
			if layer == null:
				return DotResult.fail(DotError.CODE_IO, "could not read layer %d of %s" % [i, exr])
			if layer.is_compressed():
				layer.decompress()
			images.append(layer)

	for image in images:
		image.convert(Image.FORMAT_RGBE9995)

	var array := Texture2DArray.new()
	var made := array.create_from_images(images)

	if made != OK:
		return DotResult.failure(DotError.from_engine(made, "building the lightmap array"))

	var out := data.duplicate() as LightmapGIData
	out.set_lightmap_textures([array])
	out.set_meta(META_FINGERPRINT, fp)
	out.set_meta(META_COMPONENTS, parts_hashes)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var saved := ResourceSaver.save(out, out_path, ResourceSaver.FLAG_COMPRESS)

	if saved != OK:
		return DotResult.failure(DotError.from_engine(saved, "saving %s" % out_path))

	return DotResult.success({
		"path": out_path, "layers": layers, "size": images[0].get_size(),
		"bytes": FileAccess.get_file_as_bytes(out_path).size(),
	})
