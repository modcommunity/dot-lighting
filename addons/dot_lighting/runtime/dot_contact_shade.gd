class_name DotContactShade
extends RefCounted

## A contact shade for a world built of boxes: a soft dark band where a box meets the floor, a
## wall, the ceiling or another box, on both faces of the crease. Fake ambient occlusion for the
## Compatibility renderer (the client shell), which has no SSAO.
##
## [codeblock]
## var boxes: Array = []
## for b in my_map.boxes:
##     boxes.append(DotContactShade.box(b.transform, b.size))
## add_child(DotContactShade.node(boxes))          # one mesh, built once at load
## [/codeblock]
##
## [b]A darkening overlay, not vertex colours on the game's meshes.[/b] Every painted game
## builds its boxes its own way (SurfaceTool batches, BoxMesh nodes, MultiMeshes) with its own
## materials, and a box's face is two triangles: a vertex colour on a 10 m wall is a 10 m
## gradient, not a shade at its foot. So this builds its own thin bands, a few millimetres off
## each face, in one unshaded mesh: black at an alpha of (1 - the vertex's grey), which is the
## world behind it times that grey. Multiplying commutes, so the bands need no sorting and
## overlapping bands deepen the shade the way two nearby walls do. One draw call for a whole
## map, no lights, no textures, nothing per frame; the vertex shader pulls it a fraction toward
## the camera and the fragment fades it out with distance, where its z-fighting would show.
## [b]Not `blend_mul`[/b], which was the first version: with glow on, the Compatibility renderer
## keeps the scene scaled down in its buffer, a multiplied white drew a fifth of the wall behind
## it, and every band was black.
##
## [b]Where a crease is.[/b] For every face F of a box B and every box A that crosses or
## touches F's plane and sticks out of it, A's cross-section in that plane is a rectangle; along
## each of its edges, where F carries on past the edge, there is a concave corner: a band on F
## outside the rectangle (the band up A's side face is the same crease found from that face,
## with the two boxes' parts swapped). Two floor tiles side by side make no band (F does not carry on past the seam), a wall sunk into the floor makes the
## same crease as one standing on it, and a box against a wall shades the wall round its outline.
## A must have one axis along F's normal (yawed boxes on a floor, not tilted ones); its
## cross-section's edges are clipped to F exactly when its axes are F's, and kept only when
## wholly on F when they are not.
##
## [b]How dark is how much sticks out.[/b] A band is [code]width[/code] wide and
## [code]strength[/code] deep when the box stands at least that tall, and narrower and fainter
## below it, so a rug makes no ring and a wall makes a full one.

const CHANNEL := "lighting.shade"

## How far a band reaches from its crease, in metres.
const WIDTH := 0.45

## How dark a band is at its crease: 0.42 multiplies the crease by 0.58.
const STRENGTH := 0.42

## How close a face and a plane count as touching, in metres.
const TOLERANCE := 0.01

## How far off its face a band is drawn, in metres.
const LIFT := 0.004

## Beyond this distance from the camera a band has faded out entirely, in metres.
const FADE_END := 70.0

## The broad phase's cell, in metres.
const CELL := 6.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float fade_start = 40.0;
uniform float fade_end = 70.0;
uniform float pull = 0.002;

varying float view_distance;

