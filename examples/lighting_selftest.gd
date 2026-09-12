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

const EXPECTED_SECTIONS := 6
const EXPECTED_CHECKS := 55

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
	_zone()
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

	_check(zone.describe_lines().size() >= 4, "and it can describe itself")
	_done()
