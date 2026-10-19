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

### A hand-built world: `painted()`

`high()`, `web()` and `low()` are for a world whose shade is baked into it. A world built from flat colours has nothing but the rig's light to read a shape by, and under the stock numbers it comes out pale: the floor near white and the shade a step from the sun side. `DotLightProfile.painted()` is the tier this platform gets, with:

- **a longer filmic shoulder and an exposure under 1.0**, so a pale floor in full sun lands a light grey and a saturated paint keeps its colour;
- **a fill**: a dim, shadowless light in the shade's colour from the side of the sky the sun is not on. An ambient colour lights every face alike, so a box in shade is one flat colour with no edges; the fill makes faces turned different ways different shades, which is the shape ambient occlusion would give and the Compatibility renderer cannot draw. It casts no shadow, has no specular and draws no disc in the sky (a dim one is a dark dot);
- **a little contrast and saturation** through the adjustment pass, which both renderers have. The contrast pivots at mid grey, so a world full of dark props in shade lowers it (1.04 rather than 1.12), or they go to black;
- **ambient occlusion** where the renderer has it (Forward+);
- **numbers matched to the renderer.** Forward+ lights into an HDR buffer and the tone map rolls a bright face back under white; the Compatibility renderer clips first. Under Compatibility the sun is divided further, the ambient and fill lowered and the exposure dropped, so both renderers' frames land within a shade of each other.

```gdscript
var p := DotLightProfile.painted()
p.sun_shadows = true            # a small map can afford them in a browser
DotLightRig.apply(world_root, doc, p)
```

Every new field (`exposure`, `contrast`, `saturation`, `fill_energy`, `fill_elevation`, `ambient_occlusion`) defaults to what the rig drew before it existed, so the stock tiers and every converted world look exactly as they did.

**Tone mapping survives every tier**, including the lowest. Godot's default is `LINEAR`, which is not a tone map — it clips. A filmic shoulder is why a bright sky and a dark wall can both be readable in one frame instead of one being white and the other black, and it is a curve applied to a pixel that was going to be written anyway.

### A contact shade where boxes meet: `DotContactShade`

The Compatibility renderer has no ambient occlusion, so in a painted world a crate meets the floor, and a wall the ceiling, with no shade in the corner, and nothing seems to stand on anything. `DotContactShade` is the cheap stand-in for a world built of boxes: hand it the boxes once at load and it returns one mesh of thin bands, a few millimetres off each face, that darken both faces of every concave crease (a box on the floor, a wall in a corner, a box on a box), deepest at the crease and gone 45 cm out.

```gdscript
var boxes: Array = []
for b in map_boxes:
    boxes.append(DotContactShade.box(b.transform, b.size))   # casts, shaded
add_child(DotContactShade.node(boxes))
```

- **Its own mesh, not the game's.** A face is two triangles, so a vertex colour on a wall is a gradient the height of the wall; and every game draws its boxes its own way. The bands are one unshaded draw call for a whole map, black at an alpha of the shade, which multiplies the world behind them, commutes, and needs no sorting.
- **Not `blend_mul`.** With glow on, the Compatibility renderer keeps the scene scaled down in its buffer; a multiplied white drew a fifth of the wall behind it.
- **How dark is how far it sticks out:** full under anything taller than the band, fainter under a step, nothing round a rug. Floor tiles side by side make no crease; a wall sunk into the floor makes the same one as a wall standing on it.
- **Per box:** `casts` (glass and water do not) and `shaded` (a prop's bounding box darkens the floor round it but takes no bands of its own). A box must have one axis along the face it stands on: yawed, not tilted.
- **Cheap at load:** a school of 449 boxes builds in under 0.1 s, about 88 000 vertices. Nothing runs per frame; the bands fade out past 40-70 m, where their depth would fight.

## What it can change, and what it cannot

A world drawn from a **baked lightmap** has its lighting in its textures: its materials are unshaded, and a directional light added beside them lights nothing they own.

So the sun here lights the **characters**, the props and anything else with an ordinary material. What changes how the baked world itself looks is the post-processing — the tone map, the fog, the glow and the colour behind everything. That is not a limitation so much as the division of labour a baked world already has, and those four are most of the difference between a faithful conversion and one that feels like the engine it came from.

## Three things that are easy to get wrong, and are handled here

- **A brightness is not an energy.** Worlds from the older BSP-family formats write the light's compiled intensity alongside its colour, and it ranges from 20 to 600 across eight ordinary maps. Handing that to `Light3D.light_energy` gives a sun six hundred times too bright on one map and twenty times on the next. It is carried unconverted in the document and curved against a reference by the rig, because what to do with 600 is a renderer's decision.
- **A yaw in one handedness is not a yaw in the other.** Converting pitch and yaw separately between a Z-up left-handed world and Godot's Y-up right-handed one produces a sun that rises in the north, and nothing about the result looks wrong enough to question. `DotLightRig.sun_rotation` builds the direction in the source convention and swaps axes once, on the vector.
- **A sun straight overhead has no `looking_at`.** It is parallel to the default up vector and a basis cannot be built from two parallel vectors. Worlds with an exactly vertical sun are ordinary, not a corner case, and the suite asserts the result is a number rather than a `NaN`.

## The sky's top can be its own colour

The procedural sky's zenith is drawn in the ambient colour by default, because in a converted world that is literally the colour of its sky. A world whose shade is meant to be paler than its sky says so with `"sky_top": [r, g, b]` at the top level of the document; the sky changes and the ambient light does not. Without the key, a world looks exactly as it did before the key existed.

## The glow threshold is under 1.0 on purpose

A world lit by a baked 8-bit lightmap has nothing above white in it anywhere, so an HDR glow threshold finds nothing to bloom at, on any map, for ever. Lowering it is what lets the brightest surfaces — the strip lights and signage a level is signposted with — read as light rather than as paint. Raise it above 1.0 for a world whose materials genuinely emit.

## Baked light for a world built in code: `DotLightBake`

A map a game generates from a document at load time does not exist in the editor, so the editor has nothing to bake. The game makes it exist for a moment: it builds the map exactly as a client would, copies the drawn meshes into a scene with a `LightmapGI` (`DotLightBake.prepare`), and the editor bakes that scene (`addons/dot_lighting/bake/bake.sh <project> res://<dir>`, which needs the plugin enabled in `project.godot`; the plugin does nothing without the `--dot-bake-lightmaps=` flag). The result is one self-contained `LightmapGIData` per map, no import step, HDR in RGB9E5, that the game ships in its pack.

At runtime the client rebuilds the same meshes, under the same names, with the same second UV set (`DotLightmapSheet`, a deterministic packer for meshes of flat quads), and calls:

```gdscript
var res := DotLightBake.attach(map_node, "res://lightmaps/%s.res" % id, DotLightBake.fingerprint(my_document_parts))
if res.ok:
    for lamp in my_lamps: lamp.light_bake_mode = Light3D.BAKE_STATIC   # baked, not drawn twice
```

A bake made from other geometry is refused with a WARN and the world is drawn with its live lights; a missing one is the same fallback at DEBUG; a headless process (a server) refuses and touches nothing. Baking needs Vulkan: a real graphics card does a map in seconds, a software one takes many minutes.

## No autoloads

A lighting rig belongs to a world. A process running a server and a client, or holding two worlds while one loads over the other, needs two of them — and a global would make that the one arrangement this family cannot have.

## Validating

```bash
godot --headless --path . --import
godot --headless --path . res://examples/lighting_selftest.tscn   # 116 checks
```

## Licence

MIT. See [LICENSE](LICENSE).
