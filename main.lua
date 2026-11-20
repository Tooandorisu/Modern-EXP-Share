-- Modern Exp. Share (Gen 3)
--
-- Gen 6+ experience sharing for FireRed, LeafGreen, Ruby, Sapphire and
-- Emerald:
--   * every Pokemon that fought gets the full experience, with no split
--     between fighters;
--   * every other healthy party member gets a share (50% by default);
--   * the held EXP. SHARE no longer matters - the whole team is covered;
--   * the team's gains are summed up in one line instead of one box each;
--   * catching a Pokemon pays experience, as it does from Gen 6 on.
--
-- Everything goes through the public battle.exp_award, exp.gain and
-- battle.catch_exp hooks.  The only engine reach is optional: the summary
-- line is spliced into the native EXP sequence, and the "needs EXP. SHARE"
-- option reads the bag.  If either module is missing the mod still pays
-- the team; it just falls back to quiet awards / no item check.

local mod = ...

local ITEM_EXP_SHARE = 182 -- same number in FRLG and RSE

mod.options:define({
  { key = "enabled", label = "EXP. SHARE", type = "toggle", default = true },
  { key = "team_share", label = "TEAM SHARE", type = "choice", default = "50",
    choices = { { "50%", "50" }, { "100%", "100" } } },
  { key = "messages", label = "TEAM MESSAGES", type = "choice", default = "summary",
    choices = { { "SUMMARY", "summary" }, { "EACH MON", "each" }, { "QUIET", "quiet" } } },
  { key = "formula", label = "EXP. FORMULA", type = "choice", default = "classic",
    choices = { { "GEN 3", "classic" }, { "SCALED", "scaled" } } },
  { key = "catch_exp", label = "EXP. ON CATCH", type = "toggle", default = true },
  { key = "needs_item", label = "NEEDS EXP. SHARE", type = "toggle", default = false },
})

local function opt(key) return mod.options:get(key) end

-- Text other mods (a translation mod, say) can replace through
-- mod.find("modern_exp_share").exports.setText("summary", "...").
local TEXT = {
  summary = "The rest of your team\ngained EXP. Points!",
}

mod.exports.setText = function(key, value)
  if TEXT[key] ~= nil and type(value) == "string" and value ~= "" then
    TEXT[key] = value
    return true
  end
  return false
end

-- --------------------------------------------------------------- helpers

local function any(t)
  for _ in pairs(t) do return true end
  return false
end

local function num(v, default) return tonumber(v) or default or 0 end

local function isEgg(mon)
  return mon.isEgg == true or mon.egg == true or num(mon.species) == 412
end

local function canGain(mon)
  return type(mon) == "table"
    and num(mon.species or mon.speciesId) ~= 0
    and not isEgg(mon)
    and num(mon.hp) > 0
    and num(mon.level, 1) < 100
end

local function heldItem(mon)
  return num(mon and (mon.item or mon.heldItem))
end

local bagModule
local function ownsExpShare(st)
  local session = st and st.session
  if not session then return true end -- nothing to check against; don't lock the player out
  for _, mon in ipairs(st.playerParty or session.party or {}) do
    if heldItem(mon) == ITEM_EXP_SHARE then return true end
  end
  if bagModule == nil then
    local ok, Bag = pcall(require, "src.core.game3.bag")
    bagModule = ok and type(Bag) == "table" and Bag or false
  end
  if bagModule and session.bag then
    local ok, has = pcall(bagModule.has, session.bag, ITEM_EXP_SHARE)
    if ok then return has and true or false end
  end
  return false
end

-- Scripted demos keep their vanilla flow: the Pokedude's lessons, the old
-- man's and Wally's catching tutorials.
local function scripted(st)
  if not st then return true end
  if st.pokedude or st.oldManTutorial then return true end
  local kinds = st.kinds
  return type(kinds) == "table" and kinds.tutorial ~= nil and kinds.tutorial ~= false
end

-- In a partner battle (Steven at Mossdeep) the partner's Pokemon sit in
-- playerParty after slot playerHalf.  They are not the player's team.
local function ownSlot(st, pi)
  local half = tonumber(st.playerHalf)
  return half == nil or pi <= half
end

local function active(st)
  if scripted(st) then return false end
  if not opt("enabled") then return false end
  if opt("needs_item") and not ownsExpShare(st) then return false end
  return true
end

-- ------------------------------------------------------- the EXP formula

