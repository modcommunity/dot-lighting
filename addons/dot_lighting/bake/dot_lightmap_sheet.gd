class_name DotLightmapSheet
extends RefCounted

## The second UV set a baked lightmap needs, for a mesh a game builds in code out of flat
## quads (the faces of boxes). One sheet per mesh: add every face, then [method commit] it into
## a [SurfaceTool] with its UV2, and set [member size] as the mesh's `lightmap_size_hint`.
##
## [codeblock]
## var sheet := DotLightmapSheet.new()
## for box in boxes:
##     for face in faces_of(box):
##         sheet.face(face.a, face.b, face.c, face.d, face.normal)
## var tool := SurfaceTool.new()
## tool.begin(Mesh.PRIMITIVE_TRIANGLES)
## sheet.commit(tool)
## var mesh := tool.commit()
## mesh.lightmap_size_hint = sheet.size
## [/codeblock]
##
## [b]Deterministic, and that is the whole reason this exists.[/b] A lightmap is a picture in
## this mesh's UV2 space, baked once offline and loaded by every client. The client rebuilds the
## mesh from the map's document, so it must come out with exactly the UV2 the bake saw, or the
## light lands on the wrong faces. The engine's own unwrapper (`ArrayMesh.lightmap_unwrap`) is
## editor-only (it is not in an export template) and gives no promise of the same layout twice;
## this is plain arithmetic on the faces in the order they were added, the same on every
## machine. Change the layout and bump [constant VERSION]: every bake's fingerprint includes it,
## so an old bake is refused as stale instead of drawn on the wrong faces.
##
## [b]A face is a parallelogram given by its corners in order[/b]: `a` to `b` is one edge (its
## height on the sheet), `a` to `d` the other (its width); `c` is the corner opposite `a`. The
## two triangles are written `a, c, b` and `a, d, c`, the winding game-zombie-zone's and
## game-arena's box builders already emit (Godot's front face is clockwise seen from outside).
##
## [b]Packed on shelves, tallest first, with [member padding] texels round every face[/b], so a
## filtered sample at a face's edge reads its own light and not the neighbour's. A thin face (a
## kerb's side, a wall's top) still gets at least one texel.

## Bump when the layout changes (see the class notes).
const VERSION := 1

## Metres of surface one lightmap texel covers. 0.25 is four texels a metre: a lamp's pool and
## the dark in a corner both read, and a school stays under a megabyte. LightmapGI's own
## `texel_scale` multiplies this at bake time without touching the UVs.
var texel: float = 0.25

## Empty texels round each face.
var padding: int = 2

## The sheet's size in texels after [method commit] (and [method pack]): the mesh's
## `lightmap_size_hint`.
var size: Vector2i = Vector2i.ZERO

# [a, b, c, d, normal, w, h] per face, in the order added.
var _faces: Array = []
# Top-left texel of each face's rectangle (inside the padding), filled by pack().
var _at: Array[Vector2i] = []


func face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var w := maxi(1, ceili(a.distance_to(d) / texel - 0.001))
	var h := maxi(1, ceili(a.distance_to(b) / texel - 0.001))
	_faces.append([a, b, c, d, normal, w, h])


func face_count() -> int:
	return _faces.size()


## Lays the faces out and sets [member size]. [method commit] calls it; a caller that only wants
## the size can call it alone.
func pack() -> Vector2i:
	_at.clear()
	_at.resize(_faces.size())

	if _faces.is_empty():
		size = Vector2i.ZERO
		return size

	var order: Array[int] = []
	var area := 0
	var widest := 0

	for i in _faces.size():
		order.append(i)
		var w: int = int(_faces[i][5]) + padding * 2
		var h: int = int(_faces[i][6]) + padding * 2
		area += w * h
		widest = maxi(widest, w)

	# Tallest first, the order added breaking ties: sort_custom is not stable, and a layout that
	# depends on the sort's internals is not one two machines agree on.
	order.sort_custom(func(x: int, y: int) -> bool:
		var hx: int = _faces[x][6]
		var hy: int = _faces[y][6]
		return hx > hy if hx != hy else x < y)

	var width := maxi(widest, ceili(sqrt(float(area) * 1.15)))
	var x := 0
	var y := 0
	var shelf := 0

	for i in order:
		var w: int = int(_faces[i][5]) + padding * 2
		var h: int = int(_faces[i][6]) + padding * 2

		if x + w > width:
			x = 0
			y += shelf
			shelf = 0

		_at[i] = Vector2i(x + padding, y + padding)
		x += w
		shelf = maxi(shelf, h)

	size = Vector2i(width, y + shelf)
	return size


## Writes every face into [param tool] (begun as triangles) with its normal and UV2.
func commit(tool: SurfaceTool) -> void:
	pack()

	if _faces.is_empty():
		return

	var scale := Vector2(1.0 / float(size.x), 1.0 / float(size.y))

	for i in _faces.size():
		var f: Array = _faces[i]
		var at := Vector2(_at[i])
		var w := float(f[5])
		var h := float(f[6])
		# a at the rectangle's top left, d along its width, b down its height.
		var uv_a := at * scale
		var uv_b := Vector2(at.x, at.y + h) * scale
		var uv_c := Vector2(at.x + w, at.y + h) * scale
		var uv_d := Vector2(at.x + w, at.y) * scale
		var corners := [[f[0], uv_a], [f[2], uv_c], [f[1], uv_b], [f[0], uv_a], [f[3], uv_d], [f[2], uv_c]]

		for corner: Array in corners:
			tool.set_normal(f[4])
			tool.set_uv2(corner[1])
			tool.add_vertex(corner[0])


func describe() -> String:
	return "DotLightmapSheet(%d faces, %dx%d texels at %.2f m)" % [_faces.size(), size.x, size.y, texel]
