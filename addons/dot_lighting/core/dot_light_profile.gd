class_name DotLightProfile
extends Resource

## How much rendering a machine is asked to do, and what it costs.
##
## Separate from the document on purpose: the document is what the WORLD is, the same on every
## machine; a profile is what THIS machine draws of it.

## Tone mapping costs nothing, so it is on at every tier.
@export var tonemap: bool = true

## Roughly filmic. Higher is a longer shoulder and a darker midtone.
@export_range(0.5, 4.0, 0.05) var tonemap_white: float = 1.6

@export var glow: bool = true
@export_range(0.0, 2.0, 0.01) var glow_intensity: float = 0.55

## Below this a bright pixel does not bloom.
## Under 1.0 is real: a baked 8-bit lightmap has nothing above white, so a lower threshold
## makes strip lights and signage glow. Raise it above 1.0 for emissive materials.
@export_range(0.0, 4.0, 0.01) var glow_threshold: float = 0.85

@export var fog: bool = true

## Draw a sky behind the world, rather than a flat colour.
##
## On everywhere: a flat background fills the same pixels. It is the sky the world's own numbers
## describe, not the one it named ([member DotLightDocument.sky_name]).
@export var sky: bool = true

## The sky continues below the horizon, instead of turning into dark ground.
##
## Off by default: an enclosed level has geometry under its horizon. On for a world that
## floats in its sky, where a dark lower half looks like a missing floor.
@export var sky_below_horizon: bool = false

## Shadows cost a depth pass per light and are the first thing a weak machine should lose.
@export var sun_shadows: bool = true

## What a brightness of this much means an energy of 1.0.
## See [member DotLightDocument.sun_brightness] for why this is a division.
@export_range(1.0, 2000.0, 1.0) var brightness_reference: float = 200.0

@export_range(0.0, 8.0, 0.01) var ambient_energy: float = 0.8

## Brightness going into the tone map. 1.0 is untouched.
##
## A pale world's floor comes down here, not by dimming the sun: exposure moves lit and shade together.
@export_range(0.1, 4.0, 0.01) var exposure: float = 1.0

## A grade over the tone-mapped picture: the renderer's adjustment pass, which the
## Compatibility renderer has as well. 1.0 and 1.0 leave the pass switched off.
@export_range(0.5, 2.0, 0.01) var contrast: float = 1.0
@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0

## A second, shadowless light from the side of the sky the sun is not on. 0 is none.
## The shade's shape where nothing else can draw it: ambient lights every face alike, and the
## Compatibility renderer has no AO. A dim opposite-side light in the ambient's colour keeps a
## box's corners, casts no shadow, and is off for a baked world.
@export_range(0.0, 2.0, 0.01) var fill_energy: float = 0.0

## Degrees above the horizon the fill comes from.
@export_range(5.0, 85.0, 1.0) var fill_elevation: float = 35.0

## Screen-space ambient occlusion, where the renderer has it (Forward+). Compatibility does
## not, and on it this asks for nothing; [member fill_energy] is what reads there.
@export var ambient_occlusion: bool = false


## Whether this process draws with the Compatibility renderer: the client shell's, on every
## platform, and the only one in a browser.
static func is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## A hand-built world of painted surfaces under a sun: this platform's tier, graded for
## A hand-built world of painted surfaces under a sun. A baked world takes [method high] or
## [method web] as they are; a painted one has only this light to read a shape by.
##
## Filmic white 3.0, a fill and a lower ambient, a little contrast and saturation, and AO where
## available. Under Compatibility the sun and fill are divided down and the exposure lowered, as
## it clips where Forward+ rolls off. A game changes the rest afterwards; everything is a field.
static func painted() -> DotLightProfile:
	var p := for_platform()
	p.tonemap_white = 3.0
	p.contrast = 1.12
	p.saturation = 1.15
	p.ambient_occlusion = true
	if is_compatibility():
		p.brightness_reference = 700.0
		p.ambient_energy = 0.3
		p.fill_energy = 0.35
		p.exposure = 0.85
	else:
		p.ambient_energy = 0.45
		p.fill_energy = 0.4
		p.exposure = 0.95
	return p


## The stock profile for this machine: a phone (native, or a phone's browser) gets [method low],
## a desktop browser [method web], everything else [method high]. Games call this and never
## test the platform themselves.
static func for_platform() -> DotLightProfile:
	if DotPlatform.is_mobile() or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return low()
	if DotPlatform.is_web():
		return web()
	return high()


## Everything on. A desktop.
static func high() -> DotLightProfile:
	return DotLightProfile.new()


## No glow and no shadows: two full-screen costs a weak GPU should not pay.
## The tone map stays: it is free, and switching it off changes the look for nothing saved.
static func low() -> DotLightProfile:
	var p := DotLightProfile.new()
	p.glow = false
	p.sun_shadows = false
	return p


## What a browser gets by default.
## Glow survives and shadows do not: on the web the shadow pass scales with geometry in the
## frame, glow is a fixed screen cost.
static func web() -> DotLightProfile:
	var p := DotLightProfile.new()
	p.sun_shadows = false
	return p
