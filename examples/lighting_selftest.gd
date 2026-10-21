extends Node3D

## dot-lighting's headless suite.
##
##     godot --headless --path . res://examples/lighting_selftest.tscn
##
## [b]It counts two things and the second is the one that matters.[/b] Sections that ran to
## their last line, and a total number of checks — because a script error inside a section
## aborts THAT section and not the run, and the section counter is satisfied by a section
## that had already announced itself. A suite reporting "0 failed" with checks missing is a
## failure this family has shipped more than once.

const EXPECTED_SECTIONS := 10
const EXPECTED_CHECKS := 119

var _passed := 0
var _failed := 0
var _sections := 0
var _failures := PackedStringArray()


func _ready() -> void:
	print("dot-lighting")
	print("")
	_document()
	_round_trip()
	_sun_direction()
	_profiles()
	_rig()
	_sky_top()
	_painted()
	_zone()
	_contact_shade()
	_bake()
	print("")
	_check(_sections == EXPECTED_SECTIONS,
		"every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS,
		"and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  %s" % line)
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	print(title)


func _done() -> void:
	_sections += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)


func _document() -> void:
	_section("the document")

	var empty := DotLightDocument.from_dictionary({})
	_check(not empty.has_sun, "an empty document declares no sun")
	_check(not empty.fog_enabled, "and no fog")
	_check(empty.sun_colour == Color.WHITE, "and its sun colour is white rather than black")
	_check(empty.baked_light_count == 0, "and it knows of no baked lights")

	var doc := DotLightDocument.from_dictionary({
		"sun": {
			"pitch_src": -28.0, "yaw_src": 270.0,
			"colour": [0.92, 0.87, 0.69], "brightness": 600.0,
			"ambient_colour": [0.49, 0.57, 0.67], "spread_degrees": 12.0,
		},
		"fog": {"enabled": true, "colour": [0.61, 0.93, 0.98],
			"start": 5000.0, "end": 20000.0},
		"sky_name": "mpa104",
		"baked_light_count": 6,
	})
	_check(doc.has_sun, "a full document declares a sun")
	_check(is_equal_approx(doc.sun_pitch, -28.0), "with the pitch it was given")
	_check(is_equal_approx(doc.sun_brightness, 600.0),
		"and the brightness UNCONVERTED, because it is not a 0..1 value")
	_check(doc.has_ambient, "and an ambient colour separate from the sun's")
	_check(doc.fog_enabled and is_equal_approx(doc.fog_end, 20000.0), "and fog with a range")
	_check(doc.sky_name == "mpa104", "and the name of its sky")
	_check(doc.baked_light_count == 6, "and how many lights were baked into it")

	# [b]Absent is not zero, and this is the check that says so.[/b] A document with no
	# ambient keeps the consumer's default; one with a black ambient means black.
	var no_ambient := DotLightDocument.from_dictionary({"sun": {"pitch_src": -45.0}})
	_check(not no_ambient.has_ambient, "a sun with no ambient does not claim one")
	var black := DotLightDocument.from_dictionary(
		{"sun": {"pitch_src": -45.0, "ambient_colour": [0.0, 0.0, 0.0]}})
	_check(black.has_ambient and black.ambient_colour == Color.BLACK,
		"and one that says black means black, which is a different instruction")
	_done()


