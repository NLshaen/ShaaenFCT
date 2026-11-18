-- ShaaenFCT - optional preset in Blizzard's Combat Log UI (WoW Forever).
-- This only configures Blizzard's *display filter*. It does not (and cannot)
-- expose raw combat-log events to addons or decode protected log messages.
-- All changes are opt-in and only take place outside combat.
local ADDON = ...
local NAME = 'ShaaenFCT'
local function getRegistry()
 local registry = _G.Blizzard_CombatLog_Filters
 if type(registry) ~= 'table' or type(registry.filters) ~= 'table' then return nil end
 return registry
end
local function findFilter(registry)
 for index, filter in ipairs(registry.filters) do
  if type(filter) == 'table' and filter.name == NAME then return index end
 end
end
local function copyTable(value, visited)
 if type(value) ~= 'table' then return value end
 if visited[value] then return visited[value] end
 local result = {}
 visited[value] = result
 for k,v in pairs(value) do result[copyTable(k, visited)] = copyTable(v, visited) end
 return result
end
local function newPreset(registry)
 local mine = _G.COMBATLOG_FILTER_MINE
 local pet = _G.COMBATLOG_FILTER_MY_PET
 if mine == nil or pet == nil then return nil, 'Blizzard source flags unavailable.' end
 local template = _G.DEFAULT_COMBATLOG_FILTER_TEMPLATE or registry.filters[1]
 if type(template) ~= 'table' then return nil, 'Blizzard Combat Log template unavailable.' end
 local preset = copyTable(template,{})
 preset.name = NAME
 preset.quickButtonName = NAME
 preset.tooltip = 'ShaaenFCT - own and pet damage, misses, dodges, parries and blocks'
 preset.hasQuickButton = true
 preset.onQuickBar = nil
 preset.isTemp = nil
 preset.quickButtonDisplay = {solo = true, party = true, raid = true}
 preset.settings = preset.settings or {}
 preset.settings.showHistory = true
 preset.settings.timestamp = true
 -- Exclude unrelated casts, auras, healing and other players' damage:
 -- those messages would otherwise generate unrelated Smart-mode credits.
 local events = {
  SWING_DAMAGE=true, SWING_MISSED=true,
  RANGE_DAMAGE=true, RANGE_MISSED=true,
  SPELL_DAMAGE=true, SPELL_MISSED=true,
  SPELL_PERIODIC_DAMAGE=true, SPELL_PERIODIC_MISSED=true,
  DAMAGE_SHIELD=true, DAMAGE_SHIELD_MISSED=true,
  DAMAGE_SPLIT=true, SPELL_BUILDING_DAMAGE=true,
 }
 local available = _G.COMBATLOG_EVENT_LIST
 if type(available) == 'table' then
  for event in pairs(events) do
   if available[event] == nil then events[event] = nil end
  end
 end
 preset.filters = {{eventList = events, sourceFlags = {[mine] = true, [pet] = true}}}
 return preset
end
local bridge = {}
function bridge:Status()
 local registry = getRegistry()
 if not registry then return false, 'Blizzard Combat Log not ready. Open the Combat Log and try again.' end
 local index = findFilter(registry)
 if not index then return false, 'ShaaenFCT filter not installed.' end
 return true, registry.currentFilter == index and 'ShaaenFCT filter active.' or 'ShaaenFCT filter available.'
end
function bridge:Activate()
 if type(InCombatLockdown) == 'function' and InCombatLockdown() then
  return false, 'Create/select the combat filter outside combat.'
 end
 local registry = getRegistry()
 if not registry then return false, 'Blizzard Combat Log unavailable. Open the Combat Log first.' end
 local selectFilter = _G.Blizzard_CombatLog_QuickButton_OnClick
 if type(selectFilter) ~= 'function' then
  return false, 'Blizzard Combat Log selection API unavailable; create the filter manually.'
 end
 local index = findFilter(registry)
 if not index then
  local preset, err = newPreset(registry)
  if not preset then return false, err end
  -- Prefer Blizzard's filter creation API when the client exposes it.
  -- The fallback mirrors its standard saved-filter table path and is not used
  -- automatically on loading or while in combat.
  local create = _G.CombatConfig_CreateCombatFilter
  if type(create) == 'function' then
   local ok = pcall(create, NAME, preset)
   if ok then index = findFilter(registry) end
  end
  if not index then
   local okay, problem = pcall(function()
    if #registry.filters >= 32 then error('Blizzard Combat Log filter limit reached') end
    table.insert(registry.filters, preset)
    index = #registry.filters
   end)
   if not okay then return false, 'Unable to create Blizzard Combat Log filter: '..tostring(problem) end
  end
 end
 local ok, err = pcall(selectFilter, index)
 if not ok then
  return false, 'Filter saved, but Blizzard could not select it: '..tostring(err)
 end
 local log = _G.COMBATLOG
 if log and type(_G.FCF_SelectDockFrame) == 'function' then
  pcall(_G.FCF_SelectDockFrame, log)
 end
 return true, 'ShaaenFCT filter selected (player + pet damage/misses).'
end
_G.ShaaenFCTCombatFilter = bridge
