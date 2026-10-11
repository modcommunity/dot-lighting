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
const LEVEL := 2
const OLDEST := 1