func _round_trip() -> void:
	_section("it survives being written down")

	var before := DotLightDocument.from_dictionary({
		"sun": {"pitch_src": -69.0, "yaw_src": 111.0, "colour": [0.97, 0.91, 0.83],
			"brightness": 32.0, "spread_degrees": 12.0},
		"fog": {"enabled": true, "colour": [0.09, 0.66, 0.86], "start": 0.0, "end": 8536.0,
			"max_density": 0.4},
		"sky_name": "reef",
		"baked_light_count": 74,
	})
	var after := DotLightDocument.from_dictionary(before.to_dictionary())

	_check(is_equal_approx(after.sun_pitch, before.sun_pitch), "the pitch comes back")
	_check(is_equal_approx(after.sun_yaw, before.sun_yaw), "and the yaw")
	_check(is_equal_approx(after.sun_brightness, 32.0), "and the brightness")
	_check(is_equal_approx(after.sun_spread, 12.0), "and the sun's spread")
	_check(after.fog_enabled and is_equal_approx(after.fog_end, 8536.0), "and the fog")
	_check(is_equal_approx(after.fog_max_density, 0.4),
		"and how dense that fog is allowed to get, which is not always all the way")
	_check(after.sky_name == "reef", "and the sky name")
	_check(after.baked_light_count == 74, "and the baked light count")

	# A JSON round trip as well, because the whole point of a document is that it travels.
	var text := JSON.stringify(before.to_dictionary())
	var parsed: Variant = JSON.parse_string(text)
	var via_json := DotLightDocument.from_dictionary(parsed as Dictionary)
	_check(is_equal_approx(via_json.sun_pitch, -69.0), "and through JSON as well")
	_done()


func _sun_direction() -> void:
	_section("the sun points where the world says")

	# Source is Z-up; -90 is straight down whatever the yaw.
	var down := DotLightRig.sun_rotation(-90.0, 0.0)
	var basis := Basis.from_euler(down)
	var direction := -basis.z
	_check(direction.y < -0.99,
		"a pitch of -90 is a sun straight overhead, shining down")

	# [b]The case that has no answer without handling.[/b] A vertical direction is parallel
	# to the default up vector and `looking_at` cannot build a basis from two parallel
	# vectors — worlds with an exactly vertical sun are ordinary, not a corner case.
	_check(is_finite(down.x) and is_finite(down.y) and is_finite(down.z),
		"and the rotation is a number rather than a NaN")

	var level := DotLightRig.sun_rotation(0.0, 0.0)
	var level_dir := -Basis.from_euler(level).z
	_check(absf(level_dir.y) < 0.01, "a pitch of 0 is a sun on the horizon")

	# Yaw has to move the sun AROUND rather than tilt it, and the two yaws below are
	# opposite, so their directions must be too.
	var east := -Basis.from_euler(DotLightRig.sun_rotation(-30.0, 0.0)).z
	var west := -Basis.from_euler(DotLightRig.sun_rotation(-30.0, 180.0)).z
	_check(absf(east.y - west.y) < 0.01, "opposite yaws keep the same height")
	_check(east.dot(west) < 0.0, "and point opposite ways")

	var aimed := DotLightRig.aim_along(Vector3.ZERO)
	_check(is_finite(aimed.x), "and a zero direction does not produce a NaN either")
	_done()


func _profiles() -> void:
	_section("a profile is what THIS machine draws")

	var high := DotLightProfile.high()
	var low := DotLightProfile.low()
	var web := DotLightProfile.web()

	_check(high.glow and high.sun_shadows, "high draws everything")
	_check(not low.glow and not low.sun_shadows, "low drops glow and shadows")
	_check(low.tonemap,
		"and keeps the tone map, which is a curve on a pixel already being written")

	# [b]The browser drops the expensive half and not the cheap one.[/b] A shadow pass
	# scales with how much geometry is in frame; glow is a fixed cost in screen pixels.
	_check(web.glow and not web.sun_shadows,
		"web keeps glow and drops shadows, which is the expensive one there")
	_done()


