--[[
For API information, consult [API.md](+API.md).
--]]

local json = require("json")

local mod = RegisterMod("Lost Hearts", 1)

local id_green = Isaac.GetCostumeIdByPath("gfx/characters/holymantle_green.anm2")
local id_black = Isaac.GetCostumeIdByPath("gfx/characters/holymantle_black.anm2")
local id_gold = Isaac.GetCostumeIdByPath("gfx/characters/holymantle_gold.anm2")
local id_gray = Isaac.GetCostumeIdByPath("gfx/characters/holymantle_gray.anm2")
NullItemID.ID_HOLYMANTLE_GREEN = id_green
NullItemID.ID_HOLYMANTLE_BLACK = id_black
NullItemID.ID_HOLYMANTLE_GOLD = id_gold
NullItemID.ID_HOLYMANTLE_GRAY = id_gray

-- Immortal Hearts integration
local immortal_heart = Isaac.GetEntityVariantByName("Immortal Heart")

local MantleSetting = {
  LostOnly = 0, TaintedLost = 1, Item = 2, Any = 3,
}

local config = { immortal_heart_integration = true, visible = true, arbitrary = MantleSetting.LostOnly, soul = 1, soul_max = 4 }

-- when this gets set to true, the player's costume gets updated next frame
-- have to use costumes for this because there's no way to just tint an existing one
local fix_costumes = false

local HeartType = {
  None = 0,
  Rotten = 1,
  Black = 1 << 1,
  Gold = 1 << 2,
  Eternal = 1 << 3,
  Bone = 1 << 4,
  Immortal = 1 << 5,
}

-- who has what mantle type
local mantle_states = {}
-- who had the mantle last frame
local has_mantle = {}
-- who has how many soul hearts
local soul_hearts = {}

local vel_rng = RNG()

-- copied from isaacscript-common
-- gets an index for a player, suitable for using in a table like mantle_states
-- the other ways of indexing (controller index, actual player index, etc.) each change under certain circumstances
-- but rng seeds never change
local function index(player)
  local item
  if player:GetPlayerType() == PlayerType.PLAYER_LAZARUS2_B then
    item = CollectibleType.COLLECTIBLE_INNER_EYE
  else
    item = CollectibleType.COLLECTIBLE_SAD_ONION
  end
  return tostring(player:GetCollectibleRNG(item):GetSeed())
end

-- check according to mod config if the player can receive mantle states
local function valid_player(player)
  if config.arbitrary == MantleSetting.LostOnly then
    return player:GetPlayerType() == PlayerType.PLAYER_THELOST
  elseif config.arbitrary == MantleSetting.TaintedLost then
    local ptype = player:GetPlayerType()
    return ptype == PlayerType.PLAYER_THELOST or ptype == PlayerType.PLAYER_THELOST_B
  elseif config.arbitrary == MantleSetting.Item then
    return player:HasCollectible(CollectibleType.COLLECTIBLE_HOLY_MANTLE)
  else
    return true
  end
end

local function remove_mantles(player)
  player:TryRemoveCollectibleCostume(CollectibleType.COLLECTIBLE_HOLY_MANTLE, true)
  player:TryRemoveNullCostume(id_green)
  player:TryRemoveNullCostume(id_black)
  player:TryRemoveNullCostume(id_gold)
  player:TryRemoveNullCostume(id_gray)
end

-- needed to handle birthright's stacking behavior
local function set_mantle_state(player, htype)
  local idx = index(player)
  if player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT) and mantle_states[idx] then
    mantle_states[idx] = mantle_states[idx] | htype
  else
    mantle_states[idx] = htype
  end
  fix_costumes = true
end

