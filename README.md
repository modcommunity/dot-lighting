This is the **lighting** asset for TMC's **Dot** collection. It adds a world's lighting as a *document* rather than as a scene: a sun, an ambient colour, fog, a procedural sky built from the world's own numbers, and the post-processing that goes with them, read from data a map file or a content pack can carry, with quality profiles so the same world reads the same way on a desktop and in a browser.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Lighting is a document, and that is the whole idea

Lighting that lives in a `.tscn` can only ship with the build. Lighting that is a dictionary can come out of a map file, a content pack downloaded at runtime, a server's configuration or a level editor — and a game that reads one reads all four.

```gdscript
var doc := DotLightDocument.from_dictionary(manifest.get("lighting", {}))
DotLightRig.apply(world_root, doc, DotLightProfile.web())
```

That matters most for **converted worlds**. A map authored in another engine describes its own lighting — where the sun is, what colour it is, how far the fog reaches, which sky is behind it — and an importer that reads the geometry and leaves that behind produces a world that is geometrically perfect and looks like nothing in particular. Every map ends up under whatever one sun the game happened to hardcode.

## Absent is not zero

Every field is optional, and a document that says nothing about the sun is different from one that says the sun is black. The first keeps whatever default the consumer holds; the second means black. `has_sun` and `has_ambient` exist so a renderer can tell those apart, because they are different instructions and a world lit by the wrong one looks broken in a way nothing reports.

## A document is the world; a profile is the machine

`DotLightDocument` says what the world **is** and is the same on every machine that loads it. `DotLightProfile` says what **this** machine will draw of it. Folding the two together is how a world ends up looking different because somebody turned their settings down — which for a world whose surfaces are read for speed is not a cosmetic difference.

| | `high()` | `web()` | `low()` |
| --- | --- | --- | --- |
| tone mapping | yes | yes | yes |
| glow | yes | yes | no |
| fog | yes | yes | yes |
| sun shadows | yes | **no** | no |

**The browser drops the expensive half and not the cheap one.** A shadow pass scales with how much geometry is in frame, which on a large level is all of it; glow is a fixed cost in screen pixels that a phone-class GPU handles. Dropping glow first is the mistake the profiles exist to prevent.

**Tone mapping survives every tier**, including the lowest. Godot's default is `LINEAR`, which is not a tone map — it clips. A filmic shoulder is why a bright sky and a dark wall can both be readable in one frame instead of one being white and the other black, and it is a curve applied to a pixel that was going to be written anyway.

## What it can change, and what it cannot

A world drawn from a **baked lightmap** has its lighting in its textures: its materials are unshaded, and a directional light added beside them lights nothing they own.

So the sun here lights the **characters**, the props and anything else with an ordinary material. What changes how the baked world itself looks is the post-processing — the tone map, the fog, the glow and the colour behind everything. That is not a limitation so much as the division of labour a baked world already has, and those four are most of the difference between a faithful conversion and one that feels like the engine it came from.

## Three things that are easy to get wrong, and are handled here

- **A brightness is not an energy.** Source-family worlds write the light's compiled intensity alongside its colour, and it ranges from 20 to 600 across eight ordinary maps. Handing that to `Light3D.light_energy` gives a sun six hundred times too bright on one map and twenty times on the next. It is carried unconverted in the document and curved against a reference by the rig, because what to do with 600 is a renderer's decision.
- **A yaw in one handedness is not a yaw in the other.** Converting pitch and yaw separately between a Z-up left-handed world and Godot's Y-up right-handed one produces a sun that rises in the north, and nothing about the result looks wrong enough to question. `DotLightRig.sun_rotation` builds the direction in the source convention and swaps axes once, on the vector.
- **A sun straight overhead has no `looking_at`.** It is parallel to the default up vector and a basis cannot be built from two parallel vectors. Worlds with an exactly vertical sun are ordinary, not a corner case, and the suite asserts the result is a number rather than a `NaN`.

## The glow threshold is under 1.0 on purpose

A world lit by a baked 8-bit lightmap has nothing above white in it anywhere, so an HDR glow threshold finds nothing to bloom at, on any map, for ever. Lowering it is what lets the brightest surfaces — the strip lights and signage a level is signposted with — read as light rather than as paint. Raise it above 1.0 for a world whose materials genuinely emit.

## No autoloads

A lighting rig belongs to a world. A process running a server and a client, or holding two worlds while one loads over the other, needs two of them — and a global would make that the one arrangement this family cannot have.

## Validating

```bash
godot --headless --path . --import
godot --headless --path . res://examples/lighting_selftest.tscn   # 55 checks
```