func _rig() -> void:
	_section("the rig builds a sun and an environment")

	var doc := DotLightDocument.from_dictionary({
		"sun": {"pitch_src": -28.0, "yaw_src": 270.0, "colour": [0.92, 0.87, 0.69],
			"brightness": 600.0, "ambient_colour": [0.49, 0.57, 0.67]},
		"fog": {"enabled": true, "colour": [0.61, 0.93, 0.98],
			"start": 5000.0, "end": 20000.0},
	})

	var root := Node3D.new()
	add_child(root)
	var sun := DotLightRig.apply(root, doc)

	_check(sun != null, "it returns the sun it made")
	_check(sun.light_color.is_equal_approx(Color(0.92, 0.87, 0.69)),
		"in the colour the document asked for")
	# 600 against a reference of 200 is sqrt(3), not 3 and not 600.
	_check(absf(sun.light_energy - sqrt(3.0)) < 0.01,
		"with a brightness of 600 curved to an energy of %.2f rather than 600" % sqrt(3.0))

	var env_node: WorldEnvironment = null
	for child in root.get_children():
		if child is WorldEnvironment:
			env_node = child
	_check(env_node != null, "and a WorldEnvironment beside it")

	var env := env_node.environment
	_check(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "tone mapped rather than clipped")
	_check(env.glow_enabled, "with glow on")
	_check(env.glow_hdr_threshold < 1.0,
		"and a threshold under 1.0, or a baked world would never bloom at all")
	_check(env.fog_enabled, "and fog")
	# apply_fog is what environment() now calls; applying it again to a bare Environment in
	# metres (as weather does) must write the same fields, and off must switch fog off.
	var bare := Environment.new()
	var metre_doc := DotLightDocument.from_dictionary({"fog": {"enabled": true,
		"colour": [0.5, 0.6, 0.7], "start": 5.0, "end": 90.0, "max_density": 0.4}})
	DotLightRig.apply_fog(bare, metre_doc, 1.0)
	_check(bare.fog_enabled and is_equal_approx(bare.fog_depth_end, 90.0)
		and is_equal_approx(bare.fog_density, 0.4) and bare.fog_light_color.is_equal_approx(Color(0.5, 0.6, 0.7)),
		"apply_fog writes a bare Environment in metres: colour, depth and the document's own density")
	DotLightRig.apply_fog(bare, DotLightDocument.new(), 1.0)
	_check(not bare.fog_enabled, "and a document with no fog switches it off")
	_check(is_equal_approx(env.fog_depth_end, DotLightRig.metres(20000.0)),
		"while environment() still converts map units (%.1f m)" % env.fog_depth_end)
	# The same invariant the flat background used to carry, moved to where the horizon
	# now is. A sky whose horizon is not the colour the fog fades into draws a visible
	# line along every ridge in the world, which is the whole reason either is tied to
	# the other.
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	_check(env.background_mode == Environment.BG_SKY and sky_mat != null,
		"drawn against a sky rather than a flat colour")
	_check(sky_mat != null and sky_mat.sky_horizon_color.is_equal_approx(env.fog_light_color),
		"whose horizon is the fog colour, or the horizon has a seam in it")
	_check(env.fog_sky_affect == 0.0, "and the fog does not also fog the sky")
	_check(env.fog_depth_end > env.fog_depth_begin, "and a range that goes forwards")

	# A negative start means "from the camera" in a source world and is not the same
	# statement as a negative depth here.
	var negative := DotLightDocument.from_dictionary(
		{"fog": {"enabled": true, "start": -300.0, "end": 8536.0}})
	var neg_node := DotLightRig.environment(negative)
	_check(neg_node.environment.fog_depth_begin >= 0.0,
		"a negative fog start is clamped rather than passed on")
	neg_node.free()

	# An enclosed level keeps a dark ground; a world floating in its sky does not.
	_check(sky_mat != null and sky_mat.ground_bottom_color.get_luminance() < sky_mat.sky_horizon_color.get_luminance(),
		"by default the sky's lower half is dark ground, for a level with a floor under its horizon")
	var floating := DotLightProfile.high()
	floating.sky_below_horizon = true
	var float_node := DotLightRig.environment(doc, floating)
	var float_sky := float_node.environment.sky.sky_material as ProceduralSkyMaterial
	_check(float_sky != null and float_sky.ground_bottom_color.is_equal_approx(float_sky.sky_top_color),
		"and with sky_below_horizon the lower half mirrors the upper, for a world inside its skybox")
	float_node.free()

	var low_node := DotLightRig.environment(doc, DotLightProfile.low())
	var low_env := low_node.environment
	_check(not low_env.glow_enabled, "a low profile turns the glow off")
	_check(low_env.tonemap_mode == Environment.TONE_MAPPER_FILMIC,
		"and leaves the same world tone mapped")
	low_node.free()

	var spare := Node3D.new()
	add_child(spare)
	var empty_sun := DotLightRig.apply(spare, DotLightDocument.new())
	_check(empty_sun != null, "an empty document still produces a usable sun")
	spare.queue_free()
	_check(DotLightRig.apply(null, doc) == null, "and a null parent is refused rather than crashing")
	_done()


