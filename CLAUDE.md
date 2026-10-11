# dot-lighting

A world's lighting as a document rather than as a scene: `DotLightDocument` is a dictionary in and a dictionary out (sun, ambient, fog, sky, baked-light count), `DotLightRig` turns one into a sun and an `Environment`, and `DotLightProfile` says how much of it this machine draws. An imported map carries its lighting in its manifest and the game applies it; game-g2gfast applies imported maps' lighting this way, and game-arena gives each built-in map a document of its own (2026-10-10).

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_lighting/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

## Layout

| Path | What |
| --- | --- |
| `core/dot_light_document.gd` | `DotLightDocument`: what the world is; `from_dictionary`, `to_dictionary`, `has_sun`, `has_ambient`, `sky_name`, `baked_light_count` |
| `core/dot_light_profile.gd` | `DotLightProfile`: what this machine draws (tonemap, glow, fog, sky, shadows); `high()`, `low()`, `web()` |
| `runtime/dot_light_rig.gd` | `DotLightRig`: `apply`, `environment`, the procedural sky, `METRES_PER_UNIT` and `metres()` |
| `runtime/dot_light_zone.gd` | `DotLightZone`: the inspector half for a hand-built world; builds the lighting on `_ready` and steps aside |
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
- **`baked_light_count` exists so nobody places those lights again** and lights the world twice.

## Not here yet

- **Point and spot lights.** A world that wants *dynamic* lights wants a different field from `baked_light_count`, and no consumer has asked for one.
- **Light probes and reflection.** The sheen on a wet or polished surface is a cubemap, a material property rather than a world one.