void vertex() {
	// Toward the camera by a fraction of the distance, along the view ray: the screen position
	// is unchanged and the band wins the depth test against the face it lies on.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_distance = length(view.xyz);
	view.xyz *= 1.0 - pull;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	// Black at an alpha of the shade: the framebuffer times (1 - alpha), which is a multiply by
	// the vertex's grey. Not blend_mul: the Compatibility renderer stores the scene scaled down
	// when glow is on, and a multiplied white came out as a fifth of the wall behind it.
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - COLOR.r) * (1.0 - smoothstep(fade_start, fade_end, view_distance));
}
"""


## One box for [method build]: [param transform] at its centre, [param size] its full size.
## [param casts]: it darkens what it meets. [param shaded]: its own faces take bands. A
## furniture prop's bounding box casts and is not shaded (bands on a box nobody can see would
## float round the chair); glass or water does neither.
static func box(transform: Transform3D, size: Vector3, casts: bool = true, shaded: bool = true) -> Dictionary:
	return {"transform": transform, "size": size, "casts": casts, "shaded": shaded}


## The node to add to the world: [method mesh] with [method material], casting no shadow. An
## empty [MeshInstance3D] when nothing touches.
static func node(boxes: Array, width: float = WIDTH, strength: float = STRENGTH) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "ContactShade"
	instance.mesh = mesh(boxes, width, strength)
	instance.material_override = material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return instance


## The bands as one mesh (vertices and colours, no normals), or null when nothing touches.
static func mesh(boxes: Array, width: float = WIDTH, strength: float = STRENGTH) -> ArrayMesh:
	var built := build(boxes, width, strength)
	var vertices: PackedVector3Array = built["vertices"]
	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = built["colors"]
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## The material the bands are drawn with: unshaded and multiplied. A new one per call; a game
## builds one shade per map.
static func material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER
	var out := ShaderMaterial.new()
	out.shader = shader
	out.set_shader_parameter(&"fade_end", FADE_END)
	out.set_shader_parameter(&"fade_start", FADE_END * 0.6)
	return out


## The bands, as data: `vertices` and `colors` (three per triangle), `bands` (strips along a
## crease), `corners` (squares round an outside corner), `creases` (box pairs that made any).
## Malformed entries (no size, a non-finite number, a size of zero) are skipped.
static func build(boxes: Array, width: float = WIDTH, strength: float = STRENGTH) -> Dictionary:
	var out := {
		"vertices": PackedVector3Array(), "colors": PackedColorArray(),
		"bands": 0, "corners": 0, "creases": 0,
	}
	if not is_finite(width) or width <= 0.0 or not is_finite(strength) or strength <= 0.0:
		return out
	strength = minf(strength, 1.0)

	var parsed: Array[Dictionary] = []
	for raw: Variant in boxes:
		var b := _parse(raw)
		if not b.is_empty():
			parsed.append(b)

	# Broad phase: boxes by the cells their bounds cover, so each face is tried only against
	# boxes near it.
	var cells := {}
	for index in range(parsed.size()):
		var bounds: AABB = parsed[index]["bounds"]
		var lo := Vector3i((bounds.position / CELL).floor())
		var hi := Vector3i((bounds.end / CELL).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var key := Vector3i(x, y, z)
					if not cells.has(key):
						cells[key] = []
					(cells[key] as Array).append(index)

	for bi in range(parsed.size()):
		var b: Dictionary = parsed[bi]
		if not b["shaded"]:
			continue
		var near := {}
		var bounds: AABB = b["bounds"]
		var lo := Vector3i((bounds.position / CELL).floor())
		var hi := Vector3i((bounds.end / CELL).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					for ai: int in cells.get(Vector3i(x, y, z), []):
						near[ai] = true
		for ai: int in near:
			if ai == bi:
				continue
			var a: Dictionary = parsed[ai]
			if not a["casts"]:
				continue
			if not (a["bounds"] as AABB).grow(TOLERANCE).intersects(bounds.grow(TOLERANCE)):
				continue
			var before: int = out["bands"]
			for axis in range(3):
				for side: float in [-1.0, 1.0]:
					_crease(b, axis, side, a, width, strength, out)
			if int(out["bands"]) > before:
				out["creases"] = int(out["creases"]) + 1
	return out


# --- Internals --------------------------------------------------------------

static func _parse(raw: Variant) -> Dictionary:
	var transform := Transform3D.IDENTITY
	var size := Vector3.ZERO
	var casts := true
	var shaded := true
	if raw is Dictionary:
		var d := raw as Dictionary
		if not (d.get("transform") is Transform3D) or not (d.get("size") is Vector3):
			return {}
		transform = d["transform"]
		size = d["size"]
		casts = bool(d.get("casts", true))
		shaded = bool(d.get("shaded", true))
	elif raw is Array and (raw as Array).size() >= 2 and raw[0] is Transform3D and raw[1] is Vector3:
		transform = raw[0]
		size = raw[1]
	else:
		return {}
	if not size.is_finite() or not transform.origin.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return {}
	# Unit axes and half extents: a scaled basis is folded into the size.
	var axes: Array[Vector3] = []
	var half := PackedFloat32Array()
	for i in range(3):
		var column: Vector3 = transform.basis[i]
		var length := column.length()
		if not is_finite(length) or length < 0.000001:
			return {}
		axes.append(column / length)
		half.append(size[i] * 0.5 * length)
	var corner := Vector3.ZERO
	for i in range(3):
		corner += (axes[i] * half[i]).abs()
	return {
		"centre": transform.origin, "axes": axes, "half": half,
		"bounds": AABB(transform.origin - corner, corner * 2.0),
		"casts": casts, "shaded": shaded,
	}


## The creases [param a] makes on face ([param axis], [param side]) of [param b].
static func _crease(b: Dictionary, axis: int, side: float, a: Dictionary, width: float,
		strength: float, out: Dictionary) -> void:
	var b_axes: Array[Vector3] = b["axes"]
	var b_half: PackedFloat32Array = b["half"]
	var normal := b_axes[axis] * side
	var plane_point: Vector3 = b["centre"] + normal * b_half[axis]
	var u := b_axes[(axis + 1) % 3]
	var v := b_axes[(axis + 2) % 3]
	var hu := b_half[(axis + 1) % 3]
	var hv := b_half[(axis + 2) % 3]

	# A's axis along the face's normal, and the two in the plane.
	var a_axes: Array[Vector3] = a["axes"]
	var a_half: PackedFloat32Array = a["half"]
	var along := -1
	for i in range(3):
		if absf(a_axes[i].dot(normal)) > 0.999:
			along = i
	if along < 0:
		return
	var offset := (a["centre"] as Vector3 - plane_point).dot(normal)
	var low := offset - a_half[along]
	var high := offset + a_half[along]
	# It must reach the plane and stand out of it.
	if low > TOLERANCE or high <= TOLERANCE:
		return

	var stands := high
	var band_width := minf(width, stands)
	var band_strength := strength * clampf(stands / width, 0.0, 1.0)
	if band_width < 0.02 or band_strength < 0.02:
		return

	var centre: Vector3 = (a["centre"] as Vector3) - normal * offset
	var e1 := a_axes[(along + 1) % 3]
	var e2 := a_axes[(along + 2) % 3]
	var g1 := a_half[(along + 1) % 3]
	var g2 := a_half[(along + 2) % 3]
	var aligned := absf(e1.dot(u)) > 0.999 or absf(e1.dot(v)) > 0.999

	# Where a point of the plane is in F's rectangle.
	var on_face := func(p: Vector3) -> bool:
		var d := p - plane_point
		return absf(d.dot(u)) <= hu + TOLERANCE and absf(d.dot(v)) <= hv + TOLERANCE

	var edges := [[e1, g1, e2, g2], [-e1, g1, e2, g2], [e2, g2, e1, g1], [-e2, g2, e1, g1]]
	var full := {}
	for edge: Array in edges:
		var m: Vector3 = edge[0]
		var to_edge: float = edge[1]
		var t: Vector3 = edge[2]
		var length: float = edge[3]
		var edge_centre := centre + m * to_edge
		var from := -length
		var to := length
		var depth := band_width
		if aligned:
			# F's rectangle in the edge's own (m, t) coordinates, about the edge's centre.
			var rel := edge_centre - plane_point
			var m_lo := -_reach(rel, m, u, v, hu, hv, false)
			var m_hi := _reach(rel, m, u, v, hu, hv, true)
			var t_lo := -_reach(rel, t, u, v, hu, hv, false)
			var t_hi := _reach(rel, t, u, v, hu, hv, true)
			# The crease is on F only if the edge itself is.
			if m_lo > TOLERANCE or m_hi < -TOLERANCE:
				continue
			depth = minf(band_width, m_hi)
			from = maxf(from, t_lo)
			to = minf(to, t_hi)
		else:
			var inside: bool = on_face.call(edge_centre + t * length) and on_face.call(edge_centre - t * length) \
				and on_face.call(edge_centre + t * length + m * band_width) and on_face.call(edge_centre - t * length + m * band_width)
			if not inside:
				continue
		if depth < 0.02 or to - from < 0.02:
			continue
		if depth >= band_width - 0.001 and from <= -length + 0.001 and to >= length - 0.001:
			full[m] = true
		var shade := band_strength * clampf(depth / band_width, 0.0, 1.0)
		var lift_f := normal * LIFT
		# On F, outside A: dark at the crease, light at `depth`. Only F's half: the band up A's
		# side face is the same crease seen from that face, made when A's face is F and this
		# box is the one crossing it. Drawing both here drew every crease twice as dark.
		_strip(out, edge_centre + t * from + lift_f, edge_centre + t * to + lift_f, m, depth, shade)
		out["bands"] = int(out["bands"]) + 1

	# The outside corners of A's rectangle on F, where two full bands meet.
	for c1: Vector3 in [e1, -e1]:
		for c2: Vector3 in [e2, -e2]:
			if not full.has(c1) or not full.has(c2):
				continue
			var at := centre + c1 * g1 + c2 * g2
			var far := at + (c1 + c2) * band_width
			if not on_face.call(far):
				continue
			_corner(out, at + normal * LIFT, c1, c2, band_width, band_strength)
			out["corners"] = int(out["corners"]) + 1


## How far F's rectangle reaches from [param rel] (a point relative to F's centre) along
## [param dir], or against it when not [param forward]; [param dir] is one of ±u, ±v.
static func _reach(rel: Vector3, dir: Vector3, u: Vector3, v: Vector3, hu: float, hv: float, forward: bool) -> float:
	var h := hu if absf(dir.dot(u)) > 0.999 else hv
	var r := rel.dot(dir)
	return h - r if forward else h + r


## A strip from the crease line ([param a] to [param b]) out along [param out_dir], [param depth]
## long: three rows, so the shade falls off faster near the crease than a straight ramp.
static func _strip(out: Dictionary, a: Vector3, b: Vector3, out_dir: Vector3, depth: float, shade: float) -> void:
	var rows := [[0.0, 1.0 - shade], [0.3, 1.0 - shade * 0.45], [1.0, 1.0]]
	for r in range(rows.size() - 1):
		var d0: float = rows[r][0] * depth
		var d1: float = rows[r + 1][0] * depth
		var k0 := Color(rows[r][1], rows[r][1], rows[r][1])
		var k1 := Color(rows[r + 1][1], rows[r + 1][1], rows[r + 1][1])
		var p0 := a + out_dir * d0
		var p1 := b + out_dir * d0
		var p2 := b + out_dir * d1
		var p3 := a + out_dir * d1
		_triangle(out, p0, p1, p2, k0, k0, k1)
		_triangle(out, p0, p2, p3, k0, k1, k1)


## A square at an outside corner: dark at the box's corner, with the strips' profile along its
## two sides (which the strips beside it end on) and lighter across the diagonal, which is
## further from both faces.
static func _corner(out: Dictionary, at: Vector3, c1: Vector3, c2: Vector3, size: float, shade: float) -> void:
	var dark := Color(1.0 - shade, 1.0 - shade, 1.0 - shade)
	var side := Color(1.0 - shade * 0.45, 1.0 - shade * 0.45, 1.0 - shade * 0.45)
	var across := Color(1.0 - shade * 0.3, 1.0 - shade * 0.3, 1.0 - shade * 0.3)
	var light := Color.WHITE
	var i1 := at + c1 * size * 0.3
	var i2 := at + c2 * size * 0.3
	var id := at + (c1 + c2) * size * 0.3
	var o1 := at + c1 * size
	var o2 := at + c2 * size
	var od := at + (c1 + c2) * size
	_triangle(out, at, i1, id, dark, side, across)
	_triangle(out, at, id, i2, dark, across, side)
	_triangle(out, i1, o1, od, side, light, light)
	_triangle(out, i1, od, id, side, light, across)
	_triangle(out, i2, id, od, side, across, light)
	_triangle(out, i2, od, o2, side, light, light)


static func _triangle(out: Dictionary, p0: Vector3, p1: Vector3, p2: Vector3, k0: Color, k1: Color, k2: Color) -> void:
	var vertices: PackedVector3Array = out["vertices"]
	var colors: PackedColorArray = out["colors"]
	vertices.append_array(PackedVector3Array([p0, p1, p2]))
	colors.append_array(PackedColorArray([k0, k1, k2]))
	out["vertices"] = vertices
	out["colors"] = colors