## A sky colour of its own, apart from the ambient.
##
## [b]The default is the half that matters most.[/b] Every document written before sky_top
## existed has to draw the sky it always did, so the first checks are the old zenith
## (ambient, or a darker horizon) and an ambient light the new key cannot reach.
func _sky_top() -> void:
	_section("sky_top: the zenith apart from the fill")

	var base := {
		"sun": {"pitch_src": -50.0, "yaw_src": -35.0, "brightness": 380.0,
			"ambient_colour": [0.74, 0.78, 0.92]},
		"fog": {"enabled": true, "colour": [0.80, 0.89, 1.0], "start": 2600.0, "end": 12000.0},
	}
	var plain := DotLightDocument.from_dictionary(base)
	_check(not plain.has_sky_top, "a document without sky_top does not claim one")
	_check(not plain.to_dictionary().has("sky_top"), "and does not write one back out")
	var plain_sky := _sky_of(DotLightRig.environment(plain))
	_check(plain_sky != null and plain_sky.sky_top_color.is_equal_approx(Color(0.74, 0.78, 0.92)),
		"and its zenith is still the ambient, exactly as before sky_top existed")
	var dark := _sky_of(DotLightRig.environment(DotLightDocument.from_dictionary(
		{"fog": {"enabled": true, "colour": [0.80, 0.89, 1.0], "end": 12000.0}})))
	_check(dark != null and dark.sky_top_color.is_equal_approx(Color(0.80, 0.89, 1.0).darkened(0.3)),
		"and with no ambient either, still the darker horizon")

	# The shape game-arena's maps already carry: a top-level key beside sky_name.
	var data := base.duplicate(true)
	data["sky_top"] = [0.30, 0.56, 0.96]
	var doc := DotLightDocument.from_dictionary(data)
	var blue := Color(0.30, 0.56, 0.96)
	_check(doc.has_sky_top and doc.sky_top.is_equal_approx(blue),
		"a top-level \"sky_top\": [r, g, b] is read")
	var env_node := DotLightRig.environment(doc)
	var env := env_node.environment
	var sky := _sky_of(env_node)
	_check(sky != null and sky.sky_top_color.is_equal_approx(blue), "and drawn as the zenith")
	_check(env.ambient_light_color.is_equal_approx(Color(0.74, 0.78, 0.92)),
		"while the ambient LIGHT stays the pale fill, which is the point of naming it apart")
	_check(sky != null and sky.sky_horizon_color.is_equal_approx(env.fog_light_color),
		"and the horizon is still the fog colour")
	var floating := DotLightProfile.high()
	floating.sky_below_horizon = true
	var under := _sky_of(DotLightRig.environment(doc, floating))
	_check(under != null and under.ground_bottom_color.is_equal_approx(blue),
		"and a world floating in its sky mirrors the sky_top underneath, not the ambient")

	var back := DotLightDocument.from_dictionary(doc.to_dictionary())
	_check(back.has_sky_top and back.sky_top.is_equal_approx(blue), "it survives being written down")
	var via_json := DotLightDocument.from_dictionary(
		JSON.parse_string(JSON.stringify(doc.to_dictionary())) as Dictionary)
	_check(via_json.has_sky_top and via_json.sky_top.is_equal_approx(blue), "and through JSON")

	# Absent is not zero here either: black is a colour, and a malformed value is absent.
	var black := DotLightDocument.from_dictionary({"sky_top": [0.0, 0.0, 0.0]})
	_check(black.has_sky_top and black.sky_top == Color.BLACK, "a black sky_top means black")
	var bad := DotLightDocument.from_dictionary({"sky_top": [0.3, 0.5]})
	var bad_word := DotLightDocument.from_dictionary({"sky_top": "blue"})
	_check(not bad.has_sky_top and not bad_word.has_sky_top,
		"and a value that is not a colour is ignored rather than painted as a default")
	_done()


