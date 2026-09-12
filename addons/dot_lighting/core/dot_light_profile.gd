class_name DotLightProfile
extends Resource

## How much rendering a machine is asked to do, and what it costs.
##
## [b]Separate from the document on purpose.[/b] A [DotLightDocument] says what the WORLD
## is — where its sun is, what colour its fog is — and is the same on every machine that
## loads that world. A profile says what THIS machine will draw of it, and is different on
## a desktop and in a browser. Folding the two together is how a map ends up looking
## different because somebody turned their settings down, which for a world whose geometry
## is read for speed is not a cosmetic difference.
##
## The two halves compose: a low profile draws the same sun in the same place with the
## glow turned off.

## Tone mapping is the largest single change to how a scene reads and it costs nothing,
## so it is on at every tier including the lowest.
@export var tonemap: bool = true

## Roughly filmic. Higher is a longer shoulder and a darker midtone.
@export_range(0.5, 4.0, 0.05) var tonemap_white: float = 1.6

@export var glow: bool = true
@export_range(0.0, 2.0, 0.01) var glow_intensity: float = 0.55

## Below this a bright pixel does not bloom.
##
## [b]Under 1.0 is a real setting and not a mistake.[/b] A world lit by a baked 8-bit
## lightmap has nothing above white in it anywhere, so an HDR threshold finds nothing to
## glow at, ever. Lower it and the brightest surfaces — the strip lights and signage a
## level is signposted with — read as light rather than as paint. Raise it above 1.0 for a
## world whose materials genuinely emit.
@export_range(0.0, 4.0, 0.01) var glow_threshold: float = 0.85

@export var fog: bool = true

## Shadows cost a depth pass per light and are the first thing a weak machine should lose.
@export var sun_shadows: bool = true

## What a brightness of this much means an energy of 1.0.
##
## See [member DotLightDocument.sun_brightness] for why this is a division rather than a
## multiplication.
@export_range(1.0, 2000.0, 1.0) var brightness_reference: float = 200.0

@export_range(0.0, 8.0, 0.01) var ambient_energy: float = 0.8


## Everything on. A desktop.
static func high() -> DotLightProfile:
	return DotLightProfile.new()


## No glow and no shadows: two full-screen costs a weak GPU should not pay.
##
## The tone map stays, because it is a curve applied to a pixel that was going to be
## written anyway and switching it off changes what the world looks like for nothing
## saved.
static func low() -> DotLightProfile:
	var p := DotLightProfile.new()
	p.glow = false
	p.sun_shadows = false
	return p


## What a browser gets by default.
##
## Glow survives and shadows do not. On the web the shadow pass is the expensive half —
## it scales with how much geometry is in the frame, which on a large level is all of it —
## while glow is a fixed cost in screen pixels that a phone-class GPU handles. Dropping
## the cheap one first is the mistake this exists to avoid.
static func web() -> DotLightProfile:
	var p := DotLightProfile.new()
	p.sun_shadows = false
	return p
