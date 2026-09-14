class_name DotLightZone
extends Node3D

## A lighting document, placed in a scene and applied when it enters the tree.
##
## The inspector half of the addon, for a hand-built world: point it at a JSON file or fill
## the exports in and it builds the same sun and [Environment] [DotLightRig] would.
## A world built from an imported map does not need this — it calls [DotLightRig.apply]
## with the document its manifest already carries — and that is the usual case here.
##
## [b]The node is not the lighting.[/b] It makes the lighting and steps out of the way, so
## nothing in a scene holds a reference to something a map change is about to replace.

const CHANNEL := "lighting"

## A JSON file holding a lighting document. Overrides the exports below when it loads.
@export_file("*.json") var document_path: String = ""

## What this machine draws. Null takes [method DotLightProfile.high].
@export var profile: DotLightProfile = null

@export_group("Sun")
@export var sun_enabled: bool = true
@export_range(-90.0, 90.0, 0.1) var sun_pitch: float = -45.0
@export_range(-360.0, 360.0, 0.1) var sun_yaw: float = 0.0
@export var sun_colour: Color = Color(1.0, 0.97, 0.9)
@export_range(0.0, 2000.0, 1.0) var sun_brightness: float = 200.0
@export var ambient_colour: Color = Color(0.6, 0.6, 0.65)

@export_group("Fog")
@export var fog_enabled: bool = false
@export var fog_colour: Color = Color(0.6, 0.7, 0.8)
@export_range(0.0, 100000.0, 1.0) var fog_start: float = 4000.0
@export_range(0.0, 100000.0, 1.0) var fog_end: float = 20000.0

## The sun this built, or null before it entered the tree.
var sun: DirectionalLight3D = null


func _ready() -> void:
	sun = DotLightRig.apply(self, document(), profile)


## The document this node describes, from its file if it has a readable one and from its
## exports otherwise.
##
## [b]A file that fails to parse falls back to the exports rather than to nothing.[/b] A
## world with no lighting at all is a black screen, which reads as a broken build; a world
## with the inspector's lighting is visibly not what was asked for, which reads as the
## missing file it is.
func document() -> DotLightDocument:
	if not document_path.is_empty() and FileAccess.file_exists(document_path):
		var text := FileAccess.get_file_as_string(document_path)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return DotLightDocument.from_dictionary(parsed)
		# DotLog, not push_warning: this is a runtime condition about content, not a
		# programmer error, and push_warning drags an engine backtrace into a log where
		# the interesting fact is the path. It also means a server shipping its log
		# somewhere actually sees this one.
		DotLog.warn(
			CHANNEL,
			"the lighting document would not parse; using the exported defaults",
			{"path": document_path}
		)

	var doc := DotLightDocument.new()
	doc.has_sun = sun_enabled
	doc.sun_pitch = sun_pitch
	doc.sun_yaw = sun_yaw
	doc.sun_colour = sun_colour
	doc.sun_brightness = sun_brightness
	doc.has_ambient = true
	doc.ambient_colour = ambient_colour
	doc.fog_enabled = fog_enabled
	doc.fog_colour = fog_colour
	doc.fog_start = fog_start
	doc.fog_end = fog_end
	return doc


func describe_lines() -> PackedStringArray:
	return document().describe_lines()