## The procedural sky [param node] draws. Frees the node: the material and the
## [Environment] are resources and outlive it for as long as the caller holds them.
func _sky_of(node: WorldEnvironment) -> ProceduralSkyMaterial:
	var env := node.environment
	var mat: ProceduralSkyMaterial = null
	if env.sky != null:
		mat = env.sky.sky_material as ProceduralSkyMaterial
	node.free()
	return mat


## The preset for a hand-built world, and the fill it brings.
##
## [b]The stock profiles first, because every document already shipped is drawn with them.[/b]
## The new fields default to what the rig drew before they existed (exposure 1, no grade, no
## fill), so a converted world looks exactly as it did; only a game that asks for `painted()`
## gets the new look.
func _painted() -> void:
	_section("painted: contrast for a world of flat colours")

	for stock in [DotLightProfile.high(), DotLightProfile.web(), DotLightProfile.low()]:
		var p := stock as DotLightProfile
		_check(p.exposure == 1.0 and p.contrast == 1.0 and p.saturation == 1.0
			and p.fill_energy == 0.0 and not p.ambient_occlusion,
			"a stock profile leaves exposure, the grade, the fill and occlusion as they were")

	var painted := DotLightProfile.painted()
	_check(painted.tonemap and painted.tonemap_white > DotLightProfile.high().tonemap_white,
		"painted is tone mapped with a longer shoulder, so a pale floor lands grey and not white")
	_check(painted.fill_energy > 0.0 and painted.ambient_energy < DotLightProfile.high().ambient_energy,
		"and trades some of the flat ambient for a fill, so shade keeps its edges")
	_check(painted.contrast > 1.0 and painted.saturation > 1.0, "with a little contrast and colour")
	_check(painted.exposure < 1.0, "and an exposure under 1.0")
	_check(painted.sun_shadows == DotLightProfile.high().sun_shadows or OS.has_feature("web"),
		"on this platform's own tier")

	var doc := DotLightDocument.from_dictionary({
		"sun": {"pitch_src": -50.0, "yaw_src": -35.0, "brightness": 380.0,
			"ambient_colour": [0.74, 0.78, 0.92]},
	})
	var root := Node3D.new()
	add_child(root)
	var sun := DotLightRig.apply(root, doc, painted)
	var fill: DirectionalLight3D = root.get_node_or_null("Fill")
	var env_node: WorldEnvironment = null
	for child in root.get_children():
		if child is WorldEnvironment:
			env_node = child
	_check(fill != null and fill != sun, "the rig adds a second light named Fill")
	if fill != null:
		var sun_travel := -Basis.from_euler(sun.rotation).z
		var fill_travel := -Basis.from_euler(fill.rotation).z
		_check(Vector2(sun_travel.x, sun_travel.z).dot(Vector2(fill_travel.x, fill_travel.z)) < 0.0,
			"shining across the ground the opposite way to the sun")
		_check(fill_travel.y < 0.0, "and downwards, from the sky")
		_check(not fill.shadow_enabled and fill.light_specular == 0.0,
			"with no shadow and no glint, so there is still one sun")
		_check(fill.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY,
			"and no disc in the sky, where a dim one is a dark dot")
		_check(fill.light_color.is_equal_approx(doc.ambient_colour) and is_equal_approx(fill.light_energy, painted.fill_energy),
			"in the shade's own colour, at the profile's energy")
	var env := env_node.environment if env_node != null else null
	_check(env != null and is_equal_approx(env.tonemap_exposure, painted.exposure),
		"the exposure reaches the environment")
	_check(env != null and env.adjustment_enabled and is_equal_approx(env.adjustment_contrast, painted.contrast)
		and is_equal_approx(env.adjustment_saturation, painted.saturation),
		"and so does the grade")
	root.queue_free()

	var stock_root := Node3D.new()
	add_child(stock_root)
	DotLightRig.apply(stock_root, doc)
	var stock_env: Environment = null
	for child in stock_root.get_children():
		if child is WorldEnvironment:
			stock_env = (child as WorldEnvironment).environment
	_check(stock_root.get_node_or_null("Fill") == null, "a stock profile adds no fill")
	_check(stock_env != null and not stock_env.adjustment_enabled and stock_env.tonemap_exposure == 1.0,
		"and no grade, at an exposure of 1")
	stock_root.queue_free()

	# A sun straight overhead has no opposite side; the fill still has to point somewhere real.
	var overhead := DotLightRig.fill(doc, DotLightRig.aim_along(Vector3.DOWN), painted)
	var up_travel := -Basis.from_euler(overhead.rotation).z
	_check(is_finite(up_travel.x) and up_travel.y < 0.0,
		"under an overhead sun the fill comes from a fixed side, not from NaN")
	overhead.free()
	_done()