function mod:onPickup(pickup, collider, low)
  local player = collider:ToPlayer()
  -- change mantle state when hearts are picked up
  if (pickup.Variant == PickupVariant.PICKUP_HEART --[[ or (config.immortal_heart_integration and immortal_heart and pickup.Variant == immortal_heart) ]])
    and player
    and valid_player(player)
    -- only works if they actually have the mantle active
    and player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE)
  then
    local idx = index(player)
    local state = mantle_states[idx] or 0
    local collect = function()
      -- should approximate what picking up the heart looks like
      pickup:GetSprite():Play("Collect", true)
      pickup:PlayPickupSound()
      pickup:Die()
    end
    -- don't pick up hearts if the player already has that state.
    -- only really necessary if the player isn't the Lost or T.Lost
    local ctrl = Input.IsActionPressed(ButtonAction.ACTION_DROP, player.ControllerIndex)
    if pickup.SubType == HeartSubType.HEART_ROTTEN and state & HeartType.Rotten == 0 and not ctrl then
      collect(pickup)
      set_mantle_state(player, HeartType.Rotten)
      return true
    elseif pickup.SubType == HeartSubType.HEART_BLACK and state & HeartType.Black == 0 and not ctrl then
      collect(pickup)
      set_mantle_state(player, HeartType.Black)
      return true
    elseif pickup.SubType == HeartSubType.HEART_GOLDEN and state & HeartType.Gold == 0 and not ctrl then
      collect(pickup)
      set_mantle_state(player, HeartType.Gold)
      return true
    elseif pickup.SubType == HeartSubType.HEART_BONE and state & HeartType.Bone == 0 and not ctrl then
      collect(pickup)
      set_mantle_state(player, HeartType.Bone)
      return true
    elseif pickup.SubType == HeartSubType.HEART_ETERNAL and state & HeartType.Eternal == 0 and not ctrl then
      collect(pickup)
      set_mantle_state(player, HeartType.Eternal)
      return true
    -- for this one, you _do_ have to be holding ctrl, because soul hearts are a lot more valuable to most players as soul hearts, unless you are the Lost
    elseif pickup.SubType == HeartSubType.HEART_SOUL and (ctrl or player:GetPlayerType() == PlayerType.PLAYER_THELOST or player:GetPlayerType() == PlayerType.PLAYER_THELOST_B) then
      local idx = index(player)
      collect(pickup)
      soul_hearts[idx] = (soul_hearts[idx] or 0) + 1
      return true
-- Gotta wait for help on this one
--[[
    elseif pickup.Variant == immortal_heart and not ctrl then
      collect(pickup)
      set_mantle_state(player, HeartType.Immortal)
      return true
--]]
    end
  end
end
mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, mod.onPickup)

local had_item = {}
-- handle collecting items that give you hearts instead of directly picking up hearts
function mod:onCollectItem(player)
  local idx = index(player)
  local queued = player.QueuedItem.Item
  local prev = had_item[idx]
  -- if they were holding an item last frame, and aren't holding that item this frame
  -- will fail if they somehow queued two copies of the same item
  if prev and (not queued or queued.ID ~= prev) then
    if prev.AddBlackHearts ~= 0 and not Input.IsActionPressed(ButtonAction.ACTION_DROP, player.ControllerIndex) then
      set_mantle_state(player, HeartType.Black)
    end
    if prev.AddSoulHearts ~= 0 then
      soul_hearts[idx] = (soul_hearts[idx] or 0) + prev.AddSoulHearts
    end
  end
  had_item[idx] = queued
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.onCollectItem)

-- run this function only when the mod starts up
local started = false
function mod:ConfigSetup()
  if started then return end
  started = true
  if not ModConfigMenu then return end
  local OptionType = ModConfigMenu.OptionType
  local name = "Lost Hearts"
  local settings = "Settings"
  local yesno = { [true] = "Yes", [false] = "No" }
  local arbitrary = { 
    [MantleSetting.LostOnly] = "No", 
    [MantleSetting.TaintedLost] = "Tainted Lost", 
    [MantleSetting.Item] = "Holy Mantle item", 
    [MantleSetting.Any] = "Any Holy Mantle effect"
  }
  ModConfigMenu.RemoveCategory(name)
  ModConfigMenu.AddSetting(name, settings, {
    Type = OptionType.NUMBER,
    Default = 0, 
    CurrentSetting = function() return config.arbitrary; end,
    Display = function() return "Additional mantles: " .. arbitrary[config.arbitrary]; end,
    OnChange = function(x) config.arbitrary = x; end,
    Info = { "Mantle effects will activate in more situations than just The Lost" },
    Minimum = 0,
    Maximum = 3,
    ModifyBy = 1,
  })
