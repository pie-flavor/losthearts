local json = require("json")

local mod = RegisterMod("Lost Hearts", 1)

local id_green = Isaac.GetCostumeIdByPath("gfx/characters/holymantle_green.anm2")
local id_black = Isaac.GetCostumeIdByPath("gfx/characters/holymantle_black.anm2")
local id_gold = Isaac.GetCostumeIdByPath("gfx/characters/holymantle_gold.anm2")
NullItemID.ID_HOLYMANTLE_GREEN = id_green
NullItemID.ID_HOLYMANTLE_BLACK = id_black
NullItemID.ID_HOLYMANTLE_GOLD = id_gold


local fix_costumes = false

local HeartType = {
  None = 0,
  Rotten = 1,
  Black = 1 << 1,
  Gold = 1 << 2,
  Eternal = 1 << 3,
}

local mantle_states = {}
local has_mantle = {}

local vel_rng = RNG()

local function index(player)
  local item
  if player:GetPlayerType() == PlayerType.PLAYER_LAZARUS2_B then
    item = CollectibleType.COLLECTIBLE_INNER_EYE
  else
    item = CollectibleType.COLLECTIBLE_SAD_ONION
  end
  return tostring(player:GetCollectibleRNG(item):GetSeed())
end

local function remove_mantles(player)
  player:TryRemoveCollectibleCostume(CollectibleType.COLLECTIBLE_HOLY_MANTLE, true)
  player:TryRemoveNullCostume(id_green)
  player:TryRemoveNullCostume(id_black)
  player:TryRemoveNullCostume(id_gold)
end

local function set_mantle_state(player, htype)
  local idx = index(player)
  if player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT) and mantle_states[idx] then
    mantle_states[idx] = mantle_states[idx] | htype
  else
    mantle_states[idx] = htype
  end
end

function mod:onPickup(pickup, collider, low)
  local player = collider:ToPlayer()
  if pickup.Variant == PickupVariant.PICKUP_HEART
    and player
    and player:GetPlayerType() == PlayerType.PLAYER_THELOST
    and player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE)
  then
    if pickup.SubType == HeartSubType.HEART_ROTTEN then
      -- you can't pick up rotten hearts, so that has to be reimplemented
      pickup:GetSprite():Play("Collect", true)
      pickup:PlayPickupSound()
      pickup:Die()
      fix_costumes = true
      set_mantle_state(player, HeartType.Rotten)
      return true
    elseif pickup.SubType == HeartSubType.HEART_BLACK then
      fix_costumes = true
      set_mantle_state(player, HeartType.Black)
    elseif pickup.SubType == HeartSubType.HEART_GOLDEN then
      pickup:GetSprite():Play("Collect", true)
      pickup:PlayPickupSound()
      pickup:Die()
      fix_costumes = true
      set_mantle_state(player, HeartType.Gold)
      return true
    elseif pickup.SubType == HeartSubType.HEART_ETERNAL then
      set_mantle_state(player, HeartType.Eternal)
    end
  end
end

local apply_mantle = {}

function mod:onPlayerUpdate(player)
  local idx = index(player)
  if apply_mantle[idx] then
    apply_mantle[idx] = nil
    player:UseCard(Card.CARD_HOLY, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER | UseFlag.USE_NOCOSTUME)
  end
  if player:GetPlayerType() == PlayerType.PLAYER_THELOST then
    if player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE) then
      has_mantle[idx] = true
    elseif has_mantle[idx] then
      -- broke the mantle this frame
      has_mantle[idx] = false
      fix_costumes = true
      local state = mantle_states[idx]
      mantle_states[idx] = HeartType.None
      if state then
        if state & HeartType.Black ~= 0 then
          player:UseActiveItem(CollectibleType.COLLECTIBLE_NECRONOMICON, UseFlag.USE_NOANIM)
        end
        if state & HeartType.Gold ~= 0 then
          local pennies = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_MIDAS_TOUCH):RandomInt(4) + 1
          for x = 1, pennies do
            Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COIN, CoinSubType.COIN_PENNY, player.Position, RandomVector() * (vel_rng:RandomFloat() * 0.5 + 0.5), player)
          end
          for i, entity in ipairs(Isaac.FindInRadius(player.Position, 60, EntityPartition.ENEMY)) do
            entity:AddMidasFreeze(EntityRef(player), 150)
          end
        end
        if state & HeartType.Rotten ~= 0 then
          local flies = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_GUPPYS_HEAD):RandomInt(3) + 2
          for x = 1, flies do
            Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLUE_FLY, 0, player.Position, Vector(0, 0), player)
          end
        end
        if state & HeartType.Eternal ~= 0 then
          -- player:UseCard(Card.CARD_HOLY, UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER | UseFlag.USE_NOCOSTUME) -- breaks shit
          -- player:GetEffects():AddCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE, false) -- crashes
          apply_mantle[idx] = true
        end
      end
    end
  end
end

function mod:onRoomClear(rng, pos)
  for x = 1, Game():GetNumPlayers() do
    local player = Isaac.GetPlayer(x - 1)
    local state = mantle_states[index(player)]
    if state and state & HeartType.Rotten ~= 0 and player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE) then
      for y = 1, 2 do
        Isaac.Spawn(EntityType.ENTITY_FAMILIAR, FamiliarVariant.BLUE_FLY, 0, player.Position, Vector(0, 0), player)
      end
    end
  end
end

function mod:onNewRoom()
  fix_costumes = true
end

function mod:onUpdate()
  if fix_costumes then
    fix_costumes = false
    for x = 1, Game():GetNumPlayers() do
      local player = Isaac.GetPlayer(x - 1)
      if player:GetPlayerType() == PlayerType.PLAYER_THELOST then
        local state = mantle_states[index(player)]
        if state and state ~= 0 and state ~= HeartType.Eternal then
          remove_mantles(player)
          if state & HeartType.Rotten ~= 0 then
            player:AddNullCostume(id_green)
          elseif state & HeartType.Gold ~= 0 then
            player:AddNullCostume(id_gold)
          elseif state & HeartType.Black ~= 0 then
            player:AddNullCostume(id_black)
          end
        elseif not player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_HOLY_MANTLE) then
          remove_mantles(player)
        end
      end
    end
  end
end

local function save_data()
  local data = { mantles = mantle_states }
  mod:SaveData(json.encode(data))
end

local function load_data()
  if mod:HasData() then
    local data = json.decode(mod:LoadData())
    mantle_states = data.mantles
    fix_costumes = true
  end
end

function mod:onNewLevel()
  save_data()
end

function mod:onGameExit(save)
  if save then
    save_data()
  end
end

function mod:onGameEnd(irrelevant)
  mod:RemoveData()
end

function mod:onStarted(continuing)
  if continuing then
    load_data()
  end
end

mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, mod.onPickup)
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.onPlayerUpdate)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onRoomClear)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_GAME_END, mod.onGameEnd)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onStarted)