func _zone() -> void:
	_section("the inspector half")

	var zone := DotLightZone.new()
	zone.sun_pitch = -70.0
	zone.fog_enabled = true
	zone.fog_end = 9000.0
	add_child(zone)

	_check(zone.sun != null, "a zone builds its sun on entering the tree")
	var doc := zone.document()
	_check(is_equal_approx(doc.sun_pitch, -70.0), "from its own exports")
	_check(doc.fog_enabled and is_equal_approx(doc.fog_end, 9000.0), "including the fog")

	# A path that does not resolve falls back to the exports rather than to nothing: a
	# black screen reads as a broken build, and the wrong lighting reads as the missing
	# file it is.
	zone.document_path = "res://no_such_lighting.json"
	_check(is_equal_approx(zone.document().sun_pitch, -70.0),
		"and a missing file falls back to them rather than to darkness")

	_check(not doc.has_sky_top, "and by default it names no sky_top, like a document")
	zone.sky_top_enabled = true
	zone.sky_top = Color(0.2, 0.4, 0.9)
	_check(zone.document().has_sky_top and zone.document().sky_top.is_equal_approx(Color(0.2, 0.4, 0.9)),
		"until its Sky group asks for one")
	_check(zone.describe_lines().size() >= 4, "and it can describe itself")
	_done()