-- It's a surprise tool that will help us later.
--[[
  ModConfigMenu.AddSetting(name, settings, {
    Type = OptionType.BOOLEAN,
    Default = true,
    CurrentSetting = function() return config.visible; end,
    Display = function() return "Visible Lost Health integration: " .. yesno[config.visible]; end,
    OnChange = function(x) config.visible = x; end,
    Info = { "Mantle effects will be shown in the Visible Lost Health mod's display" },
  })
--]]
  ModConfigMenu.AddSetting(name, settings, {
    Type = OptionType.NUMBER,
    Default = 1,
    CurrentSetting = function() return config.soul; end,
    Display = function() return string.format("Soul heart invulnerability: %0.1f", config.soul); end,
    OnChange = function(x) config.soul = x; end,
    Info = { "You get this much additional invulnerability time from the mantle breaking, in seconds, per soul heart" },
    Maximum = 3,
    Minimum = 0,
    ModifyBy = 0.1,
  })
  ModConfigMenu.AddSetting(name, settings, {
    Type = OptionType.NUMBER,
    Default = 4,
    Maximum = 12,
    Minimum = 1,
    ModifyBy = 1,
    CurrentSetting = function() return config.soul_max; end,
    Display = function() return "Maximum spent soul hearts: " .. config.soul_max; end,
    OnChange = function(x) config.soul_max = x; end,
    Info = { "You can't consume more than this many soul hearts in one mantle break. " },
  })
--[[
  if immortal_heart then
    ModConfigMenu.AddSetting(name, settings, {
      Type = OptionType.BOOLEAN,
      Default = true,
      CurrentSetting = function() return config.immortal_heart_integration; end,
      Display = function() return "Immortal Hearts integration: " .. yesno[config.immortal_heart_integration]; end,
      OnChange = function(x) config.immortal_heart_integration = x; end,
    })
  end
]]
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.ConfigSetup)

local apply_mantle = {}

-- local teleporting_animations = { Appear = 1, TeleportUp = 1, TeleportDown = 1, Trapdoor = 1, MinecartEnter = 1, Jump = 1, LightTravel = 1, DeathTeleport = 1 }

function mod:onPlayerUpdate(player)
  local idx = index(player)
  -- add the mantle effect? crash the game. use the other way of adding the mantle effect? doesn't fucking work.
  -- joke's on you if you already had a holy card ig
  if apply_mantle[idx] then
    apply_mantle[idx] = nil
    player:UseCard(Card.CARD_HOLY, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER | UseFlag.USE_NOCOSTUME)
  end
  if valid_player(player) then
    if player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE) then
      has_mantle[idx] = 2
    -- one of the previous hacks for the mantle disappearing when you jump down the trapdoor
    -- elseif teleporting_animations[player:GetSprite():GetAnimation()] == nil then -- sometimes works, sometimes doesn't.
    else
      -- the current hack. simply make sure they're not currently standing in a trapdoor.
      -- todo extend this to handle the curse room door
      local room = Game():GetLevel():GetCurrentRoom()
      local block = room:GetGridEntityFromPos(player.Position)
      local door
      if block then door = block:ToDoor(); end
      if block == nil 
        or not (block:GetType() == GridEntityType.GRID_TRAPDOOR or
          (door and (door.TargetRoomType == RoomType.ROOM_CURSE or door.CurrentRoomType == RoomType.ROOM_CURSE) and room:IsClear()))
      then
        if has_mantle[idx] == 0 then
          -- broke the mantle this frame
          has_mantle[idx] = nil
          fix_costumes = true
          local state = mantle_states[idx]
          -- you broke it, so reset
          mantle_states[idx] = HeartType.None
          if state then
            -- have to use bitwise ops to handle birthright stacking
            if state & HeartType.Black ~= 0 then
              -- dumb, but works
              player:UseActiveItem(CollectibleType.COLLECTIBLE_NECRONOMICON, UseFlag.USE_NOANIM)
            end
            if state & HeartType.Gold ~= 0 then
              SFXManager():Play(SoundEffect.SOUND_ULTRA_GREED_COIN_DESTROY)
              -- I _think_ this is how many coins golden hearts spawn? Undocumented
              local pennies = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_MIDAS_TOUCH):RandomInt(4) + 1
              for x = 1, pennies do
                Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, 0, player.Position, RandomVector() * (vel_rng:RandomFloat() * 0.5 + 0.5), player)
              end
              for i, entity in ipairs(Isaac.FindInRadius(player.Position, 80, EntityPartition.ENEMY)) do
                entity:AddMidasFreeze(EntityRef(player), 150)
              end
              -- todo add gold explosion
            end
            if state & HeartType.Rotten ~= 0 then
              local flies = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_GUPPYS_HEAD):RandomInt(3) + 2
              for x = 1, flies do
                Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLUE_FLY, 0, player.Position, Vector(0, 0), player)
              end
            end
            if state & (HeartType.Eternal | HeartType.Immortal) ~= 0 then
              apply_mantle[idx] = true
            end
            if state & HeartType.Bone ~= 0 then
              for x = 1, 4 do
                Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BONE_ORBITAL, 0, player.Position, Vector(0, 0), player)
              end
            end
          end
          -- handle soul heart iframes increase
          local soul = soul_hearts[idx]
          if soul and soul > 0 then
            -- maximum soul hearts per hit
            if soul > config.soul_max then
              soul_hearts[idx] = soul - config.soul_max
              soul = config.soul_max
            else
              soul_hearts[idx] = 0
            end
            local damage_cooldown = player:GetDamageCooldown()
            -- measured in frames 60/s; soul_max is in seconds
            player:SetMinDamageCooldown(damage_cooldown + soul * config.soul * 60)
          end
        elseif has_mantle[idx] then
          -- I can't even remember why it has to be a two-frame window instead of a one-frame window. It just does. Fuck this API
          has_mantle[idx] = has_mantle[idx] - 1
        end
      end
    end
  end
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.onPlayerUpdate)

