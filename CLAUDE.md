# dot-lighting

A world's lighting as a document rather than as a scene: `DotLightDocument` is a dictionary in and a dictionary out (sun, ambient, fog, sky, baked-light count), `DotLightRig` turns one into a sun and an `Environment`, and `DotLightProfile` says how much of it this machine draws. An imported map carries its lighting in its manifest and the game applies it; game-g2gfast applies imported maps' lighting this way, and game-arena gives each built-in map a document of its own.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_lighting/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

## Layout

| Path | What |
| --- | --- |
| `core/dot_light_document.gd` | `DotLightDocument`: what the world is; `from_dictionary`, `to_dictionary`, `has_sun`, `has_ambient`, `sky_name`, `sky_top`/`has_sky_top`, `baked_light_count` |
| `core/dot_light_profile.gd` | `DotLightProfile`: what this machine draws (tonemap, exposure, grade, fill, glow, fog, sky, shadows, occlusion); `high()`, `low()`, `web()` for baked worlds, `painted()` for hand-built ones; `is_compatibility()` |
| `runtime/dot_light_rig.gd` | `DotLightRig`: `apply`, `environment`, `fill`, the procedural sky, `METRES_PER_UNIT` and `metres()` |
| `runtime/dot_contact_shade.gd` | `DotContactShade`: fake ambient occlusion for a world of boxes; `box`, `node`, `mesh`, `material`, `build` |
| `runtime/dot_light_zone.gd` | `DotLightZone`: the inspector half for a hand-built world; builds the lighting on `_ready` and steps aside |
| `dot_lighting_api.gd` | the API level (`DotAddonApi`); bump `LEVEL` for anything a game could newly call, with a comment line saying what |
| `examples/lighting_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/dot_lighting/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/lighting_selftest.tscn`. The suite counts sections run to their last line as well as checks; keep that when adding one.

## Rules, and why

- **Not part of dot-fx.** dot-fx's invariant is "safe to drop", and lighting fails it: a world whose glow got budgeted out is the wrong world, and a player judging a surface's speed by how fast its pattern goes past is reading something lighting decides the legibility of. An effect is an event; lighting is continuous world state. It is not dot-effects either (status effects, which are simulation; this cannot touch the simulation).
- **The document is the point.** Lighting built into a `.tscn` can only ship with the build; a dictionary lets a converted map carry its own, with nothing in between knowing about either end.
- **Absent is not zero.** `has_sun` and `has_ambient` tell "the map said nothing" from "the map said black". Those are different instructions and the suite asserts both.
- **The document and the profile stay separate.** The document is the same on every machine; the profile differs between a desktop and a browser. Folding them together makes a map look different because somebody turned their settings down. Tone mapping is on at every tier.
- **`METRES_PER_UNIT` (0.01905) is duplicated on purpose.** The same figure lives in game-g2gfast's `g2g_units.gd` and game-arena's `arena_bsp_map.gd`. The one-place rule is per project; this addon depends on dot-core alone, and importing a game's unit class to read a fog distance would be a dependency on the game. A caller with its own conversion passes metres in.
- **The sun does not light a baked world's surfaces.** They are unshaded (the lightmap is their lighting), so the sun lights characters and props and the post-processing changes the world. "The sun does not seem to do anything" on a baked map is working as intended.
- **`sky_name` is carried, never drawn.** It names a texture set inside the game the world was authored for, which is not ours to copy. The rig draws a procedural sky from the world's own numbers instead: fog colour as the horizon, ambient as the top, the sun at its own angle.
- **`sky_top` is optional and absent draws the old sky exactly.** A converted world's ambient was measured from its sky, so the zenith in the ambient colour is right there; a world whose ambient was chosen for the shade names its zenith as a top-level `"sky_top": [r, g, b]`, and only what is drawn changes, never the ambient light. A malformed value is absent, not a default colour. The suite's `sky_top` section asserts both halves.
- **A hand-built world takes `painted()`; a baked one takes `high()`/`web()`.** Painted worlds were near white under the stock numbers (a filmic white of 1.6, an ambient at 0.8 of the sun). `painted()` lengthens the shoulder, lowers the exposure, grades, and trades ambient for a fill. Its numbers were set by rendering a painted map in both renderers and measuring the sunlit floor and the shade (README, "A hand-built world").
- **New profile fields default to the old drawing.** `exposure` 1, `contrast`/`saturation` 1 (pass off), `fill_energy` 0, `ambient_occlusion` off, so a converted world never changes look because a field was added. The suite's `painted` section asserts the stock tiers.
- **The Compatibility renderer clips before it tone maps.** A profile's light numbers are per renderer (`is_compatibility()`); one set tuned under Forward+ comes out white under the client shell, which draws Compatibility everywhere.
- **`contrast` pivots at mid grey, so it crushes dark albedo in shade.** At `painted()`'s 1.12 a dark trunk or chair in shade goes to black; a world with dark props lowers it (mg-prop-hunt and game-hide-n-seek use 1.04). Check the near-black share of a frame, not only the blown one.
- **The fill casts no shadow, has no specular and draws no sky disc.** There is still one sun: one shadow direction, one highlight. It is in the ambient colour so it reads as more sky.
- **A painted world of boxes takes `DotContactShade`** under Compatibility (no SSAO): its own band mesh, never vertex colours on the game's two-triangle faces (a gradient the height of the wall). Black at the shade's alpha, never `blend_mul` (the Compatibility glow buffer is scaled down: every band came out black). A crease is drawn only on the face it lies on; the other face's band comes from the swapped pair (drawing both doubled it). [README](README.md#a-contact-shade-where-boxes-meet-dotcontactshade)
- **`baked_light_count` exists so nobody places those lights again** and lights the world twice.

## Not here yet

- **The contact shade is in mg-prop-hunt's maps only.** game-arena (its built-in maps were the first target; another session held it), game-playground, game-hide-n-seek, mg-deathrun and mg-wipeout are not converted yet: nightly `look-fake-ao-2`.

- **Point and spot lights.** A world that wants *dynamic* lights wants a different field from `baked_light_count`, and no consumer has asked for one.
- **Light probes and reflection.** The sheen on a wet or polished surface is a cubemap, a material property rather than a world one.
