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

## Draw a sky behind the world, rather than a flat colour.
##
## [b]On everywhere, because the flat colour is not cheaper in any way that matters.[/b]
## A procedural sky is one shader over the pixels no geometry covered, which in an
## enclosed level is almost none of them; the flat background it replaces still had to
## fill those same pixels. What it buys is that the brightest thing in an outdoor frame
## stops being a single flat rectangle with a hard edge along every ridge line.
##
## It is NOT the sky the source world named — see [member DotLightDocument.sky_name],
## which is a texture set that lives in that world's own game and was never inside the
## file. This is the sky that world's own numbers describe: its sun, at its angle, in
## its colour, over its fog.
@export var sky: bool = true

## The sky continues below the horizon, instead of turning into dark ground.
##
## [b]Off by default, because an enclosed level has geometry under its horizon[/b] and a
## bright band there reads as a hole. On for a world that FLOATS inside its sky -- the
## platforms-in-a-skybox shape every ride-the-ramp and jump-the-gap map is built in --
## where the source world's sky surrounded the player on all sides and a dark lower half
## turns every glance down between two platforms into looking at a floor that is not there.
@export var sky_below_horizon: bool = false

## Shadows cost a depth pass per light and are the first thing a weak machine should lose.
@export var sun_shadows: bool = true

## What a brightness of this much means an energy of 1.0.
##
## See [member DotLightDocument.sun_brightness] for why this is a division rather than a
## multiplication.
@export_range(1.0, 2000.0, 1.0) var brightness_reference: float = 200.0

@export_range(0.0, 8.0, 0.01) var ambient_energy: float = 0.8

## Brightness going into the tone map. 1.0 is untouched.
##
## [b]A pale world's floor comes down here, not by dimming the sun.[/b] The sun against the
## ambient is the contrast between a lit face and a shaded one; the exposure moves both
## together, so the floor stops being white without the shade getting any closer to it.
@export_range(0.1, 4.0, 0.01) var exposure: float = 1.0

## A grade over the tone-mapped picture: the renderer's adjustment pass, which the
## Compatibility renderer has as well. 1.0 and 1.0 leave the pass switched off.
@export_range(0.5, 2.0, 0.01) var contrast: float = 1.0
@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0

## A second, shadowless light from the side of the sky the sun is not on. 0 is none.
##
## [b]The shade's shape, where nothing else can draw it.[/b] An ambient colour lights every
## face the same however it points, so in shade a box is one flat colour with no edges and a
## step reads as a ramp. Ambient occlusion would separate them and the Compatibility renderer
## (the client shell's, on every platform) has none. A dim light from the opposite side does
## it for one directional light's cost: faces turned towards it are a step lighter than faces
## turned away, and the shade keeps its corners. It is in the ambient's colour, so it reads as
## more sky rather than as a second sun, and it casts no shadow, so there is still one
## direction shadows fall in. Off for a baked world, whose shade is in its lightmap already.
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
## contrast and matched to the renderer that draws it.
##
## [b]For a world built from flat colours, not one converted with its light baked in.[/b] A
## baked world's shade is in its lightmap and takes [method high] or [method web] as they
## are. A painted one has nothing but this light to read a shape by, and the stock profile
## (a filmic white of 1.6, an ambient at 0.8 of the sun's level) draws it pale: every map the
## family built that way came out near white, with the shade a step from the sun side.
##
## What this changes, each for a reason a frame showed:
## [br]- A filmic white of 3.0: a longer shoulder, so a pale floor in full sun lands a light
##   grey instead of white, and a saturated paint keeps its colour in the light.
## [br]- A fill ([member fill_energy]) and a lower ambient: the same total light in the shade,
##   but faces turned different ways are different shades, so a box keeps its edges.
## [br]- A little contrast and saturation, so a pastel is a colour and not a tint of white.
## [br]- Ambient occlusion where the renderer has it.
## [br]- [b]Under Compatibility, the light itself is turned down.[/b] Forward+ lights into an
##   HDR buffer and the tone map rolls a bright face back under white; Compatibility has no
##   headroom over white and clips it first, so the sun and the fill are divided down and the
##   exposure lowered to land both renderers' frames within a shade of each other. The world
##   is the same; this is what each renderer can draw of it.
##
## A game changes what it needs afterwards (shadows on in a browser for a small map, the sky
## under the horizon for a floating one); everything here is a field.
static func painted() -> DotLightProfile:
	var p := web() if OS.has_feature("web") else high()
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
