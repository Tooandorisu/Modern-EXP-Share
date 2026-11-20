# Changelog

## 1.0.1

- Fixed: in Steven's partner battle (Emerald), Steven's Pokémon on the bench got a share of the experience. Now only your own team does.
- Fixed: the Pokédude lessons and the catching tutorials (the old man, Wally) no longer give the team a share or show the summary line.
- Fixed: catching a Pokémon in the Safari Zone no longer gives experience. None of your Pokémon is out there.
- Removed `exports.version`. It could drift from the release version; `mod.find("modern_exp_share").version` is the reliable one.

## 1.0.0

- First release: a Gen 6+ style Exp. Share for FireRed, LeafGreen, Ruby, Sapphire and Emerald.
- Fighters get the full amount without a split, and the rest of the team gets 50% or 100%.
- Adds the summary line, plus EACH MON and QUIET message modes.
- Adds the GEN 3 and SCALED (Gen 7+) EXP formulas.
- Catching a Pokémon gives experience (optional).
- Adds the optional "needs EXP. SHARE" unlock.
- Translation mods can replace the summary text through `exports.setText`.