-- `role` is "fighter" or "team".  ctx is the exp.gain context: defeatedDef,
-- level (the foe's), isTrainer, luckyEgg, traded, index (party slot).
local function modernAmount(ctx, role, recipient)
  local def = ctx.defeatedDef or {}
  local yield = num(def.baseExp or def.expYield)
  local foeLevel = math.max(1, num(ctx.level, 1))
  local share = num(opt("team_share"), 50)
  local amount

  if opt("formula") == "scaled" then
    -- Gen 7+ scaled formula: rewards beating stronger foes, tapers
    -- grinding weaker ones.  No trainer bonus in this formula.
    local myLevel = math.max(1, num(recipient and recipient.level, foeLevel))
    local divisor = (role == "team" and share < 100) and 2 or 1
    local base = (yield * foeLevel) / (5 * divisor)
    local ratio = ((2 * foeLevel + 10) / (foeLevel + myLevel + 10)) ^ 2.5
    amount = math.floor(base * ratio) + 1
    if ctx.traded then amount = math.floor(amount * 150 / 100) end
    if ctx.luckyEgg then amount = math.floor(amount * 150 / 100) end
  else
    -- Gen 3's own numbers (pret Cmd_getexp), minus the split.
    amount = math.floor(yield * foeLevel / 7)
    if role == "team" then amount = math.floor(amount * share / 100) end
    if amount < 1 then amount = 1 end
    if ctx.luckyEgg then amount = math.floor(amount * 150 / 100) end
    if ctx.isTrainer then amount = math.floor(amount * 150 / 100) end
    if ctx.traded then amount = math.floor(amount * 150 / 100) end
  end
  if amount < 1 then amount = 1 end
  return amount
end

-- ---------------------------------------------------- the summary line

-- Set while battle.exp_award pays the team, read by exp.gain.
local plan
-- Set once the team was paid quietly, consumed by the EXP sequence.
local summary

local SEQ_KEY = "__modern_exp_share_original_begin"
local seqHooked = false

local function hookSequence()
  if seqHooked then return true end
  -- set per instance; a reload starts with seqHooked = false and re-wraps
  local ok, ExpSeq = pcall(require, "src.core.game3.battle.exp_seq")
  if not ok or type(ExpSeq) ~= "table" or type(ExpSeq.begin) ~= "function" then
    return false
  end
  -- survive a hot reload: always wrap the engine's own begin, never ours
  local original = rawget(ExpSeq, SEQ_KEY) or ExpSeq.begin
  rawset(ExpSeq, SEQ_KEY, original)
  ExpSeq.begin = function(awards, pushMsg, thenMsgs, opts)
    local pending = summary
    local started = original(awards, pushMsg, thenMsgs, opts)
    if not pending then return started end
    local matched = false
    for _, entry in ipairs(awards or {}) do
      if pending.team[entry.partyIndex] and entry.announce == false then matched = true end
    end
    if not matched then return started end
    summary = nil
    local tail = thenMsgs or (opts and opts.thenMsgs) or {}
    if not started then
      -- No fighter had anything to show (e.g. it fainted): the line alone.
      local msgs = { TEXT.summary }
      for _, t in ipairs(tail) do msgs[#msgs + 1] = t end
      return original({}, pushMsg, msgs, opts)
    end
    local steps = ExpSeq._steps
    if type(steps) ~= "table" then return started end
    -- before the first team level-up, else just before the closing lines
    local at
    for i, step in ipairs(steps) do
      local d = step.data or {}
      if d.partyIndex and pending.team[d.partyIndex] then at = i; break end
    end
    at = at or (#steps - #tail + 1)
    table.insert(steps, math.max(1, math.min(at, #steps + 1)),
      { kind = "msg", data = { text = TEXT.summary } })
    return started
  end
  seqHooked = true
  return true
end

-- ------------------------------------------------------------- the hooks

mod.hooks:wrap("battle.exp_award", function(next, ctx)
  local st = ctx and ctx.battle
  local party = st and st.playerParty
  if type(party) ~= "table" or type(ctx.applyShare) ~= "function" or not active(st) then
    return next(ctx)
  end

  local fighters = {}
  for _, pi in ipairs(ctx.recipients or {}) do fighters[pi] = true end

  -- a new award supersedes any line that never got shown
  summary = nil
  -- always (re)claim the sequence, so a hot-reloaded copy of this mod
  -- replaces the old one's wrapper instead of leaving it in charge
  local hooked = hookSequence()
  local messages = opt("messages")
  local wantSummary = messages == "summary" and hooked
  local announceTeam = messages == "each"

  plan = { battle = st, roles = {}, teamPaid = {} }
  local ok, err = pcall(function()
    -- fighters first, so their lines come before the team's
    for pi = 1, 6 do
      if fighters[pi] and canGain(party[pi]) then
        plan.roles[pi] = "fighter"
        ctx.applyShare(party[pi], 1, true)
      end
    end
    for pi = 1, 6 do
      if not fighters[pi] and ownSlot(st, pi) and canGain(party[pi]) then
        plan.roles[pi] = "team"
        ctx.applyShare(party[pi], 1, announceTeam)
      end
    end
  end)
  local paid = plan.teamPaid
  plan = nil
  if not ok then error(err, 0) end

  if wantSummary and any(paid) then summary = { battle = st, team = paid } end
end)

mod.hooks:wrap("exp.gain", function(next, ctx)
  local role = plan and ctx and plan.battle == ctx.battle and plan.roles[ctx.index]
  if not role then return next(ctx) end
  local recipient = plan.battle.playerParty and plan.battle.playerParty[ctx.index]
  local amount = modernAmount(ctx, role, recipient)
  if role == "team" and amount > 0 then plan.teamPaid[ctx.index] = true end
  return amount
end)

mod.hooks:wrap("battle.catch_exp", function(next, ctx)
  local st = ctx and ctx.battle
  -- Safari Zone catches stay EXP-free: no Pokemon of yours is out there.
  if opt("catch_exp") and active(st) and not st.safari then return true end
  return next(ctx)
end)

-- A battle that ends before its EXP sequence runs must not leave a stale line.
mod.events:on("battle.started", function() summary = nil end)
mod.events:on("battle.ended", function() summary = nil end)