## [b]A contact shade where a box meets the floor or another box.[/b] Painted worlds under
## Compatibility (no SSAO) stood every crate on the floor with no shade at its foot.
func _contact_shade() -> void:
	_section("contact shade: where a box meets a box")

	var floor_box := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, 0.0)), Vector3(10.0, 1.0, 10.0))
	var cube := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Vector3.ONE)
	var on_floor := DotContactShade.build([floor_box, cube])
	_check(int(on_floor["bands"]) == 8 and int(on_floor["corners"]) == 4,
		"a cube on a floor: a band each side of each foot edge and a square at each corner (%d, %d)" % [on_floor["bands"], on_floor["corners"]])
	var darkest := 1.0
	var highest := -INF
	var widest := 0.0
	for i in range((on_floor["vertices"] as PackedVector3Array).size()):
		var at: Vector3 = on_floor["vertices"][i]
		darkest = minf(darkest, (on_floor["colors"][i] as Color).r)
		highest = maxf(highest, at.y)
		widest = maxf(widest, maxf(absf(at.x), absf(at.z)))
	_check(is_equal_approx(darkest, 1.0 - DotContactShade.STRENGTH),
		"as dark as STRENGTH at the crease (%.2f)" % darkest)
	_check(highest < DotContactShade.WIDTH + 0.01 and widest < 0.5 + DotContactShade.WIDTH + 0.01,
		"reaching WIDTH up the cube and out across the floor, no further")

	var tile_a := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(-1.0, 0.0, 0.0)), Vector3(2.0, 0.2, 2.0))
	var tile_b := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)), Vector3(2.0, 0.2, 2.0))
	_check(int(DotContactShade.build([tile_a, tile_b])["bands"]) == 0,
		"two floor tiles side by side make no crease")

	var sunk := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(4.0, 3.0, 0.2))
	_check(int(DotContactShade.build([floor_box, sunk])["bands"]) == 8,
		"a wall sunk into the floor makes the same crease as one standing on it")

	var rug := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.005, 0.0)), Vector3(2.0, 0.01, 1.0))
	_check(int(DotContactShade.build([floor_box, rug])["bands"]) == 0, "a rug makes no ring")

	var on_cube := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.25, 0.0)), Vector3(0.5, 0.5, 0.5))
	var stacked := DotContactShade.build([cube, on_cube])
	_check(int(stacked["bands"]) == 8 and int(stacked["creases"]) == 2,
		"a box on a box shades the top it stands on")

	var ledge := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(4.8, 0.5, 0.0)), Vector3.ONE)
	# Overhanging the edge: the floor's top is shaded only as far as it goes (the underside of
	# the overhang and the floor's side under it are creases too, and are shaded).
	var past := 0.0
	for at: Vector3 in DotContactShade.build([floor_box, ledge])["vertices"]:
		if at.y > 0.0 and at.y < 0.01:
			past = maxf(past, at.x)
	_check(past > 4.0 and past <= 5.0 + 0.001, "a box over the floor's edge shades the floor only as far as it goes (%.3f)" % past)

	var yawed := DotContactShade.box(Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(0.0, 0.5, 0.0)), Vector3.ONE)
	_check(int(DotContactShade.build([floor_box, yawed])["bands"]) >= 4, "a box turned on the floor is shaded too")
	var tilted := DotContactShade.box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20.0)), Vector3(0.0, 0.5, 0.0)), Vector3.ONE)
	_check(int(DotContactShade.build([floor_box, tilted])["bands"]) == 0, "and a tilted one is left alone")

	var glass := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Vector3.ONE, false, false)
	var prop := DotContactShade.box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)), Vector3.ONE, true, false)
	var prop_shade := DotContactShade.build([floor_box, prop])
	_check(int(DotContactShade.build([floor_box, glass])["bands"]) == 0
		and int(prop_shade["bands"]) == 4
		and (prop_shade["vertices"] as PackedVector3Array).size() < (on_floor["vertices"] as PackedVector3Array).size(),
		"a box that does not cast makes none; one not shaded darkens the floor and draws nothing on itself")

	_check(DotContactShade.mesh([cube]) == null
		and int(DotContactShade.build([floor_box, cube, {"size": Vector3.ONE}, [Transform3D.IDENTITY, Vector3(NAN, 1.0, 1.0)], 7])["bands"]) == 8,
		"nothing touching is no mesh, and a malformed entry is skipped")
	var node := DotContactShade.node([floor_box, cube])
	var shader := (node.material_override as ShaderMaterial).shader
	_check(node.mesh != null and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and shader.code.contains("blend_mix") and shader.code.contains("ALBEDO = vec3(0.0)") and shader.code.contains("unshaded"),
		"the node is one unshaded mesh, black at the grey's alpha, casting no shadow")
	node.free()
	_done()


func _sheet_arrays(faces: Array) -> Array:
	var sheet := DotLightmapSheet.new()
	for f: Array in faces:
		sheet.face(f[0], f[1], f[2], f[3], f[4])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	sheet.commit(tool)
	return [sheet, tool.commit_to_arrays()]


