class_name DotLightRig
extends RefCounted

## Turns a [DotLightDocument] into a sun and an [Environment] under a node.
##
## [codeblock]
## DotLightRig.apply(world_root, DotLightDocument.from_dictionary(manifest["lighting"]))
## [/codeblock]
##
## [b]What this can and cannot change is worth being exact about, because it decides
## whether the addon is doing anything at all.[/b] A world drawn from a BAKED lightmap has
## its lighting in its textures: its materials are unshaded, and a directional light added
## beside them lights nothing they own. The sun here therefore lights the CHARACTERS, the
## props and anything else with an ordinary material — and what changes how the baked world
## itself looks is the post-processing: the tone map, the fog, the glow and the colour
## behind everything.
##
## That is not a limitation so much as the division of labour a baked world already has,
## and those four are most of the difference between a faithful import and one that feels
## like the engine it came from.

## Applies [param doc] under [param parent] and returns the sun it made.
##
## [param profile] decides what this machine draws; null means [method DotLightProfile.high].
## Safe on an empty document: every field is optional and absent keeps the default.
static func apply(
	parent: Node3D,
	doc: DotLightDocument,
	profile: DotLightProfile = null
) -> DirectionalLight3D:
	if parent == null:
		return null
	if doc == null:
		doc = DotLightDocument.new()
	if profile == null:
		profile = DotLightProfile.high()

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.shadow_enabled = profile.sun_shadows

	if doc.has_sun:
		light.rotation = sun_rotation(doc.sun_pitch, doc.sun_yaw)
	else:
		light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)

	light.light_color = doc.sun_colour

	if doc.sun_brightness > 0.0:
		# Soft-curved rather than linear because the range is nearly two orders of
		# magnitude across ordinary content, and a player should not be squinting on one
		# world and unable to see on the next.
		light.light_energy = clampf(
			sqrt(doc.sun_brightness / maxf(profile.brightness_reference, 1.0)), 0.35, 2.0)

	if doc.sun_spread > 0.0:
		light.light_angular_distance = clampf(doc.sun_spread, 0.0, 90.0)

	parent.add_child(light)
	parent.add_child(environment(doc, profile))
	return light


## The rotation that points a [DirectionalLight3D] the way a Z-up world's sun points.
##
## [b]The conversion is on the DIRECTION and not on the angles, and that is the whole
## reason this is a function.[/b] Source-family worlds are Z-up and left-handed and Godot
## is Y-up and right-handed; a yaw in one is not a yaw in the other, so converting pitch
## and yaw separately produces a sun that rises in the north and nothing about the result
## looks wrong enough to question. Build the vector in the source convention, swap axes
## once — `godot = (x, z, -y)` — and aim along it.
##
## A negative pitch is a sun in the sky, because the angle describes where the light GOES
## rather than where it comes from.
static func sun_rotation(pitch_degrees: float, yaw_degrees: float) -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	var src := Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))
	return aim_along(Vector3(src.x, src.z, -src.y))


## The rotation of a light shining along [param direction].
##
## A [DirectionalLight3D] shines down its own -Z, so this is `looking_at` — with the one
## case that has no answer handled: a sun straight overhead is parallel to the default up
## vector and `looking_at` cannot build a basis from two parallel vectors. Worlds with an
## exactly vertical sun are common, not a corner case.
static func aim_along(direction: Vector3) -> Vector3:
	var forward := direction.normalized()
	if forward.length_squared() < 0.5:
		return Vector3(-0.96, -0.61, 0.0)
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.999:
		up = Vector3.FORWARD
	return Transform3D().looking_at(forward, up).basis.get_euler()


## The [WorldEnvironment] a document and a profile describe.
static func environment(
	doc: DotLightDocument,
	profile: DotLightProfile = null
) -> WorldEnvironment:
	if doc == null:
		doc = DotLightDocument.new()
	if profile == null:
		profile = DotLightProfile.high()

	var node := WorldEnvironment.new()
	node.name = "Lighting"
	var env := Environment.new()

	# [b]The background follows the fog, and a world with fog and a different sky behind it
	# has a visible seam along every horizon.[/b] Fog is what distance fades INTO, so the
	# colour it fades into and the colour past the last surface have to be the same one.
	var horizon := doc.fog_colour if doc.fog_enabled else Color(0.55, 0.65, 0.80)
	env.background_mode = Environment.BG_COLOR
	env.background_color = horizon

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = doc.ambient_colour
	env.ambient_light_energy = profile.ambient_energy

	if profile.tonemap:
		# Godot defaults to LINEAR, which is not a tone map: it clips. A filmic shoulder is
		# why a bright sky and a dark wall can both be readable in one frame instead of one
		# being white and the other black.
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = profile.tonemap_white

	if profile.glow:
		env.glow_enabled = true
		env.glow_intensity = profile.glow_intensity
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = profile.glow_threshold
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	if profile.fog and doc.fog_enabled:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = horizon
		# A source world may write a negative start, meaning "from the camera". A negative
		# depth here is not the same statement, so it is clamped rather than passed on.
		var start := maxf(doc.fog_start, 0.0)
		env.fog_depth_begin = metres(start)
		env.fog_depth_end = metres(maxf(doc.fog_end, start + 1.0))
		env.fog_density = 1.0
		env.fog_depth_curve = 1.0

	node.environment = env
	return node


## The family's one unit boundary, and the only place this addon crosses it.
##
## 0.75 inch per unit is the scale these worlds were authored at. It is duplicated here
## rather than imported because the addon depends on dot-core alone and a game that owns
## its own conversion passes metres in already.
const METRES_PER_UNIT := 0.01905


static func metres(units: float) -> float:
	return units * METRES_PER_UNIT
