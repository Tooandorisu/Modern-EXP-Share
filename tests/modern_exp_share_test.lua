-- Modern Exp. Share (Gen 3) -- headless tests against the real Gen 3 EXP code.
-- Run from the engine root:
--   luajit mods/modern_exp_share/tests/modern_exp_share_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local ModRuntime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Runtime = require("src.core.game3.runtime")
local Pokemon = require("src.core.game3.pokemon")
local ItemsData = require("src.core.game3.items_data")
local Dataset = require("src.core.game3.dataset")
local State = require("src.core.game3.battle.state")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local Anim = require("src.core.game3.battle.anim")
local Experience = require("src.core.game3.battle.experience")
local ExpSeq = require("src.core.game3.battle.exp_seq")
local Rng = require("src.core.game3.rng")
local Space = require("src.core.game3.scripting.space")

local MOD_DIR = "mods/modern_exp_share/"
local SUMMARY = "The rest of your team\ngained EXP. Points!"

local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }
local savedVersion = Version.get()
local restore = {}
local function fixture(owner, key, value)
  local old = owner[key]
  restore[#restore + 1] = function() owner[key] = old end
  owner[key] = value
end

local function readFile(path)
  local f = assert(io.open(path, "rb"), "missing " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local function mon(species, level)
  return { species = species or 4, nickname = "MON", level = level or 20, growthRate = 0,
    exp = 8000, hp = 60, maxHp = 60, attack = 30, defense = 30, speed = 30, spAtk = 30,
    spDef = 30, moves = { 1, 10, 33, 52 }, pp = { 35, 35, 35, 25 }, maxPp = { 35, 35, 35, 25 },
    item = 0, ability = 0, friendship = 70, personality = 1, otId = 1, otSecretId = 2,
    ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } }
end

-- party: [1] fighter, [2] bench, [3] fainted bench, [4] egg
local function setup(version, options, opts)
  opts = opts or {}
  Battle.reset()
  Version.set(version)
  Versions.select(version)
  local data = T.sdk.gen3Data()
  for key, value in pairs(data.gen3Pokemon) do fixture(Pokemon, key, value) end
  fixture(Pokemon, "_cache", Dataset.cache())
  fixture(Pokemon, "_national", { toNational = { [4] = 4, [16] = 16 } })
  fixture(Pokemon, "_romMoveNames", data.gen3Pokemon._moveNames)
  local itemRows = data.gen3Items._byId
  for id, name in pairs({ [182] = "EXP SHARE", [197] = "LUCKY EGG" }) do
    itemRows[id] = { name = name, pocket = "ITEMS", price = 100 }
  end
  fixture(ItemsData, "_byId", itemRows)
  fixture(ItemsData, "_byName", nil)
  local fainted = mon(); fainted.hp = 0
  local egg = mon(); egg.isEgg = true
  local party = { mon(), mon(), fainted, egg }
  for _, m in ipairs(party) do Pokemon.applyStats(m); if m.hp > 0 then m.hp = m.maxHp end end
  for _, m in ipairs(party) do m.exp = Experience.expForLevel(m, m.level) end
  local session = { version = version, name = "RED", trainerId = 1, secretId = 2,
    party = party, flags = {}, vars = {}, options = {}, gameStats = {},
    bag = opts.bag }
  local game = { data = data, session = session, options = session.options }
  session.game = game
  fixture(Runtime, "active", true)
  fixture(Runtime, "session", session)
  fixture(Runtime, "_game", game)
  fixture(Space, "bundle", { text = setmetatable({}, { __index = function(t, key)
    local value = { { t = "text", s = tostring(key) }, { t = "eos" } }
    rawset(t, key, value)
    return value
  end }), events = {}, maps = {}, textTables = {} })
  local files = {
    [MOD_DIR .. "manifest.json"] = readFile(MOD_DIR .. "manifest.json"),
    [MOD_DIR .. "main.lua"] = readFile(MOD_DIR .. "main.lua"),
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  loader.game = game
  T.eq(loader:load(data), true, version .. " loader accepts the mod")
  T.eq(#loader.errors, 0, version .. " mod loads without errors")
  loader.modOptions.modern_exp_share = options or {}
  local st = State.new({ playerParty = party, foeParty = { mon(16), mon(16) },
    wild = not opts.trainer, rng = Rng.compat })
  st.session, st.turn, st.aiFlags = session, 1, 0
  st.enemy.participants = { [1] = true }
  Battle._active, Battle._st = true, st
  Battle._phase, Battle._headless, Battle._fade = "command", true, false
  Ui.reset({ headless = true })
  Ui.bindState(st, session)
  Anim.reset({ headless = true })
  return st, loader
end

local function teardown()
  Battle.reset()
  for i = #restore, 1, -1 do restore[i]() end
  restore = {}
  ModRuntime.events, ModRuntime.hooks, ModRuntime.errors =
    savedRuntime[1], savedRuntime[2], savedRuntime[3]
end

local function exercise(version, label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  T.check(ok, version .. " " .. label .. ": " .. tostring(err))
  teardown()
end

local function gains(st, awards)
  local byIndex = {}
  for _, entry in ipairs(awards) do byIndex[entry.partyIndex] = entry end
  return byIndex
end

local function runSeq(awards)
  local messages = {}
  ExpSeq.begin(awards, function(text) messages[#messages + 1] = text end, nil, { headless = true })
  for _ = 1, 2000 do if not ExpSeq.busy() then break end; ExpSeq.update() end
  return messages
end

local function count(list, text)
  local n = 0
  for _, t in ipairs(list) do if t == text then n = n + 1 end end
  return n
end

local function baseExp(level)
  return math.floor(Pokemon.speciesMeta(16).expYield * (level or 20) / 7)
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  exercise(version, "wild battle pays the whole team", function()
    local st = setup(version)
    local awards = Experience.awardFoe(st, st.enemy, { trainer = false })
    local by = gains(st, awards)
    local base = baseExp()
    T.eq(#awards, 2, version .. " fighter and bench are paid, fainted mon and egg are not")
    T.eq(by[1].amount, base, version .. " fighter gets the full, unsplit amount")
    T.eq(by[2].amount, math.floor(base / 2), version .. " bench gets 50%")
    T.check(by[1].announce ~= false, version .. " fighter keeps its own line")
    T.eq(by[2].announce, false, version .. " bench is paid quietly")
    local messages = runSeq(awards)
    T.eq(count(messages, SUMMARY), 1, version .. " one summary line")
    T.check(messages[1] ~= SUMMARY and messages[#messages] == SUMMARY,
      version .. " summary comes after the fighter's line")
    T.eq(ExpSeq.busy(), false, version .. " EXP sequence completes")
  end)

  exercise(version, "trainer bonus and 100% team share", function()
    local st = setup(version, { team_share = 100 }, { trainer = true })
    local by = gains(st, Experience.awardFoe(st, st.enemy, { trainer = true }))
    local boosted = math.floor(baseExp() * 150 / 100)
    T.eq(by[1].amount, boosted, version .. " trainer x1.5 for the fighter")
    T.eq(by[2].amount, boosted, version .. " 100% share pays the bench in full")
  end)

  exercise(version, "a held EXP. SHARE no longer halves the fighter", function()
    local st = setup(version)
    st.playerParty[2].item = 182
    local by = gains(st, Experience.awardFoe(st, st.enemy, { trainer = false }))
    T.eq(by[1].amount, baseExp(), version .. " fighter still gets the full amount")
    T.eq(by[2].amount, math.floor(baseExp() / 2), version .. " holder is treated as team")
  end)

  exercise(version, "turned off = vanilla", function()
    local st = setup(version, { enabled = false })
    local awards = Experience.awardFoe(st, st.enemy, { trainer = false })
    T.eq(#awards, 1, version .. " only the fighter is paid")
    T.eq(awards[1].amount, baseExp(), version .. " vanilla amount")
    T.eq(count(runSeq(awards), SUMMARY), 0, version .. " no summary line")
  end)

  exercise(version, "each-mon and quiet messages", function()
    local st = setup(version, { messages = "each" })
    local awards = Experience.awardFoe(st, st.enemy, { trainer = false })
    local by = gains(st, awards)
    T.check(by[2].announce ~= false, version .. " each: bench announced")
    T.eq(count(runSeq(awards), SUMMARY), 0, version .. " each: no summary")
    teardown()
    st = setup(version, { messages = "quiet" })
    awards = Experience.awardFoe(st, st.enemy, { trainer = false })
    T.eq(gains(st, awards)[2].announce, false, version .. " quiet: bench silent")
    T.eq(count(runSeq(awards), SUMMARY), 0, version .. " quiet: no summary")
  end)

  exercise(version, "needs EXP. SHARE option", function()
    local st = setup(version, { needs_item = true })
    T.eq(#Experience.awardFoe(st, st.enemy, { trainer = false }), 1,
      version .. " without the item it stays vanilla")
    teardown()
    st = setup(version, { needs_item = true })
    st.playerParty[2].item = 182
    T.eq(#Experience.awardFoe(st, st.enemy, { trainer = false }), 2,
      version .. " holding one unlocks it")
  end)

  exercise(version, "scaled formula", function()
    local st = setup(version, { formula = "scaled" }, { trainer = true })
    local by = gains(st, Experience.awardFoe(st, st.enemy, { trainer = true }))
    local y, L, Lp = Pokemon.speciesMeta(16).expYield, 20, 20
    local ratio = ((2 * L + 10) / (L + Lp + 10)) ^ 2.5
    T.eq(by[1].amount, math.floor(y * L / 5 * ratio) + 1, version .. " fighter, no trainer bonus")
    T.eq(by[2].amount, math.floor(y * L / 10 * ratio) + 1, version .. " team halves")
  end)

  exercise(version, "fighter fainted: the line still shows", function()
    local st = setup(version)
    st.playerParty[1].hp = 0
    local awards = Experience.awardFoe(st, st.enemy, { trainer = false })
    T.eq(#awards, 1, version .. " only the bench is paid")
    local messages = runSeq(awards)
    T.eq(count(messages, SUMMARY), 1, version .. " summary shown on its own")
  end)

  exercise(version, "catching pays experience", function()
    local st = setup(version)
    local before1, before2 = st.playerParty[1].exp, st.playerParty[2].exp
    Battle.startPostCatchFlow({ success = true, mon = st.enemy.mon, location = "party" })
    T.eq(st.playerParty[1].exp, before1 + baseExp(), version .. " fighter paid on catch")
    T.eq(st.playerParty[2].exp, before2 + math.floor(baseExp() / 2), version .. " team paid on catch")
    teardown()
    st = setup(version, { catch_exp = false })
    before1 = st.playerParty[1].exp
    Battle.startPostCatchFlow({ success = true, mon = st.enemy.mon, location = "party" })
    T.eq(st.playerParty[1].exp, before1, version .. " catch EXP can be turned off")
  end)
end

Version.set(savedVersion)
T.finish("modern_exp_share")
