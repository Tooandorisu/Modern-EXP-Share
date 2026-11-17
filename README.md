# Modern Exp. Share (Gen 3)

Gen 6+ style Exp. Share for Gen1Recomp's FireRed, LeafGreen, Ruby, Sapphire and Emerald.

## What it does

- **Every Pokémon that fought gets the full experience.** It isn't split between fighters any more.
- **The rest of your team gets a share** (50% by default). Fainted Pokémon, Eggs and Pokémon at Lv. 100 are skipped.
- **You don't need to hold the EXP. SHARE.** The whole team is covered, and a held one no longer halves the fighter's experience.
- **One summary line**, *"The rest of your team gained EXP. Points!"*, instead of a separate box for each Pokémon. Level-ups, stat windows and new moves for the bench still show as usual.
- **Catching a Pokémon gives experience**, as it does from Gen 6 onward.

## Options

| Option | Default | Choices |
| --- | --- | --- |
| EXP. SHARE | On | Turn it off in-game, like the Gen 6/7 key item |
| TEAM SHARE | 50% | 50% / 100% for Pokémon that didn't fight |
| TEAM MESSAGES | SUMMARY | SUMMARY (one line) / EACH MON (Gen 3 style lines) / QUIET |
| EXP. FORMULA | GEN 3 | GEN 3 (classic, with the trainer bonus) / SCALED (Gen 7+ level-scaled, without the trainer bonus) |
| EXP. ON CATCH | On | Get experience for catching a Pokémon |
| NEEDS EXP. SHARE | Off | Only works once you own an EXP. SHARE (in the Bag or held by a party Pokémon) |

The Lucky Egg and traded-Pokémon boosts (×1.5) still apply.

## Compatibility

- API 3, `games: ["gen3"]`. It only uses the `battle.exp_award`, `exp.gain` and `battle.catch_exp` hooks.
- It declares `engine_internals` for two optional things: adding the summary line to the EXP sequence, and checking the Bag for the NEEDS EXP. SHARE option. If either engine module is missing, the mod still pays the team. It just pays it quietly or skips the item check.
- Other mods that also wrap `exp.gain` won't change the amounts this mod pays out.
- Translation mods can replace the summary text:
  ```lua
  local share = mod.find("modern_exp_share")
  if share then share.exports.setText("summary", "Resten av laget fikk\nEXP. Poeng!") end
  ```

## Install

Download the `.zip` from [Releases](https://github.com/Tooandorisu/Modern-EXP-Share/releases) and use **MODS > Import mod .zip** in Gen1Recomp, or put the files in a `modern_exp_share` folder inside your `mods` folder.

## Tests

Copy this repo into the engine as `mods/modern_exp_share`, then run from the engine root:

```sh
luajit mods/modern_exp_share/tests/modern_exp_share_test.lua
```
