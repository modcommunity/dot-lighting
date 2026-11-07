class_name DotLightDocument
extends RefCounted

## What a world's lighting is, as data rather than as a scene.
##
## A document, not a node, so lighting can come from a map file, a content pack or a server.
## Every consumer here takes one of these.
##
## [codeblock]
## var doc := DotLightDocument.from_dictionary(manifest.get("lighting", {}))
## DotLightRig.apply(world_root, doc)
## [/codeblock]
##
## Every field is optional and absent is not zero ([member has_sun] and friends): "the map said
## nothing" and "the map said black" are different instructions.

## Degrees. The sun's own pitch and yaw, in the source world's convention.
##
## Stored unconverted; [method DotLightRig.sun_direction] converts the direction vector once.
var sun_pitch: float = 0.0
var sun_yaw: float = 0.0
var has_sun: bool = false

## Linear 0..1, as a colour with no intensity in it.
var sun_colour: Color = Color.WHITE

## What the source world's own light compiler was given.
##
## Not a multiplier or a 0..1 fraction: `_light`'s fourth component, 20 to 600 across maps.
## Carried as it stands; the rig decides what to do with it.
var sun_brightness: float = 0.0

## Half-angle of the sun disc, in degrees. Softer shadows on a hazy map.
var sun_spread: float = 0.0

var ambient_colour: Color = Color(0.6, 0.6, 0.65)
var has_ambient: bool = false

var fog_enabled: bool = false
var fog_colour: Color = Color(0.6, 0.7, 0.8)
## Source units, converted by the consumer at its own boundary.
var fog_start: float = 0.0
var fog_end: float = 0.0

## How opaque the fog is allowed to become at [member fog_end], 0..1.
##
## The source world's own maximum, and 1.0 is a default: a world saying 0.4 wants distance
## tinted, not erased.
var fog_max_density: float = 1.0

## The name of the sky the source world used. Carried for a consumer that has one.
var sky_name: String = ""

## The colour of the top of the sky, when the world names one apart from its ambient.
##
## Optional; absent keeps the old sky, with the zenith in [member ambient_colour]. Naming it
## lets a world whose ambient was chosen for the shade have a bluer sky. Written as
## `"sky_top": [r, g, b]` beside `sky_name`; [member has_sky_top] tells absent from black.
var sky_top: Color = Color(0.3, 0.56, 0.96)
var has_sky_top: bool = false

## How many lights were compiled into the baked lighting.
##
## Not for placing: those lights are already in the lightmap, and placing them lights the
## world twice.
var baked_light_count: int = 0


static func from_dictionary(data: Dictionary) -> DotLightDocument:
	var doc := DotLightDocument.new()
	if data.is_empty():
		return doc

	var sun: Dictionary = data.get("sun", {})
	if sun.has("pitch_src") or sun.has("yaw_src"):
		doc.has_sun = true
		doc.sun_pitch = float(sun.get("pitch_src", 0.0))
		doc.sun_yaw = float(sun.get("yaw_src", 0.0))
	if sun.has("colour"):
		doc.sun_colour = _colour(sun["colour"], Color.WHITE)
	if sun.has("brightness"):
		doc.sun_brightness = float(sun["brightness"])
	if sun.has("spread_degrees"):
		doc.sun_spread = float(sun["spread_degrees"])
	if sun.has("ambient_colour"):
		doc.has_ambient = true
		doc.ambient_colour = _colour(sun["ambient_colour"], doc.ambient_colour)

	var fog: Dictionary = data.get("fog", {})
	if not fog.is_empty():
		doc.fog_enabled = bool(fog.get("enabled", false))
		doc.fog_colour = _colour(fog.get("colour", []), doc.fog_colour)
		doc.fog_start = float(fog.get("start", 0.0))
		doc.fog_end = float(fog.get("end", 0.0))
		doc.fog_max_density = clampf(float(fog.get("max_density", 1.0)), 0.0, 1.0)

	doc.sky_name = str(data.get("sky_name", ""))
	# Only a real colour counts; anything else is absent, so a typo keeps today's sky.
	var top: Variant = data.get("sky_top", null)
	if (top is Array and (top as Array).size() >= 3) or top is Color:
		doc.has_sky_top = true
		doc.sky_top = _colour(top, doc.sky_top)
	doc.baked_light_count = int(data.get("baked_light_count", 0))
	return doc


func to_dictionary() -> Dictionary:
	var out: Dictionary = {}
	if has_sun or sun_brightness > 0.0:
		var sun: Dictionary = {
			"pitch_src": sun_pitch,
			"yaw_src": sun_yaw,
			"colour": [sun_colour.r, sun_colour.g, sun_colour.b],
			"brightness": sun_brightness,
		}
		if sun_spread > 0.0:
			sun["spread_degrees"] = sun_spread
		if has_ambient:
			sun["ambient_colour"] = [ambient_colour.r, ambient_colour.g, ambient_colour.b]
		out["sun"] = sun
	if fog_enabled or fog_end > 0.0:
		out["fog"] = {
			"enabled": fog_enabled,
			"colour": [fog_colour.r, fog_colour.g, fog_colour.b],
			"start": fog_start,
			"end": fog_end,
			"max_density": fog_max_density,
		}
	if not sky_name.is_empty():
		out["sky_name"] = sky_name
	if has_sky_top:
		out["sky_top"] = [sky_top.r, sky_top.g, sky_top.b]
	out["baked_light_count"] = baked_light_count
	return out


static func _colour(value: Variant, fallback: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]))
	if value is Color:
		return value
	return fallback


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if has_sun:
		out.append("sun       pitch %.0f yaw %.0f, %s, brightness %.0f" % [
			sun_pitch, sun_yaw, sun_colour.to_html(false), sun_brightness])
	else:
		out.append("sun       none declared")
	if fog_enabled:
		out.append("fog       %s, %d to %d units"
			% [fog_colour.to_html(false), int(fog_start), int(fog_end)])
	else:
		out.append("fog       off")
	out.append("sky       %s, top %s" % [
		sky_name if not sky_name.is_empty() else "-",
		sky_top.to_html(false) if has_sky_top else "not named"])
	out.append("baked     %d lights compiled into the lighting" % baked_light_count)
	return out
