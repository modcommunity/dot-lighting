# dot-lighting

A world's lighting as a document rather than as a scene. Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first; this file is only about what this addon decides.

## Why it is not part of dot-fx, which is the question it was created out of

dot-fx's own invariant is the answer: *"pooled, budgeted, quality-tiered, distance-culled, **and safe to drop**."* Lighting fails that at the last clause. A world whose glow got budgeted out is not missing an effect, it is the wrong world — and a player judging a surface's speed by how fast its pattern goes past is reading something that the lighting decides the legibility of.

The shapes are different too. An effect is an **event**: something happened, draw a picture of it, and the picture is allowed not to arrive. Lighting is **continuous world state** that exists before anything happens and is still there when nothing does.

And it is not dot-effects, which is status effects — burning, stuns, incapacitation, temporary health. That addon is about the simulation; this one cannot touch it.

## The document is the point

`DotLightDocument` is a dictionary in and a dictionary out. That is what lets a converted map carry its own lighting: an importer writes a `lighting` block into a manifest and the game reads it, with nothing in between knowing about either end. Lighting built into a `.tscn` can only ship with the build.

**Absent is not zero.** `has_sun` and `has_ambient` exist so a consumer can tell "the map said nothing" from "the map said black". Those are different instructions and the suite asserts both.

## The unit constant is duplicated, deliberately

`DotLightRig.METRES_PER_UNIT` is 0.01905, which is also `G2GUnits`' figure and dot-physics'. The family rule is that a conversion lives in exactly one place — and that rule is per project, not across a dependency boundary this addon does not have: it depends on dot-core alone, and importing a game's unit class to read a fog distance would be a dependency on the game. A caller that owns its own conversion passes metres in and never touches it.

## What it cannot do, and why that is not a bug

A baked world's surfaces are unshaded — the lightmap *is* their lighting — so the sun lights characters and props and nothing of the world itself. What changes the world is the post-processing. Anybody reading this file because "the sun does not seem to do anything" is looking at that, and it is working as intended.

## Validating

```bash
godot --headless --path . --import
godot --headless --path . res://examples/lighting_selftest.tscn   # 55 checks
```

The suite counts **sections that ran to their last line** as well as a total check count, because a script error inside a section aborts that section and not the run, and the section counter is satisfied by one that had already announced itself. A suite reporting "0 failed" with checks missing is a failure this family has shipped more than once.

## Not here yet

- **The sky a converted world NAMED.** `sky_name` is carried and is not what gets drawn: it names a texture set that lives inside the game that world was authored for, is not in the file, and is not ours to copy. What is drawn instead is a procedural sky built from the world's own numbers — its fog colour as the horizon, its ambient as the top, its sun at its own angle — which is the same trick the rest of this addon plays: everything needed was already in the file, because the compiler that baked the lightmap had to be told all of it.
- **Point and spot lights.** `baked_light_count` says how many a world compiled into its lightmap precisely so that nobody places them again and lights it twice. A world that wants *dynamic* lights wants a different field, and no consumer has asked for one.
- **Light probes and reflection.** The sheen on a wet or polished surface is a cubemap, and that is a material property rather than a world one.
