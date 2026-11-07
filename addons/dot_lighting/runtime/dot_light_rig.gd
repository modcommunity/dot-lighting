class_name DotLightRig
extends RefCounted

## Turns a [DotLightDocument] into a sun and an [Environment] under a node.
##
## [codeblock]
## DotLightRig.apply(world_root, DotLightDocument.from_dictionary(manifest["lighting"]))
## [/codeblock]
##
## A baked world has its light in its textures, so the sun here lights characters, props and
## anything with an ordinary material. What changes the baked world itself is the post-processing:
## tone map, fog, glow and the background colour.

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
	# Soft-curved: the range is nearly two orders of magnitude across ordinary content.
		light.light_energy = clampf(
			sqrt(doc.sun_brightness / maxf(profile.brightness_reference, 1.0)), 0.35, 2.0)

	if doc.sun_spread > 0.0:
		light.light_angular_distance = clampf(doc.sun_spread, 0.0, 90.0)

	parent.add_child(light)
	if profile.fill_energy > 0.0:
		parent.add_child(fill(doc, light.rotation, profile))
	parent.add_child(environment(doc, profile))
	return light


## The shadowless light from the side of the sky the sun is not on; see
## [member DotLightProfile.fill_energy]. [param sun_rotation] is the sun's. A sun straight
## overhead has no opposite side, so the fill then comes from a fixed one.
static func fill(doc: DotLightDocument, sun_rotation: Vector3, profile: DotLightProfile) -> DirectionalLight3D:
	var travel := -Basis.from_euler(sun_rotation).z
	var across := Vector3(-travel.x, 0.0, -travel.z)
	if across.length_squared() < 0.0025:
		across = Vector3(0.0, 0.0, 1.0)
	var elevation := deg_to_rad(clampf(profile.fill_elevation, 5.0, 85.0))
	var direction := across.normalized() * cos(elevation) + Vector3.DOWN * sin(elevation)

	var light := DirectionalLight3D.new()
	light.name = "Fill"
	light.rotation = aim_along(direction)
	# The shade's own colour, so the fill reads as more sky and not as a second sun.
	light.light_color = doc.ambient_colour
	light.light_energy = profile.fill_energy
	# No glint: a second highlight on every glossy surface is the giveaway of a second sun.
	light.light_specular = 0.0
	light.shadow_enabled = false
	# A procedural sky draws a disc for every directional light; the dim fill's is a black dot.
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return light


## The rotation that points a [DirectionalLight3D] the way a Z-up world's sun points.
##
## Convert the DIRECTION, not the angles: the BSP-family worlds are Z-up left-handed, Godot is
## Y-up right-handed, and converting pitch and yaw separately gives a sun rising in the north.
## Build the vector in the source convention, swap axes once (`godot = (x, z, -y)`), aim along it.
## A negative pitch is a sun in the sky: the angle is where the light goes.
static func sun_rotation(pitch_degrees: float, yaw_degrees: float) -> Vector3:
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	var src := Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))
	return aim_along(Vector3(src.x, src.z, -src.y))


## The rotation of a light shining along [param direction].
##
## A [DirectionalLight3D] shines down -Z, so this is `looking_at`, except for a sun straight
## overhead, where the up vector is parallel and no basis exists.
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

	# The background follows the fog: a different colour past the last surface is a seam at the horizon.
	var horizon := doc.fog_colour if doc.fog_enabled else Color(0.55, 0.65, 0.80)
	if profile.sky:
		env.background_mode = Environment.BG_SKY
		env.sky = _sky(doc, horizon, profile.sky_below_horizon)
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = horizon

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = doc.ambient_colour
	env.ambient_light_energy = profile.ambient_energy

	if profile.tonemap:
		# Godot defaults to LINEAR, which clips; a filmic shoulder keeps a bright sky and a dark wall readable.
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = profile.tonemap_white
	env.tonemap_exposure = profile.exposure

	# Off unless asked: the adjustment pass is a full-screen pass.
	if not is_equal_approx(profile.contrast, 1.0) or not is_equal_approx(profile.saturation, 1.0):
		env.adjustment_enabled = true
		env.adjustment_contrast = profile.contrast
		env.adjustment_saturation = profile.saturation

	# Forward+ only. The radius is a step's depth, so a box sits on its floor.
	if profile.ambient_occlusion and RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6

	if profile.glow:
		env.glow_enabled = true
		env.glow_intensity = profile.glow_intensity
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = profile.glow_threshold
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	if profile.fog and doc.fog_enabled:
		apply_fog(env, doc)

	node.environment = env
	return node


## Writes [param doc]'s fog onto [param env] (off when the document has none), so weather can
## change the fog the way a map's lighting does. [param metres_per_unit] is 1.0 for metres.
static func apply_fog(env: Environment, doc: DotLightDocument, metres_per_unit: float = METRES_PER_UNIT) -> void:
	if env == null or doc == null:
		return
	if not doc.fog_enabled:
		env.fog_enabled = false
		return
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = doc.fog_colour
	# A negative start means "from the camera"; a negative depth does not, so clamp.
	var start := maxf(doc.fog_start, 0.0)
	env.fog_depth_begin = start * metres_per_unit
	env.fog_depth_end = maxf(doc.fog_end, start + 1.0) * metres_per_unit
	# The document's own maximum, not 1.0: a world saying 0.4 wants distance tinted, not erased.
	env.fog_density = clampf(doc.fog_max_density, 0.0, 1.0)
	env.fog_depth_curve = 1.0
	# Fog over the sky would flatten it; the sky is already the colour the fog fades into.
	env.fog_sky_affect = 0.0


## A sky from the world's own numbers, since the named [member DotLightDocument.sky_name] is
## another game's texture. The fog colour is the horizon, the top is [member DotLightDocument.sky_top]
## or else the ambient, and the ground half is dark and neutral.
static func _sky(doc: DotLightDocument, horizon: Color, below_horizon: bool = false) -> Sky:
	var mat := ProceduralSkyMaterial.new()
	mat.sky_horizon_color = horizon
	# sky_top, then ambient, then a darker horizon. The ambient LIGHT is untouched by sky_top.
	if doc.has_sky_top:
		mat.sky_top_color = doc.sky_top
	elif doc.has_ambient:
		mat.sky_top_color = doc.ambient_colour
	else:
		mat.sky_top_color = horizon.darkened(0.3)
	mat.sky_energy_multiplier = 1.0
	mat.ground_horizon_color = horizon
	# The lower half mirrors the upper when the world floats in its sky; see
	# [member DotLightProfile.sky_below_horizon].
	mat.ground_bottom_color = mat.sky_top_color if below_horizon else horizon.darkened(0.7)
	mat.ground_energy_multiplier = 1.0
	# A disc only where there is a sun: small and bright, to agree with the baked hard shadows.
	if doc.has_sun:
		mat.sun_angle_max = 3.0
		mat.sun_curve = 0.12
	else:
		mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = mat
	# The sky is static, so the radiance map is generated once.
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	return sky


## The family's one unit boundary: 0.75 inch per unit. Duplicated rather than imported, as
## the addon depends on dot-core alone.
const METRES_PER_UNIT := 0.01905


static func metres(units: float) -> float:
	return units * METRES_PER_UNIT