function mod:onRoomClear(rng, pos)
  for x = 1, Game():GetNumPlayers() do
    local player = Isaac.GetPlayer(x - 1)
    local state = mantle_states[index(player)]
    if state and state & HeartType.Rotten ~= 0 and valid_player(player) and player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE) then
      for y = 1, 2 do
        Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLUE_FLY, 0, player.Position, Vector(0, 0), player)
      end
    end
  end
end
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onRoomClear)

function mod:onNewRoom()
  -- costumes are reset upon entering a new room
  -- why not pill costumes, you ask? because player tints are different than costumes. but you can't tint a costume on its own. fuck this api
  fix_costumes = true
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)

function mod:onUpdate()
  -- remove all mantle costumes and apply the correct one if, for a variety of reasons, they need to be reset
  if fix_costumes then
    fix_costumes = false
    for x = 1, Game():GetNumPlayers() do
      local player = Isaac.GetPlayer(x - 1)
      if valid_player(player) then
        local state = mantle_states[index(player)]
        if state and state ~= 0 and state & ~(HeartType.Eternal | HeartType.Immortal) ~= 0 then
          remove_mantles(player)
          if state & HeartType.Rotten ~= 0 then
            player:AddNullCostume(id_green)
          elseif state & HeartType.Gold ~= 0 then
            player:AddNullCostume(id_gold)
          elseif state & HeartType.Black ~= 0 then
            player:AddNullCostume(id_black)
          elseif state & HeartType.Bone ~= 0 then
            player:AddNullCostume(id_gray)
          end
        elseif not player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE) then
          remove_mantles(player)
        end
      end
    end
  end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)

local function save_data()
  -- mod data is saved as a string instead of an object, so json is a must
  local data = { mantles = mantle_states, soul_hearts = soul_hearts, config = config }
  mod:SaveData(json.encode(data))
end

local function load_data()
  if mod:HasData() then
    local data = json.decode(mod:LoadData())
    mantle_states = data.mantles
    soul_hearts = data.soul_hearts
    config = data.config
    fix_costumes = true
  end
end

function mod:onNewLevel()
  save_data()
--[[
  for i = 1, Game():GetNumPlayers() do
    local idx = Isaac.GetPlayer(i - 1)
    mantle_states[idx] = mantle_states[idx] & ~HeartType.Immortal
  end
--]]
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)

function mod:onGameExit(save)
  if save then
    save_data()
  end
end
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)

function mod:onGameEnd(irrelevant)
  mod:RemoveData()
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_END, mod.onGameEnd)

function mod:onStarted(continuing)
  if continuing then
    load_data()
  end
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onStarted)

LostHeartsAPI = {
  HeartType = HeartType,
  mantle_states = mantle_states,
  soul_hearts = soul_hearts,
  index = index,
  set_mantle_state = set_mantle_state,
  config = config,
  valid_player = valid_player,
}
