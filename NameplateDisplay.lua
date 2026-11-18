-- ShaaenFCT nameplate-anchored floating text display.
-- Original implementation inspired by MSBT's separate display/animation layers.
-- No code from MSBT is copied. This module only manages visual anchors;
-- Core.lua remains responsible for attributing combat and animating numbers.
local ADDON = ...
local Display = {}
local host
local attached = setmetatable({}, {__mode='k'})
local recycled = {}
local stats = {created=0,attached=0,reused=0,removed=0,failed=0,current=0}

function Display:Configure(parent)
 host=parent
end

-- The frame is parented to a dedicated high-level overlay, NOT the nameplate.
-- Only its position is anchored to the nameplate. Thus Blizzard alpha/clipping
-- on the plate itself cannot hide an otherwise valid floating combat number.
-- No GetCenter/GetTop/secret coordinate arithmetic is needed for live plates.
function Display:Attach(plate)
 if not plate or not host then return nil end
 local existing=attached[plate]
 if existing then return existing end
 local frame=table.remove(recycled)
 if frame then stats.reused=stats.reused+1
 else
  frame=CreateFrame('Frame',nil,host)
  stats.created=stats.created+1
 end
 local ok=pcall(function()
  frame:Hide()
  frame:SetParent(host)
  frame:ClearAllPoints()
  frame:SetSize(1,1)
  frame:SetFrameStrata('HIGH')
  frame:SetFrameLevel(240)
  frame:SetPoint('CENTER',plate,'TOP',0,0)
  frame:SetAlpha(1)
  frame:Show()
 end)
 if not ok then
  frame:Hide()
  frame:ClearAllPoints()
  recycled[#recycled+1]=frame
  stats.failed=stats.failed+1
  return nil
 end
 attached[plate]=frame
 stats.attached=stats.attached+1
 stats.current=stats.current+1
 return frame
end

-- Called only AFTER Core has detached/released text on an old nameplate.
-- The same plate frame may later be recycled for another unit by Blizzard.
function Display:Forget(plate)
 local frame=attached[plate]
 if not frame then return end
 attached[plate]=nil
 frame:Hide()
 frame:ClearAllPoints()
 recycled[#recycled+1]=frame
 stats.removed=stats.removed+1
 stats.current=stats.current-1
end

function Display:Clear()
 for plate in pairs(attached) do self:Forget(plate) end
end

function Display:Statistics()
 return stats
end

_G.ShaaenFCTPlateDisplay=Display