func _bake() -> void:
	_section("baked light: the sheet, the fingerprint, the refusals")

	# A 4 x 3 m wall facing +z, a 1 x 1 m floor tile and a sliver (a 2 cm kerb side).
	var faces := [
		[Vector3(0, 0, 0), Vector3(0, 3, 0), Vector3(4, 3, 0), Vector3(4, 0, 0), Vector3.BACK],
		[Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3.UP],
		[Vector3(0, 0, 2), Vector3(0, 0.02, 2), Vector3(5, 0.02, 2), Vector3(5, 0, 2), Vector3.BACK],
	]
	var made := _sheet_arrays(faces)
	var sheet: DotLightmapSheet = made[0]
	var arrays: Array = made[1]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	_check(verts.size() == 18 and uv2.size() == 18, "two triangles a face, every vertex with a UV2 (%d, %d)" % [verts.size(), uv2.size()])
	var inside := true
	for uv in uv2:
		inside = inside and uv.x >= 0.0 and uv.y >= 0.0 and uv.x <= 1.0 and uv.y <= 1.0
	_check(inside and sheet.size.x > 0 and sheet.size.y > 0, "inside the sheet (%dx%d texels)" % [sheet.size.x, sheet.size.y])
	_check(verts[0] == faces[0][0] and verts[1] == faces[0][2] and verts[2] == faces[0][1],
		"written a, c, b: the box builders' winding")

	# Each face's rectangle, in texels: no two overlap, and the wall is 16 x 12 at 0.25 m.
	var rects: Array[Rect2] = []
	for f in 3:
		var r := Rect2(uv2[f * 6] * Vector2(sheet.size), Vector2.ZERO)
		for k in 6:
			r = r.expand(uv2[f * 6 + k] * Vector2(sheet.size))
		rects.append(r)
	_check(rects[0].size.is_equal_approx(Vector2(16, 12)), "a texel is a quarter metre (the wall is %s)" % rects[0].size)
	_check(not rects[0].intersects(rects[1]) and not rects[0].intersects(rects[2]) and not rects[1].intersects(rects[2]),
		"no two faces share a texel")
	_check(rects[2].size.y >= 1.0, "a 2 cm sliver still gets a texel")
	var pad := float(sheet.padding) - 0.01
	_check(not rects[0].grow(pad).intersects(rects[1].grow(pad)) and not rects[0].grow(pad).intersects(rects[2].grow(pad))
		and not rects[1].grow(pad).intersects(rects[2].grow(pad)), "with padding texels between any two")
	var again: Array = _sheet_arrays(faces)[1]
	_check(again[Mesh.ARRAY_TEX_UV2] == arrays[Mesh.ARRAY_TEX_UV2], "the same faces give the same sheet, every time")

	var fp := DotLightBake.fingerprint({"boxes": [[1, 2, 3]], "lights": []})
	_check(fp.length() == 64 and fp == DotLightBake.fingerprint({"lights": [], "boxes": [[1, 2, 3]]}),
		"a fingerprint is a sha256, the same whatever order the keys came in")
	_check(fp != DotLightBake.fingerprint({"boxes": [[1, 2, 3.5]], "lights": []}), "and a moved box is a different one")

	var host := Node3D.new()
	var refused := DotLightBake.attach(host, "res://nowhere.res", fp)
	_check(not refused.ok and refused.error.code == (DotError.CODE_UNSUPPORTED if not DotLightBake.can_draw() else DotError.CODE_IO)
		and host.get_child_count() == 0,
		"headless, nothing is attached (%s), and the world is left as it was" % (refused.error.code if refused.error != null else "ok"))
	var none := DotLightBake.store(null, fp, "user://x.res")
	_check(not none.ok and none.error.code == DotError.CODE_INVALID, "storing nothing is refused")
	host.free()
	_done()
