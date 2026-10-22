extends RefCounted

## dot-lighting's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: DotLightDocument.sky_top / has_sky_top (the document's "sky_top" key), and
#    DotLightZone.sky_top_enabled / sky_top. A pack whose map names a sky_top on a level-1
#    host still runs, with the zenith in its ambient colour; the level is how it can ask
#    for the sky it was drawn against.
# 3: DotLightProfile.painted() / is_compatibility(), and its exposure, contrast, saturation,
#    fill_energy, fill_elevation and ambient_occlusion fields; DotLightRig.fill(). Every new
#    field defaults to what the rig drew before, so high(), low() and web() are unchanged.
# 4: DotContactShade (box, node, mesh, material, build): a multiplied contact shade where
#    boxes meet, the fake ambient occlusion for the Compatibility renderer.
# 5: DotLightBake (fingerprint, can_draw, attach, prepare, store) and DotLightmapSheet: baked
#    light for a world built in code, and the editor bake runner behind --dot-bake-lightmaps.
# 6: DotLightRig.apply_fog(env, doc, metres_per_unit): the fog half of environment(), for a system
#    (weather) that changes the fog of a world that is already running.
# 7: DotLightBake.components, first_difference and scan; attach and prepare take the parts, so a stale
#    WARN names the first component that differs. fingerprint ignores environment/props and rounds floats.
const LEVEL := 7
const OLDEST := 1
