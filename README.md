# dot-lighting

Lighting as data. A world's sun, ambient light, fog, sky and glow live in a dictionary that a map file, a downloaded pack, a server config or an editor can supply, and one call turns it into Godot nodes sized for the machine it runs on.

Part of TMC's **Dot** collection: modular, MIT-licensed building blocks for games on the TMC platform (only the TMC website back end is closed). It was built with Claude Code and its headless suite passes, but little of it has met real players yet, so expect rough edges and please report what you find.

## Install

Copy `addons/dot_lighting/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-lighting in **Project > Project Settings > Plugins**. There are no autoloads: a rig belongs to a world, so a process can hold two.

## Use

```gdscript
var doc := DotLightDocument.from_dictionary(manifest.get("lighting", {}))
DotLightRig.apply(world_root, doc, DotLightProfile.web())
```

A map converted from another engine carries its own sun direction and colour, fog distance and sky. Reading those, instead of lighting every map with one hardcoded sun, is the main reason this exists.

Every field of a document is optional. A document with no sun keeps the consumer's default sun, and a document with a black sun means black. `has_sun` and `has_ambient` tell the two apart.

## Document and profile

`DotLightDocument` says what the world is and is the same on every machine. `DotLightProfile` says what this machine draws of it, so a low settings choice never changes the world itself.

| Profile | Tone mapping | Glow | Fog | Sun shadows |
| --- | --- | --- | --- | --- |
| `high()` | yes | yes | yes | yes |
| `web()` | yes | yes | yes | no |
| `low()` | yes | no | yes | no |

`for_platform()` picks `low()` on a phone, `web()` in a desktop browser and `high()` elsewhere. Shadows are dropped first on the web because their cost grows with the geometry in frame. Glow is a fixed cost in screen pixels. Tone mapping stays on in every tier, because Godot's default `LINEAR` only clips.

### `painted()` for hand-built worlds

`painted()` starts from the platform's tier and then adds the settings below. A world made of flat colours has nothing but the rig's light to show shape, and under the stock numbers it looks pale. `painted()` adds:

| Setting | Effect |
| --- | --- |
| `exposure`, a longer filmic shoulder | Pale floors land light grey and saturated paint keeps its colour. |
| `fill_energy`, `fill_elevation` | A dim shadowless light from the side opposite the sun, so faces turned different ways get different shades. |
| `contrast`, `saturation` | A small lift through the adjustment pass (contrast is lowered for worlds with many dark props). |
| `ambient_occlusion` | Used where the renderer has it (Forward+). |
| Renderer matching | Under Compatibility the sun, ambient, fill and exposure are lowered so both renderers look alike. |

All of these default to the old look, so existing worlds do not change.

```gdscript
var p := DotLightProfile.painted()
p.sun_shadows = true            # a small map can afford them in a browser
DotLightRig.apply(world_root, doc, p)
```

## Contact shade

The Compatibility renderer has no ambient occlusion, so a crate looks like it floats above the floor. `DotContactShade` builds one mesh of thin dark bands along every concave crease between boxes (box on floor, wall in a corner), fading out 45 cm from the crease.

```gdscript
var boxes: Array = []
for b in map_boxes:
    boxes.append(DotContactShade.box(b.transform, b.size))
add_child(DotContactShade.node(boxes))
```

- It is one unshaded draw call for a whole map and does nothing per frame. 449 boxes build in under 0.1 s.
- Each box has `casts` (glass and water do not) and `shaded` (a prop's box darkens the floor around it but gets no bands of its own).
- Boxes may be yawed but not tilted. The bands fade out beyond 40 to 70 m.

## What it can and cannot change

A baked lightmap has its light in its textures, so a directional light does not change how the baked world itself looks. The sun does light characters, props and anything with an ordinary material. For a baked world, the visible changes come from the tone map, fog, glow and background colour.

The glow threshold is under 1.0 on purpose. A baked 8-bit lightmap has nothing above white, so an HDR threshold would never bloom. Raise it above 1.0 for worlds with genuinely emissive materials.

The sky's top is the ambient colour unless the document has `"sky_top": [r, g, b]`.

## Conversion pitfalls handled here

- **Brightness is not energy.** Older BSP formats store a compiled brightness (20 to 600 across ordinary maps). The document carries it unconverted and the rig curves it against a reference.
- **Yaw handedness.** `DotLightRig.sun_rotation` builds the direction in the source convention and swaps axes once, on the vector.
- **A vertical sun** has no `looking_at`. The rig handles it, and the test asserts no `NaN`.

## Baked light for generated maps

A map built from a document at load time has nothing for the editor to bake. `DotLightBake.prepare` copies the drawn meshes into a scene with a `LightmapGI`, and the editor bakes it:

```bash
addons/dot_lighting/bake/bake.sh <project> res://<dir>
```

The plugin must be enabled in `project.godot` (it does nothing without `--dot-bake-lightmaps=`). Baking needs Vulkan: a real GPU takes seconds per map, software rendering takes many minutes. The result is one `LightmapGIData` per map. At runtime the client rebuilds the same meshes (same names, same second UV set from `DotLightmapSheet`) and attaches it:

```gdscript
var res := DotLightBake.attach(map_node, "res://lightmaps/%s.res" % id, DotLightBake.fingerprint(my_document_parts))
if res.ok:
    for lamp in my_lamps: lamp.light_bake_mode = Light3D.BAKE_STATIC   # baked, not drawn twice
```

A bake made from other geometry is refused with a warning and the live lights are used. A missing bake does the same at debug level. A headless process (a server) touches nothing.

## Test

```bash
godot --headless --path . --import
godot --headless --path . res://examples/lighting_selftest.tscn
```

## Licence

MIT. See [LICENSE](LICENSE).
