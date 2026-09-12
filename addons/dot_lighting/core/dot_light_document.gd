class_name DotLightDocument
extends RefCounted

## What a world's lighting is, as data rather than as a scene.
##
## [b]The whole addon exists because this is a document and not a node.[/b] Lighting that
## lives in a `.tscn` can only ship with the build; lighting that is a dictionary can come
## out of a map file, a content pack downloaded at runtime, a server's config, or a level
## editor — and a game that reads one reads all four. Every consumer here takes one of
## these and nothing else.
##
## [codeblock]
## var doc := DotLightDocument.from_dictionary(manifest.get("lighting", {}))
## DotLightRig.apply(world_root, doc)
## [/codeblock]
##
## [b]Every field is optional and absent is not zero.[/b] A document with no sun keeps
## whatever default the consumer holds; a document with a sun and no colour gets a white
## one. That distinction is the reason [member has_sun] exists rather than callers testing
## [member sun_colour] against something — "the map said nothing" and "the map said black"
## are different instructions and a renderer must not confuse them.

## Degrees. The sun's own pitch and yaw, in the source world's convention.
##
## [b]Stored unconverted, deliberately.[/b] A yaw in a Z-up left-handed world is not a yaw
## in a Y-up right-handed one, and converting the two angles separately is how a sun ends
## up rising in the north. [method DotLightRig.sun_direction] does the conversion on the
## direction vector, once, where the handedness is written down.
var sun_pitch: float = 0.0
var sun_yaw: float = 0.0
var has_sun: bool = false

## Linear 0..1, as a colour with no intensity in it.
var sun_colour: Color = Color.WHITE

## What the source world's own light compiler was given.
##
## [b]Not a multiplier and not a 0..1 fraction.[/b] Source's `light_environment` writes
## this as the fourth component of `_light` and it ranges from 20 to 600 across eight
## ordinary maps, so handing it to [member Light3D.light_energy] gives a sun six hundred
## times too bright on one map and twenty times on the next. It is carried as it stands
## and interpreted by the rig, because what a renderer should do with 600 is a renderer's
## decision and folding it in here would throw the colour away with it.
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

## The name of the sky the source world used. Carried for a consumer that has one.
var sky_name: String = ""

## How many lights were compiled into the baked lighting.
##
## Not for placing: those lights are already in the lightmap and placing them again lights
## the world twice. It is here so a tool can say "this map has 148 lights in it and none of
## them are dynamic" out loud, and so a renderer that ever wants a glow around them knows
## they exist.
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

	doc.sky_name = str(data.get("sky_name", ""))
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
		}
	if not sky_name.is_empty():
		out["sky_name"] = sky_name
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
	out.append("sky       %s" % (sky_name if not sky_name.is_empty() else "-"))
	out.append("baked     %d lights compiled into the lighting" % baked_light_count)
	return out
